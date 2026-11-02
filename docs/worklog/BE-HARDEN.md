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

### Item 1 — gateway passes upstream 5xx through unchanged

**Fails before the change** (the three implementation files were temporarily
reverted to `logic-exploitation` while the new tests stayed in place — the
new option does not exist there, so the packages do not even build):

```
$ (cd shared/infra && go test ./resilience/ -count=1 -run 'TestResilienceClient_Upstream5xx|TestResilienceRoundTripper_Upstream5xx')
# github.com/project/shared/infra/resilience [github.com/project/shared/infra/resilience.test]
resilience/resilience_test.go:488:3: undefined: WithUpstream5xxPassthrough
resilience/resilience_test.go:488:3: too many arguments in call to NewClient
	have (*http.Client, string, number, "time".Duration, unknown type)
	want (*http.Client, string, int, "time".Duration)
resilience/resilience_test.go:554:3: undefined: WithUpstream5xxPassthrough
resilience/resilience_test.go:554:3: too many arguments in call to NewRoundTripper
	have (http.RoundTripper, string, number, "time".Duration, unknown type)
	want (http.RoundTripper, string, int, "time".Duration)
FAIL	github.com/project/shared/infra/resilience [build failed]
FAIL

$ (cd services/api-gateway && go test ./internal/proxy/ -count=1 -run 'TestProxy_Upstream')
# github.com/project/gateway/internal/proxy [github.com/project/gateway/internal/proxy.test]
internal/proxy/proxy_test.go:586:3: too many arguments in call to resilience.NewRoundTripper
	have (http.RoundTripper, string, number, "time".Duration, unknown type)
	want (http.RoundTripper, string, int, "time".Duration)
internal/proxy/proxy_test.go:586:14: undefined: resilience.WithUpstream5xxPassthrough
internal/proxy/proxy_test.go:644:3: too many arguments in call to resilience.NewRoundTripper
	have (http.RoundTripper, string, number, "time".Duration, unknown type)
	want (http.RoundTripper, string, int, "time".Duration)
internal/proxy/proxy_test.go:644:14: undefined: resilience.WithUpstream5xxPassthrough
internal/proxy/proxy_test.go:698:3: too many arguments in call to resilience.NewRoundTripper
	have (http.RoundTripper, string, number, "time".Duration, unknown type)
	want (http.RoundTripper, string, int, "time".Duration)
internal/proxy/proxy_test.go:698:14: undefined: resilience.WithUpstream5xxPassthrough
FAIL	github.com/project/gateway/internal/proxy [build failed]
FAIL
```

**Passes after the change:**

```
$ (cd shared/infra && go test ./resilience/ -count=1 -v -run 'TestResilienceClient_Upstream5xx|TestResilienceRoundTripper_Upstream5xx')
=== RUN   TestResilienceClient_Upstream5xxPassthrough
--- PASS: TestResilienceClient_Upstream5xxPassthrough (0.00s)
=== RUN   TestResilienceClient_Upstream5xxWithoutPassthroughStillErrors
--- PASS: TestResilienceClient_Upstream5xxWithoutPassthroughStillErrors (0.00s)
=== RUN   TestResilienceRoundTripper_Upstream5xxPassthroughStillTripsBreaker
2026/11/02 13:21:52 [SECURITY EVENT / DOWNSTREAM DEGRADED] Circuit breaker test-passthrough-breaker transitioned from closed to open
--- PASS: TestResilienceRoundTripper_Upstream5xxPassthroughStillTripsBreaker (0.00s)
PASS
ok  	github.com/project/shared/infra/resilience	0.004s

$ (cd services/api-gateway && go test ./internal/proxy/ -count=1 -v -run 'TestProxy_Upstream')
=== RUN   TestProxy_Upstream503PhotoStorageUnavailable_PassesThroughAs503
--- PASS: TestProxy_Upstream503PhotoStorageUnavailable_PassesThroughAs503 (0.00s)
=== RUN   TestProxy_Upstream500BodyPassesThrough
--- PASS: TestProxy_Upstream500BodyPassesThrough (0.22s)
=== RUN   TestProxy_Upstream5xxStillOpensCircuitBreaker
2026/11/02 13:21:52 [SECURITY EVENT / DOWNSTREAM DEGRADED] Circuit breaker test-user-route-breaker transitioned from closed to open
2026/11/02 13:21:52 [PROXY ERROR] POST /users/jobs → http://127.0.0.1:34815: circuit breaker is open
--- PASS: TestProxy_Upstream5xxStillOpensCircuitBreaker (0.00s)
PASS
ok  	github.com/project/gateway/internal/proxy	0.226s
```

### Item 2 — notification-service survives missing Redis and Mongo

**Fails before the change** (the implementation files were temporarily
reverted to `logic-exploitation` while the new tests stayed in place — the
new sentinel and the new method do not exist there):

```
$ (cd shared/infra && go test ./ratelimit/ -count=1 -run 'TestRateLimiter_Nil|TestOtherLimiters_Nil')
# github.com/project/shared/infra/ratelimit [github.com/project/shared/infra/ratelimit.test]
ratelimit/nil_client_test.go:25:26: rl.CheckAndRecordDetailed undefined (type *RateLimiter has no field or method CheckAndRecordDetailed)
ratelimit/nil_client_test.go:32:21: undefined: ErrNoRedisClient
ratelimit/nil_client_test.go:40:24: rl.CheckAndRecordDetailed undefined (type *RateLimiter has no field or method CheckAndRecordDetailed)
ratelimit/nil_client_test.go:44:21: undefined: ErrNoRedisClient
FAIL	github.com/project/shared/infra/ratelimit [build failed]
FAIL

$ (cd services/notification-service && go test ./internal/handlers/ -count=1 -run 'TestSend_RateLimiterWithoutRedis|TestSend_TypedNilStore|TestStoreUsable')
# github.com/project/notification-service/internal/handlers [github.com/project/notification-service/internal/handlers.test]
internal/handlers/degraded_dependencies_test.go:121:5: undefined: storeUsable
internal/handlers/degraded_dependencies_test.go:125:5: undefined: storeUsable
FAIL	github.com/project/notification-service/internal/handlers [build failed]
FAIL
```

**Passes after the change:**

```
$ (cd shared/infra && go test ./ratelimit/ -count=1 -v -run 'TestRateLimiter_Nil|TestOtherLimiters_Nil')
=== RUN   TestRateLimiter_NilClientFailsClosed
2026/11/02 13:23:05 [SECURITY CRITICAL] Redis rate limiter unavailable (FAIL CLOSED): ratelimit: redis client is not available
2026/11/02 13:23:05 [SECURITY CRITICAL] Redis rate limiter unavailable (FAIL CLOSED): ratelimit: redis client is not available
--- PASS: TestRateLimiter_NilClientFailsClosed (0.00s)
=== RUN   TestRateLimiter_NilLimiterFailsClosed
2026/11/02 13:23:05 [SECURITY CRITICAL] Redis rate limiter unavailable (FAIL CLOSED): ratelimit: redis client is not available
--- PASS: TestRateLimiter_NilLimiterFailsClosed (0.00s)
=== RUN   TestOtherLimiters_NilClientDoesNotPanic
2026/11/02 13:23:05 [SECURITY CRITICAL] Redis auth rate limiter unavailable (FAIL CLOSED): ratelimit: redis client is not available
2026/11/02 13:23:05 [SECURITY CRITICAL] Redis auth rate limiter unavailable (FAIL CLOSED): ratelimit: redis client is not available
2026/11/02 13:23:05 [SECURITY CRITICAL] Redis reviewer rate limiter unavailable (FAIL CLOSED): ratelimit: redis client is not available
2026/11/02 13:23:05 [SECURITY CRITICAL] Redis reviewer rate limiter unavailable (FAIL CLOSED): ratelimit: redis client is not available
--- PASS: TestOtherLimiters_NilClientDoesNotPanic (0.00s)
PASS
ok  	github.com/project/shared/infra/ratelimit	0.003s

$ (cd services/notification-service && go test ./internal/handlers/ -count=1 -v -run 'TestSend_RateLimiterWithoutRedis|TestSend_TypedNilStore|TestStoreUsable')
=== RUN   TestSend_RateLimiterWithoutRedis_FailsClosedWith503
2026/11/02 13:23:05 [SECURITY CRITICAL] Redis rate limiter unavailable (FAIL CLOSED): ratelimit: redis client is not available
2026/11/02 13:23:05 [ERROR] 000d931276dafa04 service_unavailable POST /notifications/send: ratelimit: redis client is not available
--- PASS: TestSend_RateLimiterWithoutRedis_FailsClosedWith503 (0.00s)
=== RUN   TestSend_TypedNilStore_SkipsPersistenceAndDelivers
2026/11/02 13:23:05 [NOTIF-STORE] notification persistence is unavailable; notifications are delivered live and over push only
2026/11/02 13:23:05 [SSE-HUB] Broadcast: type=popup tenant=tenant-1 → 0 local clients
--- PASS: TestSend_TypedNilStore_SkipsPersistenceAndDelivers (0.00s)
=== RUN   TestStoreUsable_TypedNilIsNotUsable
--- PASS: TestStoreUsable_TypedNilIsNotUsable (0.00s)
PASS
ok  	github.com/project/notification-service/internal/handlers	0.005s
```

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

## Unverified

- **Item 1**: the upstream 5xx passthrough was verified against local test
  servers (httptest) and with the real circuit breaker, but **not** against a
  real upstream deployment that answers 5xx. The proxy still translates a
  *transport* error (dial, timeout, open breaker) into its own 502 — only a
  real upstream 5xx answer is passed through.
- **Item 2**: the degraded paths were verified with a closed Mongo client and
  a limiter without a Redis client (unit level). The behaviour against a
  **real** Redis/Mongo outage (server down, not client nil) was not
  reproduced; the nil-client case is the one the task asked for.
- **Item 3**: the Mongo store method (`RemoveDeviceTokenFromAnyUser`) was
  verified against the local MongoDB of this worktree, and the handler
  against a fake store. The **round trip through a running auth-service**
  (a real HTTP call with a real `X-Internal-Token` and a real Mongo) was not
  executed; the contract test checks that both sides agree on route, method,
  header and body field, not the live call.
- **Item 3**: the new endpoint is **not** in the docgen `KnownEndpoints` map
  (out of lane), so its row in `docs/APPLICATION_MAP.md` carries a
  `<!-- TODO: verify manually -->` cell. The row itself was generated by
  `make docs` and reflects the real route, but the map's hand-written
  context is not updated for it.
- **Item 4**: the masking was verified with unit tests over the helper and
  the list handler. No **frontend** consumer of `GET /admin/jobs` exists, so
  no client had to be adapted — but that was confirmed by searching the
  frontend, not by running a frontend against a live admin list.
- **Item 5**: the store failure was forced by closing the Mongo client. The
  two job endpoints (`cancel`, `complete-stuck-cod`) could not be forced to
  fail in a test (their first store call is the job lookup, which fails
  earlier with a 404); they are covered by the AST guard instead, not by a
  behavioural test.
- **Item 6**: the `::add-mask::` commands were verified locally (the script
  emits the right command, at the right point, with the right values). The
  **runner** behaviour (GitHub Actions consuming the command and redacting
  the value in the log) was not reproduced — there is no CI runner here. It
  is the documented behaviour of the platform.
- **Item 7**: the refusal was verified through `config.Load()` and through
  the real `--check-env` pre-flight of both services. It was **not** verified
  against the production environment itself: whether the production env file
  still carries the published dev key is unknown (the production env file
  is not in the repository). If it does, the next deploy of the
  user-service/auth-service will fail the pre-flight — see the deploy notes.
- The whole `make check` gate (full scope, including the frontend analyze
  and test stages) passed before every one of the seven commits; the exact
  gate output is not pasted into this worklog, it is reproducible with
  `make check`.

## Follow-ups / out-of-lane findings

These were found while working on the task and are **not** fixed here,
because the files are outside this task's lane (or the change would exceed
the item's scope). They are listed with their exact location so the owner
can pick them up:

- **chat-service still leaks raw store/JWT error text** in admin and chat
  responses (`services/chat-service/internal/handlers/admin_tickets.go`
  lines 106, 283, 287, 431, 435 and `chat.go` line 1119). The pattern is
  the same one item 5 removed from the user-service admin handlers:
  `writeJSON(w, <status>, map[string]string{"error": err.Error()})`. The
  chat-service is outside this task's lane.
- **The user-service still leaks raw store text in its non-admin paths**:
  `services/user-service/internal/handlers/reconciliation_handlers.go`
  lines 509 and 513 (404/409 bodies) and
  `services/user-service/internal/handlers/jobs_handlers.go` lines 475, 589
  and 966 (409 bodies). These are curated "not found" / "already exists"
  answers, but they are built from the raw store error, so a store error
  that happens to contain one of those words would be passed through
  verbatim. Item 5 deliberately limited itself to the admin handlers.
- **`docs/APPLICATION_MAP.md` line 122 is stale**: it still says
  "`POST /auth/device-token` (`unregister`) removes a token FCM reports as
  stale", which is the old, broken contract that item 3 replaced. The file
  may only be regenerated with `make docs`, and the docgen
  `KnownEndpoints` map (`shared/infra/docgen/generator.go`, out of lane)
  drives the table — the hand-written prose is not regenerated. The new
  route is in the generated table (line 206) with a
  `<!-- TODO: verify manually -->` cell in the `Targets` column, because
  the docgen does not know the new endpoint yet.
- **The auth-service only refuses an empty `DOCUMENT_ENCRYPTION_KEY` when
  `APP_ENV` is exactly `production`** (`services/auth-service/internal/config/config.go`,
  the `appEnv == "production"` comparison). `APP_ENV=Production` or
  `APP_ENV=production ` would skip that check. The new item-7 check is
  case-insensitive and trimmed; the pre-existing empty-key check was left
  untouched because changing it is a different (behaviour-changing) fix.
- **The script test harness of the repo is out of lane**
  (`scripts/test_staging_up.sh`, `scripts/run_script_tests.sh`): item 6
  could not add a regression test there, so the masking was verified with a
  manual reproduction instead (see the item 6 section). The existing
  harness was run and still passes.
- **The local dev stack still ships the published dev key**
  (`infrastructure/.env.example` line 108, `APP_ENV=local`). That is
  exactly what item 7 allows, but it means every local document is
  encrypted with a public key — acceptable for local development, not for
  anything else.

## Open questions

- **Does the production env file still carry the published dev
  `DOCUMENT_ENCRYPTION_KEY`?** If it does, item 7 turns the next deploy of
  the user-service/auth-service into a failed pre-flight
  (`PREFLIGHT FAILED: … DOCUMENT_ENCRYPTION_KEY is the published development
  key`) instead of a silent start with a public key. That is the intended
  behaviour, but it is a *deployment-visible* change and the owner has to
  know about it before the release.
- **Should the item-1 passthrough become the default** instead of an opt-in
  option? It is opt-in because only the api-gateway proxy wants it; every
  other consumer of `shared/infra/resilience` still gets an error on an
  upstream 5xx. A follow-up task could decide whether the other consumers
  (chat-service, notification-service) need the same treatment.
- **Should the dev-key blocklist grow** (e.g. the other published
  placeholders of `infrastructure/.env.example` — `JWT_SECRET`,
  `INTERNAL_SERVICE_TOKEN`, `ADMIN_API_TOKEN`)? Item 7 covers only
  `DOCUMENT_ENCRYPTION_KEY`, because that is the key that encrypts user
  data. The other placeholders protect tokens, not documents, and they are
  not valid 64-hex keys in every case.

## Deploy notes

- **Nothing beyond the normal release.** No new environment variable, no
  new configuration key, no changed port, no changed image and no changed
  default: every item is a behaviour change inside an existing request path
  or a new internal endpoint behind the existing `X-Internal-Token`.
- Item 1 changes what the api-gateway answers when an upstream service
  answers 5xx: the upstream status and body are passed through instead of
  being turned into a gateway 502. Clients that relied on the gateway 502
  for an upstream 5xx will now see the upstream status.
- Item 2 changes the notification-service answer when Redis is unavailable:
  503 `service_unavailable` instead of a panic (500). The plain rate-limit
  answer (429) is unchanged.
- Item 3 adds `POST /auth/internal/device-token/unregister` to the
  auth-service. It is internal (same `X-Internal-Token` as the other
  `/auth/internal/*` endpoints) and needs no route, port or env change.
- Item 4 changes the body of `GET /admin/jobs`: the recipient phone is
  masked there. The unmasked phone stays in `GET /admin/jobs/{id}`. No
  frontend consumer of the list exists.
- Item 5 changes the **body** of six admin endpoints on a store failure:
  they now answer `{"error": "<stable message>", "code": "internal_error",
  "request_id": "…"}` instead of a body that carried the store error text.
  The status code (500) is unchanged.
- Item 6 changes only the CI log of the release-gate workflow (the secrets
  are now registered as GitHub Actions log masks). No runtime behaviour.
- Item 7 makes the user-service and the auth-service **refuse to start**
  when `DOCUMENT_ENCRYPTION_KEY` is the published dev key and `APP_ENV` is
  not `local`/`test`. This is the one item that can stop a deployment: see
  the open question above. The staging stack is unaffected (it uses a
  random key), and the local dev stack is unaffected (`APP_ENV=local`).
