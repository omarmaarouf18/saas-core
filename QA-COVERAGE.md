# QA Strategy & Regression Coverage Matrix

## 1. Executive Summary

This document serves as the persistent single source of truth for end-to-end quality assurance, release gates, and regression protection across the Quick Delivery SaaS platform. It documents verified system invariants, end-to-end Critical User Journeys (CUJs) executed against live staging infrastructure, and the gap analysis informing subsequent QA phases.

---

## 2. Currently Protected Workflows (Phase 0 Baseline)

The following journeys are actively executed and protected by the automated CI Release Gate (`.github/workflows/release-gate-e2e.yml`) and local staging test suite (`tests/e2e`):

### CUJ-A: Cascade Dispatch, Offer Isolation, Pricing Lock & Live GPS Tracking
* **Test Implementation**: `tests/e2e/cuj_a_test.go` (`TestCUJ_A_CascadeOfferAcceptAndLiveTracking`)
* **Infrastructure Path**: Client -> Caddy (`:8088`) -> API Gateway (`:8080`) -> `user-service` / `chat-service` / `notification-service` -> MongoDB & Redis.
* **Verified Invariants**:
  1. **Cascade Dispatch Initial State**: Customer booking creates a job in `pending_dispatch` and directs an offer strictly to the nearest available courier based on spatial distance.
  2. **Price Deferral**: Job distance (`booked_distance`) and escrow (`locked_escrow_amount`) remain zero/deferred until courier acceptance.
  3. **Notification Isolation (N-01 & N-02)**:
     - **N-01**: Only the offered courier receives the real-time `job_offer` event over live SSE. Un-offered couriers receive 0 events.
     - **N-02**: The un-offered courier's historical notifications query (`GET /api/v1/notifications`) contains zero leaked job details.
  4. **Pricing Lock on Acceptance**: When the courier accepts the offer, distance is calculated from the courier's actual coordinates and the escrow amount is atomically locked from the tenant's wallet.
  5. **Navigation Resilience (F-01)**: Courier app navigation (querying profile, jobs list, and notifications) does not disrupt active job tracking or state.
  6. **WebSocket Live Map Updates**: Full-duplex WebSocket stream through Caddy and API Gateway delivers live coordinate updates to customer subscribers within the 3-second throttle interval.

### CUJ-B: KYC Reviewer Console, Mandatory Reason & Live Proxy SSE Delivery
* **Test Implementation**: `tests/e2e/cuj_b_test.go` (`TestCUJ_B_KYCSubmissionReviewAndSSEOutcomeDelivery`)
* **Infrastructure Path**: Client / Reviewer -> Caddy (`:8088` & `:8091`) -> API Gateway & KYC Reviewer Console -> `auth-service` & `notification-service`.
* **Verified Invariants**:
  1. **Console Queue Discovery**: Pending KYC verification submissions appear immediately in the Reviewer Console queue (`GET /api/queue`).
  2. **Mandatory Rejection Reason Enforcement ([ADR-0021](docs/adr/ADR-0021-reviewer-rejection-reason.md))**:
     - Submitting a rejection without a reason is rejected with `400 Bad Request`.
     - Submitting a whitespace-only rejection reason (`"   "`) is rejected with `400 Bad Request`.
     - Submitting a valid reason returns `200 OK` and persists the rejection reason.
  3. **Real SSE Delivery via Edge Proxy**:
     - Customer connects to real SSE stream through Caddy and API Gateway.
     - Rejection and approval events (`kyc_rejected`, `kyc_approved`) are flushed immediately across Caddy and API Gateway without reverse-proxy buffering delay or dropped events.
  4. **WebSocket Protocol Upgrade Integrity**: Gateway resilience transport preserves `io.ReadWriteCloser` for `101 Switching Protocols`, preventing bad handshake errors.

---

## 3. Critical Business Tests & Critical User Journeys (Phase 2)

The following journeys are actively executed against the live containerized staging stack (`tests/e2e`):

### CUJ-C: Customer Registration, Password Validation, Duplicate Defense & 2FA Flow
* **Test Implementation**: `tests/e2e/cuj_c_test.go` (`TestCUJ_C_CustomerRegistration`)
* **Infrastructure Path**: Client -> Caddy (`:8088`) -> API Gateway (`:8080`) -> `auth-service` (`:3002`) -> MongoDB (`auth_db`).
* **Verified Invariants**:
  1. **Input Validations**:
     - Weak passwords (< 6 characters) are strictly rejected with `400 Bad Request` (addresses a real seam defect discovered during Phase 2).
     - Malformed email formats are rejected with `400 Bad Request`.
  2. **OTP Generation & Verification**:
     - Customer registration emits an OTP code (`201 Created`).
     - Submitting an invalid or expired OTP code fails with `401 Unauthorized`.
     - Submitting the valid OTP confirms the account, sets status to `active`, and assigns default role `user`.
  3. **Duplicate Prevention**:
     - Re-registering with an already existing, confirmed email address is blocked with `409 Conflict`.
  4. **Two-Factor Authentication (2FA) & Session State**:
     - Valid login credentials trigger a 2FA challenge and issue an OTP.
     - OTP verification returns a valid JWT Bearer session token.
     - Authenticated request through API Gateway to `GET /api/v1/auth/user` resolves the full authenticated customer profile.

### CUJ-D: Driver Workflow Full Cycle, IDOR Defense & Escrow Settlement
* **Test Implementation**: `tests/e2e/cuj_d_test.go` (`TestCUJ_D_DriverWorkflowFullCycle`)
* **Infrastructure Path**: Customer/Courier -> Caddy (`:8088`) -> API Gateway (`:8080`) -> `user-service` (`:3003`) -> MongoDB (`users_db`).
* **Verified Invariants**:
  1. **Booking & Assignment**: Customer books a service via `POST /api/v1/users/jobs/track`; Courier A accepts the job via `POST /api/v1/users/employee/jobs/{id}/accept`.
  2. **Location Updates**: Courier updates delivery GPS coordinates via `POST /api/v1/users/jobs/location/update` (nested location struct `{"latitude": ..., "longitude": ...}` enforcing reasonable speed checks).
  3. **Cross-Courier IDOR Guards**:
     - Unauthorized Courier B attempting to complete Courier A's active job is blocked with `403 Forbidden`.
     - Unauthorized Courier B attempting to query Courier A's job details (`GET /api/v1/users/jobs/get?id=...&employee_id=...`) is blocked with `403 Forbidden`.
  4. **Job Completion & Financial Escrow Release**:
     - Courier A marks the delivery completed via `POST /api/v1/users/jobs/complete`.
     - Locked escrow balance is atomically released to `0.00` and credited to tenant wallet as withdrawable funds.

### CUJ-E: Owner Workflow, Paid-Tier Gating, Service Management & IDOR Defense
* **Test Implementation**: `tests/e2e/cuj_e_test.go` (`TestCUJ_E_OwnerWorkflow`)
* **Infrastructure Path**: Tenant Owner -> Caddy (`:8088`) -> API Gateway (`:8080`) -> `user-service` (`:3003`) -> MongoDB (`users_db`).
* **Verified Invariants**:
  1. **Dashboard Aggregation**: Owner accesses aggregated dashboard telemetry (`GET /api/v1/users/wallet`, `GET /api/v1/users/ledger`, `GET /api/v1/users/jobs/owner`, `GET /api/v1/auth/employees`) returning 200 OK.
  2. **Paid-Tier Subscription Gating**:
     - Free-tier owner attempting `POST /api/v1/users/services` is rejected with `402 Payment Required` (`upgrade_required`).
     - Subscribed Paid-tier owner successfully creates (`201 Created`) and updates (`200 OK`) service listings.
  3. **Dispute & Reconciliation Access**: Paid-tier owner accesses tenant dispute reconciliation queue (`GET /api/v1/users/jobs/reconciliation-queue`).
  4. **Cross-Tenant IDOR Guards**:
     - Tenant B attempting to mutate Tenant A's service listing is rejected (`402` gating / `403 Forbidden`).
     - Tenant B attempting to read Tenant A's reconciliation queue is strictly rejected with `403 Forbidden`.

### CUJ-F: Active Job Real-Time Chat, WebSocket Ordering & Cross-Tenant IDOR Isolation
* **Test Implementation**: `tests/e2e/cuj_f_test.go` (`TestCUJ_F_Chat`)
* **Infrastructure Path**: Customer/Courier -> Caddy (`:8088`) -> API Gateway (`:8080`) -> `chat-service` (`:3001`) -> MongoDB (`chat_db`) & Redis.
* **Verified Invariants**:
  1. **Subscription Authorization**: Customer and assigned Courier A connect via WebSocket upgrade (`GET /api/v1/chat/ws`) and subscribe to channel `job:<job_id>`.
  2. **Real-Time Live Delivery**: Message dispatched by Customer arrives at Courier A's open WebSocket connection in real time.
  3. **Persistence & Historical Reconnect**: Message history query (`GET /api/v1/chat/history?channel=job:<id>`) verifies durable MongoDB persistence and message ordering.
  4. **Cross-Tenant IDOR Isolation**:
     - Unassigned Courier B querying `GET /api/v1/chat/history` for Customer A's job is denied with `403 Forbidden`.
     - Unassigned Courier B attempting WebSocket subscription to `job:<job_id>` receives an immediate authorization error (`not authorized for this channel`).

### CUJ-G: Double-Blind Rating, Validations & Aggregate Metrics
* **Test Implementation**: `tests/e2e/cuj_g_test.go` (`TestCUJ_G_Rating`)
* **Infrastructure Path**: Customer/Owner -> Caddy (`:8088`) -> API Gateway (`:8080`) -> `user-service` (`:3003`) -> MongoDB (`users_db`).
* **Verified Invariants**:
  1. **Completion Prerequisite**: Submitting a rating for an uncompleted job is rejected with `400 Bad Request` (`cannot rate a job that is not completed`).
  2. **Star Bounds Validation**: Star ratings outside the [1, 5] range (e.g. 0 stars or 6 stars) are rejected with `400 Bad Request` (`stars must be between 1 and 5`).
  3. **Participant Authorization**: A user not party to the job attempting to submit a rating is blocked with `403 Forbidden`.
  4. **Duplicate Submission Protection**: Submitting a second rating for the same job by the same participant is blocked with `409 Conflict`.
  5. **Aggregate Metrics Verification**: `GET /api/v1/users/ratings` correctly reflects the updated rating count and average score.

### CUJ-H: Support Ticket Resolution & Dual-Delivery Regression Guard
* **Test Implementation**: `tests/e2e/cuj_h_test.go` (`TestCUJ_H_SupportTicketResolution`)
* **Infrastructure Path**: Customer/Reviewer -> Caddy (`:8088` & `:8091`) -> API Gateway & Ops Console -> `chat-service` (`:3001`) & `notification-service` (`:3004`).
* **Verified Invariants**:
  1. **Ticket Creation**: Customer creates a complaint ticket (`POST /api/v1/chat/tickets`) returning `201 Created` with state `pending`.
  2. **Channel Subscription**: Customer connects to SSE stream (`GET /api/v1/notifications/stream`) and subscribes to WebSocket ticket channel (`ticket:<ticket_id>`).
  3. **Mandatory Resolution Note**: Reviewer resolving ticket via Ops Console without a resolution note is rejected with `400 Bad Request`.
  4. **Reviewer Authorization**: Non-reviewer callers attempting resolution are rejected with `401 Unauthorized`.
  5. **Dual-Delivery Regression Guard**:
     - **Delivery 1 (SSE)**: Customer receives real-time `ticket_resolved` notification via Server-Sent Events with resolution summary.
     - **Delivery 2 (WebSocket)**: Customer receives a structured system message (`sender_id: system:support`, `type: ticket_resolution`) inside the live `ticket:<ticket_id>` channel.

---

## 4. Auth & RBAC Security Matrix (Phase 2b)

* **Test Implementation**: `tests/e2e/auth_matrix_test.go` (`TestAuthMatrix` / `TestAuthAndRBACMatrix`)
* **Coverage Scope**:
  - **Role Matrix**: Evaluates Anonymous (unauthenticated), Customer (`user`), Driver (`employee`), Owner (`tenant`), and Reviewer (`reviewer`) roles against representative endpoints.
  - **Representative Endpoints Tested**:
    - Customer-scoped: `POST /api/v1/chat/tickets`
    - Driver-scoped: `POST /api/v1/users/employee/location`
    - Owner-scoped: `POST /api/v1/users/services`
    - Reviewer-scoped: `GET /api/queue` (Ops Console `:8091`)
  - **Cross-Tenant IDOR Invariants Verified**:
    - *Service Mutation IDOR*: Tenant B cannot mutate Tenant A's service (`402`/`403 Forbidden`).
    - *Reconciliation Queue IDOR*: Tenant B cannot read Tenant A's reconciliation queue (`403 Forbidden`).
    - *Job Completion IDOR*: Courier B cannot complete Courier A's active job (`403 Forbidden`).
    - *Chat History IDOR*: Courier B cannot inspect Customer A's job chat history (`403 Forbidden`).

---

## 5. Backend-Frontend Parity Guard Tooling (Phase 2c)

* **Tool Implementation**: `tools/paritycheck/main.go`
* **Execution**: `make backend-frontend-parity-check`
* **CI Integration**: Wired into `.github/workflows/ci.yml` as an informational non-blocking gate.
* **Extraction Scope**:
  - Extracts 82 registered backend routes from Go AST via `docgen.GenerateEndpointsList`.
  - Extracts API call sites across all Dart files in `frontend/lib`.
  - Extracts API proxy call sites across Ops Console (`kyc-reviewer-console/internal/proxy/proxy.go`).
* **Inventory Classification Results**:
  - **Total Registered Backend Routes**: 82
  - **Mobile App Routes (Flutter)**: 53
  - **Ops Console Routes (Reviewer Console)**: 19
  - **Internal Service-to-Service Routes**: 6 (`/api/v1/admin/version-config`, `/chat/internal/broadcast-location`, `/notifications/send`, `/notifications/broadcast/job-alert`, `/users/subscription/internal`, `/auth/reviewer/verify`)
  - **Infra / Health Probes**: 3 (`/health`, `/health/internal`, `/`)
  - **Unconsumed / Orphan Routes**: 1 (`POST /chat/tickets/resolve` per GAP-03 / ADR-0013: legacy support agent token endpoint superseded by Ops Console `/admin/tickets/resolve`)

---

## 6. Real Seam Bugs Discovered & Resolved During Staging Verification

Executing end-to-end tests across real microservices, Caddy edge proxy, and live datastores surfaced two genuine defects in the integration seams:

1. **`api-gateway` Route Prefix Mismatch**:
   - *Defect*: Gateway configuration mapped `{"/api/v1/notifications/stream", notifServiceURL}` instead of prefix `{"/api/v1/notifications/", notifServiceURL}`.
   - *Impact*: In-app notification management endpoints (`GET /api/v1/notifications/history`, `POST /api/v1/notifications/read-all`, `POST /api/v1/notifications/{id}/read`, `DELETE /api/v1/notifications/{id}`) returned `404 Not Found` from the gateway.
   - *Fix*: In `services/api-gateway/internal/config/config.go`, updated prefix route to `{"/api/v1/notifications/", notifServiceURL}`.
2. **`auth-service` Missing Password Length Validation**:
   - *Defect*: `Signup` handler lacked password minimum length validation.
   - *Impact*: Weak passwords (< 6 characters) successfully registered accounts, deferring failure or causing inconsistent authentication behavior.
   - *Fix*: In `services/auth-service/internal/handlers/auth.go`, added validation `len(req.Password) < 6` returning `400 Bad Request` with `{"error":"password must be at least 6 characters"}`.

---

## 7. Remaining QA Roadmap (Phase 1 & Phase 3)

| Domain | Current State | Target Phase | Risk Level |
| :--- | :--- | :--- | :--- |
| **Contract Testing** | Integration tests rely on live DBs | Phase 1 (Pact / Consumer-driven contract tests) | Medium |
| **FCM Push Notifications** | Mock dispatcher in staging | Phase 3 (Real device token dispatch and background wakeups) | Medium |
| **Chaos & Node Failure** | Zero chaos testing | Phase 3 (Automated kill-test of Redis/Mongo nodes during cascades) | High |

---

## 8. Living Reference Links

- **Staging Runbook & Topology**: [docs/STAGING.md](docs/STAGING.md)
- **Backend Capabilities & Messaging Backlog**: [docs/frontend/MESSAGING_BACKLOG.md](docs/frontend/MESSAGING_BACKLOG.md)
- **Reviewer Console Rejection Reason**: [docs/adr/ADR-0021-reviewer-rejection-reason.md](docs/adr/ADR-0021-reviewer-rejection-reason.md)
- **Modular Ops Console Expansion**: [docs/adr/0023-modular-ops-console-expansion.md](docs/adr/0023-modular-ops-console-expansion.md)
- **Reverse-Proxy SSE Buffering Resolution**: [docs/changelog/bug-fixes.md](docs/changelog/bug-fixes.md)
- **Production Deployment Standards**: [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)

