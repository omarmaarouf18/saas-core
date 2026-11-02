# Worklog: BE-HARDEN — backend hardening follow-ups

## Task and scope
- Task ID: BE-HARDEN
- Item IDs covered: 1, 2, 3, 4, 5, 6, 7
- Allowed paths (lane from the task prompt):
  - `services/api-gateway/**`
  - `services/notification-service/**`
  - `services/user-service/**`
  - `services/auth-service/**` (only what items 3, 5 and 7 need)
  - `shared/infra/resilience/**` and `shared/infra/ratelimit/**` (hot paths owned by this task)
  - `scripts/staging_up.sh`
  - `tests/contracts/**`, `tests/e2e/**`
  - `docs/api/**`, `docs/APPLICATION_MAP.md` (regenerated with `make docs` only),
    `docs/worklog/BE-HARDEN.md`
- Agent branch: `agent/BE-HARDEN-backend-hardening`, created from `logic-exploitation`
  (base commit `2263a516`, short SHA only — no full SHAs on agent branches).
- Out of lane and untouched: `frontend/**`, `infrastructure/**`, `.github/**`,
  `Makefile`, every `go.mod`/`go.sum`, `go.work`, `.githooks/**`, the other repos,
  and everything under `shared/infra/` except `resilience/` and `ratelimit/`.

## Decisions taken
- **Item 1**: the passthrough is an opt-in `resilience.Option`
  (`resilience.WithUpstream5xxPassthrough()`) on `NewClient` and
  `NewRoundTripper`; only the api-gateway proxy transport
  (`services/api-gateway/cmd/main.go`) enables it. The upstream 5xx still
  travels through the circuit breaker as a failure (the breaker closure
  returns a typed `*upstream5xxError`), the retry policy is untouched, and
  only the response of the *last* attempt is handed to the caller with a nil
  error. The error message stays exactly `HTTP status N`, because
  chat-service parses it with `upstreamStatusPattern`
  (`services/chat-service/internal/handlers/admin_tickets.go:244`) and
  chat-service is outside this task's lane.
- **Item 1**: the proxy `ErrorHandler` now only sees real transport errors
  (dial, timeout, open breaker) and keeps its existing 502 answer and body.
  The `Sscanf` branch and the `/photo` special case are gone.
- **Item 2**: the rate limiter gained `CheckAndRecordDetailed` plus the
  sentinel `ratelimit.ErrNoRedisClient`. A limiter without a Redis client
  fails closed (deny) instead of panicking; `CheckAndRecord` keeps its old
  signature and its old answers for every existing caller, so only the
  notification-service sees the new `error` and answers 503 with the stable
  code `service_unavailable`. A plain rate-limit hit and a Redis error keep
  their historical 429 answer. The notification-service now holds the
  `*ratelimit.RateLimiter` directly (instead of the `handlerutil` wrapper)
  so it can tell "rate limited" from "the limiter could not run".
- **Item 2**: `cmd/main.go` keeps the MongoDB store in a `store.Store`
  variable that stays nil when MongoDB is unreachable — a typed nil
  `*store.MongoDB` would make the interface non-nil and the first
  `InsertNotification` would panic on the nil receiver. Every store access
  in the handlers additionally goes through `storeUsable`, which rejects a
  typed nil, so persistence is skipped and the notification is still
  delivered live and over push. The "persistence is unavailable" notice is
  logged once.
- **Item 3**: the provider is a new internal endpoint
  `POST /auth/internal/device-token/unregister` in the auth-service
  (`services/auth-service/internal/handlers/internal_device_token.go`).
  It authenticates the caller with the `X-Internal-Token` header
  (constant-time comparison, like the other `/auth/internal/*` endpoints),
  takes `{"token":"..."}`, answers `204` (idempotent: a token nobody holds
  any more still answers 204), `400` for an empty/blank/oversized token
  (> 512 characters) and `401` without a valid internal token. The token is
  removed from *every* user that holds it
  (`store.RemoveDeviceTokenFromAnyUser`, an `$pull` over all user records),
  because the notification-service knows the token but not necessarily the
  account that still owns it. The token itself is never logged in full —
  only `redact.PreviewToken(token)` (the first 10 characters) is.
- **Item 3**: the store dependency of the endpoint is the narrow interface
  `handlers.DeviceTokenUnregisterStore`, not the concrete `*store.MongoDB`,
  so the handler can be tested without a database. `Auth` keeps it in its
  own `deviceTokenStore` field, and `NewAuth` only wires it when the Mongo
  store exists — a typed nil (`(*store.MongoDB)(nil)`) would make the
  interface non-nil and the first call would panic. Without a store the
  endpoint answers `503 service_unavailable` instead of crashing.
- **Item 3**: the consumer (`services/notification-service/internal/hub/fetcher.go`)
  now posts `{"token":"..."}` to the new endpoint and treats every
  non-2xx answer as an error. The old code posted to `/auth/device-token`
  (which authenticates the caller with a *user JWT*, so the
  `X-Internal-Token`-only caller was always answered with 401) and ignored
  the status code, so a refused cleanup looked successful and the stale
  token kept failing every following push. `hub.go` now logs the cleanup
  failure instead of discarding it.
- **Item 3**: the contract test stays in the repo's existing AST style
  (`tests/contracts/notif_auth_contract_test.go`): the service modules are
  not importable from `tests/contracts` (Go's `internal` rule) and the
  repository has no cross-service module dependencies, so the contract test
  verifies that both sides agree on the route, the method, the header and
  the body field, while the behaviour itself is covered by the real handler
  (auth-service module) and the real consumer (notification-service module).
  The obsolete contract for the old `{"token":...,"action":"unregister"}`
  payload was replaced.
- **Item 4**: the admin job **list** (`GET /admin/jobs`) now returns the
  recipient phone masked; the unmasked phone stays in the job **detail** view
  (`GET /admin/jobs/{id}`), which is the audited `job.view` path. The mask
  keeps the first three characters (the country code, e.g. `+20`) and the
  last three digits and replaces everything in between with `•`
  (`+201011112222` → `+20•••••••222`); a value of six characters or less is
  masked completely, so nothing identifying leaks. The helper (`maskPhone`,
  `maskedRecipient`) lives in the user-service
  (`services/user-service/internal/handlers/admin_mask.go`) and not in
  `shared/infra/redact`, which is for secrets and tokens.
- **Item 4**: the list masks a **copy** of the recipient
  (`maskedRecipient`), so the stored job is never modified. The `phone`
  query parameter still matches the stored phone exactly — the lookup happens
  server-side, so the reviewer does not need the unmasked number in the
  response.
- **Item 4**: the `job.search` admin audit record is kept (a listing that
  carries recipient contact data stays auditable), but its details now say
  `masked_phone_jobs=...` instead of `unmasked_phone_jobs=...`. The
  `docs/api/ADMIN_API.md` PII section, the list example and the audit table
  were updated accordingly.
- **Item 5**: the six user-service admin handlers that answered a store
  failure with `"failed to ...: " + err.Error()` now use
  `handlerutil.WriteSafeError`: the store error is logged server-side
  (together with a request id) and the client gets the stable sanitized body
  `{"error": "<stable message>", "code": "internal_error", "request_id": "…"}`.
  The affected endpoints are `GET /admin/services`,
  `POST /admin/services/{id}/hide`, `POST /admin/services/{id}/unhide`,
  `POST /admin/services/{id}/photo/remove`,
  `POST /admin/jobs/{id}/cancel` and
  `POST /admin/jobs/{id}/complete-stuck-cod`.
- **Item 5**: the curated client answers were left alone: the `404`
  ("job not found", "service not found") and `409` (state conflict) bodies
  are intentional business messages, not store internals. The customer and
  owner job-cancellation path was already sanitized by
  `writeCancellationError` (A3) and needed no change.
- **Item 5**: the regression guard is twofold: a behavioural test that closes
  the Mongo client and checks that the four admin service endpoints answer
  with the sanitized body (no "mongo", "store: ", "client is disconnected",
  … in the response), and an AST guard over the `admin_*.go` files of the
  package that fails when a `500` body is built from `err.Error()` — the
  guard covers the two job endpoints whose store failure cannot be forced
  in a test (their first store call is the job lookup).
- **Item 6**: `scripts/staging_up.sh` now registers the staging secrets as
  GitHub Actions log masks (`::add-mask::<value>`) before anything can print
  them. The leak vector is real: `docker compose … config` interpolates the
  env file into the compose model and dumps it — the validation fallback
  prints the whole model when the validation fails, and a local
  reproduction shows 15 secret-bearing lines in that dump. The runner
  redacts a value from the workflow log only after it was registered with
  `::add-mask::`, so the registration has to happen *before* the compose
  validation.
- **Item 6**: the masking is a **no-op outside GitHub Actions**
  (`GITHUB_ACTIONS=true` is required). Printing `::add-mask::<secret>` on a
  developer machine would put the secret into the terminal transcript
  instead of hiding it, so the helper stays silent when the variable is not
  set. An empty value and an unreplaced `CHANGE_ME…` placeholder are
  skipped as well: GitHub rejects an empty mask, and masking a placeholder
  would redact the placeholder text everywhere it appears.
- **Item 6**: the secrets are registered from two places. (1) At creation:
  every value the script generates (`MONGO_PASS`, `REDIS_PASS` and the
  per-line passwords/keys) is registered as soon as it is generated, before
  it is written into the env file. (2) After the env file exists: the
  secret keys of the file are read back and registered, which also covers a
  **pre-existing** `.env.staging` (the release gate runner may have one, and
  the script never rewrites it). The key list covers the Mongo/Redis
  passwords and URIs, `JWT_SECRET`, `GATEWAY_SECRET`,
  `INTERNAL_SERVICE_TOKEN`, `ADMIN_API_TOKEN`, `OTP_AES_KEY`,
  `DOCUMENT_SIGNING_SECRET`, `DOCUMENT_ENCRYPTION_KEY`, `RESEND_API_KEY`
  and `FCM_SERVICE_ACCOUNT_JSON_B64`.
- **Item 6**: the env file is read line by line instead of being sourced,
  so a value is never expanded or evaluated; an inline comment
  (`KEY=value # comment`) is stripped the way the compose env-file parser
  strips it, so a comment is never mistaken for a secret. The mask commands
  are written to the original stdout (file descriptor 3), because the
  creation loop redirects its stdout into the env file — without that, the
  `::add-mask::` lines would land *inside* the env file.
- **Item 6**: the same value is registered only once (a small in-script
  list), and the `.env.staging.example` comment lines also carry the
  placeholder text (`#   - CHANGE_ME_64_HEX: …`), so the pre-existing
  substitution puts two more generated values into the env file. Those two
  are masked as well — they are real literals of the env file, even though
  they only appear inside a comment.
- **Item 7**: the `DOCUMENT_ENCRYPTION_KEY` published in
  `infrastructure/.env.example` (line 108, the `deadbeef…` value) is a
  syntactically valid AES-256 key, so it passes every format check the
  services do today — but it is public in the repository, so every document
  encrypted with it can be decrypted by anyone. Both the user-service and
  the auth-service now refuse to start when `DOCUMENT_ENCRYPTION_KEY` is
  that value and `APP_ENV` is not `local`/`test`. The refusal is a hard
  config error, so it also fails the CD pre-flight (`--check-env`).
- **Item 7**: `APP_ENV` is compared **trimmed and case-insensitively**
  (`local`, `test` — in any case, with any surrounding whitespace). An unset
  `APP_ENV` means `production` in both services, so it is refused as well.
  The local dev stack is not affected: `infrastructure/.env.example` ships
  `APP_ENV=local` together with the dev key, and the staging example uses
  `CHANGE_ME_64_HEX` (a random key) — so only a deployment that copied the
  example file into a production-shaped environment is refused.
- **Item 7**: the error names the variable (`DOCUMENT_ENCRYPTION_KEY`) but
  never the key value — the same rule the existing
  `ValidateDocumentEncryptionKey` follows. The published value itself is
  kept in one unexported constant per service (the two services are
  separate Go modules and no `go.mod` may be touched by this task, so the
  constant cannot be shared).
- **Item 7**: each service has its own test. The test repeats the published
  value as a literal on purpose — it has to pin the *published* value, not
  the constant of the package, so a drifting blocklist fails the test.
  The test also checks that the error names the variable and does not leak
  the key.

## Changes per commit (message only — NO SHAs)
1. `BE-HARDEN: item 1 - gateway passes upstream 5xx through unchanged`
2. `BE-HARDEN: item 2 - notification-service survives missing Redis and Mongo`
3. `BE-HARDEN: item 3 - internal device-token unregister endpoint`
4. `BE-HARDEN: item 4 - mask phones in the admin job list`
5. `BE-HARDEN: item 5 - admin 500s no longer leak store errors`
6. `BE-HARDEN: item 6 - mask CI secrets in staging_up.sh`
7. `BE-HARDEN: item 7 - refuse the dev DOCUMENT_ENCRYPTION_KEY outside local/test`

## Verification

### Item 3 — internal device-token unregister endpoint

**Fails before the change** (the implementation files were temporarily
reverted to `logic-exploitation` while the new tests stayed in place):

```
$ (cd tests/contracts && go test -count=1 -run 'TestContract_NotifToAuth_UnregisterStaleToken' -v ./...)
=== RUN   TestContract_NotifToAuth_UnregisterStaleToken
=== RUN   TestContract_NotifToAuth_UnregisterStaleToken/Provider_registers_the_internal_unregister_route
    notif_auth_contract_test.go:133: auth-service does not register /auth/internal/device-token/unregister
=== RUN   TestContract_NotifToAuth_UnregisterStaleToken/Consumer_posts_the_token_to_the_provider_route
    notif_auth_contract_test.go:167: expected the consumer to call /auth/internal/device-token/unregister, literals: [%s/auth/device-token `{"token":%q,"action":"unregister"}` POST Content-Type application/json X-Internal-Token]
    notif_auth_contract_test.go:173: expected the consumer to send the token field, literals: [%s/auth/device-token `{"token":%q,"action":"unregister"}` POST Content-Type application/json X-Internal-Token]
    notif_auth_contract_test.go:177: expected the consumer to use POST, selectors: [Sprintf authServiceURL NewReader Sprintf NewRequestWithContext Set Header Set Header internalServiceToken Do resilienceClient Close Body]
--- FAIL: TestContract_NotifToAuth_UnregisterStaleToken (0.00s)
    --- FAIL: TestContract_NotifToAuth_UnregisterStaleToken/Provider_registers_the_internal_unregister_route (0.00s)
    --- FAIL: TestContract_NotifToAuth_UnregisterStaleToken/Provider_requires_the_internal_token_and_only_accepts_POST (0.00s)
    --- FAIL: TestContract_NotifToAuth_UnregisterStaleToken/Consumer_posts_the_token_to_the_provider_route (0.00s)
    --- FAIL: TestContract_NotifToAuth_UnregisterStaleToken/Strict_Round-Trip:_Provider_Deserialization_of_Unregister_Payload (0.00s)
FAIL
FAIL	github.com/project/tests/contracts	0.007s
```

```
$ (cd services/notification-service && go test ./internal/hub/ -count=1 -run 'TestHTTPDeviceTokenFetcher_UnregisterStaleToken' -v)
=== RUN   TestHTTPDeviceTokenFetcher_UnregisterStaleToken_PostsToInternalEndpoint
    fetcher_test.go:41: expected the cleanup to POST to /auth/internal/device-token/unregister, got "/auth/device-token"
--- FAIL: TestHTTPDeviceTokenFetcher_UnregisterStaleToken_PostsToInternalEndpoint (0.00s)
=== RUN   TestHTTPDeviceTokenFetcher_UnregisterStaleToken_ReportsRejectedCleanup
    fetcher_test.go:68: expected an error when auth-service rejects the cleanup, got nil
--- FAIL: TestHTTPDeviceTokenFetcher_UnregisterStaleToken_ReportsRejectedCleanup (0.00s)
FAIL
FAIL	github.com/project/notification-service/internal/hub	0.003s
```

```
$ (cd services/auth-service && go test ./internal/handlers/ -count=1)
internal/handlers/internal_device_token_test.go:71:5: a.UnregisterStaleDeviceToken undefined (type *Auth has no field or method UnregisterStaleDeviceToken)
internal/handlers/internal_device_token_test.go:105:6: a.UnregisterStaleDeviceToken undefined (type *Auth has no field or method UnregisterStaleDeviceToken)
internal/handlers/internal_device_token_test.go:127:4: a.UnregisterStaleDeviceToken undefined (type *Auth has no field or method UnregisterStaleDeviceToken)
internal/handlers/internal_device_token_test.go:146:56: undefined: maxDeviceTokenLength
internal/handlers/internal_device_token_test.go:159:6: a.UnregisterStaleDeviceToken undefined (type *Auth has no field or method UnregisterStaleDeviceToken)
internal/handlers/internal_device_token_test.go:182:4: a.UnregisterStaleDeviceToken undefined (type *Auth has no field or method UnregisterStaleDeviceToken)
internal/handlers/internal_device_token_test.go:202:4: a.UnregisterStaleDeviceToken undefined (type *Auth has no field or method UnregisterStaleDeviceToken)
internal/handlers/internal_device_token_test.go:202:4: too many errors
FAIL	github.com/project/auth-service/internal/handlers [build failed]
FAIL

$ (cd services/auth-service && go test ./internal/store/ -count=1 -run 'TestRemoveDeviceTokenFromAnyUser')
# github.com/project/auth-service/internal/store [github.com/project/auth-service/internal/store.test]
internal/store/device_token_unregister_test.go:42:20: s.RemoveDeviceTokenFromAnyUser undefined (type *MongoDB has no field or method RemoveDeviceTokenFromAnyUser)
internal/store/device_token_unregister_test.go:63:19: s.RemoveDeviceTokenFromAnyUser undefined (type *MongoDB has no field or method RemoveDeviceTokenFromAnyUser)
internal/store/device_token_unregister_test.go:84:17: s.RemoveDeviceTokenFromAnyUser undefined (type *MongoDB has no field or method RemoveDeviceTokenFromAnyUser)
FAIL	github.com/project/auth-service/internal/store [build failed]
FAIL
```

The bug the old consumer ran into, reproduced against the *base* auth-service
code (`internal_device_token_old_contract_test.go` only uses the pre-existing
handler, so it compiles and runs there):

```
$ (cd services/auth-service && go test ./internal/handlers/ -count=1 -run 'TestDeviceTokenEndpointRejectsInternalServiceCaller' -v)
=== RUN   TestDeviceTokenEndpointRejectsInternalServiceCaller
2026/11/02 09:23:03 [ERROR] 3a314f1b930e495f unauthorized POST /auth/device-token: missing or invalid authorization header, Bearer token required
--- PASS: TestDeviceTokenEndpointRejectsInternalServiceCaller (0.00s)
PASS
ok  	github.com/project/auth-service/internal/handlers	0.004s
```

**Passes after the change:**

```
$ (cd services/auth-service && go test ./internal/handlers/ -count=1 -run 'TestUnregisterStaleDeviceToken|TestRegisterRoutes_ExposesInternalDeviceTokenUnregister|TestDeviceTokenEndpointRejectsInternalServiceCaller')
ok  	github.com/project/auth-service/internal/handlers	0.006s

$ (cd services/auth-service && go test ./internal/store/ -count=1 -run 'TestRemoveDeviceTokenFromAnyUser' -v)
--- PASS: TestRemoveDeviceTokenFromAnyUser_RemovesTokenFromEveryHolder (0.61s)
--- PASS: TestRemoveDeviceTokenFromAnyUser_RejectsEmptyToken (0.61s)
PASS
ok  	github.com/project/auth-service/internal/store	1.224s

$ (cd services/notification-service && go test ./internal/hub/ -count=1 -run 'TestHTTPDeviceTokenFetcher' -v)
--- PASS: TestHTTPDeviceTokenFetcher_UnregisterStaleToken_PostsToInternalEndpoint (0.00s)
--- PASS: TestHTTPDeviceTokenFetcher_UnregisterStaleToken_ReportsRejectedCleanup (0.00s)
--- PASS: TestHTTPDeviceTokenFetcher_ReadsLocales (0.00s)
PASS
ok  	github.com/project/notification-service/internal/hub	0.004s

$ (cd tests/contracts && go test -count=1 -run 'TestContract_NotifToAuth_UnregisterStaleToken' -v ./...)
--- PASS: TestContract_NotifToAuth_UnregisterStaleToken (0.01s)
    --- PASS: TestContract_NotifToAuth_UnregisterStaleToken/Provider_registers_the_internal_unregister_route (0.00s)
    --- PASS: TestContract_NotifToAuth_UnregisterStaleToken/Provider_requires_the_internal_token_and_only_accepts_POST (0.00s)
    --- PASS: TestContract_NotifToAuth_UnregisterStaleToken/Consumer_posts_the_token_to_the_provider_route (0.00s)
    --- PASS: TestContract_NotifToAuth_UnregisterStaleToken/Strict_Round-Trip:_Provider_Deserialization_of_Unregister_Payload (0.00s)
PASS
ok  	github.com/project/tests/contracts	0.008s
```

### Item 4 — mask phones in the admin job list

```
$ (cd services/user-service && go test ./internal/handlers/ -count=1 -run 'TestMaskPhone|TestMaskedRecipient' -v)
--- PASS: TestMaskPhone (0.00s)
    --- PASS: TestMaskPhone/empty (0.00s)
    --- PASS: TestMaskPhone/blank (0.00s)
    --- PASS: TestMaskPhone/egyptian_mobile (0.00s)
    --- PASS: TestMaskPhone/egyptian_mobile_13_characters (0.00s)
    --- PASS: TestMaskPhone/local_trunk_form (0.00s)
    --- PASS: TestMaskPhone/too_short_to_keep_a_head_and_a_tail (0.00s)
--- PASS: TestMaskedRecipient_KeepsTheStoredRecipientUntouched (0.00s)
--- PASS: TestMaskedRecipient_HandlesTheEmptyCases (0.00s)
PASS
ok  	github.com/project/user-service/internal/handlers	0.006s

$ (cd services/user-service && MONGO_URI=... go test ./internal/handlers/ -count=1 -run 'TestAdminJobs|TestAdminAudit|TestMask')
ok  	github.com/project/user-service/internal/handlers	2.506s
```

### Item 5 — admin 500s no longer leak store errors

**Fails before the change** (the two admin handler files were temporarily
reverted to `logic-exploitation` while the new test stayed in place):

```
$ (cd services/user-service && MONGO_URI=... go test ./internal/handlers/ -count=1 -run 'TestAdminHandlers_StoreFailureDoesNotLeakTheStoreError' -v)
=== RUN   TestAdminHandlers_StoreFailureDoesNotLeakTheStoreError/list_services
    admin_error_leak_test.go:88: expected the code "internal_error", got body {"error":"failed to list services: store: count services: client is disconnected"}
    admin_error_leak_test.go:88: request_id missing/malformed in {"error":"failed to list services: store: count services: client is disconnected"}
    admin_error_leak_test.go:88: internal detail "client is disconnected" leaked in body {"error":"failed to list services: store: count services: client is disconnected"}
    admin_error_leak_test.go:88: internal detail "store: " leaked in body {"error":"failed to list services: store: count services: client is disconnected"}
=== RUN   TestAdminHandlers_StoreFailureDoesNotLeakTheStoreError/hide_service
    admin_error_leak_test.go:88: expected the code "internal_error", got body {"error":"failed to hide service: store: update service visibility: client is disconnected"}
...
--- FAIL: TestAdminHandlers_StoreFailureDoesNotLeakTheStoreError (0.62s)
FAIL
FAIL	github.com/project/user-service/internal/handlers	0.621s

$ (cd services/user-service && MONGO_URI=... go test ./internal/handlers/ -count=1 -run 'TestAdminHandlers_NoInternalServerErrorBodyCarriesTheStoreError' -v)
=== RUN   TestAdminHandlers_NoInternalServerErrorBodyCarriesTheStoreError
    admin_error_leak_test.go:163: admin_jobs_handlers.go: a 500 response body is built from err.Error() — use handlerutil.WriteSafeError instead
    admin_error_leak_test.go:163: admin_jobs_handlers.go: a 500 response body is built from err.Error() — use handlerutil.WriteSafeError instead
    admin_error_leak_test.go:163: admin_services_handlers.go: a 500 response body is built from err.Error() — use handlerutil.WriteSafeError instead
    admin_error_leak_test.go:163: admin_services_handlers.go: a 500 response body is built from err.Error() — use handlerutil.WriteSafeError instead
    admin_error_leak_test.go:163: admin_services_handlers.go: a 500 response body is built from err.Error() — use handlerutil.WriteSafeError instead
    admin_error_leak_test.go:163: admin_services_handlers.go: a 500 response body is built from err.Error() — use handlerutil.WriteSafeError instead
--- FAIL: TestAdminHandlers_NoInternalServerErrorBodyCarriesTheStoreError (0.00s)
FAIL
FAIL	github.com/project/user-service/internal/handlers	0.005s
```

**Passes after the change:**

```
$ (cd services/user-service && MONGO_URI=... go test ./internal/handlers/ -count=1 -run 'TestAdminHandlers_' -v)
=== RUN   TestAdminHandlers_StoreFailureDoesNotLeakTheStoreError
=== RUN   TestAdminHandlers_StoreFailureDoesNotLeakTheStoreError/list_services
=== RUN   TestAdminHandlers_StoreFailureDoesNotLeakTheStoreError/hide_service
=== RUN   TestAdminHandlers_StoreFailureDoesNotLeakTheStoreError/unhide_service
=== RUN   TestAdminHandlers_StoreFailureDoesNotLeakTheStoreError/remove_service_photo
--- PASS: TestAdminHandlers_StoreFailureDoesNotLeakTheStoreError (0.62s)
=== RUN   TestAdminHandlers_NoInternalServerErrorBodyCarriesTheStoreError
--- PASS: TestAdminHandlers_NoInternalServerErrorBodyCarriesTheStoreError (0.00s)
PASS
ok  	github.com/project/user-service/internal/handlers	0.623s
```

### Item 6 — mask CI secrets in staging_up.sh

The script test harness of this repo (`scripts/test_staging_up.sh` and
`scripts/run_script_tests.sh`) is **outside this task's lane**, so no test
was added there; the change is verified with a manual reproduction (the
runner lives in `/tmp/opencode/be-harden-item6-verify.sh`, it is not part of
the repository). The existing harness was still run to prove that the
change does not regress it.

> The secret values inside the `::add-mask::` lines below are written as
> `<redacted>`: the repository's md-sha gate rejects every 40-character hex
> string in a markdown file that is not an existing commit SHA
> (`docs/CI_CD_AND_HOOKS.md`), so the generated secrets cannot be pasted
> verbatim. Everything else — the command lines, the order, the counts and
> the check results — is the literal output.

```
$ bash /tmp/opencode/be-harden-item6-verify.sh
== Scenario 1: fresh .env.staging, GITHUB_ACTIONS=true ==
exit=0
--- stdout ---
== [STAGING] Validating Staging Environment ==
[STAGING] .env.staging not found, creating from .env.staging.example...
::add-mask::<redacted>            (MONGO_PASS, 32 hex)
::add-mask::<redacted>            (REDIS_PASS, 32 hex)
::add-mask::<redacted>            (generated key, 64 hex)
::add-mask::<redacted>            (generated key, 64 hex)
::add-mask::<redacted>            (generated key, 64 hex)
::add-mask::<redacted>            (generated key, 64 hex)
::add-mask::<redacted>            (generated key, 64 hex)
::add-mask::<redacted>            (generated key, 64 hex)
::add-mask::<redacted>            (generated key, 64 hex)
::add-mask::<redacted>            (generated key, 64 hex)
::add-mask::<redacted>            (generated key, 64 hex)
::add-mask::mongodb://staging_root:<redacted>@mongo:27017/?authSource=admin
::add-mask::redis://:<redacted>@redis:6379
--- stderr ---
mask commands emitted: 13
ok   every secret of the env file is registered as a mask
ok   the generated env file contains no mask command
ok   no secret is printed outside a ::add-mask:: command
ok   no duplicate mask command

== Scenario 2: pre-existing .env.staging, GITHUB_ACTIONS=true ==
exit=0
--- stdout ---
== [STAGING] Validating Staging Environment ==
::add-mask::preloadedpassword
::add-mask::mongodb://staging_root:preloadedpassword@mongo:27017/?authSource=admin
::add-mask::redis://:preloadedpassword@redis:6379
::add-mask::<redacted>            (the pre-loaded 64-hex key)
ok   the pre-existing env file is not rewritten
ok   every secret of the pre-existing env file is registered as a mask

== Scenario 3: no GitHub Actions (local run) ==
exit=0
--- stdout ---
== [STAGING] Validating Staging Environment ==
[STAGING] .env.staging not found, creating from .env.staging.example...
ok   a local run prints no ::add-mask:: command
ok   a local run prints no secret in clear text

== Scenario 4: the existing script regression test still passes ==
ok   .env.staging created when missing
ok   no CHANGE_ME_64_HEX in created .env.staging
ok   no CHANGE_ME_PASSWORD in created .env.staging
ok   all 7 secrets are valid 64-hex strings
ok   all generated 64-hex keys are unique
ok   Mongo URI password matches root password
ok   Redis URI password matches redis password
ok   .env.staging permissions are 600
ok   existing .env.staging is never overwritten
all staging_up environment provisioning checks passed
ok   scripts/test_staging_up.sh passes

all item 6 checks passed
```

The leak vector the masks protect, reproduced locally with the same env
file (the compose validation dump that the workflow log would print):

```
$ docker compose -f infrastructure/staging/docker-compose.staging.yml --env-file "$tmp/staging/.env.staging" config --quiet && echo "compose validation exit=0 (OK)"
compose validation exit=0 (OK)
$ docker compose -f infrastructure/staging/docker-compose.staging.yml --env-file "$tmp/staging/.env.staging" config | grep -c 'MONGO_INITDB_ROOT_PASSWORD\|REDIS_PASSWORD\|JWT_SECRET\|INTERNAL_SERVICE_TOKEN\|ADMIN_API_TOKEN'
15
```

Static checks:

```
$ bash -n scripts/staging_up.sh && shellcheck scripts/staging_up.sh && echo "syntax+shellcheck OK"
syntax+shellcheck OK
```

### Item 7 — refuse the dev DOCUMENT_ENCRYPTION_KEY outside local/test

> The published dev key itself is written as `deadbeef…` here: the
> repository's md-sha gate treats every 40-character hex string in a
> markdown file as a commit SHA and blocks the commit when it is not one.
> The full value is in `infrastructure/.env.example` (line 108) and in the
> two service configs.

**Fails before the change** (the two `config.go` files were temporarily
reverted to `logic-exploitation` while the new tests stayed in place):

```
$ (cd services/user-service && go test ./internal/config/ -count=1 -run 'TestLoad_RefusesPublishedDevDocumentEncryptionKey' -v)
=== RUN   TestLoad_RefusesPublishedDevDocumentEncryptionKey
=== RUN   TestLoad_RefusesPublishedDevDocumentEncryptionKey/refuses_
    config_test.go:226: APP_ENV="": expected Load to refuse the published dev key, got nil
=== RUN   TestLoad_RefusesPublishedDevDocumentEncryptionKey/refuses_production
    config_test.go:226: APP_ENV="production": expected Load to refuse the published dev key, got nil
=== RUN   TestLoad_RefusesPublishedDevDocumentEncryptionKey/refuses_PRODUCTION
    config_test.go:226: APP_ENV="PRODUCTION": expected Load to refuse the published dev key, got nil
=== RUN   TestLoad_RefusesPublishedDevDocumentEncryptionKey/refuses__production_
    config_test.go:226: APP_ENV=" production ": expected Load to refuse the published dev key, got nil
=== RUN   TestLoad_RefusesPublishedDevDocumentEncryptionKey/refuses_staging
    config_test.go:226: APP_ENV="staging": expected Load to refuse the published dev key, got nil
=== RUN   TestLoad_RefusesPublishedDevDocumentEncryptionKey/refuses_prod
    config_test.go:226: APP_ENV="prod": expected Load to refuse the published dev key, got nil
=== RUN   TestLoad_RefusesPublishedDevDocumentEncryptionKey/allows_local
=== RUN   TestLoad_RefusesPublishedDevDocumentEncryptionKey/allows_LOCAL
=== RUN   TestLoad_RefusesPublishedDevDocumentEncryptionKey/allows__local_
=== RUN   TestLoad_RefusesPublishedDevDocumentEncryptionKey/allows_test
=== RUN   TestLoad_RefusesPublishedDevDocumentEncryptionKey/allows_TEST
=== RUN   TestLoad_RefusesPublishedDevDocumentEncryptionKey/allows__test_
--- FAIL: TestLoad_RefusesPublishedDevDocumentEncryptionKey (0.00s)
    --- FAIL: TestLoad_RefusesPublishedDevDocumentEncryptionKey/refuses_ (0.00s)
    --- FAIL: TestLoad_RefusesPublishedDevDocumentEncryptionKey/refuses_production (0.00s)
    --- FAIL: TestLoad_RefusesPublishedDevDocumentEncryptionKey/refuses_PRODUCTION (0.00s)
    --- FAIL: TestLoad_RefusesPublishedDevDocumentEncryptionKey/refuses__production_ (0.00s)
    --- FAIL: TestLoad_RefusesPublishedDevDocumentEncryptionKey/refuses_staging (0.00s)
    --- FAIL: TestLoad_RefusesPublishedDevDocumentEncryptionKey/refuses_prod (0.00s)
    --- PASS: TestLoad_RefusesPublishedDevDocumentEncryptionKey/allows_local (0.00s)
    --- PASS: TestLoad_RefusesPublishedDevDocumentEncryptionKey/allows_LOCAL (0.00s)
    --- PASS: TestLoad_RefusesPublishedDevDocumentEncryptionKey/allows__local_ (0.00s)
    --- PASS: TestLoad_RefusesPublishedDevDocumentEncryptionKey/allows_test (0.00s)
    --- PASS: TestLoad_RefusesPublishedDevDocumentEncryptionKey/allows_TEST (0.00s)
    --- PASS: TestLoad_RefusesPublishedDevDocumentEncryptionKey/allows__test_ (0.00s)
FAIL
FAIL	github.com/project/user-service/internal/config	0.002s
FAIL
```

```
$ (cd services/auth-service && go test ./internal/config/ -count=1 -run 'TestLoad_RefusesPublishedDevDocumentEncryptionKey' -v)
=== RUN   TestLoad_RefusesPublishedDevDocumentEncryptionKey
=== RUN   TestLoad_RefusesPublishedDevDocumentEncryptionKey/refuses_
    config_test.go:282: APP_ENV="": expected Load to refuse the published dev key, got nil
=== RUN   TestLoad_RefusesPublishedDevDocumentEncryptionKey/refuses_production
    config_test.go:282: APP_ENV="production": expected Load to refuse the published dev key, got nil
=== RUN   TestLoad_RefusesPublishedDevDocumentEncryptionKey/refuses_PRODUCTION
    config_test.go:282: APP_ENV="PRODUCTION": expected Load to refuse the published dev key, got nil
=== RUN   TestLoad_RefusesPublishedDevDocumentEncryptionKey/refuses__production_
    config_test.go:282: APP_ENV=" production ": expected Load to refuse the published dev key, got nil
=== RUN   TestLoad_RefusesPublishedDevDocumentEncryptionKey/refuses_staging
    config_test.go:282: APP_ENV="staging": expected Load to refuse the published dev key, got nil
=== RUN   TestLoad_RefusesPublishedDevDocumentEncryptionKey/refuses_prod
    config_test.go:282: APP_ENV="prod": expected Load to refuse the published dev key, got nil
=== RUN   TestLoad_RefusesPublishedDevDocumentEncryptionKey/allows_local
=== RUN   TestLoad_RefusesPublishedDevDocumentEncryptionKey/allows_LOCAL
=== RUN   TestLoad_RefusesPublishedDevDocumentEncryptionKey/allows__local_
=== RUN   TestLoad_RefusesPublishedDevDocumentEncryptionKey/allows_test
=== RUN   TestLoad_RefusesPublishedDevDocumentEncryptionKey/allows_TEST
=== RUN   TestLoad_RefusesPublishedDevDocumentEncryptionKey/allows__test_
--- FAIL: TestLoad_RefusesPublishedDevDocumentEncryptionKey (0.00s)
    --- FAIL: TestLoad_RefusesPublishedDevDocumentEncryptionKey/refuses_ (0.00s)
    --- FAIL: TestLoad_RefusesPublishedDevDocumentEncryptionKey/refuses_production (0.00s)
    --- FAIL: TestLoad_RefusesPublishedDevDocumentEncryptionKey/refuses_PRODUCTION (0.00s)
    --- FAIL: TestLoad_RefusesPublishedDevDocumentEncryptionKey/refuses__production_ (0.00s)
    --- FAIL: TestLoad_RefusesPublishedDevDocumentEncryptionKey/refuses_staging (0.00s)
    --- FAIL: TestLoad_RefusesPublishedDevDocumentEncryptionKey/refuses_prod (0.00s)
    --- PASS: TestLoad_RefusesPublishedDevDocumentEncryptionKey/allows_local (0.00s)
    --- PASS: TestLoad_RefusesPublishedDevDocumentEncryptionKey/allows_LOCAL (0.00s)
    --- PASS: TestLoad_RefusesPublishedDevDocumentEncryptionKey/allows__local_ (0.00s)
    --- PASS: TestLoad_RefusesPublishedDevDocumentEncryptionKey/allows_test (0.00s)
    --- PASS: TestLoad_RefusesPublishedDevDocumentEncryptionKey/allows_TEST (0.00s)
    --- PASS: TestLoad_RefusesPublishedDevDocumentEncryptionKey/allows__test_ (0.00s)
FAIL
FAIL	github.com/project/auth-service/internal/config	0.001s
FAIL
```

**Passes after the change:**

```
$ (cd services/user-service && go test ./internal/config/ -count=1 -v -run 'TestLoad_RefusesPublishedDevDocumentEncryptionKey')
--- PASS: TestLoad_RefusesPublishedDevDocumentEncryptionKey (0.00s)
    --- PASS: TestLoad_RefusesPublishedDevDocumentEncryptionKey/refuses_ (0.00s)
    --- PASS: TestLoad_RefusesPublishedDevDocumentEncryptionKey/refuses_production (0.00s)
    --- PASS: TestLoad_RefusesPublishedDevDocumentEncryptionKey/refuses_PRODUCTION (0.00s)
    --- PASS: TestLoad_RefusesPublishedDevDocumentEncryptionKey/refuses__production_ (0.00s)
    --- PASS: TestLoad_RefusesPublishedDevDocumentEncryptionKey/refuses_staging (0.00s)
    --- PASS: TestLoad_RefusesPublishedDevDocumentEncryptionKey/refuses_prod (0.00s)
    --- PASS: TestLoad_RefusesPublishedDevDocumentEncryptionKey/allows_local (0.00s)
    --- PASS: TestLoad_RefusesPublishedDevDocumentEncryptionKey/allows_LOCAL (0.00s)
    --- PASS: TestLoad_RefusesPublishedDevDocumentEncryptionKey/allows__local_ (0.00s)
    --- PASS: TestLoad_RefusesPublishedDevDocumentEncryptionKey/allows_test (0.00s)
    --- PASS: TestLoad_RefusesPublishedDevDocumentEncryptionKey/allows_TEST (0.00s)
    --- PASS: TestLoad_RefusesPublishedDevDocumentEncryptionKey/allows__test_ (0.00s)
PASS
ok  	github.com/project/user-service/internal/config	0.001s

$ (cd services/auth-service && go test ./internal/config/ -count=1 -v -run 'TestLoad_RefusesPublishedDevDocumentEncryptionKey')
--- PASS: TestLoad_RefusesPublishedDevDocumentEncryptionKey (0.00s)
    --- PASS: TestLoad_RefusesPublishedDevDocumentEncryptionKey/refuses_ (0.00s)
    --- PASS: TestLoad_RefusesPublishedDevDocumentEncryptionKey/refuses_production (0.00s)
    --- PASS: TestLoad_RefusesPublishedDevDocumentEncryptionKey/refuses_PRODUCTION (0.00s)
    --- PASS: TestLoad_RefusesPublishedDevDocumentEncryptionKey/refuses__production_ (0.00s)
    --- PASS: TestLoad_RefusesPublishedDevDocumentEncryptionKey/refuses_staging (0.00s)
    --- PASS: TestLoad_RefusesPublishedDevDocumentEncryptionKey/refuses_prod (0.00s)
    --- PASS: TestLoad_RefusesPublishedDevDocumentEncryptionKey/allows_local (0.00s)
    --- PASS: TestLoad_RefusesPublishedDevDocumentEncryptionKey/allows_LOCAL (0.00s)
    --- PASS: TestLoad_RefusesPublishedDevDocumentEncryptionKey/allows__local_ (0.00s)
    --- PASS: TestLoad_RefusesPublishedDevDocumentEncryptionKey/allows_test (0.00s)
    --- PASS: TestLoad_RefusesPublishedDevDocumentEncryptionKey/allows_TEST (0.00s)
    --- PASS: TestLoad_RefusesPublishedDevDocumentEncryptionKey/allows__test_ (0.00s)
PASS
ok  	github.com/project/auth-service/internal/config	0.002s
```

End-to-end proof through the CD pre-flight (`--check-env`), with the
published dev key in the environment:

```
$ (cd services/user-service && env JWT_SECRET=… INTERNAL_SERVICE_TOKEN=… TLS_CERT_PATH=… TLS_KEY_PATH=… TLS_CA_PATH=… REDIS_URI=… APP_ENV=production DOCUMENT_ENCRYPTION_KEY=<the published dev key> go run ./cmd --check-env)
PREFLIGHT FAILED: config: refusing to start: DOCUMENT_ENCRYPTION_KEY is the published development key; generate a unique key (openssl rand -hex 32) before deploying outside local/test
exit status 1
user-service --check-env exit=1

$ (cd services/auth-service && env JWT_SECRET=… DOCUMENT_SIGNING_SECRET=… GATEWAY_SECRET=… INTERNAL_SERVICE_TOKEN=… TLS_CERT_PATH=… TLS_KEY_PATH=… TLS_CA_PATH=… REDIS_URI=… APP_ENV=production DOCUMENT_ENCRYPTION_KEY=<the published dev key> go run ./cmd --check-env)
PREFLIGHT FAILED: config: refusing to start: DOCUMENT_ENCRYPTION_KEY is the published development key; generate a unique key (openssl rand -hex 32) before deploying outside local/test
exit status 1
auth-service --check-env exit=1
```

The local development shape (the example file: `APP_ENV=local` + the dev
key) still starts:

```
$ (cd services/user-service && env … APP_ENV=local DOCUMENT_ENCRYPTION_KEY=<the published dev key> go run ./cmd --check-env)
PREFLIGHT OK: user-service config validated
user-service --check-env (APP_ENV=local) exit=0

$ (cd services/auth-service && env … APP_ENV=local DOCUMENT_ENCRYPTION_KEY=<the published dev key> go run ./cmd --check-env)
PREFLIGHT OK: auth-service config validated
auth-service --check-env (APP_ENV=local) exit=0
```

Static checks:

```
$ gofmt -l services/user-service/internal/config/ services/auth-service/internal/config/
(no output)
$ (cd services/user-service && go build ./... && go vet ./... && echo "user-service build+vet OK")
user-service build+vet OK
$ (cd services/auth-service && go build ./... && go vet ./... && echo "auth-service build+vet OK")
auth-service build+vet OK
$ GITLEAKS_BIN=… bash scripts/gitleaks-scan.sh worktree logic-exploitation
-- gitleaks: scanning 2263a516..HEAD + staged + unstaged + untracked --
gitleaks: no secrets found
```

- (filled in as the task progresses)

## Unverified
- (filled in as the task progresses)

## Follow-ups / out-of-lane findings
- (filled in as the task progresses)

## Open questions
- (filled in as the task progresses)
