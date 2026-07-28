# Bug Fixes Changelog

This file tracks historical entries for the primary category: **Bug Fixes Changelog**.

---

## WalletDeposit Upper Limit

- **Implementation Detail**: Enforced a maximum limit of 1,000,000 on WalletDeposit amounts in user-service.
- **Commit SHA**: ``a1e965f76f3b2e436b1f76d3c13d0d390e6529f1``
- **Verification**: Verified via user-service unit tests. ✅

## Graceful Employee Deactivation

- **Implementation Detail**: Gated new job assignment in TrackJob behind employee IsActive lookup. Allowed deactivated employees to complete existing in-progress jobs.
- **Commit SHA**: ``ebe5f62e41459ede18a1a9a4644d9e99cb5574cd``
- **Verification**: Verified via auth-service and user-service integration tests. ✅

## Per-Job Location Throttling

- **Implementation Detail**: Throttled consecutive location updates under 3s per Job ID with in-flight reservations and rollback.
- **Commit SHA**: ``8ba1b34dd5fbb068f43bd94ce29692620ce8877e``
- **Verification**: Verified via unit, race, and integration tests. ✅

## CORS headers on SSE stream errors

- **Implementation Detail**: Moved Access-Control-Allow-Origin header injection to the top of SSE Stream handler so that connection error responses are readable by browser JS.
- **Commit SHA**: ``bb80f2bcc6dde695861c6547db6152662b7e1e0a``
- **Verification**: Verified via compilation and test execution. ✅

## Removed dead SSE Done channel

- **Implementation Detail**: Deleted the unused Done channel field from SSEClient and its initialization as client connection disconnects are already handled gracefully by the context and Send channel closure.
- **Commit SHA**: ``0d9caf82127392992ac60677ad1f0ca60760d7c6``
- **Verification**: Verified via compilation and test execution. ✅

## Random Notification IDs

- **Implementation Detail**: Switched notification ID generation from UnixNano timestamp to crypto/rand-based 16-byte random hex string to eliminate collision risks.
- **Commit SHA**: ``8cab6c2fe22909455ebed3f351706a0d0d8f6967``
- **Verification**: Verified via compilation and test execution. ✅

## Token Refresh Panic on Expired Token

- **Implementation Detail**: Updated `ValidateToken` in `jwtutil` to return the parsed claims even when `ErrExpiredToken` is encountered. This prevents nil-pointer panics in `/auth/refresh` when accessing `claims.ExpiresAt` on expired tokens.
- **Commit SHA**: ``5ac1d9e3173d94f91bb2c8d6217795a1c7775e62``
- **Verification**: Verified via auth-service unit tests (`TestTokenRefresh`) and jwtutil unit tests (`TestValidateToken_Expired`). ✅

## Signup Rollback on OTP Set Failure

- **Implementation Detail**: Updated `Signup` in `auth-service` to delete/rollback the newly created user record in MongoDB if generating/saving the OTP code via `SetOTP` fails. This prevents leaving an orphaned user record in a stuck `is_confirmed = false` state.
- **Commit SHA**: ``5a17284748a87a5b24467d4397183e7b8b5768f7``
- **Verification**: Verified via auth-service unit tests (`TestSignupRollbackOnOTPFailure`). ✅

## KYB/KYE Signed URL Error Propagation

- **Implementation Detail**: Captured and propagated S3/local storage `GetSignedURL` errors in `GetPendingKYBKYESubmissions` (`/auth/kyb-kye/pending`). Server-side failures are now logged with details and surfaced in the client response under `document_errors` per submission rather than silently rendering an empty URL.
- **Commit SHA**: ``f95367ee3f2cc95be594c795037c874d219269b9``
- **Verification**: Verified via auth-service integration tests (`TestGetPendingKYBKYESubmissions_StorageError`). ✅


## Unconfirmed User OTP Verification Deadlock & Resend Path

- **Implementation Detail**: Added a new `POST /auth/resend-otp` endpoint to `auth-service` allowing unconfirmed users to request a fresh OTP. This breaks the deadlock where an unconfirmed account could not log in, sign up again, or trigger a new code. The endpoint validates parameters, enforces IP and email rate limiting via the existing rate limiter, prevents identity/state leakage by returning a generic success message if the account doesn't exist or is already confirmed, and updates the OTP and expiration in MongoDB. Updated the Flutter frontend's `OtpScreen` to include a "Resend Code" button that invokes this endpoint, dynamically handles the response, and displays the new dev OTP code in development environments.
- **Commit SHA**: ``119f4f1d2b38527ecb13280574334506b3456a83``
- **Verification**: Verified via auth-service unit tests (`TestOTPResendFlow`). ✅

## Resilience Client Connection Leak Fix

- **Implementation Detail**: Corrected a resource leak in `ResilienceClient.Do` and `ResilienceRoundTripper.RoundTrip` where intermediate responses returned by the circuit breaker execution on HTTP 5xx failures were not closed during retries or prior to returning the error, leading to connection/file descriptor leaks. Added explicit body closure on error states.
- **Commit SHA**: ``eb0ddb54b537358b46f00b82b9540d069b531705``
- **Verification**: Verified via `shared/infra/resilience/resilience_test.go` (`TestResilienceClient_ConnectionLeak`). ✅

## Documentation Sync and Code Formatting Drift Correction

- **Implementation Detail**: Corrected formatting drift in the notification-service tests, synchronized the APPLICATION_MAP.md Git commit version, and established a pre-commit verification gate in CLAUDE.md to require gofmt, go build, and go test checks before code changes are committed and pushed.
- **Commit SHA**: ``4e57ef7c5127730198f67800f80b260ab877a2fd``
- **Verification**: Verified by executing formatting checks (`gofmt -l .`) and running the documentation AST/SHA validators (`TestDocgenFreshness` and `TestChangelogCommitSHAs`). ✅

## API Gateway Container go.sum Drift

- **Implementation Detail**: Ran `go mod tidy` in the `api-gateway`, `chat-service`, and `notification-service` modules to resolve build-blocking dependency drift. The addition of CloudWatch logging dependencies in `shared/infra/handlerutil/security_logs.go` caused `docker compose build` to fail for `api-gateway` with a missing module entry in `go.sum`. Added missing indirect dependencies to `api-gateway/go.mod` and cleanups to `chat-service/go.mod` and `notification-service/go.mod`.
- **Commit SHA**: ``8d62ee0e54b60a0aff65059039fa9557950b52b8``
- **Verification**: Verified by executing a clean `docker compose down`, `docker compose build --no-cache`, and `docker compose up -d` locally, confirming the gateway successfully builds, resolves dependencies, listens on HTTPS port 8080, and responds to health checks. ✅

## UpdateJobLocation Throttle Rollback Test Flakiness

- **Implementation Detail**: Eliminated a timing race in `TestUserServiceHandlers/UpdateJobLocation_Throttle_Error_Rollback` where a polling goroutine canceled the request context to simulate a database write failure. On slower CI machines, the write could complete before the cancel signal, causing the request to succeed (returning 200 instead of 500) and setting a new throttle timestamp, which then caused the retry call to fail with 429. Added an unexported test hook `updateJobLocationBeforeWriteHook` on `UserService` to allow the test to deterministically synchronize and cancel the context *after* the in-flight state is established but *before* the MongoDB write is executed.
- **Commit SHA**: ``b6cae1753e1146c5b1900cafbce9935f3b18389f``
- **Verification**: Verified via `services/user-service` handlers tests (`TestUserServiceHandlers/UpdateJobLocation_Throttle_Error_Rollback`) running in a tight loop of 50 runs with zero failures. ✅

## Notification-Service Handlers Test Sleep Auditing

- **Implementation Detail**: Audited and replaced 5 flaky, fixed `time.Sleep` calls in `services/notification-service/internal/handlers/handlers_test.go` with deterministic polling loops using generous timeouts (2s). Introduced a thread-safe `safeRecorder` helper struct to prevent data races on `httptest.ResponseRecorder`'s unsynchronized `bytes.Buffer` when polling for writes concurrently. Staggered client disconnect stress testing is now synchronized to wait for active hub registration before scheduling disconnect timers, ensuring robust execution under load.
- **Commit SHA**: ``f6aedfa84b70cba80ba9f88370dc376b24c55dea``
- **Verification**: Verified via `services/notification-service` handlers tests running in a loop of 50 runs under the Go race detector with zero failures. ✅

## Chat-Service Hub Test Sleep Auditing

- **Implementation Detail**: Audited and replaced flaky `time.Sleep` calls in `services/chat-service` tests. Replaced the fixed `time.Sleep(50 * time.Millisecond)` in `internal/chat/hub_test.go` with a deterministic, thread-safe polling loop on `hub.ClientCount()` and `hub.ChannelCount()` to synchronize after concurrent client unregistrations. The remaining `time.Sleep` calls in `hub_test.go` (spacing simulated active overlapping traffic) and `chat_test.go` (spacing database write timestamps) were verified as safe timing configurations with no active I/O races, and were left unmodified.
- **Commit SHA**: ``51c50e96efba171d6c0b115db0601972ee508389``
- **Verification**: Verified via `services/chat-service` unit and stress tests running in a loop of 50 runs under the Go race detector with zero failures. ✅

## Resend From-Email Configuration Validation

- **Implementation Detail**: Enforced fail-fast startup validation in `auth-service`'s `config.Load()` requiring `RESEND_FROM_EMAIL` to be specified whenever `RESEND_API_KEY` is set. Removed silent fallback to Resend's shared test domain (`onboarding@resend.dev`), preventing production deployments from accidentally dispatching emails from the sandbox address.
- **Commit SHA**: ``7cd13c04e407ae527d8a641193d0cb37fc2db777``
- **Verification**: Verified via `services/auth-service/internal/config` unit tests (`TestLoad_ResendConfig`) covering error on missing sender email, success on full config, and un-gated fallback when Resend is disabled. ✅

## Rate Limiting for RateJob and GetRatings Handlers (Item #3)

- **Implementation Detail**: Resolved deep-tester Item #3 (severity 5/10, priority 6/10). Added IP-based rate limiting via `u.limiter.CheckAndRecord` to `RateJob` (`POST /users/jobs/rate`) and `GetRatings` (`GET /users/ratings`), matching the security controls on `TrackJob` and `WalletDeposit` to prevent request flooding and rating enumeration attacks.
- **Commit SHA**: ``12fde32e15a4f150ac9f10f6f9223ff2163f5d5c``
- **Verification**: Verified via `go test ./services/user-service/internal/handlers -run TestRateJobAndGetRatings_RateLimiting -v` (asserting 429 Too Many Requests response after exceeding rate limit). ✅

## Expected Role Enforcement via resolveTokenWithRole (Item #4)

- **Implementation Detail**: Resolved deep-tester Item #4 (severity 4/10, priority 6/10). Replaced raw `resolveToken` calls with `resolveTokenWithRole` across handlers, enforcing expected roles (`owner`, `employee`, `user`/`customer`) during JWT claim resolution and rejecting tokens early on role mismatch.
- **Commit SHA**: ``a81a75323978195cf3d22c40dbc2c9400adc89a7``
- **Verification**: Verified via `go test ./services/user-service/internal/handlers -run TestResolveTokenWithRole -v` (asserting role matching, multi-role acceptance, and role mismatch rejection). ✅

## Rating Summary Access Model for Authenticated Requesters (Item #5)

- **Implementation Detail**: Resolved deep-tester Item #5 (severity 4/10, priority 5/10). Updated `GetRatings` (`GET /users/ratings`) to authenticate the caller via JWT token while allowing target `user_id` query parameter to specify any candidate employee/user ID. This enables business flows such as owners evaluating candidate employee rating summaries before hiring without requiring possession of the candidate's JWT token.
- **Commit SHA**: ``0213d4674fbd411923b1511262417edecceda47d``
- **Verification**: Verified via `go test ./services/user-service/internal/handlers -run TestUserServiceHandlers/GetRatings -v` (asserting authenticated owner query for target employee rating summary returns 200 OK). ✅

## Dual-Layer Rate Limiting for GetLedger Handler (Item #6)

- **Implementation Detail**: Resolved deep-tester Item #6 (severity 3/10, priority 4/10). Added IP-based and tenant-based rate limiting via `u.limiter.CheckAndRecord` to `GetLedger` (`GET /users/ledger`), matching the financial rate limiting protections on `WalletDeposit` to prevent ledger scraping and resource exhaustion attacks.
- **Commit SHA**: ``2398fcd44ee834b78f073d424c9cb08e7ad5094a``
- **Verification**: Verified via `go test ./services/user-service/internal/handlers -run TestGetLedger_RateLimiting -v` (asserting 429 Too Many Requests response after 5 requests from same IP). ✅

## Test Payment Bypass Gating & Production Safeguard (Item #7)

- **Implementation Detail**: Resolved deep-tester Item #7 (severity 3/10, priority 4/10). Hardened payment bypass controls in `TrackJob` and `WalletDeposit` to require the explicit environment variable `ALLOW_TEST_PAYMENT_BYPASS=true` in addition to non-production environment checks (`APP_ENV=test` or `local`). Added startup validation in `config.Load()` that immediately fails service startup if `ALLOW_TEST_PAYMENT_BYPASS=true` is set when `APP_ENV=production`.
- **Commit SHA**: ``0a8cfb789c6eb95b40087557884d179ff58863a7``
- **Verification**: Verified via `go test ./services/user-service/internal/config -run TestLoad_AllowTestPaymentBypass -v` (asserting production startup error) and `go test ./services/user-service/internal/handlers -run TestTestPaymentBypass_Gating -v` (asserting 400 Bad Request when flag is unset). ✅

## RateJob Comment Sanitization & Length Bound (Item #8)

- **Implementation Detail**: Resolved deep-tester Item #8 (severity 3/10, priority 3/10). Added 1000-character maximum length validation on incoming comments in `RateJob` (`POST /users/jobs/rate`) and sanitized comments using `html.EscapeString` server-side to neutralize HTML/XSS injection payloads. Confirmed frontend rendering in `frontend/lib` uses standard Flutter `Text` widgets to display comments strictly as plain text.
- **Commit SHA**: ``48546bdb5f768af3d75aadb73c5adb7fdf414595``
- **Verification**: Verified via `go test ./services/user-service/internal/handlers -run TestRateJob_CommentSanitizationAndLengthLimit -v` (asserting 400 Bad Request response when comment exceeds 1000 characters). ✅

## E2E Integration Test Redis Port Resolution & Nil Safety Guards

- **Implementation Detail**: Fixed hardcoded Redis port (`localhost:6380`) in `adr0006_e2e_integration_test.go` and `adr0007_e2e_integration_test.go` to dynamically parse `REDIS_URI` / `REDIS_ADDR` with fallback to default port `6379`, matching `ci.yml` runner configuration (`redis://localhost:6379`). Added Redis `Ping` connectivity checks to skip E2E integration tests gracefully when Redis is unreachable, and added explicit HTTP status code assertions and nil pointer safety guards across all test subtests to prevent test runner crashes. Updated documentation guidelines requiring explicit disclosure of local vs CI environment verification scope.
- **Commit SHA**: ``cd824bfc90427e18d5ccab9ddde5c441fdec93c7``
- **Verification**: Verified via local Go test execution (`go test ./services/user-service/internal/handlers -run TestADR0006_E2E_NegotiableTransportPricing -v` and `TestADR0007_E2E_DeliveryGPSReconciliation -v`). Pending GitHub Actions CI runner verification. ✅

## Negotiable Transport Pricing Escrow Locking & Reconciliation Fallback in RespondPrice

- **Implementation Detail**: Resolved non-COD negotiable transport job escrow locking gap in `RespondPrice` (`POST /users/jobs/respond-price`). When a price proposal is accepted (`decision == "accept"`), `LockEscrow` locks the agreed price in the owner wallet before transitioning status to `active`. On `UpdateJobLockedEscrow` persistence failure, `performRollbackEscrow` executes with single retry; if rollback fails, the job transitions to `models.JobStatusEscrowReconciliationRequired` with `ReconciliationNote` set, preventing silent unrecorded escrow state and routing the job to `GET /users/jobs/reconciliation-queue`.
- **Commit SHA**: ``e8eb530ebcd0529369596d87f807052b55ff7d8a``
- **Verification**: Verified via `go test ./services/user-service/internal/handlers -run TestRespondPrice_EscrowLockingAndReconciliationFallback -v` (6/6 passing including COD skip, insufficient funds 400, rollback failure reconciliation queue routing, and full accept-then-complete end-to-end chain) and `make docs-check`. ✅

## AI_CONTEXT.md Orphaned Commit SHA Citation Correction

- **Implementation Detail**: Corrected an orphaned commit SHA citation in `AI_CONTEXT.md` under "Verified Android Emulator End-to-End Backend Connectivity". The citation previously referenced an orphaned reflog object (`05b5ca72b083cfd77347a64ea7f39b1a67e66986`) resulting from a local `git commit --amend`, which was caught by CI SHA validation. Updated the entry to cite the real commit (`807f98bbca30bf072824b11892a60af02ff310ba`) that introduced the verification entry.
- **Commit SHA**: ``930c346070c5f866ce0638ab0d091e9abae95e38``
- **Verification**: Verified via local SHA verification loop (`grep -oE '[0-9a-f]{40}' AI_CONTEXT.md docs/changelog/*.md | while read -r line; do sha=$(echo "$line" | cut -d: -f2); if ! git cat-file -e "$sha^{commit}" 2>/dev/null; then echo "BLOCKED: fabricated/non-existent SHA $sha"; fi; done` printed 0 output). ✅

## Android Gradle compileSdk Pinning for AAR Metadata Alignment

- **Implementation Detail**: Resolved Android APK compilation failure caused by AAR metadata requirement mismatch. The transitive dependency `flutter_plugin_android_lifecycle` (v2.0.35, pulled in via `file_picker: ^8.0.0`) requires compiling against Android SDK 36 (`compileSdkVersion 36`), whereas default `flutter.compileSdkVersion` resolved to a lower version. Updated `frontend/android/app/build.gradle.kts` to explicitly pin `compileSdk = 36`. Exact error signature resolved: `checkDebugAarMetadata... Dependency 'flutter_plugin_android_lifecycle' requires 'compileSdkVersion' 36 or higher`. Updated troubleshooting matrix in `frontend/CONNECTING_TO_BACKEND.md`.
- **Commit SHA**: ``c1f00d3d026207acb4f78741afaae121c07afa88``
- **Verification**: Verified via `flutter analyze` (0 issues), `flutter test` (35/35 test suites passing), and local SHA verification check. ✅





