# Infrastructure & Tooling Changelog

This file tracks historical entries for the primary category: **Infrastructure & Tooling Changelog**.

## Redis Sentinel High Availability Support & JWT Validation Graceful Degradation

- **Implementation Detail**:
  - **Sentinel-Aware Client Factory (`shared/infra/ratelimit/ratelimit.go`)**: Extended `NewRedisClient(redisURI string)` and added `NewRedisClientFromEnv(redisURI string, getenv func(string) string)` to support Redis Sentinel high availability while preserving 100% backward compatibility for all 5 calling microservices (`api-gateway`, `auth-service`, `chat-service`, `notification-service`, `user-service`). When `REDIS_SENTINEL_ADDRS` is provided (comma-separated list of sentinel nodes), it constructs a failover client via `redis.NewFailoverClient` with `MasterName` (from `REDIS_SENTINEL_MASTER_NAME`, defaulting to `"mymaster"`), `Password` (from `REDIS_PASSWORD` or parsed from `redisURI`), and `SentinelPassword` (from `REDIS_SENTINEL_PASSWORD`), automatically handling master failovers transparently. When `REDIS_SENTINEL_ADDRS` is unset, it falls back to standalone Redis instance connectivity. Updated `infrastructure/.env.example` with Sentinel configuration documentation.
  - **Graceful Degradation & Blip Absorption in JWT Validation (`shared/infra/jwtutil/jwt.go`)**: Refined the fail-closed Redis denylist and per-user token revocation checks in `ValidateToken` to absorb transient network blips and Sentinel failover windows without rejecting valid users or logging them out prematurely. Implemented thread-safe `redisHealthTracker` tracking `lastSuccessTime` and `consecutiveFailures`. When a Redis error occurs during revocation/denylist lookups within the blip tolerance threshold (< 3 consecutive failures and within 5 seconds of last success or initial attempt), `ValidateToken` executes a single immediate retry with a 500ms timeout. If the retry succeeds, it logs `[REDIS] Transient connectivity blip absorbed, ... succeeded on retry` and completes token validation normally. If the retry fails or the sustained failure threshold is exceeded, it preserves the strict security guarantee by failing closed with `[SECURITY CRITICAL]` logs. The write path in `RevokeAllUserTokens` strictly fails loudly without silent degradation.
  - **Automated Regression & Unit Test Suites (`ratelimit_test.go` & `jwt_test.go`)**: Added `TestNewRedisClient_SentinelAndStandaloneBranching` in `ratelimit_test.go` testing standalone fallback, Sentinel configuration parsing, and URI password extraction. Added `TestValidateToken_GracefulDegradation` in `jwt_test.go` verifying that single transient network drops on both denylist and per-user revocation checks are absorbed on retry, genuine sustained outages fail closed preserving security integrity, and write-path revocations fail loudly on Redis outages.
- **Commit SHA**: ``a606943d7760dca45274fff88c0eeafd688326cf``
- **Verification**: Verified via `go test ./...` across all 7 Go modules (100% pass), `go build ./...`, `go vet ./...`, and `gofmt -l .`. ✅

## Client Application Semantic Versioning & Version-Gating Middleware (ADR-0018)

- **Implementation Detail**:
  - **CI/CD Semver Integration (`build-apk.yml`)**: Updated `frontend/.github/workflows/build-apk.yml` to extract `version` directly from `pubspec.yaml` and publish `app-release.json` with real semver `"version"` (e.g. `"1.0.0"`) and `"build_sha"` (e.g. `"ed2afc4"`) fields on `logiclinc`. (Commit ``ed2afc4``).
  - **MongoDB Version Registry & API Gateway `VersionGate` (`api-gateway`)**: Added `platform_versions` MongoDB collection and `version.Store` tracking `latest_version`, `minimum_supported_version`, `enforce_minimum_version`, and `download_url`. Implemented zero-dependency semver parser `version.ParseSemVer` and `middleware.VersionGate` intercepting `X-App-Version` headers. Safe rollout policy allows missing headers during grace period when `enforce_minimum_version == false`, and rejects out-of-date clients with HTTP `426 Upgrade Required` when enforcing. Added admin configuration endpoints `GET / PUT /api/v1/admin/version-config` gated by `X-Internal-Token`. (Commit ``2dcb97e``).
  - **Flutter Header Injection & HTTP 426 Global Interception (`frontend`)**: Integrated `package_info_plus` in `pubspec.yaml`, injected `X-App-Version` into all `ApiClient` requests, and intercepted HTTP 426 responses globally to trigger `onUpdateRequired` callback displaying `UpdateRequiredScreen` (`update_required_screen.dart`). Added unit/widget tests in `api_client_version_test.dart` and `update_required_screen_test.dart`. Updated `docs/frontend/STATUS.md`. (Commit ``34915b7``).
  - **Architectural Documentation**: Authored [ADR-0018](docs/adr/0018-client-app-semantic-versioning-and-enforcement-gate.md) and updated `docs/DEPLOYMENT.md` Section 11.3.
- **Commit SHA**: ``34915b76e3b4f0e106fc66c1ce814cba4fdec9ea``
- **Verification**: Verified via `go test ./...` in `api-gateway` (100% pass), `flutter analyze` (0 issues), `flutter test` (191/191 pass), `make ci`, `make docs-check`, and `.githooks/pre-push` gate exit code 0. ✅

## Strict CD Rollback Hardening & Post-Rollback Health Verification (ADR-0015)

- **Implementation Detail**: Remediated silent failure vulnerabilities in `infrastructure/deploy/deploy.yml`'s "Rollback on Health Failure" step:
  - Added `set -euo pipefail` to ensure command failures halt workflow step execution immediately.
  - Hardened missing previous commit check (`if ! git show HEAD~1:docker-compose.yml > /dev/null 2>&1`), outputting `::error::Cannot rollback — no previous commit in git history. Manual intervention required immediately.` and exiting with code 1.
  - Added explicit status check on `docker compose up -d --force-recreate --remove-orphans`, logging `::error::ROLLBACK COMMAND ITSELF FAILED — manual intervention required immediately` and exiting 1 on failure.
  - Integrated `verify_service_health` re-verification loop (12 attempts * 5s) against restored containers. Only logs success if post-rollback health checks pass.
  - Logged distinct critical alert `::error::CRITICAL: ROLLBACK FAILED HEALTH CHECK TOO — service is down, manual intervention required NOW` and exited 1 if post-rollback health checks fail.
  - Updated [ADR-0015](docs/adr/0015-strict-cd-preflight-validation.md) with post-audit addendum.
- **Commit SHA**: ``b2b2a380b977582a11989e8e767e597f13b18087``
- **Verification**: Verified via Python YAML syntax parser, shell execution flow trace, `make docs-check`, `.githooks/pre-push` gate, and full git audit. ✅

## Standardized Graceful Shutdown Protocol Across All 5 Microservices

- **Implementation Detail**: Extended graceful shutdown handling to `api-gateway`, `chat-service`, and `notification-service`, unifying all 5 microservices on the canonical pattern from `auth-service` and `user-service`. On receiving `SIGINT` or `SIGTERM`, each service logs `[<SERVICE_TAG>] Shutting down...` and executes `http.Server.Shutdown()` with a 10-second context timeout. Enhanced `Hub.Close()` in `chat-service` to iterate over active clients and close outbound `Send` channels, triggering `writePump` to transmit normal WebSocket close frames (`websocket.CloseMessage`) before closing socket connections. Enhanced `SSEHub.Close()` in `notification-service` to close active `Send` channels across `SSEHub.clients`, ensuring streaming handler loops terminate cleanly alongside HTTP context cancellation (`r.Context()`).
- **Commit SHA**: ``62c269a4079a10b2511024b6c827838c6b16c568``
- **Verification**: Verified via `go build` and `go vet` across all 7 Go modules, 100% pass across all unit and handler test suites (`go test ./...`), empirical SIGTERM test executions confirming graceful shutdown logs (`[GATEWAY] Shutting down...`, `[CHAT] Shutting down...`, `[NOTIF] Shutting down...`), and `.githooks/pre-push` gate. ✅

## Strict CD Pre-Flight Validation, Structural Sync & Rollback (ADR-0015)

- **Implementation Detail**: Added `--check-env` pre-flight validation flag across all 5 Go microservices (`api-gateway`, `auth-service`, `chat-service`, `notification-service`, `user-service`) running `config.Load()` and exiting 0/1 without starting the HTTP server or requiring DB/TLS cert files. Created production reference files in `infrastructure/deploy/` (`docker-compose.prod.yml` containing canonical environment variable blocks and `deploy.yml` featuring pre-flight validation, all-5-service health checks, health-gated rollback to prior `docker-compose.yml`, and `.env` symlink unification). Rewrote `update-deployment-repo` job in `.github/workflows/build-and-publish.yml` to execute full structural sync from `infrastructure/deploy/` to `omarmaarouf18/saas-core-deploy` (eliminating env block drift). Authored [ADR-0015](docs/adr/0015-strict-cd-preflight-validation.md) documenting root causes of 3 real production incidents from 2026-08-06.
- **Commit SHA**: ``8f768a08059af871c2885ce143c7520685a84741``
- **Verification**: Verified via `--check-env` exit code 1 failure test on missing required env vars, exit code 0 success test with required env vars, YAML syntax validation across all workflow and compose files, `make ci` execution, and cross-repository automated sync pipeline. ✅

## Database-per-Service Microservice Isolation (Finding #8)

- **Implementation Detail**: Enforced strict logical database isolation per microservice to resolve shared-database tight coupling (`MONGO_INITDB_DATABASE=saas_platform`). Updated default database name fallback in `auth-service` (`services/auth-service/internal/config/config.go`) to `auth_db` and in `user-service` (`services/user-service/internal/config/config.go`) to `user_db`. Restructured `infrastructure/.env.example`, `infrastructure/.env`, `infrastructure/.env.local`, and `infrastructure/docker-compose.yml` to pass dedicated environment variables (`AUTH_MONGO_DATABASE=auth_db`, `USER_MONGO_DATABASE=user_db`, `CHAT_MONGO_DATABASE=chat_db`). Updated `docs/DEPLOYMENT.md` and `docs/RUNBOOK.md` noting the database separation, documenting that pre-production deployments must be reset (booting fresh empty `auth_db` and `user_db` databases), and specifying that future database structure changes once live production data exists require a formal `mongodump`/`mongorestore` data migration script.
- **Commit SHA**: ``2553814de9be4162c34e367c3acb97eeb11c39e9``
- **Verification**: Verified via `TestLoad_MongoDatabaseDefaults` in `auth-service` and `user-service` config tests, fresh-boot store initialization & smoke test on separate `auth_db` and `user_db` databases, `go build ./...`, `go vet ./...`, `go test ./services/auth-service/...`, and `go test ./services/user-service/...`. ✅

## Single Source of Truth for Production `.env` (ADR-0012)

- **Implementation Detail**: Documented real production incident on `quickdelivery-vm` caused by dual `.env` files (`~/azureuser/saas-core-deploy/.env` vs `/home/deploybot/.env`). The self-hosted GitHub Actions runner (`saas-vm-runner`) restores its working environment from `/home/deploybot/.env` (a cross-run persistent backup). Because `/home/deploybot/.env` lacked `RESEND_API_KEY` and `RESEND_FROM_EMAIL`, every automated CD deployment auto-triggered on pushes to `main` silently restored `/home/deploybot/.env` and force-recreated containers, overriding manual operator SSH edits and silently reverting `auth-service`'s OTP delivery mechanism from `Resend` to `MockSMS`. Additionally, differing `MONGO_INITDB_ROOT_PASSWORD` definitions between the two `.env` files triggered `SCRAM authentication failed` errors. Established `/home/deploybot/.env` as the single canonical source of truth for production environment variables per ADR-0012, updated `docs/DEPLOYMENT.md` Troubleshooting section 10.7 with root cause analysis and manual remediation steps, and added a recommended CD safeguard follow-up to fail loudly if critical keys are missing.
- **Commit SHA**: ``f819ce30f46e19a5761d441f90c9da9929ce6c65``
- **Verification**: Verified via `make ci` (0 issues found, all Go tests passing including `TestChangelogCommitSHAs`, `make docs-check`, `gofmt`, `govulncheck`, `gosec`, `flutter analyze`), `docs/adr/0012-single-source-of-truth-for-production-env.md` validation, and manual verification against `saas-core-deploy/.github/workflows/deploy.yml`. ✅


## Resend Email OTP Delivery End-to-End Verification

- **Implementation Detail**: Configured and verified real end-to-end email OTP dispatching via `ResendDispatcher` (`github.com/resend/resend-go/v3`) using live Resend API infrastructure and verified domain `logiclinkeg.tech` (`info@logiclinkeg.tech`). Updated `infrastructure/docker-compose.yml` to inject `RESEND_API_KEY` and `RESEND_FROM_EMAIL` into `auth-service`. Verified full lifecycle: signup (`POST /api/v1/auth/signup`) dispatched live email via Resend API (`Resend email ID: 3f0843d1-5682-455d-9ebe-00fcec6590be`), suppressed `dev_otp` in non-local environment (`APP_ENV=production`), stored AES-256-GCM encrypted OTP ciphertext at rest in MongoDB (`otp_code`), delivered email OTP, completed 2FA authentication via `POST /api/v1/auth/verify-otp` (HTTP 200 OK + JWT issued), and confirmed graceful error logging on invalid API key (`[RESEND] Error dispatching OTP email ... API key is invalid`) without crashing `auth-service`.
- **Commit SHA**: ``08017f437e76bb6ce71674c2fdf310365387f9d8``
- **Verification**: Verified end-to-end via `curl` requests against local `docker-compose` stack (`api-gateway` + `auth-service`), Mongo ciphertext inspection, AES-256-GCM OTP decryption, and successful 2FA JWT issuance. ✅


## user-service Redis-Backed Location Update Throttle

- **Implementation Detail**: Replaced in-process Go maps (`locationInFlight` and `locationLastUpdate`) in `user-service` (`UpdateJobLocation` in `services/user-service/internal/handlers/handlers.go`) with Redis-backed atomic key evaluation (`loc:inflight:<job_id>` with 15s TTL and `loc:lastupdate:<job_id>` with 300s TTL) executed via an atomic Lua script. Added fail-closed logging (`[SECURITY CRITICAL]`) on Redis errors, preserved in-memory fallback for nil-Redis environments, updated ADR-0005 with a dated correction note, and added multi-instance test coverage (`TestUpdateJobLocation_RedisBackedThrottle_MultiInstance`).
- **Commit SHA**: ``24b10339f37342e4280bdc9d32099bb44e5a7fba``
- **Verification**: Verified via `go test ./services/user-service/... -v -race -count=1` passing all 100+ tests including `UpdateJobLocation Throttle Error Rollback` and `TestUpdateJobLocation_RedisBackedThrottle_MultiInstance`. ✅


## chat-service Redis Pub/Sub Horizontal Scaling

- **Implementation Detail**: Implemented dynamic per-channel Redis Pub/Sub horizontal scaling in `chat-service` (`internal/chat/hub.go`). Hub dynamically subscribes to `chat:channel:<name>` on the first local client join and unsubscribes on the last local client leave. Published messages undergo immediate in-process delivery on the origin instance plus Redis `Publish()` for remote replica fan-out, using `OriginInstanceID` tagging to eliminate self-loopback de-duplication latency. Added multi-instance `miniredis` test coverage.
- **Commit SHA**: ``203111290514c71a25de3ada16bd43a46fac8f68``
- **Verification**: Verified via `go test -count=1 ./services/chat-service/...` passing all unit and multi-instance Pub/Sub delivery tests. ✅

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

## Two-Repo Deployment Pipeline & GHCR Build/Publish Workflow Setup

- **Implementation Detail**: Created separate private production deployment repository `omarmaarouf18/saas-core-deploy` containing image-based `docker-compose.yml`, production `.env.example`, `Caddyfile`, and README. Created `.github/workflows/build-and-publish.yml` in primary repo (`saas-core`) triggering on push to `main` to build all 5 microservices' `prod` stage Docker images, publish them to GitHub Container Registry (`ghcr.io/omarmaarouf18/saas-core-<service>:${SHA}` and `:latest`), and update `saas-core-deploy` image references using `DEPLOY_REPO_PAT`. Updated service Dockerfiles (`api-gateway`, `auth-service`, `chat-service`, `notification-service`, `user-service`) for root-context compilation resolving `shared/infra`. Updated `docs/DEPLOYMENT.md` with two-repo architecture and production setup commands.
- **Commit SHA**: ``bbdaaa6b508061e9300e154b8a347358898e064d``
- **Verification**: Verified via local Docker `prod` stage builds, successful creation and initial commit push to `omarmaarouf18/saas-core-deploy` (`main` branch), `make docs-check`, and `.githooks/pre-push` gate passing 100%. ✅

## Standalone Mobile Frontend Repository & Hot-Swap Auto-Sync Pipeline

- **Implementation Detail**: Created dedicated private GitHub repository `omarmaarouf18/quick-delivery-mobile` for the Flutter mobile client, extracted from `frontend/` via `git subtree split --prefix=frontend` while preserving full commit history and authorship. Authored `frontend/README.md`, `frontend/docs/CI_CD.md`, and `frontend/.github/workflows/build-apk.yml` in `saas-core` (mapping to root files in `quick-delivery-mobile`). Added `.github/workflows/sync-mobile-frontend.yml` in `saas-core` triggering on push to `main` and `logic-exploitation` branches touching `frontend/**` to extract subtree split and force-push to `quick-delivery-mobile`'s `main` branch using secret `MOBILE_REPO_PAT`. Added `build-apk.yml` in `quick-delivery-mobile` compiling release APKs using `subosito/flutter-action` with `API_BASE_URL` variable injection (`vars.API_BASE_URL`) and attaching `app-release-<short_sha>.apk` build artifacts.
- **Commit SHA**: ``21e98385dcfde99a14b0208427f4233560cf0e76``
- **Verification**: Verified via `git subtree split`, initial remote push to `quick-delivery-mobile`, `make docs-check`, and `.githooks/pre-push` gate passing 100%. ✅

## Containerized Caddy TLS Reverse Proxy Integration in Docker Compose Stack

- **Implementation Detail**: Resolved the "Production Caddy Orphan Container Incident" where Caddy was running outside Docker Compose via an un-orchestrated manual `docker run` command on the production VM (`quickdelivery-vm`) and suffered proxy failures from loopback address targeting (`127.0.0.1:8080`). Added a `caddy` service block (`image: caddy:2-alpine`, `container_name: saas-caddy`, `restart: unless-stopped`, ports `80:80`/`443:443`/`443:443/udp`) to `infrastructure/docker-compose.yml` on `saas-net` network with `api-gateway:8080` upstream target and volume mounts (`./Caddyfile:/etc/caddy/Caddyfile:ro`, `caddy_data:/data`, `caddy_config:/config`). Updated `docs/DEPLOYMENT.md` to remove manual `docker run` instructions in favor of unified `docker compose up -d` stack management. Authored `docs/adr/0011-containerized-caddy-in-compose-stack.md`.
- **Commit SHA**: ``ef4bd21b7a0c2d1e721027c5d1852b77cf7b42c7``
- **Verification**: Verified via `make ci` gate, `make docs-check`, and `docker compose config` syntax validation. ✅

## Production Dockerfile Curl Installation & Health Check Fallback

- **Implementation Detail**: Resolved deployment health check failure where `docker exec <container> curl` failed because production stage Dockerfiles (`FROM alpine:3.20 AS prod`) lacked `curl` package. Updated `RUN apk --no-cache add ca-certificates` to `RUN apk --no-cache add ca-certificates curl` across all 5 microservices' Dockerfiles (`api-gateway`, `auth-service`, `chat-service`, `notification-service`, `user-service`). Updated `infrastructure/deploy/deploy.yml` post-deploy health check step to support both `curl` and `wget` HTTP status verification against `https://localhost:${PORT}/health`.
- **Commit SHA**: ``4a1bd377352e426352bd704b4a8795530b589b7b``
- **Verification**: Verified via Dockerfile builds, changelog commit SHA verification, and pre-push gate. ✅

## Microservices mTLS Health Check Client Certificate Integration

- **Implementation Detail**: Resolved deployment health check failure where internal microservices (`auth-service`, `chat-service`, `notification-service`, `user-service`) returned `HTTP 400` during health checks due to mandatory mutual TLS (`tls.RequireAndVerifyClientCert`). Updated `infrastructure/deploy/deploy.yml` post-deploy health check step to pass mounted mTLS client certificates (`--cert /app/certs/${SVC}.crt --key /app/certs/${SVC}.key`) on initial HTTPS check, with fallback to non-mTLS HTTPS and HTTP.
- **Commit SHA**: ``8e552163daa90cccd34eb849fa3188f311a40285``
- **Verification**: Verified via `shared/infra` changelog tests, pre-push gate, and local TLS check. ✅








## Frontend Composition-Layer Gate (P5 CI Enforcement)

- **Implementation Detail**:
  - Created `scripts/frontend_composition_gate.sh`: rejects `Scaffold(`, `AppBar(`, `BoxDecoration(`, `Color(0xFF`, and `.toUpperCase()` inside `frontend/lib/screens/**` (PCRE negative-lookbehind so identifier substrings don't false-positive). Shared widgets (`widgets/**`) and design tokens (`core/theme.dart`) are outside the gated path and remain the single sources of truth.
  - Wired into `.githooks/pre-push` (gate step before flutter analyze/test) and `.github/workflows/ci.yml` (`Frontend Composition Gate` step before Flutter Analyze) preserving the strict hook/CI parity principle.
  - Prevents recurrence of the drift documented in FRONTEND_ARCHITECTURE_PLAN §0 where phases marked "Complete" silently regressed to hardcoded values.
- **Commit SHA**: ``07d4898257bb6bb13502acf9dc4a37ad4ce12fe1``
- **Verification**: Verified via negative audit — injected violation block into `frontend/lib/screens/wallet_screen.dart` produced `BLOCKED: 4 composition-layer rule(s) violated` with exit code 1 listing every hit with file:line; reverting via `git checkout` restored exit code 0. YAML validated with Python yaml.safe_load; hook syntax validated with bash -n. ✅

## Golden Baseline Environment Contract — Root Cause of All Historical Golden CI Failures

**Date**: 2026-08-22
**Category**: Infrastructure / CI Hardening
**Related Commit SHAs**: ``e596b8092a03ed93952877ad718862764690386c`` (pin + deterministic fonts + regen workflow), ``2f8af6d189bab7b397050dc4074916cf17628121`` (self-path trigger bridge)

- **Root Cause (confirmed with literal evidence)**: Every "Flutter Lint & Test" golden failure since goldens were introduced was an environment mismatch, not a code regression. Baselines were generated on the developer machine (Fedora 44, Flutter 3.44.6) while CI installed an UNPINNED stable SDK (`subosito/flutter-action@v2` with only `channel: stable`; literal `FLUTTER_ROOT: /opt/hostedtoolcache/flutter/stable-3.47.1-x64` from failed run 32552945499) on ubuntu-24.04. Two commits on two days produced byte-identical diff numbers because zero baseline bytes changed between them — the diffs were constant engine-version rendering differences.
- **Fix**: (1) `ci.yml` pins `flutter-version: '3.44.6'` with an explanatory comment; (2) new manual `regen-goldens.yml` workflow renders baselines inside the SAME pinned comparator environment and uploads them as a reviewed artifact (least privilege — no token write access); (3) `golden_screens_test.dart` setUpAll preloads the five bundled Poppins TTFs via `FontLoader` so glyph rasterization depends only on the pinned engine, replacing reliance on google_fonts' async path (a global `flutter_test_config.dart` binding-init was attempted first and reverted — it broke suites constructing HTTP clients outside test zones).
- **Diagnostic Finding**: After pinning alone (before any baseline change), CI-rendered baselines were **sha256-identical to all 12 existing repo baselines** (`gh run download` + checksum comparison) — proving the Flutter ENGINE VERSION was the sole failing variable and cross-distro fontconfig contributed nothing for these screens (all text renders from bundled Poppins). Consequently no baseline commit was required; the pre-existing baselines are canonical under the pin.
- **Standing Rule**: any Flutter bump must regenerate goldens in the same change (procedure + rationale documented in `frontend/README.md`, root-cause table in `docs/frontend/STATUS.md`). `workflow_dispatch` on `regen-goldens.yml` becomes available once the file reaches `main`; until then a self-path push trigger fires it when the mechanism itself changes.
- **Verification (GitHub Actions, not local)**: Run 32555159762 on `e596b80` — all 8 CI Gate jobs success including "Flutter Lint & Test", log line `🎉 305 tests passed.`; Run 32555473575 on `2f8af6d` — "Flutter Lint & Test" success. Local suite additionally 305/305 (not counted as verification). ✅

## A3 Test Coverage Pass — P1 Money & P2 Auth Provider Gaps Closed

**Date**: 2026-08-22
**Category**: Infrastructure / Test Coverage
**Related Commit SHA**: ``84bd5aa447099d7cd7bb0a2b26650feb3ebe26d9``

- **Re-runnable auditor**: `scripts/frontend_coverage_audit.py` parses `frontend/coverage/lcov.info` and prints per-file line coverage for screens/providers/widgets/services with risk-tier flags (0% always flagged; floors: 60% money/auth/job-state, 40% presentational).
- **Stale-flag correction**: the previously reported zero-coverage trio was wrong on two counts — `utils/logout_helper.dart` measures **100%**, `screens/chat_screen.dart` **81.5%**; the only true zero is `screens/rating_screen.dart` (still open, P3). The real concentration of risk was PROVIDERS starved by widget tests that mock providers wholesale.
- **Coverage deltas** (line coverage): reconciliation_provider 2.9%→**100%**, employee_jobs_provider 4.3%→**94.3%**, marketplace_provider 18.6%→**89.0%**, auth_provider 25.1%→**75.8%**, core/api_client.dart 24.7%→**63.9%**. Overall audited coverage 69.4%→**73.2%**. Suite 305→**355 tests**.
- **New test infrastructure**: dart:io `HttpClient` fake via `HttpOverrides` (`test/helpers/mock_http_harness.dart`, request recording + canned routing — no production code changes) and a `FlutterSecureStorage` method-channel mock with in-memory store.
- **Behavioral find (documented as contract)**: ALL auth flows surface `ApiClientException.message` verbatim (e.g. "email exists", "invalid OTP") unlike every other provider which routes through `friendlyErrorMessage`. Auth endpoints return safe strings by contract, so this is intentional; asserted in tests to prevent silent drift.
- **Deferred (Still OPEN)**: rating_screen widget suite (P3), map_tracking_provider WebSocket fake layer (P3), notifications/chat providers + low-coverage data models + service_screen (P4 cosmetic/data-class risk only).
- **Verification**: local full suite `flutter test` 355/355 pass; `flutter analyze` No issues found!; coverage re-run literal before/after above. ✅

## A3-P3: rating_screen First Coverage + Two 360dp Layout Bug Fixes

**Date**: 2026-08-22
**Category**: Bug Fix / Test Coverage
**Related Commit SHA**: ``c133f0e4fa32915a7892013f7c4c204b19f9163d``

- **Two real production layout bugs** caught by the screen's first-ever widget tests at its target 360dp width (screen previously had 0% coverage and no golden):
  1. Star selector RenderFlex overflowed **38px right**: five IconButton(44px icon)s each render ~60px wide with default padding/density. Fixed by constraining each to a 44dp square.
  2. Blind-rating info cards overflowed **25/11px bottom**: the 1-column GridView forced `childAspectRatio: 3.5` (~84px tiles) under ~110px of content. Mobile path replaced with an intrinsic-height Column (wide path keeps the 3-column grid).
- **l10n blind-spot find**: CTA used hardcoded `"Submit Rating"` — `PrimaryButton`'s `text:` property was not in the A2 scanner's property list; existing ARB key `ratingSubmitBtn` ('SUBMIT RATING') was sitting unused. Now routed through it.
- **Mock-default cleanup**: leftover Stitch placeholder party defaults ('Marcus J.' / 'Driver / Specialist') replaced with role-neutral labels for the auth-race edge case.
- **Coverage**: rating_screen.dart **0.0% → 92.5%**; overall audited coverage 73.2% → **75.2%**; suite 355 → **361 tests**.
- **Suite**: 6 widget tests covering party determination both directions, blind-status waiting vs locked-in branches, submit payload contract incl. comment trimming, success pop flow, failure snackbar retention, identity guard with zero network calls.
- **Verification**: flutter analyze No issues found!; full suite 361/361 pass locally; CI verification recorded separately in AI_CONTEXT. ✅

## l10n Scanner `text:` Property Gap Closure — 39 Strings Across 11 Files

**Date**: 2026-08-22
**Category**: Bug Fix / Localization
**Related Commit SHA**: ``018c79551f978b3b67b7346b53ee08599d80d515``

- **Gap**: the A2 audit scanner's property list omitted `text:` (PrimaryButton/SecondaryButton/Tab/_buildFeatureRow style params), letting hardcoded CTA/tab-label strings survive despite matching ARB keys existing (e.g. 'Submit Rating' vs unused `ratingSubmitBtn`).
- **Scope found**: 39 production strings across 11 files — job_status_screen CTAs (7), subscription feature lists (9), employee_screen tabs/register (3), marketplace booking dialog (3), kyc upload/replace (2), dialogs Cancel/Confirm/Create (4), plus wallet/home/map/config singles.
- **Remediation**: 9 exact-value REUSES of existing keys + 24 new en+ar keys (`subFreeFeature*`, `subProFeature*`, CTA labels). Post-fix audit: zero non-exception flags (38 remaining = 33 documented accepted exceptions + 5 debug-only component-library literals newly visible to the widened scanner).
- **Hydration-race scan (follow-up)**: rating_screen was the sole stuck-placeholder instance; all other screens read auth at build time (reactive) or use post-frame refreshes. No further action needed.
- **Verification**: flutter analyze No issues found!; full suite 361/361 pass locally. ✅

## Reviewer Console Production Deployment Wiring (ADR-0021)

- **Implementation Detail**: Wired `kyc-reviewer-console` into the production deployment reference files: added a `kyc-reviewer-console` service to `infrastructure/deploy/docker-compose.prod.yml` (image `ghcr.io/omarmaarouf18/kyc-reviewer-console:${KYC_CONSOLE_IMAGE_TAG:-latest}`, built by the console repo's own release workflow since the image originates outside this monorepo's build matrix; loopback-only binding `127.0.0.1:8090:8090` so it is never directly internet-reachable; mTLS client certs mounted from `./certs/reviewer-console.*`; reuses existing shared `INTERNAL_SERVICE_TOKEN`; fail-fast config guard upstream). Added console cert generation to the DEPLOYMENT.md Step 5.3 mTLS loop (`reviewer-console` in SERVICES array), new `KYC_CONSOLE_IMAGE_TAG` env key, Caddy route documentation for the reviewer subdomain with an explicit network-mode-dependent proxy-target note (`kyc-reviewer-console:8090` on saas-net vs `http://127.0.0.1:8090` for host-network sibling), and health verification steps (`/healthz` returns ok; unauthenticated `/api/queue` must 401). Compose syntax validated via the same dummy-env method the sync job uses.
- **Commit SHA**: ``4e317a6c594bbaed6f70519d723be85830cc3619``
- **Verification**: Local: `docker compose --env-file <dummy> -f infrastructure/deploy/docker-compose.prod.yml config --quiet` passes (COMPOSE_SYNTAX_OK). Deployment activation itself is deliberately NOT executed from this commit: production pickup requires (1) saas-core merge to `main` (sync job force-copies the reference compose into saas-core-deploy), (2) operator DNS record for the chosen subdomain, (3) VM-side issuance of `certs/reviewer-console.{crt,key}` against the existing CA, and (4) operator merge of the prepared `saas-core-deploy` branch adding the Caddy route + `.env.example` keys — merging any branch to that repo's `main` triggers CD on the VM.

## Reviewer Console Production Rollout Execution & CD Sync Substitution Fix (ADR-0021)

**Date**: 2026-08-26
**Category**: Infrastructure / Deployment
**Related Commit SHA**: ``29cb138f41252659a112fbc860e343eff5d1f195``

- **Production rollout executed on `quickdelivery-vm`**: issued `certs/reviewer-console.{crt,key}` in the runner-workspace certs dir via the DEPLOYMENT.md §5.3 single-service procedure against the existing internal CA (`SaaS-Root-CA`, 10y, SAN `DNS:reviewer-console, DNS:localhost, IP:127.0.0.1` verified post-signing); pinned `KYC_CONSOLE_IMAGE_TAG=fc85e7b4...` (console repo `main` HEAD, GHCR manifest existence checked first) in canonical `/home/deploybot/.env` (timestamped backup taken); pulled the public GHCR image; installed the console service block into the live workspace `docker-compose.yml` (timestamped backup taken) after proving via `docker compose config` before/after diff that the change was strictly additive; brought the service up with a targeted `up -d kyc-reviewer-console` (no `--remove-orphans`) — every pre-existing container kept its exact uptime (zero restarts).
- **Live verification**: `/healthz` → `ok`; unauthenticated `/api/queue` → `401 {"error":"reviewer token required"}` (console-side gate); invalid-reviewer-token probe → upstream `401 {"error":"unauthorized"}` after a real mTLS round-trip to auth-service (71ms, no TLS errors), proving cert trust + internal-token injection; port published loopback-only (`127.0.0.1:8090`).
- **CD sync bug fixed (`29cb138f41252659a112fbc860e343eff5d1f195`)**: `update-deployment-repo`'s blanket `sed s|IMAGE_TAG|<sha>|g` also mangled the env var NAME inside `${KYC_CONSOLE_IMAGE_TAG:-latest}`, silently breaking image pinning on the first post-merge deploy. Substitution is now colon-prefixed plus a loud guard step failing the sync if `KYC_CONSOLE_IMAGE_TAG` disappears; fix simulated against the reference compose file.
- **DEPLOYMENT.md corrected to match reality**: (1) §5.3 key permissions — documented that `chmod 600 *.key` crash-loops non-root containers whose host file owner differs (observed live: `failed to load TLS keypair ... permission denied`); deployed stack requires `644`. (2) New §8.1 warning documenting the LIVE Caddyfile location on `quickdelivery-vm` (`/home/azureuser/saas-core-deploy/Caddyfile`, mounted into `saas-caddy`; `/opt/saas-platform` and runner-workspace copies hold stale placeholders), the zero-downtime `docker exec saas-caddy caddy reload` procedure, and the require-DNS-before-site-block ACME rate-limit rationale.
- **INTERNAL_SERVICE_TOKEN rotated mid-rollout** (prior value exposed in an operator session transcript): single in-place replacement in `/home/deploybot/.env` (fresh timestamped backup), then config-change-driven rolling recreate of exactly the six consumers (api-gateway, auth-, chat-, notification-, user-service, console) — mongo/redis/caddy untouched. Post-rotation: new token → `200` on `GET /api/v1/admin/version-config`, old token → rejected, public gateway health and gateway→auth proxy path verified.
- **Verification**: local — substitution simulation + `docker compose config --quiet`; server — checks listed above captured live over SSH. Public route activation remained gated on operator DNS correction (`kyc.logiclinkeg.tech` was attached to Vercel at rollout time; wired separately once propagated).

## Cross-Repo Automation Auth Migrated to GitHub App Installation Tokens

**Date**: 2026-08-26
**Category**: Infrastructure / CI
**Related Commit SHA**: ``92606328e669583e2b9ab223d7e427df83ab5dd4``

- **Failure #1 (code bug)**: `trigger-reviewer-console-sync.yml` wired `github-token: ${{ secrets.REVIEWER_CONSOLE_PAT }}` but no such secret exists in the repo (`gh secret list` shows only `APP_ID` / `APP_PRIVATE_KEY`); github-script received an empty string and every run failed with `Input required and not supplied: github-token`. Latent since `019ccce...` because the workflow's main-only path filter meant its first-ever execution was the post-release push. Fix: generate a short-lived installation token via `actions/create-github-app-token@v1` scoped to `kyc-reviewer-console` using the existing App secrets, matching the proven pattern in `build-and-publish.yml` and `sync-mobile-frontend.yml`; the dead PAT reference was removed.
- **Failure #2 (App-side, owner action)**: `Sync Mobile Frontend` generated its App token successfully but the subtree force-push returned `403 ... denied to quick-delivery-automation[bot]` despite succeeding Aug 24 (run `32745471664...`) — App installation/permission reduction on `quick-delivery-mobile`, not a code regression. Restored owner-side in GitHub settings between 10:43Z and 11:05Z the same day; workflow re-dispatched and passed with zero code changes.
- **Verification (literal)**: manual dispatches on `main` post-merge — Contract Sync run `32961504183` success, which fired the console repo's own `Contract Sync (from saas-core)` via `repository_dispatch` (run `32961516484`, 36s, success — cross-repo chain proven end-to-end); Sync Mobile Frontend run `32961583879` success (20s).

## notification-service Docker Build go.sum Transitive Checksum Fix

**Date**: 2026-08-29
**Category**: Infrastructure / CI / Docker Build
**Related Commit SHA**: ``913fa58dc15d41b97b7b0cf411f97ae2e2e01533``

- **Problem**: `Build and Publish Docker Images` workflow failed on `Build & Publish GHCR Images (notification-service)` during standalone Docker image compilation (`go build ./cmd/main.go`) with `missing go.sum entry for module providing package` errors across mongo-driver transitive packages (`github.com/youmark/pkcs8`, `github.com/golang/snappy`, `github.com/klauspost/compress`, `github.com/xdg-go/scram`, `github.com/xdg-go/stringprep`, `golang.org/x/sync`, `golang.org/x/crypto`, `golang.org/x/text`).
- **Fix**: Executed `go mod tidy` in `services/notification-service` module root to regenerate `services/notification-service/go.sum` with full transitive checksums and promote `go.mongodb.org/mongo-driver/v2 v2.2.1` to direct module requirement in `services/notification-service/go.mod`.
- **Verification**: Verified via `CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" ./cmd/main.go` compiling cleanly, full test suite `go test -v ./...` in `services/notification-service` passing (100% pass), and `shared/infra` tests passing.

