# Worklog: SEC-PAY — email-change revocation, store errors, COD-only payments

## Task and scope
- Task ID: SEC-PAY
- Item IDs covered: 1 (SEC-07c), 2 (BE-ERR), 3 (PAY-COD-ONLY)
- Allowed paths (lane from the task prompt): `services/auth-service/**`, `services/user-service/**`,
  `services/api-gateway/**` (not needed, untouched), `infrastructure/.env.example`,
  `infrastructure/staging/.env.staging.example`, `infrastructure/deploy/docker-compose.prod.yml` (one env line),
  `frontend/**` (item 3), `docs/worklog/SEC-PAY.md`
- Agent branch: agent/SEC-PAY-revoke-errors-cod, created from logic-exploitation (31f20aa1)

## Status
| Item | Status |
|---|---|
| 1 SEC-07c | done |
| 2 BE-ERR | done (non-money fixes); money-path swallowed errors listed below, not fixed (MONEY task) |
| 3 PAY-COD-ONLY | done (backend, env, frontend, read-only check) |

## Decisions taken

### Item 1 — SEC-07c (`ConfirmEmailChange`, `services/auth-service/internal/handlers/auth.go`)
- Order now: verify OTP (consumes the pending record, unchanged) → clash check → `RevokeAllUserTokens` →
  `UpdateEmail` → `reRevokeAfterPersist` (best effort, `EMAIL_CHANGE_REREVOKE_FAILED`) → wait for the next
  wall-clock second → mint the fresh token.
- Revoke failure: 503 `service_unavailable` + security event `EMAIL_CHANGE_REVOKE_FAILED`; email not changed.
  The pending change was already consumed by the OTP check (`FindOneAndDelete`), so it is put back best effort
  with `SetPendingEmailChange` (same OTP, original expiry kept) so the holder can retry the same code, matching
  SEC-07b's "reset token not consumed". If that restore fails the event detail says the user must request a new
  code. No `log.Printf` added (gosec G706 lesson from SEC-07b).
- Fresh token vs the `<=` rule: both revocations stamp a second ≤ now, and `GenerateToken` uses `time.Now()` for
  `iat` (no override without a `shared/infra/jwtutil` change, out of lane). So the handler waits until the wall
  clock enters the next second (`waitForNextSecond`, ctx-aware, ≤ 1 s) before minting. Proven necessary: with
  the wait removed, `TestConfirmEmailChange_RevokesOldSessions` failed 3/3 runs with
  `expected fresh token to be accepted, got: jwtutil: token has been revoked`. If the ctx is cancelled during
  the wait the email is already changed: response 503 "email updated, please sign in again".
- Existing tests updated: the three `email_change_test.go` tests now give jwtutil a Redis client (confirm needs
  it), and the lifecycle test uses the fresh token after confirm (the old one is now revoked, by design).

### Item 2 — BE-ERR (`services/user-service/internal/store/mongodb.go`)
- `CreateService` returns `error`: duplicate ID → `store.ErrServiceExists` (handler 409 `conflict`), anything else
  wrapped (handler 500 `internal_error`). Before: 201 "service created" with nothing written.
- `NewMongoDB` returns errors from `ensurePlatformConfig` and `ensureSeedData` (and disconnects). The code did
  not distinguish environments, so it now fails everywhere (task rule). Details:
  - platform config: a `FindOne` error other than `ErrNoDocuments` is returned (before: any error triggered an
    insert); a duplicate key on the config or the central wallet insert is treated as "another instance seeded
    it" and is not an error.
  - demo seed (`SEED_DEMO_DATA=true` only): `CountDocuments`, `InsertMany`, and each courier-location upsert
    error is returned.
- Other non-money fixes found by the grep:
  - `TryAcquireCourierLock` stale-lock self-heal ignored the `ReleaseCourierLock` error and the retry's
    `UpdateOne` error, reporting a DB failure as "courier busy" `(false, nil)`. Both are now returned.
  - `AdminActivateSubscription` replaced a non-duplicate insert error with "subscription not found or was
    concurrently modified", which the handler maps to 409. Now returned wrapped (500 path).
- Test fallout: `handlers_test.go` had two subtests seeding the same service ID `svc-deact-999`; the second
  insert used to fail silently. The second subtest now uses `svc-deact-998`. `mustCreateService` now just
  checks the returned error.

#### Swallowed store errors in `user-service/internal/store` (full list from the grep, base line numbers)
| Location (base) | What | Kind | Action |
|---|---|---|---|
| `mongodb.go:184-193` | platform config / central wallet seed inserts, only logged | non-money (startup) | fixed |
| `mongodb.go:203` | `CountDocuments` error discarded in demo seed | non-money | fixed |
| `mongodb.go:210` | demo `InsertMany` error only logged | non-money | fixed |
| `mongodb.go:235` | demo courier `UpsertEmployeeLocation` error discarded | non-money | fixed |
| `mongodb.go:249-253` | `CreateService` insert error only logged | non-money | fixed |
| `mongodb.go:2101-2105` | `TryAcquireCourierLock` self-heal release + retry errors discarded | non-money | fixed |
| `mongodb.go:1545-1549` | `AdminActivateSubscription` insert error replaced by a conflict message | non-money (billing state, no wallet) | fixed |
| `mongodb.go:921` | `GetOrCreateWallet` duplicate-key re-read ignores decode error (returns zero wallet) | money | listed only |
| `mongodb.go:979-985` | `Deposit` ledger `InsertOne` after the wallet `$inc`, only logged | money | listed only |
| `mongodb.go:1013-1020` | `LockEscrow` ledger `InsertOne` after the wallet update, only logged | money | listed only |
| `mongodb.go:1055,1079` | `ReleaseEscrowWithSplit` fallback compensation `UpdateOne`s, `_, _ =` | money | listed only |
| `mongodb.go:1212` | `RequestPayout` wallet revert after failed payout insert, `_, _ =` | money | listed only |
| `mongodb.go:1220-1231` | payout-request ledger `InsertOne`, only logged | money | listed only |
| `mongodb.go:1740,1788` | `RefundEscrow` fallback compensation `UpdateOne`s, `_, _ =` | money | listed only |
| `mongodb.go:1960-1967` | payout-reject `payout_refund` ledger `InsertOne`, only logged | money | listed only |
| `mongodb.go:2221-2223,2270-2272` | reconciliation note update after escrow already moved, only logged | money-adjacent (after funds moved; failing the request would invite a retry against a finished CAS) | listed only |
| `mongodb.go:320,327` | `ListServices` find/decode errors only logged (reads, not writes) | read | out of scope, listed |

### Item 3 — PAY-COD-ONLY
- **Existing flag found**: user-service already had an undocumented `ELECTRONIC_PAYMENTS_ENABLED` (default false)
  gating TrackJob's wallet path, passed by no compose file. Instead of a second flag with the same meaning,
  `DIGITAL_PAYMENTS_ENABLED` replaces it in `config.Config` (`DigitalPaymentsEnabled`); the old name is still
  read as a deprecated alias when the new one is unset (no silent behaviour change for an env that set it), and
  the two must agree when both are set. Values other than `true/false/1/0` fail `config.Load`, hence
  `--check-env`. Note: the deploy preflight runs `--check-env` with the whole `.env`, while the prod compose only
  passes `DIGITAL_PAYMENTS_ENABLED`; a stray `ELECTRONIC_PAYMENTS_ENABLED` in the prod `.env` is visible to the
  preflight but not to the running container.
- **Effective rule** (`UserService.digitalPaymentsAvailable`): `DIGITAL_PAYMENTS_ENABLED=true`, or the existing
  local/test bypass (`ALLOW_TEST_PAYMENT_BYPASS=true` with `APP_ENV` local/test; config already refuses the
  bypass in production). Kept so local, staging (`APP_ENV=local` + bypass) and the existing escrow test suite
  keep working. In production the flag alone decides.
- **Why production already rarely hit the "201 unfunded" path**: prod compose never passed
  `ELECTRONIC_PAYMENTS_ENABLED`, so TrackJob already returned 400 for `wallet` in production (old message, no
  stable code). `AcceptJobOffer` (~2102) and `RespondPrice` (~3848) do not create jobs: on escrow failure they
  already answer 400 `escrow_lock_failed`; they only act on jobs that already carry a non-COD method and were
  left unchanged ("do not modify existing jobs").
- **Endpoints gated when off** (400, body `{"error":"payment_method_unavailable","code":"payment_method_unavailable","message":...}`):
  - `POST /users/jobs/track` (TrackJob) — the only endpoint that sets a job's payment method (grep of
    `PaymentMethod` writes in handlers/store). Any non-empty method other than `cod` (incl. `card`, `WALLET`) is
    refused before validation and before any job is created. Empty still defaults to `cod`.
  - `POST /users/wallet/payout/request` (RequestPayout), checked first after the method check.
  - `POST /users/wallet/deposit`: unchanged local/test-only gate, as instructed.
  - When on, unknown methods keep the old `invalid payment_method` message, and the direct-assignment
    unfunded wallet job still gets today's 201 "escrow lock failed".
- **Exposure**: existing public `GET /users/platform/config` (user-service, owns the flag) now also returns
  `digital_payments_enabled`. No new endpoint. `docs/APPLICATION_MAP.md` lists that endpoint without a response
  schema, so nothing there went stale; it is out of lane anyway.
- **Frontend**: `OwnerProvider.fetchPaymentAvailability()` reads the field (false until fetched, false on any
  error, never touches `error`/`isLoading`). `WalletScreen` fetches it on first paint and on every refresh; the
  three entry points (deposit button, payout button, payout empty-state action) open their dialogs only when it
  is true, otherwise show a SnackBar with `digitalPaymentsComingSoon` (EN + AR, `flutter gen-l10n` run). No
  layout change, so no golden churn. The booking dialog was already hard-coded to COD only (Phase 4); it does not
  read the flag (adding a wallet option when true would be a new feature, not asked). A widget test now pins
  that it offers exactly one option. Existing jobs with other methods render through the unchanged job models.
- **Read-only check**: `store.CountUnfundedDigitalJobs` aggregates `jobs` with a non-empty, non-`cod`
  `payment_method`, no positive `locked_escrow_amount`, and no `escrow_lock` row in `transaction_ledger` for the
  job (`locked_escrow_amount` alone is not enough: completed/refunded jobs also end at 0), grouped by status.
  It never writes. Exposed as `service --count-unfunded-digital-jobs` (plain Mongo client: no index creation,
  no seeding, unlike `NewMongoDB`).

  Owner command for production (container name and binary path from `docker-compose.prod.yml` / the Dockerfile;
  NOT run against production by me):

  ```bash
  docker exec saas-user-service /bin/service --count-unfunded-digital-jobs
  ```

  Output is one JSON line, e.g. the local smoke run against an empty database printed
  `{"total":0,"by_status":{}}` (exit 0). Caveat: ledger inserts after escrow locks were only logged (see the
  money list above), so a job whose lock succeeded but whose ledger row failed and was later released would be
  counted as "never escrowed". Treat a non-zero count as "inspect these", not as proof.

## Changes per commit (message only — NO SHAs)
1. `SEC-PAY: SEC-07c email change revokes sessions first and fails closed`
2. `SEC-PAY: BE-ERR user-service store returns write errors instead of logging them`
3. `SEC-PAY: PAY-COD-ONLY digital payments flag, COD-only by default`
4. `SEC-PAY: worklog` (this file, alone)

## Verification

### Regression proof (each test run against the code before its fix)
Method: item 1 — base `auth.go` restored, new tests run. Item 2 — base `mongodb.go`/`services_handlers.go` with
only a compile shim (`CreateService` returns a constant `nil` after logging; `ErrServiceExists` declared). Item 3
— base config/handlers with `ElectronicPaymentsEnabled` renamed to `DigitalPaymentsEnabled` (pure rename, same
semantics); frontend — base `wallet_screen.dart` and `owner_provider.dart` restored.

| Test | Failed before fix? |
|---|---|
| `TestConfirmEmailChange_RevokesOldSessions` | yes (`expected pre-change confirming session token to be rejected after email change, got: <nil>`) |
| `TestConfirmEmailChange_RevokeFailure_FailsClosed` | yes (`expected 503, got 200`) |
| `TestCreateService_InsertFailure_ReturnsError` (store) | yes (`expected ErrServiceExists for a duplicate ID, got <nil>`; `expected an error when the insert is rejected, got nil`) |
| `TestCreateService_StoreFailure_Returns500` (handler) | yes (`expected 500 when the insert fails, got 201`) |
| `TestNewMongoDB_PlatformConfigSeedFailure_ReturnsError` | yes (`got nil`) |
| `TestNewMongoDB_PlatformWalletSeedFailure_ReturnsError` | yes (`got nil`) |
| `TestNewMongoDB_DemoSeedFailure_ReturnsError` | yes (`got nil`) |
| `TestNewMongoDB_SeedIsIdempotent` | no (guard: restarting on a seeded DB must still succeed) |
| `TestTryAcquireCourierLock_RetryError_IsReturned` | yes (`got ok=false err=<nil>`) |
| `TestAdminActivateSubscription_InsertError_KeepsCause` | yes (`insert failure must not be reported as a conflict`) |
| `TestLoad_DigitalPaymentsEnabled` | yes (true/1/alias cases false; conflict and invalid value not rejected) |
| `TestTrackJob_DigitalPaymentsOff_OnlyCOD` | yes (no stable code; `card`/`instapay` got `invalid payment_method`) |
| `TestTrackJob_DigitalPaymentsOn_KeepsWalletFlow` | no (guard: "true keeps today's behaviour") |
| `TestRequestPayout_DigitalPaymentsFlag` | yes (`expected 400, got 201`) |
| `TestGetPlatformConfig_ExposesDigitalPaymentsFlag` | yes (`digital_payments_enabled` absent) |
| `TestCountUnfundedDigitalJobs` | n/a (new read-only function) |
| `wallet_digital_payments_test.dart` flag false / flag absent / fetch fails / Arabic | yes, all 4 (Dialog opened; no coming-soon text) |
| `wallet_digital_payments_test.dart` flag true | no (guard) |
| `customer_marketplace_screen_test.dart` "BookingDialog offers only cash on delivery" | no (booking was already COD-only; pins it) |

### Gates
- `make check` before each commit 1–3 exited 0. Item 3 run (local) ended:

  ```
  [timing] total 345.3s
  == pre-push gate: all checks passed (scope: go=services/auth-service,services/user-service contracts docs docgen frontend compose=local,staging,prod) ==
  gate stamp written: /home/omarmaarouf/CS tools/Antigravity/SaaS prototype/.git/gate-stamps/98f92fa2e2... (scope: go=services/auth-service,services/user-service contracts docs docgen frontend compose=local,staging,prod)
  ```

  The stamp file name is a 40-hex digest; it is truncated here (`98f92fa2e2...`) so it is not read as a commit
  citation. Everything else is the literal captured text.
- The first item-2 `make check` FAILED (`BLOCKED: services/user-service failed test`,
  `handlers_test.go:1516: seed CreateService "svc-deact-999": store: service already exists`); fixed before
  committing (see item 2 test fallout). Nothing was committed on a failing gate.
- `flutter analyze lib`: `No issues found!`. `gofmt -l .` empty in both services.
- CLI smoke (local, empty DB): `go run ./cmd --count-unfunded-digital-jobs` printed `{"total":0,"by_status":{}}`, exit 0.

### Literal: `git log --oneline logic-exploitation..HEAD` (before this worklog commit)
```
8ccce27e SEC-PAY: PAY-COD-ONLY digital payments flag, COD-only by default
205f995e SEC-PAY: BE-ERR user-service store returns write errors instead of logging them
e4af199b SEC-PAY: SEC-07c email change revokes sessions first and fails closed
```

### Literal: `git diff --stat logic-exploitation..HEAD | tail -5` (before this worklog commit)
```
 services/user-service/internal/store/mongodb.go    | 101 ++++++---
 .../user-service/internal/store/mongodb_test.go    |   6 +-
 .../internal/store/unfunded_digital_jobs.go        |  92 ++++++++
 .../internal/store/unfunded_digital_jobs_test.go   |  50 +++++
 33 files changed, 1417 insertions(+), 113 deletions(-)
```

## Owner actions
- Production `.env`: add `DIGITAL_PAYMENTS_ENABLED=false` (the compose line defaults to false if it is absent,
  so this is for explicitness). Remove `ELECTRONIC_PAYMENTS_ENABLED` from any `.env` if present: if it disagrees
  with the new variable, `--check-env` fails the deploy preflight by design.
- Run the read-only count once in production (command above) and decide what to do with any jobs it reports.
- Fold into shared docs: AI_CONTEXT "Deferred by decision → Payments" (new variable name, payouts now also
  gated, `digital_payments_enabled` on platform config), the open "Backend changes the client has not been
  checked against" list (email change now revokes other sessions; confirm can take up to ~1 s).

## Unverified
- Real Redis outage behaviour (failure injected with go-redis hooks on miniredis, as in SEC-07b).
- The app's handling of the email-change response was not exercised end to end: the client must replace its
  stored token with the returned one, otherwise it is logged out after a confirm (all older tokens are revoked).
  I did not check `email_change_dialog.dart` beyond noticing it exists.
- `--count-unfunded-digital-jobs` was only run locally against an empty database and through the store test;
  not run in production, not run inside the container image.
- Staging/local compose files do not pass `DIGITAL_PAYMENTS_ENABLED` (out of lane); they rely on the
  local/test bypass, so behaviour there is unchanged. Not verified on a running staging stack.
- Golden screenshots were not regenerated (no layout change intended); the full flutter suite in `make check`
  passed, which includes `golden_screens_test.dart` comparisons.

## Follow-ups / out-of-lane findings
- MONEY task: the money-path swallowed errors listed in the item 2 table.
- `GetAndConsumePendingEmailChange` deletes the pending record before checking the OTP, so one wrong code
  burns the pending change (user must request a new code). Pre-existing, not changed here.
- `docs/APPLICATION_MAP.md`: `GET /users/platform/config` could mention `digital_payments_enabled`, and
  `infrastructure/docker-compose.yml` / `infrastructure/staging/docker-compose.staging.yml` could pass the
  variable explicitly. Both out of lane.
- If a wallet option is ever wanted in the booking dialog, it should read `digital_payments_enabled` the same
  way the wallet screen does.

## Open questions
- none
