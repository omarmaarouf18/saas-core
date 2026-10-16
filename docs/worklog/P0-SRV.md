# Worklog: P0-SRV — server-side Phase 0 fixes

## Deploy prerequisite (read first)

> **ADMIN_API_TOKEN must be added to the production and staging `.env` files
> BEFORE deploying this branch, or the gateway will refuse to start.**

- Which env files need it:
  - production `.env` used by `infrastructure/deploy/docker-compose.prod.yml`
  - `infrastructure/staging/.env.staging` used by `scripts/staging_up.sh`
  - local dev: the `infrastructure/.env` used by `infrastructure/docker-compose.yml`
- Generate the value with `openssl rand -hex 32` (64 hex chars); it must
  differ from `INTERNAL_SERVICE_TOKEN`.
- Failure mode if missing: docker compose refuses to interpolate the gateway
  service (`ADMIN_API_TOKEN is required`), and the gateway's own
  config.Load / `--check-env` fails closed with
  `config: required env var ADMIN_API_TOKEN is required and must not be empty`.
- Never paste the value into the repo, docs, or chat.

## Task and scope

- Task ID: P0-SRV
- Item IDs covered: SEC-01a, BE-20, BE-09 (stopped — see Open questions),
  SEC-07, SEC-03, SEC-02, OBS-01
- Allowed paths (lane from the task prompt): `services/api-gateway/**`,
  `services/auth-service/**`, user/chat/notification services (OBS-01 call
  sites only), `shared/infra/handlerutil/security_logs.go` + test,
  new `shared/infra/passwordpolicy/**`,
  `shared/infra/jwtutil/**` (SEC-07 only),
  `infrastructure/.env.example`,
  `infrastructure/staging/.env.staging.example`, `docs/worklog/P0-SRV.md`.
  Owner-granted SEC-02 lane extension: `infrastructure/docker-compose.yml`,
  `infrastructure/staging/docker-compose.staging.yml`,
  `infrastructure/deploy/docker-compose.prod.yml`,
  `tests/e2e/e2e_helpers.go`, `tests/e2e/contract_gateway_test.go`.
  Further owner-granted for the SEC-03 follow-up: `tests/e2e/cuj_c_test.go`.
- Agent branch: `agent/P0-SRV-cleanup`, created from `logic-exploitation`

## Decisions taken

- SEC-07: revoke-before-state-change plus an ownership precheck before
  revoking (prevents a foreign owner from triggering revocation). The
  jwtutil same-second bypass is fixed at second resolution (`<=`); this is
  fail-closed: a token issued in the same second as the freeze is also
  rejected (documented trade-off).
- SEC-03: minimum 8 runes, maximum 72 bytes (bcrypt), exact
  case-insensitive blocklist of common passwords. In ResetPassword the
  policy check runs after token verification and rate-limiter reset, so
  invalid tokens keep the generic 401 and a policy-rejected attempt does
  not consume the single-use token.
- SEC-02: `ADMIN_API_TOKEN` is a required env var (fail-closed). Both GET
  and PUT on `/api/v1/admin/version-config` require `X-Admin-Token`;
  `X-Internal-Token` is explicitly rejected there. `download_url` is
  validated in `version.Store.UpdateConfig` (https only, exact host
  `github.com` or `play.google.com`; lookalike hosts rejected) so it
  applies to every caller. Successful PUT ships a `VERSION_CONFIG_CHANGED`
  security event.
- SEC-02 owner conditions applied: compose uses
  `${ADMIN_API_TOKEN:?ADMIN_API_TOKEN is required}`; the prod compose change
  is only that one env line; e2e reads `ADMIN_API_TOKEN` from the
  environment with a clearly fake fallback (`CHANGE_ME_64_HEX`) matching
  `.env.staging.example`, which is what CI provisions from.
- SEC-02 fallout fix (in-lane): `tests/e2e/e2e_helpers.go` default Mongo/
  Redis credentials and JWT/internal tokens were still the old real values,
  which no longer match a stack provisioned from the SEC-01a placeholders
  (`staging_secret123` etc. are gone from the example). The defaults now
  use the same fake placeholders as `.env.staging.example`, removing the
  last hard-coded real secrets from the e2e helper and keeping the release
  gate green on a freshly provisioned stack.
- SEC-03 follow-up (own commit): `tests/e2e/cuj_c_test.go` asserted the old
  "at least 6 characters" message; aligned to "at least 8 characters".
- BE-09: skipped, not implemented — a production frontend caller exists
  (see Open questions). No code was changed for this item.
- OBS-01: `ShipSecurityEvent` signature unchanged (72 call sites untouched).
  Every event is now emitted synchronously as a structured slog JSON line
  on stdout regardless of CloudWatch state; CloudWatch shipping moved from
  one goroutine per event to a bounded queue (capacity 1000) drained by a
  single FIFO worker, with an atomic drop counter and a rate-limited drop
  warning. The pending item captures client/log group at enqueue time so
  the worker never reads the mutable `Cw*` globals (race-free under
  `-race`).

## Changes per commit (message only — NO SHAs)

1. `SEC-01a: replace real secrets in staging env example with placeholders`
2. `BE-20: return errors instead of log.Fatalf from ID/OTP generators`
3. `SEC-07: revoke employee sessions on freeze, fix same-second revocation bypass`
4. `SEC-03: shared password policy (min 8 runes, bcrypt 72-byte cap, common-password blocklist)`
5. `SEC-03 follow-up: align e2e CUJ-C with the 8-char password policy`
6. `SEC-02: gate version-config behind a dedicated admin token and validate download URLs`
7. `OBS-01: emit security events to stdout always and bound CloudWatch shipping`

## Verification

- `make ci` — PASS before every code commit on this branch (SEC-01a,
  BE-20, SEC-07, SEC-03, SEC-03 follow-up, SEC-02, OBS-01); every retained
  gate log ends with `All tests passed!` and
  `== pre-push gate: all checks passed ==`.
- `gofmt -l .` — empty for every module touched.
- `go build ./...`, `go vet ./...` — PASS for api-gateway, shared/infra,
  tests/e2e.
- SEC-07 regression proof: with the jwtutil fix reverted (`<` instead of
  `<=`), both new freeze/nonce tests failed as expected; restored, all
  auth-service packages pass.
- SEC-03 regression proof: pre-wire failures captured (weak passwords
  accepted; a 73-byte password returned 500 `failed to hash password`);
  after wiring, full auth-service + shared/infra suites pass.
- SEC-02 unit tests: api-gateway `go test ./...` PASS, including new
  subtests for admin-token lockdown (missing/wrong token 403,
  internal-token-only 403, unconfigured token 403), download_url allowlist
  (http, lookalike host, empty, disallowed host all 400) and PUT success on
  github.com / play.google.com URLs.
- SEC-02 compose gate, verified literally:
  - local and prod compose without the var: entrypoint error
    `required variable ADMIN_API_TOKEN is missing a value: ADMIN_API_TOKEN is required`;
  - staging compose with `.env.staging.example` (as CI provisions):
    `docker compose config -q` exit 0;
  - HEAD baseline comparison shows no ADMIN-related error existed before.
- SEC-02 end-to-end release-gate reproduction: `bash scripts/staging_up.sh`
  (stack up, gateway healthy) then `go test -v -count=1 ./tests/e2e/...` —
  exit 0, 22 top-level tests passed, 0 failed, final line
  `ok github.com/project/tests/e2e 8.162s`. This included the new
  contract subtests `GET_Admin_Version_Config`, `PUT_Admin_Version_Config`
  and the internal-token lockdown cases, all PASS.
- OBS-01: `go test -race ./handlerutil/...` PASS, including new tests for
  stdout emission (CloudWatch disabled and enabled) and bounded-queue drop
  counting.
- BE-20 regression proof: not obtainable — the generator refactor has no
  injectable reader in the pre-fix code, so the new failure-path tests
  cannot run against the old implementation (see Unverified).

## Unverified

- The GitHub release-gate workflow itself (`.github/workflows/release-gate-e2e.yml`)
  was not run on a GitHub runner; it was reproduced locally (same script +
  command) and passed. Runner-specific differences (image cache, timing)
  are not covered.
- CloudWatch `PutLogEvents` success path (OBS-01 / SEC-02 event shipping):
  no AWS credentials available; disabled-path, non-blocking behavior and
  queue semantics are tested, the successful ship path is code-path-only.
- BE-20 and OBS-01 pre-fix regression proofs (see above): the new tests
  intentionally reference new internals, so "failed before the fix" could
  not be demonstrated by running them against the old code. The behavioral
  gap is evident from the old implementations (silent `log.Fatalf` /
  return-before-emit).
- Local/prod compose `config -q` still exits non-zero without a full local
  `.env` (pre-existing `no port specified: :<empty>`); the ADMIN gate
  itself was verified via the controlled HEAD comparison above.

## Follow-ups / out-of-lane findings

- `docs/APPLICATION_MAP.md` and ADR-0018 still document
  `/api/v1/admin/version-config` as guarded by `X-Internal-Token`; they need
  an owner update to `X-Admin-Token` / `ADMIN_API_TOKEN`.
- Frontend still advertises the old 6-char minimum password rule
  (out of lane): `frontend/lib/l10n/app_en.arb:144,629,833`; generated
  `app_localizations.dart:908,2703,3261` and `app_localizations_en.dart:429,1427,1746`;
  validators `frontend/lib/screens/signup_screen.dart:246`,
  `employee_screen.dart:532`, `reset_password_new_screen.dart:182`
  (`email_change_dialog.dart:226` is OTP, not password).
- `tests/e2e/security_regression_test.go` (~line 459) has a stale comment
  "requires internal token" for the version-config RBAC check. Behavior is
  still correct (Bearer-only → 403); no change made (out of lane).
- `scripts/staging_up.sh` health gate waits only for the gateway and the
  console; `user-service` can still be starting and the e2e run immediately
  after provisioning once raced it (502s). Waiting for full readiness
  produced a stable green run. This could make the CI release gate
  timing-sensitive.
- One e2e run showed 429s in the RBAC matrices caused by reviewer
  rate-limiter state shared across back-to-back runs against the same
  Redis; a fresh Redis always passes. Not a code defect.

## Open questions

- BE-09 stop: the task asked to remove the production endpoint
  `POST /auth/employee/action` (employee self-deactivate), but it has a
  production frontend caller: `frontend/lib/providers/employee_jobs_provider.dart:58-79`
  used from `frontend/lib/screens/employee_jobs_screen.dart:152`, with
  tests in `frontend/test/employee_jobs_provider_test.dart:178,187,195` and
  `frontend/test/employee_jobs_screen_audit_test.dart:71`, handler tests in
  `services/auth-service/internal/handlers/account_suspension_test.go:248,264`,
  `audit_log_dto_test.go:136`, `auth_test.go:456,465,2849,2989,2998,3008`,
  and e2e coverage in `tests/e2e/contract_auth_test.go:835,914`. Question
  for the owner: keep the endpoint as-is (it is production behavior), or
  coordinate a frontend migration before removal? No code was changed for
  BE-09.
