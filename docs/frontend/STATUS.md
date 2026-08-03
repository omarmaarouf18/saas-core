# Frontend Status Tracker

> [!NOTE]
> This is a lean tracker mapping the current implementation state of the Flutter frontend application. For the complete step-by-step roadmap, consult [IMPLEMENTATION.md](../../IMPLEMENTATION.md).

---

## Phase Progress (Per IMPLEMENTATION.md Sequence)

*   **Phase 1: Project Setup & Shared Auth Flow** — **[100% COMPLETE & VERIFIED]**
    *   *Auth Flow Logic*: **[VERIFIED]** contract-matching works against the live docker-compose backend for signup, 2FA OTP, direct employee login, and KYC dashboard warning banners.
    *   *Branding & Re-Theming*: **[VERIFIED]** Re-skinned the entire application layout to use the Quick Delivery brand kit (Deep Navy, Amber Gold, Light Gray, White, Poppins typography), including a programmatic dark theme (`quickDeliveryDarkTheme`) wired via system settings and anchored around brand gold (`Color(0xFFFFC107)`). Removed all hardcoded Material indigo/blue values and routed styling through `ThemeData` and `theme.dart`.
    *   *Platform Builds*:
        *   *Android*: **[VERIFIED]** successfully compiled debug APK using local Adoptium JDK 17 and Android SDK platforms-36/build-tools-34. Output location: `frontend/build/app/outputs/flutter-apk/app-debug.apk` (Size: 153,369,344 bytes).
        *   *iOS*: **[UNVERIFIED]** macOS/Xcode toolchain unavailable (build execution requires a Mac environment).
*   **Phase 2: Owner Core Functionality** — **[100% COMPLETE & VERIFIED]**
    *   *Dashboard Layout*: **[VERIFIED]** Owner dashboard metrics grid displays wallet balance (via GetWallet) and subscription status (via Subscription) with active jobs placeholder layout. Confirmed working end-to-end against live docker-compose backend using real signed owner JWT token resolve logic.
    *   *Wallet Management*: **[VERIFIED]** Balance display (total, withdrawable, escrow), reverse-chronological transaction ledger, and deposit dialog with inline error notice for production environment gating. Verified end-to-end against live backend with local/production environment check.
    *   *Employee Management*: **[VERIFIED]** Worker registration, worker freeze/activate status toggling (with owner password re-auth), and tenant audit log retrieval (using paired RAW ID + JWT token). Tested end-to-end against live backend including worker action simulation and audit trail verification.
    *   *Service Directory Configuration*: **[VERIFIED]** KYC-gated service creation form with name, category (mapped to Delivery, Ride, Shipping), base price, rate per KM, and coordinates. Tested end-to-end against the live backend user-service.
*   **Phase 3: Employee Dashboard & Audit Simulator** — **[100% COMPLETE & VERIFIED]**
    *   *Employee Job Assignment List*: **[VERIFIED]** successfully retrieves all jobs assigned to the current employee via `/users/jobs/get?requester_id=<employee_token>`. Job details card correctly renders destination coordinates, customer user ID, payment method, and status. Verified end-to-end against live local docker-compose backend.
    *   *Employee Action Simulator*: **[VERIFIED]** allows employee to log events (e.g. "Arrived at Pickup") via `/auth/employee/action`. Handles and displays custom user-friendly warnings for both "employee account frozen" and "owner KYC pending approval" blocking error conditions. Verified end-to-end against live backend.
    *   *Job Completion Wiring (POST /users/jobs/complete)*: **[VERIFIED]** Added `completeJob` method to `EmployeeJobsProvider` and "Complete Job" action button to `EmployeeJobsScreen` rendered exclusively for active jobs. Features confirmation dialog (`ConfirmActionDialog`), double-submit prevention loading state, inline error banner via `friendlyErrorMessage`, and instant status update to COMPLETED. Verified via 4 widget tests (`test/employee_jobs_screen_test.dart`).
*   **Phase 4: Customer Directory & Job Booking Flow** — **[100% COMPLETE & VERIFIED]**
    *   *Marketplace Directory*: **[VERIFIED]** List view with custom latitude/longitude coordinate query inputs, search radius, exactly 3 categories (Delivery, Ride, Shipping) using existing constant mapping, and price sorting, querying `/users/services`.
    *   *Booking Workflow (COD Only)*: **[VERIFIED]** Booking creation dialog forcing Cash on Delivery (COD) payment method with an informative beta note about deferred escrow, invoking `/users/jobs/track`. Supported by custom backend fallback allowing raw owner user ID input.
    *   *Real-Time Status Screen*: **[VERIFIED]** Step-based progress tracker (Pending -> Active -> Completed/Cancelled), job details, assigned worker info, and 5-second automatic polling + manual status refresh querying `/users/jobs/get`.
    *   *Job Cancellation Wiring (POST /users/jobs/cancel)*: **[VERIFIED]** Added `cancelJob` to `MarketplaceProvider` and `OwnerProvider`. Implemented `CancelJobDialog` with required reason field validation. Enforces role-specific rules: Owners can cancel pending/active jobs on `home_screen.dart` Dashboard; Customers can cancel pending jobs on `job_status_screen.dart`, while active jobs present "Open a Complaint Ticket" affordance. Verified via 6 widget tests (`test/job_cancellation_test.dart`).
*   **Phase 5: Real-Time Messaging Integration** — **[100% COMPLETE & VERIFIED]**
    *   *WebSocket Manager & History Sync*: **[VERIFIED]** Connects to the API Gateway proxied chat-service WebSocket endpoint (`wss://`) with the user JWT `token` parameter, subscribing to channel `job:<job_id>`. Automatically loads historical messages via REST first, merging without duplicates. Handles reconnection via exponential backoff.
    *   *Real-Time Messaging*: **[VERIFIED]** Dual-direction messaging works in real-time. Verified via Go integration tests (`TestChatWebSocketCommunication`) simulating concurrent client connections (customer & employee) communicating on a shared job channel.
    *   *Authorization Gating*: **[VERIFIED]** Attempts by unauthorized users to subscribe to channels they do not participate in are blocked by the backend server-side (`canAccessChannel` checks) and correctly surfaced in the UI as access-denied error boards.
*   **Phase 6: Server-Sent Events Notifications** — **[100% COMPLETE & VERIFIED]**
    *   *SSE Subscriber Provider*: **[VERIFIED]** Implemented `NotificationsProvider` utilizing `flutter_client_sse` to subscribe to the API Gateway proxied route (`/notifications/stream?token=<token>`). Listens to `"notification"` events, parsing them into `NotificationModel` payloads, and handles dynamic unread tracking and connection status/errors.
    *   *Notifications Screen*: **[VERIFIED]** Built a responsive layout (`NotificationsScreen`) supporting category chip filters (All, Jobs, System, Alerts), chronological group splits (Today, Yesterday, Earlier), dynamic system connectivity banners, inline dismiss/reply actions, and integrated direct deep-link tracking ("Track Shipment" to `JobStatusScreen`). Colors are strictly mapped to theme roles.
    *   *App Bar Integration*: **[VERIFIED]** Embedded a reactive bell icon and unread count badge in the AppBars of `home_screen.dart` (owner & basic dashboards), `customer_marketplace_screen.dart`, and `employee_jobs_screen.dart` to make notifications accessible for all roles.
*   **Phase 7: Ratings & Subscriptions (Final Polish)** — **[100% COMPLETE & VERIFIED]**
    *   *Subscription Screen*: **[VERIFIED]** Created `SubscriptionScreen` enabling owners to select subscription tiers. Integrates with the backend POST `/users/subscription` endpoint via `OwnerProvider`. Supports manual activation warnings for Professional plan and instant downgrade to Free plan. Styled completely using `Theme.of(context)` color roles.
    *   *Blind Rating Screen*: **[VERIFIED]** Implemented `RatingScreen` supporting 1-5 star selection and text comment inputs. Connects to POST `/users/jobs/rate` using `MarketplaceProvider`. Features live progress checks querying GET `/users/ratings` to render partner rating status dynamically.
    *   *Rating Summary Card*: **[VERIFIED]** Designed `RatingSummaryCard` showing verified average stars score and review count. Embedded inside owner reputation view and customer marketplace cards.
*   **Phase 8: Live Employee Map Tracking (ADR-0008)** — **[100% COMPLETE & VERIFIED]**
    *   *Live Employee Map Tracking*: **[VERIFIED]** Implemented `flutter_map` OpenStreetMap raster tile rendering with custom User-Agent policy header `QuickDeliveryApp/1.0` and configurable tile URL constant (`MAP_TILE_URL`). Created `OwnerFleetMapScreen` for tenant owners (subscribing to `fleet:<owner_id>` WebSocket stream with hydration via `GET /users/jobs/owner`) and `CustomerJobMapScreen` for active customer job tracking (subscribing to `job:<job_id>` WebSocket stream with hydration via `GET /users/jobs/get`). Backend extended in `chat-service` (`canAccessChannel` for `fleet:<owner_id>`) and `user-service` (`UpdateJobLocation` dual broadcast to `job:<id>` and `fleet:<owner_id>`). Verified end-to-end via non-mocked integration test `TestADR0008_E2E_LiveEmployeeMapTracking` connecting real WebSockets to `chat-service` Hub and executing `UpdateJobLocation`.
*   **Phase 9: Owner Escrow Reconciliation Review** — **[100% COMPLETE & VERIFIED]**
    *   *Owner Escrow Reconciliation Review*: **[VERIFIED]** Implemented `ReconciliationProvider`, `ReconciliationJob` model, and `OwnerReconciliationQueueScreen`. Consumes `GET /users/jobs/reconciliation-queue` and `POST /users/jobs/reconciliation-resolve`. Renders human-readable failure reasons (e.g. mapping `under_distance_mismatch` to "Distance mismatch — under 70% of booked distance"), detailed reconciliation notes, and locked escrow amounts. Enforces confirmation dialogs before executing release/refund fund movements, handles empty/loading queue states, surfaces specific 409 "already resolved" and 429 rate-limiting responses, and updates queue list dynamically. Verified via widget tests (`test/reconciliation_queue_test.dart` 5/5 pass) and backend unit/integration tests.
*   **Phase 10: KYB/KYE Document Upload Screen** — **[100% COMPLETE & VERIFIED]**
    *   *KYB/KYE Document Upload Screen*: **[VERIFIED]** Implemented `KycDocumentUploadScreen` (`frontend/lib/screens/kyc_document_upload_screen.dart`), updated `UserProfile` (`frontend/lib/models/user_profile.dart`), extended `AuthProvider` (`frontend/lib/providers/auth_provider.dart`), and wired banner prompt + AppBar action in `home_screen.dart`. Renders role-conditional document upload slots (4 slots for owner: `id_front`, `id_back`, `selfie`, `business_proof`; 3 slots for employee: `id_front`, `id_back`, `selfie`). Integrates `StatusBadge` for KYC statuses, displays prominent rejection reason banner when status is `rejected`, enforces client-side file size ($\le 10$MB) and MIME format rules prior to network calls, handles per-slot upload loading and error states independently, and locks/disables upload actions when status is `approved`. Verified via widget tests (`test/kyc_document_upload_screen_test.dart` 5/5 pass).
*   **Phase 11: Negotiable Transport Pricing UI (ADR-0006)** — **[100% COMPLETE & VERIFIED]**
    *   *Negotiation UI*: **[VERIFIED]** Integrated counter-offer submission UI with $[0.5 \times P_{\text{suggested}}, 1.5 \times P_{\text{suggested}}]$ validation in `JobStatusScreen` for transport jobs in `awaiting_price_response` state. Added incoming proposal card comparing proposer, proposed fare, original system fare, and percentage difference. Handled 409 `job_state_changed` conflict responses with auto-refresh and user notification. Added 5-minute countdown ticker + explicit expired banner.
    *   *Unit/Widget Tests*: **[VERIFIED]** Added 5 comprehensive widget tests in `frontend/test/negotiable_transport_pricing_test.dart` (5/5 pass, full suite 44/44 pass). Clean `flutter analyze` (0 issues).
* **Phase 12: Real Push Notification Delivery (Firebase Cloud Messaging)** — **[100% COMPLETE & VERIFIED]**
    *   *FCM Device Token Storage (Commit 1)*: **[VERIFIED]** Added `DeviceToken` struct and array to `models.User` in `auth-service`. Built `POST /auth/device-token` and `DELETE /auth/device-token` endpoints for token registration, update, multi-device registration, and unregistration. Verified via unit tests (`TestDeviceToken_RegistrationAndUpsert`, `TestDeviceToken_Unauthorized`).
    *   *FCM Dispatcher in Notification Service (Commit 2)*: **[VERIFIED]** Added lightweight FCM HTTP v1 REST client (`fcm.Client`) in `notification-service` with fail-safe no-op mode on missing config. Integrated non-blocking parallel `PushDispatcher` into `SSEHub` (`go dispatchPush`) that delivers FCM push notifications alongside SSE broadcasts without blocking real-time streams. Added automatic stale token cleanup (`UNREGISTERED` / 404 responses trigger `DELETE /auth/device-token` on `auth-service`). Verified via unit tests in `fcm_test.go` and `hub_test.go`.
    *   *Frontend FCM Registration (Commit 3)*: **[VERIFIED]** Added `firebase_messaging` to `pubspec.yaml`. Added `registerDeviceToken` and `unregisterDeviceToken` methods to `ApiClient`. Built `PushNotificationService` with `PushMessagingAdapter` for managing token registration, unregistration, and foreground notifications. Wired `PushNotificationService` into `AuthProvider` auto-login, login/signup success, and logout flows. Built 4 unit and widget tests in `test/fcm_push_registration_test.dart` (44/44 full suite pass). Clean `flutter analyze` (0 issues).
* **Phase 13: Missing Backend Endpoints Integration Sweep (11-Endpoint Audit)** — **[IN PROGRESS — 6/11 COMPLETED]**
    *   *Completed Endpoints (6 of 11)*:
        *   **1. `POST /users/jobs/complete`**: **[VERIFIED]** Wired into `EmployeeJobsScreen`. Distinguishes COD vs non-COD flows; COD jobs require explicit cash collection confirmation dialog copy and pass `cashCollected: true` (triggering owner wallet fee deduction), whereas non-COD jobs pass `cashCollected: false` with standard completion prompt (commits `8f20aa6`, corrected in `73dc64c` after review). Verified via 5 widget tests (`test/employee_jobs_screen_test.dart`).
        *   **2. `POST /users/jobs/cancel`**: **[VERIFIED]** Wired with full role and state authorization rules (`cancelJob` in `MarketplaceProvider` and `OwnerProvider`, commit `c9e9c9c`). Requires a non-empty cancellation reason in `CancelJobDialog`. Owners can cancel pending and active jobs on `home_screen.dart` Dashboard; Customers can cancel pending jobs on `job_status_screen.dart`, while active jobs present an "Open a Complaint Ticket" button wired directly to `CreateTicketDialog`. Verified via 6 widget tests (`test/job_cancellation_test.dart`).
        *   **3. `POST /users/jobs/location/update`**: **[VERIFIED]** Wired in two parts: Part 1 (`geolocator: ^12.0.0` dependency + foreground location permissions infra, commit `0ee8e78`) and Part 2 (`EmployeeLocationProvider` featuring 10m distance filter, 3.5s minimum interval gate, quiet 429 rate limit & 400 speed check error suppression, and UI indicators in `employee_jobs_screen.dart`, commit `6e860d8`). Verified via 5 test cases in `test/employee_location_tracking_test.dart`.
        *   **4. `GET /users/platform/config`**: **[VERIFIED]** Integrated public platform configuration endpoint into `OwnerProvider` (commit `4e3cecc`) with in-memory caching after first successful fetch and silent failure handling for non-critical info. Rendered user-facing platform fee percentage as a small transparency note in `wallet_screen.dart` (`key: Key('platform_fee_percentage_text')`). Enforced security requirement ensuring `platform_wallet_id` is never rendered in UI. Verified via 3 unit/widget tests in `test/platform_config_test.dart`.
        *   **5. `GET /users/jobs/mine`**: **[VERIFIED]** Added `fetchCustomerJobs` to `MarketplaceProvider` (`frontend/lib/providers/marketplace_provider.dart`) querying `/users/jobs/mine` via `Authorization: Bearer <token>` without explicit `user_id` query parameters (IDOR protection compliant). Created `CustomerJobsScreen` (`frontend/lib/screens/customer_jobs_screen.dart`, "My Orders") with status badges, payment methods, prices, cancellation reasons, and pull-to-refresh. Wired navigation entry point (`key: Key('my_orders_button')`) in `CustomerMarketplaceScreen`. Verified via 6 widget test cases in `frontend/test/customer_jobs_screen_test.dart` (commit `61bdf2703095bae8f63ddcd9757ff5e419d09170`).
        *   **6. `POST /chat/tickets`**: **[VERIFIED]** Added `createTicket` to `ChatProvider` (`frontend/lib/providers/chat_provider.dart`) querying `POST /chat/tickets` via standard customer/user Bearer JWT authentication. Implemented `CreateTicketDialog` (`frontend/lib/widgets/create_ticket_dialog.dart`) requiring subject and issue details. Resolved existing `TODO` in `JobStatusScreen` (`frontend/lib/screens/job_status_screen.dart`), wiring the "Open a Complaint Ticket" button (`key: Key('open_complaint_ticket_button')`) directly to `CreateTicketDialog`. Verified via 5 widget test cases in `frontend/test/create_ticket_test.dart`.
    *   *Architecturally Excluded Endpoint (1 of original 11, leaving 10 actionable)*:
        *   **7. `POST /chat/tickets/resolve`**: **[SCOPE-EXCLUDED]** Architecturally excluded from the Flutter consumer app (`frontend/`). Endpoint uses agent-token authentication (`GetAgentByToken`) rather than user/employee/owner JWT auth. Documented via [ADR-0013](../adr/0013-support-agent-console-as-separate-client-application.md) establishing that this endpoint belongs to a future, separate Support Agent Console application (`omarmaarouf18/support-agent-console`). Status: architecturally excluded, not "to do."
    *   *Not Yet Started Endpoints (4 remaining, in planned execution order)*:
        *   **8. `GET /auth/employees`**: Owner-facing employee list.
        *   **9. `GET /auth/kyb-kye/pending`**: Admin/reviewer queue (requires dedicated reviewer-facing screen, larger scope similar to `jobs/mine`).
        *   **10. `POST /auth/kyb-kye/review`**: Paired with #9 (admin review action).
        *   **11. `GET /auth/documents/view`**: Paired with #9/#10 (viewing uploaded KYB/KYE documents during review).
    *   *Process Improvement & Scope Rules*:
        *   **Shared Widget Process Policy**: **[VERIFIED]** Recorded process-improvement commit `c19fb0b` adding explicit shared-widget change policy to `CLAUDE.md` under `## Auto-commit policy` following the `primary_button.dart` scope-creep review finding.
        *   **UI/UX Design Pass Sequenced Post-Wiring**: **[PLANNED]** UI/UX design improvement pass (per earlier agreement) has NOT started yet — deliberately sequenced AFTER all endpoint wiring is complete, screen by screen, per user's explicit instruction.

 ---

 ## Verified Capabilities
 *   **Owner/Customer Signup**: Sends email/password/role parameters to backend. Returns `dev_otp` in development.
 *   **2FA OTP Verification**: Validates 6-digit code and securely stores signed JWT session details.
 *   **Employee Direct Authentication**: Logs in directly bypassing 2FA.
 *   **Dashboard KYC Banner**: Renders alert banner to Owners when `kyc_status` is `pending_super_admin_approval`.
 *   **Employee Job Assignment List**: Fetches and renders all active/pending/completed jobs assigned to the logged-in worker.
 *   **Employee Action Simulator**: Logs actions to the audit trail, enforcing frozen and KYC-pending checks.
 *   **Username Validation & RTL Support**: Enforces 3-30 character rune-aware username checking at signup, supports mixed Latin/Arabic text directions, and registers usernames to the backend.
 *   **Username Propagation & Chat Snapshot**: Propagates registered usernames to dashboard welcome messages and profile detail panels, and displays `senderUsername` in the chat UI including fallback support and Agent display name resolution.
 *   **Real-Time Chat & History Sync**: Fetches message history on load, establishes WebSocket connection, supports dual-direction message broadcasts, handles reconnection backoff, and restricts channel access securely.
 *   **SSE Notifications Stream**: Establishes Server-Sent Events subscription, decodes real-time JSON alert payloads, manages local message history, filters by category, groups alerts chronologically, and integrates unread notification badges in dashboard AppBars.
 *   **Live Employee Map Tracking**: Hydrates employee locations from HTTP API endpoints, connects to chat-service WebSocket hub channels (`fleet:<owner_id>` / `job:<job_id>`), updates employee marker positions in real time, and displays reconnection banners gracefully. Verified end-to-end with real backend WebSocket connections and broadcasts (`TestADR0008_E2E_LiveEmployeeMapTracking`).
 *   **Owner Escrow Reconciliation Review**: Lists jobs in status `escrow_reconciliation_required` for tenant owners via `GET /users/jobs/reconciliation-queue`, displays human-readable failure descriptions and locked escrow details, requires interactive confirmation dialogs before executing release/refund fund movements via `POST /users/jobs/reconciliation-resolve`, handles empty/loading states, and handles 409 conflict and 429 rate-limit responses gracefully.
 * **Negotiable Transport Pricing (ADR-0006)**: Enables customer and employee counter-offers within ±50% bounds for transport jobs in `awaiting_price_response` state via `POST /users/jobs/propose-price` and `POST /users/jobs/respond-price`, displays clear proposal comparison card with system fare comparison, handles 409 `job_state_changed` conflicts gracefully, and tracks 5-minute negotiation expiry window with live countdown ticker and expired banner state.
 * **Device GPS Location Permission & Ingestion (POST /users/jobs/location/update)**: **[VERIFIED]** Added `geolocator: ^12.0.0` dependency, configured foreground-only Android (`ACCESS_FINE_LOCATION`) and iOS (`NSLocationWhenInUseUsageDescription`) location permissions, implemented `requestLocationPermission` helper utility (`frontend/lib/core/location_permission.dart`), created `EmployeeLocationProvider` (`frontend/lib/providers/employee_location_provider.dart`) featuring 10m distance filter, 3.5s minimum interval gate (providing safety margin over backend 3s rate limit floor), quiet rate-limit/speed-check error suppression (`429` / `400 implausible_speed`), and automatic stream subscription management. Integrated unobtrusive "Sharing live location" status indicator and inline permission explanation into `employee_jobs_screen.dart`. Verified via 5 test cases in `frontend/test/employee_location_tracking_test.dart` and 7 test cases in `frontend/test/location_permission_test.dart`.
 * **Public Platform Config Wiring (GET /users/platform/config)**: **[VERIFIED]** Integrated public platform configuration endpoint into `OwnerProvider` (`frontend/lib/providers/owner_provider.dart`) with in-memory caching after first successful fetch and silent failure handling for non-critical info. Rendered user-facing platform fee percentage as a small transparency note in `wallet_screen.dart` (`key: Key('platform_fee_percentage_text')`). Enforced security requirement preventing internal `platform_wallet_id` from rendering in UI. Verified via 3 unit/widget tests in `frontend/test/platform_config_test.dart`.
 * **Customer Job History (GET /users/jobs/mine)**: **[VERIFIED]** Added `fetchCustomerJobs` to `MarketplaceProvider` (`frontend/lib/providers/marketplace_provider.dart`) querying `GET /users/jobs/mine` (IDOR-safe Bearer token authentication). Displays customer order history cards in `CustomerJobsScreen` ("My Orders") with status badges, payment details, prices, cancellation reasons, navigation to `JobStatusScreen`, and pull-to-refresh. Accessible via "My Orders" AppBar action (`key: Key('my_orders_button')`) in `CustomerMarketplaceScreen`. Verified via 6 widget test cases in `frontend/test/customer_jobs_screen_test.dart`.
 * **Support Complaint Ticket Creation (POST /chat/tickets)**: **[VERIFIED]** Added `createTicket` to `ChatProvider` (`frontend/lib/providers/chat_provider.dart`) querying `POST /chat/tickets` via standard JWT Bearer authentication. Implemented `CreateTicketDialog` (`frontend/lib/widgets/create_ticket_dialog.dart`) requiring subject and issue details with validation and error banner. Wired "Open a Complaint Ticket" button (`key: Key('open_complaint_ticket_button')`) in `JobStatusScreen` (`frontend/lib/screens/job_status_screen.dart`). Verified via 5 widget test cases in `frontend/test/create_ticket_test.dart`.

 ## File Tracking Index

 The following Dart implementation files are currently active in the codebase and tracked by the structural drift check:
 * **Core**:
   * `api_client.dart`
   * `error_messages.dart`
   * `location_permission.dart`
 * **Models**:
   * `user_profile.dart`
   * `job.dart`
   * `marketplace_service.dart`
   * `chat_message.dart`
   * `notification_model.dart`
   * `employee_marker.dart`
   * `reconciliation_job.dart`
 * **Theme**:
   * `theme.dart`
 * **Services**:
   * `push_notification_service.dart`
 * **Providers**:
   * `auth_provider.dart`
   * `owner_provider.dart`
   * `employee_jobs_provider.dart`
   * `employee_location_provider.dart`
   * `marketplace_provider.dart`
   * `chat_provider.dart`
   * `notifications_provider.dart`
   * `map_tracking_provider.dart`
   * `reconciliation_provider.dart`
 * **Screens**:
   * `employee_jobs_screen.dart`
   * `employee_screen.dart`
   * `home_screen.dart`
   * `login_screen.dart`
   * `otp_screen.dart`
   * `service_screen.dart`
   * `signup_screen.dart`
   * `wallet_screen.dart`
   * `customer_marketplace_screen.dart`
   * `job_status_screen.dart`
   * `chat_screen.dart`
   * `notifications_screen.dart`
   * `subscription_screen.dart`
   * `rating_screen.dart`
   * `owner_fleet_map_screen.dart`
   * `customer_job_map_screen.dart`
   * `owner_reconciliation_queue_screen.dart`
   * `kyc_document_upload_screen.dart`
   * `forgot_password_screen.dart`
   * `reset_password_screen.dart`
   * `customer_jobs_screen.dart`
 * **Widgets**:
   * `rating_summary_card.dart`
   * `primary_button.dart`
   * `secondary_button.dart`
   * `themed_text_field.dart`
   * `themed_card.dart`
   * `themed_section_header.dart`
   * `themed_loading_indicator.dart`
   * `themed_empty_state.dart`
   * `themed_error_banner.dart`
   * `cancel_job_dialog.dart`
   * `create_ticket_dialog.dart`

---

## Known Gaps & Limitations

*   **Mock Reply Feature**: The "Reply" button on notification cards in [notifications_screen.dart](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/frontend/lib/screens/notifications_screen.dart) marks the notification as read and shows a `SnackBar` stating that the feature is in beta and local-only. It does not send any backend messages. This is a frontend-only demo placeholder.
*   **Notification Deep-Linking (Temporary Bootstrap Stub)**: When navigating to [job_status_screen.dart](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/frontend/lib/screens/job_status_screen.dart) from a notification alert with a parsable Job ID, the screen is initialized with a temporary, minimal placeholder `Job` model (a bootstrap stub). Once loaded, the screen's polling mechanism and manual refresh invoke `MarketplaceProvider.fetchJobStatus` to retrieve the real, complete job record from the API, fully replacing the placeholder data with the live state. Thus, it is a temporary transition state rather than permanent fake/mock data.
