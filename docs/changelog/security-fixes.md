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
- **Commit SHA**: ``current``
- **Verification**: Verified in `user-service/internal/handlers/handlers.go`. ✅

## WebSocket Message Authorization

- **Implementation Detail**: Gated chat message broadcasts by canAccessChannel in WebSocket readPump.
- **Commit SHA**: ``current``
- **Verification**: Verified in `chat-service/internal/handlers/chat.go`. ✅

## Cryptographically Signed JWTs

- **Implementation Detail**: Replaced raw user ID tokens with signed HS256 JWT tokens containing user ID, role, tenant ID, and email. Added POST /auth/refresh to reissue tokens. Downstream services validate JWT signatures and expiry locally.
- **Commit SHA**: ``current``
- **Verification**: Verified in `auth-service`, `chat-service`, `notification-service`, `user-service`. ✅

## auth-service XFF Trust Boundary Hardening

- **Implementation Detail**: auth-service rate limiter only trusts XFF headers if verified by the dynamic GATEWAY_SECRET header injected by the API Gateway.
- **Commit SHA**: ``current``
- **Verification**: Verified in `auth-service` getClientIP. ✅

## Signup-time Anti-spam OTP

- **Implementation Detail**: Gated signup with OTP confirmation. Accounts are created as unconfirmed (is_confirmed = false) and login is rejected until the signup OTP is verified.
- **Commit SHA**: ``current``
- **Verification**: Verified in `auth-service` Signup, Login, and VerifyOTP. ✅

## JWT Secret Hardening

- **Implementation Detail**: Removed hardcoded JWT secret fallback in all 4 services. Services now require JWT_SECRET env var on startup and fail-fast if it's missing.
- **Commit SHA**: ``current``
- **Verification**: Verified via startup crash test. ✅

## Gateway Secret Hardening

- **Implementation Detail**: Removed hardcoded X-Gateway-Secret. Both api-gateway and auth-service now require the GATEWAY_SECRET env var on startup and fail-fast if it's missing.
- **Commit SHA**: ``current``
- **Verification**: Verified via startup crash test. ✅

## Job Endpoint Access Control

- **Implementation Detail**: Secured GET /users/jobs/get?id= by strictly restricting access to matching owners/employees (validated via JWT) or trusted internal clients via X-Internal-Token header. Closed resolveToken() unverified bypass.
- **Commit SHA**: ``current``
- **Verification**: Verified via user-service integration test and cURL validation. ✅

## Employee Toggle Authentication

- **Implementation Detail**: Fixed POST /auth/employee/toggle security gap by requiring the owner's password and verifying it with bcrypt before freezing or activating employees.
- **Commit SHA**: ``current``
- **Verification**: Verified via auth-service compilation. ✅

## Audit Log Access Control

- **Implementation Detail**: Secured GET /auth/audit-log by strictly requiring requester_id query param and restricting access to matching tenant owner (validated via JWT). Closed unverified bypass.
- **Commit SHA**: ``current``
- **Verification**: Verified via auth-service unit test and cURL validation. ✅

## GetUser Endpoint Access Control

- **Implementation Detail**: Secured GET /auth/user by requiring `X-Internal-Token` for internal service-to-service calls (chat/notification/user-service) and valid signed JWT for external callers. Removed raw-ID passthrough. Updated all 4 internal callers to inject `X-Internal-Token` header. Added `INTERNAL_SERVICE_TOKEN` fail-fast to notification-service.
- **Commit SHA**: ``current``
- **Verification**: Verified via compilation and existing test suites (all pass). ✅

## Hardcoded Secrets Audit

- **Implementation Detail**: Audited entire codebase for hardcoded secrets. Removed JWT fallbacks, X-Gateway-Secret, and confirmed via repo-wide regex audit that no other secrets exist.
- **Commit SHA**: ``current``
- **Verification**: Verified via repo-wide regex audit. ✅

## Gateway Internal Token Stripping

- **Implementation Detail**: Edge api-gateway removes any client-supplied `X-Internal-Token` before proxying requests to backends.
- **Commit SHA**: ``current``
- **Verification**: Verified in api-gateway proxy.go. ✅

## CompleteJob Authorization Check

- **Implementation Detail**: Enforced user/employee role identity and internal X-Internal-Token verification on CompleteJob.
- **Commit SHA**: ``current``
- **Verification**: Verified via user-service unit tests. ✅

## Notification Auth Enforcement

- **Implementation Detail**: Enforced X-Internal-Token authentication on Send and BroadcastJobAlert endpoints in notification-service.
- **Commit SHA**: ``current``
- **Verification**: Verified via notification-service unit tests. ✅

## GetHistory Channel-Access Check

- **Implementation Detail**: Enforced requester_id (JWT token) and channel access (canAccessChannel) validation on GetHistory in chat-service.
- **Commit SHA**: ``current``
- **Verification**: Verified via chat-service unit tests. ✅

## Employee Toggle Lockout

- **Implementation Detail**: Enforced limiter lockout and failure recording on failed owner password check in ToggleEmployee.
- **Commit SHA**: ``current``
- **Verification**: Verified via compilation and logic flow analysis. ✅

## Token Refresh 7-Day Limit

- **Implementation Detail**: Gated token refresh to reject tokens that expired more than 7 days ago.
- **Commit SHA**: ``current``
- **Verification**: Verified via compilation and logic flow analysis. ✅

## ID and OTP Cryptographic Hardening

- **Implementation Detail**: Removed weak fallbacks from generateID and generate4DigitOTP, causing fail-fast logs on failure.
- **Commit SHA**: ``current``
- **Verification**: Verified via compilation. ✅

## WebSocket Origin Verification

- **Implementation Detail**: Restricted WebSocket connection origins to match configured ALLOWED_ORIGIN in chat-service.
- **Commit SHA**: ``current``
- **Verification**: Verified via compilation and test suites. ✅

## Membership Tier Enforcement

- **Implementation Detail**: Gated UpdateJobLocation location tracking endpoint behind PlanPaid check on Job Owner.
- **Commit SHA**: ``current``
- **Verification**: Verified via unit and integration tests. ✅

## CloudWatch Security Log Shipping

- **Implementation Detail**: Structured JSON log event to CloudWatch Logs for security-relevant blocked events in auth, user, and chat services.
- **Commit SHA**: ``current``
- **Verification**: Verified via unit, race, and log shipping tests. ✅

## mTLS Stage 1: Dev CA & Certs

- **Implementation Detail**: Created generate-certs.sh script generating Root CA and leaf certificates for local dev.
- **Commit SHA**: ``current``
- **Verification**: Verified via cert creation and gitignore validation. ✅

## mTLS Stage 2: TLS Server Config

- **Implementation Detail**: Configured auth, chat, notification, and user services to serve HTTPS with client cert verification (tls.RequireAndVerifyClientCert).
- **Commit SHA**: ``current``
- **Verification**: Verified via compilation and test execution. ✅

## mTLS Stage 3: TLS Client Config

- **Implementation Detail**: Updated internal HTTP clients in api-gateway, chat, notification, and user services to use custom TLS client configuration with hostname verification and local root CA trust.
- **Commit SHA**: ``current``
- **Verification**: Verified via compilation and test execution. ✅

## mTLS Stage 4: Docker & Env Wiring

- **Implementation Detail**: Configured docker-compose.yml to mount local certs and keys, updated service URLs to HTTPS, and updated env templates.
- **Commit SHA**: ``current``
- **Verification**: Verified via configuration review. ✅

## mTLS Stage 5: Verification

- **Implementation Detail**: Created and ran an integration test (mtls_integration_test.go) verifying handshake rejection of missing/untrusted client certs and success of trusted ones.
- **Commit SHA**: ``current``
- **Verification**: Verified via integration tests. ✅

## Redis Rate Limiting Stage 5: Failure Mode

- **Implementation Detail**: Implemented fail-closed behaviors for Redis runtime unavailability, with audit logging and rate restriction.
- **Commit SHA**: ``current``
- **Verification**: Verified via compilation and code review. ✅

## Prevent Duplicate Ratings

- **Implementation Detail**: Added compound unique index on ratings for (job_id, rated_by) and returned 409 Conflict when duplicate rating is submitted (identified during schema review).
- **Commit SHA**: ``current``
- **Verification**: Verified via integration tests. ✅

## Complaint Routing Stage 2: Atomic Agent Assignment

- **Implementation Detail**: Implemented atomic support agent assignment using MongoDB FindOneAndUpdate to prevent race conditions on concurrent ticket creation.
- **Commit SHA**: ``current``
- **Verification**: Verified via compilation. ✅

## External HTTPS Listener on api-gateway

- **Implementation Detail**: Migrated the gateway's external port to listen on HTTPS with separate EXTERNAL_TLS credentials, keeping public and internal mTLS domains distinct.
- **Commit SHA**: ``current``
- **Verification**: Verified via compilation and configuration. ✅

## SimulateEmployeeAction Authorization

- **Implementation Detail**: Enforced JWT authentication on simulate employee action endpoint, validating that the token matches the requested employee email.
- **Commit SHA**: ``current``
- **Verification**: Verified via unit test. ✅

## Mask plain text tokens in logs

- **Implementation Detail**: Replaced raw JWT / session tokens with authenticated IDs (userID / tenantID) in stdout logs to prevent credential leakage.
- **Commit SHA**: ``current``
- **Verification**: Verified via grep checks. ✅

## Gateway Info & Health Leak Fix

- **Implementation Detail**: Stripped routes/topology leakage from public / endpoint and reduced public /health endpoint to basic status, moving detailed metrics to authenticated /health/internal.
- **Commit SHA**: ``current``
- **Verification**: Verified via compilation and route checks. ✅

## Constant-time internal token compare

- **Implementation Detail**: Replaced standard string comparison operators with subtle.ConstantTimeCompare in all X-Internal-Token verification checks to mitigate timing attacks.
- **Commit SHA**: ``current``
- **Verification**: Verified via test execution. ✅

## Reviewer Identity Gap Fix

- **Implementation Detail**: Added reviewer token auth to pending, review, and view doc endpoints, populated ReviewerID on review, and logged reviewer ID in security logs.
- **Commit SHA**: ``current``
- **Verification**: Verified via auth-service integration tests. ✅

## Mask Plaintext OTP Codes in logs

- **Implementation Detail**: Restricted logging of plaintext OTP code values during signup and login 2FA in `services/auth-service/internal/handlers/auth.go#L229` and `services/auth-service/internal/handlers/auth.go#L371` to local environments only (`isLocal == true`).
- **Commit SHA**: ``current``
- **Verification**: Verified via auth-service integration/unit tests. ✅

## Gated Wallet Deposit Endpoint

- **Implementation Detail**: Gated the public `/users/wallet/deposit` endpoint behind a strict environment allow-list (`"local"` and `"test"` only). Refactored user-service configuration to read `APP_ENV` from config rather than inline, and added verification tests for both production and unset/empty environment configurations to ensure unverified deposits are securely blocked.
- **Commit SHA**: ``current``
- **Verification**: Verified via unit tests. ✅

## Owner-Authenticated Employee Provisioning

- **Implementation Detail**: Enforced owner authentication on the employee signup endpoint (`POST /auth/signup` when `role=employee`), requiring a valid JWT matching the requested `owner_id` with role `owner`. Added rate limiting and audit logging via `UNAUTHORIZED_EMPLOYEE_PROVISION_BLOCKED` security events. Documented in [ADR-0001](../adr/0001-owner-authenticated-employee-provisioning.md).
- **Commit SHA**: ``current``
- **Verification**: Verified via auth-service integration tests. ✅

## Per-Job Escrow Isolation, Zero-Value Fail-Closed & Concurrency Hardening

- **Implementation Detail**: Reverted unsafe GPS coordinates in price recalculations; persisted LockedEscrowAmount at booking; implemented atomic per-job escrow isolation in MongoDB with sequential dev fallbacks; capped payouts/refunds at the locked ceiling; added dynamic context-cancellation rollback and record deletion on TrackJob persistence failures; failed-closed with `escrow_amount_unrecorded` error if LockedEscrowAmount is zero; verified race-condition closure (CompleteJob vs CancelJob concurrency) through multi-goroutine tests. Documented in [ADR-0002](../adr/0002-per-job-escrow-integrity.md).
- **Commit SHA**: ``logic-exploitation``
- **Verification**: Verified via user-service integration and concurrency tests. ✅

## TrackJob Non-COD Payment APP_ENV Gate

- **Implementation Detail**: Restricts `TrackJob` to accept non-COD payment methods (such as `wallet` or bank cards) ONLY when `APP_ENV` is explicitly set to `"local"` or `"test"`. All other environments (including production and unset/empty configurations) continue to reject non-COD payments at the endpoint level to prevent un-auditable fund flows. This exception allows end-to-end integration and concurrency testing of the escrow paths.
- **Commit SHA**: ``logic-exploitation``
- **Verification**: Verified via user-service integration test suite (checking both rejection in production-like configs and bypass success in test config). ✅

## COD Completion Concurrency Hardening

- **Implementation Detail**: Hardened the Cash on Delivery (COD) job completion path to be atomic by updating the job document status from `active` to `completed` inside `DeductCODFee`'s transaction (using conditional `UpdateOne`). If the job status is already updated, subsequent concurrent completion attempts will fail to match the query and are rejected with a 409 Conflict. This prevents double platform fee deductions and duplicate ledger entries.
- **Commit SHA**: ``logic-exploitation``
- **Verification**: Verified via user-service concurrency tests. ✅



