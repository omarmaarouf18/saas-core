# Infrastructure & Tooling Changelog

This file tracks historical entries for the primary category: **Infrastructure & Tooling Changelog**.

---

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



