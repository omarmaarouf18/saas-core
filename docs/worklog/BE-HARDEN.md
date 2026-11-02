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

- (filled in as the task progresses)

## Unverified
- (filled in as the task progresses)

## Follow-ups / out-of-lane findings
- (filled in as the task progresses)

## Open questions
- (filled in as the task progresses)
