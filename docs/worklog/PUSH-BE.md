# Worklog: PUSH-BE — FCM delivery with OAuth2; PROD-PHOTO-STORAGE follow-ups

## Task and scope
- Task ID: PUSH-BE
- Item IDs covered: 1, 2, 3, 4, 5, 6
- Allowed paths (lane from the task prompt): `services/notification-service/**` (fcm, config,
  cmd), user-service photo handlers/models and tests, `infrastructure/docker-compose.yml` and
  `infrastructure/.env.example` (item 3), `docs/DEPLOYMENT.md`, the notification API doc
  (`docs/APPLICATION_MAP.md`, hand-written contract notes), one new `tests/e2e` file,
  this worklog. Not `frontend/**` (PUSH-FCM).
- Agent branch: agent/PUSH-BE-fcm-oauth-photo-followups, created from logic-exploitation (bca961e7)

## Decisions taken
- **Dependency: none added.** Token minting uses only the standard library (`crypto/rsa`,
  `crypto/x509`, `encoding/pem`, `encoding/json`): JWT-bearer grant (RFC 7523), RS256, scope
  `https://www.googleapis.com/auth/firebase.messaging`, `aud` = the key's `token_uri`
  (default `https://oauth2.googleapis.com/token`), 1 h assertion, `kid` = `private_key_id`.
  No go.mod / go.sum change, so go.work, GOWORK=off, govulncheck and the drift guard are untouched.
- **Android channel id: `qd_default`** (`fcm.DefaultAndroidChannelID`). PUSH-FCM must create a
  notification channel with exactly this id. Every Google-mode message carries
  `android.priority = "HIGH"` and `android.notification.channel_id = "qd_default"`.
- Payload: `notification.title/body`; `data` is passed through from the hub unchanged:
  `id`, `type`, `tenant_id` always, `job_id` and `event_type` for job notifications only (the
  BE-GAPS-FIX rule: no empty `event_type` on non-job notifications). All strings.
- Token cache: one mutex held across a mint, so concurrent senders share one mint; replaced when
  less than 5 min remain; a 401 drops the token (only if it is still the cached one) and retries
  once; that retry does not use up a 429/5xx attempt.
- Retry: 429 and 5xx, at most 3 attempts in all, 250 ms doubling or `Retry-After`, capped at 2 s
  (the hub gives one whole notification fan-out a 10 s context).
- Stale mapping: 404 / `NOT_FOUND` / `UNREGISTERED` → stale. `INVALID_ARGUMENT` → stale **only
  when it names the token** (field violation `message.token`, or "registration token" in the
  message). Before, any `INVALID_ARGUMENT` detail deleted the user's token; a payload bug would
  have wiped every token. Changed deliberately.
- Log lines: config now logs `[CONFIG] push key loaded (project X)` (was "push enabled"); cmd/main
  then mints one token (no send) at startup and in `--check-env` and logs
  `[FCM] push enabled (project X, token ok)` or `[FCM] push disabled: token mint failed: <reason>`.
  A third, truthful case: a **transient** mint failure (network, 429, 5xx) logs
  `[FCM] push enabled (project X, token mint failed: <reason>; retried on every send)` and keeps
  push on, so a short outage at boot does not disable push until the next restart. Only a
  rejected key/grant (4xx, unparseable key) disables the client. A failed mint never fails
  `--check-env` (same rule as PROD-PHOTO-STORAGE item 8).
- Outbound URL safety: `token_uri` (from the key) and the new `FCM_API_BASE_URL` must be https,
  or plain http only to a loopback host. `FCM_API_BASE_URL` exists only for local fakes and the
  e2e test; empty in every compose file.
- Error logs carry HTTP status, Google's status and a truncated message, never the raw body, key,
  assertion, access token or a full device token (the old code logged the raw FCM body).
- Item 2: "legacy" = `X-App-Version` parses with major < 2 (`1.4.2`, `v1.9.9`, `1.0.0+7`, `0.9.0`).
  A missing or unparseable header is **not** legacy (strict 400): every 2.0.0+ build sends the
  header, and builds older than the header itself (before 34915b76...) are not worth weakening
  the rule for. Values starting with `services/` (also after a leading `/` or `./`) or containing
  `..` are always 400 with the security event, whatever the version. Ignored values are logged
  without the value (may be a device path).
- Item 3: dev-only default `DOCUMENT_ENCRYPTION_KEY` in `infrastructure/.env.example` is `deadbeef`
  repeated to 64 hex characters (recognisably fake, low entropy for gitleaks), marked public and
  never for staging/production. Not written out here (the repo's SHA check rejects long hex runs).
- Item 4: `photo_version` = first 16 hex of SHA-256 of the storage key; ETag = `"<photo_version>"`;
  `Cache-Control: private, max-age=300`; 304 with no body on a matching `If-None-Match` (weak
  comparison, lists, `*`). The file is opened before answering 304, so a deleted object is 404,
  not 304. `photo_version` reaches the JSON through `MarshalJSON` on `Service` and on
  `ServiceWithPrice` (needed: the promoted method would otherwise drop the price fields); a
  reflection test guards that every field still reaches the JSON. App use:
  `GET /users/services/{id}/photo?v=<photo_version>` (the server ignores `v`).
- Item 6: the e2e test runs the real binary outside the staging stack against fakes (pointing the
  staging compose at a fake Google would need a hot-path change to
  `infrastructure/staging/**`, not granted). It uses the staging Redis/Mongo because the service
  panics without them (see Follow-ups); it skips when they are unreachable.

## Changes per commit (message only — NO SHAs)
1. `PUSH-BE: item 1 - FCM HTTP v1 with OAuth2 access tokens`
2. `PUSH-BE: item 2 - photo_url compatibility for app builds below 2.0.0`
3. `PUSH-BE: item 3 - local compose passes DOCUMENT_ENCRYPTION_KEY to user-service`
4. `PUSH-BE: item 4 - service photo ETag, short private cache, photo_version`
5. `PUSH-BE: item 5 - docs: push delivery, test push, payload, photo caching`
6. `PUSH-BE: item 6 - e2e: notification-service push through fake Google OAuth + FCM`
7. `PUSH-BE: worklog`

## Verification
- `make check` passed before every commit (`make commit` refuses otherwise). One run before
  item 3 was BLOCKED by `govulncheck: fetching vulnerabilities: Get "https://vuln.go.dev/index/modules.json.gz": dial tcp: lookup vuln.go.dev: Temporary failure in name resolution`
  (transient DNS); the rerun passed. One run before item 1 was BLOCKED by gosec G101 on the
  public token URL constant; fixed with a `#nosec G101` justification.
- Tests that failed before:
  - item 1, new FCM tests against the old `fcm.go` (compile failure: no OAuth API existed):

    ```text
    # github.com/project/notification-service/internal/fcm [github.com/project/notification-service/internal/fcm.test]
    ./fcm_test.go:73:29: undefined: FCMErrorDetail
    ./fcm_test.go:132:115: undefined: WithAPIBaseURL
    ./fcm_test.go:132:115: too many arguments in call to NewClient
    	have (string, string, string, string, string, nil, unknown type)
    	want (string, string, string, string, string, *http.Client)
    ./oauth_test.go:138:24: undefined: messagingScope
    ./oauth_test.go:188:105: undefined: WithAPIBaseURL
    ```

  - item 2, `TestServicePhotoURL_LegacyAppBuilds` against the old handler:

    ```text
    --- FAIL: TestServicePhotoURL_LegacyAppBuilds (0.54s)
        service_photo_url_guard_test.go:192: legacy 1.4.2 create with "file:///data/user/0/com.qd.app/cache/image_picker123.jpg": 400 {"error":"photo_url must be empty or a key returned by the photo upload","code":"invalid_photo_url","request_id":"8ed459e8b8c3a45b"}
    FAIL
    FAIL	github.com/project/user-service/internal/handlers	0.539s
    ```

  - items 4 and 6: not run against the old code (the tests target headers/fields/flags that did
    not exist; the old endpoint sent `max-age=86400` and no ETag by inspection).
- `go test -count=1 ./...`, notification-service, plus the new test names (`-v`, filtered):

  ```text
  ?   	github.com/project/notification-service/cmd	[no test files]
  ok  	github.com/project/notification-service/internal/config	0.003s
  ok  	github.com/project/notification-service/internal/fcm	0.110s
  ok  	github.com/project/notification-service/internal/handlers	0.745s
  ok  	github.com/project/notification-service/internal/hub	0.526s
  ok  	github.com/project/notification-service/internal/store	2.677s
  --- PASS: TestFCMPush_NoInternalTokenToGoogle (0.04s)
  --- PASS: TestFCMOAuth_TokenMintedCachedAndSentAsBearer (0.00s)
  --- PASS: TestFCMOAuth_TokenRefreshedFiveMinutesBeforeExpiry (0.00s)
  --- PASS: TestFCMOAuth_RefreshOn401Once (0.01s)
  --- PASS: TestFCMOAuth_ConcurrentSendsMintOnce (0.00s)
  --- PASS: TestFCMOAuth_StaleTokenMapping (0.01s)
  --- PASS: TestFCMOAuth_RetryOn429And5xx (0.01s)
  --- PASS: TestFCMOAuth_StartupCheck (0.00s)
  --- PASS: TestFCMOAuth_NoKeyMaterialInLogs (0.00s)
  ```

  (This run was a raw `go test` without `scripts/ci-lock.sh`; the store/hub packages use the shared
  local Mongo/Redis. My mistake against the rule; no concurrent gate run was visible at the time,
  and `make check` ran the same packages under the lock before each commit. `go test -race` of
  `internal/fcm` also passed during development.)
- `go test -count=1 -v ./...`, user-service, under `bash scripts/ci-lock.sh` (summary + new tests,
  0 `--- FAIL` lines in the run):

  ```text
  ?   	github.com/project/user-service/cmd	[no test files]
  ok  	github.com/project/user-service/internal/config	0.002s
  ok  	github.com/project/user-service/internal/handlers	207.048s
  ok  	github.com/project/user-service/internal/models	0.003s
  ok  	github.com/project/user-service/internal/store	8.600s
  --- PASS: TestServicePhoto_ETagAndCacheControl (0.97s)
  --- PASS: TestServicePhotoURL_LegacyAppBuilds (2.28s)
  --- PASS: TestPhotoVersionOf (0.00s)
  --- PASS: TestServiceWithPrice_JSONHasEveryField (0.00s)
  ```

- e2e, `go test -count=1 -v -run TestPushBE ./` in `tests/e2e` (staging stack up locally):

  ```text
  === RUN   TestPushBE_NotificationServiceDeliversViaFCMOAuth
  --- PASS: TestPushBE_NotificationServiceDeliversViaFCMOAuth (1.01s)
  PASS
  ok  	github.com/project/tests/e2e	1.015s
  ```

- `--check-env` of a locally built notification-service binary (`go build ./cmd`, not the prod
  image) with a throwaway RSA key (`openssl genpkey`, shredded afterwards) whose `token_uri`
  pointed at a fake token server on 127.0.0.1, dummy JWT/TLS/Redis values. Nothing needed
  redacting: a grep of the output for the key's second PEM line, the fake access token and the
  first 40 base64 characters of the key file found 0 matches. Literal output:

  ```text
  ## fake token server MODE=ok
  2026/10/28 08:51:44 [CONFIG] push key loaded (project qd-check)
  2026/10/28 08:51:44 [FCM] push enabled (project qd-check, token ok)
  PREFLIGHT OK: notification-service config validated
  exit=0
  fake-token: grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer assertion_parts=3
  ## fake token server MODE=reject
  2026/10/28 08:51:45 [CONFIG] push key loaded (project qd-check)
  2026/10/28 08:51:45 [FCM] push disabled: token mint failed: token endpoint returned HTTP 400: invalid_grant Invalid JWT Signature.
  PREFLIGHT OK: notification-service config validated
  exit=0
  fake-token: grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer assertion_parts=3
  ## token server down
  2026/10/28 08:51:45 [CONFIG] push key loaded (project qd-check)
  2026/10/28 08:51:45 [FCM] push enabled (project qd-check, token mint failed: token request failed: dial tcp 127.0.0.1:18765: connect: connection refused; retried on every send)
  PREFLIGHT OK: notification-service config validated
  exit=0
  ```

- Item 3: `bash scripts/compose-validate.sh local prod staging`:

  ```text
  compose config OK: local (infrastructure/docker-compose.yml)
  compose config OK: prod (infrastructure/deploy/docker-compose.prod.yml)
  compose config OK: staging (infrastructure/staging/docker-compose.staging.yml)
  ```

  and the resolved local config (key value replaced by me with a placeholder via `sed`):

  ```text
  81:    container_name: saas-auth-service
  87:      DOCUMENT_ENCRYPTION_KEY: deadbeef...(dev default, 64 hex)
  370:    container_name: saas-user-service
  377:      DOCUMENT_ENCRYPTION_KEY: deadbeef...(dev default, 64 hex)
  ```

  user-service `--check-env` (`go run ./cmd/... --check-env`, APP_ENV=local, dummy values):

  ```text
  ## APP_ENV=local key=<empty>
  PREFLIGHT WARNING: DOCUMENT_ENCRYPTION_KEY is empty; service photo upload and read will answer 503 photo_storage_unavailable
  PREFLIGHT OK: user-service config validated
  ## APP_ENV=local key=<.env.example dev default>
  PREFLIGHT OK: user-service config validated
  ```

- `make check`, last lines of the run before the item 6 commit (scope full, because a new
  `tests/e2e` path is unmapped):

  ```text
  00:47 +1319: All tests passed!
  [timing] flutter-analyze-test 59.7s
  [timing] total 554.1s
  == pre-push gate: all checks passed (scope: full) ==
  ```

## Unverified
- Real delivery through Google: no Firebase project or key was available here. The OAuth flow is
  checked against fakes that verify the RS256 signature and claims; the exact Google error bodies
  used for the stale mapping are taken from the FCM v1 docs as I know them, not captured live.
- The prod image (`docker build --target prod`) was not rebuilt; `--check-env` ran on a local
  binary of the same code.
- Local photo upload in the running local compose stack (item 3) was not exercised end to end;
  only the compose config and user-service pre-flight were checked.
- The DEPLOYMENT.md step 6 test-push commands (curl over mTLS on the VM, `-H @<(...)`) were not
  run (no VM access); they follow the cert layout and compose names in the repo.
- The e2e test has not run in the GitHub release-gate workflow yet.

## Follow-ups / out-of-lane findings
- **notification-service panics instead of degrading** when Redis or Mongo is unreachable at
  startup: `cmd/main.go` logs "falling back to single-instance local hub mode" / "running without
  notification persistence", but `POST /notifications/send` then panics (nil Redis client in the
  rate limiter, `shared/infra/ratelimit/ratelimit.go:149`; a typed-nil `*store.MongoDB` in
  `InsertNotification`, `store/mongodb.go:151`). Seen while writing the e2e test. Not fixed: not
  asked, and the rate-limiter part is in `shared/infra` (hot path).
- `infrastructure/.env.example` also feeds the prod compose validation; nothing stops someone from
  copying the dev-only `DOCUMENT_ENCRYPTION_KEY` into a production `.env`. A production refusal of
  that known value in user-service/auth-service config would close it.
- The app should append `photo_version` to the photo URL and create the `qd_default` channel
  (PUSH-FCM).

## Open questions
- none
