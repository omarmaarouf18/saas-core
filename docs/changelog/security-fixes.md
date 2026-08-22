# Security Fixes Changelog

This file tracks historical entries for the primary category: **Security Fixes Changelog**.

## ResetPassword Per-User Session Invalidation & Raw MongoDB Error Sanitization

- **Severity**: High (Session-hijacking mitigation gap & raw database error leakage; new, previously-unaudited finding distinct from original external report Finding #6)
- **Implementation Detail**:
  - **Per-User Token Invalidation Mechanism (`shared/infra/jwtutil/jwt.go`)**: Added `RevokeAllUserTokens(userID string) error` to `shared/infra/jwtutil`, which sets a Redis key `jwt:invalidated_before:<user_id>` to the current Unix timestamp with an 8-day TTL (24h token lifetime + 7-day refresh window, matching `RevokeToken` TTL logic). Updated `ValidateToken` to check `jwt:invalidated_before:<claims.UserID>` after the per-JTI denylist check and reject tokens if `claims.IssuedAt.Time` is before the stored timestamp with `jwtutil: token has been revoked`. Maintained security posture by failing closed on Redis lookup errors during verification.
  - **Password Reset Session Invalidation (`services/auth-service/internal/handlers/auth.go`)**: Updated `ResetPassword` to invoke `jwtutil.RevokeAllUserTokens(user.ID)` immediately after successful password update in MongoDB, invalidating all sessions issued prior to the reset moment.
  - **Raw Database Error Leakage Remediation**: Fixed raw MongoDB driver error leakage in `ResetPassword`. Replaced `"error": "failed to update password: " + err.Error()` with a generic user-facing message `{"error": "failed to update password"}`, logging the underlying MongoDB error server-side only (`log.Printf(...)`), matching the pattern established for Finding #6 in `UpdateProfile`.
  - **Regression Test Coverage (`shared/infra/jwtutil/jwt_test.go` & `services/auth-service/internal/handlers/auth_test.go`)**: Added `TestRevokeAllUserTokens` in `jwt_test.go` verifying invalidation timestamp storage, pre-invalidation token rejection, post-invalidation token validity, and fail-closed Redis lookup errors. Added `TestResetPassword_SessionInvalidation` and `TestResetPassword_DBErrorGenericMessage` in `auth_test.go` confirming tokens issued before password reset are rejected after reset while post-reset tokens remain valid, and verifying that MongoDB update failures return generic HTTP 500 error responses without leaking driver details.
- **Commit SHA**: ``d04e6a3830dc0df781babb8cf315c9faea4763d9``
- **Verification**: Verified via `go test ./...` in `shared/infra` and `services/auth-service` (100% pass), `go build ./...`, `go vet ./...`, and `gofmt -l .`. ✅

## AES-256-GCM Encryption at Rest for KYB/KYE Identity Documents on Local Storage

- **Implementation Detail**:
  - **Application-Level Storage Encryption (`services/auth-service/internal/storage/storage.go`)**: Enforced AES-256-GCM encryption at rest for all uploaded KYB/KYE identity documents (ID front/back, business proof, selfies). `LocalStorage.Upload()` generates a fresh 12-byte random nonce per file and encrypts raw file bytes via `cipher.AEAD.Seal(nonce, nonce, plaintext, nil)` prior to writing to disk. `LocalStorage.OpenFile()` transparently reads and decrypts ciphertext via `cipher.AEAD.Open(nil, nonce, ciphertext, nil)`, keeping reviewer-facing document viewing flows (`GetSignedURL` -> `ValidateSignedURLToken` -> `OpenFile`) fully operational without API-shape changes. Preserved strict path traversal validation (`strings.HasPrefix(absDest, absBase)`).
  - **Cryptographic Key Separation (`DOCUMENT_ENCRYPTION_KEY`)**: Added a dedicated `DOCUMENT_ENCRYPTION_KEY` environment variable and `Config.DocumentEncryptionKey` field in `services/auth-service/internal/config/config.go`, enforcing key separation from `OTP_AES_KEY`, `DOCUMENT_SIGNING_SECRET`, and `JWTSecret`. Enforced fail-fast validation in production mode (`appEnv == "production"`), returning a startup error if empty, with safe 32-byte key handling for local/test execution. Updated `infrastructure/.env.example`, `infrastructure/docker-compose.yml`, and `infrastructure/deploy/docker-compose.prod.yml`.
  - **Idempotent Data Migration Tool (`cmd/encrypt-documents`)**: Implemented a standalone CLI migration tool in `services/auth-service/cmd/encrypt-documents/main.go` to scan `STORAGE_BASE_DIR` and encrypt existing unencrypted plaintext documents in place. The tool validates AEAD tags prior to encryption; already-encrypted documents are safely skipped. Executed migration tool on existing repository sample documents (`services/auth-service/data/documents/kyb/...`), verifying 8 plaintext files were encrypted in place and confirming raw disk bytes are recognized as opaque data rather than unencrypted image/PDF headers.
- **Commit SHA**: ``b21628d916753a3eb753195e418cc297f2f99a99``
- **Verification**: Verified via `go test ./...` in `auth-service` (100% pass including `TestLocalStorage_EncryptionRoundTripAndDiskVerification` and `TestLocalStorage_ProductionModeMissingKey`), `make ci` gate, `make docs-check`, and `gosec` static security scans. ✅

## Go Stdlib Vulnerability Mitigation & Explicit Toolchain Patch Pinning (go1.26.6)

- **Implementation Detail**:
  - **Explicit Toolchain Pinning (`toolchain go1.26.6`)**: Added `toolchain go1.26.6` directive to `go.work` and all 7 `go.mod` files (`services/api-gateway`, `services/auth-service`, `services/chat-service`, `services/notification-service`, `services/user-service`, `shared/infra`, `tools/docgen`). This explicitly pins the Go toolchain patch version used for builds to 1.26.6 while retaining `go 1.26` language floor compatibility, remediating 6 recurring Go stdlib vulnerabilities (`GO-2026-6218`, `GO-2026-6090`, `GO-2026-6089`, `GO-2026-6088`, `GO-2026-5972`, `GO-2026-5026`).
  - **Dockerfile Base Image Pinning**: Updated all 5 microservice Dockerfiles (`services/*/Dockerfile`) across both `AS dev` and `AS build` multi-stage build targets to pin base image `golang:1.26.6-alpine`.
  - **CI Workflow Pinning**: Updated `.github/workflows/ci.yml` `actions/setup-go@v5` steps to pin `go-version: '1.26.6'`.
  - **Automated Drift Guard Extension**: Extended the Go Version Consistency Drift Guard in `.github/workflows/ci.yml` and `.githooks/pre-push` to enforce strict consistency for standard language floor (`1.26`), toolchain directive (`go1.26.6`), CI version (`1.26.6`), and Dockerfile base image patch versions (`1.26.6`).
- **Commit SHA**: ``277011c67ed17707f8d903a6bf8f797c7d371c80``
- **Verification**: Verified via `govulncheck` (0 vulnerabilities across all services), `go test ./...` across all 6 Go modules (100% pass), `flutter test` (189/189 pass), `.githooks/pre-push` drift guard execution, and `make docs-check`. ✅

## Production Container Non-Root Security Hardening & Native Docker HEALTHCHECK Directives

- **Implementation Detail**:
  - **Non-Root Runtime Execution (`USER appuser`)**: Updated production container stages across all 5 microservices (`api-gateway`, `auth-service`, `chat-service`, `notification-service`, `user-service`) to create a dedicated system group `appgroup` (GID 101) and system user `appuser` (UID 100). Placed `USER appuser` as the final instruction before `ENTRYPOINT`. In `auth-service/Dockerfile`, created `/app/data` with explicit `appuser:appgroup` ownership, resolving non-root permission denied errors on local file storage directory creation.
  - **Native Container HEALTHCHECK Directives**: Added Docker native `HEALTHCHECK` directives to each Dockerfile (`--interval=10s --timeout=5s --start-period=5s --retries=3`) executing `curl -f -s -k` pointing to each service's respective `/health` endpoint with fallback mTLS client cert arguments (`--cert /app/certs/<SVC>.crt --key /app/certs/<SVC>.key`).
  - **Unprivileged Port Verification**: Verified all 5 microservices listen on unprivileged ports (`8080`, `3002`, `3001`, `3004`, `3003`), confirming `appuser` binds network sockets cleanly without requiring `CAP_NET_BIND_SERVICE` or root privileges. Tested all 5 containers simultaneously on a shared Docker network, confirming `docker ps` status transitions to `healthy` across all 5 containers and `docker exec <container> id` outputs `uid=100(appuser) gid=101(appgroup)`.
- **Commit SHA**: ``a7e7ecfb2fcf634a933fc1960f9baf8eddb85cf3``
- **Verification**: Verified via local `docker build --target prod`, `docker run`, `docker inspect`, `docker ps` (all 5 containers `healthy`), `docker exec id` (UID 100), `go test ./...` across all 5 Go modules (100% pass), and `make docs-check`. ✅

## External Security & Architecture Review — Resolution Summary (2026-08-06)

This section consolidates the resolution status for all 10 findings from the external security and architecture findings report (`security-and-architecture-findings.md` on branch `logic-exploitation` @ `30ae8ce`). 9 of 10 findings have been resolved (Findings #1–#8 code-remediated; Finding #9 documented as an accepted architectural decision), and 1 finding remains explicitly open/deferred (Finding #10).

> [!NOTE]
> **Finding Severities**: Severities in the table below are quoted verbatim as assigned in the original external audit report (`🔴 High`, `🟡 Medium`, `🟢 Low`) without independent re-grading or tier reclassification.

| Finding # | Severity | Title / Area | Status | Resolution Detail & Commit SHAs |
| :--- | :--- | :--- | :--- | :--- |
| **Finding #1** | 🔴 High | KYB/KYE Review Approval Race Condition | **Resolved** | Remediated TOCTOU race condition in `ReviewKYBKYESubmissions` by adding `UpdateUserConditional` in `services/auth-service/internal/store/mongodb.go` conditioning status updates on matching `_id` AND `kyc_status`/`kye_status` equal to `pending_approval`. Returns HTTP 409 Conflict when `MatchedCount == 0`.<br>Commit SHAs: ``bb1d0099a4e536686d0206d9d6e0a91453602147``, ``b6cb5b93a9138b02be7daa3eb6cce67878d54db8`` |
| **Finding #2** | 🟡 Medium | Reviewer Auth Query-Parameter Token Fallback | **Resolved** | Hardened `authenticateReviewer` in `auth-service` to strictly require `X-Internal-Token` and `X-Reviewer-Token` HTTP headers, completely removing URL query-parameter fallbacks (`internal_token` and `reviewer_token`) to prevent credential leakage in logs and Referer headers.<br>Commit SHAs: ``f81d97897e342f81488517afbb5b83b6c03aa217``, ``e12d15be656d9fc7e4b61aaaebcef0a9bf9e2311`` |
| **Finding #3** | 🟡 Medium | Cryptographic Key Reuse (JWT Secret for Document Signing) | **Resolved** | Replaced `JWTSecret` reuse in `storage.NewLocalStorage` with a dedicated, distinct `DOCUMENT_SIGNING_SECRET` environment variable and configuration field, enforcing cryptographic key separation between session JWTs and document viewing URLs.<br>Commit SHAs: ``f81d97897e342f81488517afbb5b83b6c03aa217``, ``e12d15be656d9fc7e4b61aaaebcef0a9bf9e2311`` |
| **Finding #4** | 🟢 Low | Storage Layer Error Detail Leakage in Reviewer Submissions | **Resolved** | Updated `GetPendingKYBKYESubmissions` in `auth-service` to log raw storage errors server-side via `log.Printf(...)` while appending generic error strings without string interpolation or internal storage path details to user-facing `sub.DocumentErrors`.<br>Commit SHAs: ``4e7be5d31378bffa2c23839577b715ac731abf04``, ``1aa0fa089380c528dfd75346d0268d8c785dd59f`` |
| **Finding #5** | 🔴 High | Unbounded Request Body Read in Profile Updates | **Resolved** | Wrapped `r.Body` with `http.MaxBytesReader(w, r.Body, 1<<20)` (1MB cap) in `UpdateProfile` (`auth-service`) prior to `io.ReadAll`, preventing memory exhaustion DoS attacks on profile updates.<br>Commit SHAs: ``4e550288e34562d4cea04940e0f65a1e1f1df280``, ``5acf22c84d21f228833d5e851c100c150cd9f94f`` |
| **Finding #6** | 🟢 Low | Raw Database Driver Error Disclosure on Username Conflict | **Resolved** | Added `mongo.IsDuplicateKeyError(err)` check on `UpdateUser` failure path in `UpdateProfile`, returning HTTP 409 Conflict with a clean message `{"error": "username is already taken"}` while logging raw MongoDB driver errors server-side only.<br>Commit SHAs: ``f15dadfa4c281607fb4ecafbdafb6bcf82263eb2``, ``7a4d409368d7e2096ed9a823ad162243f0a9c35e`` |
| **Finding #7** | 🟢 Low | Missing Phone Field Format and Length Validation | **Resolved** | Implemented E.164 phone regex validation (`^\+?[0-9]{7,15}$`) for `phone` profile updates in `UpdateProfile`, rejecting empty strings (`"phone": ""`) and malformed phone strings with HTTP 400 Bad Request.<br>Commit SHAs: ``f15dadfa4c281607fb4ecafbdafb6bcf82263eb2``, ``7a4d409368d7e2096ed9a823ad162243f0a9c35e`` |
| **Finding #8** | 🟡 Medium | Shared MongoDB Database Coupling Between Services | **Resolved** | Enforced database-per-service isolation by updating default configuration fallbacks to `auth_db` for `auth-service` and `user_db` for `user-service`. Restructured docker-compose and .env files to pass dedicated `AUTH_MONGO_DATABASE`, `USER_MONGO_DATABASE`, and `CHAT_MONGO_DATABASE` variables. Updated deployment docs documenting pre-production DB reset.<br>Commit SHAs: ``2553814de9be4162c34e367c3acb97eeb11c39e9``, ``be7beafa7c64dfce9f31e1b47a2a89602a7dbf30`` |
| **Finding #9** | 🟢 Low | Monorepo Shared Dependency Relative-Path Coupling | **Resolved (Architectural Decision)** | Resolved via documented architectural decision in `docs/REPOSITORY_MAP.md` §5 rather than a code change. Documented relative-path resolution (`replace github.com/project/shared/infra => ../../shared/infra`), service extraction rules (copy `shared/infra` alongside service), maintenance risk (manual re-sync required for copied instances), and long-term modularization trigger (publish versioned module if 3+ external apps depend on copied instances).<br>Commit SHAs: ``a35ca8670818a6d1c44b5bfd21ed211bd3f38c83``, ``82f0eec786935b5ee3051fba4379327eb8d06f74`` |
| **Finding #10** | 🟢 Low | Team-Scale Organizational Readiness Gaps | **Open — Not Yet Addressed (Deferred)** | **Deferred**: Governance and team-scale workflow controls remain open for future implementation *(Process item unrated in original report)*. Outstanding tasks include creating `CONTRIBUTING.md`, configuring `.github/CODEOWNERS`, verifying automated GitHub branch protection enforcement on `main`, and establishing a module-ownership map across microservices. |

---

## GetPendingKYBKYESubmissions Storage Error Detail Sanitization (Finding #4)

- **Implementation Detail**: Remediated internal storage error disclosure in `auth-service` (`GetPendingKYBKYESubmissions` in `services/auth-service/internal/handlers/auth.go`). Previously, signed URL generation failures for reviewer document previews appended `fmt.Sprintf("Failed to load <doc_type>: %v", err)` to the user-facing `DocumentErrors` response array, exposing internal storage paths and driver-level error details to reviewers. Updated `GetPendingKYBKYESubmissions` to log underlying storage errors server-side via `log.Printf(...)` while appending generic error strings without string interpolation (`"Failed to load id_front"`, `"Failed to load id_back"`, `"Failed to load selfie"`, and `"Failed to load business_proof"`). Updated regression test `TestGetPendingKYBKYESubmissions_StorageError` in `auth_test.go` and frontend mock tests to assert exact generic error strings and confirm no raw error details or colon interpolation are exposed.
- **Commit SHA**: ``4e7be5d31378bffa2c23839577b715ac731abf04``
- **Verification**: Verified via `TestGetPendingKYBKYESubmissions_StorageError` in `auth_test.go`, `flutter test` (126/126 pass), `go build ./...`, `go vet ./...`, and `go test ./services/auth-service/...`. ✅

## UpdateProfile Duplicate Username Error Sanitization & Phone Validation (Findings #6 & #7)

- **Implementation Detail**:
  1. **Finding #6**: Fixed raw database error disclosure in `auth-service` (`UpdateProfile` in `services/auth-service/internal/handlers/auth.go`). Previously, database update failures returned raw driver error text via `writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to update user profile: " + err.Error()})`, leaking MongoDB collection and index schemas (`E11000 duplicate key error collection...`) on username conflicts. Added `mongo.IsDuplicateKeyError(err)` check on `a.store.UpdateUser` failure path, returning HTTP 409 Conflict with a clean message `{"error": "username is already taken"}` while logging raw errors server-side only.
  2. **Finding #7**: Added strict format and length validation for `phone` updates in `UpdateProfile`. Previously, `updateFields["phone"] = str` accepted arbitrary or empty strings, allowing accidental phone deletion via `"phone": ""`. Introduced E.164 phone regex validation (`^\+?[0-9]{7,15}$`) requiring 7 to 15 digits with optional leading `+`. Rejects empty strings (`"phone": ""`) and malformed phone strings with HTTP 400 Bad Request (`{"error": "phone number cannot be empty"}` / `{"error": "invalid phone number format"}`).
- **Commit SHA**: ``f15dadfa4c281607fb4ecafbdafb6bcf82263eb2``
- **Verification**: Verified via regression test subtests (`Duplicate Username Conflict Returns Clean 409 Without Raw Driver Text`, `Invalid Phone Format Rejected with 400`, and `Empty Phone String Rejected with 400` in `user_profile_test.go`), `go build ./...`, `go vet ./...`, and `go test ./services/auth-service/...`. ✅

## UpdateProfile Unbounded Request Body Cap (Finding #5)

- **Implementation Detail**: Remediated memory exhaustion vulnerability in `auth-service` (`UpdateProfile` in `services/auth-service/internal/handlers/auth.go`). Previously, `UpdateProfile` read the request body via `io.ReadAll(r.Body)` without a size boundary, allowing authenticated users to send arbitrarily large payloads and force full in-memory buffering before JSON decoding or IDOR validation. Wrapped `r.Body` with `http.MaxBytesReader(w, r.Body, 1<<20)` (1MB cap) prior to `io.ReadAll`. Added regression test `Request Body Exceeding 1MB Limit Rejected` in `user_profile_test.go` asserting that payloads exceeding 1MB return HTTP 400 Bad Request without application crashes or silent memory buffering.
- **Commit SHA**: ``4e550288e34562d4cea04940e0f65a1e1f1df280``
- **Verification**: Verified via `Request Body Exceeding 1MB Limit Rejected` in `user_profile_test.go`, `go build ./...`, `go vet ./...`, and `go test ./services/auth-service/...`. ✅

## Reviewer Auth Query-Param Fallback Removal & Document Signing Secret Separation (Findings #2 & #3)

- **Implementation Detail**:
  1. **Finding #2**: Hardened reviewer authentication in `auth-service` (`authenticateReviewer` in `services/auth-service/internal/handlers/auth.go`). Removed URL query-string fallbacks (`internal_token` and `reviewer_token`) which exposed long-lived credentials to HTTP access logs, browser histories, and `Referer` header leakage. `authenticateReviewer` now strictly requires `X-Internal-Token` and `X-Reviewer-Token` HTTP headers. Updated Flutter frontend (`api_client.dart` and `auth_provider.dart`) and mock tests to pass tokens exclusively in HTTP headers.
  2. **Finding #3**: Resolved key material reuse in `auth-service` (`cmd/main.go`). Previously, `storage.NewLocalStorage` reused `cfg.JWTSecret` for signing short-lived document viewing URLs, violating cryptographic key separation principles between session JWTs and document-view URLs. Introduced a dedicated required configuration field and environment variable `DOCUMENT_SIGNING_SECRET` in `config.go`, `infrastructure/.env.example`, `infrastructure/docker-compose.yml`, and `docs/DEPLOYMENT.md`. Updated `main.go` to pass `cfg.DocumentSigningSecret` to `storage.NewLocalStorage`.
- **Commit SHA**: ``f81d97897e342f81488517afbb5b83b6c03aa217``
- **Verification**: Verified via updated Go handler tests (`QueryParamInternalTokenRejected` and `QueryParamReviewerTokenRejected` in `auth_test.go`), Flutter tests (`flutter test` and `flutter analyze`), `go build ./...`, `go vet ./...`, and unit test suite execution. ✅

## KYB/KYE Review Approval Atomic Conditional Status Guard (Finding #1)

- **Implementation Detail**: Remediated race condition in `auth-service` (`ReviewKYBKYESubmissions` in `services/auth-service/internal/handlers/auth.go`). Previously, `ReviewKYBKYESubmissions` queried user status via `GetUserByID` and then updated the record unconditionally using `store.UpdateUser(ctx, userID, update)`. Concurrent review requests could both read `pending_approval`, pass status validation in memory, and both write, causing the last write to silently win and generating duplicate/contradictory audit log entries. Added `UpdateUserConditional` store method in `services/auth-service/internal/store/mongodb.go` which conditions `UpdateOne` on matching `_id` AND `kyc_status` (or `kye_status`) equal to `pending_approval`. Updated `ReviewKYBKYESubmissions` to execute `UpdateUserConditional`, returning HTTP 409 Conflict with `{"error": "submission status has already changed or been reviewed"}` when `MatchedCount == 0`.
- **Commit SHA**: ``bb1d0099a4e536686d0206d9d6e0a91453602147``
- **Verification**: Verified via regression test `TestReviewKYBKYESubmissions_ConcurrencyRace` in `auth_test.go` confirming 1 success (200 OK) and 1 conflict (409 Conflict) on concurrent reviews with exactly 1 audit log entry ("KYC_REVIEWED"), `go build ./...`, `go vet ./...`, and `go test ./...` in `auth-service`. ✅



## UpdateJobLocation Atomic Rate-Limit Throttle Reservation

- **Implementation Detail**: Resolved TOCTOU (time-of-check-to-time-of-use) race condition in `user-service` (`UpdateJobLocation` in `services/user-service/internal/handlers/handlers.go`). Previously, rate limiting/throttling checks were performed after database reads (`GetJob`) and subscription tier checks (`requireTier`), allowing two simultaneous requests to pass validation before either committed its in-flight lock or updated timestamp. Created `tryReserveLocationThrottleInMemory` helper for atomic in-memory reservation and moved the throttle reservation check to the immediate entry point of `UpdateJobLocation` (before DB queries or external calls). Ensured atomic in-flight reservation across both Redis (`checkLocationThrottleScript`) and in-memory modes. If any subsequent validation step fails, `clearInFlight()` is called to release the reservation.
- **Architecture & Dual-Path Verification**: Confirmed via `git show 118c40d -- services/user-service/internal/handlers/handlers.go` and `services/user-service/cmd/main.go:59` that the production Redis path (`if u.rdb != nil`) remains 100% intact and active for all deployments. In `cmd/main.go`, `ratelimit.NewRedisClient` enforces non-nil `redisClient` at startup. The Redis path executes `u.rdb.Eval(evalCtx, checkLocationThrottleScript, ...)` where Redis guarantees single-threaded atomic execution of the Lua script (checking `loc:inflight` and `loc:lastupdate` and setting `loc:inflight` in one round-trip). The in-memory map path (`tryReserveLocationThrottleInMemory`) is strictly an isolated fallback for unit tests where `u.rdb == nil` (e.g. `handlers_test.go:5156`). Moving reservation to the handler entry point (line 1834) before `GetJob` (line 1898) and `requireTier` (line 1916) closes the TOCTOU window. If any subsequent check fails (unauthorized, invalid coordinates, job missing, forbidden, job inactive, or upgrade required), `clearInFlight()` is called to delete `loc:inflight` and prevent deadlocking future updates for that job.
- **Commit SHA**: ``118c40d47a231a558201069bb485f271ab697b4e``
- **Verification**: Verified via `go test ./services/user-service/internal/handlers/... -run TestUserServiceHandlers/UpdateJobLocation_Throttle_Concurrent_Race_Handling -count=20 -race` passing 20 consecutive iterations with the `-race` detector enabled, `go test ./...` across all services, and `make ci`. ✅

## API Gateway Trusted-Proxy-Aware Client IP Resolution

- **Implementation Detail**: Resolved production issue where `api-gateway`'s reverse proxy (`services/api-gateway/internal/proxy/proxy.go`) unconditionally overwrote `X-Forwarded-For` with `req.RemoteAddr`, causing Caddy loopback connections (`127.0.0.1`) to collapse all client IPs to `127.0.0.1` and triggering false rate-limiting lockouts across unrelated users. Created `iputil` package (`services/api-gateway/internal/iputil/iputil.go`) providing `ExtractIP`, `IsTrustedProxy`, and `ResolveClientIP`. Configured `TRUSTED_PROXY_IPS` in `config.go` (defaulting to `127.0.0.1,::1`, configurable via environment variable to support CIDRs like `172.16.0.0/12`). Updated reverse proxy Director and `middleware.RateLimit` (`services/api-gateway/internal/middleware/limiter.go`) to check whether immediate connection IP (`req.RemoteAddr`) matches `TRUSTED_PROXY_IPS`. For trusted proxies with existing `X-Forwarded-For` headers, the real client IP at the head of the chain is preserved and forwarded downstream. Direct untrusted connections overwrite `X-Forwarded-For` with `req.RemoteAddr` to harden against client IP spoofing attacks. Documented trust chain Hop 1 (Caddy → api-gateway) and Hop 2 (api-gateway → auth-service) in code comments and updated `docs/DEPLOYMENT.md` Step 8.1.
- **Commit SHA**: ``4d2fda7ac63665ec4d9e050f594978118b4a7c79``
- **Verification**: Verified via unit test suite (`go test -v ./services/api-gateway/...` passing 100% including trusted proxy forwarding, untrusted spoofing overwrite, and empty XFF fallback), `go test ./...` across all services, live production VM deployment (`saas-core-deploy` run `30695839438`), live Caddy proxy requests (`https://api.logiclinkeg.tech`), direct `api-gateway` port 8080 spoofing checks, and pre-push hook validation (`.githooks/pre-push` gate exit code 0). ✅

## Cumulative Route Speed Check (ADR-0007 Phase 0)

- **Implementation Detail**: Added a cumulative route speed check in `user-service` (`UpdateJobLocation` in `services/user-service/internal/handlers/handlers.go`). Evaluates average velocity across the full route of validated waypoints (`Job.Waypoints` persisted via `$push` in `UpdateJobLocation` in `services/user-service/internal/store/mongodb.go`). If average speed from `CreatedAt` exceeds `MaxReasonableSpeedKmh` (150 km/h), the update is rejected with `implausible_speed` and `IMPLAUSIBLE_SPEED_DETECTED` security event shipping. Added regression test suite `TestUpdateJobLocation_SpeedCheck_CumulativeAndStep`.
- **Commit SHA**: ``12dd2f39b9c5e1293fa1a2f63e12c37a71fa015e``
- **Verification**: Verified via unit tests (`TestUpdateJobLocation_SpeedCheck_CumulativeAndStep`) and `make docs-check`. ✅

## Delivery and Shipping GPS Trail Settlement Reconciliation (ADR-0007 Phase 1)

- **Implementation Detail**: Implemented ADR-0007 Phase 1 actual distance settlement and under-distance manual review flagging in `user-service` (`CompleteJob` in `services/user-service/internal/handlers/handlers.go`). For delivery and shipping category services, `CompleteJob` calculates `ActualDistance` from the cumulative Haversine distance across recorded `Job.Waypoints`. If `ActualDistance < 0.70 * BookedDistance`, completion is halted and the job transitions to `models.JobStatusEscrowReconciliationRequired` with note `"tracked_distance_mismatch: actual X km vs booked Y km"`. Otherwise, employee payout uses the guaranteed floor `max(LockedEscrowAmount, A_actual)`. For non-COD escrow jobs, payouts exceeding `LockedEscrowAmount` are capped at `LockedEscrowAmount` per ADR-0002 to preserve wallet isolation and emit `ESCROW_LIMIT_EXCEEDED` audit logs. Added test suite `TestCompleteJob_ADR0007_Phase1_SettlementAndReconciliation`.
- **Commit SHA**: ``44e51b2efdc925c6862df04658b73429a9680154``
- **Verification**: Verified via `go vet`, `go test ./... -count=1` (`TestCompleteJob_ADR0007_Phase1_SettlementAndReconciliation`), and `make docs-check`. ✅



## Bcrypt Password Hashing

- **Implementation Detail**: Replaced plaintext comparison in auth-service with bcrypt password hashing.
- **Commit SHA**: ``48ece45eb6b0282194c2f7026a7a85c8fbd79917``
- **Verification**: Verified in `auth-service/internal/handlers/auth.go`. ✅

## Dual-Key rate limiting & lockouts

- **Implementation Detail**: Enforced lockout limits in `auth-service` on client IP and email with exponential backoff.
- **Commit SHA**: ``04185514a931e597de3e97da46b6842a691090db``
- **Verification**: Verified in `auth-service/internal/handlers/limiter.go`. ✅

## OTP TTL Expiry & Cleanup

- **Implementation Detail**: Added a 5-minute TTL to OTPs and a background database sweep sweeping expired OTPs every minute.
- **Commit SHA**: ``f3f313b97c034a4118aba1760403bf1a47911df1``
- **Verification**: Verified in `auth-service/internal/store/mongodb.go`. ✅

## Owner KYC Status Checks

- **Implementation Detail**: Restricts service creation, deposits, and job tracking to owners with approved KYC status.
- **Commit SHA**: ``49d453c92742deb58bf31e806da7f2a084ea1be2``
- **Verification**: Verified in `user-service/internal/handlers/handlers.go`. ✅

## JSON Injection Fix in WebSocket

- **Implementation Detail**: Replaced manual string concatenation in chat broadcast with `json.Marshal`.
- **Commit SHA**: ``d8e9f762fb9d3dff1e054285ef6e9c0954f35e4a``
- **Verification**: Verified in `chat-service/internal/chat/hub.go`. ✅

## WebSocket Channel Authorization

- **Implementation Detail**: Restricts channel subscriptions to job participants (Owner or Employee) by querying user-service.
- **Commit SHA**: ``54750d0711e56a2afc48508aed44c2515ac39433``
- **Verification**: Verified in `chat-service/internal/handlers/chat.go`. ✅

## SSE Stream Authentication

- **Implementation Detail**: Enforces SSE connection token verification by querying auth-service.
- **Commit SHA**: ``5dd15e27c7cc6f216b15e907e0eb2c1cbb26cde9``
- **Verification**: Verified in `notification-service/internal/handlers/handlers.go`. ✅

## CORS Origins Restriction

- **Implementation Detail**: Restricted notification SSE stream CORS from wildcard `*` to configured `ALLOWED_ORIGIN`.
- **Commit SHA**: ``49752a64c4a641153087c7e95958d37e33f3bc05``
- **Verification**: Verified in `notification-service/internal/handlers/handlers.go`. ✅

## X-Forwarded-For Spoof Hardening

- **Implementation Detail**: Edge api-gateway overwrites X-Forwarded-For. Gateway limiter keys off `RemoteAddr` directly.
- **Commit SHA**: ``aebb580fb7b5a9c7520034e865153fc08681cfb5``
- **Verification**: Verified in `api-gateway/internal/middleware/limiter.go` and `proxy.go`. ✅

## Tenant Subscription Gating

- **Implementation Detail**: POST /users/subscription upgrades require requester_id == tenant_id, auth-service check, and maps paid to pending_payment (requires manual activation).
- **Commit SHA**: ``1660178fa2bf2aa37535de5597ce92594ff8f61b``
- **Verification**: Verified in `user-service/internal/handlers/handlers.go`. ✅

## WebSocket Message Authorization

- **Implementation Detail**: Gated chat message broadcasts by canAccessChannel in WebSocket readPump.
- **Commit SHA**: ``1660178fa2bf2aa37535de5597ce92594ff8f61b``
- **Verification**: Verified in `chat-service/internal/handlers/chat.go`. ✅

## Cryptographically Signed JWTs

- **Implementation Detail**: Replaced raw user ID tokens with signed HS256 JWT tokens containing user ID, role, tenant ID, and email. Added POST /auth/refresh to reissue tokens. Downstream services validate JWT signatures and expiry locally.
- **Commit SHA**: ``4094f5a5746611d4103fb58943f851fad108f74d``
- **Verification**: Verified in `auth-service`, `chat-service`, `notification-service`, `user-service`. ✅

## auth-service XFF Trust Boundary Hardening

- **Implementation Detail**: auth-service rate limiter only trusts XFF headers if verified by the dynamic GATEWAY_SECRET header injected by the API Gateway.
- **Commit SHA**: ``d2638b2bda8d6e25bc1d5013c91511814f55a6f4``
- **Verification**: Verified in `auth-service` getClientIP. ✅

## Signup-time Anti-spam OTP

- **Implementation Detail**: Gated signup with OTP confirmation. Accounts are created as unconfirmed (is_confirmed = false) and login is rejected until the signup OTP is verified.
- **Commit SHA**: ``eecd7e9114107c88b9005be1c4870fba2331e3df``
- **Verification**: Verified in `auth-service` Signup, Login, and VerifyOTP. ✅

## JWT Secret Hardening

- **Implementation Detail**: Removed hardcoded JWT secret fallback in all 4 services. Services now require JWT_SECRET env var on startup and fail-fast if it's missing.
- **Commit SHA**: ``b4bb3e57aa776386040fa635aaf3990c405e6dff``
- **Verification**: Verified via startup crash test. ✅

## Gateway Secret Hardening

- **Implementation Detail**: Removed hardcoded X-Gateway-Secret. Both api-gateway and auth-service now require the GATEWAY_SECRET env var on startup and fail-fast if it's missing.
- **Commit SHA**: ``85ee9eaf8114096aef85eb77fd2d84291218a908``
- **Verification**: Verified via startup crash test. ✅

## Job Endpoint Access Control

- **Implementation Detail**: Secured GET /users/jobs/get?id= by strictly restricting access to matching owners/employees (validated via JWT) or trusted internal clients via X-Internal-Token header. Closed resolveToken() unverified bypass.
- **Commit SHA**: ``5c728683518528cfa3197b0f6a4175fb12fe2e1a``
- **Verification**: Verified via user-service integration test and cURL validation. ✅

## Employee Toggle Authentication

- **Implementation Detail**: Fixed POST /auth/employee/toggle security gap by requiring the owner's password and verifying it with bcrypt before freezing or activating employees.
- **Commit SHA**: ``d43021c052600158902c3a2ac2190d8b94888833``
- **Verification**: Verified via auth-service compilation. ✅

## Audit Log Access Control

- **Implementation Detail**: Secured GET /auth/audit-log by strictly requiring requester_id query param and restricting access to matching tenant owner (validated via JWT). Closed unverified bypass.
- **Commit SHA**: ``58436e3032a0e8ff78034036e723f64846d242d9``
- **Verification**: Verified via auth-service unit test and cURL validation. ✅

## GetUser Endpoint Access Control

- **Implementation Detail**: Secured GET /auth/user by requiring `X-Internal-Token` for internal service-to-service calls (chat/notification/user-service) and valid signed JWT for external callers. Removed raw-ID passthrough. Updated all 4 internal callers to inject `X-Internal-Token` header. Added `INTERNAL_SERVICE_TOKEN` fail-fast to notification-service.
- **Commit SHA**: ``b6d4f47b649614e491a8b6aa62e5c2abfb4a770e``
- **Verification**: Verified via compilation and existing test suites (all pass). ✅

## Hardcoded Secrets Audit

- **Implementation Detail**: Audited entire codebase for hardcoded secrets. Removed JWT fallbacks, X-Gateway-Secret, and confirmed via repo-wide regex audit that no other secrets exist.
- **Commit SHA**: ``fbdbb314d685f5bb6946b53351bc36d302dfce54``
- **Verification**: Verified via repo-wide regex audit. ✅

## Gateway Internal Token Stripping

- **Implementation Detail**: Edge api-gateway removes any client-supplied `X-Internal-Token` before proxying requests to backends.
- **Commit SHA**: ``b1fa777a6291679b651690157cacd676229b1a1b``
- **Verification**: Verified in api-gateway proxy.go. ✅

## CompleteJob Authorization Check

- **Implementation Detail**: Enforced user/employee role identity and internal X-Internal-Token verification on CompleteJob.
- **Commit SHA**: ``3b394868e87932633dc4a87233a4883b0f35b377``
- **Verification**: Verified via user-service unit tests. ✅

## Notification Auth Enforcement

- **Implementation Detail**: Enforced X-Internal-Token authentication on Send and BroadcastJobAlert endpoints in notification-service.
- **Commit SHA**: ``298f92ad476983313f665111c07d0dd70689af06``
- **Verification**: Verified via notification-service unit tests. ✅

## GetHistory Channel-Access Check

- **Implementation Detail**: Enforced requester_id (JWT token) and channel access (canAccessChannel) validation on GetHistory in chat-service.
- **Commit SHA**: ``9ffd4eec768ba1903ea1339780ab2038bc0ed8d5``
- **Verification**: Verified via chat-service unit tests. ✅

## Employee Toggle Lockout

- **Implementation Detail**: Enforced limiter lockout and failure recording on failed owner password check in ToggleEmployee.
- **Commit SHA**: ``ebe5f62e41459ede18a1a9a4644d9e99cb5574cd``
- **Verification**: Verified via compilation and logic flow analysis. ✅

## Token Refresh 7-Day Limit

- **Implementation Detail**: Gated token refresh to reject tokens that expired more than 7 days ago.
- **Commit SHA**: ``ebe5f62e41459ede18a1a9a4644d9e99cb5574cd``
- **Verification**: Verified via compilation and logic flow analysis. ✅

## ID and OTP Cryptographic Hardening

- **Implementation Detail**: Removed weak fallbacks from generateID and generate4DigitOTP, causing fail-fast logs on failure.
- **Commit SHA**: ``ebe5f62e41459ede18a1a9a4644d9e99cb5574cd``
- **Verification**: Verified via compilation. ✅

## WebSocket Origin Verification

- **Implementation Detail**: Restricted WebSocket connection origins to match configured ALLOWED_ORIGIN in chat-service.
- **Commit SHA**: ``a55af8d29f7860a9bf8629d8448855f616f393cb``
- **Verification**: Verified via compilation and test suites. ✅

## Membership Tier Enforcement

- **Implementation Detail**: Gated UpdateJobLocation location tracking endpoint behind PlanPaid check on Job Owner.
- **Commit SHA**: ``bff88aabb27c72887ccb2976adc95e97e9b37e75``
- **Verification**: Verified via unit and integration tests. ✅

## CloudWatch Security Log Shipping

- **Implementation Detail**: Structured JSON log event to CloudWatch Logs for security-relevant blocked events in auth, user, and chat services.
- **Commit SHA**: ``cc903dd325c89423f15d820f3a801f2dcfb734cf``
- **Verification**: Verified via unit, race, and log shipping tests. ✅

## mTLS Stage 1: Dev CA & Certs

- **Implementation Detail**: Created generate-certs.sh script generating Root CA and leaf certificates for local dev.
- **Commit SHA**: ``bbab3a657d00cea1309b2a17a5a01e0a01d8f88b``
- **Verification**: Verified via cert creation and gitignore validation. ✅

## mTLS Stage 2: TLS Server Config

- **Implementation Detail**: Configured auth, chat, notification, and user services to serve HTTPS with client cert verification (tls.RequireAndVerifyClientCert).
- **Commit SHA**: ``28a31dcd94db5d0c5ade855c5f8949f00daa97cd``
- **Verification**: Verified via compilation and test execution. ✅

## mTLS Stage 3: TLS Client Config

- **Implementation Detail**: Updated internal HTTP clients in api-gateway, chat, notification, and user services to use custom TLS client configuration with hostname verification and local root CA trust.
- **Commit SHA**: ``45fffa12de3c33fa7e668540c0136d6a205ea521``
- **Verification**: Verified via compilation and test execution. ✅

## mTLS Stage 4: Docker & Env Wiring

- **Implementation Detail**: Configured docker-compose.yml to mount local certs and keys, updated service URLs to HTTPS, and updated env templates.
- **Commit SHA**: ``dff2df441e5fc3c7e6ffaeadae2a69bac48ea919``
- **Verification**: Verified via configuration review. ✅

## mTLS Stage 5: Verification

- **Implementation Detail**: Created and ran an integration test (mtls_integration_test.go) verifying handshake rejection of missing/untrusted client certs and success of trusted ones.
- **Commit SHA**: ``558749397dd8c4ea956a4ef7c1cd95126cc372eb``
- **Verification**: Verified via integration tests. ✅

## Redis Rate Limiting Stage 5: Failure Mode

- **Implementation Detail**: Implemented fail-closed behaviors for Redis runtime unavailability, with audit logging and rate restriction.
- **Commit SHA**: ``2914dc8fb9c6c34c4edc644ce7ff2031fc5b5b54``
- **Verification**: Verified via compilation and code review. ✅

## Prevent Duplicate Ratings

- **Implementation Detail**: Added compound unique index on ratings for (job_id, rated_by) and returned 409 Conflict when duplicate rating is submitted (identified during schema review).
- **Commit SHA**: ``c0564c0fbd217a1d8de9501335bef4ec796a7e31``
- **Verification**: Verified via integration tests. ✅

## Complaint Routing Stage 2: Atomic Agent Assignment

- **Implementation Detail**: Implemented atomic support agent assignment using MongoDB FindOneAndUpdate to prevent race conditions on concurrent ticket creation.
- **Commit SHA**: ``1f46ed23763eca30135f43afdd0f52589174ec0f``
- **Verification**: Verified via compilation. ✅

## External HTTPS Listener on api-gateway

- **Implementation Detail**: Migrated the gateway's external port to listen on HTTPS with separate EXTERNAL_TLS credentials, keeping public and internal mTLS domains distinct.
- **Commit SHA**: ``da7960a66651c5005761807cd8096da40d5ff6eb``
- **Verification**: Verified via compilation and configuration. ✅

## SimulateEmployeeAction Authorization

- **Implementation Detail**: Enforced JWT authentication on simulate employee action endpoint, validating that the token matches the requested employee email.
- **Commit SHA**: ``0a2cdb45d6ec0fef649f55b716ac7b5a89089a73``
- **Verification**: Verified via unit test. ✅

## Mask plain text tokens in logs

- **Implementation Detail**: Replaced raw JWT / session tokens with authenticated IDs (userID / tenantID) in stdout logs to prevent credential leakage.
- **Commit SHA**: ``6c5675bcdd79b002cea675500671078e92810aa6``
- **Verification**: Verified via grep checks. ✅

## Gateway Info & Health Leak Fix

- **Implementation Detail**: Stripped routes/topology leakage from public / endpoint and reduced public /health endpoint to basic status, moving detailed metrics to authenticated /health/internal.
- **Commit SHA**: ``3fd832aa4d661279626bc6a521b9b3b7b1d21d8e``
- **Verification**: Verified via compilation and route checks. ✅

## Constant-time internal token compare

- **Implementation Detail**: Replaced standard string comparison operators with subtle.ConstantTimeCompare in all X-Internal-Token verification checks to mitigate timing attacks.
- **Commit SHA**: ``6698e3b29a27c0a7c2411fce02e9fa0fded9479c``
- **Verification**: Verified via test execution. ✅

## Reviewer Identity Gap Fix

- **Implementation Detail**: Added reviewer token auth to pending, review, and view doc endpoints, populated ReviewerID on review, and logged reviewer ID in security logs.
- **Commit SHA**: ``98533e7ae7b300f302d75d512b770128757a1582``
- **Verification**: Verified via auth-service integration tests. ✅

## Mask Plaintext OTP Codes in logs

- **Implementation Detail**: Restricted logging of plaintext OTP code values during signup and login 2FA in `services/auth-service/internal/handlers/auth.go#L229` and `services/auth-service/internal/handlers/auth.go#L371` to local environments only (`isLocal == true`).
- **Commit SHA**: ``9d7fa3bde676d280cd89cdd10106a75b51d81b37``
- **Verification**: Verified via auth-service integration/unit tests. ✅

## Gated Wallet Deposit Endpoint

- **Implementation Detail**: Gated the public `/users/wallet/deposit` endpoint behind a strict environment allow-list (`"local"` and `"test"` only). Refactored user-service configuration to read `APP_ENV` from config rather than inline, and added verification tests for both production and unset/empty environment configurations to ensure unverified deposits are securely blocked.
- **Commit SHA**: ``2fc19e412253afda248acab62720bdaa2bbe9da4``
- **Verification**: Verified via unit tests. ✅

## Owner-Authenticated Employee Provisioning

- **Implementation Detail**: Enforced owner authentication on the employee signup endpoint (`POST /auth/signup` when `role=employee`), requiring a valid JWT matching the requested `owner_id` with role `owner`. Added rate limiting and audit logging via `UNAUTHORIZED_EMPLOYEE_PROVISION_BLOCKED` security events. Documented in [ADR-0001](../adr/0001-owner-authenticated-employee-provisioning.md).
- **Commit SHA**: ``a6eef07e86b8ed57ad9d5e0fcdcb70f9fd832fe5``
- **Verification**: Verified via auth-service integration tests. ✅

## Per-Job Escrow Isolation, Zero-Value Fail-Closed & Concurrency Hardening

- **Implementation Detail**: Reverted unsafe GPS coordinates in price recalculations; persisted LockedEscrowAmount at booking; implemented atomic per-job escrow isolation in MongoDB with sequential dev fallbacks; capped payouts/refunds at the locked ceiling; added dynamic context-cancellation rollback and record deletion on TrackJob persistence failures; failed-closed with `escrow_amount_unrecorded` error if LockedEscrowAmount is zero; verified race-condition closure (CompleteJob vs CancelJob concurrency) through multi-goroutine tests. Documented in [ADR-0002](../adr/0002-per-job-escrow-integrity.md).
- **Commit SHA**: ``c78590dbcac14cfd11397ebe8dc47ac540c8a9ed``
- **Verification**: Verified via user-service integration and concurrency tests. ✅

## TrackJob Non-COD Payment APP_ENV Gate

- **Implementation Detail**: Restricts `TrackJob` to accept non-COD payment methods (such as `wallet` or bank cards) ONLY when `APP_ENV` is explicitly set to `"local"` or `"test"`. All other environments (including production and unset/empty configurations) continue to reject non-COD payments at the endpoint level to prevent un-auditable fund flows. This exception allows end-to-end integration and concurrency testing of the escrow paths.
- **Commit SHA**: ``ac569b962fe12c61e471744c6cfaf536b5b7ce36``
- **Verification**: Verified via user-service integration test suite (checking both rejection in production-like configs and bypass success in test config). ✅

## COD Completion Concurrency Hardening

- **Implementation Detail**: Hardened the Cash on Delivery (COD) job completion path to be atomic by updating the job document status from `active` to `completed` inside the completion transaction (using conditional `UpdateOne`). If the job status is already updated, subsequent concurrent completion attempts will fail to match the query and are rejected with a 409 Conflict. This prevents duplicate completions and duplicate ledger entries.
- **Commit SHA**: ``2c914b98d29631938e543bb770046666180a84b8``
- **Verification**: Verified via user-service concurrency tests. ✅

## OTP AES Key Fail-Closed Hardening

- **Implementation Detail**: Hardened `otpcrypto.NewCipher` to accept the current environment (`AppEnv`). In non-local and non-test environments, it now strictly requires `OTP_AES_KEY` to be set, to be a valid hex string, and to be exactly 32 bytes (after hex decoding), failing startup immediately with a panic/fatal log on any invalid key configuration rather than using the insecure ephemeral fallback or silent padding.
- **Commit SHA**: ``a2e1cffeda51294619c3d58426e77d498c3900ce``
- **Verification**: Verified via otpcrypto unit tests (`TestNewCipher_Validation`). ✅

## Employee Job Assignment Tenant Isolation Gating

- **Implementation Detail**: Gated job assignment in `TrackJob` to verify that the assigned employee actually belongs to the calling owner's tenant and has an active employee role. Refactored user-service's internal `isEmployeeActive` helper to `verifyEmployeeAssignment` to query auth-service and validate both `role == "employee"`, matching `tenant_id`, and `is_active == true` before allowing assignment. Documented in [ADR-0003](../adr/0003-employee-assignment-tenant-binding-check.md).
- **Commit SHA**: ``2c914b98d29631938e543bb770046666180a84b8``
- **Verification**: Verified via user-service integration test suite (`TrackJob Employee Assignment Gating`). ✅

## Geographic Coordinate Bounds Validation

- **Implementation Detail**: Enforced strict geographic coordinate bounds validation (latitude: -90 to 90, longitude: -180 to 180) in `TrackJob` and `UpdateJobLocation` inside `user-service`. Validates inputs at the handler level, rejecting invalid requests with 400 Bad Request (`invalid_coordinates`). For `UpdateJobLocation`, it generates a `[SECURITY WARNING]` and ships a security event `INVALID_COORDINATES_DETECTED` prior to checking other constraints.
- **Commit SHA**: ``f95367ee3f2cc95be594c795037c874d219269b9``
- **Verification**: Verified via user-service integration test suite (`TestUserServiceHandlers/Geographic_Coordinate_Bounds_Validation`). ✅

## Default APP_ENV Fail-Open Default Hardening

- **Implementation Detail**: Changed default `APP_ENV` fallback value from `local` to `production` when unset in `auth-service` and `user-service`. This ensures the application runs in the most restrictive mode (disabling dev OTP leak, enforcing mTLS, restricting payment methods, etc.) unless `APP_ENV` is explicitly set to `local` or `test`.
- **Commit SHA**: ``ba29c790c0eff5ecb758ff333b3c87d11d396d63``
- **Verification**: Verified via `services/auth-service/internal/config/config_test.go` and `services/user-service` suite. ✅

## Redis-Backed JWT Revocation Denylist & Logout Endpoint

- **Implementation Detail**: Added a cryptographically secure random UUID `ID` (`jti`) to all issued JWT claims. Integrated a Redis-backed denylist in `jwtutil.ValidateToken` that checks the JTI and fails-closed (rejects authentication and logs `[SECURITY CRITICAL]` security alerts) if Redis is unreachable. Added `jwtutil.RevokeToken` which sets the JTI in Redis with a TTL covering the remaining validity plus the 7-day refresh window to prevent session refresh abuse. Exposed `POST /auth/logout` endpoint in `auth-service` to revoke the caller's JWT.
- **Commit SHA**: ``9a534b461e9993cf27fc261a6723b6bc5aca866c``
- **Verification**: Verified via `services/auth-service/internal/handlers/auth_test.go` (`TestLogout_Denylist`). ✅

## Constant-Time Comparison in VerifyOTP

- **Implementation Detail**: Replaced direct string comparison of the decrypted OTP code with `subtle.ConstantTimeCompare` in `services/auth-service/internal/store/mongodb.go` to prevent timing side-channel attacks on OTP validation.
- **Commit SHA**: ``b798510b7350d1c0296cd753ab7094ab941b7610``
- **Verification**: Verified via auth-service integration tests. ✅

## 6-Digit OTP Entropy Hardening

- **Implementation Detail**: Increased OTP code length from 4 digits to 6 digits by updating `generate4DigitOTP` to `generate6DigitOTP` (generating a cryptographically random number in the `[0, 999999]` range and formatting with `%06d`), significantly increasing the keyspace.
- **Commit SHA**: ``6aa28cd9be19478fb813876c181896d678762335``
- **Verification**: Verified via auth-service integration tests. ✅

## Chat History Query Limit Hardening

- **Implementation Detail**: Enforced a hard upper bound of 500 on the `limit` query parameter for the `/chat/history` endpoint in `services/chat-service/internal/handlers/chat.go` to prevent potential Denial of Service (DoS) and out-of-memory issues from requesting unboundedly large history sets.
- **Commit SHA**: ``ec1d3278365f6e0d0e9fc53397198d2af91f3fbf``
- **Verification**: Verified via chat-service integration tests (`TestGetHistoryAccessControl/Limit_Clamping_Verification`). ✅

## Query-Param Tokens Accepted Tradeoff

- **Implementation Detail**: Documented transporting authentication tokens via query parameters for browser APIs that do not support custom headers (WebSockets, SSE, and ViewDocument short-lived URLs) as an accepted design tradeoff. Verified that the `api-gateway` access logs and error logs natively redact them by logging only the URL Path (`r.URL.Path`) rather than full request URLs.
- **Commit SHA**: ``2fcee8d14ed5aee74fe8441401ee496ce9720fcd``
- **Verification**: Verified by auditing `services/api-gateway/internal/middleware/logging.go` and `services/api-gateway/internal/proxy/proxy.go`. ✅

## Employee Toggle active enumeration hardening

- **Implementation Detail**: Collapsed specific owner-mismatch, non-employee, and not-found error returns inside the HTTP handler of `ToggleEmployee` into a generic `"employee not found or not authorized for this owner"` client-facing error message to prevent valid email enumeration by malicious owners, while retaining detailed backend logs.
- **Commit SHA**: ``0cd553d42f60ce8d03ed9f79651445602cfe981f``
- **Verification**: Verified via auth-service integration tests. ✅

## CI Pipeline Security Hardening & Flutter Validation

- **Implementation Detail**: Hardened the GitHub Actions CI pipeline by adding `govulncheck` vulnerability scanning and `gosec` static security analysis to the Go services build matrix, and integrated a Flutter job that runs `flutter analyze` and `flutter test` on the frontend workspace.
- **Commit SHA**: ``db5accacce8ece19091f83a54f5b43555e3ec6d8``
- **Verification**: Verified via pipeline configuration validation and syntax checking. ✅

## TrackJob Owner ID Spoofing & Regression Hardening

- **Implementation Detail**: Reverted the unsafe `owner_id` raw-ID fallback in `TrackJob` that allowed unverified raw hex string inputs. To address the customer-initiated booking flow where customers do not have access to the owner's JWT token, the handler now securely loads the service record from the database by its `service_id` and resolves the target `owner_id` server-side via `svc.TenantID`. If the client explicitly provides an `owner_id` (e.g. in owner-initiated flows), the backend strictly validates that it is a cryptographically verified JWT token and cross-checks that the resolved ID matches the service's `TenantID`, rejecting mismatch attempts with `403 Forbidden` and malformed values with `401 Unauthorized`. This prevents tenant bypass/IDOR and preserves existing owner-initiated flows.
- **Commit SHA**: ``651f9c025ce5244a364f6988293517c9951bfd46``
- **Verification**: Verified via `services/user-service/internal/handlers/handlers_test.go` (`TestUserServiceHandlers/TrackJob_Security_-_Owner_ID_server-side_resolution`). ✅

## TrackJob Customer Booking Employee Pre-Assignment Gating Correctness

- **Implementation Detail**: Corrected the execution order in the `TrackJob` handler to ensure that the owner ID is fully resolved (either decoded from the owner JWT or resolved server-side from `svc.TenantID` via database service lookup) before calling `verifyEmployeeAssignment`. This resolves a regression where customer-initiated bookings with employee pre-assignment failed because the assignment check was run with an empty owner ID.
- **Commit SHA**: ``bb405d3dea2c8f4464433e4635a7e4db563adc08``
- **Verification**: Verified via `services/user-service/internal/handlers/handlers_test.go` (`TestUserServiceHandlers/TrackJob_Customer-Initiated_Employee_Assignment_Gating`). ✅

## Handled Unchecked Response Writes in notification-service

- **Implementation Detail**: Captured and handled unchecked response writing and JSON encoding errors (gosec G104) across all handlers in `services/notification-service` to satisfy CWE-703 bounds. Implemented local helper functions, structured error handling to print log diagnostics on write failures, and added `ReadHeaderTimeout` to prevent Slowloris attacks. Resolved false positives via targeted inline `// #nosec` annotations.
- **Commit SHA**: ``4267ef27633bea94036287e535404174c92a92ce``
- **Verification**: Verified via local gosec analysis (`Issues: 0`) and microservice testing suite. ✅

## Codebase-wide G104 Unhandled Error Security Hardening
 
- **Implementation Detail**: Resolved 125 unhandled error warnings (gosec G104) across all Go microservices and shared libraries (`api-gateway`, `auth-service`, `chat-service`, `notification-service`, `user-service`, `shared/infra`). Consolidated response writing logic into a single shared helper package `shared/infra/handlerutil` (`WriteJSON` and `WriteBytes`), handled database transaction/connection cleanup errors, and configured local pre-push hook and CI checks to run G104 security scans codebase-wide.
- **Commit SHA**: ``123ffc76c66d7efce8653f99b709289418501392``
- **Verification**: Verified via local gosec analysis (`Issues: 0`) and microservice testing suite. ✅
 
## Codebase-wide Gosec Security Hardening and Full-Scope Verification
 
- **Implementation Detail**: Performed a full-scope unfiltered `gosec ./...` security audit across all 6 modules. Fixed Slowloris attack vectors (G112) by configuring `ReadHeaderTimeout: 3 * time.Second` on `http.Server` in `chat-service` and `user-service`. Mitigated local directory traversal vulnerabilities (G304) in `auth-service` document upload/open storage paths by introducing strict prefix path validation. Added explicit, justified `//nolint:gosec` exception annotations to handle false positives in G118 (WebSockets and async log shipping), G304/G703/G306 (documentation generation and local TLS file boots), G404 (non-cryptographic retry jitter), and G704/G706 (SSRF and sanitised log statements). Reverted CI config narrowing to enforce unfiltered, full-scope security scanning repository-wide.
- **Commit SHA**: ``fee8376f9171fe3c6031c89e72f4f8175f807646``
- **Verification**: Verified via local full-scope gosec checks (`Issues: 0` across all modules) and test suite execution. ✅

## Upgrade golang.org/x/crypto to v0.53.0 for Go 1.24 CI Compatibility and CVE Mitigation

- **Implementation Detail**: Upgraded `golang.org/x/crypto` from `v0.33.0` to `v0.53.0` across `auth-service`, `chat-service`, and `user-service`. Version `v0.53.0` is the highest release compatible with the Go 1.24 CI toolchain (since `v0.54.0` requires Go 1.25+) and resolves all known CVEs in `golang.org/x/crypto` (CVE-2025-22869, CVE-2025-47914, CVE-2025-58181).
- **Commit SHA**: ``60b23555eb268f51112fc13a9811386605d62626``
- **Verification**: Verified via `gofmt`, `go build ./...`, `go vet ./...`, `go test ./...`, and `govulncheck ./...` across all services. ✅

## Upgrade golang.org/x/crypto to v0.54.0 & Vulnerability Mitigation

- **Implementation Detail**: Upgraded `golang.org/x/crypto` from `v0.33.0` to `v0.54.0` across all backend Go modules (`auth-service`, `chat-service`, `notification-service`, `user-service`, `api-gateway`, `shared/infra`). This resolved 17 vulnerabilities present in older releases (leaving only the uncalled, unmaintained upstream `openpgp` finding).
- **Commit SHA**: ``5006ba499dd6545455af3b3bc5cd67f5f178ead5``
- **Verification**: Verified via `govulncheck ./...`, `go build ./...`, `go vet ./...`, and full test execution (`go test ./...`) across all backend modules. ✅

## CreateService Negative Pricing Validation

- **Implementation Detail**: Added validation in `services/user-service/internal/handlers/handlers.go` (`CreateService`) rejecting negative `TenantBasePrice` or `TenantPricePerKM` (`< 0`) with HTTP 400 (`invalid_pricing`), while permitting zero (`0.0`) for free listings/services per business requirements.
- **Commit SHA**: ``1cb62d2d9bb3101e1f714319fe4d1f68727dfee1``
## Explicit Tenant Scoping for Notification SSE Streams (Item #3)

- **Implementation Detail**: Enforced tenant scoping on notification SSE broadcasts unless explicitly flagged global via `n.Global = true` or `BroadcastGlobal()`, preventing empty `tenant_id` payloads from leaking cross-tenant.
- **Commit SHA**: ``cd39b4db8a567093d2f82ad443e5e54ffc142023``
- **Verification**: Verified via `go test ./services/notification-service/... -run TestSSEHub -v` (`TestSSEHub_BroadcastScopingAndFiltering`). ✅

## Enforce HTTPS Scheme on API Gateway Backend Routes under mTLS (Item #4)

- **Implementation Detail**: Updated API Gateway default backend target URLs from `http://` to `https://` and added startup validation rejecting non-HTTPS targets when client mTLS certificates are active.
- **Commit SHA**: ``f4887a45ae917adaa6f0c84f689bedc9d07977bf``
- **Verification**: Verified via `go test ./services/api-gateway/... -run TestLoad -v` (`TestLoad`). ✅

## Nil User Pointer Dereference Guard in VerifyOTP (Item #5)

- **Implementation Detail**: Added explicit `if user == nil` check in `VerifyOTP` handler returning `404 Not Found` cleanly if a user is deleted concurrently post-OTP verification.
- **Commit SHA**: ``62b343376260bb40371ea39b1d1dd34f2ce5c214``
- **Verification**: Verified via `go test ./services/auth-service/... -run TestAuthHandlers/VerifyOTP_Gaps -v` (`OTPUserDeletedClean404`). ✅

## Compensating Rollback Logic for Non-Transactional Escrow Fallback (Item #6)

- **Implementation Detail**: Added warning diagnostic log `[ESCROW] ⚠ non-transactional fallback in use` and step-by-step compensating rollback functions to revert job and wallet balance writes if secondary steps fail in non-transactional fallback mode.
- **Commit SHA**: ``397164d9b617a96bc48d0bb542df66e44dbc89c8``
- **Verification**: Verified via `go test ./services/user-service/... -run TestMongoDB_ReleaseEscrowFallbackCompensate -v`. ✅

## Token Cache TTL Reduction in chat-service (Item #7)

- **Implementation Detail**: Reduced chat-service `verifyToken` in-memory cache TTL from 60 seconds to 5 seconds to mitigate windows where deactivated/banned users could retain WebSocket access.
- **Commit SHA**: ``8fbbe25a9bfd92570e36322c7d569141fc480f6b``
- **Verification**: Verified via `go test ./services/chat-service/... -run TestVerifyToken -v`. ✅

## Collision-Resistant UUIDs for Chat Messages and Tickets (Item #8)

- **Implementation Detail**: Completed a two-part fix for chat service ID collision risks: ticket ID generation was updated to RFC 4122 v4 UUIDs via `jwtutil.GenerateUUID()`, and `PersistMessage` message `_id` generation was updated to `msg-<uuid>` format (replacing `time.Now().UnixNano()`). `readPump` was also updated to block live WS broadcasts if DB persistence fails.
- **Commit SHA**: ``3ee92f9861123c39255f5f55defb10c1581da2ea``
- **Verification**: Verified via `go test ./services/chat-service/... -run TestMongoDB_ConcurrentPersistMessageNoCollision -v` (asserting 500 concurrent messages receive unique RFC 4122 `msg-<uuid>` IDs). ✅

## TrackJob Escrow Rollback Failure Job Preservation (Item #1)

- **Implementation Detail**: Resolved deep-tester Item #1 (severity 7/10, priority 8/10). If `RollbackEscrow` fails during `TrackJob` escrow lock rollback (after `UpdateJobLockedEscrow` error), the job record is no longer deleted. Instead, the handler executes a single retry attempt and, if rollback still fails, marks the job in MongoDB with status `escrow_reconciliation_required` (`models.JobStatusEscrowReconciliationRequired`) along with durable failure context in `ReconciliationNote` and `EscrowFailureReason`. This preserves the stuck-funds job document for operator reconciliation without blocking HTTP client responses.
- **Commit SHA**: ``9b61b343e1f39ef8e8e57ce432542b2ad7fdc680``
- **Verification**: Verified via `go test ./services/user-service/... -run TestTrackJob_EscrowRollbackFailure_ReconciliationRequired -v` (asserting job survival, status change, failure notes, and 500 error response). ✅

## TrackJob Request Idempotency via Idempotency-Key Header (Item #2)

- **Implementation Detail**: Resolved deep-tester Item #2 (severity 6/10, priority 7/10). Added support for `Idempotency-Key` / `X-Idempotency-Key` headers and `idempotency_key` JSON field in `TrackJob`. `UserService` tracks request idempotency keys in a thread-safe map, returning the previously created job record (with HTTP 200 OK) on repeat requests rather than creating duplicate jobs or locking escrow twice.
- **Commit SHA**: ``0d8c4a7eac56c0b2d1623c1e06c28c2eebfd07be``
- **Verification**: Verified via `go test ./services/user-service/internal/handlers -run TestTrackJob_IdempotencyKey -v` (asserting initial 201 Created and subsequent 200 OK with identical job ID and single DB record). ✅

## Remediation: Redis-Backed TrackJob Request Idempotency & 24h TTL (Item #2 Remediation)

- **Implementation Detail**: Corrected an incomplete fix for Item #2 (original commit `0d8c4a7eac56c0b2d1623c1e06c28c2eebfd07be`), which relied on a single-instance in-memory `idempotencyJobs` map (`map[string]string`) with no TTL. Replaced the in-memory map with Redis-backed key storage (`idempotency:job:<key> -> job_id`) with 24-hour TTL (`24 * time.Hour`). Removed `idempotencyMu` and `idempotencyJobs` fields from `UserService` struct.
- **Commit SHA**: ``25d683cc39a59671c83e7c25277d8173bee5550f``
- **Verification**: Verified via `go test ./services/user-service/internal/handlers -run TestTrackJob_RedisBackedIdempotency_MultiInstanceAndTTL -v` (asserting cross-replica duplicate detection between independent `UserService` instances sharing Redis, and 24-hour TTL expiration key setting in miniredis). ✅

## Remediation: Explicit Token Role Enforcement in CreateService & TrackJob (Item #4 Remediation - Part 1)

- **Implementation Detail**: Corrected an incomplete fix for Item #4 (original commit `a81a75323978195cf3d22c40dbc2c9400adc89a7`), where `resolveToken(x)` had been defined as a no-op pass-through `resolveTokenWithRole(x)` with zero role filters. Replaced bare `resolveToken` calls in `CreateService` (`req.OwnerID`) and `TrackJob` (`req.OwnerID`, `req.UserID`, `req.EmployeeID`) with explicit role requirements (`"owner"`, `"user"`/`"customer"`, `"employee"`), returning HTTP 401 Unauthorized on role mismatch.
- **Commit SHA**: ``97a02c0dcf8220b86eec43daabe794d7aeda1460``
- **Verification**: Verified via `go test ./services/user-service/internal/handlers -run TestRoleEnforcement_CreateServiceAndTrackJob -v` (asserting 401 Unauthorized with role mismatch error for employee/owner token role violations). ✅

## Remediation: Explicit Token Role Enforcement in Job Lifecycle Handlers (Item #4 Remediation - Part 2)

- **Implementation Detail**: Extended Item #4 remediation (original commit `a81a75323978195cf3d22c40dbc2c9400adc89a7`). Replaced bare `resolveToken` calls in job lifecycle endpoints (`GetJob`, `CompleteJob`, `CancelJob`, `UpdateJobLocation`) with explicit `resolveTokenWithRole` checks, returning HTTP 401 Unauthorized on role mismatch.
- **Commit SHA**: ``5ff9c141a5395d0229bb11315ff7c15017f18bda``
- **Verification**: Verified via `go test ./services/user-service/internal/handlers -run TestRoleEnforcement_JobLifecycle -v` (asserting 401 Unauthorized with role mismatch error for unauthorized token roles). ✅

## Remediation: Explicit Token Role Enforcement in Wallet & Subscription Handlers (Item #4 Remediation - Part 3)

- **Implementation Detail**: Extended Item #4 remediation (original commit `a81a75323978195cf3d22c40dbc2c9400adc89a7`). Replaced bare `resolveToken` calls in financial and administrative endpoints (`GetWallet`, `WalletDeposit`, `GetSubscription`, `UpdateSubscription`) with explicit `resolveTokenWithRole(..., "owner")` checks, returning HTTP 401 Unauthorized on non-owner tokens.
- **Commit SHA**: ``c6da74b1db9263c3ae7c02fd6b0a815f91447b85``
- **Verification**: Verified via `go test ./services/user-service/internal/handlers -run TestRoleEnforcement_WalletAndSubscription -v` (asserting 401 Unauthorized with role mismatch error for employee/user token role violations). ✅

## Remediation: Explicit Token Role Enforcement in RateJob & GetRatings Handlers (Item #4 Remediation - Part 4)

- **Implementation Detail**: Completed Item #4 remediation across all remaining call sites (original commit `a81a75323978195cf3d22c40dbc2c9400adc89a7`). Replaced bare `resolveToken` calls in `RateJob` (`req.RatedBy`, `req.RatedUser`) and `GetRatings` (`targetUserID`) with explicit `resolveTokenWithRole` checks, completing 100% role enforcement across all 18 endpoint token resolution locations in `handlers.go`. Zero bare `resolveToken` calls remain without role validation.
- **Commit SHA**: ``45328ebbcf8eb4adcca143c6ed5101d0cfb97208``
- **Verification**: Verified via `go test ./services/user-service/internal/handlers -run TestRoleEnforcement_RateJobAndGetRatings -v` and grep-counting 0 remaining bare `resolveToken` calls in `handlers.go`. ✅

## Remediation: Removal of Dead resolveToken Function (Task 2)

- **Implementation Detail**: Following the complete migration of all 18 token resolution locations in `user-service` to `resolveTokenWithRole`, deleted the legacy `resolveToken` pass-through function from `services/user-service/internal/handlers/handlers.go`. Verified via grep search that zero references to `resolveToken` remain anywhere in the repository.
- **Commit SHA**: ``60e8939ace375df1240e08e35a7efeddd77630aa``
- **Verification**: Verified via `grep -rn "resolveToken(" services/` returning zero caller sites, and full `user-service` build, vet, and test suite passing. ✅

## Remediation: Centralized Friendly Error Messages Utility & Raw Error Leakage Prevention

- **Implementation Detail**: Created `frontend/lib/core/error_messages.dart` (`friendlyErrorMessage(Object? error)`) mapping `ApiClientException` status codes (400, 401, 403, 404, 409, 429, 5xx) to clear, user-facing English error messages without branching on backend raw error strings or leaking internal validation codes. Connectivity errors (`SocketException`, `TimeoutException`, etc.) map to a connection issue message, and unrecognized errors fall back safely. Replaced raw error string display (`e.toString().replaceFirst(...)` / `e.message`) across all frontend providers and screens while preserving developer debug logging via `debugPrint`. Added table-driven unit test suite in `frontend/test/error_messages_test.dart` asserting zero raw string or status code leaks.
- **Commit SHA**: ``fc4456efed1f6f86787943ad15133a7b9f0845e1``
- **Verification**: Verified via `dart format --set-exit-if-changed lib/`, `flutter analyze` (0 issues), and `flutter test` (all tests passed including 4 new friendly error mapping unit tests). ✅

## Negotiable Transport Pricing Atomic Compare-and-Swap TOCTOU Hardening (ADR-0009)

- **Implementation Detail**: Remediated TOCTOU race conditions in the negotiable transport pricing flow (`RespondPrice` and `ProposePrice` in `user-service`). Conditioned `UpdateJobAgreedPrice` and `UpdateJobCancellation` MongoDB updates on `status == AwaitingPriceResponse`, returning `job_state_changed` on zero matched documents. Conditioned `UpdateJobPriceProposal` updates on `status == AwaitingPriceResponse` and `proposed_price == nil` (or matching current proposal). If `RespondPrice` encounters `job_state_changed` post-escrow lock, it automatically executes compensating `performRollbackEscrow` to refund locked funds and returns `409 Conflict`. Added concurrent race test suites (`TestRespondPrice_ConcurrencyRace_DoubleEscrowPrevention` and `TestProposePrice_ConcurrencyRace_OverwrittenProposalPrevention`). Authored ADR-0009.
- **Commit SHA**: ``ffb75f989bd25ed0ac5bb54f46094a66ecad0080``
- **Verification**: Verified via `gofmt`, `go build ./...`, `go vet ./...`, and `go test ./...` in `user-service` (100% passing). ✅

## ADR-0009 Hardening: Job State Changed Escrow Lock Rollback Retry & Operator Reconciliation Fallback (Gap 3)

- **Implementation Detail**: Remediated a financial leakage risk in `RespondPrice` (`user-service`). When `UpdateJobAgreedPrice` returns `job_state_changed` post-escrow lock, if the initial `performRollbackEscrow` call fails, the handler now retries `performRollbackEscrow` once. If the retry also fails, the handler invokes `u.store.UpdateJobReconciliation` to mark the job as `models.JobStatusEscrowReconciliationRequired` with durable diagnostic details in `ReconciliationNote` and `EscrowFailureReason`, while still returning HTTP `409 Conflict` (`"error": "job_state_changed"`) to the client. Added unit test `TestRespondPrice_JobStateChanged_RollbackFailure_ReconciliationFallback` in `negotiation_concurrency_test.go`. Updated ADR-0009.
- **Commit SHA**: ``42e5843b3471bb272f1deef9846ad14b79414e35``
- **Verification**: Verified via `gofmt`, `go build ./...`, `go vet ./...`, and `go test ./...` in `user-service` (100% passing). ✅

## ListServices Spatial Coordinate Bounds Validation Hardening

- **Implementation Detail**: Resolved "Flagged for Next Pass" item 3 in `docs/audit/shared-module-review.md`. Added `isValidCoordinate(refLat, refLon)` bounds validation (`-90 <= lat <= 90`, `-180 <= lon <= 180`) to the `ListServices` handler in `user-service` when `near_by=true` or when explicit `lat`/`lon` query parameters are supplied. On out-of-range inputs, the handler logs a `[SECURITY WARNING]`, ships a `handlerutil.ShipSecurityEvent` (`INVALID_COORDINATES_DETECTED`), and returns HTTP `400 Bad Request` (`{"error": "invalid_coordinates"}`). Added 4 unit tests in `list_services_test.go`.
- **Commit SHA**: ``679667f9c994edd582d5c6d79226e78d1b277320``
- **Verification**: Verified via `gofmt`, `go build ./...`, `go vet ./...`, and `go test ./...` in `user-service` (100% passing). ✅

## Production Infrastructure & Database Authentication Hardening

- **Implementation Detail**: Remediated critical public database vulnerability where MongoDB (27017) and Redis (6380) had zero authentication and published open ports to `0.0.0.0` on host machines. Enforced MongoDB root credentials (`MONGO_INITDB_ROOT_USERNAME` / `MONGO_INITDB_ROOT_PASSWORD`) and Redis authentication (`REDIS_PASSWORD` / `--requirepass`). Updated all microservice `MONGO_URI` and `REDIS_URI` strings. Restricted host port bindings for `mongo` (`127.0.0.1:27017:27017`) and `redis` (`127.0.0.1:6380:6379`) to localhost, preventing public internet database access while preserving inter-service communication across internal Docker bridge `saas-net`. Audited environment secrets in `infrastructure/.env.example`. Authored `docs/DEPLOYMENT.md` for generic Docker cloud VPS deployment.
- **Commit SHA**: ``49572882a98844de0f688fa97275c9a835dc93ce``
- **Verification**: Verified via `docker compose -f infrastructure/docker-compose.yml config` (syntactically valid), local Docker Compose startup (`saas-mongo` and `saas-redis` reporting `healthy`, all 5 microservices running), `curl -k https://localhost:8080/health` (`{"status":"ok"}`), and `.githooks/pre-push` gate passing 100%. ✅

## Reviewer/Admin KYB-KYE UI Removal per ADR-0013

- **Implementation Detail**: Enforced ADR-0013 security scope boundary by removing all administrative KYB/KYE reviewer screens (`kyb_kye_review_screen.dart`), document viewer dialogs (`document_viewer_dialog.dart`), AppBar actions (`reviewer_queue_button`), and dead provider methods (`fetchPendingSubmissions`, `fetchDocumentBytes`, `reviewSubmission`) from the consumer mobile app (`frontend/`). Prevents bundling reviewer/admin review workflows and administrative endpoints inside the public binary where decompilation/reverse-engineering could leak administrative review logic and API structures. Annotated `STATUS.md` and updated `ADR-0013`.
- **Commit SHA**: ``ab3ef6f6f76dbeafeb40c4f79f11b3002822f87e``
- **Verification**: Verified via `dart format .`, `flutter analyze` (0 issues), `flutter test` (100% passing), `make ci`, and `make push`. ✅


















## TrackJob Idempotency Replay Required Authentication & Per-User Key Namespacing (Pre-Auth Job Disclosure)

- **Implementation Detail**: Fixed a HIGH-severity unauthenticated information disclosure in `TrackJob` (`services/user-service/internal/handlers/jobs_handlers.go`). The Redis idempotency replay lookup (`idempotency:job:<key>`) executed BEFORE any JWT validation — the first `resolveTokenWithRole` call occurred only later in the handler. Any unauthenticated caller who obtained or guessed a victim's client-chosen `Idempotency-Key` / `X-Idempotency-Key` header / `idempotency_key` body field received the victim's full job object (pickup coordinates, payment method, participant IDs) with HTTP 200 OK and zero authentication. The lookup now runs immediately after the customer's identity is resolved from a signed JWT, and keys are namespaced per user as `idempotency:job:<userID>:<key>` (24h TTL unchanged), so cross-user key replay can never match another user's record. `saveIdempotencyKey` signature extended with the resolved user ID; all four write sites updated.
- **Commit SHA**: ``152c3d54d6d12e2ea3ac93cff5a7f98d46a686fc``
- **Verification**: New regression test `TestTrackJob_IdempotencyReplayRequiresAuthentication` passes (asserts HTTP 401 for unauthenticated key replay, asserts the victim's job ID never appears in the attacker response, and asserts authorized duplicates still return the original job with 200 OK). Existing `TestTrackJob_RedisBackedIdempotency_MultiInstanceAndTTL` updated for the namespaced key format and passing. Full `go test ./... -count=1` in `user-service` passes (config, handlers, models, store all `ok`). ✅

## Exact-Locked Escrow Release & Refund (Reprice-Down Fund Entrapment)

- **Implementation Detail**: Fixed a HIGH-severity financial defect in `CompleteJob` and `CancelJob` (`services/user-service/internal/handlers/jobs_handlers.go`). Both handlers recomputed the settlement amount from the service's CURRENT pricing at settlement time (`svc.TenantBasePrice + dist*svc.TenantPricePerKM`, or `AgreedPrice`) and applied only an upper cap at `LockedEscrowAmount` — with no floor. When a tenant owner lowered service prices after booking (allowed any time via `UpdateService`, no job-state check), the recomputed amount fell below `LockedEscrowAmount`; the release/refund then moved only the smaller amount, permanently stranding the residual in `wallet.escrow_balance` on a job that was now `completed` or `cancelled` — unreachable by any flow, silently corrupting wallet accounting. Both handlers now settle on exactly `job.LockedEscrowAmount`. The recompute is retained solely for COD collection logging and ADR-0007 delivery/shipping reconciliation distance math (whose prior floor-then-cap composition already resolved to exactly the locked amount, so that category's behavior is unchanged). ADR-0002 wallet isolation is preserved: no release can ever draw down other jobs' escrow.
- **Commit SHA**: ``f0a2a39b82f9cef4614b73d93f01f77f3da86957``
- **Verification**: New regression test `TestEscrowRepriceDown_ReleasesAndRefundsExactLockedAmount` passes (repriced-down service; completion pays exactly 155.60 == locked with wallet-delta assertion; cancellation refunds exactly 80.00 == locked). Legacy sub-test `CompleteJob_Location_Recalculation_original_coordinates_check/Escrow_Path` updated — it had asserted the stranding outcome (10.0 recomputed payout on a 100.0 lock) as correct — and now asserts 100.0. Full `go test ./... -count=1` in `user-service` passes (config, handlers, models, store all `ok`). ✅

## Production OTP Dispatcher Fail-Fast (Removed Silent Stdout-Mock Fallback)

- **Implementation Detail**: Fixed a HIGH-severity OTP leakage path in `services/auth-service/cmd/main.go`. Outside local environments, an unset `RESEND_API_KEY` silently selected `MockSMSDispatcher`, which prints every OTP code to stdout (`[MOCK-SMS] 📱 OTP dispatched to <email> → code: <code>` plus a boxed OTP block) — i.e., every 2FA/signup/password-reset code for the entire platform landed in container logs, recoverable by anyone with log access. Extracted dispatcher selection into a testable `selectOTPDispatcher(appEnv, resendAPIKey, resendFromEmail)` helper: `local|dev|development` keep the stdout mock; every other environment now REQUIRES `RESEND_API_KEY` and returns a startup error otherwise; `main()` `log.Fatalf`s on that error so the service refuses to boot in an insecure mode. AI_CONTEXT.md's "Mock OTP SMS/Email Dispatcher" decision entry updated in the same commit to describe fail-fast semantics instead of the removed fallback.
- **Commit SHA**: ``b024bd00582141f9bdc15b6d72b7be40d3ad584b``
- **Verification**: New table test `TestSelectOTPDispatcher` passes all 4 subtests (local/dev/development → MockSMS; production+key → Resend; production without key → error mentioning `RESEND_API_KEY` with nil dispatcher; arbitrary non-local env without key → error). Full `go test ./... -count=1` in `auth-service` passes across all 10 packages. ✅

## Post-Handshake WebSocket Flood Guards & SSE Stream Registration Limits

- **Implementation Detail**: Closed two resource-exhaustion vectors. (1) `chat-service` (`services/chat-service/internal/handlers/chat.go`): the 30/min `wsLimiter` applied only at connect time; after handshake, each inbound `message` triggered an outbound `canAccessChannel` authz HTTP call, a MongoDB persist, and a hub fan-out — and each `subscribe` another authz call — all unthrottled per client. Added Redis-backed per-client limiters `chat:wsmsg` (60/min) and `chat:wssub` (30/min), checked inside `readPump` BEFORE authorization; exceeded requests receive a structured `{"type":"error","error":"rate_limited",...}` frame via a new non-blocking `sendWSError` helper and are neither persisted nor broadcast. (2) `notification-service` (`services/notification-service/internal/handlers/handlers.go`): the shared limiter guarded only `POST /notifications/send`; `GET /stream` registered SSE clients with no rate limit and no connection cap. Added a `notification:stream` registration limiter (30 opens/min per tenant identity, returning 429 JSON before SSE headers) plus an in-process concurrent-stream cap (`maxConcurrentStreamsPerTenant = 5`) using mutex-guarded slot acquire/release around the handler lifecycle.
- **Commit SHA**: ``56c8d04002cf8c58fbde97cc968d75447cfbdac3``
- **Verification**: New tests all pass: `TestWebSocket_MessageRateLimiting` (real WebSocket flood of 70 messages → at least one `rate_limited` error frame, accepted count < sent count, persisted history equals accepted count exactly), `TestStream_RegistrationRateLimiting` (30 opens OK, 31st → 429), `TestStream_ConcurrentStreamCapPerTenant` (6th concurrent stream → 429; after closing held streams, new streams admitted again). Pre-existing WS/SSE suites (`TestHandleWebSocket_RateLimiting`, `TestStreamAndVerifyAndResolve`, `TestStreamAuthScenarios`, `TestStreamTenantScopingAndIsolation`) still pass. Full `go test ./... -count=1` passes in both `chat-service` and `notification-service`. ✅

## FCM Frontend Stub Replaced With Real firebase_messaging Adapter & False Verification Claims Corrected

- **Implementation Detail**: `DefaultPushMessagingAdapter` (`frontend/lib/services/push_notification_service.dart`) was a stub: `getToken()` fabricated `'fcm-device-token-<DateTime.now().millisecondsSinceEpoch>'` strings, `deleteToken()` only debug-printed, and `onForegroundMessage` was an empty body — despite STATUS.md Phase 12 and AI_CONTEXT.md marking frontend FCM registration "[VERIFIED]". Consequence: real push delivery never worked from the Flutter client, and every login/signup/auto-login registered a garbage timestamp token into auth-service's `device_tokens` collection (multi-device upsert), polluting production data. The adapter is now genuinely backed by `firebase_messaging` (`FirebaseMessaging.instance.getToken()`/`deleteToken()`, `FirebaseMessaging.onMessage` listener with subscription management) and degrades to safe no-ops — returning null and registering nothing — when `Firebase.apps` is empty, since no build currently ships Firebase project configuration. Added `firebase_core ^2.32.0` as a direct dependency (matches the resolved transitive version). STATUS.md Phase 12 header and Commit 3 entry rewritten from "[100% COMPLETE & VERIFIED]"/"[VERIFIED]" to explicit partial-verification wording documenting the correction; AI_CONTEXT.md entry likewise corrected. End-to-end push delivery remains explicitly UNVERIFIED until `google-services.json` / `GoogleService-Info.plist` and `Firebase.initializeApp()` land in mobile builds.
- **Commit SHA**: ``aee511874be9aad86090651573c08b763b129007``
- **Verification**: New regression suite `frontend/test/default_push_adapter_test.dart` passes (without initialized Firebase: `getToken()` returns null instead of a fake token; `deleteToken()` completes; `onForegroundMessage` is a safe no-op). Existing `test/fcm_push_registration_test.dart` passes 7/7 with injected mocks. Full local gate: `flutter analyze` → "No issues found!", full `flutter test` → "+288: All tests passed!". ✅

## Atomic SETNX Idempotency Reservation & Disconnect-Safe Key Writes (TrackJob Double-Booking)

- **Implementation Detail**: Closed two residual TrackJob idempotency defects. (1) The replay check was GET-then-insert: two concurrent requests sharing one idempotency key could both miss it, both insert a job, and both lock escrow — duplicate funded bookings. `reserveIdempotencyKey` (`services/user-service/internal/handlers/handlers.go`) now atomically claims the per-user slot via Redis `SET NX` with an `__pending__` marker (24h TTL). Concurrent losers receive the winner's job as an idempotent 200 replay, or an explicit `409 duplicate_request_in_progress` while the winner is still in flight; every validation-failure exit releases the pending reservation through one deferred guard gated on a `jobRecorded` flag, so stale reservations never block legitimate retries. Redis unavailability degrades to logged non-idempotent operation, matching prior availability behaviour. (2) `saveIdempotencyKey` wrote through the inbound request context: a client disconnect between job creation and key-set cancelled the write and dropped the key, so the client's retry created a second funded booking. The function signature no longer accepts a request context — bookkeeping is unconditionally `context.Background()`.
- **Commit SHA**: ``770211ed2a8eb3fd22a67be69d8dbefef093d139``
- **Verification**: New regression tests in `idempotency_race_regression_test.go`: `TestSaveIdempotencyKey_SurvivesRequestContextCancellation` (deterministic dropped-key repro — FAIL pre-fix with "idempotency key was NOT written when the request context was canceled", PASS post-fix) and `TestTrackJob_ConcurrentDuplicateIdempotencyKey` (race repro — FAILED 25/25 pre-fix runs via `-count=25` with "GET-then-insert race reproduced ... returned 201 Created", 0/25 post-fix runs). Pre-existing idempotency suites (`TestTrackJob_RedisBackedIdempotency_MultiInstanceAndTTL`, `TestTrackJob_IdempotencyReplayRequiresAuthentication`) still pass. Full `go test ./... -count=1` in `user-service`: config/handlers/models/store all `ok`. ✅

## Rate Limiters on Fund-Moving Endpoints (CompleteJob / Reconciliation Resolve / Payouts)

- **Implementation Detail**: Four fund-related `user-service` endpoints had zero rate limiting: `POST /users/jobs/complete` (escrow release), `POST /users/jobs/reconciliation-resolve` (escrow settlement), `POST /users/wallet/payout/request`, and `GET /users/wallet/payout/requests`. An authenticated caller could invoke them without bound. Added three identity-keyed Redis limiters following the established per-endpoint architecture (ADR-0016): `user:complete_job` (30 req/min, keyed by resolved requester), `user:reconciliation_resolve` (30 req/min, keyed by resolved owner), and `user:payout` (30 req/min shared across both payout endpoints, keyed by resolved owner). All checks run immediately after JWT identity resolution so unauthenticated traffic never consumes limiter budget. Also corrected the long-standing inaccurate AI_CONTEXT.md claim that reconciliation-resolve was "rate-limited (30 req/min)" — pre-fix only the queue endpoint was.
- **Commit SHA**: ``0b06229a6a00cb50405171c1822439479a2c6d7f``
- **Verification**: Pre-fix flood repro failed all four new tests with literal output including `expected 31st RequestPayout call to be rate limited (429), got 201 (codes=[201 201 ... 201])` — thirty-one consecutive successful payout requests. Post-fix all four pass (`TestCompleteJob_RateLimiting`, `TestResolveReconciliation_RateLimiting`, `TestRequestPayout_RateLimiting`, `TestGetPayoutRequests_RateLimiting`), each asserting zero 429s within the 30-call budget and exactly a 429 on call 31. ✅

## Escrow-Failure Warning Sanitization (Cross-Tenant Wallet Balance Disclosure)

- **Implementation Detail**: On escrow-lock failure, both `TrackJob` (unfunded-booking response) and `RespondPrice` (price-acceptance failure) in `services/user-service/internal/handlers/jobs_handlers.go` embedded the raw store error — `"insufficient withdrawable balance: have %.2f, need %.2f"` — inside a client-facing `warning` JSON field. Any customer booking a job (or accepting a transport price) could therefore read the target owner's exact withdrawable balance and the requested amount, a cross-tenant financial disclosure. Both responses now carry generic warnings ("escrow lock failed — owner must deposit funds…") while the underlying error remains server-side only. Additionally hardened `NewUserService`: limiter construction is nil-safe, so a nil Redis client yields nil limiter fields (with matching absence guards on the new CompleteJob / reconciliation-resolve / payout limiter call sites) instead of wrappers around a nil-Redis limiter that panicked on first use and broke nil-Redis test harnesses.
- **Commit SHA**: ``d74f015dfe0bdafe44fd0a4f07a72695f2ef1c81``
- **Verification**: New regression tests captured the leak verbatim pre-fix (`"warning":"insufficient withdrawable balance: have 0.00, need 47.35"` present in the literal 201 response body for TrackJob; equivalent leak on RespondPrice acceptance with a zero-balance owner) and assert absence post-fix: `TestTrackJob_EscrowFailureWarningDoesNotLeakOwnerBalance` and `TestRespondPrice_EscrowFailureWarningDoesNotLeakOwnerBalance` both PASS. Full user-service module: config/models/store `ok`; handlers package green across three consecutive full runs after one transient load-related failure of `TestCompleteJob_ADR0007_Phase1_SettlementAndReconciliation` during an intermediate state (nil-limiter panic), which was root-caused to the constructor issue above and fixed in this commit rather than retried away. ✅

## Service Write-Path Coordinate Validation (Spatial Index Poisoning & Document Leak)

- **Implementation Detail**: `CreateService` and `UpdateService` (`services/user-service/internal/handlers/services_handlers.go`) accepted arbitrary coordinates — only the read path (`ListServices`) validated. Consequences observed in repro: (1) create with latitude 9999 returned 201 while MongoDB silently rejected the `2dsphere` geo index entry, poisoning proximity search results for all customers; (2) update with longitude 9999 returned a 500 whose body was the raw MongoDB driver error, echoing the entire service document (IDs, pricing, coordinates) back to the client. Both write paths now enforce `isValidCoordinate` (-90..90 / -180..180) immediately after request decoding, returning `400 invalid_coordinates` and shipping an `INVALID_COORDINATES_DETECTED` audit event consistent with the existing ListServices pattern.
- **Commit SHA**: ``6827d664f2f9b0e0b6a122bd52a1ee52ff31112c``
- **Verification**: New regression tests: `TestCreateService_RejectsInvalidCoordinates` (pre-fix literal failure: "expected 400 ... got 201" with persisted GeoJSON `"coordinates":[31,9999]`; post-fix PASS) and `TestUpdateService_RejectsInvalidCoordinates` (pre-fix literal failure: 500 body containing "Can't extract geo keys ... Longitude/latitude is out of bounds, lng: 9999"; post-fix PASS). Full user-service module suite passes (config/handlers/models/store all `ok`). ✅

## Customer Role Alias on Job History & Auth Secret-Comparison Hardening

- **Implementation Detail**: (1) `GET /users/jobs/mine` (`services/user-service/internal/handlers/jobs_handlers.go`) enforced `claims.Role != "user"` only, returning 403 to customers holding valid `"customer"`-role JWTs issued by other auth flows; both aliases are now accepted. (2) auth-service hardening in `internal/handlers/auth.go`: the `X-Gateway-Secret` comparison inside `getClientIP` (which gates XFF trust for audit attribution) switched from `==` to `subtle.ConstantTimeCompare` — a behavior-preserving change with no externally observable test; and `authenticateReviewer` gained the same empty-secret precondition already present in `GetUser`, because `subtle.ConstantTimeCompare` over two empty byte slices returns 1 and would authenticate any caller if the configured internal token were ever empty (defense-in-depth; `config.Load` already rejects empty tokens at startup).
- **Commit SHA**: ``7b7e76962e93680cb1e80094fdf45dfc6c2ab5f4``
- **Verification**: New regression test `TestGetCustomerJobs_AcceptsCustomerRoleAlias` — pre-fix literal failure: "expected 200 for role=customer on /users/jobs/mine, got 403 {"error":"access denied: customer role required"}"; post-fix PASS with exactly one job returned. Full auth-service suite passes (all 10 packages `ok`); full user-service suite passes (config/handlers/models/store all `ok`). ✅

## Authentication Precedes Location-Throttle Reservation (Unauthenticated Throttle-Window Starvation)

- **Implementation Detail**: `UpdateJobLocation` (`services/user-service/internal/handlers/jobs_handlers.go`) executed its atomic Redis throttle reservation — a Lua EVAL claiming the per-job `loc:inflight:<job_id>` slot and evaluating the minimum-interval budget — BEFORE resolving the requester's JWT. Any unauthenticated caller who knew (or guessed) a job ID could continuously claim the reservation window, causing the assigned employee's legitimate location updates to receive 429 `too_many_requests ("already in progress")`, and burning Redis EVAL capacity per attack request. `resolveTokenWithRole` is now hoisted above the reservation; the unauthenticated path returns 401 without touching Redis, and all post-reservation failure paths retain their existing in-flight cleanup.
- **Commit SHA**: ``b4a1e66807bb0ae842f96da16461c90cdd74d472``
- **Verification**: New regression test `TestUpdateJobLocation_NoThrottleReservationBeforeAuth` instruments the Redis client with a counting hook and asserts an invalid-token request produces zero EVAL invocations. Pre-fix literal failure: `THROTTLE RESERVATION BEFORE AUTH: unauthenticated request triggered 1 throttle EVAL call(s); authentication must precede the reservation`. Post-fix: 3/3 passes; full user-service suite passes (`go test ./... -count=1`: config/handlers/models/store all `ok`). ✅

## Subscription POST Rate Limiter & Stable Upsert ID

- **Implementation Detail**: Two defects in `POST /users/subscription`. (1) It was the only state-changing user-service endpoint without a per-endpoint limiter — 31 consecutive subscription upserts produced zero 429s. Added `subscriptionLimiter` (`user:subscription`, 30 req/min, verified-identity-keyed, post-authentication, nil-safe per the established limiter pattern). (2) Latent write defect exposed by the flood repro: `UpsertSubscription` regenerated `sub-%d` `_id` on every call, so ANY repeat upsert failed with MongoDB's immutable-`_id` error (500 from call 2 onward) — meaning tier changes after an initial POST were broken entirely. The store now preserves the tenant's existing document ID on update.
- **Commit SHA**: ``0ae986cb46d6f1e8b89178121f0fe2d4014ba297``
- **Verification**: New flood regression `TestSubscriptionPOST_RateLimiting`. Pre-fix literal failure: `SUBSCRIPTION POST UNTHROTTLED: 31 consecutive POST /users/subscription requests produced no 429 (last status 500); endpoint lacks a per-endpoint rate limit` (the 500 itself demonstrating defect 2). Post-fix: limiter engages within budget, 3/3 passes; full user-service suite passes. ✅

## Server-Side Pagination for GetLedger & GetRatings (Unbounded-Response DoS Surface)

- **Implementation Detail**: `GET /users/ledger` and `GET /users/ratings` materialized every matching MongoDB document into memory and serialized it — an unbounded-response DoS surface and slow-query risk at scale. Added server-side paging in `services/user-service/internal/store/mongodb.go` via shared `clampPage` normalization with exported bounds (`DefaultLedgerPage` 100 / `MaxLedgerPage` 500; `DefaultRatingsPage` 50 / `MaxRatingsPage` 200), `SetLimit`/`SetSkip`, and newest-first sort for stable rating pages. Handlers accept `?limit=`/`?offset=` (malformed/negative values fall back to defaults) and echo the effective `limit`/`offset` alongside existing keys, keeping prior response shapes backward compatible.
- **Commit SHA**: ``c6184303de8625b4b531525729a2721a2e61c257``
- **Verification**: New regression tests `TestGetLedger_DefaultCapAndPagination` / `TestGetRatings_DefaultCapAndPagination`. Pre-fix literal failures: `UNBOUNDED LEDGER READ: default page returned 150 entries, want 100 (server-side default cap)` + `limit param ignored: got 150, want 10`; `UNBOUNDED RATINGS READ: default page returned 60 ratings, want 50` + both params ignored. Post-fix: all assertions pass 3/3 runs; full user-service suite passes. ✅

## HTTP Server ReadTimeout & IdleTimeout Across All 5 Microservices (Slowloris / Idle-Connection Exhaustion)

- **Implementation Detail**: Every Go HTTP server (`api-gateway`, `auth-service`, `chat-service`, `notification-service`, `user-service` `cmd/main.go`) set only `ReadHeaderTimeout: 3s` — request BODIES could trickle in indefinitely (slow-loris style resource exhaustion) and idle keep-alive connections were never reaped. All five servers now set `ReadTimeout: 30s` and `IdleTimeout: 120s`. `WriteTimeout` is deliberately unset on every server: SSE streams (`notification-service`, gateway-proxied) and long-lived responses must never be truncated by a write deadline — this preserves the streaming guarantees established by the resilience-wrapper SSE fix.
- **Commit SHA**: ``79d2312f8173b8dbb102d48a7696f69822fe9a2c``
- **Verification**: Literal grep across all 5 `cmd/main.go` files shows the identical block (ReadHeaderTimeout 3s + ReadTimeout 30s + IdleTimeout 120s, zero WriteTimeout) — output pasted in the delivery log. No unit test asserts main() literals (server construction is not extracted behind an interface; noted honestly). Verified via `go build ./...`, `go vet ./...`, and full user-service suite pass. ✅

## Account-Enumeration Oracle Closure (Login Timing + ToggleEmployee Wording/Status)

- **Implementation Detail**: Three oracles revealed whether an account exists despite uniform-looking errors. (1) `Login` (`services/auth-service/internal/handlers/auth.go`): the user-not-found branch performed NO bcrypt work while the wrong-password branch paid full cost-10 (~45ms) — a response-time side channel; not-found now compares the supplied password against `dummyBcryptHash` (a valid bcrypt digest of an unknown random string), making both paths indistinguishable in cost. (2) `ToggleEmployee` owner lookup: nonexistent owner returned `"invalid owner credentials or owner does not exist"` vs wrong-password `"…password does not match"` — both now return identical `(403, "invalid owner credentials")` with dummy-hash timing parity on the not-found path. (3) `ToggleEmployee` employee resolution: nonexistent employee returned 404 vs foreign-tenant employee 400 with identical message text — both now return `(400, "employee not found or not authorized for this owner")`.
- **Commit SHA**: ``b5ae0789f2d17ec4e8f341dc862b2d04d8edde5a``
- **Verification**: New regression tests. Pre-fix literal failures: `OWNER EXISTENCE ORACLE: wrong-password → (403, {"error":"invalid owner credentials or password does not match"}); nonexistent-owner → (403, {"error":"invalid owner credentials or owner does not exist"})`; `EMPLOYEE EXISTENCE ORACLE: foreign-tenant employee → (400, …); nonexistent employee → (404, …)`; timing test pre-fix would show sub-millisecond unknown-email path (post-fix averages logged: `avg unknown-email=45.1ms avg wrong-password=44.9ms`, threshold 20ms floor catches a regression to no-bcrypt). Two vacuous-test traps were caught during repro and fixed: KYC-gate short-circuit (both employee probes stopped at `KYC approval is pending` until owner2 was approved via `UpdateKYCStatus`) and IP-lockout interaction (probes reordered after signup, counts kept under the lockout threshold). Post-fix: all oracle tests pass 3+/5+ consecutive runs; full auth-service suite passes (`go test ./... -count=1`: handlers/models/otp/otpcrypto/storage/store all `ok`). ✅

## Reviewer & Support-Agent Token Hashing at Rest (+ Serialization-Leak Guard)

- **Implementation Detail**: KYB/KYE reviewer tokens (`auth-service`) and support-agent bearer tokens (`chat-service`) were stored as plaintext in MongoDB — any database compromise yielded every administrative credential. `SupportAgent.Token` additionally carried a live `json:"token"` tag, serializing the credential into any accidental marshal. Both stores now persist SHA-256 hex digests on write (`hashToken` / `hashAgentToken`); lookups hash the presented credential before querying, with a single legacy-plaintext fallback query preserving pre-hardening rows during the migration window (documented; re-onboarding rotates those). The agent struct's token is now `json:"-"`. Onboarding CLI tools (`onboard-reviewer`, support-agent creation) inherit the hashing automatically by writing through the same store methods.
- **Commit SHA**: ``8f8888aef8108796197490ab634a592af5e7b072``
- **Verification**: New regression tests `TestReviewerTokenHashedAtRest` / `TestSupportAgentTokenHashedAtRest` read the raw persisted document via `DatabaseForTesting()` / direct collection access. Pre-fix literal failures: `PLAINTEXT TOKEN AT REST: reviewers collection stores the raw bearer token "rvw-plaintext-secret-…" want digest "46488afe78c6..."`; same for support_agents plus `TOKEN SERIALIZATION LEAK: marshalled agent contains token material: {"agent_id":"agent-hash-1",...,"token":"agt-plaintext-secret-…"}`. Post-fix: 3/3 passes each; legacy chat store test updated to assert the hashing contract; full auth-service AND chat-service suites pass. ✅

## Reviewed Decision: ToggleEmployee Owner Password in Request Body (Accepted, Documented)

- **Decision**: The owner re-authentication password for employee freeze/unfreeze remains in the request body (`owner_password`). **Rationale**: it is required for genuine step-up authentication of a destructive action; transport is exclusively TLS/mTLS; the value is never logged (all ToggleEmployee log lines audited — emails only), never persisted, never serialized back; enumeration/timing oracles around this path were closed in commit `b5ae0789f2d17ec4e8f341dc862b2d04d8edde5a`. Removing the field would require a coordinated backend+frontend contract migration (short-lived step-up token) that cannot land safely in a backend-only parallel session against an unreleased frontend branch. **Flagged for future hardening**: dedicated re-auth endpoint issuing a short-lived step-up token.

## FCM Client No Longer Sends X-Internal-Token to External Host

- **Implementation Detail**: `notification-service`'s FCM client (`services/notification-service/internal/fcm/fcm.go`) attached `X-Internal-Token` to every push request, including those addressed to the default `https://fcm.googleapis.com/...` endpoint when no internal relay was configured — leaking a shared intra-cluster secret to an external host. The client now records whether an explicit `FCMEndpointURL` relay was configured and attaches the header ONLY in that mode; default Google-mode requests carry no internal auth material.
- **Commit SHA**: ``51196fa5d27ef0ec0f8ad108cb6ebf8cac662e88``
- **Verification**: New white-box regression `TestFCMPush_NoInternalTokenToGoogle` intercepts a default-mode client's outbound call via httptest (endpoint overridden without changing endpoint MODE). Pre-fix literal failure: `INTERNAL TOKEN LEAKED TO EXTERNAL HOST: X-Internal-Token="secret-internal-token" was sent to the default (Google) endpoint`. Companion test `TestFCMPush_InternalTokenPresentOnCustomRelay` asserts relay mode still authenticates. Full notification-service suite passes (`go test ./...`: config/fcm/handlers/hub all `ok`). ✅

## Process Note: Missed Test Files in c618430

- **Detail**: Two store test files updated by the GetLedger/GetRatings signature change were left unstaged in commit `c6184303de8625b4b531525729a2721a2e61c257`; committed separately as `ad9779f37f11e20472c1b9298828ce39ba2222b9` (test-only, mechanical `(0,0)` default-page args). Recorded for transparency per repo honesty rules.
