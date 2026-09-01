# Quick Delivery — Complete Application Map

> [!NOTE]
> **Reflects Repository State**: This document maps the application architecture, APIs, inter-service connections, and actor flows as of Git commit: **`91f60fa`**.
> Since the codebase is subject to ongoing development, this map should be regenerated and re-verified via `git rev-parse --short HEAD` after significant routing or security changes.

---

## Connection Diagram

The following diagram visualizes the trust boundary and inter-service connections across the application. External client traffic enters solely through the API Gateway, which acts as the SSL-termination edge and proxies to internal services via mTLS.

```mermaid
flowchart TD
    subgraph External Client Boundary [Internet / External Network]
        ClientApp["Browser / Mobile Client"]
    end

    subgraph Internal Network [Secure Private Network - mTLS Required]
        Gateway["api-gateway (Port: 8080)"]
        AuthService["auth-service (Port: 3002)"]
        ChatService["chat-service (Port: 3001)"]
        NotifService["notification-service (Port: 3004)"]
        UserService["user-service (Port: 3003)"]
        ReviewerApp["kyc-reviewer-console (Port: 8090 - ADR-0021)"]
        SharedInfra["shared/infra (Compile-Time Only)"]
    end

    %% External Connections
    ClientApp -- "External HTTPS (TLS)" --> Gateway

    %% Proxy Routes
    Gateway -- "Forwarded HTTPS (mTLS)" --> AuthService
    Gateway -- "Forwarded HTTPS (mTLS)" --> UserService
    Gateway -- "Forwarded HTTPS / WS (mTLS)" --> ChatService
    Gateway -- "Forwarded HTTPS / SSE (mTLS)" --> NotifService

    %% Inter-service HTTP Calls
    ChatService -- "GET /auth/user (mTLS)" --> AuthService
    ChatService -- "GET /users/jobs/get (mTLS)" --> UserService
    NotifService -- "GET /auth/user (mTLS)" --> AuthService
    UserService -- "GET /auth/user (mTLS)" --> AuthService
    UserService -- "POST /chat/internal/broadcast-location (mTLS)" --> ChatService
    UserService -- "POST /notifications/send & broadcast (mTLS)" --> NotifService
    AuthService -- "POST /notifications/send (mTLS)" --> NotifService
    ReviewerApp -- "Forwarded mTLS / KYC Reviews" --> AuthService

    %% Styling and Legend
    style ClientApp fill:#f9f,stroke:#333,stroke-width:2px
    style Gateway fill:#bbf,stroke:#333,stroke-width:2px
    style SharedInfra fill:#eee,stroke:#999,stroke-dasharray: 5 5

    classDef default fill:#fff,stroke:#333,stroke-width:1px;
```

---

## Section 1: Service Inventory

The platform is comprised of **5 microservices** and **1 compile-time shared package**. Below is the detailed inventory of each component, its database ownership, port mappings, and HTTP routing policies.

### 1. `api-gateway` (Port: `8080`)
* **Core Responsibility**: The public-facing reverse proxy and routing edge for all client-facing traffic. Terminates SSL/TLS on the internet boundary, enforces edge rate limiting via Redis, enforces minimum client version gating (`VersionGate` middleware), rewrites request paths, and strips unsafe incoming headers.
* **Database & Collections**: MongoDB (`platform_versions` for ADR-0018 client version gating configuration; in-memory fallback in local/test mode). Maintains edge rate limit buckets inside Redis.
* **Security & TLS Policy**: 
  * Inbound: Serves public traffic over HTTPS (`http.ListenAndServeTLS` using `EXTERNAL_TLS_CERT_PATH` and `EXTERNAL_TLS_KEY_PATH`).
  * Outbound: Calls downstream services using mTLS (`tlsutil.LoadClientTLSConfig`).
* **Header Handling**: 
  * Strips/deletes incoming `X-Internal-Token` headers from callers.
  * Overwrites `X-Forwarded-For` with the client’s remote address.
  * Injects `X-Gateway-Secret` to authenticate gateway-proxied requests.
* **Outbound HTTP Calls**:
  * `auth-service`: Matches prefix `/api/v1/auth/` and forwards to `http://auth-service:3002`.
  * `user-service`: Matches prefix `/api/v1/users/` and forwards to `http://user-service:3003`.
  * `chat-service`: Matches prefix `/api/v1/chat/` and forwards to `http://chat-service:3001`.
  * `notification-service`: Matches prefix `/api/v1/notifications/stream` and forwards to `http://notification-service:3004`.

### 2. `auth-service` (Port: `3002`)
* **Core Responsibility**: Manages user profiles, credentials, 2FA OTP codes, employee activations, session verification, and audit logs.
* **Database & Collections**: MongoDB (`auth_db`):
  * `users`: Stores emails, role types, hashed passwords (bcrypt), KYC states, and OTP secrets.
  * `audit_logs`: Records simulated employee actions and administrative tasks.
* **Security & TLS Policy**: Internal mTLS-only server.
* **Inbound HTTP calls**:
  * `api-gateway` (public routes).
  * `chat-service` (calls `/auth/user` to authenticate WebSockets).
  * `notification-service` (calls `/auth/user` to authenticate SSE streams).
  * `user-service` (calls `/auth/user` to verify KYC status).
* **Outbound HTTP calls**: `notification-service` (invokes `/notifications/send` internally to dispatch KYC/KYB/KYE review outcome notifications per ADR-0021).

### 3. `chat-service` (Port: `3001`)
* **Core Responsibility**: Real-time communication server. Hosts WebSockets for active chat channels (segregated per job/ticket), manages location broadcasts, and coordinates support agent ticket assignments.
* **Database & Collections**: MongoDB (`chat_db`):
  * `chat_messages`: Stores message history for channels.
  * `complaint_tickets`: Stores complaint ticket states and assigned agents.
  * `support_agents`: Stores onboarded support agents and active session tokens.
* **Security & TLS Policy**: Serves mTLS HTTPS API routes and upgrades client WebSocket connections.
* **Inbound HTTP calls**:
  * `api-gateway` (public routes).
  * `user-service` (calls `/chat/internal/broadcast-location`).
* **Outbound HTTP calls**:
  * `auth-service`: Queries `/auth/user?id=<user_id>` to authenticate WebSocket connections.
  * `user-service`: Queries `GET /users/jobs/get?id=<job_id>` to resolve job owner, employee, and customer relationships for channel access control.

### 4. `notification-service` (Port: `3004`)
* **Core Responsibility**: Real-time client alerts and durable in-app notifications hub. Streams real-time popups and tenant-wide job alerts to connected web/mobile clients via Server-Sent Events (SSE), persists durable MongoDB-backed notification history with 30-day TTL retention, maintains per-recipient read and dismiss tracking across single-recipient and role-broadcast notifications (isolated per recipient rather than a single shared flag), and exposes 5 authenticated REST endpoints for history, read marking, and deletion (`GET /notifications/history`, `POST /notifications/{id}/read`, `POST /notifications/read-all`, `DELETE /notifications/{id}`, `DELETE /notifications`).
* **Database & Collections**: MongoDB (`notification_db`):
  * `notifications`: Stores persisted notification documents with compound indexes on `(tenant_id, user_id, timestamp desc)` and `(tenant_id, roles, timestamp desc)`, a 30-day TTL expiration index on `created_at` (`expireAfterSeconds = 2592000`), and per-recipient tracking arrays (`read_by`, `dismissed_by`). SSE connections are held in-memory within the active Hub.
* **Security & TLS Policy**: Serves mTLS HTTPS API routes and maintains SSE streams.
* **Inbound HTTP calls**:
  * `api-gateway` (public `/notifications/stream` routes and REST endpoints).
  * `user-service` (invokes `/notifications/broadcast/job-alert` internally).
  * `auth-service` (invokes `/notifications/send` internally for KYC/KYB/KYE review outcome notifications per ADR-0021).
* **Outbound HTTP calls**:
  * `auth-service`: Queries `/auth/user?id=<user_id>` to verify connecting SSE client tokens.

### 5. `user-service` (Port: `3003`)
* **Core Responsibility**: Manages the marketplace services directory (with spatial queries), active job lifecycles, wallets, ledgers, subscriptions, and provider ratings.
* **Database & Collections**: MongoDB (`user_db`):
  * `services`: Stores list of provider service listings with `2dsphere` coordinates.
  * `jobs`: Stores active jobs, statuses, tracking coordinates, and transaction references.
  * `wallets`: Stores tenant e-wallet balances (`total_balance`, `withdrawable_balance`).
  * `ledger`: Stores accounting journal entries for auditability.
  * `subscriptions`: Stores tenant subscription statuses and plans.
* **Internal Handler Architecture (`internal/handlers/`)**:
  * `handlers.go`: Service receiver struct (`UserService`), constructor (`NewUserService`), route registration (`RegisterRoutes`), and cross-domain shared utility helpers (`resolveClaims`, `resolveTokenWithRole`, `writeJSON`, `generateID`, `haversineKm`, `checkKYC`, `verifyEmployeeAssignment`, `requireTier`).
  * `services_handlers.go`: Service catalogue management and platform configuration (`ListServices`, `CreateService`, `UpdateService`, `GetPlatformConfig`).
  * `jobs_handlers.go`: Core job lifecycle, cascade dispatch, offer acceptance/decline, escrow locking/settlement, live location updates, and price negotiation (`TrackJob`, `AcceptJobOffer`, `DeclineJobOffer`, `HeartbeatLocation`, `CompleteJob`, `GetJob`, `GetOwnerJobs`, `GetCustomerJobs`, `UpdateJobLocation`, `CancelJob`, `ProposePrice`, `RespondPrice`).
  * `wallet_handlers.go`: Tenant balance, ledger audit trails, deposit bypass, and payout requests (`GetWallet`, `WalletDeposit`, `GetLedger`, `RequestPayout`, `GetPayoutRequests`).
  * `subscription_handlers.go`: Tenant subscription tier status and upgrade requests (`Subscription`).
  * `ratings_handlers.go`: Blind rating submissions and aggregated score lookups (`RateJob`, `GetRatings`).
  * `reconciliation_handlers.go`: Disputed escrow reconciliation queue and resolution (`GetReconciliationQueue`, `ResolveReconciliation`).
* **Security & TLS Policy**: Internal mTLS-only server.
* **Inbound HTTP calls**:
  * `api-gateway` (public routes).
  * `chat-service` (queries `/users/jobs/get?id=<job_id>`).
* **Outbound HTTP calls**:
  * `auth-service`: Queries `/auth/user?id=<owner_id>` to verify owner KYC status.
  * `chat-service`: Queries `POST /chat/internal/broadcast-location` to publish live driver coordinates.
  * `notification-service`: Dispatches real-time courier acceptance and cascade exhaustion alerts via `POST /notifications/send`, and broadcasts tenant job notifications via `POST /notifications/broadcast/job-alert`.

### 6. `shared/infra` (Compile-time dependency)
* **Core Responsibility**: Consolidates common code dependencies (saving duplicate lines in monorepo).
* **Libraries**:
  * `jwtutil`: Validates/generates signed JWT credentials.
  * `ratelimit`: Redis-backed sliding-window rate limiters.
  * `resilience`: Circuit breakers (`gobreaker`) and retries.
  * `tlsutil`: Configures internal mTLS handshakes.
  * `handlerutil`: Ships structured logs and security events.

---

## Section 2: Complete Endpoint Table

All HTTP endpoints registered across the services are listed below, cross-referenced with their actual routing definitions.

> [!NOTE]
> **Request Parameter Naming Compatibility**: To address naming clarity issues where request fields expected signed JWT tokens rather than raw database IDs, the Go backend supports newer `_token` aliases alongside legacy parameter names (preferring `_token` if both are present).
> 
> | Legacy Field Name | New Preferred Alias | Affected Endpoints |
> |---|---|---|
> | `user_id` / `id` | `user_token` | GET /auth/user, GET /auth/user/public-profile, POST /users/jobs/track, GET /users/ratings |
> | `owner_id` | `owner_token` | POST /users/services, POST /users/jobs/track |
> | `employee_id` | `employee_token` | POST /users/jobs/track, GET /users/jobs/get |
> | `requester_id` | `requester_token` | GET /auth/audit-log, GET /auth/user/public-profile, GET /users/jobs/get, POST /users/jobs/complete, POST /users/jobs/cancel, POST /users/subscription, POST /users/jobs/location/update |
> | `tenant_id` | `tenant_token` | GET /users/wallet, POST /users/wallet/deposit, GET /users/ledger, GET /users/subscription, POST /users/subscription |
> | `rated_by` / `rated_user` | `rated_by_token` / `rated_user_token` | POST /users/jobs/rate |

<!-- GENERATED:ENDPOINTS:START -->
| Method + Path | Owning Service | Caller Permissions | Core Functionality | Read / Write Target & Downstream Actions |
| :--- | :--- | :--- | :--- | :--- |
| **`GET /`** | `api-gateway` | Public | Root index. | None. |
| **`GET /api/v1/admin/version-config`** | `api-gateway` | `X-Internal-Token` | Fetches current mobile client minimum and latest version enforcement configuration. | Reads `platform_versions` collection. |
| **`PUT /api/v1/admin/version-config`** | `api-gateway` | `X-Internal-Token` | Updates mobile client minimum and latest version enforcement configuration. | Updates `platform_versions` collection. |
| **`GET /health`** | `api-gateway` | Public | Public gateway health status. | None. |
| **`GET /health/internal`** | `api-gateway` | `X-Internal-Token` | Returns circuit breaker metrics. | Reads breaker memory. |
| **`GET /auth/accounts`** | `auth-service` | Reviewer Token & `X-Internal-Token` | Searches and lists registered accounts with pagination, role and status filters (ADR-0022). | Reads `users` collection. |
| **`POST /auth/accounts/reactivate`** | `auth-service` | Reviewer Token & `X-Internal-Token` | Reactivates a suspended user account with optional reason and dispatches notification (ADR-0022). | Updates `users` collection. Writes `audit_log`. |
| **`POST /auth/accounts/suspend`** | `auth-service` | Reviewer Token & `X-Internal-Token` | Suspends a user account with mandatory reason, revoking active JWT sessions and dispatching notification (ADR-0022). | Updates `users` collection. Writes `audit_log`. Invalidates Redis JWT tokens. |
| **`POST /auth/accounts/{id}/reactivate`** | `auth-service` | Reviewer Token & `X-Internal-Token` | Reactivates a suspended user account with optional reason and dispatches notification (ADR-0022). | Updates `users` collection. Writes `audit_log`. |
| **`POST /auth/accounts/{id}/suspend`** | `auth-service` | Reviewer Token & `X-Internal-Token` | Suspends a user account with mandatory reason, revoking active JWT sessions and dispatching notification (ADR-0022). | Updates `users` collection. Writes `audit_log`. Invalidates Redis JWT tokens. |
| **`GET /auth/audit-log`** | `auth-service` | Tenant Owner JWT | Fetches tenant security audit logs. Accepts requester_id (legacy) or requester_token (preferred). | Reads `audit_logs` collection. |
| **`DELETE /auth/device-token`** | `auth-service` | Authenticated User JWT | Unregisters client push notification device token. | Updates `users` collection (`device_tokens`). |
| **`GET /auth/documents/view`** | `auth-service` | Reviewer Token & `X-Internal-Token` | Validates signed URL token and streams/serves the uploaded document file. | Streams file content. |
| **`POST /auth/email-change/confirm`** | `auth-service` | Authenticated User JWT | Verifies OTP and commits updated email address to user profile, issuing fresh JWT. | Updates `users` collection, clears pending change, issues new JWT. |
| **`POST /auth/email-change/request`** | `auth-service` | Authenticated User JWT | Initiates email change request, validates format and availability, and dispatches OTP to new email. | Writes `pending_email_changes` in `users` collection, dispatches OTP. |
| **`POST /auth/employee/action`** | `auth-service` | Target Employee JWT | Records a simulated worker activity. | Writes `audit_logs` collection. |
| **`POST /auth/employee/toggle`** | `auth-service` | Owner JWT (KYC Approved) | Activates/deactivates employee account. | Reads `users` (owner/employee), updates `users`. |
| **`GET /auth/employees`** | `auth-service` | Owner JWT | GetEmployees returns all employees registered under the caller's tenant owner account. | Reads `users` collection by `tenant_id`. Returns JSON array of `EmployeeResponse` (`ID`, `Username`, `Email`, `IsActive`, `CreatedAt`). Rate-limited per owner ID. |
| **`POST /auth/forgot-password`** | `auth-service` | Public | Dispatches password reset OTP code if account exists. | Reads `users` collection by email, updates `otp_code` and `otp_expires_at` fields. |
| **`GET /auth/kyb-kye/pending`** | `auth-service` | Reviewer Token & `X-Internal-Token` | Fetches pending KYB verification submissions (including username). | Reads `users` and `reviewers` collections. |
| **`POST /auth/kyb-kye/review`** | `auth-service` | Reviewer Token & `X-Internal-Token` | Approves or rejects KYB submissions. | Updates `users` status. Writes `audit_logs` and `reviewers`. |
| **`POST /auth/kyb/upload`** | `auth-service` | Owner JWT | Uploads KYB verification files (ID front/back, selfie, business proof). | Writes uploaded documents to local storage. Updates `users` collection. |
| **`POST /auth/kye/upload`** | `auth-service` | Employee JWT | Uploads KYE verification files (ID front/back, selfie). | Writes uploaded documents to local storage. Updates `users` collection. |
| **`POST /auth/login`** | `auth-service` | Public (via Gateway) | Logs in user, dispatches 2FA OTP. | Reads/writes `users` collection (OTP/attempts). Writes `audit_logs`. |
| **`POST /auth/logout`** | `auth-service` | Bearer JWT | Logs out user, revokes JWT session. | Writes token JTI to Redis denylist. |
| **`POST /auth/refresh`** | `auth-service` | Public (via Gateway) | Refreshes active JWT sessions. | None. |
| **`POST /auth/resend-otp`** | `auth-service` | Public | ResendOTP handles resending a fresh OTP for unconfirmed accounts. | Reads `users` collection by email, updates `otp_code` and `otp_expires_at` fields. |
| **`POST /auth/reset-password`** | `auth-service` | Public | Verifies OTP code and updates user password. | Reads `users` collection by email, updates `password` hash and clears OTP fields. |
| **`GET /auth/reviewer/verify`** | `auth-service` | Reviewer Token & `X-Internal-Token` | Verifies reviewer credentials and returns reviewer identity for inter-service ops authentication (ADR-0023). | Reads `reviewers` collection. |
| **`POST /auth/signup`** | `auth-service` | Public (via Gateway) | Registers a new tenant or user. | Writes `users` collection. Logs OTP code. |
| **`GET /auth/user`** | `auth-service` | `X-Internal-Token` OR User JWT | Resolves user profile (including username) and role details. Accepts id (legacy) or user_token (preferred). | Reads `users` collection. |
| **`PATCH /auth/user`** | `auth-service` | Authenticated User JWT | Self-service profile update (username, phone, frequent_addresses) with IDOR protection. | Updates `users` collection. |
| **`GET /auth/user/public-profile`** | `auth-service` | User JWT | Returns only non-sensitive, public profile fields (ID and username). Accepts id (legacy) or user_token (preferred), and requester_id (legacy) or requester_token (preferred). | Reads `users` collection. |
| **`POST /auth/verify-otp`** | `auth-service` | Public (via Gateway) | Validates 2FA OTP, issues JWT. | Reads/writes `users` collection. Writes `audit_logs`. |
| **`GET /admin/tickets`** | `chat-service` | Reviewer Token & `X-Internal-Token` | Lists all support tickets globally for ops console oversight (ADR-0023). | Reads `complaint_tickets` collection. Paginated. |
| **`POST /admin/tickets/resolve`** | `chat-service` | Reviewer Token & `X-Internal-Token` | Resolves support ticket globally with mandatory resolution note (ADR-0023). | CAS updates `complaint_tickets` and releases assigned agent. |
| **`GET /chat/admin/tickets`** | `chat-service` | Reviewer Token & `X-Internal-Token` | Lists all support tickets globally for ops console oversight (ADR-0023). | Reads `complaint_tickets` collection. Paginated. |
| **`POST /chat/admin/tickets/resolve`** | `chat-service` | Reviewer Token & `X-Internal-Token` | Resolves support ticket globally with mandatory resolution note (ADR-0023). | CAS updates `complaint_tickets` and releases assigned agent. |
| **`GET /chat/history`** | `chat-service` | Channel Member JWT | Retrieves channel chat history (containing sender_username point-in-time snapshot). | Reads `chat_messages` collection. Downstream: calls `user-service/users/jobs/get`. |
| **`POST /chat/internal/broadcast-location`** | `chat-service` | `X-Internal-Token` | Broadcasts driver location event. | None. |
| **`POST /chat/tickets`** | `chat-service` | User JWT | Submits complaint ticket & assigns agent. | Reads/writes `complaint_tickets` and `support_agents` (atomic). |
| **`POST /chat/tickets/resolve`** | `chat-service` | Support Agent Token | Resolves ticket & releases agent status. | Updates `complaint_tickets` and `support_agents`. |
| **`GET /chat/ws`** | `chat-service` | User JWT OR Agent Token | WebSocket connection upgrade path. | Reads `support_agents` (for agent tokens). Downstream: calls `auth-service/auth/user`. |
| **`DELETE /notifications`** | `notification-service` | User JWT | Clears all notifications for the authenticated user. | Deletes from `notifications` collection. |
| **`POST /notifications/broadcast/job-alert`** | `notification-service` | `X-Internal-Token` | Broadcasts job alert to employees. | Dispatches message to SSE clients. |
| **`GET /notifications/history`** | `notification-service` | User JWT | Returns the authenticated user's persisted notifications, paginated. | Reads `notifications` collection. |
| **`POST /notifications/read-all`** | `notification-service` | User JWT | Marks all notifications as read for the authenticated user. | Updates `notifications` collection. |
| **`POST /notifications/send`** | `notification-service` | `X-Internal-Token` | Sends a targeted popup alert. | Dispatches message to SSE client. |
| **`GET /notifications/stream`** | `notification-service` | User JWT | Opens SSE channel for alerts. | Downstream: calls `auth-service/auth/user`. |
| **`DELETE /notifications/{id}`** | `notification-service` | User JWT | Deletes a single notification for the authenticated user. | Deletes from `notifications` collection. |
| **`POST /notifications/{id}/read`** | `notification-service` | User JWT | Marks a single notification as read for the authenticated user. | Updates `notifications` collection. |
| **`GET /admin/reconciliation/queue`** | `user-service` | Reviewer Token & `X-Internal-Token` | Lists all jobs in escrow_reconciliation_required status globally across all tenants for ops console oversight (ADR-0023). | Reads `jobs` collection. Paginated. |
| **`POST /admin/reconciliation/resolve`** | `user-service` | Reviewer Token & `X-Internal-Token` | Resolves disputed job in escrow_reconciliation_required status globally via ops reviewer override with mandatory reason (ADR-0023). | CAS status transition on `jobs`, financial settlement/refund, ships security audit event and dispatches notifications. |
| **`GET /admin/subscriptions`** | `user-service` | Reviewer Token & `X-Internal-Token` | Lists subscriptions globally with optional status/search filters and pagination for ops console oversight (ADR-0023). | Reads `subscriptions` collection. Paginated. |
| **`POST /admin/subscriptions/activate`** | `user-service` | Reviewer Token & `X-Internal-Token` | Activates tenant subscription to PlanPaid with configurable duration (ADR-0023). | CAS status transition on `subscriptions` collection, ships security audit event. |
| **`GET /admin/subscriptions/queue`** | `user-service` | Reviewer Token & `X-Internal-Token` | Lists subscriptions globally with optional status/search filters and pagination for ops console oversight (ADR-0023). | Reads `subscriptions` collection. Paginated. |
| **`POST /admin/subscriptions/revoke`** | `user-service` | Reviewer Token & `X-Internal-Token` | Revokes tenant subscription to PlanCancelled with mandatory reason (ADR-0023). | CAS status transition on `subscriptions` collection, ships security audit event. |
| **`GET /users/admin/reconciliation/queue`** | `user-service` | Reviewer Token & `X-Internal-Token` | Lists all jobs in escrow_reconciliation_required status globally across all tenants for ops console oversight (ADR-0023). | Reads `jobs` collection. Paginated. |
| **`POST /users/admin/reconciliation/resolve`** | `user-service` | Reviewer Token & `X-Internal-Token` | Resolves disputed job in escrow_reconciliation_required status globally via ops reviewer override with mandatory reason (ADR-0023). | CAS status transition on `jobs`, financial settlement/refund, ships security audit event and dispatches notifications. |
| **`GET /users/admin/subscriptions`** | `user-service` | Reviewer Token & `X-Internal-Token` | Lists subscriptions globally with optional status/search filters and pagination for ops console oversight (ADR-0023). | Reads `subscriptions` collection. Paginated. |
| **`POST /users/admin/subscriptions/activate`** | `user-service` | Reviewer Token & `X-Internal-Token` | Activates tenant subscription to PlanPaid with configurable duration (ADR-0023). | CAS status transition on `subscriptions` collection, ships security audit event. |
| **`POST /users/admin/subscriptions/revoke`** | `user-service` | Reviewer Token & `X-Internal-Token` | Revokes tenant subscription to PlanCancelled with mandatory reason (ADR-0023). | CAS status transition on `subscriptions` collection, ships security audit event. |
| **`POST /users/employee/jobs/accept`** | `user-service` | Employee JWT | Accepts an active dispatch offer, calculates final distance pricing from courier location, and activates job. | Updates `jobs` collection, updates `wallets` (for escrow locking), dispatches notification. |
| **`POST /users/employee/jobs/decline`** | `user-service` | Employee JWT | Declines an active dispatch offer and advances the cascade immediately to the next courier. | Updates `jobs` collection, queries `employee_locations`, dispatches next offer notification. |
| **`POST /users/employee/jobs/{id}/accept`** | `user-service` | Employee JWT | Accepts an active dispatch offer, calculates final distance pricing from courier location, and activates job. | Updates `jobs` collection, updates `wallets` (for escrow locking), dispatches notification. |
| **`POST /users/employee/jobs/{id}/decline`** | `user-service` | Employee JWT | Declines an active dispatch offer and advances the cascade immediately to the next courier. | Updates `jobs` collection, queries `employee_locations`, dispatches next offer notification. |
| **`POST /users/employee/location`** | `user-service` | Public | <!-- TODO: verify manually --> | <!-- TODO: verify manually --> |
| **`POST /users/jobs/cancel`** | `user-service` | Owner or Customer JWT | Cancels an active job and processes escrow refunds. Accepts requester_id (legacy) or requester_token (preferred). | Updates `jobs` collection. Updates `wallets` and `ledger` collections. |
| **`POST /users/jobs/complete`** | `user-service` | Owner or Employee JWT | Completes active job, processes fees. Accepts requester_id (legacy) or requester_token (preferred) in body or query. | Updates `jobs`, writes `wallets`, writes `ledger`. |
| **`GET /users/jobs/get`** | `user-service` | `X-Internal-Token` OR Owner, Employee, User, or Customer JWT | Resolves detailed job configuration (single job by ID) or lists jobs. Accepts id (legacy) or user_token (preferred), requester_id (legacy) or requester_token (preferred), and employee_id (legacy) or employee_token (preferred). | Reads `jobs` collection. Enforces IDOR protection: if `employee_id` query param is provided, it must match the employee identity strictly resolved from the JWT token. |
| **`POST /users/jobs/location/update`** | `user-service` | Employee or Owner JWT | Updates driver coordinates. Accepts requester_id (legacy) or requester_token (preferred). | Reads `jobs`, updates `jobs`. Downstream: calls `chat-service/chat/internal/broadcast-location`. |
| **`GET /users/jobs/mine`** | `user-service` | Customer JWT | Lists all jobs booked by the authenticated customer (DTO: CustomerJobResponse). Supports optional user_id parameter matching for IDOR validation. | Reads `jobs` collection. Rate-limited per customer identity (30 req/min). |
| **`GET /users/jobs/owner`** | `user-service` | Owner JWT | Lists all jobs owned by the authenticated tenant owner (DTO: OwnerJobResponse). Supports optional owner_id parameter matching for IDOR validation. | Reads `jobs` collection. Rate-limited per owner identity (30 req/min). |
| **`POST /users/jobs/propose-price`** | `user-service` | Customer or Employee JWT | ProposePrice proposes a custom price for a negotiable transport job. | Reads services and jobs, updates proposed_price, proposed_by, proposal_expires_at, and job status. |
| **`POST /users/jobs/rate`** | `user-service` | Owner, Employee, User, or Customer JWT | Submits a double-blind rating. Accepts rated_by (legacy) or rated_by_token (preferred), and rated_user (legacy) or rated_user_token (preferred). | Writes `ratings`, updates `jobs`. |
| **`GET /users/jobs/reconciliation-queue`** | `user-service` | Owner JWT | Lists all jobs in escrow_reconciliation_required status for the authenticated tenant owner. | Reads `jobs` collection. Scoped to authenticated owner ID with IDOR validation and rate-limiting (30 req/min). |
| **`POST /users/jobs/reconciliation-resolve`** | `user-service` | Owner JWT | Resolves job in escrow_reconciliation_required status ('release_to_employee' or 'refund_to_customer'). | Updates `jobs` status and reconciliation fields, writes `wallets` and `ledger`, ships security audit event. |
| **`POST /users/jobs/respond-price`** | `user-service` | Customer or Employee JWT | RespondPrice accepts or declines a price proposal for a transport job. | Updates jobs agreed_price, status (active or cancelled), and cancellation_reason. |
| **`POST /users/jobs/track`** | `user-service` | Owner/Employee JWT (legacy tracking) OR Customer JWT + service_id (owner resolved server-side; supports optional employee pre-assignment) | Books job with coordinate validation. Accepts user_id (legacy) or user_token (preferred), owner_id (legacy) or owner_token (preferred), and employee_id (legacy) or employee_token (preferred). | Downstream: calls `auth-service/auth/user`. Writes `jobs`. |
| **`GET /users/ledger`** | `user-service` | Owner JWT | Lists financial ledger records. Accepts tenant_id (legacy) or tenant_token (preferred). | Reads `ledger` collection. |
| **`GET /users/platform/config`** | `user-service` | Public | Fetches global fees configuration. | Reads `platform_config` collection. |
| **`GET /users/ratings`** | `user-service` | Owner, Employee, User, or Customer JWT | Returns ratings count and average. Accepts user_id (legacy) or user_token (preferred). | Reads `ratings` collection. |
| **`GET /users/services`** | `user-service` | Public | Spatial search on services directory. | Reads `services` collection. |
| **`PATCH /users/services`** | `user-service` | Owner JWT (KYC Approved) | Updates an existing service listing (photo, address, working hours, coverage radius, prices, category). | Downstream: calls `auth-service/auth/user`. Updates `services` collection. |
| **`POST /users/services`** | `user-service` | Owner JWT (KYC Approved) | Inserts service listing. | Downstream: calls `auth-service/auth/user`. Writes `services` collection. |
| **`PUT /users/services`** | `user-service` | Owner JWT (KYC Approved) | Updates an existing service listing (photo, address, working hours, coverage radius, prices, category). | Downstream: calls `auth-service/auth/user`. Updates `services` collection. |
| **`PATCH /users/services/update`** | `user-service` | Owner JWT (KYC Approved) | Updates an existing service listing (photo, address, working hours, coverage radius, prices, category). | Downstream: calls `auth-service/auth/user`. Updates `services` collection. |
| **`POST /users/services/update`** | `user-service` | Owner JWT (KYC Approved) | Updates an existing service listing (photo, address, working hours, coverage radius, prices, category). | Downstream: calls `auth-service/auth/user`. Updates `services` collection. |
| **`PUT /users/services/update`** | `user-service` | Owner JWT (KYC Approved) | Updates an existing service listing (photo, address, working hours, coverage radius, prices, category). | Downstream: calls `auth-service/auth/user`. Updates `services` collection. |
| **`POST /users/subscription`** | `user-service` | Owner JWT (KYC Approved) | Subscribes/renews SaaS tier. Accepts tenant_id (legacy) or tenant_token (preferred), and requester_id (legacy) or requester_token (preferred). | Updates `subscriptions`, writes `wallets`, writes `ledger`. |
| **`GET /users/wallet`** | `user-service` | Owner JWT | Fetches active balance details. Accepts tenant_id (legacy) or tenant_token (preferred). | Reads `wallets` collection. |
| **`POST /users/wallet/deposit`** | `user-service` | Owner JWT | Loads funds up to maximum limits. Accepts tenant_id (legacy) or tenant_token (preferred). | Updates `wallets` collection. |
| **`POST /users/wallet/payout/request`** | `user-service` | Owner JWT | Processes a tenant owner withdrawal request for electronic wallet balance. | Reads `wallets` collection, writes `payout_requests` collection. |
| **`GET /users/wallet/payout/requests`** | `user-service` | Owner JWT | Retrieves historical payout requests for authenticated tenant owner. | Reads `payout_requests` collection. |
<!-- GENERATED:ENDPOINTS:END -->

### Standalone Operations (CLI Tool)
* **`onboard-agent` CLI** (`services/chat-service/cmd/onboard-agent/main.go`):
  * **Caller Permissions**: Standard Linux CLI execution with MongoDB credentials. Not exposed as an HTTP endpoint.
  * **Core Functionality**: Safe onboarding of support agents. Validates uniqueness, generates secure 32-byte hex credentials, and writes the record to the `support_agents` database.
  * **Read/Write**: Writes `support_agents` collection.
* **`onboard-reviewer` CLI** (`services/auth-service/cmd/onboard-reviewer/main.go`):
  * **Caller Permissions**: Standard Linux CLI execution with MongoDB credentials. Not exposed as an HTTP endpoint.
  * **Core Functionality**: Safe onboarding of super-admin KYB/KYE document reviewers. Validates uniqueness, generates secure 32-byte hex credentials, and writes the record to the `reviewers` database.
  * **Read/Write**: Writes `reviewers` collection.

---

## Section 3: Actor-Centric Flows

Below are the step-by-step transaction lifecycles for each user role on the platform, illustrating the sequence of backend requests.

### 1. Tenant Owner Flow (Setup & Directory Listing)
1. **Signup**: Caller triggers `POST /auth/signup` with role `"owner"`.
   * *Status*: Account created but flag `is_confirmed = false`.
   * *2FA SMS / Email Dispatch*: Mocked in code. It logs the OTP to stdout and exposes it as `dev_otp` in the JSON response in local environments.
2. **OTP Verification**: Caller triggers `POST /auth/verify-otp` with the OTP code.
   * *Status*: Account is verified (`is_confirmed = true`), returning a signed JWT token.
3. **KYC Approval**: Owner KYC status default is `"pending_super_admin_approval"`. 
   * *Verification*: Since no administrative endpoint exists, KYC status must be approved manually by an operations engineer in the database (`db.users.updateOne({_id: "..."}, {$set: {kyc_status: "approved"}})`).
4. **Create Service Listing**: Owner triggers `POST /users/services` with their JWT token.
   * *Validation*: `user-service` calls `auth-service/auth/user` internally to check if the owner's KYC status is `"approved"`. Writes listing to `services`.
5. **Purchase Subscription**: Owner triggers `POST /users/subscription` with JWT to register for a SaaS plan.
   * *Validation*: Checks wallet has sufficient funds, deducts subscription cost, and writes record to `subscriptions` and `ledger` collections.

### 2. Job Lifecycle Flow (Owner & Employee & Customer)
1. **Job Booking**: Tenant Owner (legacy tracking) OR Customer (marketplace booking) calls `POST /users/jobs/track` with JWT.
   * *Owner Resolution*: If booked by a customer without an owner token, the backend securely loads the service record from the database by its `service_id` and resolves the owner ID server-side (`svc.TenantID`) to prevent owner-ID spoofing. If an owner token is explicitly provided (owner/employee-initiated tracking), the backend validates the token and cross-checks that the owner matches the service's tenant, rejecting mismatches with a `403 Forbidden` error.
   * *Employee Pre-Assignment*: If an `employee_id` is supplied to pre-assign an employee, the backend validates that the employee is active, holds the employee role, and belongs to the resolved owner's tenant. Distance pricing is calculated, escrow is locked, and status is set to `"active"`.
   * *Cascade Initialization*: When booked without a pre-assigned employee, the job is initialized with status `"pending_dispatch"`. Distance computation, fare pricing, and escrow locking are deferred until courier acceptance. The backend ranks fresh available tenant couriers by Haversine proximity and offers the job to the nearest courier (`current_offered_employee_id`, `offer_expires_at = now + 60s`).
   * *Validation*: Checks that the resolved Owner KYC status is `"approved"`.
   * *Constraint*: The endpoint rejects any payment method other than `"cod"` (Cash on Delivery) in non-local environments.
   * *Alerting*: It broadcasts a job alert to tenant employees via `POST /notifications/broadcast/job-alert`.
2. **Sequential Accept/Decline Cascade & Deferred Pricing**:
   * *Offer Window*: The offered courier has a 60-second countdown to accept (`POST /users/employee/jobs/{id}/accept`) or decline (`POST /users/employee/jobs/{id}/decline`).
   * *Cascade Progression*: If the courier declines or the 60-second timer expires, the cascade automatically advances the offer to the next-nearest available courier.
   * *Exhaustion Fallback*: If all couriers decline or none are available, the job transitions to `"unavailable"`. The customer is notified asynchronously via `POST /notifications/send` and sees a busy state with a "Retry Booking" CTA on their status screen.
   * *Acceptance-Before-Pricing*: When a courier accepts, the backend verifies they are not already busy (rejecting with 409 `courier_busy` if on an active job) and their GPS location is fresh (rejecting with 409 `location_stale` if >5m). Final distance pricing is calculated using the accepting courier's actual coordinates, escrow is locked in the wallet, and the job transitions to `"active"` (or `"awaiting_price_response"` for negotiable transport services). An asynchronous notification (`POST /notifications/send`) is sent to the customer with the confirmed fare.
   * *Pre-Dispatch Cancellation*: Customers can cancel during `"pending_dispatch"` without escrow penalty, immediately clearing the offer and halting the cascade.
3. **Location Updates (Driver tracking)**: While driving, the Employee client triggers `POST /users/jobs/location/update` with their Employee JWT.
   * *Validation*: `user-service` verifies the Owner's subscription tier is active and enforces a **2-second throttling minimum** between requests.
   * *Action*: Coordinates are saved to MongoDB and broadcasted via `POST /chat/internal/broadcast-location` (mTLS) to the `chat-service` WebSocket hub.
4. **Job Completion**: The Owner or Employee triggers `POST /users/jobs/complete` confirming cash collection.
   * *Zero Commission (ADR-0017)*: Platform fee is 0% (zero-commission subscription-only revenue model). Settles escrow/COD and records journal entries to `ledger` and `wallets`.
5. **Rating**: Customer triggers `POST /users/jobs/rate`. Checks that job status is `"completed"` and limits users to **one rating per job** (enforced by a compound unique index in MongoDB).

### 3. Customer Service Flow (User & Support Agent)
1. **Ticket Creation**: User triggers `POST /chat/tickets` with JWT.
   * *Atomic Assignment*: The `chat-service` performs an atomic transaction (`FindOneAndUpdate`) looking for an available agent (status `"available"`). If found, it marks the agent as `"busy"` and assigns their ID to the ticket. If no agent is available, the ticket queues as `"pending"`.
2. **WebSocket Communication**: Both the User and the Support Agent connect to `chat-service/chat/ws`.
   * *Agent Auth*: Agent authenticates using the secure token printed during the CLI onboarding.
   * *Access Gating*: Users can only access channel `"ticket:<ticket_id>"` if they own the ticket or are the assigned agent.
3. **Resolution**: The assigned agent triggers `POST /chat/tickets/resolve`.
   * *Validation*: An IDOR check verifies that the caller's agent ID matches the ticket's assigned agent ID.
   * *Action*: Marks ticket as `"resolved"`, sets agent status back to `"available"`.

---

## Section 4: Data Flow for Sensitive Operations

Detailed execution paths for transactions requiring absolute auditing integrity:

### 1. Wallet & COD Fee Handling
```
[Owner/Employee Client] 
         │
         ▼
POST /users/jobs/complete  ──► (Validates JWT, Checks payment_method == "cod")
          │
          ▼
[user-service] ──────────────► (Status-only logging, 0% platform fee per ADR-0017)
          │
          ▼
[user-service Store] ────────► CompleteCODJob()
          │
          └──► Logs cash collection event without wallet balance mutation
```

### 2. KYC / KYB Gating
```
[Client Request]
         │ (e.g. POST /users/services)
         ▼
   [user-service]
         │
         ▼ (GET /auth/user?id=<owner_id> with X-Internal-Token)
   [auth-service]
         │
         ▼ (Reads 'users' collection in MongoDB)
   [auth-service] ───────────► Returns KYCStatus ("approved" | "pending_super_admin_approval")
         │
         ▼
   [user-service]
         │
         ├──► If KYCStatus == "approved" ──────────────────► Allow execution (write to MongoDB)
         └──► If KYCStatus == "pending_super_admin_approval" ► Block with 403 Forbidden
```

### 3. Double-Blind Rating System
```
[Client Request] (POST /users/jobs/rate)
         │
         ▼
   [user-service] ───────────► (Validates JWT tokens for RatedBy and RatedUser)
         │
         ▼
   [user-service] ───────────► (Checks Job collection: JobStatus == "completed")
         │
         ▼
   [user-service] ───────────► (Enforces Rating Authorization: RatedBy and RatedUser 
         │                      must map to Job's OwnerID and EmployeeID)
         ▼
   [user-service Store] ─────► CreateRating()
         │
         ▼ (Writes to MongoDB 'ratings' collection)
   [MongoDB Index] ──────────► Compound unique index {job_id: 1, rated_by: 1}
         │
         ├──► Success ───────► Return 201 Created
         └──► Duplicate ─────► Catch WriteError 11000, abort & return 409 Conflict
```
