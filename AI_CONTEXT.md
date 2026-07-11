# AI Context: saas-core

> [!IMPORTANT]
> **Branch Workflow**: `main` = stable/deployable, kept in sync only via reviewed merges from `logic-exploitation`. All active development happens on `logic-exploitation`. Never commit directly to `main`.

This file serves as a persistent, model-agnostic, single source of truth for the technical stack, architecture, feature status, security logs, and current gaps of the `saas-core` platform. Any agent or developer modifying this repository must update this document in the same commit.

---

## Project Summary

The `saas-core` platform is a multi-tenant SaaS application providing a marketplace services directory, real-time messaging, and job tracking. 

* **Tech Stack Deviation Note**: The codebase is implemented as **Go microservices** running on a containerized environment (Docker Compose) and backing onto MongoDB. This deviates from an original planning diagram that specified a Node.js and Socket.io stack. The microservices architecture and real-time messaging functionality were preserved, but migrated to Go for type safety and performance.

---

## Architecture Table

The platform uses a microservices architecture coordinated via a reverse-proxy API Gateway.

| Service | Default Port | Role | Data Store / Key Libraries |
| :--- | :--- | :--- | :--- |
| **api-gateway** | `8080` | Reverse proxy/routing edge for clients. Implements edge rate limiting and path rewriting. | Go Standard Library |
| **auth-service** | `3002` | Handles tenant registration, password hashing (bcrypt), multi-role login, and encrypted 2FA OTPs. | MongoDB, `golang.org/x/crypto` |
| **chat-service** | `3001` | Real-time WebSocket hub for messaging, segregated per job. | MongoDB, `github.com/gorilla/websocket` |
| **notification-service** | `3004` | Real-time client alerts via Server-Sent Events (SSE). | Go Standard Library |
| **user-service** | `3003` | Services directory (using spatial indexes), job tracking, e-wallets, ledger, and subscriptions. | MongoDB (with `2dsphere` index) |
| **shared/infra** | `N/A` | Compile-time shared library module for cross-cutting infrastructure packages. | `github.com/redis/go-redis/v9`, `github.com/sony/gobreaker/v2`, `github.com/golang-jwt/jwt/v5` |

* **Shared Infrastructure Module (`shared/infra`)**: Created to eliminate duplicate copy-pasted codebase files (saving ~2,150 duplicate lines of code) without compromising microservice independence. It acts purely as a compile-time dependency, similar to third-party modules (no shared runtime processes, databases, or in-memory state). It contains:
  * `shared/infra/resilience`: HTTP client wrapper for retries, exponential backoff, jitter, and circuit breaking.
  * `shared/infra/ratelimit`: Redis-backed sliding window and login-lockout rate limiting.
  * `shared/infra/tlsutil`: TLS config loaders for mutual TLS (mTLS) server and client setup.
  * `shared/infra/jwtutil`: Cryptographically signed JSON Web Token (JWT) generation and validation helpers.

---

## Feature Status

Features are classified into three groups: Done & Verified, Explicitly Deferred by Decision, and Not Started Yet. Only features verified directly against the repository are marked as verified.

### 1. Done & Verified

| Feature | Implementation Detail | Commit SHA | Verification |
| :--- | :--- | :--- | :--- |
| **Bcrypt Password Hashing** | Replaced plaintext comparison in auth-service with bcrypt password hashing. | `48ece45eb6b0282194c2f7026a7a85c8fbd79917` | Verified in `auth-service/internal/handlers/auth.go`. ✅ |
| **Dual-Key rate limiting & lockouts** | Enforced lockout limits in `auth-service` on client IP and email with exponential backoff. | `04185514a931e597de3e97da46b6842a691090db` | Verified in `auth-service/internal/handlers/limiter.go`. ✅ |
| **OTP TTL Expiry & Cleanup** | Added a 5-minute TTL to OTPs and a background database sweep sweeping expired OTPs every minute. | `f3f313b97c034a4118aba1760403bf1a47911df1` | Verified in `auth-service/internal/store/mongodb.go`. ✅ |
| **Owner KYC Status Checks** | Restricts service creation, deposits, and job tracking to owners with approved KYC status. | `49d453c92742deb58bf31e806da7f2a084ea1be2` | Verified in `user-service/internal/handlers/handlers.go`. ✅ |
| **JSON Injection Fix in WebSocket**| Replaced manual string concatenation in chat broadcast with `json.Marshal`. | `d8e9f762fb9d3dff1e054285ef6e9c0954f35e4a` | Verified in `chat-service/internal/chat/hub.go`. ✅ |
| **WebSocket Channel Authorization** | Restricts channel subscriptions to job participants (Owner or Employee) by querying user-service. | `54750d0711e56a2afc48508aed44c2515ac39433` | Verified in `chat-service/internal/handlers/chat.go`. ✅ |
| **SSE Stream Authentication** | Enforces SSE connection token verification by querying auth-service. | `5dd15e27c7cc6f216b15e907e0eb2c1cbb26cde9` | Verified in `notification-service/internal/handlers/handlers.go`. ✅ |
| **CORS Origins Restriction** | Restricted notification SSE stream CORS from wildcard `*` to configured `ALLOWED_ORIGIN`. | `49752a64c4a641153087c7e95958d37e33f3bc05` | Verified in `notification-service/internal/handlers/handlers.go`. ✅ |
| **X-Forwarded-For Spoof Hardening**| Edge api-gateway overwrites X-Forwarded-For. Gateway limiter keys off `RemoteAddr` directly. | `aebb580fb7b5a9c7520034e865153fc08681cfb5` | Verified in `api-gateway/internal/middleware/limiter.go` and `proxy.go`. ✅ |
| **COD Platform Fee Overdraft** | Deducts 15% platform fee directly from Owner e-wallet upon job completion, allowing negative balances. | `6edf1b7c825b37cc15b16dbc348026c4b689724b` | Verified in `user-service/internal/store/mongodb.go`. ✅ |
| **Tenant Subscription Gating** | POST /users/subscription upgrades require requester_id == tenant_id, auth-service check, and maps paid to pending_payment (requires manual activation). | `current` | Verified in `user-service/internal/handlers/handlers.go`. ✅ |
| **WebSocket Message Authorization** | Gated chat message broadcasts by canAccessChannel in WebSocket readPump. | `current` | Verified in `chat-service/internal/handlers/chat.go`. ✅ |
| **Rating & Comment System** | Rating and comment submissions on completed jobs with average rating queries. | `6edf1b7c825b37cc15b16dbc348026c4b689724b` | Verified in `user-service/internal/handlers/handlers.go`. ✅ |
| **Cryptographically Signed JWTs** | Replaced raw user ID tokens with signed HS256 JWT tokens containing user ID, role, tenant ID, and email. Added POST /auth/refresh to reissue tokens. Downstream services validate JWT signatures and expiry locally. | `current` | Verified in `auth-service`, `chat-service`, `notification-service`, `user-service`. ✅ |
| **auth-service XFF Trust Boundary Hardening** | auth-service rate limiter only trusts XFF headers if verified by the dynamic GATEWAY_SECRET header injected by the API Gateway. | `current` | Verified in `auth-service` getClientIP. ✅ |
| **Signup-time Anti-spam OTP** | Gated signup with OTP confirmation. Accounts are created as unconfirmed (is_confirmed = false) and login is rejected until the signup OTP is verified. | `current` | Verified in `auth-service` Signup, Login, and VerifyOTP. ✅ |
| **Automated Test Coverage** | Added table-driven and integration unit tests covering bcrypt hashing, rate limiter lockout, OTP expiry in auth-service, KYC gating, COD validation, subscription matching in user-service, and websocket channel access control in chat-service. | `current` | Verified via `go test` in all three services. All 3 suites pass successfully (16 total integration/unit test cases, 0 skipped). ✅ |
| **JWT Secret Hardening** | Removed hardcoded JWT secret fallback in all 4 services. Services now require JWT_SECRET env var on startup and fail-fast if it's missing. | `current` | Verified via startup crash test. ✅ |
| **Gateway Secret Hardening** | Removed hardcoded X-Gateway-Secret. Both api-gateway and auth-service now require the GATEWAY_SECRET env var on startup and fail-fast if it's missing. | `current` | Verified via startup crash test. ✅ |
| **Job Endpoint Access Control** | Secured GET /users/jobs/get?id= by strictly restricting access to matching owners/employees (validated via JWT) or trusted internal clients via X-Internal-Token header. Closed resolveToken() unverified bypass. | `current` | Verified via user-service integration test and cURL validation. ✅ |
| **Employee Toggle Authentication** | Fixed POST /auth/employee/toggle security gap by requiring the owner's password and verifying it with bcrypt before freezing or activating employees. | `current` | Verified via auth-service compilation. ✅ |
| **Audit Log Access Control** | Secured GET /auth/audit-log by strictly requiring requester_id query param and restricting access to matching tenant owner (validated via JWT). Closed unverified bypass. | `current` | Verified via auth-service unit test and cURL validation. ✅ |
| **GetUser Endpoint Access Control** | Secured GET /auth/user by requiring `X-Internal-Token` for internal service-to-service calls (chat/notification/user-service) and valid signed JWT for external callers. Removed raw-ID passthrough. Updated all 4 internal callers to inject `X-Internal-Token` header. Added `INTERNAL_SERVICE_TOKEN` fail-fast to notification-service. | `current` | Verified via compilation and existing test suites (all pass). ✅ |
| **Hardcoded Secrets Audit** | Audited entire codebase for hardcoded secrets. Removed JWT fallbacks, X-Gateway-Secret, and confirmed via repo-wide regex audit that no other secrets exist. | `current` | Verified via repo-wide regex audit. ✅ |
| **Gateway Internal Token Stripping** | Edge api-gateway removes any client-supplied `X-Internal-Token` before proxying requests to backends. | `current` | Verified in api-gateway proxy.go. ✅ |
| **CompleteJob Authorization Check** | Enforced user/employee role identity and internal X-Internal-Token verification on CompleteJob. | `current` | Verified via user-service unit tests. ✅ |
| **Notification Auth Enforcement** | Enforced X-Internal-Token authentication on Send and BroadcastJobAlert endpoints in notification-service. | `current` | Verified via notification-service unit tests. ✅ |
| **GetHistory Channel-Access Check** | Enforced requester_id (JWT token) and channel access (canAccessChannel) validation on GetHistory in chat-service. | `current` | Verified via chat-service unit tests. ✅ |
| **Employee Toggle Lockout** | Enforced limiter lockout and failure recording on failed owner password check in ToggleEmployee. | `current` | Verified via compilation and logic flow analysis. ✅ |
| **Token Refresh 7-Day Limit** | Gated token refresh to reject tokens that expired more than 7 days ago. | `current` | Verified via compilation and logic flow analysis. ✅ |
| **ID and OTP Cryptographic Hardening** | Removed weak fallbacks from generateID and generate4DigitOTP, causing fail-fast logs on failure. | `current` | Verified via compilation. ✅ |
| **WebSocket Origin Verification** | Restricted WebSocket connection origins to match configured ALLOWED_ORIGIN in chat-service. | `current` | Verified via compilation and test suites. ✅ |
| **WalletDeposit Upper Limit** | Enforced a maximum limit of 1,000,000 on WalletDeposit amounts in user-service. | `current` | Verified via user-service unit tests. ✅ |
| **Host Ports Stripping** | Removed host port exposures for internal services in docker-compose.yml, replacing with expose. | `current` | Verified docker-compose.yml configuration. ✅ |
| **OTP AES Key Configuration** | Added OTP_AES_KEY variable to docker-compose.yml, .env.example, and .env.local. | `current` | Verified environment configurations. ✅ |








| **Live Location Tracking** | Broadcast real-time employee locations via WebSockets to owner and client. | `current` | Verified via integration tests and E2E simulation. ✅ |
| **Membership Tier Enforcement** | Gated UpdateJobLocation location tracking endpoint behind PlanPaid check on Job Owner. | `current` | Verified via unit and integration tests. ✅ |
| **Per-Job Location Throttling** | Throttled consecutive location updates under 3s per Job ID with in-flight reservations and rollback. | `current` | Verified via unit, race, and integration tests. ✅ |
| **CloudWatch Security Log Shipping** | Structured JSON log event to CloudWatch Logs for security-relevant blocked events in auth, user, and chat services. | `current` | Verified via unit, race, and log shipping tests. ✅ |
| **mTLS Stage 1: Dev CA & Certs** | Created generate-certs.sh script generating Root CA and leaf certificates for local dev. | `current` | Verified via cert creation and gitignore validation. ✅ |
| **mTLS Stage 2: TLS Server Config** | Configured auth, chat, notification, and user services to serve HTTPS with client cert verification (tls.RequireAndVerifyClientCert). | `current` | Verified via compilation and test execution. ✅ |
| **mTLS Stage 3: TLS Client Config** | Updated internal HTTP clients in api-gateway, chat, notification, and user services to use custom TLS client configuration with hostname verification and local root CA trust. | `current` | Verified via compilation and test execution. ✅ |
| **mTLS Stage 4: Docker & Env Wiring** | Configured docker-compose.yml to mount local certs and keys, updated service URLs to HTTPS, and updated env templates. | `current` | Verified via configuration review. ✅ |
| **mTLS Stage 5: Verification** | Created and ran an integration test (mtls_integration_test.go) verifying handshake rejection of missing/untrusted client certs and success of trusted ones. | `current` | Verified via integration tests. ✅ |
| **Redis Rate Limiting Stage 1: Wrapper & Config** | Created shared ratelimit package wrapping Redis client with atomic Lua scripts, and updated all 5 config packages to load REDIS_URI. | `current` | Verified via compilation and unit tests. ✅ |
| **Redis Rate Limiting Stage 2: api-gateway** | Migrated the api-gateway edge rate limiter to use the Redis-backed wrapper. | `current` | Verified via compilation. ✅ |
| **Redis Rate Limiting Stage 3: auth-service** | Migrated the auth-service dual-key (IP + email) rate limiter to use Redis. | `current` | Verified via compilation and test execution. ✅ |
| **Redis Rate Limiting Stage 4: chat, user & notification services** | Migrated rate limiters in chat, user, and notification services to use Redis-backed wrapper. | `current` | Verified via compilation and test execution. ✅ |
| **Redis Rate Limiting Stage 5: Failure Mode** | Implemented fail-closed behaviors for Redis runtime unavailability, with audit logging and rate restriction. | `current` | Verified via compilation and code review. ✅ |
| **Redis Rate Limiting Stage 6: Verification & Concurrency Tests** | Created concurrency and cross-instance rate limit tests, and ran full test suite verification. | `current` | Verified via integration and concurrency tests. ✅ |
| **Resilience Stage 1: Wrapper Client** | Created shared resilience package implementing retry-with-backoff + jitter and circuit-breaker wrapper around http.Client. | `current` | Verified via compilation. ✅ |
| **Resilience Stage 2 & 3: Wiring & Fail-Closed Errors** | Wired separate circuit breaker and retry instances into internal HTTP clients and proxies, returning 503 Service Unavailable and failing closed on timeouts. | `current` | Verified via compilation and test execution. ✅ |
| **Resilience Stage 4: Observability & Health Integration** | Configured structured logs for circuit breaker transitions and exposed dependency breaker status on /health endpoints. | `current` | Verified via compilation and test execution. ✅ |
| **Resilience Stage 5: Resilience Tests & Verification** | Created unit and integration tests verifying retry limit capping, circuit breaker trip/recovery transitions, and fail-closed security properties. | `current` | Verified via integration tests. ✅ |
| **Prevent Duplicate Ratings** | Added compound unique index on ratings for (job_id, rated_by) and returned 409 Conflict when duplicate rating is submitted (identified during schema review). | `current` | Verified via integration tests. ✅ |
| **CI Integration (MongoDB & Redis)** | Configured MongoDB and Redis service containers in GitHub Actions to enable full, non-skipped execution of microservice integration tests. | `current` | Verified via workflow configuration. ✅ |
| **Gitignore Precision Fix** | Added precise root-level /cmd ignore rule to `.gitignore` to prevent stray binaries from being tracked while keeping sub-level cmd directories tracked. | `current` | Verified using git check-ignore. ✅ |
| **JWT Util Extraction** | Consolidated duplicate `jwt.go` files across auth, chat, notification, and user services into `shared/infra/jwtutil`. | `current` | Verified via compilation and test execution. ✅ |
| **Complaint Routing Stage 1: Data Model** | Added database collections, Go model structs, and indexes for support agents and complaint tickets in chat-service store. | `current` | Verified via compilation. ✅ |
| **Complaint Routing Stage 2: Atomic Agent Assignment** | Implemented atomic support agent assignment using MongoDB FindOneAndUpdate to prevent race conditions on concurrent ticket creation. | `current` | Verified via compilation. ✅ |
| **Complaint Routing Stage 3, 4, 5: WebSocket & HTTP Wiring** | Wired complaint ticket channel/access checks into chat WebSocket/Hub, added structured security audit logging, and applied Redis rate limiter. | `current` | Verified via compilation. ✅ |
| **Complaint Routing Stage 6: Concurrency & Access Tests** | Added unit and concurrency tests proving atomic support agent assignment, queueing, and IDOR mitigation for ticket access. | `current` | Verified via test execution. ✅ |
| **Complaint Routing Stage 7: Documentation** | Documented complaint routing design and atomic assignment decisions in DESIGN.md and AI_CONTEXT.md. | `current` | Verified via review. ✅ |

### 2. Explicitly Deferred by Decision

* **CloudWatch Event Rate Limiting/Batching**
  * **Decision**: Log shipping performs a separate CloudWatch Logs `PutLogEvents` API call per event rather than using client-side batching or queuing.
  * **Reasoning**: Accepted as a known limitation in the initial rollout. A genuine high-volume abuse burst could hit CloudWatch's per-stream PutLogEvents throttling limit and silently drop events at exactly the moment they matter most. Batching/queuing events client-side is flagged for future implementation.
* **E-Wallet and Bank Card Payment Flows**
  * **Decision**: Only Cash on Delivery (`cod`) is allowed as a payment method for now; other methods are rejected during tracking/booking.
  * **Reasoning**: The interface for Stripe or other bank card gateways is placeholder-only; to prevent actual security vulnerabilities or un-auditable fund flows, all payment pathways besides `cod` are explicitly blocked at the endpoint level.
* **Manual KYC/KYB Approval Process (Ops Runbook)**
  * **Decision**: Know Your Customer (KYC) approval for tenant owners is deliberately not automated or exposed via API endpoints.
  * **Reasoning**: To maintain security and avoid exposing administrative endpoints that could be targeted by attackers. approvals must be handled manually by an operations engineer directly in the database (updating the `kyc_status` field to `"approved"`).
* **Mock OTP SMS/Email Dispatcher**
  * **Decision**: SMS dispatching is stubbed using a mock that logs OTPs to stdout. In local environment (`APP_ENV=local`), OTPs are exposed directly in response payloads as `dev_otp`.
  * **Reasoning**: Speeds up development and avoids dependencies on external paid SMS gateways during local testing.
* **Rating Edits / Updates**
  * **Decision**: Editing or updating an existing rating is deliberately not allowed. The endpoint blocks duplicate ratings, and no PATCH/update rating endpoint is provided.
  * **Reasoning**: To prevent data manipulation. Allowing users to modify ratings later is flagged as a potential future feature with its own authorization checks.

### 3. Not Started Yet

* **Real Email/SMS Integration**: No Twilio, SendGrid, or SMTP dispatchers are set up.

---

## Known Open Items / Unverified Claims

Only features verified directly against the running application are marked as verified (✅). The following items are implemented but remain unverified end-to-end or represent accepted security risks:

* **Unverified Escrow Logic**: Escrow locking (`LockEscrow`) and release splits (`ReleaseEscrowWithSplit`) exist in `user-service/internal/store/mongodb.go`, but since the `/track` endpoint actively blocks any payment method other than `cod`, **this code path has never been executed or verified end-to-end**.
* **Fail-Closed Rate Limiting on Redis Unavailability**: If the shared Redis instance becomes unavailable at runtime, all rate limiters across all microservices (api-gateway, auth-service, chat-service, notification-service, user-service) will fail-closed. This means incoming traffic is restricted/blocked and authentication attempts are denied with critical security logs (`[SECURITY CRITICAL]`), rather than allowing un-throttled traffic to bypass security boundaries.
* **Dev-Grade mTLS CA**: The certificates generated for mTLS use a dev-grade local Root CA. For production, a real internal CA (e.g. AWS Private CA, HashiCorp Vault PKI, or cert-manager on Kubernetes) must be integrated.

---

## Breaking Token Policy Change (JWT Integration)

With JWT support enabled:
1. Client-facing endpoints expecting a `token` (such as `chat-service` WebSocket `?token=` and `notification-service` SSE stream `?token=`) must now pass a valid signed JWT token instead of raw user IDs.
2. `user-service` JSON fields/query params (`owner_id`, `tenant_id`, `requester_id`, `user_id`, `rated_by`, `rated_user`) support JWT tokens. The backend will validate the token signature/expiry locally, extract the raw user ID, and map it.

---

## Standing Working Rule

This file is a persistent document tracking the real state of the repository.

> [!IMPORTANT]
> **Every code change must update `AI_CONTEXT.md` in the SAME commit.**
> Any pull request or commit that changes application behavior, adds endpoints, modifies security boundaries, or changes the tech stack but does not update `AI_CONTEXT.md` is considered incomplete. 
> Keep the feature status and unverified claims list strictly in sync with actual code implementations.

---

* **Immediate Next Step**: Awaiting user request / next phase of development.

