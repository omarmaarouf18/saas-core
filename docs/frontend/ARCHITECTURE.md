# Frontend System Architecture

This document describes the design patterns, state management models, directory structures, and API connections used in the Flutter frontend application.

## Directory Layout
*   **`lib/main.dart`**: Main entrypoint setting up dependency injection (`MultiProvider`), localized routing, theme configuration, and HTTP overrides.
*   **`lib/core/`**: Utility code and shared libraries.
    *   `api_client.dart`: HTTP client wrapper configured for local development SSL overrides (gated by `kDebugMode`), bearer token authorization header injection, binary byte stream downloading, and query parameter handling.
    *   `theme.dart`: Single source of truth for design system tokens (`AppColors`, `AppSpacing`, `AppRadius`, `AppElevation`, `AppMotion`, `AppIconSize`, `AppTypography`).
    *   `location_permission.dart`: Foreground-only device GPS location permission state handling.
    *   `constants.dart`: Global constants and API gateway URLs.
    *   `error_messages.dart`: User-friendly localized error message resolution.
*   **`lib/models/`**: Clean serialization data schemas.
    *   `user_profile.dart`: Representation of active logged-in user profile, role, and KYC states.
    *   `job.dart`: Job tracking model with status transitions and location coordinates.
    *   `marketplace_service.dart`: Marketplace service directory model.
    *   `chat_message.dart`: Real-time chat message schema.
    *   `notification_model.dart`: Real-time SSE alert notification model.
    *   `employee_marker.dart`: Live employee map marker coordinates and status.
    *   `reconciliation_job.dart`: Escrow reconciliation failure details model.
    *   `payout_request.dart`: Owner payout/withdrawal request record.
*   **`lib/providers/`**: Core app logic and state models (Provider Pattern — 11 active providers).
    *   `auth_provider.dart`: Tracks session authentication state, user profile, password reset, account updates, and persists JWT parameters via `flutter_secure_storage`.
    *   `owner_provider.dart`: Owner subscription management, wallet operations, payout requests, platform config caching, employee roster fetching, and job cancellation.
    *   `employee_jobs_provider.dart`: Assigned worker job listing state and COD/non-COD job completion actions.
    *   `employee_location_provider.dart`: Foreground live GPS location tracking manager with 10m distance filter, 3.5s minimum interval gate, and error suppression.
    *   `customer_jobs_provider.dart` / `marketplace_provider.dart`: Service browsing, filtering, customer order history fetching (`fetchCustomerJobs`), job booking, counter-offer negotiation, rating state, and job cancellation.
    *   `chat_provider.dart`: WebSocket connection, channels, real-time message history, and support complaint ticket creation (`createTicket`).
    *   `notifications_provider.dart`: Real-time SSE alerts stream and unread badge tracking.
    *   `map_tracking_provider.dart`: Live courier location WebSocket stream and map state manager.
    *   `reconciliation_provider.dart`: Owner escrow reconciliation queue fetching and dispute resolution.
    *   `theme_provider.dart`: Theme mode state management (Light / Dark / System) persisted via secure storage.
    *   `locale_provider.dart`: Locale state management (English / Egyptian Colloquial Arabic) with device auto-detection.
*   **`lib/screens/`**: UI Views and layout definitions (28 active Flutter screens).
    *   *Authentication & Platform (5 screens)*:
        *   `login_screen.dart`: Stitch-styled login with brand logotype, 2-card role selector, and pre-login theme/language toggles.
        *   `signup_screen.dart`: 2-step registration with customer/owner role cards and form validation.
        *   `otp_screen.dart`: Discrete 6-digit PIN input with security badge, auto-advance, and countdown resend timer.
        *   `forgot_password_screen.dart`: 2-step password recovery (request OTP -> inline reset with auto-fill).
        *   `update_required_screen.dart`: Mandatory update gate with concentric pulse animation and version notes.
    *   *Customer Experience (5 screens)*:
        *   `customer_home_screen.dart`: 4-tab shell with Stitch Welcome Banner, "Where to deliver?" search, category grid, and active orders card.
        *   `customer_jobs_screen.dart`: Customer order history ("My Orders") with `#QD-` tracking IDs, live progress bars, price chips, and filter pills.
        *   `customer_marketplace_screen.dart`: Service directory with location map picker dialog, distance filters, and booking modal.
        *   `job_status_screen.dart`: Real-time tracking with live status bar, 4-stage stepper, RouteTimeline, driver profile card, price counter-offer panel, and ticket creation.
        *   `customer_job_map_screen.dart`: Interactive FlutterMap with custom pickup & gold courier markers, floating controls, and bottom details sheet.
    *   *Tenant Owner Operations (7 screens)*:
        *   `home_screen.dart`: 4-tab shell (Home, Employees, History, Settings) with Bento grid (Jobs, Fleet, Revenue), quick access cards, and order list.
        *   `employee_screen.dart`: Worker roster with `#QD-` IDs, EntityAvatar, StatusBadge, quick actions, and register/freeze forms.
        *   `service_screen.dart`: KYC-gated service management with 2-column pricing metrics and creation dialog.
        *   `owner_configuration_screen.dart`: 3 Bento profile sections (Business Identity, Location & Operations, Pricing & Rates).
        *   `wallet_screen.dart`: Deep Navy Balance Hero card, withdrawable/escrow metrics, payout request dialog & history, and ledger.
        *   `subscription_screen.dart`: Pricing tier matrix with active plan banner and highlighted recommended card.
        *   `owner_reconciliation_queue_screen.dart`: Escrow reconciliation review queue with dispute reason alert containers and confirmation modal.
    *   *Employee & Fleet Operations (4 screens)*:
        *   `employee_home_screen.dart`: 3-tab shell (Jobs, History, Settings) with Quick Delivery brand header and notification bell.
        *   `employee_jobs_screen.dart`: Active job card with RouteTimeline, COD/Pre-paid indicator, location tracking status pill, chat/complete actions, and simulator.
        *   `employee_history_screen.dart`: Historical job cards with timestamps, customer info, payment methods, and cancellation alerts.
        *   `owner_fleet_map_screen.dart`: Live fleet tracking map with floating filter pills (All Fleet, On Route, Idle), OpenStreetMap markers, and WebSocket stream.
    *   *Shared & Support (7 screens)*:
        *   `kyc_document_upload_screen.dart`: Role-conditional document upload slots with status badges and rejection banners.
        *   `owner_history_screen.dart`: 3-tab history (Activity Log, Jobs, Ledger) with `#QD-` tracking IDs and filter pills.
        *   `settings_screen.dart`: User profile summary card, SegmentedButton theme/language pickers, KYC access row, and support tickets.
        *   `my_account_screen.dart`: Profile information, read-only email with change modal, and frequent address manager (10-entry cap).
        *   `notifications_screen.dart`: Category filter pills, operational status banner, unread notification cards, and clear actions.
        *   `chat_screen.dart`: Live connection indicator, sender usernames, chat bubbles, and message composer.
        *   `rating_screen.dart`: Driver profile card, 5-star rating selector with gold icons, private feedback field, and blind status visualizer.
*   **`lib/widgets/`**: Reusable component design system (27 widgets).
    *   *Buttons & Inputs*: `primary_button.dart` (Amber Gold CTA with debounce protection), `secondary_button.dart` (Outlined/neutral action), `themed_text_field.dart`, `otp_pin_input.dart`, `pill_filter_bar.dart`.
    *   *Cards & Containers*: `themed_card.dart` (Tokenized container with `topAccentColor` support), `stat_card.dart`, `rating_summary_card.dart`, `info_list_tile.dart`, `entity_avatar.dart`, `status_badge.dart`, `route_timeline.dart`, `themed_section_header.dart`.
    *   *States & Feedback*: `themed_empty_state.dart`, `themed_loading_indicator.dart`, `themed_error_banner.dart`, `themed_success_banner.dart`, `themed_banner.dart`, `skeleton_loader.dart`.
    *   *Dialogs & Pickers*: `confirm_action_dialog.dart`, `cancel_job_dialog.dart`, `create_ticket_dialog.dart`, `create_service_dialog.dart`, `deposit_funds_dialog.dart`, `payout_request_dialog.dart`, `email_change_dialog.dart`, `location_picker_map.dart`.

## State Management Approach
The frontend uses the **Provider** pattern for state management:
1.  **`AuthProvider`**: Authentication lifecycle, credentials, profile, and secure token persistence via `FlutterSecureStorage`.
2.  **`OwnerProvider`**: Business metrics, subscription tier changes, e-wallet transactions, payout requests, platform config, employee roster, and job cancellation.
3.  **`MarketplaceProvider`**: Service catalog search/filtering, job booking, customer order history, counter-offer pricing, ratings, and job cancellation.
4.  **`EmployeeJobsProvider` & `EmployeeLocationProvider`**: Assigned jobs queue, job completion actions, and live GPS location stream updates with rate-limit and speed error suppression.
5.  **`ChatProvider` & `NotificationsProvider`**: Real-time WebSocket channel communication, complaint ticket creation (`createTicket`), and SSE alert notification streams.
6.  **`MapTrackingProvider` & `ReconciliationProvider`**: Real-time live fleet tracking map and escrow reconciliation dispute resolution.
7.  **`ThemeProvider` & `LocaleProvider`**: App-wide theme mode (Light/Dark/System) and locale (English/Arabic) state.

## API Route Mappings
Flutter HTTP requests map directly onto the backend's microservices through the centralized API Gateway.
*   For the complete listing of microservice route endpoints, request/response models, and database effects, consult **[docs/APPLICATION_MAP.md](../APPLICATION_MAP.md)**.
*   Authentication & KYC endpoints map specifically to:
    *   `POST /auth/signup` -> `SignupScreen` / `AuthProvider.signup`
    *   `POST /auth/login` -> `LoginScreen` / `AuthProvider.login`
    *   `POST /auth/verify-otp` -> `OtpScreen` / `AuthProvider.verifyOtp`
    *   `GET /auth/employees` -> `EmployeeScreen` / `OwnerProvider.fetchEmployees`
    *   `GET /auth/kyb-kye/pending` -> **[REMOVED PER ADR-0013]** Reserved for Support Agent Console
    *   `GET /auth/documents/view` -> **[REMOVED PER ADR-0013]** Reserved for Support Agent Console
    *   `POST /auth/kyb-kye/review` -> **[REMOVED PER ADR-0013]** Reserved for Support Agent Console

## Real-Time Subscriptions
*   *WebSocket Chat*: Real-time channel messaging via `wss://` gateway proxy connection (`/chat/ws?token=<token>`). Integrated in `ChatProvider` / `ChatScreen`.
*   *WebSocket Live Tracking*: Real-time driver/courier coordinate streaming on `job:<job_id>` and `fleet:<owner_id>`. Integrated in `MapTrackingProvider`, `CustomerJobMapScreen`, and `OwnerFleetMapScreen`.
*   *SSE Notifications*: Server-Sent Events alerts via `NotificationsProvider` subscribing to `/notifications/stream?token=<token>`. Integrated in `NotificationsScreen`.

