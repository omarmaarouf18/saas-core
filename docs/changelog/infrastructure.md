# Infrastructure & Tooling Changelog

This file tracks historical entries for the primary category: **Infrastructure & Tooling Changelog**.

---

## KYC Approval CLI Tool

- **Implementation Detail**: Created out-of-band CLI tool to approve or reject owner KYC documents, verifying user role/state and prompting for confirmation before writing.
- **Commit SHA**: ``current``
- **Verification**: Verified via unit and integration tests. ✅

## Automated Test Coverage

- **Implementation Detail**: Added table-driven and integration unit tests covering bcrypt hashing, rate limiter lockout, OTP expiry in auth-service, KYC gating, COD validation, subscription matching in user-service, and websocket channel access control in chat-service.
- **Commit SHA**: ``current``
- **Verification**: Verified via `go test` in all three services. All 3 suites pass successfully (16 total integration/unit test cases, 0 skipped). ✅

## Host Ports Stripping

- **Implementation Detail**: Removed host port exposures for internal services in docker-compose.yml, replacing with expose.
- **Commit SHA**: ``current``
- **Verification**: Verified docker-compose.yml configuration. ✅

## OTP AES Key Configuration

- **Implementation Detail**: Added OTP_AES_KEY variable to docker-compose.yml, .env.example, and .env.local.
- **Commit SHA**: ``current``
- **Verification**: Verified environment configurations. ✅

## CI Integration (MongoDB & Redis)

- **Implementation Detail**: Configured MongoDB and Redis service containers in GitHub Actions to enable full, non-skipped execution of microservice integration tests.
- **Commit SHA**: ``current``
- **Verification**: Verified via workflow configuration. ✅

## Gitignore Precision Fix

- **Implementation Detail**: Added precise root-level /cmd ignore rule to `.gitignore` to prevent stray binaries from being tracked while keeping sub-level cmd directories tracked.
- **Commit SHA**: ``current``
- **Verification**: Verified using git check-ignore. ✅

## JWT Util Extraction

- **Implementation Detail**: Consolidated duplicate `jwt.go` files across auth, chat, notification, and user services into `shared/infra/jwtutil`.
- **Commit SHA**: ``current``
- **Verification**: Verified via compilation and test execution. ✅

## Support Agent Onboarding CLI Tool

- **Implementation Detail**: Created out-of-band CLI tool to onboard support agents, generating secure tokens and preventing running attack surface on chat-service.
- **Commit SHA**: ``current``
- **Verification**: Verified via unit and integration tests. ✅

## limiter/security_logs Dedup

- **Implementation Detail**: Extracted duplicate `limiter.go` and `security_logs.go` implementation from microservices into shared `infra/handlerutil`.
- **Commit SHA**: ``current``
- **Verification**: Verified via test execution. ✅

## api-gateway Test Coverage

- **Implementation Detail**: Added comprehensive unit/integration test coverage proving route matching, rate limiting, and security header stripping/injection in api-gateway.
- **Commit SHA**: ``current``
- **Verification**: Verified via test execution. ✅

## shared/infra in CI Matrix

- **Implementation Detail**: Added shared/infra to .github/workflows/ci.yml test matrix using path-based working directories to ensure shared module changes are tested on every PR/push.
- **Commit SHA**: ``current``
- **Verification**: Verified via workflow configuration. ✅

## auth-service Test Coverage

- **Implementation Detail**: Added comprehensive integration tests for Signup, Login, VerifyOTP, ToggleEmployee, SimulateEmployeeAction, GetUser, and Refresh handlers.
- **Commit SHA**: ``current``
- **Verification**: Verified via test execution. ✅

## chat-service Test Coverage

- **Implementation Detail**: Added comprehensive integration tests for HandleWebSocket (failure paths), BroadcastLocation, and HandleCreateTicket handlers.
- **Commit SHA**: ``current``
- **Verification**: Verified via test execution. ✅

## notification-service Test Coverage

- **Implementation Detail**: Added comprehensive integration tests for SSE Stream and verifyAndResolve handlers.
- **Commit SHA**: ``current``
- **Verification**: Verified via test execution. ✅

## user-service Test Coverage

- **Implementation Detail**: Added comprehensive integration tests for ListServices, GetWallet, GetLedger, GetPlatformConfig, and GetRatings handlers.
- **Commit SHA**: ``current``
- **Verification**: Verified via test execution. ✅

## Consolidated Token Helper

- **Implementation Detail**: Pulled duplicate cryptographically secure token generation into shared/infra/jwtutil.
- **Commit SHA**: ``current``
- **Verification**: Verified via test execution. ✅

