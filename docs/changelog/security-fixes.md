# Security Fixes Changelog

This file tracks historical entries for the primary category: **Security Fixes Changelog**.

---

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

- **Implementation Detail**: Hardened the Cash on Delivery (COD) job completion path to be atomic by updating the job document status from `active` to `completed` inside `DeductCODFee`'s transaction (using conditional `UpdateOne`). If the job status is already updated, subsequent concurrent completion attempts will fail to match the query and are rejected with a 409 Conflict. This prevents double platform fee deductions and duplicate ledger entries.
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
- **Commit SHA**: `5006ba499dd6545455af3b3bc5cd67f5f178ead5`
- **Verification**: Verified via `govulncheck ./...`, `go build ./...`, `go vet ./...`, and full test execution (`go test ./...`) across all backend modules. ✅

## CreateService Negative Pricing Validation

- **Implementation Detail**: Added validation in `services/user-service/internal/handlers/handlers.go` (`CreateService`) rejecting negative `TenantBasePrice` or `TenantPricePerKM` (`< 0`) with HTTP 400 (`invalid_pricing`), while permitting zero (`0.0`) for free listings/services per business requirements.
- **Commit SHA**: `1cb62d2d9bb3101e1f714319fe4d1f68727dfee1`
- **Verification**: Verified via `go test ./services/user-service/... -run TestCreateService -v` (`TestCreateService_ExtraEdgeCases`). ✅















