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
*   **Phase 4: Customer Directory & Job Booking Flow** — **[100% COMPLETE & VERIFIED]**
    *   *Marketplace Directory*: **[VERIFIED]** List view with custom latitude/longitude coordinate query inputs, search radius, exactly 3 categories (Delivery, Ride, Shipping) using existing constant mapping, and price sorting, querying `/users/services`.
    *   *Booking Workflow (COD Only)*: **[VERIFIED]** Booking creation dialog forcing Cash on Delivery (COD) payment method with an informative beta note about deferred escrow, invoking `/users/jobs/track`. Supported by custom backend fallback allowing raw owner user ID input.
    *   *Real-Time Status Screen*: **[VERIFIED]** Step-based progress tracker (Pending -> Active -> Completed/Cancelled), job details, assigned worker info, and 5-second automatic polling + manual status refresh querying `/users/jobs/get`.
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
    *   *Live Employee Map Tracking*: **[VERIFIED]** Implemented flutter_map OpenStreetMap raster tile rendering with custom User-Agent policy header `QuickDeliveryApp/1.0` and configurable tile URL constant (`MAP_TILE_URL`). Created `OwnerFleetMapScreen` for tenant owners (subscribing to `fleet:<owner_id>` WebSocket stream with hydration via `GET /users/jobs/owner`) and `CustomerJobMapScreen` for active customer job tracking (subscribing to `job:<job_id>` WebSocket stream with hydration via `GET /users/jobs/get`). Verified via widget tests in `map_tracking_test.dart`.

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
 *   **Live Employee Map Tracking**: Hydrates employee locations from HTTP API endpoints, connects to chat-service WebSocket hub channels (`fleet:<owner_id>` / `job:<job_id>`), updates employee marker positions in real time, and displays reconnection banners gracefully.

 ## File Tracking Index

 The following Dart implementation files are currently active in the codebase and tracked by the structural drift check:
 * **Models**:
   * `user_profile.dart`
   * `job.dart`
   * `marketplace_service.dart`
   * `chat_message.dart`
   * `notification_model.dart`
   * `employee_marker.dart`
 * **Theme**:
   * `theme.dart`
 * **Providers**:
   * `auth_provider.dart`
   * `owner_provider.dart`
   * `employee_jobs_provider.dart`
   * `marketplace_provider.dart`
   * `chat_provider.dart`
   * `notifications_provider.dart`
   * `map_tracking_provider.dart`
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

---

## Known Gaps & Limitations

*   **Mock Reply Feature**: The "Reply" button on notification cards in [notifications_screen.dart](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/frontend/lib/screens/notifications_screen.dart) marks the notification as read and shows a `SnackBar` stating that the feature is in beta and local-only. It does not send any backend messages. This is a frontend-only demo placeholder.
*   **Notification Deep-Linking (Temporary Bootstrap Stub)**: When navigating to [job_status_screen.dart](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/frontend/lib/screens/job_status_screen.dart) from a notification alert with a parsable Job ID, the screen is initialized with a temporary, minimal placeholder `Job` model (a bootstrap stub). Once loaded, the screen's polling mechanism and manual refresh invoke `MarketplaceProvider.fetchJobStatus` to retrieve the real, complete job record from the API, fully replacing the placeholder data with the live state. Thus, it is a temporary transition state rather than permanent fake/mock data.
