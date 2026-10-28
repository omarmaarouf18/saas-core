# Worklog FIX-E2E-PHOTO: Release Gate E2E Photo Upload Fix

## Task Summary
- **Task ID**: `FIX-E2E-PHOTO`
- **Objective**: Fix the Release Gate E2E failure where photo upload returned `502 {"error": "service unavailable", "target": "/api/v1/users/"}` instead of succeeding (or returning `503 photo_storage_unavailable`).
- **Branch**: `agent/FIX-E2E-PHOTO-staging-key-and-502`
- **Worktree**: `../saas-core-wt/FIX-E2E-PHOTO`

---

## Root Cause Analysis
1. **CI Staging Provisioning**: In CI runners where `.env.staging` does not pre-exist, `scripts/staging_up.sh` copied `.env.staging.example` without replacing placeholders, leaving `DOCUMENT_ENCRYPTION_KEY="CHANGE_ME_64_HEX"`. Because `PROD-PHOTO-STORAGE` item 1 made `user-service` fail closed on unusable encryption keys, photo storage remained uninitialized (`u.storage == nil`).
2. **Gateway 502 Masking**: When photo upload requests reached `user-service`, the handler returned `503 photo_storage_unavailable`. However, `api-gateway` wrapped routes with `resilience.NewRoundTripper`, which returned `fmt.Errorf("HTTP status %d", resp.StatusCode)` for any response with status >= 500 and closed the response body. `httputil.ReverseProxy` treated this error as a transport failure, discarded the backend response, and invoked its `ErrorHandler`, which replied with `502 Bad Gateway: {"error": "service unavailable", "target": "/api/v1/users/"}`, masking the underlying 503.

---

## Items Completed

### Item 1: CI/Staging Key Generation
- Updated `scripts/staging_up.sh` to generate `.env.staging` with unique `openssl rand -hex 32` values for all `CHANGE_ME_64_HEX` occurrences and random hex passwords for `CHANGE_ME_PASSWORD` occurrences, matching Mongo and Redis connection URIs with root passwords.
- Set file permissions to `600` via `chmod 600 "$ENV_FILE"`.
- Prevented overwriting existing `.env.staging`.
- Added `scripts/test_staging_up.sh` with 9 regression checks, discovered by `scripts/run_script_tests.sh`.
- Commit: `64a051d`

### Item 2: Root Cause of 502 & Gateway Pass-Through
- Investigated user-service behavior and gateway reverse proxy interaction.
- Verified user-service did not panic and did not close connections early; it returned clean HTTP 503.
- Fixed `services/api-gateway/internal/proxy/proxy.go` `ErrorHandler` to inspect upstream status errors and pass through HTTP 503 and `photo_storage_unavailable` responses rather than masking them with 502.
- Updated `services/user-service/internal/handlers/services_handlers.go` to limit and drain `r.Body` when storage is uninitialized before replying 503.
- Added regression test `TestProxy_Upstream503PhotoStorageUnavailable_PassesThroughAs503` in `services/api-gateway/internal/proxy/proxy_test.go` verifying that upstream 503 is passed through cleanly.
- Commit: `a2a34f0c`

### Item 3: Strict Photo Tests & CI Env Propagation
- Verified both photo tests (`TestE2E_BEGapsFix/ServicePhoto_RemoveAndReplaceDeleteObject` and `TestE2E_UserAuthBEGaps/ServiceCreate_PersistsAllFields_AndPhoto`) are strict and correct; kept both tests unchanged.
- Added environment variable export to `$GITHUB_ENV` in `scripts/staging_up.sh` so CI release-gate steps seamlessly inherit the randomly generated staging database credentials.
- Verified both photo tests pass (200 OK) against staging stack built from clean `.env.staging`.
- Commit: `b7b7b31`

### Item 4: Documentation in docs/RELEASE.md
- Updated `docs/RELEASE.md` section 4 ("What to Do When a Gate is Red") with:
  - How to read and distinguish Gateway 502 (`[PROXY ERROR]` transport errors) vs Service 503 (application subsystem rejections).
  - Detailed case study of the `FIX-E2E-PHOTO` incident.
- Commit: `8c3e4c8`

---

## Verification Evidence

### 1. Script Test Failing Before / Passing After

#### Failing Before Fix:
```text
FAIL: .env.staging was not created
FAIL: found CHANGE_ME_64_HEX in .env.staging
FAIL: found CHANGE_ME_PASSWORD in .env.staging
FAIL: not all secrets are valid 64-hex strings
FAIL: not all 64-hex keys are unique
FAIL: .env.staging permissions are 644, expected 600
```

#### Passing After Fix:
```text
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
```

### 2. Item 2 Reproduction Before / After (Status Lines Only)

#### Before Fix (502 Bad Gateway):
```text
=== RUN   TestProxy_Upstream503PhotoStorageUnavailable_PassesThroughAs503
2026/10/28 13:40:34 [PROXY ERROR] POST /users/services/svc_123/photo → http://127.0.0.1:35673: HTTP status 503
    proxy_test.go:599: expected 503, got 502: {"error": "service unavailable", "target": "/api/v1/users/"}
--- FAIL: TestProxy_Upstream503PhotoStorageUnavailable_PassesThroughAs503 (0.00s)
```

#### Staging curl Before Fix:
```text
HTTP/1.1 502 Bad Gateway
{"error": "service unavailable", "target": "/api/v1/users/"}
```

#### After Fix (503 Service Unavailable):
```text
=== RUN   TestProxy_Upstream503PhotoStorageUnavailable_PassesThroughAs503
2026/10/28 13:41:15 [PROXY ERROR] POST /users/services/svc_123/photo → http://127.0.0.1:42541: HTTP status 503
--- PASS: TestProxy_Upstream503PhotoStorageUnavailable_PassesThroughAs503 (0.00s)
PASS
```

### 3. Full E2E Against Staging (Clean .env.staging Provision)

#### Both Photo Tests PASS:
```text
=== RUN   TestE2E_BEGapsFix
=== RUN   TestE2E_BEGapsFix/ServicePhoto_RemoveAndReplaceDeleteObject
--- PASS: TestE2E_BEGapsFix (0.04s)
    --- PASS: TestE2E_BEGapsFix/ServicePhoto_RemoveAndReplaceDeleteObject (0.02s)
PASS
ok  	github.com/project/tests/e2e	0.039s
=== RUN   TestE2E_UserAuthBEGaps
=== RUN   TestE2E_UserAuthBEGaps/ServiceCreate_PersistsAllFields_AndPhoto
--- PASS: TestE2E_UserAuthBEGaps (0.02s)
    --- PASS: TestE2E_UserAuthBEGaps/ServiceCreate_PersistsAllFields_AndPhoto (0.01s)
PASS
ok  	github.com/project/tests/e2e	0.025s
```

#### Full E2E Test Suite Summary:
```text
PASS
ok  	github.com/project/tests/e2e	12.021s
```

### 4. make check Last Lines
```text
[timing] flutter-analyze-test 44.5s
[timing] total 407.9s
== pre-push gate: all checks passed (scope: full) ==
gate stamp written: <repo-root>/.git/gate-stamps/<stamp-sha> (scope: full)
```
