# Frontend Endpoint Integration Scope & Technical Audit

This document outlines the scoping, backend contracts, UI requirements, and implementation sequence required to wire unintegrated backend endpoints into the Flutter mobile application (`frontend/`).

---

## 1. Auth & Session Lifecycle Endpoints

### 1.1 `POST /auth/logout`
* **Backend Contract**: [`services/auth-service/internal/handlers/auth.go:1555`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/services/auth-service/internal/handlers/auth.go#L1555)
  * **Method**: `POST /auth/logout`
  * **Headers**: `Authorization: Bearer <JWT>`
  * **Body**: Empty JSON `{}`
  * **Response**: `200 OK` → `{"message": "successfully logged out"}`. Error `400` if Authorization header missing; `401` if token invalid/expired.
  * **Auth**: Requires valid Bearer JWT.
  * **Side Effects**: Revokes and blacklists the token via `jwtutil.RevokeToken(tokenStr)`.
* **Which Screen(s) / Provider(s) Should Call It**: `AuthProvider` ([`frontend/lib/providers/auth_provider.dart`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/frontend/lib/providers/auth_provider.dart)), invoked from `MyAccountScreen` ([`frontend/lib/screens/my_account_screen.dart`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/frontend/lib/screens/my_account_screen.dart)) and the app navigation drawer logout action.
* **UI Elements Needed**: "Logout" list tile in user settings, clearing auth tokens from `FlutterSecureStorage` and redirecting to `LoginScreen`.
* **Complexity Estimate**: **Small** — single API call and state clear.
* **Dependencies / Ordering**: Batch 1. Can be wired immediately.

### 1.2 `POST /auth/refresh`
* **Backend Contract**: [`services/auth-service/internal/handlers/auth.go:957`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/services/auth-service/internal/handlers/auth.go#L957)
  * **Method**: `POST /auth/refresh`
  * **Headers / Body**: JSON body `{"token": "<EXPIRED_OR_ACTIVE_JWT>"}` or fallback `Authorization: Bearer <JWT>` header.
  * **Response**: `200 OK` → `{"status": "success", "token": "<NEW_JWT>"}`. Errors: `401` if token expired > 7 days (`7*24*time.Hour`); `403` if account frozen (`!user.IsActive`).
  * **Auth**: Accepts active or expired JWTs within a 7-day grace period.
  * **Side Effects**: Validates user active state in MongoDB and re-issues a fresh signed JWT with updated claims.
* **Which Screen(s) / Provider(s) Should Call It**: `ApiClient` ([`frontend/lib/core/api_client.dart`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/frontend/lib/core/api_client.dart)) via HTTP response interceptor.
* **UI Elements Needed**: Transparent HTTP 401 retry interceptor in `api_service.dart`. On receiving HTTP 401, automatically call `/auth/refresh`; if successful, save the new token and retry the original failed HTTP request. If refresh fails (> 7 days expired), trigger `AuthProvider.logout()` and display a "Session Expired" toast.
* **Complexity Estimate**: **Small** — networking layer interceptor pattern.
* **Dependencies / Ordering**: Batch 1. Prevents active user sessions from abruptly disconnecting when access tokens expire.

### 1.3 `POST /auth/forgot-password`
* **Backend Contract**: [`services/auth-service/internal/handlers/auth.go:1689`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/services/auth-service/internal/handlers/auth.go#L1689)
  * **Method**: `POST /auth/forgot-password`
  * **Body**: `{"email": "user@example.com"}` (`ForgotPasswordRequest`)
  * **Response**: `200 OK` → `{"status": "success", "message": "If an account exists for this email, a reset code has been sent.", "dev_otp": "123456"}` (where `dev_otp` is present only when `APP_ENV=local`). Always returns 200 OK to prevent account enumeration.
  * **Auth**: Public / Unauthenticated.
  * **Side Effects**: Generates 6-digit OTP code, stores encrypted ciphertext in MongoDB (`SetOTP`), dispatches email via `ResendDispatcher`. Rate limited by IP and email address.
* **Which Screen(s) / Provider(s) Should Call It**: `ForgotPasswordScreen` ([`frontend/lib/screens/forgot_password_screen.dart`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/frontend/lib/screens/forgot_password_screen.dart)), wired to `AuthProvider`.
* **UI Elements Needed**: Consolidated single-step reset form on `ForgotPasswordScreen` with email, 6-digit OTP code, new password, and confirm password fields.
* **Complexity Estimate**: **Small** — straightforward single-input form and navigation trigger.
* **Dependencies / Ordering**: Batch 1. Precedes `POST /auth/reset-password`.

### 1.4 `POST /auth/reset-password`
* **Backend Contract**: [`services/auth-service/internal/handlers/auth.go:1776`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/services/auth-service/internal/handlers/auth.go#L1776)
  * **Method**: `POST /auth/reset-password`
  * **Body**: `{"email": "user@example.com", "otp": "123456", "new_password": "NewPassword123!"}` (`ResetPasswordRequest`)
  * **Response**: `200 OK` → `{"status": "success", "message": "Password reset successfully. You can now login with your new password."}`. Error `400` if fields missing; `401` if invalid/expired OTP; `404` if user not found.
  * **Auth**: Public / Unauthenticated.
  * **Side Effects**: Verifies OTP against MongoDB (`VerifyOTP`), hashes new password with bcrypt, updates user document, and clears OTP fields (`otp_code`, `otp_verified`, `otp_expires_at`).
* **Which Screen(s) / Provider(s) Should Call It**: `ForgotPasswordScreen` ([`frontend/lib/screens/forgot_password_screen.dart`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/frontend/lib/screens/forgot_password_screen.dart)), wired to `AuthProvider`.
* **UI Elements Needed**: Consolidated single-step reset form on `ForgotPasswordScreen` with email, 6-digit OTP code, new password, and confirm password fields.
* **Complexity Estimate**: **Small** — consolidated 1-step reset form reusing existing OTP input widgets.
* **Dependencies / Ordering**: Batch 1. Depends on `POST /auth/forgot-password`.

---

## 2. Job Lifecycle & Customer Order Management Endpoints

### 2.1 `GET /users/jobs/mine`
* **Backend Contract**: [`services/user-service/internal/handlers/handlers.go:1024`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/services/user-service/internal/handlers/handlers.go#L1024)
  * **Method**: `POST /users/jobs/mine` (or `GET /users/jobs/mine`)
  * **Headers / Query Params**: `Authorization: Bearer <JWT>`
  * **Response**: `200 OK` → List of jobs owned/booked by current user.
  * **Auth**: Standard user Bearer token.
* **Which Screen(s) / Provider(s) Should Call It**: `CustomerJobsScreen` ([`frontend/lib/screens/customer_jobs_screen.dart`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/frontend/lib/screens/customer_jobs_screen.dart)) via `MarketplaceProvider` ([`frontend/lib/providers/marketplace_provider.dart`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/frontend/lib/providers/marketplace_provider.dart)).
* **UI Elements Needed**: "My Orders / History" screen for customer role displaying a list of order cards, status badges (`pending`, `active`, `completed`, `cancelled`), service details, timestamp, and tap-to-track navigation to `JobStatusScreen`.
* **Complexity Estimate**: **Medium** — requires new customer order list screen and provider binding.
* **Dependencies / Ordering**: Batch 2. Core order history feature for customer role.

### 2.2 `POST /users/jobs/cancel`
* **Backend Contract**: [`services/user-service/internal/handlers/handlers.go:2101`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/services/user-service/internal/handlers/handlers.go#L2101)
  * **Method**: `POST /users/jobs/cancel`
  * **Body**: `{"job_id": "...", "reason": "...", "requester_id": "optional_token_or_id"}`
  * **Headers / Query Params**: `Authorization: Bearer <JWT>` (or query param `requester_id`).
  * **Response**: `200 OK` → `{"status": "cancelled", "job_id": "...", "refund_issued": true|false}`. Error `403` if customer attempts to cancel an `active` job ("customer-initiated cancellation of active jobs is not allowed. Please open a complaint ticket.").
  * **Auth**: Authorized for job owner (`models.RoleOwner`) or job customer (`models.RoleUser`). Customers can only cancel `pending` jobs.
  * **Side Effects**: Updates job status to `cancelled` in MongoDB. For non-COD jobs, refunds escrow from owner balance back to customer wallet and records a ledger entry. Broadcasts WebSocket update.
* **Which Screen(s) / Provider(s) Should Call It**: `JobStatusScreen` ([`frontend/lib/screens/job_status_screen.dart`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/frontend/lib/screens/job_status_screen.dart)), wired to `MarketplaceProvider`.
* **UI Elements Needed**: "Cancel Job" button on `JobStatusScreen`. For customers, visible only when job status is `pending`; for owners, visible on `pending` or `active`. Clicking opens a confirmation dialog with a mandatory cancellation reason text field.
* **Complexity Estimate**: **Small** — action button, confirmation modal with reason input, and provider method `cancelJob()`.
* **Dependencies / Ordering**: Batch 2.

### 2.3 `POST /users/jobs/complete`
* **Backend Contract**: [`services/user-service/internal/handlers/handlers.go:643`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/services/user-service/internal/handlers/handlers.go#L643)
  * **Method**: `POST /users/jobs/complete`
  * **Body**: `{"job_id": "...", "requester_id": "optional_token_or_id"}` (`CompleteJobRequest`)
  * **Headers / Query Params**: `Authorization: Bearer <JWT>` (or query param `requester_id`).
  * **Response**: `200 OK` → `{"status": "completed", "job_id": "...", "settled_amount": 150.0}`. Error `403` if customer attempts completion (customers cannot complete jobs).
  * **Auth**: Authorized for job owner (`models.RoleOwner`) or assigned employee/driver (`models.RoleEmployee`).
  * **Side Effects**: Updates job status to `completed` in MongoDB, settles escrow (transfers funds to owner/driver, calculates distance pricing, writes ledger transaction), broadcasts FCM push notification / SSE job completion event.
* **Which Screen(s) / Provider(s) Should Call It**: `JobStatusScreen` ([`frontend/lib/screens/job_status_screen.dart`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/frontend/lib/screens/job_status_screen.dart)) or driver active navigation screen, wired to `MarketplaceProvider` / `MapTrackingProvider`.
* **UI Elements Needed**: "Complete Delivery" primary action button for driver or business owner when job status is `active`. Clicking triggers confirmation dialog and executes `completeJob()`.
* **Complexity Estimate**: **Small** — primary action button, confirmation dialog, and provider method `completeJob()`.
* **Dependencies / Ordering**: Batch 2.

---

## 3. Discrepancy Audits & Corrections

### 3.1 Discrepancy 1: `home_screen.dart` Active Jobs Placeholder vs `GET /users/jobs/owner`
* **Backend Contract**: `GET /users/jobs/owner?active_only=true` (or `filter=active`) is fully implemented in [`services/user-service/internal/handlers/handlers.go:975`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/services/user-service/internal/handlers/handlers.go#L975). It returns an array of `OwnerJobResponse` objects owned by the authenticated business owner.
* **Frontend Code Status**: [`frontend/lib/providers/map_tracking_provider.dart:56`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/frontend/lib/providers/map_tracking_provider.dart#L56) ALREADY calls `/users/jobs/owner?active_only=true` in `fetchOwnerJobs()`. However, [`frontend/lib/screens/home_screen.dart:512`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/frontend/lib/screens/home_screen.dart#L512) displays a static placeholder card with a comment claiming *"the user-service does not currently expose an API endpoint to list active jobs for owners"*.
* **Root Cause & Resolution**: The inline comment and static empty state in `home_screen.dart` are **stale technical debt**. `home_screen.dart` should be refactored to consume `MapTrackingProvider` (or `MarketplaceProvider`), invoke `fetchOwnerJobs()`, and render dynamic active job cards displaying live job status, assigned driver name, and direct tracking buttons.
* **Complexity Estimate**: **Small** — replace static placeholder card in `home_screen.dart` with a dynamic `ListView` bound to `MapTrackingProvider.fetchOwnerJobs()`.
* **Dependencies / Ordering**: Batch 2. High priority — removes visible placeholder defect for business owners.

### 3.2 Discrepancy 2: `notifications_screen.dart` `placeholderJob` vs `GET /users/jobs/get`
* **Backend Contract**: `GET /users/jobs/get?job_id=...` (or `id=...`) is fully implemented in [`services/user-service/internal/handlers/handlers.go:870`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/services/user-service/internal/handlers/handlers.go#L870). It returns the full `Job` model from MongoDB.
* **Frontend Code Status**: [`frontend/lib/screens/notifications_screen.dart:343`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/frontend/lib/screens/notifications_screen.dart#L343) constructs a hardcoded `final placeholderJob = Job(id: extractedJobId!, ownerId: '', userId: '', serviceId: '', status: 'pending', location: JobLocation(latitude: 0, longitude: 0), paymentMethod: 'cod')` when a user taps "Track Shipment" on a notification, passing incomplete dummy data (including (0,0) coordinates) to `JobStatusScreen`.
* **Root Cause & Resolution**: `notifications_screen.dart` bypasses backend data fetching. When "Track Shipment" is tapped, `notifications_screen.dart` should call `MarketplaceProvider.fetchJobStatus(extractedJobId!, userToken)`, display a brief loading spinner, and upon receiving the real `Job` object from `GET /users/jobs/get`, navigate to `JobStatusScreen(job: realJob)`.
* **Complexity Estimate**: **Small** — replace inline dummy constructor in `notifications_screen.dart` with `MarketplaceProvider.fetchJobStatus()` async call and loading overlay.
* **Dependencies / Ordering**: Batch 2. High priority — resolves invalid coordinate rendering when navigating from notification alerts.

---

## 4. Fleet & Fleet Management Endpoints

### 4.1 `GET /auth/employees`
* **Backend Contract**: [`services/auth-service/internal/handlers/auth.go:1947`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/services/auth-service/internal/handlers/auth.go#L1947)
  * **Method**: `GET /auth/employees`
  * **Headers / Query Params**: `Authorization: Bearer <JWT>` (or query param `owner_token`).
  * **Response**: `200 OK` → Array of `EmployeeResponse`: `[{"id": "...", "username": "...", "email": "...", "is_active": true/false, "created_at": "..."}]`
  * **Auth**: Must have `models.RoleOwner` ("owner" role).
  * **Side Effects**: Queries MongoDB for all employee/driver accounts associated with the requesting owner ID (`GetEmployeesByOwner`).
* **Which Screen(s) / Provider(s) Should Call It**: `EmployeeScreen` ([`frontend/lib/screens/employee_screen.dart`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/frontend/lib/screens/employee_screen.dart)) or `HomeScreen` ([`frontend/lib/screens/home_screen.dart`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/frontend/lib/screens/home_screen.dart)), wired into `OwnerProvider`.
* **UI Elements Needed**: "Manage Drivers" card on owner dashboard opening `EmployeeScreen`, listing registered drivers, active status toggles, creation dates, and driver addition controls.
* **Complexity Estimate**: **Medium** — requires new list UI view with driver status indicators for business owners.
* **Dependencies / Ordering**: Batch 3 (Fleet Management).

---

## 5. Compliance & KYC Review Admin Flow Endpoints

### 5.1 `GET /auth/kyb-kye/pending` **[EXCLUDED PER ADR-0013]**
* **Backend Contract**: [`services/auth-service/internal/handlers/auth.go:1279`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/services/auth-service/internal/handlers/auth.go#L1279)
* **Which Screen(s) / Provider(s) Should Call It**: **[EXCLUDED PER ADR-0013]** Reserved for separate Support Agent Console application.

### 5.2 `POST /auth/kyb-kye/review` **[EXCLUDED PER ADR-0013]**
* **Backend Contract**: [`services/auth-service/internal/handlers/auth.go:1373`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/services/auth-service/internal/handlers/auth.go#L1373)
* **Which Screen(s) / Provider(s) Should Call It**: **[EXCLUDED PER ADR-0013]** Reserved for separate Support Agent Console application.

### 5.3 `GET /auth/documents/view` **[EXCLUDED PER ADR-0013]**
* **Backend Contract**: [`services/auth-service/internal/handlers/auth.go:1463`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/services/auth-service/internal/handlers/auth.go#L1463)
* **Which Screen(s) / Provider(s) Should Call It**: **[EXCLUDED PER ADR-0013]** Reserved for separate Support Agent Console application.

---

## 6. Helpdesk Support, Location Tracking & Config Endpoints

### 6.1 `POST /chat/tickets`
* **Backend Contract**: [`services/chat-service/internal/handlers/chat.go:678`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/services/chat-service/internal/handlers/chat.go#L678)
  * **Method**: `POST /chat/tickets`
  * **Body**: `{"context_id": "optional_job_id"}`
  * **Headers / Query Params**: `Authorization: Bearer <JWT>` (or query param `token`).
  * **Response**: `201 Created` → Ticket object: `{"id": "...", "context_id": "...", "customer_id": "...", "assigned_agent_id": "...", "status": "open"|"assigned"|"queued", "created_at": "...", "updated_at": "..."}`
  * **Auth**: Any authenticated user JWT (`claims.UserID`). Rate-limited per user (`ticket_create:<user_id>`).
  * **Side Effects**: Creates support ticket in MongoDB (`CreateTicketAndAssign`), automatically assigns available support agent if online, ships `TICKET_CREATED` and `TICKET_ASSIGNED`/`TICKET_QUEUED` security events.
* **Which Screen(s) / Provider(s) Should Call It**: `ChatProvider` ([`frontend/lib/providers/chat_provider.dart`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/frontend/lib/providers/chat_provider.dart)), invoked from `JobStatusScreen` ("Contact Support / File Dispute") or `CreateTicketDialog` ([`frontend/lib/widgets/create_ticket_dialog.dart`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/frontend/lib/widgets/create_ticket_dialog.dart)).
* **UI Elements Needed**: "Open Support Ticket" button on `JobStatusScreen` opening `CreateTicketDialog` that prompts user for problem context, calls `createTicket(contextId)`, and opens a support chat session.
* **Complexity Estimate**: **Medium** — ticket creation flow and support chat session binding in `ChatProvider`.
* **Dependencies / Ordering**: Batch 5.

### 6.2 `POST /chat/tickets/resolve`
* **Backend Contract**: [`services/chat-service/internal/handlers/chat.go:735`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/services/chat-service/internal/handlers/chat.go#L735)
  * **Method**: `POST /chat/tickets/resolve`
  * **Body**: `{"ticket_id": "..."}`
  * **Headers / Query Params**: `Authorization: Bearer <JWT>` (or query param `token`).
  * **Response**: `200 OK` → `{"status": "resolved", "ticket_id": "..."}`.
  * **Auth**: Requires valid support agent JWT token (`GetAgentByToken`). Must be assigned agent for that ticket (`ticket.AssignedAgentID == agent.ID`).
  * **Side Effects**: Updates ticket status to `resolved` in MongoDB, frees agent support capacity in pool, ships `TICKET_RESOLVED` security event.
* **Which Screen(s) / Provider(s) Should Call It**: Support Agent Chat Interface (`SupportAgentScreen` / `ChatScreen` for support agents), managed by `ChatProvider`.
* **UI Elements Needed**: "Resolve Ticket" button in the support agent's chat header bar. Visible only when logged in as a support agent viewing an assigned ticket.
* **Complexity Estimate**: **Small** — action button in agent chat header and provider method `resolveTicket()`.
* **Dependencies / Ordering**: Batch 5. Depends on `POST /chat/tickets`.

### 6.3 `POST /users/jobs/location/update`
* **Backend Contract**: [`services/user-service/internal/handlers/handlers.go:1788`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/services/user-service/internal/handlers/handlers.go#L1788)
  * **Method**: `POST /users/jobs/location/update`
  * **Body**: `{"job_id": "...", "requester_id": "...", "latitude": 30.0444, "longitude": 31.2357}`
  * **Headers**: `Authorization: Bearer <JWT>`
  * **Response**: `200 OK` → `{"status": "updated", "job_id": "...", "location": {"latitude": 30.0444, "longitude": 31.2357}}`
  * **Auth**: Must be assigned employee/driver (`models.RoleEmployee`) on an active job (`JobStatusActive`). Validates owner subscription tier (`PlanPaid`).
  * **Side Effects**: Validates coordinate boundaries (-90..90, -180..180), runs speed physics spoofing checks, updates job location in MongoDB, broadcasts position via internal token to `chat-service` for WebSocket streaming to customer/owner. Rate limited to 1 update per 2 seconds.
* **Which Screen(s) / Provider(s) Should Call It**: `MapTrackingProvider` ([`frontend/lib/providers/map_tracking_provider.dart`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/frontend/lib/providers/map_tracking_provider.dart)), invoked periodically (e.g. background GPS timer) when a driver is navigating on active delivery.
* **UI Elements Needed**: Background REST location update fallback method inside `MapTrackingProvider` when WebSocket connection drops or as periodic HTTP heartbeats during driver active navigation.
* **Complexity Estimate**: **Small** — provider method addition for REST location updates alongside existing WebSocket streaming.
* **Dependencies / Ordering**: Batch 5.

### 6.4 `GET /users/platform/config`
* **Backend Contract**: [`services/user-service/internal/handlers/handlers.go:1275`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/services/user-service/internal/handlers/handlers.go#L1275)
  * **Method**: `GET /users/platform/config`
  * **Request**: None
  * **Response**: `200 OK` → `{"id": "...", "platform_fee_percentage": 5.0, "platform_wallet_id": "..."}`
  * **Auth**: Public / Unauthenticated.
  * **Side Effects**: Retrieves global platform settings from MongoDB.
* **Which Screen(s) / Provider(s) Should Call It**: `MarketplaceProvider` ([`frontend/lib/providers/marketplace_provider.dart`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/frontend/lib/providers/marketplace_provider.dart)) or app initialization / checkout flow (`JobBookingScreen` / `CheckoutScreen`).
* **UI Elements Needed**: Dynamic platform fee calculation display during job creation / checkout (e.g. showing "Platform Fee (5%)" dynamically derived from backend config rather than hardcoded 5%).
* **Complexity Estimate**: **Trivial** — simple GET call on app/checkout load to populate fee percentage dynamically.
* **Dependencies / Ordering**: Batch 5.

### 6.5 `POST /notifications/send`
* **Backend Contract**: [`services/notification-service/internal/handlers/handlers.go:239`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/services/notification-service/internal/handlers/handlers.go#L239)
  * **Method**: `POST /notifications/send`
  * **Headers**: `X-Internal-Token` matching `n.internalServiceToken`.
  * **Body**: `{"title": "...", "body": "...", "type": "popup"|"alert", "tenant_id": "...", "user_id": "optional", "user_ids": ["..."], "global": false, "roles": ["owner"]}` (`sendRequest`)
  * **Response**: `200 OK` → `{"status": "queued", "id": "notif-123456789"}`
  * **Auth**: Requires `X-Internal-Token` (Internal inter-service route only, intended for backend microservice-to-notification-service calls or administrative internal dispatch, NOT directly callable by client JWT tokens without internal proxy/gateway).
  * **Side Effects**: Broadcasts notification via SSE stream / FCM push service to targeted users/roles.
* **Which Screen(s) / Provider(s) Should Call It**: Not directly callable by standard client Flutter app (requires `X-Internal-Token`). If client administrative features need direct broadcast capabilities, `api-gateway` or `auth-service` must expose a proxy route; alternatively, used exclusively by backend microservices and admin CLI tools.
* **UI Elements Needed**: N/A for standard client app. If an Admin Console is added in the future, an "Admin Notification Broadcast" form calling a backend proxy endpoint would be added.
* **Complexity Estimate**: **Small** (Backend proxy / Admin tool context) — standard notification dispatch.
* **Dependencies / Ordering**: Batch 5.

---

## 7. Suggested Implementation Order

The 18 scoped items are grouped into 5 sequential implementation batches ordered by architectural dependency and user impact:

```
┌─────────────────────────────────────────────────────────────────────────┐
│ Batch 1: Auth & Token Lifecycle                                        │
│ Endpoints: /auth/logout, /auth/refresh, /auth/forgot-pass, /auth/reset │
│ Rationale: Establishes session security, token auto-refresh, and        │
│ self-service password recovery before wiring complex functional flows. │
└────────────────────┬────────────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ Batch 2: Core Job Lifecycle & UI Discrepancy Fixes                      │
│ Endpoints: /users/jobs/mine, /users/jobs/cancel, /users/jobs/complete  │
│ Discrepancies: home_screen.dart active jobs & notifications_screen.dart │
│ Rationale: Completes end-to-end order history and job status lifecycle  │
│ for customers, drivers, and owners while resolving existing UI gaps.   │
└────────────────────┬────────────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ Batch 3: Business Owner Fleet Management                                │
│ Endpoints: /auth/employees                                              │
│ Rationale: Provides business owners with driver list visibility and     │
│ management controls on the owner dashboard.                             │
└────────────────────┬────────────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ Batch 4: Compliance & KYC Review Admin Flow                             │
│ Endpoints: /auth/kyb-kye/pending, /auth/kyb-kye/review, /documents/view │
│ Rationale: Admin-facing verification queue for reviewing KYB (business) │
│ and KYE (driver) document submissions.                                  │
└────────────────────┬────────────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ Batch 5: Helpdesk Support, Location Tracking & Config                   │
│ Endpoints: /chat/tickets, /chat/tickets/resolve, /location/update,      │
│            /platform/config, /notifications/send                        │
│ Rationale: Auxiliary support ticket handling, REST location fallback,   │
│ dynamic platform fee loading, and internal notification dispatch.       │
└─────────────────────────────────────────────────────────────────────────┘
```

1. **Batch 1 (Auth & Token Lifecycle)**: Must be implemented first. Automatic 401 token refresh (`/auth/refresh`) and explicit revocation (`/auth/logout`) prevent session drops and security leaks across all subsequent screens. Password recovery (`/auth/forgot-password` and `/auth/reset-password`) completes fundamental user onboarding.
2. **Batch 2 (Core Job Lifecycle & Discrepancies)**: Second priority. Fills core operational gaps for customers (`/users/jobs/mine`), allows job cancellation (`/users/jobs/cancel`) and completion (`/users/jobs/complete`), and fixes the two identified UI discrepancies in `home_screen.dart` and `notifications_screen.dart`.
3. **Batch 3 (Fleet Management)**: Third priority. Enables tenant owners to view and manage registered driver/employee accounts (`/auth/employees`).
4. **Batch 4 (Compliance & KYC Review Admin Flow)**: Fourth priority. Admin/Reviewer flow for viewing pending KYB/KYE document submissions (`/auth/kyb-kye/pending`), viewing documents (`/auth/documents/view`), and approving/rejecting submissions (`/auth/kyb-kye/review`).
5. **Batch 5 (Helpdesk Support, Location Tracking & Config)**: Final batch. Implements support ticket creation and resolution (`/chat/tickets`, `/chat/tickets/resolve`), REST location updates (`/users/jobs/location/update`), dynamic platform fee configuration (`/users/platform/config`), and internal notification dispatching (`/notifications/send`).
