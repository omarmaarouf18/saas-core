# Worklog: FIX-E2E-UNREG — e2e fake auth-service serves the internal unregister route

## Task and scope
- Task ID: FIX-E2E-UNREG
- Item IDs covered: FIX-E2E-UNREG (Release Gate E2E failure of `TestPushBE_NotificationServiceDeliversViaFCMOAuth`)
- Allowed paths (lane from the task prompt): `tests/e2e/push_fcm_oauth_test.go`, `docs/worklog/FIX-E2E-UNREG.md`
- Agent branch: agent/FIX-E2E-UNREG-e2e-internal-unregister, created from logic-exploitation (de93dd1c)

## Decisions taken
- The fake auth-service now serves `POST /auth/internal/device-token/unregister` with body `{"token": "..."}` and answers `204`, exactly like the real handler (`services/auth-service/internal/handlers/internal_device_token.go`). Method, path, header and body were read from the real handler and from the notification-service fetcher (`services/notification-service/internal/hub/fetcher.go`), not from the task prompt:
  - method `POST`, path `/auth/internal/device-token/unregister`,
  - header `X-Internal-Token` (plus `Content-Type: application/json`),
  - body `{"token": "<token>"}` (no `action` field any more),
  - success answer `204 No Content`; the fetcher treats any 2xx as success.
- The stale token is recorded as the bare token (`device-stale`), in the shape of the new request body, and the assertion stays strict: exactly one unregistration, for the stale token only.
- The removed `POST /auth/device-token` route is still answered by the fake, but with `410 Gone`; every such call is recorded and fails the test with an explicit message, so a regression back to the old cleanup route cannot pass silently. A non-POST call on the internal route is answered `405` and fails the test the same way.

## Changes per commit (message only — NO SHAs)
1. `FIX-E2E-UNREG: e2e fake auth-service serves the internal unregister route`

## Verification
- `gofmt -l tests/e2e/push_fcm_oauth_test.go` — empty
- `go vet ./tests/e2e/...` — PASS (exit 0, no output)
- `bash ./scripts/staging_up.sh` — staging stack UP (the first attempt failed: the pre-existing `staging_saas_mongo_data` volume held a different root password than `infrastructure/staging/.env.staging`, so the mongo healthcheck answered `AuthenticationFailed: SCRAM authentication failed, storedKey mismatch`; the staging volumes are ephemeral by design — `scripts/staging_down.sh` runs `down -v` — so the stack was reset with `bash ./scripts/staging_down.sh` and brought up again, which initialized a fresh volume)
- `go test ./tests/e2e/ -run 'TestPushBE_NotificationServiceDeliversViaFCMOAuth|TestPushL10N_DeviceLanguagePerToken' -count=1 -v` against the local staging stack — PASS
  ```
  === RUN   TestPushBE_NotificationServiceDeliversViaFCMOAuth
  --- PASS: TestPushBE_NotificationServiceDeliversViaFCMOAuth (1.15s)
  === RUN   TestPushL10N_DeviceLanguagePerToken
  --- PASS: TestPushL10N_DeviceLanguagePerToken (3.01s)
  PASS
  ok  	github.com/project/tests/e2e	4.168s
  ```
- Regression check (the removed route must fail loudly): the notification-service was rebuilt from a copy outside the repo whose `UnregisterStaleToken` was patched back to `POST /auth/device-token` with `{token, action: "unregister"}`, and the test was pointed at that copy. The fake answered `410` and the test failed with the intended message:
  ```
  === RUN   TestPushBE_NotificationServiceDeliversViaFCMOAuth
      push_fcm_oauth_test.go:337: stale-token cleanup used the wrong route: [POST /auth/device-token (action="unregister"): the stale-token cleanup must POST /auth/internal/device-token/unregister]
  ...
          2026/11/02 15:50:58 [FCM-PUSH] Failed to unregister stale token for user u-e2e: auth-service device-token unregister returned status 410
  --- FAIL: TestPushBE_NotificationServiceDeliversViaFCMOAuth (1.16s)
  FAIL
  FAIL	github.com/project/tests/e2e	1.165s
  ```
  The temporary build-dir change was reverted; the committed test builds the service from `../../services/notification-service` again.
- `go test -v -count=1 ./tests/e2e/...` (the full Release Gate E2E command, locally against the staging stack) — PASS, 29 tests, 0 failures (`ok github.com/project/tests/e2e 16.061s`)
- `make check` — PASS, FULL scope: `tests/e2e/**` is not in the `scripts/changed-scope.sh` mapping, so the gate falls back to the full gate (`scope: FULL gate: tests/e2e/push_fcm_oauth_test.go (unmapped path: fail safe)`)

## Unverified
- The GitHub Actions Release Gate E2E workflow was not run here (it runs on the pushed branch in CI); the local staging runs above are the local equivalent of that workflow.
- The 410 path was exercised against a patched copy of the notification-service outside the repository, not against a released binary; the committed tree contains no reference to that copy.

## Follow-ups / out-of-lane findings
- `docs/APPLICATION_MAP.md` line 122 still describes the notification-service cleanup as `POST /auth/device-token` (`unregister`); the real route is now `POST /auth/internal/device-token/unregister` (the endpoint table itself was already updated by BE-HARDEN). Fixing the prose is a docs change outside this task's lane — reported, not fixed.
- `AI_CONTEXT.md` line 135 still lists the stale push-token cleanup as an open item ("in progress, BE-HARDEN"). It is a shared doc an agent branch must not edit (WF-01) — reported for the owner's fold.

## Open questions
- none
