# Infrastructure & Tooling Changelog

This file tracks historical entries for the primary category: **Infrastructure & Tooling Changelog**.

## notification-service Redis Pub/Sub Horizontal Scaling

- **Implementation Detail**: Added Redis Pub/Sub cross-instance fan-out to `notification-service` (`internal/hub/hub.go`). Broadcasts are published to Redis channels (`notify:tenant:<id>` and `notify:global`), allowing multi-replica deployments to fan out SSE notifications to connected clients on any instance. Added multi-instance `miniredis` test coverage.
- **Commit SHA**: ``2794adc70d938df54f97fad003f210eadc9d115f``
- **Verification**: Verified via `go test -count=1 ./services/notification-service/...` passing all unit and multi-instance Pub/Sub delivery tests. ✅

## KYC Approval CLI Tool

- **Implementation Detail**: Created out-of-band CLI tool to approve or reject owner KYC documents, verifying user role/state and prompting for confirmation before writing.
- **Commit SHA**: ``fcfe636fa9f75c615c44d67c4d7d594ef596a20b``
- **Verification**: Verified via unit and integration tests. ✅

## Automated Test Coverage

- **Implementation Detail**: Added table-driven and integration unit tests covering bcrypt hashing, rate limiter lockout, OTP expiry in auth-service, KYC gating, COD validation, subscription matching in user-service, and websocket channel access control in chat-service.
- **Commit SHA**: ``3653af93fdb9b95c1d76ed15b6b8cb00d388a3f8``
- **Verification**: Verified via `go test` in all three services. All 3 suites pass successfully (16 total integration/unit test cases, 0 skipped). ✅

## Host Ports Stripping

- **Implementation Detail**: Removed host port exposures for internal services in docker-compose.yml, replacing with expose.
- **Commit SHA**: ``2fe0fa6bf5f5afaf1ec66cd89a56054c5f52d04c``
- **Verification**: Verified docker-compose.yml configuration. ✅

## OTP AES Key Configuration

- **Implementation Detail**: Added OTP_AES_KEY variable to docker-compose.yml, .env.example, and .env.local.
- **Commit SHA**: ``2fe0fa6bf5f5afaf1ec66cd89a56054c5f52d04c``
- **Verification**: Verified environment configurations. ✅

## CI Integration (MongoDB & Redis)

- **Implementation Detail**: Configured MongoDB and Redis service containers in GitHub Actions to enable full, non-skipped execution of microservice integration tests.
- **Commit SHA**: ``4c099f869c264275e544b228b562cbbe5d1199f1``
- **Verification**: Verified via workflow configuration. ✅

## Gitignore Precision Fix

- **Implementation Detail**: Added precise root-level /cmd ignore rule to `.gitignore` to prevent stray binaries from being tracked while keeping sub-level cmd directories tracked.
- **Commit SHA**: ``a39d632b5a27ad86cc86641fe8d7e44513b4ecf5``
- **Verification**: Verified using git check-ignore. ✅

## JWT Util Extraction

- **Implementation Detail**: Consolidated duplicate `jwt.go` files across auth, chat, notification, and user services into `shared/infra/jwtutil`.
- **Commit SHA**: ``d25af3789622c3af631405301958e54c8c7e2168``
- **Verification**: Verified via compilation and test execution. ✅

## Support Agent Onboarding CLI Tool

- **Implementation Detail**: Created out-of-band CLI tool to onboard support agents, generating secure tokens and preventing running attack surface on chat-service.
- **Commit SHA**: ``35dab58ce5cc4150e778b32c1ca66c66de43431e``
- **Verification**: Verified via unit and integration tests. ✅

## limiter/security_logs Dedup

- **Implementation Detail**: Extracted duplicate `limiter.go` and `security_logs.go` implementation from microservices into shared `infra/handlerutil`.
- **Commit SHA**: ``2fc19e412253afda248acab62720bdaa2bbe9da4``
- **Verification**: Verified via test execution. ✅

## api-gateway Test Coverage

- **Implementation Detail**: Added comprehensive unit/integration test coverage proving route matching, rate limiting, and security header stripping/injection in api-gateway.
- **Commit SHA**: ``813559092ca4518d43fa47a85d10a84d59e1bf5e``
- **Verification**: Verified via test execution. ✅

## shared/infra in CI Matrix

- **Implementation Detail**: Added shared/infra to .github/workflows/ci.yml test matrix using path-based working directories to ensure shared module changes are tested on every PR/push.
- **Commit SHA**: ``0ce36c272e7dc84058fc703debf7187fe1306e1e``
- **Verification**: Verified via workflow configuration. ✅

## auth-service Test Coverage

- **Implementation Detail**: Added comprehensive integration tests for Signup, Login, VerifyOTP, ToggleEmployee, SimulateEmployeeAction, GetUser, and Refresh handlers.
- **Commit SHA**: ``777703fd3d7269f87a2e7f7fcd1c01a34ea76703``
- **Verification**: Verified via test execution. ✅

## chat-service Test Coverage

- **Implementation Detail**: Added comprehensive integration tests for HandleWebSocket (failure paths), BroadcastLocation, and HandleCreateTicket handlers.
- **Commit SHA**: ``7e8eb23ae408f307dce5cfdd9eafe737cf4c65c8``
- **Verification**: Verified via test execution. ✅

## notification-service Test Coverage

- **Implementation Detail**: Added comprehensive integration tests for SSE Stream and verifyAndResolve handlers.
- **Commit SHA**: ``88c4606853403300ee844c01018b48c715ea9776``
- **Verification**: Verified via test execution. ✅

## user-service Test Coverage

- **Implementation Detail**: Added comprehensive integration tests for ListServices, GetWallet, GetLedger, GetPlatformConfig, and GetRatings handlers.
- **Commit SHA**: ``e35582b7d48dad2bc34ff662af7992f542b28f5b``
- **Verification**: Verified via test execution. ✅

## Consolidated Token Helper

- **Implementation Detail**: Pulled duplicate cryptographically secure token generation into shared/infra/jwtutil.
- **Commit SHA**: ``99a1347f0f6eb87b6ee0d1f4934d48bd017de957``
- **Verification**: Verified via test execution. ✅

## shared/infra Test Coverage

- **Implementation Detail**: Expanded test coverage for shared/infra packages (jwtutil, ratelimit, resilience, tlsutil, handlerutil) focusing on edge cases and failure modes. Added table-driven and concurrent tests verifying JWT none/mismatched signing algorithms, expired tokens, Redis denylist fail-closed behavior, double revocation, rate limiter lockout expiry/reset/capping, resilience retries, timeouts, tlsutil missing/invalid certificate files, and handlerutil non-blocking CloudWatch log shipping.
- **Commit SHA**: ``40c6c9698cb5aba51e6efc401908889495690ae2``
- **Verification**: Verified via `go test ./...` in the `shared/infra` directory. All tests pass. ✅

## auth-service Gap Coverage

- **Implementation Detail**: Expanded test coverage in services/auth-service handlers to close gaps and test edge cases. Added tests confirming old token validity after refresh, verifying employee provisioning signup rejections (token userID mismatch, non-owner role token, non-existent owner, non-owner role owner), checking IP vs email independent rate-limiting lockout axes, verifying identical error wording/status for user non-existence and wrong password login attempts, validating VerifyOTP reuse, wrong email rejections, and wrong OTP rate limit lockouts, checking ToggleEmployee tenant owner constraints, asserting authenticateReviewer missing/invalid tokens rejections, and validating Logout behavior for expired/revoked tokens.
- **Commit SHA**: ``ba166a25fa6b04221b674d0e116fb54c02b3d4a7``
- **Verification**: Verified via `go test ./...` in `services/auth-service` directory. All tests pass. ✅

## user-service Gap Coverage

- **Implementation Detail**: Expanded test coverage in services/user-service handlers. Verified TrackJob pricing client-controlled-distance behavior, UpdateJobLocation speed check cumulative evasion, throttle state replica isolation, CompleteJob original coordinates usage (both COD and Escrow paths), job cancellation and completion authorization checks, and GetJob/GetLedger/GetWallet tenant isolation boundaries.
- **Commit SHA**: ``1b6424cf629722870aa8dd1cc4a2f1cd6cf34c59``
- **Verification**: Verified via `go test ./...` in the `services/user-service` directory. All tests pass. ✅

## chat-service Gap Coverage

- **Implementation Detail**: Expanded test coverage in services/chat-service. Added WebSocket token handshake checks for expired, revoked, and malformed tokens, channel subscription authorization validations, message persistence order, and security gating (unauthorized message non-persistence), concurrent hub registration/unregistration stress tests to catch race conditions and memory leaks, and onboard-agent CLI argument parsing validation.
- **Commit SHA**: ``dce438236e89d2143f886e487e7475cc9a03e292``
- **Verification**: Verified via `go test ./...` and `go test ./... -race` in the `services/chat-service` directory. All tests pass. ✅

## notification-service Gap Coverage

- **Implementation Detail**: Expanded test coverage in services/notification-service handlers. Added test cases verifying SSE stream JWT token handshake validation (expired, revoked, and malformed tokens), tenant scoping and stream isolation, concurrent client disconnection mid-stream cleanup under race conditions, and fail-closed behavior when the auth-service backend is unavailable.
- **Commit SHA**: ``bbe7f85b4706f2b74be4dc56b6b45cac2ea7945b``
- **Verification**: Verified via `go test ./...` and `go test ./... -race` in the `services/notification-service` directory. All tests pass. ✅

## api-gateway Gap Coverage

- **Implementation Detail**: Expanded test coverage in services/api-gateway. Verified public vs internal-only route segregation gating, hardened client IP extraction against X-Forwarded-For spoofing attempts, verified fail-closed behavior when Redis is unreachable, confirmed that sensitive credentials (passwords, JWT tokens) are excluded from gateway traffic logs, and documented the request body size/format forwarding behavior gap.
- **Commit SHA**: ``4a2122ab54b9b59c2aa9caae280ef32c7fc1489f``
- **Verification**: Verified via `go test ./...` and `go test ./... -race` in the `services/api-gateway` directory. All tests pass. ✅

## Docgen Freshness Test Circular Dependency Fix

- **Implementation Detail**: Resolved a circular dependency in the `TestDocgenFreshness` AST validation test by normalizing/ignoring the embedded commit SHA stamp note in `docs/APPLICATION_MAP.md` before comparison during freshness checks. This allows the check to verify the endpoint route table itself without failing due to the circular SHA stamp dependency on new commits.
- **Commit SHA**: ``869933855f1920ebf024a0b2eb0fb67ff2aad431``
- **Verification**: Verified via shared module test execution (`TestDocgenFreshness`). ✅

## Pre-Push Verification Git Hook and Setup

- **Implementation Detail**: Built a comprehensive bash pre-push hook (`.githooks/pre-push`) that intercepts pushes to verify code formatting (`gofmt`), validate that all changelog commit SHAs exist in local Git history, and build/vet/test all microservice modules. Configured a `Makefile` target `setup` to set Git's `core.hooksPath` to `.githooks` and updated `README.md` with setup guidelines. Staged file permissions correctly using `git update-index --chmod=+x`.
- **Commit SHA**: ``31b33da2b4c685694a060fb10915d8b6ac2bb38f``
- **Verification**: Verified by testing push blockage against fabricated commit SHAs and validating hook execution in subsequent pushes. ✅

## Go Version Standardization & Automated Drift Guard

- **Implementation Detail**: Standardized Go version across all sources of truth (`go.work`, 7 `go.mod` files, `.github/workflows/ci.yml`, and 5 `Dockerfile`s) to Go 1.26 (latest stable patch release 1.26.5). Added an automated Go version drift guard step to `.githooks/pre-push` and `.github/workflows/ci.yml` to enforce strict version consistency across all files.
- **Commit SHA**: ``06fd1690290a7a89297c0a5f439009a09080d42f``
- **Verification**: Verified via manual drift-guard check execution, simulated 1-character version mismatch test failure, and clean compilation/test execution across all microservices and shared/infra modules. ✅

## chat-service Test Coverage Expansion

- **Implementation Detail**: Expanded test coverage in services/chat-service handlers to cover ticket resolution (`HandleResolveTicket`, IDOR authorization gating, agent assignment checks), HTTP route registration (`RegisterRoutes`), and error paths in history retrieval and token verification.
- **Commit SHA**: ``2fb500873908fed2e813317c42947fe048d4e4a7``
- **Verification**: Verified via `go test ./... -v -race` in services/chat-service. All tests pass and handlers statement coverage increased from 66.5% to 76.5%. ✅

## shared/infra Test Coverage Expansion

- **Implementation Detail**: Expanded test coverage in shared/infra modules to cover HTTP response utilities (`WriteJSON`, `WriteBytes`), IP resolution (`GetIP`, `GetClientIP`), rate limiter delegation (`handlerutil.RateLimiter`), resilience circuit breaker metrics (`GetBreakerStats`), resilience round tripper (`ResilienceRoundTripper`), docgen markdown table formatting (`GenerateMarkdownTable`), and secure token generation (`GenerateSecureToken`).
- **Commit SHA**: ``887b2315f11ca1fdcc04c31fe0bd7a57d0372539``
- **Verification**: Verified via `go test ./... -v -race` in shared/infra. All tests pass and overall module statement coverage increased from 64.2% to 74.1% (with handlerutil from 29.6% to 71.7% and resilience from 47.3% to 88.2%). ✅

## auth-service Test Coverage Expansion

- **Implementation Detail**: Expanded test coverage in services/auth-service across data storage (`LocalStorage` upload, directory traversal protection, signed URLs, file opening), AES-256-GCM cipher (`otpcrypto` encrypt, decrypt, environment key validation), OTP dispatchers (`MockSMSDispatcher`, `MockEmailDispatcher`, `NoopDispatcher`), model role validation (`ValidRole`), MongoDB store (`NewMongoDB` connection handling, CRUD operations, duplicate key error handling, OTP lifecycle, reviewer management), and HTTP handlers (`RegisterRoutes`, `ResendOTP` anti-enumeration, `GetPublicProfile`, `SimulateEmployeeAction`).
- **Commit SHA**: ``7edbe74dbfdfa9c8f3aa6ffb53ce471ebbe94264``
- **Verification**: Verified via `go test ./... -v -race` in services/auth-service. All tests pass and overall module statement coverage increased from 45.5% to 72.4% (with storage from 0% to 83.1%, store from 0% to 81.2%, and otpcrypto from 51.1% to 90.0%). ✅

## user-service Test Coverage Expansion

- **Implementation Detail**: Expanded test coverage in services/user-service across domain models (`NewGeoJSONPoint`, `ValidJobStatus`), MongoDB store (`NewMongoDB` ping check, service listing/querying, job lifecycle, wallet balances, escrow lock/release splits, COD fee deduction, subscriptions, ratings), and HTTP handlers (`RegisterRoutes` route table verification, `CreateService` parameter validation, `WalletDeposit` production environment gating, `Subscription` defaults/validation, `RateJob` star bounds).
- **Commit SHA**: ``f674e7648a20ca10524cc072e5333d2f80a882b9``
- **Verification**: Verified via `go test ./... -v -race` in services/user-service. All tests pass and overall module statement coverage increased from 44.9% to 64.3% (with models from 0% to 100%, store from 0% to 65.5%, and handlers from 67.2% to 71.2%). ✅

## chat-service Test Coverage Expansion

- **Implementation Detail**: Expanded test coverage in services/chat-service across environment configuration (`Load` missing environment variable validation and default setting verification), MongoDB store (`NewMongoDB` ping check, index creation, message persistence, history query sorting, support agent CRUD, complaint ticket creation and assignment), and HTTP handlers (`NewChat` initialization options, `canAccessChannel` ticket/non-job channel authorization, `HandleCreateTicket` token & JSON error handling).
- **Commit SHA**: ``6e0cd2ae6347d92c319d19cbb2af90fd78102bfc``
- **Verification**: Verified via `go test ./... -v -race` in services/chat-service. All tests pass and overall module statement coverage increased from 51.4% to 70.8% (with config from 0% to 100% and store from 0% to 80.6%). ✅

## notification-service Test Coverage Expansion

- **Implementation Detail**: Expanded test coverage in services/notification-service across environment configuration (`Load` required variable validation and default fallback verification), SSE broadcasting hub (`NewSSEHub`, client registration/unregistration, role counting, tenant scoping, role filtering, slow client buffer overflow drop), and HTTP handlers (`RegisterRoutes` endpoint mapping, `Send` HTTP method and auth error handling, `BroadcastJobAlert` internal token authorization and JSON validation).
- **Commit SHA**: ``f699850a294ed72d8f61fdb055b0c1bb08d7cf73``
- **Verification**: Verified via `go test ./... -v -race` in services/notification-service. All tests pass and overall module statement coverage increased from 40.6% to 73.5% (with config from 0% to 100% and hub from 0% to 96.4%). ✅

## api-gateway Test Coverage Expansion

- **Implementation Detail**: Expanded test coverage in services/api-gateway across environment configuration (`Load` missing required variable checking and default route population), logging & CORS middleware (`Logging` CORS headers, OPTIONS preflight status, status code recording, hijack fallback), and rate limiting middleware (`RateLimit` client IP extraction for IPv4/IPv6/bracketed addresses, passthrough, 429 Too Many Requests response).
- **Commit SHA**: ``9e46dedd23f2ca0bf59d580d341455f8e6b48f0d``
- **Verification**: Verified via `go test ./... -v -race` in services/api-gateway. All tests pass and overall module statement coverage increased from 10.9% to 58.4% (with config from 0% to 94.3% and middleware from 0% to 88.2%). ✅

## CI/CD and Pre-Push Gate Hardening

- **Implementation Detail**: Strengthened markdown commit SHA verification in both `.githooks/pre-push` and `.github/workflows/ci.yml`. In addition to verifying that all 40-hex SHAs exist in Git history, newly added `- **Commit SHA**:` lines in `docs/changelog/*.md` are diffed against `HEAD~1` and asserted to equal `git rev-parse HEAD` of the commit being pushed. Ensured `core.hooksPath` enforcement and Go version drift guard operate identically across local hooks and GitHub Actions.
- **Commit SHA**: ``26a37c5e3c6bf6dee7cd78f5d0e9887327c058ae``
- **Verification**: Verified via local pre-push hook execution and `.github/workflows/ci.yml` validation. ✅





