# QA Strategy & Regression Coverage Matrix

## 1. Executive Summary & Phase Ordering Notice

This document serves as the persistent single source of truth for quality assurance, release gates, regression protection, and test coverage across the Quick Delivery SaaS platform.

> [!NOTE]
> **Phase-Ordering Correction (Audited Retroactively)**:
> In the initial execution of the QA Strategy initiative, the team prioritized establishing the staging-parity environment (Phase 0) and implementing the end-to-end Critical User Journeys (Phase 2: CUJ-A through CUJ-H). As caught by the product owner, Phase 1 (Baseline Audit) was skipped during that initial push. This document records the **retroactive Phase 1 Baseline Audit**, cataloguing what test coverage existed in the codebase prior to commit `370893d`, establishing a transparent and honest before/after picture of system quality and regression protection.

This matrix is explicitly divided into two major sections:
* **Section A: Pre-Existing Coverage (Baseline, Audited Retroactively)**: The state of unit, integration, security, and infrastructure tests pre-dating the QA strategy initiative (everything prior to commit `370893d`).
* **Section B: New Coverage Added by QA Strategy Initiative**: Net-new end-to-end user journeys (CUJ-A through CUJ-H), the unified Auth/RBAC Security Matrix, automated backend-frontend parity tooling, and staging-parity CI release gates.

---

## 2. Comprehensive Master Coverage Gap Matrix

The following table provides the authoritative before/after audit across all functional categories, contrasting baseline pre-existing tests with net-new QA strategy additions to identify remaining backlogged gaps:

| Functional Domain / Category | Pre-Existing Coverage (Baseline) | Citation / Evidence | Covered by New E2E CUJs? | Still Uncovered Post-Initiative? | Status / Tracking |
| :--- | :---: | :--- | :---: | :---: | :--- |
| **API Endpoints (80 Canonical Routes)** | **YES** | Unit/handler tests in service `*_test.go` | **YES** | ❌ No | Fully Covered |
| **API Endpoints: Version Config** (`GET`/`PUT /api/v1/admin/version-config`) | **NO** | Zero HTTP handler tests (`cmd/main.go:94`) | **NO** | ⚠️ **YES** | **Backlog QA-GAP-01** |
| **API Endpoints: Deprecated Orphan** (`POST /chat/tickets/resolve`) | **YES** | `services/chat-service/.../chat_test.go:1282` | **NO** (superseded by `/admin/tickets/resolve`) | ❌ No | **Backlog QA-GAP-05** (Sunset) |
| **Authentication: Signup & Account Creation** | **YES** | `auth_test.go:271`, `auth_identity_repro_test.go:19` | **YES** (CUJ-C) | ❌ No | Fully Covered |
| **Authentication: 2FA Login & OTP Lifecycle** | **YES** | `auth_test.go:291`, `otp_consume_race_regression_test.go:31` | **YES** (CUJ-C) | ❌ No | Fully Covered |
| **Authentication: Password Reset & Anti-Enumeration** | **YES** | `auth_test.go:2862` (`TestForgotPassword_AntiEnumeration`) | **NO** | ❌ No | Baseline Protected |
| **Authentication: Session Denylist & Token Revocation** | **YES** | `auth_test.go:1147` (`TestLogout_Denylist`), `jwt_test.go:12` | **YES** (CUJ-C) | ❌ No | Fully Covered |
| **Authentication: Account Suspension & Banners** | **YES** | `account_suspension_test.go:431` (`TestSuspendAndReactivateLifecycle`) | **NO** | ❌ No | Baseline Protected |
| **Role-Based Access Control (RBAC Matrix)** | **NO** | **Zero systematic regression matrix** (only ad-hoc role checks) | **YES** (`TestAuthMatrix` in `auth_matrix_test.go`) | ❌ No | Net-New Protected |
| **Cross-Tenant IDOR Guards** | Partial | Ad-hoc checks in `reconciliation_test.go`, `handlers_test.go` | **YES** (CUJ-D, CUJ-E, CUJ-F, `TestAuthMatrix`) | ❌ No | Net-New Protected |
| **WebSocket: Direct Hub / Dispatch Logic** | **YES** | `chat_test.go:791`, `hub_test.go:14`, `hub_concurrency_repro_test.go` | **YES** (CUJ-A, CUJ-F, CUJ-H) | ❌ No | Fully Covered |
| **WebSocket: Live Edge Proxy Upgrades (101)** | **NO** | Tests used direct `httptest.Server` (bypassed Caddy & resilience proxy) | **YES** (CUJ-A, CUJ-F, CUJ-H via Caddy `:8088`) | ❌ No | Net-New Protected |
| **Orders: Booking & Spatial Dispatch** | **YES** | `handlers_test.go:230`, `adr0006_e2e_integration_test.go:175` | **YES** (CUJ-A, CUJ-D) | ❌ No | Fully Covered |
| **Orders: Price Negotiation (Propose / Counter)** | **YES** | `adr0006_e2e_integration_test.go:212`, `negotiation_concurrency_test.go:15` | **NO** | ❌ No | Baseline Protected |
| **Delivery Lifecycle: Escrow Locking & Release** | **YES** | `escrow_state_audit_test.go:20`, `money_state_repro_test.go:15` | **YES** (CUJ-A, CUJ-D) | ❌ No | Fully Covered |
| **Delivery Lifecycle: COD & Reconciliation** | **YES** | `reconciliation_test.go:35`, `admin_reconciliation_test.go:101` | **YES** (CUJ-E) | ❌ No | Fully Covered |
| **Driver Workflow: Heartbeat & Availability** | **YES** | `available_employees_test.go:15`, `employee_dispatch_pricing_test.go:126` | **YES** (CUJ-A, CUJ-D) | ❌ No | Fully Covered |
| **Driver Workflow: Cascade Offer Accept / Decline** | **YES** | `cascade_dispatch_repro_test.go:249`, `dispatch_cascade_isolation_repro_test.go` | **YES** (CUJ-A) | ❌ No | Fully Covered |
| **Owner Workflow: Service Catalog & Config** | **YES** | `service_owner_config_test.go:15`, `list_services_test.go:12` | **YES** (CUJ-E) | ❌ No | Fully Covered |
| **Owner Workflow: Paid-Tier Subscription Gating** | **YES** | `paid_tier_gating_matrix_test.go:15`, `auth_paid_tier_gating_test.go:15` | **YES** (CUJ-E) | ❌ No | Fully Covered |
| **Owner Workflow: Wallets, Deposits & Payouts** | **YES** | `extra_handlers_test.go:210`, `fund_endpoint_rate_limit_test.go:120` | **YES** (CUJ-E) | ❌ No | Fully Covered |
| **Chat: Job Messaging & Durable History** | **YES** | `chat_test.go:282`, `admin_tickets_test.go:496` | **YES** (CUJ-F) | ❌ No | Fully Covered |
| **Chat: Customer Ticket Filing & Agent Routing** | **YES** | `chat_test.go:746`, `ticket_agent_repro_test.go:25` | **YES** (CUJ-H) | ❌ No | Fully Covered |
| **Ops Console: KYC/KYB Document Review** | **YES** | `auth_test.go:583`, `reviewer_credential_era_test.go:20` | **YES** (CUJ-B via Console `:8091`) | ❌ No | Fully Covered |
| **Ops Console: Support Ticket Resolution** | **YES** | `admin_tickets_test.go:252` | **YES** (CUJ-H via Console `:8091`) | ❌ No | Fully Covered |
| **Notifications: Real-Time SSE Streams** | **YES** | `handlers_test.go:204`, `q18_test.go:14` | **YES** (CUJ-A, CUJ-B, CUJ-H) | ❌ No | Fully Covered |
| **Notifications: In-App History & Read State** | **YES** | `history_handlers_test.go:295`, `history_handlers_test.go:412` | **NO** | ❌ No | Baseline Protected |
| **Notifications: Notification Isolation (N-01/N-02)** | **YES** | `dispatch_notification_isolation_test.go:80` | **YES** (CUJ-A) | ❌ No | Fully Covered |
| **Rating: Double-Blind Rating & Star Bounds** | **YES** | `extra_handlers_test.go:293`, `ratings_target_guard_regression_test.go:15` | **YES** (CUJ-G) | ❌ No | Fully Covered |
| **Static Security Analysis (`gosec`, `govulncheck`)** | **YES** | Active in CI (`.github/workflows/ci.yml:164-173`) | N/A (Static tooling) | ❌ No | Active in CI |
| **Repository Integrity (SHAs & Drift Guards)** | **YES** | Active in CI (`.github/workflows/ci.yml:29-104`) | N/A (Integrity tooling) | ❌ No | Active in CI |
| **Docker / Infra: Multi-Container Staging Parity** | **NO** | CI only ran isolated Mongo/Redis runner containers | **YES** (`.github/workflows/release-gate-e2e.yml`) | ❌ No | Net-New Protected |
| **Contract Testing (Schema-Based / Consumer-Driven)** | **NO** | Tests relied on live datastores or in-memory mocks | **YES** (`tests/contracts`) | ❌ No | Closed in Phase 4 (QA-GAP-02) |
| **Push Notifications: Live FCM Token Dispatch** | **NO** | Only mock dispatcher in `fcm_test.go` | **NO** (Mocked in staging) | ⚠️ **YES** | **Backlog QA-GAP-03** |
| **Chaos & Resiliency: Mid-Cascade Datastore Failure** | **NO** | Zero chaos / container crash tests | **NO** | ⚠️ **YES** | **Backlog QA-GAP-04** |

---

## 3. Section A: Pre-Existing Coverage (Baseline, Audited Retroactively)

This section inventories what test coverage existed in the repository prior to commit `370893d`, organized across the 7 categories defined in the original QA strategy proposal.

### Category 1: API Endpoint Unit & Handler Test Coverage

The platform registers **98 total HTTP route entries**, representing **82 canonical endpoints** and **16 companion route aliases** (backward-compatible aliases matching mobile app or reviewer console call patterns).

Every endpoint was audited against pre-existing test suites (excluding `tests/e2e`). **80 of the 82 canonical endpoints (97.6%)** possessed dedicated unit/handler tests. Exactly **2 endpoints** had zero pre-existing test coverage.

| # | Service | Method | Route Path | Handler Name | Type | Pre-Existing Unit/Handler Test Citation | Baseline Covered? |
| :-: | :--- | :--- | :--- | :--- | :--- | :--- | :-: |
| 01 | `api-gateway` | `GET` | `/health` | `GatewayHealth` | Canonical | services/api-gateway/internal/middleware/route_override_test.go:124 (`TestRateLimitWithOverrides_LoopbackExempt`) | ✅ Yes |
| 02 | `api-gateway` | `GET` | `/health/internal` | `GatewayInternalHealth` | Canonical | services/api-gateway/internal/proxy/proxy_test.go:230 (`TestRouteSegregation`) | ✅ Yes |
| 03 | `api-gateway` | `GET` | `/api/v1/admin/version-config` | `GetVersionConfig` | Canonical | **None** (Zero pre-existing test) | ❌ No |
| 04 | `api-gateway` | `PUT` | `/api/v1/admin/version-config` | `UpdateVersionConfig` | Canonical | **None** (Zero pre-existing test) | ❌ No |
| 05 | `api-gateway` | `GET` | `/` | `GatewayIndex` | Canonical | services/api-gateway/internal/config/config_test.go:51 (`TestLoad`) | ✅ Yes |
| 06 | `auth-service` | `POST` | `/auth/signup` | `Signup` | Canonical | services/auth-service/internal/handlers/auth_test.go:271 (`TestAuthHandlers`) | ✅ Yes |
| 07 | `auth-service` | `POST` | `/auth/login` | `Login` | Canonical | services/auth-service/internal/handlers/auth_test.go:312 (`TestAuthHandlers`) | ✅ Yes |
| 08 | `auth-service` | `POST` | `/auth/resend-otp` | `ResendOTP` | Canonical | services/auth-service/internal/handlers/auth_test.go:1219 (`TestOTPResendFlow`) | ✅ Yes |
| 09 | `auth-service` | `POST` | `/auth/verify-otp` | `VerifyOTP` | Canonical | services/auth-service/internal/handlers/auth_test.go:291 (`TestAuthHandlers`) | ✅ Yes |
| 10 | `auth-service` | `POST` | `/auth/forgot-password` | `ForgotPassword` | Canonical | services/auth-service/internal/handlers/auth_test.go:2890 (`TestForgotPassword_AntiEnumeration`) | ✅ Yes |
| 11 | `auth-service` | `POST` | `/auth/reset-password` | `ResetPassword` | Canonical | services/auth-service/internal/handlers/auth_test.go:2989 (`TestResetPassword_Success`) | ✅ Yes |
| 12 | `auth-service` | `POST` | `/auth/refresh` | `Refresh` | Canonical | services/auth-service/internal/handlers/auth_test.go:508 (`TestAuthHandlers`) | ✅ Yes |
| 13 | `auth-service` | `POST` | `/auth/employee/toggle` | `ToggleEmployee` | Canonical | services/auth-service/internal/handlers/auth_paid_tier_gating_test.go:135 (`TestToggleEmployee_PaidTierGating`) | ✅ Yes |
| 14 | `auth-service` | `POST` | `/auth/employee/action` | `SimulateEmployeeAction` | Canonical | services/auth-service/internal/handlers/account_suspension_test.go:252 (`TestVerifyEmployeeAssignment_SuspendedChecks`) | ✅ Yes |
| 15 | `auth-service` | `GET` | `/auth/audit-log` | `GetAuditLog` | Canonical | services/auth-service/internal/handlers/account_suspension_test.go:669 (`TestSuspendAndReactivateLifecycle`) | ✅ Yes |
| 16 | `auth-service` | `GET` | `/auth/employees` | `GetEmployees` | Canonical | services/auth-service/internal/handlers/auth_test.go:2438 (`TestGetEmployees`) | ✅ Yes |
| 17 | `auth-service` | `GET` | `/auth/user` | `GetUser` | Canonical | services/auth-service/internal/handlers/auth_test.go:471 (`TestAuthHandlers`) | ✅ Yes |
| 18 | `auth-service` | `PATCH` | `/auth/user` | `UpdateProfile` | Canonical | services/auth-service/internal/handlers/user_profile_test.go:108 (`TestUpdateOwnProfile_Valid`) | ✅ Yes |
| 19 | `auth-service` | `GET` | `/auth/user/public-profile` | `GetPublicProfile` | Canonical | services/auth-service/internal/handlers/auth_identity_repro_test.go:102 (`TestRepro_Q25_GetPublicProfile_AliasAndHeaderHandling`) | ✅ Yes |
| 20 | `auth-service` | `POST` | `/auth/kyb/upload` | `UploadKYB` | Canonical | services/auth-service/internal/handlers/auth_test.go:583 (`TestKYBKYEUploadAndReview`) | ✅ Yes |
| 21 | `auth-service` | `POST` | `/auth/kye/upload` | `UploadKYE` | Canonical | services/auth-service/internal/handlers/auth_test.go:803 (`TestKYBKYEUploadAndReview`) | ✅ Yes |
| 22 | `auth-service` | `GET` | `/auth/kyb-kye/pending` | `GetPendingKYBKYESubmissions` | Canonical | services/auth-service/internal/handlers/auth_test.go:644 (`TestKYBKYEUploadAndReview`) | ✅ Yes |
| 23 | `auth-service` | `POST` | `/auth/kyb-kye/review` | `ReviewKYBKYESubmissions` | Canonical | services/auth-service/internal/handlers/auth_test.go:725 (`TestKYBKYEUploadAndReview`) | ✅ Yes |
| 24 | `auth-service` | `GET` | `/auth/documents/view` | `ViewDocument` | Canonical | services/auth-service/internal/handlers/auth_test.go:690 (`TestKYBKYEUploadAndReview`) | ✅ Yes |
| 25 | `auth-service` | `GET` | `/auth/accounts` | `GetAccounts` | Canonical | services/auth-service/internal/handlers/account_suspension_test.go:275 (`TestGetAccounts_SecurityAndFilters`) | ✅ Yes |
| 26 | `auth-service` | `POST` | `/auth/accounts/{id}/suspend` | `SuspendAccount` | Canonical | services/auth-service/internal/handlers/account_suspension_test.go:431 (`TestSuspendAndReactivateLifecycle`) | ✅ Yes |
| 27 | `auth-service` | `POST` | `/auth/accounts/suspend` | `SuspendAccount` | Companion (Alias of `/auth/accounts/{id}/suspend`) | services/auth-service/internal/handlers/account_suspension_test.go:431 (`TestSuspendAndReactivateLifecycle`) | ✅ Yes |
| 28 | `auth-service` | `POST` | `/auth/accounts/{id}/reactivate` | `ReactivateAccount` | Canonical | services/auth-service/internal/handlers/account_suspension_test.go:431 (`TestSuspendAndReactivateLifecycle`) | ✅ Yes |
| 29 | `auth-service` | `POST` | `/auth/accounts/reactivate` | `ReactivateAccount` | Companion (Alias of `/auth/accounts/{id}/reactivate`) | services/auth-service/internal/handlers/account_suspension_test.go:431 (`TestSuspendAndReactivateLifecycle`) | ✅ Yes |
| 30 | `auth-service` | `GET` | `/auth/reviewer/verify` | `VerifyReviewer` | Canonical | services/auth-service/internal/handlers/reviewer_ratelimit_test.go:94 (`TestReviewerLogin_RateLimiting_3Attempts5MinLockout`) | ✅ Yes |
| 31 | `auth-service` | `DELETE` | `/auth/device-token` | `DeviceToken` | Canonical | services/auth-service/internal/handlers/auth_test.go:3314 (`TestDeviceToken_RegistrationAndUpsert`) | ✅ Yes |
| 32 | `auth-service` | `POST` | `/auth/email-change/request` | `RequestEmailChange` | Canonical | services/auth-service/internal/handlers/email_change_test.go:99 (`TestEmailChange_FullLifecycleAndSecurity`) | ✅ Yes |
| 33 | `auth-service` | `POST` | `/auth/email-change/confirm` | `ConfirmEmailChange` | Canonical | services/auth-service/internal/handlers/email_change_test.go:152 (`TestEmailChange_FullLifecycleAndSecurity`) | ✅ Yes |
| 34 | `auth-service` | `POST` | `/auth/logout` | `Logout` | Canonical | services/auth-service/internal/handlers/auth_test.go:1147 (`TestLogout_Denylist`) | ✅ Yes |
| 35 | `chat-service` | `GET` | `/chat/ws` | `HandleWebSocket` | Canonical | services/chat-service/internal/handlers/chat_test.go:791 (`TestChatWebSocketCommunication`) | ✅ Yes |
| 36 | `chat-service` | `GET` | `/chat/history` | `GetHistory` | Canonical | services/chat-service/internal/handlers/chat_test.go:282 (`TestGetHistoryAccessControl`) | ✅ Yes |
| 37 | `chat-service` | `POST` | `/chat/internal/broadcast-location` | `BroadcastLocation` | Canonical | services/chat-service/internal/handlers/chat_test.go:701 (`TestBroadcastLocation`) | ✅ Yes |
| 38 | `chat-service` | `POST` | `/chat/tickets` | `HandleCreateTicket` | Canonical | services/chat-service/internal/handlers/chat_test.go:746 (`TestHandleCreateTicket`) | ✅ Yes |
| 39 | `chat-service` | `GET` | `/chat/tickets/mine` | `GetCustomerTickets` | Canonical | services/chat-service/internal/handlers/chat_test.go:1829 (`TestGetCustomerTickets_IsolationAndPagination`) | ✅ Yes |
| 40 | `chat-service` | `GET` | `/tickets/mine` | `GetCustomerTickets` | Companion (Alias of `/chat/tickets/mine`) | services/chat-service/internal/handlers/chat_test.go:1829 (`TestGetCustomerTickets_IsolationAndPagination`) | ✅ Yes |
| 41 | `chat-service` | `POST` | `/chat/tickets/resolve` | `HandleResolveTicket` | Canonical | services/chat-service/internal/handlers/chat_test.go:1282 (`TestHandleResolveTicket`) | ✅ Yes |
| 42 | `chat-service` | `GET` | `/chat/admin/tickets` | `AdminListTickets` | Companion (Alias of `/admin/tickets`) | services/chat-service/internal/handlers/admin_tickets_test.go:102 (`TestAdminTickets_Authentication`) | ✅ Yes |
| 43 | `chat-service` | `GET` | `/admin/tickets` | `AdminListTickets` | Canonical | services/chat-service/internal/handlers/admin_tickets_test.go:102 (`TestAdminTickets_Authentication`) | ✅ Yes |
| 44 | `chat-service` | `POST` | `/chat/admin/tickets/resolve` | `AdminResolveTicket` | Companion (Alias of `/admin/tickets/resolve`) | services/chat-service/internal/handlers/admin_tickets_test.go:252 (`TestAdminTickets_ResolutionLifecycleAndValidation`) | ✅ Yes |
| 45 | `chat-service` | `POST` | `/admin/tickets/resolve` | `AdminResolveTicket` | Canonical | services/chat-service/internal/handlers/admin_tickets_test.go:252 (`TestAdminTickets_ResolutionLifecycleAndValidation`) | ✅ Yes |
| 46 | `notification-service` | `GET` | `/notifications/stream` | `Stream` | Canonical | services/notification-service/internal/handlers/handlers_test.go:204 (`TestStreamAndVerifyAndResolve`) | ✅ Yes |
| 47 | `notification-service` | `POST` | `/notifications/send` | `Send` | Canonical | services/notification-service/internal/handlers/dispatch_notification_isolation_test.go:80 (`TestRepro_N01_SSEHubIgnoresUserID_BroadcastsPrivateOfferToAllEmployees`) | ✅ Yes |
| 48 | `notification-service` | `POST` | `/notifications/broadcast/job-alert` | `BroadcastJobAlert` | Canonical | services/notification-service/internal/handlers/handlers_test.go:136 (`TestNotificationHandlersAuth`) | ✅ Yes |
| 49 | `notification-service` | `GET` | `/notifications/history` | `History` | Canonical | services/notification-service/internal/handlers/history_handlers_test.go:762 (`TestHandler_BroadcastReadDismissIsPerRecipient`) | ✅ Yes |
| 50 | `notification-service` | `POST` | `/notifications/read-all` | `ReadAll` | Companion (Alias of `/notifications/{id}/read`) | services/notification-service/internal/handlers/history_handlers_test.go:457 (`TestReadAllEndpoint`) | ✅ Yes |
| 51 | `notification-service` | `POST` | `/notifications/{id}/read` | `MarkRead` | Canonical | services/notification-service/internal/handlers/history_handlers_test.go:412 (`TestMarkReadEndpoint`) | ✅ Yes |
| 52 | `notification-service` | `DELETE` | `/notifications/{id}` | `Delete` | Canonical | services/notification-service/internal/handlers/history_handlers_test.go:497 (`TestDeleteEndpoints`) | ✅ Yes |
| 53 | `notification-service` | `DELETE` | `/notifications` | `DeleteAll` | Companion (Alias of `/notifications/{id}`) | services/notification-service/internal/handlers/history_handlers_test.go:497 (`TestDeleteEndpoints`) | ✅ Yes |
| 54 | `user-service` | `GET` | `/users/services` | `ListServices` | Canonical | services/user-service/internal/handlers/handlers_test.go:995 (`TestUserServiceHandlers`) | ✅ Yes |
| 55 | `user-service` | `POST` | `/users/services` | `CreateService` | Canonical | services/user-service/internal/handlers/handlers_test.go:950 (`TestUserServiceHandlers`) | ✅ Yes |
| 56 | `user-service` | `PUT` | `/users/services` | `UpdateService` | Canonical | services/user-service/internal/handlers/money_state_repro_test.go:284 (`TestRepro_Q10_UpdateService_ConcurrentFieldLevelClobber`) | ✅ Yes |
| 57 | `user-service` | `PATCH` | `/users/services` | `UpdateService` | Canonical | services/user-service/internal/handlers/money_state_repro_test.go:284 (`TestRepro_Q10_UpdateService_ConcurrentFieldLevelClobber`) | ✅ Yes |
| 58 | `user-service` | `POST` | `/users/services/update` | `UpdateService` | Companion (Alias of `/users/services`) | services/user-service/internal/handlers/money_state_repro_test.go:284 (`TestRepro_Q10_UpdateService_ConcurrentFieldLevelClobber`) | ✅ Yes |
| 59 | `user-service` | `PUT` | `/users/services/update` | `UpdateService` | Companion (Alias of `/users/services`) | services/user-service/internal/handlers/money_state_repro_test.go:284 (`TestRepro_Q10_UpdateService_ConcurrentFieldLevelClobber`) | ✅ Yes |
| 60 | `user-service` | `PATCH` | `/users/services/update` | `UpdateService` | Companion (Alias of `/users/services`) | services/user-service/internal/handlers/money_state_repro_test.go:284 (`TestRepro_Q10_UpdateService_ConcurrentFieldLevelClobber`) | ✅ Yes |
| 61 | `user-service` | `POST` | `/users/jobs/track` | `TrackJob` | Canonical | services/user-service/internal/handlers/handlers_test.go:230 (`TestUserServiceHandlers`) | ✅ Yes |
| 62 | `user-service` | `GET` | `/users/jobs/get` | `GetJob` | Canonical | services/user-service/internal/handlers/handlers_test.go:120 (`TestUserServiceHandlers`) | ✅ Yes |
| 63 | `user-service` | `GET` | `/users/jobs/owner` | `GetOwnerJobs` | Canonical | services/user-service/internal/handlers/handlers_test.go:3100 (`TestUserServiceHandlers`) | ✅ Yes |
| 64 | `user-service` | `GET` | `/users/jobs/mine` | `GetCustomerJobs` | Canonical | services/user-service/internal/handlers/handlers_test.go:3152 (`TestUserServiceHandlers`) | ✅ Yes |
| 65 | `user-service` | `POST` | `/users/jobs/complete` | `CompleteJob` | Canonical | services/user-service/internal/handlers/handlers_test.go:710 (`TestUserServiceHandlers`) | ✅ Yes |
| 66 | `user-service` | `POST` | `/users/jobs/cancel` | `CancelJob` | Canonical | services/user-service/internal/handlers/handlers_test.go:410 (`TestUserServiceHandlers`) | ✅ Yes |
| 67 | `user-service` | `POST` | `/users/jobs/propose-price` | `ProposePrice` | Canonical | services/user-service/internal/handlers/auth_identity_repro_test.go:42 (`TestRepro_Q26_AuthBeforeDBLookup`) | ✅ Yes |
| 68 | `user-service` | `POST` | `/users/jobs/respond-price` | `RespondPrice` | Canonical | services/user-service/internal/handlers/adr0006_e2e_integration_test.go:212 (`TestADR0006_E2E_NegotiableTransportPricing`) | ✅ Yes |
| 69 | `user-service` | `POST` | `/users/employee/jobs/{id}/accept` | `AcceptJobOffer` | Canonical | services/user-service/internal/handlers/cascade_dispatch_repro_test.go:278 (`TestCascade_SequentialOffers_DeclineAdvancesAndPricingAtAccept`) | ✅ Yes |
| 70 | `user-service` | `POST` | `/users/employee/jobs/{id}/decline` | `DeclineJobOffer` | Canonical | services/user-service/internal/handlers/cascade_dispatch_repro_test.go:249 (`TestCascade_SequentialOffers_DeclineAdvancesAndPricingAtAccept`) | ✅ Yes |
| 71 | `user-service` | `POST` | `/users/employee/jobs/accept` | `AcceptJobOffer` | Companion (Alias of `/users/employee/jobs/{id}/accept`) | services/user-service/internal/handlers/cascade_dispatch_repro_test.go:278 (`TestCascade_SequentialOffers_DeclineAdvancesAndPricingAtAccept`) | ✅ Yes |
| 72 | `user-service` | `POST` | `/users/employee/jobs/decline` | `DeclineJobOffer` | Companion (Alias of `/users/employee/jobs/{id}/decline`) | services/user-service/internal/handlers/cascade_dispatch_repro_test.go:249 (`TestCascade_SequentialOffers_DeclineAdvancesAndPricingAtAccept`) | ✅ Yes |
| 73 | `user-service` | `GET` | `/users/wallet` | `GetWallet` | Canonical | services/user-service/internal/handlers/admin_reconciliation_test.go:345 (`TestAdminReconciliation_ValidationAndResolutionLifecycle`) | ✅ Yes |
| 74 | `user-service` | `POST` | `/users/wallet/deposit` | `WalletDeposit` | Canonical | services/user-service/internal/handlers/extra_handlers_test.go:210 (`TestWalletDeposit_ExtraEdgeCases`) | ✅ Yes |
| 75 | `user-service` | `POST` | `/users/wallet/payout/request` | `RequestPayout` | Canonical | services/user-service/internal/handlers/fund_endpoint_rate_limit_test.go:120 (`TestRequestPayout_RateLimiting`) | ✅ Yes |
| 76 | `user-service` | `GET` | `/users/wallet/payout/requests` | `GetPayoutRequests` | Canonical | services/user-service/internal/handlers/fund_endpoint_rate_limit_test.go:145 (`TestGetPayoutRequests_RateLimiting`) | ✅ Yes |
| 77 | `user-service` | `GET` | `/users/ledger` | `GetLedger` | Canonical | services/user-service/internal/handlers/handlers_test.go:1033 (`TestUserServiceHandlers`) | ✅ Yes |
| 78 | `user-service` | `GET` | `/users/platform/config` | `GetPlatformConfig` | Canonical | services/user-service/internal/handlers/handlers_test.go:1060 (`TestUserServiceHandlers`) | ✅ Yes |
| 79 | `user-service` | `POST` | `/users/subscription` | `Subscription` | Canonical | services/user-service/internal/handlers/handlers_test.go:1200 (`TestUserServiceHandlers`) | ✅ Yes |
| 80 | `user-service` | `GET` | `/users/subscription/internal` | `InternalSubscriptionCheck` | Canonical | services/user-service/internal/handlers/paid_tier_gating_matrix_test.go:283 (`TestPaidTierGatingMatrix`) | ✅ Yes |
| 81 | `user-service` | `POST` | `/users/jobs/rate` | `RateJob` | Canonical | services/user-service/internal/handlers/handlers_test.go:1075 (`TestUserServiceHandlers`) | ✅ Yes |
| 82 | `user-service` | `GET` | `/users/ratings` | `GetRatings` | Canonical | services/user-service/internal/handlers/handlers_test.go:1080 (`TestUserServiceHandlers`) | ✅ Yes |
| 83 | `user-service` | `POST` | `/users/jobs/location/update` | `UpdateJobLocation` | Canonical | services/user-service/internal/handlers/handlers_test.go:610 (`TestUserServiceHandlers`) | ✅ Yes |
| 84 | `user-service` | `POST` | `/users/employee/location` | `UpdateEmployeeLocation` | Canonical | services/user-service/internal/handlers/employee_dispatch_pricing_test.go:126 (`TestUpdateEmployeeLocation_Endpoint`) | ✅ Yes |
| 85 | `user-service` | `GET` | `/users/employees/available` | `GetAvailableEmployees` | Canonical | services/user-service/internal/handlers/available_employees_test.go:15 (`TestGetAvailableEmployees`) | ✅ Yes |
| 86 | `user-service` | `GET` | `/users/jobs/reconciliation-queue` | `GetReconciliationQueue` | Canonical | services/user-service/internal/handlers/reconciliation_test.go:35 (`TestGetReconciliationQueue_Isolation`) | ✅ Yes |
| 87 | `user-service` | `POST` | `/users/jobs/reconciliation-resolve` | `ResolveReconciliation` | Canonical | services/user-service/internal/handlers/reconciliation_test.go:110 (`TestResolveReconciliation_Success`) | ✅ Yes |
| 88 | `user-service` | `GET` | `/users/admin/reconciliation/queue` | `AdminGetReconciliationQueue` | Companion (Alias of `/admin/reconciliation/queue`) | services/user-service/internal/handlers/admin_reconciliation_test.go:101 (`TestAdminReconciliation_AuthenticationAndAuthorization`) | ✅ Yes |
| 89 | `user-service` | `GET` | `/admin/reconciliation/queue` | `AdminGetReconciliationQueue` | Canonical | services/user-service/internal/handlers/admin_reconciliation_test.go:101 (`TestAdminReconciliation_AuthenticationAndAuthorization`) | ✅ Yes |
| 90 | `user-service` | `POST` | `/users/admin/reconciliation/resolve` | `AdminResolveReconciliation` | Companion (Alias of `/admin/reconciliation/resolve`) | services/user-service/internal/handlers/admin_reconciliation_test.go:310 (`TestAdminReconciliation_ValidationAndResolutionLifecycle`) | ✅ Yes |
| 91 | `user-service` | `POST` | `/admin/reconciliation/resolve` | `AdminResolveReconciliation` | Canonical | services/user-service/internal/handlers/admin_reconciliation_test.go:310 (`TestAdminReconciliation_ValidationAndResolutionLifecycle`) | ✅ Yes |
| 92 | `user-service` | `GET` | `/users/admin/subscriptions` | `AdminListSubscriptions` | Companion (Alias of `/admin/subscriptions`) | services/user-service/internal/handlers/admin_subscription_test.go:115 (`TestAdminSubscription_Authentication`) | ✅ Yes |
| 93 | `user-service` | `GET` | `/admin/subscriptions` | `AdminListSubscriptions` | Canonical | services/user-service/internal/handlers/admin_subscription_test.go:115 (`TestAdminSubscription_Authentication`) | ✅ Yes |
| 94 | `user-service` | `GET` | `/admin/subscriptions/queue` | `AdminListSubscriptions` | Companion (Alias of `/admin/subscriptions`) | services/user-service/internal/handlers/admin_subscription_test.go:115 (`TestAdminSubscription_Authentication`) | ✅ Yes |
| 95 | `user-service` | `POST` | `/users/admin/subscriptions/activate` | `AdminActivateSubscription` | Companion (Alias of `/admin/subscriptions/activate`) | services/user-service/internal/handlers/admin_subscription_test.go:272 (`TestAdminSubscription_ActivationAndRevocationLifecycle`) | ✅ Yes |
| 96 | `user-service` | `POST` | `/admin/subscriptions/activate` | `AdminActivateSubscription` | Canonical | services/user-service/internal/handlers/admin_subscription_test.go:272 (`TestAdminSubscription_ActivationAndRevocationLifecycle`) | ✅ Yes |
| 97 | `user-service` | `POST` | `/users/admin/subscriptions/revoke` | `AdminRevokeSubscription` | Companion (Alias of `/admin/subscriptions/revoke`) | services/user-service/internal/handlers/admin_subscription_test.go:325 (`TestAdminSubscription_ActivationAndRevocationLifecycle`) | ✅ Yes |
| 98 | `user-service` | `POST` | `/admin/subscriptions/revoke` | `AdminRevokeSubscription` | Canonical | services/user-service/internal/handlers/admin_subscription_test.go:325 (`TestAdminSubscription_ActivationAndRevocationLifecycle`) | ✅ Yes |

#### Baseline Endpoint Findings
1. **Uncovered Endpoints**:
   - `GET /api/v1/admin/version-config` (`api-gateway`)
   - `PUT /api/v1/admin/version-config` (`api-gateway`)
   - *Reason*: The handlers are registered inline inside `services/api-gateway/cmd/main.go:94`. While the underlying datastore (`VersionStore`) had unit tests in `services/api-gateway/internal/version/version_test.go` and the client enforcement middleware was tested in `version_gate_test.go`, the HTTP endpoints themselves had no route/handler tests.
2. **Orphan / Deprecated Route**:
   - `POST /chat/tickets/resolve` (`chat-service`)
   - *Finding*: Covered by `services/chat-service/internal/handlers/chat_test.go:1282`, but unconsumed by any client per GAP-03 / ADR-0013 (superseded by Ops Console `/admin/tickets/resolve`).

---

### Category 2: Pre-Existing Authentication Coverage

Before this QA initiative, authentication possessed extensive unit and regression test coverage across token management, session invalidation, OTP cryptography, and account security:

* **JWT Creation, Claims & Verification**:
  - `shared/infra/jwtutil/jwt_test.go`: Validates token creation, claims extraction, HMAC signature verification, expiration enforcement, and key-confusion defense (`TestGenerateToken`, `TestValidateToken`, `TestExpiredToken`).
* **Session Lifecycle, Revocation & Denylists**:
  - `services/auth-service/internal/handlers/auth_test.go:1147` (`TestLogout_Denylist`): Verifies token JTI is written to the Redis denylist upon logout and subsequent calls with the revoked token are rejected.
  - `services/auth-service/internal/handlers/auth_test.go:508` (`TestAuthHandlers` / `Refresh`): Validates token refresh mechanics and session continuation.
  - `services/auth-service/internal/handlers/auth_test.go:3481` (`TestLogin_ConfirmedUser_CanLoginAfterJWTExpires`): Verifies re-authentication after session timeout.
* **Password Reset & Anti-Enumeration Protections**:
  - `services/auth-service/internal/handlers/auth_test.go:2862` (`TestForgotPassword_AntiEnumeration`): Verifies identical HTTP 200 responses and constant-time execution whether an email exists or does not exist.
  - `services/auth-service/internal/handlers/auth_test.go:2926` (`TestForgotPassword_RateLimiting`): Enforces IP and email rate limits on password reset requests.
  - `services/auth-service/internal/handlers/auth_test.go:2953` (`TestResetPassword_Success`): Verifies OTP validation, bcrypt password rehashing, and OTP invalidation.
  - `services/auth-service/internal/handlers/auth_test.go:3088` (`TestResetPassword_OTPReusePrevention`): Enforces single-use semantics on reset OTPs.
  - `services/auth-service/internal/handlers/auth_test.go:3129` (`TestResetPassword_SessionInvalidation`): Confirms password change purges existing active user sessions.
* **OTP Generation, Cryptography & Concurrency Defenses**:
  - `services/auth-service/internal/otpcrypto/crypto_test.go`: Tests AES-GCM envelope encryption and decryption for OTPs at rest (`TestCipher_EncryptDecrypt`).
  - `services/auth-service/internal/store/otp_consume_race_regression_test.go:31` (`TestVerifyOTP_ConcurrentSubmitConsumesExactlyOnce`): Concurrent submission test validating atomic CAS consumption of signup OTPs.
  - `services/auth-service/internal/otp/dispatcher_test.go` & `resend_dispatcher_test.go`: Tests SMS/email dispatchers and Resend API error resilience.
* **Account Suspension & Token Invalidation**:
  - `services/auth-service/internal/handlers/account_suspension_test.go:431` (`TestSuspendAndReactivateLifecycle`): Validates account suspension, audit logging, and immediate Redis session revocation.
  - `services/auth-service/internal/handlers/account_suspension_test.go:687` (`TestAccountSuspension_OwnerSuspensionRevokesEmployeeTokens_F04`): Verifies suspending a tenant owner immediately revokes all affiliated employee sessions.
* **Reviewer & Support Agent Token Protection**:
  - `services/auth-service/internal/store/reviewer_token_hash_regression_test.go:20` (`TestReviewerTokenHashedAtRest`): Verifies reviewer tokens are stored as SHA-256 digests.
  - `services/chat-service/internal/store/agent_token_hash_regression_test.go:20` (`TestSupportAgentTokenHashedAtRest`): Verifies support agent tokens are stored as SHA-256 digests.
  - `services/auth-service/internal/handlers/reviewer_ratelimit_test.go:28` (`TestReviewerLogin_RateLimiting_3Attempts5MinLockout`): Enforces strict 3-attempt brute-force lockout on reviewer authentication.
* **Email Change Security**:
  - `services/auth-service/internal/handlers/email_change_test.go:25` (`TestEmailChange_FullLifecycleAndSecurity`): Two-step verification requiring re-authentication and OTP delivery to the new address.

---

### Category 3: Role-Based Access Control (RBAC) Baseline Finding

> [!IMPORTANT]
> **Pre-Initiative Finding: RBAC Had Zero Systematic Regression Protection**
> Prior to `TestAuthMatrix` (added in Phase 2b), there was **no centralized RBAC matrix or systematic role test suite** anywhere in the codebase.
> 
> Pre-existing role checks existed solely as isolated, ad-hoc assertions inside specific handler tests (e.g. asserting that a customer token returned 403 when hitting `POST /users/services`). No test systematically passed all platform roles (Anonymous, Customer, Driver, Owner, Reviewer) across endpoints to verify access controls and boundary isolation. This meant role permission regressions could easily slip through unnoticed until the unified Auth/RBAC matrix was created.

---

### Category 4: WebSocket Flows & The Edge Proxy Upgrade Blindspot

Before the QA strategy initiative, WebSocket communication had unit-level test coverage in `chat-service`:
* `services/chat-service/internal/handlers/chat_test.go:791` (`TestChatWebSocketCommunication`): Validated WebSocket connection, channel subscription (`job:<id>`), and bidirectional message dispatch.
* `services/chat-service/internal/chat/hub_test.go:14` (`TestHubConcurrencyStress`): High-concurrency client subscription and broadcast test.
* `services/chat-service/internal/chat/hub_test.go:90` (`TestHub_MultiInstanceRedisPubSubDelivery`): Multi-hub Redis pub/sub message synchronization.
* `services/chat-service/internal/chat/hub_concurrency_repro_test.go:13` (`TestClient_CloseSend_Idempotent` & `TestHub_RedisPubSub_SubscribeUnsubscribe_Serialized`): Q16/Q17 race condition tests preventing closed-channel panics.

#### Why the HTTP 101 Switching Protocols Bug Survived
All pre-existing WebSocket tests used `httptest.NewServer(mux)` connecting directly to the in-memory Go HTTP server. **None of the pre-existing tests routed WebSocket connections through an edge reverse proxy (Caddy) or through the API Gateway's resilience transport.**

When real traffic traverses the architecture:
```
Client -> Caddy (:8088) -> API Gateway (:8080) -> chat-service (:3001)
```
The API Gateway's resilience round-tripper wrapped all upstream responses in a custom `cancelReadCloser` struct to support request cancellations. However, for `101 Switching Protocols` (WebSocket upgrades), `httputil.ReverseProxy` requires the response body to implement `io.ReadWriteCloser` (the hijacked TCP connection). Wrapping it in `cancelReadCloser` stripped the `Write` interface, causing the gateway reverse proxy to abort the connection with a 502 Bad Gateway / bad handshake error.

Because all pre-existing tests bypassed the edge proxy, this severe architectural defect remained undetected until live staging E2E tests were executed in Phase 0.

---

### Category 5: Critical Business Flows (Unit & Integration Baseline)

Pre-existing test coverage across the 8 core business flows was concentrated at the unit/handler and mock-integration level:

1. **Authentication**:
   - Covered via `services/auth-service/internal/handlers/auth_test.go` and `account_suspension_test.go` (Signup, Login, OTP, 2FA, Revocation, Suspension).
2. **Orders (Booking & Pricing Negotiation)**:
   - Covered via `services/user-service/internal/handlers/adr0006_e2e_integration_test.go:129` (Negotiable transport pricing, proposal, counter-offer, acceptance) and `negotiation_concurrency_test.go:15`.
3. **Delivery Lifecycle (Escrow & Settlement)**:
   - Covered via `services/user-service/internal/handlers/adr0007_e2e_integration_test.go:212` (GPS reconciliation, completion, fee settlement) and `escrow_state_audit_test.go:20` (atomic escrow locking and release).
4. **Driver Workflow (Availability & Cascade Dispatch)**:
   - Covered via `services/user-service/internal/handlers/cascade_dispatch_repro_test.go:249` (Sequential dispatch offers, decline advances cascade, pricing lock at accept) and `available_employees_test.go:15`.
5. **Owner Workflow (Services, Subscriptions & Payouts)**:
   - Covered via `services/user-service/internal/handlers/service_owner_config_test.go:15` (Service creation/update), `paid_tier_gating_matrix_test.go:15` (paid-tier gating), and `fund_endpoint_rate_limit_test.go:120` (payout requests).
6. **Chat (Messaging & Tickets)**:
   - Covered via `services/chat-service/internal/handlers/chat_test.go:746` (Ticket creation), `admin_tickets_test.go:102` (Reviewer ticket listing/resolution), and `chat_test.go:282` (channel access control).
7. **Notifications (SSE Streams & History)**:
   - Covered via `services/notification-service/internal/handlers/handlers_test.go:204` (Stream connection, BroadcastJobAlert), `dispatch_notification_isolation_test.go:80` (Offer isolation), and `history_handlers_test.go:295` (Notification history & read receipts).
8. **Rating (Double-Blind Ratings)**:
   - Covered via `services/user-service/internal/handlers/extra_handlers_test.go:293` (Star bounds [1,5], completion prerequisite, self-rating rejection) and `ratings_target_guard_regression_test.go:15`.

**Baseline Limitation**: While each business area had unit tests, none verified the cross-service data consistency across the network (e.g. customer booking in `user-service` triggering real-time SSE dispatch in `notification-service` and channel authorization in `chat-service`).

---

### Category 6: Existing Security Checks & Code Review History

The repository has an extensive prior security pedigree stemming from the Independent Code Review Report and its remediation:

* **Static Security Scanning in CI (`.github/workflows/ci.yml`)**:
  - **`gosec`**: Runs AST-based security analysis (`github.com/securego/gosec/v2`) across all services, checking for hardcoded credentials, SQL/NoSQL injections, unhandled errors, file traversal, and unsafe permissions. Suppressions are explicitly documented with `#nosec` rationale.
  - **`govulncheck`**: Runs the official Go vulnerability scanner (`golang/govulncheck-action@v1`) against all service dependency trees to flag public CVEs.
* **Integrity Gates in CI**:
  - **Commit SHA Verifier**: Verifies that every 40-character commit SHA referenced in Markdown files actually exists in git and is reachable from the branch history, preventing phantom documentation drift.
  - **Go Version Consistency (Drift Guard)**: Strictly enforces identical Go language (`1.26`), patch (`1.26.6`), and toolchain versions across `go.work`, all service `go.mod` files, `ci.yml`, and Dockerfiles.
* **Independent Code Review Repro Test Suites (Q1 through Q27)**:
  - The codebase contains dedicated regression test suites verifying fixes for 27 security and concurrency audit findings, including:
    - `audit_token_repro_test.go` (Q11, Q12: device token upsert concurrency & crypto audit IDs)
    - `ticket_agent_repro_test.go` (Q13, Q14: CAS agent assignment & resolution idempotency)
    - `resolve_ticket_repro_test.go` (Q13: HTTP 409 on duplicate ticket resolution)
    - `version_test.go` (Q15: atomic monotonic config revisions)
    - `hub_concurrency_repro_test.go` (Q16, Q17: Redis pub/sub serialization & idempotent client close)
    - `auth_identity_repro_test.go` (Q8, Q25, Q26: auth check before database lookup)
    - `auth_input_validation_repro_test.go` (Q20: username length & address bounds)

---

### Category 7: Existing Docker & Infrastructure Validation

Prior to Phase 0 of this QA initiative, CI/CD infrastructure validation had severe gaps:

* **CI Runner Environment (`ci.yml`)**:
  - CI ran tests against isolated GitHub Actions service containers (`mongo:7`, `redis:7-alpine`) over unauthenticated localhost ports.
  - **No Docker Compose execution in CI**: `docker compose up` was never invoked during pull request or branch validation.
  - **No inter-service networking or mTLS**: Services were tested in isolation; inter-service calls were stubbed or executed over plaintext HTTP.
  - **No Edge Proxy**: Caddy was not part of the CI test pipeline.
* **Publish Pipeline (`build-and-publish.yml`)**:
  - Built Docker images targeting production (`target: prod`) and pushed to GitHub Container Registry (GHCR).
  - Executed a syntax check (`docker compose config --quiet`) using dummy environment variables on the deployment repository (`saas-core-deploy`).
  - **No runtime boot test**: Images were never started, container healthchecks were never exercised, and port bindings were never verified prior to deployment.

This lack of staging-parity infrastructure is what necessitated Phase 0.

---

## 4. Section B: New Coverage Added by QA Strategy Initiative (Net-New)

The following coverage was introduced net-new during Phase 0 and Phase 2 of this initiative. None of these tests existed prior to commit `370893d`.

### Staging Parity & Automated CI Release Gate (Phase 0)

* **Dedicated Staging Topology** (`infrastructure/staging/docker-compose.staging.yml`):
  - Containerized production-identical architecture utilizing `target: prod` Docker builds.
  - Dedicated isolated datastores (`staging-saas-mongo:27018` with `staging_*` databases, `staging-saas-redis:6381`).
  - Strict mutual TLS (mTLS) enforced across all internal service communications.
  - Caddy edge reverse proxy exposing port `8088` (API Gateway) and port `8091` (KYC Reviewer Console).
  - Automated provisioning and teardown scripts (`scripts/staging_up.sh`, `scripts/staging_down.sh`).
* **Automated CI Release Gate** (`.github/workflows/release-gate-e2e.yml`):
  - Automatically boots the staging environment, validates container health probes, runs the end-to-end test suite (`tests/e2e`), and tears down the stack on pushes to `main`.

### Net-New Critical User Journeys (CUJ-A through CUJ-H)

#### CUJ-A: Cascade Dispatch, Offer Isolation, Pricing Lock & Live GPS Tracking
* **Test Implementation**: `tests/e2e/cuj_a_test.go` (`TestCUJ_A_CascadeOfferAcceptAndLiveTracking`)
* **Infrastructure Path**: Client -> Caddy (`:8088`) -> API Gateway (`:8080`) -> `user-service` / `chat-service` / `notification-service` -> MongoDB & Redis.
* **Verified Invariants**:
  1. Customer booking creates job in `pending_dispatch` and offers strictly to nearest courier based on spatial distance.
  2. Job distance and escrow amount remain deferred/zero until courier acceptance.
  3. **Notification Isolation (N-01 & N-02)**: Only offered courier receives live SSE alert; un-offered couriers receive 0 events and history query reveals 0 leaked job details.
  4. Pricing calculated from courier's actual acceptance coordinates and locked atomically in tenant wallet.
  5. Courier app navigation queries do not disrupt active tracking (F-01).
  6. Live WebSocket coordinates stream through Caddy and API Gateway to customer subscribers within 3-second throttle.

#### CUJ-B: KYC Reviewer Console, Mandatory Reason & Live Proxy SSE Delivery
* **Test Implementation**: `tests/e2e/cuj_b_test.go` (`TestCUJ_B_KYCSubmissionReviewAndSSEOutcomeDelivery`)
* **Infrastructure Path**: Client / Reviewer -> Caddy (`:8088` & `:8091`) -> API Gateway & KYC Reviewer Console -> `auth-service` & `notification-service`.
* **Verified Invariants**:
  1. Pending KYC submissions appear immediately in Reviewer Console queue (`GET /api/queue`).
  2. Mandatory rejection reason strictly enforced (empty and whitespace-only reasons rejected with HTTP 400 per ADR-0021).
  3. Real-time SSE delivery across Caddy and API Gateway without reverse-proxy buffering delay or dropped events.
  4. WebSocket protocol upgrade integrity preserved across resilience transport.

#### CUJ-C: Customer Registration, Password Validation, Duplicate Defense & 2FA Flow
* **Test Implementation**: `tests/e2e/cuj_c_test.go` (`TestCUJ_C_CustomerRegistration`)
* **Infrastructure Path**: Client -> Caddy (`:8088`) -> API Gateway (`:8080`) -> `auth-service` (`:3002`) -> MongoDB (`auth_db`).
* **Verified Invariants**:
  1. Weak passwords (< 6 chars) and malformed emails rejected with HTTP 400.
  2. Registration emits OTP; invalid/expired OTP fails with HTTP 401; valid OTP activates account.
  3. Re-registering existing confirmed email blocked with HTTP 409 Conflict.
  4. 2FA challenge workflow issues session JWT; authenticated profile query succeeds through API Gateway.

#### CUJ-D: Driver Workflow Full Cycle, IDOR Defense & Escrow Settlement
* **Test Implementation**: `tests/e2e/cuj_d_test.go` (`TestCUJ_D_DriverWorkflowFullCycle`)
* **Infrastructure Path**: Customer/Courier -> Caddy (`:8088`) -> API Gateway (`:8080`) -> `user-service` (`:3003`) -> MongoDB (`users_db`).
* **Verified Invariants**:
  1. Booking creation and courier acceptance via mobile endpoints.
  2. Courier updates GPS coordinates with speed validation.
  3. Unauthorized courier attempting completion or details query blocked with HTTP 403 Forbidden.
  4. Courier completion releases locked escrow to tenant wallet with zero balance leakage.

#### CUJ-E: Owner Workflow, Paid-Tier Gating, Service Management & IDOR Defense
* **Test Implementation**: `tests/e2e/cuj_e_test.go` (`TestCUJ_E_OwnerWorkflow`)
* **Infrastructure Path**: Tenant Owner -> Caddy (`:8088`) -> API Gateway (`:8080`) -> `user-service` (`:3003`) -> MongoDB (`users_db`).
* **Verified Invariants**:
  1. Owner dashboard telemetry aggregates wallet, ledger, jobs, and employee roster.
  2. Free-tier owner rejected with HTTP 402 Payment Required; subscribed paid-tier owner creates and updates services.
  3. Paid-tier owner accesses tenant dispute reconciliation queue.
  4. Cross-tenant mutation and reconciliation queue reads blocked with HTTP 402/403.

#### CUJ-F: Active Job Real-Time Chat, WebSocket Ordering & Cross-Tenant IDOR Isolation
* **Test Implementation**: `tests/e2e/cuj_f_test.go` (`TestCUJ_F_Chat`)
* **Infrastructure Path**: Customer/Courier -> Caddy (`:8088`) -> API Gateway (`:8080`) -> `chat-service` (`:3001`) -> MongoDB (`chat_db`) & Redis.
* **Verified Invariants**:
  1. Customer and assigned courier connect via WebSocket upgrade and subscribe to `job:<id>`.
  2. Real-time message delivery between customer and assigned courier.
  3. History query verifies MongoDB persistence and chronological ordering.
  4. Unassigned courier blocked from history and live channel subscription with HTTP 403.

#### CUJ-G: Double-Blind Rating, Validations & Aggregate Metrics
* **Test Implementation**: `tests/e2e/cuj_g_test.go` (`TestCUJ_G_Rating`)
* **Infrastructure Path**: Customer/Owner -> Caddy (`:8088`) -> API Gateway (`:8080`) -> `user-service` (`:3003`) -> MongoDB (`users_db`).
* **Verified Invariants**:
  1. Rating uncompleted job rejected with HTTP 400.
  2. Out-of-bounds star ratings (< 1 or > 5) rejected with HTTP 400.
  3. Non-party rating attempt blocked with HTTP 403.
  4. Duplicate rating submission blocked with HTTP 409 Conflict.
  5. Aggregate rating score and count correctly recalculated.

#### CUJ-H: Support Ticket Resolution & Dual-Delivery Regression Guard
* **Test Implementation**: `tests/e2e/cuj_h_test.go` (`TestCUJ_H_SupportTicketResolution`)
* **Infrastructure Path**: Customer/Reviewer -> Caddy (`:8088` & `:8091`) -> API Gateway & Ops Console -> `chat-service` & `notification-service`.
* **Verified Invariants**:
  1. Customer creates complaint ticket in state `pending`.
  2. Customer connects to SSE stream and subscribes to WebSocket channel `ticket:<id>`.
  3. Reviewer resolution without note rejected with HTTP 400; non-reviewer resolution rejected with HTTP 401.
  4. **Dual-Delivery Verification**: Customer receives real-time SSE notification `ticket_resolved` AND WebSocket system resolution event inside `ticket:<id>`.

---

### Net-New Auth & RBAC Security Matrix (Phase 2b)

* **Test Implementation**: `tests/e2e/auth_matrix_test.go` (`TestAuthMatrix`)
* **Coverage Scope**:
  - Evaluates Anonymous, Customer, Driver, Owner, and Reviewer roles against representative customer, driver, owner, and reviewer endpoints.
  - Verifies cross-tenant IDOR boundaries for service mutations, reconciliation queues, job completions, and chat histories.

---

### Net-New Backend-Frontend Parity Guard Tooling (Phase 2c)

* **Tool Implementation**: `tools/paritycheck/main.go` (`make backend-frontend-parity-check`)
* **CI Integration**: Active in `.github/workflows/ci.yml`.
* **Inventory Classification**:
  - Total Registered Backend Endpoints: **98** (82 canonical + 16 companion aliases)
  - Mobile App Routes (Flutter): **64**
  - Ops Console Routes (KYC/KYE): **23**
  - Internal Service-to-Service: **7**
  - Infra / Health Probes: **3**
  - Unconsumed / Orphan Routes: **1** (`POST /chat/tickets/resolve`)

---

### Net-New Inter-Service API Contract Testing Suite (Phase 4 / QA-GAP-02)

* **Test Implementation**: `tests/contracts/*_contract_test.go` (`make contract-test`)
* **Execution Characteristics**: In-process execution in pure Go (~45ms) without Docker Compose dependencies; actively enforced in `.githooks/pre-push` and CI.
* **Architecture & Methodology (Schema-Based vs Pact Justification)**:
  - **Decision**: Implemented native Go schema-based contract testing combining **AST Source-Code Reflection Guards** and **Behavioral Round-Trip Serialization Validators** (`encoding/json` with `DisallowUnknownFields`).
  - **Rationale**: The unified Go workspace (`go.work`) microservice topology benefits from direct AST inspection of provider handler structs and consumer payloads on disk, catching field renames and tag mutations at compile/test time with zero external broker or daemon dependencies (`libpact_ffi`), ensuring 100% deterministic, millisecond CI execution.
* **Master Inter-Service Boundary Coverage**:
  1. **`chat -> auth`** (`tests/contracts/chat_auth_contract_test.go`):
     - `GET /auth/user?id={id}`: Validates consumer WebSocket auth cache (`id`, `username`) and fleet channel authorization (`id`, `role`).
     - `GET /auth/reviewer/verify`: Validates reviewer credential exchange (`ReviewerClaims` containing `id`, `name`).
  2. **`chat -> user`** (`tests/contracts/chat_user_contract_test.go`):
     - `GET /users/jobs/get?id={id}`: Validates job participant and offered-courier channel authorization against provider's `models.Job` payload (`owner_id`, `employee_id`, `user_id`, `status`, `current_offered_employee_id`).
  3. **`notif -> auth`** (`tests/contracts/notif_auth_contract_test.go`):
     - `GET /auth/user?id={id}`: Audits device token resolution for FCM push notification delivery.
     - `POST /auth/device-token`: Validates stale device token unregistration (`models.DeviceTokenRequest` with `token` and `action`).
  4. **`user -> chat`** (`tests/contracts/user_chat_contract_test.go`):
     - `POST /chat/internal/broadcast-location`: Validates driver GPS location updates (`channel`, `latitude`, `longitude`, `employee_id`) across `UpdateJobLocation` and `UpdateEmployeeLocation`.
  5. **`user -> notif`** (`tests/contracts/user_notif_contract_test.go`):
     - `POST /notifications/send`: Validates direct job offer notifications (`type`, `tenant_id`, `user_id`, `title`, `body`, `roles`).
     - `POST /notifications/broadcast/job-alert`: Validates tenant job alert broadcasts (`tenant_id`, `job_id`, `employee_id`, `service_name`, `description`).
  6. **`auth -> user`** (`tests/contracts/auth_user_contract_test.go`):
     - `GET /users/subscription/internal?tenant_id={id}`: Validates paid-tier subscription status gating during employee management (HTTP 200 OK vs HTTP 402 Payment Required).
  7. **`user -> auth`** (`tests/contracts/user_auth_contract_test.go`):
     - `GET /auth/user?id={id}`: Validates KYC verification (`role`, `kyc_status`) and employee roster checks (`role`, `tenant_id`, `is_active`, `account_status`).
  8. **`chat -> notif`** (`tests/contracts/chat_notif_contract_test.go`):
     - `POST /notifications/send`: Validates support ticket resolution alert (`ticket_resolved`) and verifies that `global: true` allows valid `tenant_id` omission.

* **Drift Detection Evidence (Fail-Then-Pass Verification)**:
  - **Boundary 1 (`user -> chat`)**: Mutated `BroadcastLocation` request struct tag in `services/chat-service/internal/handlers/chat.go` from `employee_id` to `courier_id`. Contract test immediately failed with:
    `user_chat_contract_test.go:34: Contract drift: BroadcastLocation.EmployeeID JSON tag is "courier_id", expected "employee_id"`
    Reverting the mutation restored `PASS` (`0.011s`).
  - **Boundary 2 (`chat -> user`)**: Mutated `models.Job` struct tag in `services/user-service/internal/models/models.go` from `employee_id,omitempty` to `driver_id,omitempty`. Contract test immediately failed with:
    `chat_user_contract_test.go:34: Contract drift: models.Job.EmployeeID JSON tag is "driver_id", expected "employee_id"`
    Reverting the mutation restored `PASS` (`0.004s`).

* **Real Undetected Schema Drift Discovered & Resolved**:
  - **Boundary**: `notif -> auth` (`GET /auth/user?id={id}`)
  - **Defect**: In `services/notification-service/internal/hub/fetcher.go:51-55` (`GetUserDeviceTokens`), consumer decodes `user.DeviceTokens []struct { Token string "token" } json:"device_tokens"`. However, in `services/auth-service/internal/handlers/auth.go:1050-1071` (`GetUser`), the response map explicitly constructed profile fields but omitted `device_tokens`, despite `models.User.DeviceTokens` existing in `auth-service`. In production/staging, FCM token retrieval over HTTP silently received empty tokens (masked because staging tests relied on mock dispatchers).
  - **Resolution**: ✅ **RESOLVED**. Added `"device_tokens": deviceTokens` to `GetUser` response construction in `services/auth-service/internal/handlers/auth.go:1050` with empty-slice fallback (`[]models.DeviceToken{}`), ensuring users with registered tokens return their token array and users with none return an empty JSON array (`[]`) rather than a missing key or `null`.
  - **Contract Test & Handler Protection**: Verified with `TestGetUser_DeviceTokensResponse` in `services/auth-service/internal/handlers/auth_test.go` and enforced via `TestContract_NotifToAuth_GetUser_DeviceTokens` in `tests/contracts/notif_auth_contract_test.go`.

---

### Real Seam Bugs Discovered & Resolved by Staging Verification

Executing end-to-end tests across real microservices, Caddy edge proxy, and live datastores surfaced four genuine defects in the integration seams:

1. **Gateway WebSocket Upgrades (`shared/infra/resilience/resilience.go`)**:
   - *Defect*: Gateway resilience transport wrapped response bodies with `cancelReadCloser`, stripping `io.ReadWriteCloser` needed by `httputil.ReverseProxy` during `101 Switching Protocols`.
   - *Fix*: Bypassed wrapping on HTTP 101 status, restoring full-duplex WebSocket streaming.
2. **Notification Service Dispatch Rate Limiting (`services/notification-service/internal/handlers/handlers.go`)**:
   - *Defect*: `POST /notifications/send` rate limit was set to 5 req/min, causing inter-service 429 lockout during multi-actor fan-out.
   - *Fix*: Expanded internal rate limiter to 300 req/min.
3. **API Gateway Route Prefix Mismatch (`services/api-gateway/internal/config/config.go`)**:
   - *Defect*: Gateway mapped `/api/v1/notifications/stream` instead of prefix `/api/v1/notifications/`.
   - *Fix*: Corrected prefix to `/api/v1/notifications/`, restoring proxying for notification history, read receipts, and deletions.
4. **Auth Service Missing Password Length Validation (`services/auth-service/internal/handlers/auth.go`)**:
   - *Defect*: `Signup` handler lacked minimum password length validation.
   - *Fix*: Enforced `len(req.Password) < 6` returning HTTP 400 Bad Request.

---

## 5. QA Backlog & Future Roadmap

In accordance with product owner guidelines, uncovered items discovered during this baseline audit are recorded here as backlog items rather than expanding immediate scope:

### QA-GAP-01: API Gateway Version Config Endpoint Unit Coverage
* **Priority**: P2
* **Target Routes**: `GET /api/v1/admin/version-config`, `PUT /api/v1/admin/version-config`
* **Defect**: Handlers are registered inline in `services/api-gateway/cmd/main.go:94` without unit/handler tests.
* **Remediation**: Extract handlers into `services/api-gateway/internal/handlers` or create `cmd/main_test.go` exercising `GET` and `PUT` with valid/invalid tokens and payload validations.

### QA-GAP-02: Consumer-Driven Contract Testing (Schema-Based) — RESOLVED (Phase 4)
* **Priority**: P2 (Closed in Phase 4)
* **Status**: ✅ **RESOLVED / CLOSED**
* **Resolution**: Implemented pure Go schema-based contract testing suite in `tests/contracts/` covering 8 inter-service REST boundaries with AST reflection guards and strict JSON deserialization (`tests/contracts/*_contract_test.go`). Runs in-process in CI and pre-push hooks without Docker Compose (~45ms). Drift detection proven via fail-then-pass experiments on `user -> chat` and `chat -> user`.
* **Discovered Drift**: Uncovered real undetected schema drift on `notif -> auth` (`device_tokens` omission in `auth-service` `GetUser`), now fully resolved with handler remediation and verified in `notif_auth_contract_test.go` and `auth_test.go`.

### QA-GAP-03: Real FCM Push Notification Wakeup Verification
* **Priority**: P3
* **Scope**: `services/notification-service/internal/fcm`
* **Defect**: Staging environment uses a mock FCM dispatcher; live device token dispatch and background wakeup handling are not verified end-to-end.
* **Remediation**: Configure a dedicated staging Firebase test project and automated device simulator to verify token delivery.

### QA-GAP-04: Automated Chaos & Container Resiliency Testing
* **Priority**: P3
* **Scope**: Staging infrastructure (`scripts/staging_up.sh`)
* **Defect**: Zero automated crash/kill tests during active dispatch cascades.
* **Remediation**: Implement automated container termination tests (e.g. killing Redis or Mongo during a cascade or escrow lock) to verify graceful recovery and transaction rollback.

### QA-GAP-05: Formal Deprecation & Sunset of Orphan Route
* **Priority**: P4
* **Target Route**: `POST /chat/tickets/resolve`
* **Defect**: Unconsumed legacy support agent token endpoint superseded by Ops Console `/admin/tickets/resolve` per GAP-03 / ADR-0013.
* **Remediation**: Formally remove or place behind sunset header before next major release.

---

## 6. Living Reference Links

- **Staging Runbook & Topology**: [docs/STAGING.md](docs/STAGING.md)
- **Application Architecture Map**: [docs/APPLICATION_MAP.md](docs/APPLICATION_MAP.md)
- **Backend Capabilities & Messaging Backlog**: [docs/frontend/MESSAGING_BACKLOG.md](docs/frontend/MESSAGING_BACKLOG.md)
- **Reviewer Console Rejection Reason**: [docs/adr/ADR-0021-reviewer-rejection-reason.md](docs/adr/ADR-0021-reviewer-rejection-reason.md)
- **Modular Ops Console Expansion**: [docs/adr/0023-modular-ops-console-expansion.md](docs/adr/0023-modular-ops-console-expansion.md)
- **Reverse-Proxy SSE Buffering Resolution**: [docs/changelog/bug-fixes.md](docs/changelog/bug-fixes.md)
- **Production Deployment Standards**: [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)
