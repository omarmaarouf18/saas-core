# Bug Fixes Changelog

This file tracks historical entries for the primary category: **Bug Fixes Changelog**.

## COD Job Cancel/Complete Race Condition & AgreedPrice Escrow Refund Math (Audit Findings 1 & 2)

- **Implementation Detail**:
  - **Finding 1 Fix (`services/user-service/internal/store/mongodb.go`)**: Added atomic CAS status precondition `status: {$in: [JobStatusActive, JobStatusPending, JobStatusAwaitingPriceResponse, JobStatusEscrowReconciliationRequired, JobStatusCancelled]}` to `CancelJob`, eliminating the race condition between concurrent `CompleteJob` and `CancelJob` requests. Returned HTTP 409 Conflict when a non-cancellable state transition occurs.
  - **Finding 2 Fix (`services/user-service/internal/handlers/handlers.go`)**: Updated `CancelJob` refund calculation to inspect `job.AgreedPrice` before falling back to `job.LockedEscrowAmount`, eliminating stranded locked escrow on negotiated transport cancellations.
  - **Test Suite (`services/user-service/internal/handlers/business_logic_audit_fixes_test.go`)**: Built integration tests `TestFinding1_CODCancelCompleteRaceCondition` and `TestFinding2_CancelJob_NegotiatedTransport_AgreedPriceRefund`.
- **Commit SHA**: `85a5c04`
- **Verification**: Verified via `gofmt`, `go build`, `go vet`, and `go test -v ./...`. ✅

## Settings KYC Role Gating, Redundant Refresh Button Cleanup, and Owner Arabic Localization

- **Implementation Detail**:
  1. **Settings KYC Role Gating (Bug 1)**: Updated `frontend/lib/screens/settings_screen.dart` to gate identity verification (KYC/KYB) display with `showKycRow = user != null && (user.role == 'owner' || user.role == 'employee') && user.kycStatus != 'approved'`. Updated `frontend/test/settings_screen_test.dart` to verify customer role (`user`) hides the KYC row even when unverified, while owner and employee roles display the row when unverified and hide it when approved.
  2. **Redundant Refresh Button Cleanup (Bug 2)**: Removed redundant refresh `IconButton` widgets from AppBar `actions` across 5 screens (`employee_jobs_screen.dart`, `home_screen.dart`, `customer_jobs_screen.dart`, `kyb_kye_review_screen.dart`, `owner_reconciliation_queue_screen.dart`) while retaining `RefreshIndicator` pull-to-refresh gestures. Added widget tests covering `RefreshIndicator` pull gestures in `employee_jobs_screen_audit_test.dart` and `owner_home_screen_test.dart`.
  3. **Owner Arabic Localization Pass (Bug 3)**: Extracted and localized ~90 hardcoded strings across `home_screen.dart`, `owner_history_screen.dart`, `employee_jobs_screen.dart`, and `settings_screen.dart`. Added keys to `app_en.arb` and natural Egyptian colloquial Arabic translations (`ar_EG`) in `app_ar.arb`. Ran `flutter gen-l10n`.
- **Commit SHA**: ``13a554168c2c358079ce5b806352d931f84e61b2``
- **Verification**: Verified via `flutter analyze` (0 issues found), `flutter test` (167/167 pass 100%), live backend health check (`https://api.logiclinkeg.tech/health` -> `{"status":"ok"}`), and `.githooks/pre-push` gate passing cleanly. ✅

## /users/services/update HTTP Method Restriction & PATCH /auth/user Docgen Registration

- **Implementation Detail**: Restricted `/users/services/update` route in `services/user-service/internal/handlers/handlers.go` to HTTP `POST`, `PUT`, and `PATCH` methods (returning 405 Method Not Allowed for GET/DELETE/etc). Extended AST route parser in `shared/infra/docgen/generator.go` to handle `http.MethodPatch` selector expressions and added `PUT/PATCH /users/services/update` and `PATCH /auth/user` entries to `KnownEndpoints`. Regenerated `docs/APPLICATION_MAP.md` via `make docs` and confirmed `PATCH /auth/user` and `/users/services/update` appear in generated application map without TODOs.
- **Commit SHA**: ``d43b5ecf997c1758fda7940debdd2c2dff846954``
- **Verification**: Verified via `gofmt -w .`, `go build ./...`, `go vet ./...`, `go test ./...`, and `make docs-check`. ✅

## LocationPickerMap Dialog & Dropdown Sizing Mobile Overflow Fix

- **Implementation Detail**: Fixed fixed-size container overflow (`width: 500, height: 550`) in `_openLocationPickerDialog` inside `customer_marketplace_screen.dart`. Replaced fixed dimensions with dynamic `MediaQuery` viewport calculations (`dialogWidth = screenSize.width > 600 ? 500.0 : screenSize.width * 0.92`, `dialogHeight = screenSize.height > 700 ? 550.0 : screenSize.height * 0.85`) with `insetPadding: const EdgeInsets.all(AppSpacing.md)`. Wrapped header title `Text` in `Expanded` to prevent horizontal header overflow on small viewports. Added `isExpanded: true` to Category and Sort By `DropdownButtonFormField` widgets to prevent dropdown item text overflow. Added explicit 360x800 mobile viewport regression tests in `customer_marketplace_screen_test.dart` and 330x480 narrow container tests in `location_picker_map_test.dart`.
- **Commit SHA**: ``e82cbf79a6db429bc1bfcf9c2a3bd116925f7f5a``
- **Verification**: Verified via `flutter analyze` (0 issues found), `flutter test` (119/119 full test suite pass cleanly including 360x800 mobile viewport regression tests), and `make docs-check`. ✅

## ProposePrice Concurrency Race Test Assertion Flakiness Fix

- **Implementation Detail**: Resolved flaky test assertion in `TestProposePrice_ConcurrencyRace_OverwrittenProposalPrevention` (`services/user-service/internal/handlers/negotiation_concurrency_test.go`). Production data integrity and atomic CAS write in `store.UpdateJobPriceProposal` (`{_id, status, proposed_price: nil}`) were verified as 100% correct (preventing any double-proposals, `successCount == 1` always held). However, the test assertion previously rejected HTTP 400 `proposal_already_submitted` rejections occurring when the losing concurrent goroutine executed an early non-atomic snapshot read before hitting the CAS path. Updated the test assertion to accept either valid rejection outcome (400 `proposal_already_submitted` or 409 `job_state_changed`), and added an explanatory comment above the early non-atomic read in `services/user-service/internal/handlers/handlers.go` clarifying that atomic CAS enforcement remains the authoritative protection mechanism. No production handler logic or business behavior was changed.
- **Commit SHA**: ``ecec165c399b7c70f0c04991c0c5c402a1fdfffc``
- **Verification**: Verified via `go test ./services/user-service/...` passing 100% cleanly and `go test ./services/user-service/internal/handlers/... -run TestProposePrice_ConcurrencyRace_OverwrittenProposalPrevention -count=20 -race` passing 20 consecutive iterations with 0 failures. ✅

## Forgot Password Consolidation Dead Code Cleanup

- **Implementation Detail**: Removed unused `ResetPasswordScreen` (`frontend/lib/screens/reset_password_screen.dart`) left behind after consolidating the forgot password flow into a single-step screen in commit `f2495a3...`. Updated `docs/frontend/STATUS.md` and `docs/frontend/ARCHITECTURE.md` to keep documentation and docgen verification tests in sync.
- **Commit SHA**: ``bbd869d891205089877a5f1e0a46a2e6814360ca``
- **Verification**: Verified via `grep` confirming 0 remaining references, `flutter analyze` passing with 0 issues, and `flutter test` passing 106/106 tests cleanly. ✅

## Deferred User Account Creation Until OTP Verification & IsConfirmed Removal Fix

- **Implementation Detail**: Fixed permanent login block for confirmed accounts and restructured owner/user registration flow. User accounts for `RoleOwner` and `RoleUser` are now stored in a dedicated `pending_signups` MongoDB collection (encrypted with AES-256-GCM and 5-minute expiry) during `Signup`. Accounts are persisted to the `users` collection only when `VerifyOTP` succeeds, making DB existence inherently mean "confirmed" and eliminating the redundant `IsConfirmed` field across models, store methods, handlers, and unit tests. Employee signups remain immediate and auto-confirmed. Fixed abandoned signups by overwriting existing pending records for the same email during subsequent signup attempts.
- **Commit SHA**: ``c9e27c4a322ed7725af7454f692f6b51184a2d91``
- **Verification**: Verified via `go test ./...` across all Go microservices passing cleanly, including 4 new unit test cases covering abandoned signup overwrites, confirmed user login after JWT expiry, 5-minute pending signup expiration, and wrong OTP failures without user creation. ✅

## UpdateJobLocation `requireTier` Error Branch Missing Return Fix

- **Implementation Detail**: Resolved a critical control-flow defect in `user-service` (`UpdateJobLocation` in `services/user-service/internal/handlers/handlers.go`). When `requireTier` returned a non-`ErrUpgradeRequired` internal error, the handler invoked `clearInFlight()` and `writeJSON(w, http.StatusInternalServerError, ...)` but lacked a `return` statement. This missing return allowed execution to fall through to speed checks and database persistence, attempting to process the update and write a second HTTP 200 response header. This single root cause explained two symptoms: (1) security control-flow bypass where 500 error responses continued execution, and (2) concurrent race test failure (`UpdateJobLocation_Throttle_Concurrent_Race_Handling` getting `[200 200]`) due to `clearInFlight()` releasing the in-flight lock prematurely on fallthrough. Added missing `return` statement immediately following `writeJSON(500)`. Explicitly noted that prior local analysis framing this as an "in-memory path" issue investigated the correct symptom but the wrong layer; the fix belongs in shared control flow. Added regression test `UpdateJobLocation RequireTier InternalError Regression Guard` in `handlers_test.go`.
- **Commit SHA**: ``89d1f0423315851a25479564996b0620a7ce34f6``
- **Verification**: Verified via `go test ./services/user-service/internal/handlers/... -run TestUserServiceHandlers/UpdateJobLocation_Throttle -race -count=20` passing 20 consecutive iterations, `TestUserServiceHandlers/UpdateJobLocation_RequireTier_InternalError_Regression_Guard` passing, and `make ci`. ✅

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

- **Implementation Detail**: Corrected an orphaned commit SHA citation in `AI_CONTEXT.md` under "Verified Android Emulator End-to-End Backend Connectivity". The citation previously referenced an orphaned reflog object (short ref `05b5ca7...`, no longer reachable from branch history) resulting from a local `git commit --amend`, which was caught by CI SHA validation. Updated the entry to cite the real commit (`807f98bbca30bf072824b11892a60af02ff310ba`) that introduced the verification entry.
- **Commit SHA**: ``930c346070c5f866ce0638ab0d091e9abae95e38``
- **Verification**: Verified via local SHA verification loop (`grep -oE '[0-9a-f]{40}' AI_CONTEXT.md docs/changelog/*.md | while read -r line; do sha=$(echo "$line" | cut -d: -f2); if ! git cat-file -e "$sha^{commit}" 2>/dev/null; then echo "BLOCKED: fabricated/non-existent SHA $sha"; fi; done` printed 0 output). ✅

## Android Gradle compileSdk Pinning for AAR Metadata Alignment

- **Implementation Detail**: Resolved Android APK compilation failure caused by AAR metadata requirement mismatch. The transitive dependency `flutter_plugin_android_lifecycle` (v2.0.35, pulled in via `file_picker: ^8.0.0`) requires compiling against Android SDK 36 (`compileSdkVersion 36`), whereas default `flutter.compileSdkVersion` resolved to a lower version. Updated `frontend/android/app/build.gradle.kts` to explicitly pin `compileSdk = 36`. Exact error signature resolved: `checkDebugAarMetadata... Dependency 'flutter_plugin_android_lifecycle' requires 'compileSdkVersion' 36 or higher`. Updated troubleshooting matrix in `frontend/CONNECTING_TO_BACKEND.md`.
- **Commit SHA**: ``c1f00d3d026207acb4f78741afaae121c07afa88``
- **Verification**: Verified via `flutter analyze` (0 issues), `flutter test` (35/35 test suites passing), and local SHA verification check. ✅

## Job Completion Payment Method Distinction (COD vs Non-COD cash_collected Gate)

- **Implementation Detail**: Resolved a financial-logic bug in `completeJob()` (`frontend/lib/providers/employee_jobs_provider.dart` and `frontend/lib/screens/employee_jobs_screen.dart`). Previously introduced in commit `8f20aa6...`, `completeJob()` hardcoded `cash_collected: true` for all job completion requests sent to `POST /users/jobs/complete`. For COD (cash-on-delivery) jobs, the backend handler (`handlers.go:CompleteJob`) checks `cash_collected: true` as an explicit confirmation gate to trigger immediate platform-fee deduction from the tenant owner's wallet. Hardcoding this to `true` automatically triggered fee deduction on COD jobs without verifying cash was physically collected by the employee. Updated `completeJob(String jobId, {bool cashCollected = false})` signature to pass `cashCollected` dynamically based on `job.paymentMethod`. Updated `EmployeeJobsScreen` confirmation dialog copy to differentiate COD jobs (`"Confirm Cash Collection & Complete"` with explicit physical cash collection prompt) vs non-COD jobs (`"Complete Job"`). Updated widget tests in `frontend/test/employee_jobs_screen_test.dart` to verify COD vs non-COD dialog copy and payload parameter distinction. Audit of previous test gap: earlier tests used a single COD job fixture and mocked `completeJob` without inspecting the `cash_collected` payload boolean.
- **Commit SHA**: ``73dc64ca3d34bf45333df400cc1fff336e1cf166``
- **Verification**: Verified via `flutter analyze` (0 issues) and `flutter test` (51/51 test cases passing across all 5 widget test cases covering COD vs non-COD flows). ✅

## Separate WebSocket & Read-Endpoint Rate Limiters from Write-Action Limits

- **Implementation Detail**: Separated overly-restrictive blanket 5-req/min rate limiters into dedicated read and connection limiters to prevent chat lockouts during normal client lifecycle reconnections and smooth out high-frequency data browsing. In `chat-service` (`services/chat-service/internal/handlers/chat.go`), introduced `wsLimiter` (`chat:ws`, 30 req/min) for `GET /chat/ws`, while keeping `HandleCreateTicket` on `limiter` (`chat`, 5 req/min). In `user-service` (`services/user-service/internal/handlers/handlers.go`), introduced `readLimiter` (`user:read`, 30 req/min) for read-heavy endpoints (`GetOwnerJobs`, `GetCustomerJobs`, `GetLedger` at both call sites, `GetRatings`, `GetReconciliationQueue`), while preserving 5 req/min write limits on `WalletDeposit`, `RateJob`, `CancelJob`, `ProposePrice`, `RespondPrice`, `TrackJob`, and `ResolveReconciliation`.
- **Commit SHA**: ``131a8a8133b8a4b7f58ada9a92cb0ed0cc0e6e96``
- **Verification**: Verified via unit test suites in `chat-service` (`TestHandleWebSocket_RateLimiting`) and `user-service` (`TestGetJobsByOwner`, `TestGetJobsByCustomer`, `TestRateJob_RateLimiting`, `TestGetLedger_RateLimiting`, `TestGetReconciliationQueue`), `gofmt`, `go build`, and `go vet`. ✅





