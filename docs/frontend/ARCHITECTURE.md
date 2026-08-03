# Frontend System Architecture

This document describes the design patterns, state management models, directory structures, and API connections used in the Flutter frontend application.

## Directory Layout
*   **`lib/main.dart`**: Main entrypoint setting up dependency injection (Providers), custom route configurations, and HTTP overrides.
*   **`lib/core/`**: Utility code and shared libraries.
    *   `api_client.dart`: HTTP client wrapper configured for local development SSL overrides (gated by `kDebugMode`), bearer token authorization header injection, binary byte stream downloading, and query parameter handling.
    *   `theme.dart`: Design system design tokens, typography, and color palettes.
    *   `location_permission.dart`: Foreground-only device GPS location permission state handling.
*   **`lib/models/`**: Clean serialization data schemas.
    *   `user_profile.dart`: Representation of active logged-in user profile, role, and KYC states.
    *   `job.dart`: Job tracking model with status transitions and location coordinates.
    *   `marketplace_service.dart`: Marketplace service directory model.
    *   `chat_message.dart`: Real-time chat message schema.
    *   `notification_model.dart`: Real-time SSE alert notification model.
*   **`lib/providers/`**: Core app logic and state models (Provider Pattern).
    *   `auth_provider.dart`: Tracks session authentication state, loading indicators, error triggers, KYB/KYE reviewer queue fetching, document stream fetching, review decision actions, and persists JWT parameters via `flutter_secure_storage`.
    *   `owner_provider.dart`: Owner subscription management, wallet operations, platform config caching, employee roster fetching, and job cancellation.
    *   `employee_jobs_provider.dart`: Assigned worker job listing state and COD/non-COD job completion actions.
    *   `employee_location_provider.dart`: Background/foreground live GPS location tracking manager with 10m distance filter, 3.5s minimum interval gate, and error suppression.
    *   `marketplace_provider.dart`: Service browsing, filtering, customer order history fetching (`fetchCustomerJobs`), job booking, counter-offer negotiation, rating state, and job cancellation.
    *   `chat_provider.dart`: WebSocket connection, channels, real-time message history, and support complaint ticket creation (`createTicket`).
    *   `notifications_provider.dart`: Real-time SSE alerts stream and unread badge tracking.
*   **`lib/screens/`**: UI Views and layout definitions.
    *   `login_screen.dart`: Forms for logins. Handles routing for 2FA-bound roles (Owners, Customers) vs. immediate redirect (Employees).
    *   `signup_screen.dart`: Account registration form.
    *   `otp_screen.dart`: OTP 2FA verify form with auto-populating dev capabilities.
    *   `forgot_password_screen.dart`: Password reset email request form.
    *   `reset_password_screen.dart`: Password reset verification and new password submission form.
    *   `home_screen.dart`: Dashboard wrapper incorporating role-based widgets, Owner KYC-pending alert banners, and Reviewer queue entry points.
    *   `employee_screen.dart`: Employee management and registered worker roster view.
    *   `employee_jobs_screen.dart`: Employee assigned job task list and live GPS tracking view.
    *   `service_screen.dart`: Owner service directory management view.
    *   `wallet_screen.dart`: Owner e-wallet balance and transaction ledger.
    *   `customer_marketplace_screen.dart`: Customer service directory search/filter view.
    *   `customer_jobs_screen.dart`: Customer order history ("My Orders") view with status badges and status navigation.
    *   `job_status_screen.dart`: Real-time job tracking status screen with complaint ticket submission trigger.
    *   `chat_screen.dart`: Real-time channel messaging view.
    *   `notifications_screen.dart`: SSE alert notifications center.
    *   `subscription_screen.dart`: Owner subscription tier management.
    *   `rating_screen.dart`: 1-5 star blind rating screen.
    *   `owner_fleet_map_screen.dart`: Owner live fleet map tracking view.
    *   `customer_job_map_screen.dart`: Customer live job delivery tracking map view.
    *   `owner_reconciliation_queue_screen.dart`: Owner COD cash reconciliation queue view.
    *   `kyc_document_upload_screen.dart`: KYB/KYE document submission form.
    *   `kyb_kye_review_screen.dart`: Reviewer queue roster view for pending KYB/KYE verification requests.
*   **`lib/widgets/`**: Reusable component design system and dialogs.
    *   `primary_button.dart`: Standard themed primary action button with loading and text truncation handling.
    *   `secondary_button.dart`: Outlined secondary action button with icon support.
    *   `themed_card.dart`: Container card styled with design system tokens.
    *   `themed_text_field.dart`: Standardized input text field.
    *   `themed_section_header.dart`: Layout section header widget.
    *   `themed_loading_indicator.dart`: Standardized loading spinner with custom copy.
    *   `themed_empty_state.dart`: Standardized zero-data / unauthorized state layout.
    *   `themed_error_banner.dart`: Retryable error banner widget.
    *   `status_badge.dart`: Styled status pill for jobs, KYC, and worker states.
    *   `rating_summary_card.dart`: Rating score summary card.
    *   `cancel_job_dialog.dart`: Job cancellation confirmation dialog with mandatory reason text field.
    *   `create_ticket_dialog.dart`: Support complaint ticket submission dialog.
    *   `document_viewer_dialog.dart`: KYB/KYE document preview viewer dialog supporting image decoding, PDF containers, tab switching, and Approve/Reject review decision actions.

## State Management Approach
The frontend uses the **Provider** pattern for state management and change notifications:
1.  **`AuthProvider`**:
    *   *Role*: Single source of truth for session authentication, user profile fields, network activity indicators, validation errors, KYB/KYE reviewer queue management, document fetching, and review decisions.
    *   *Persistence*: Automatically loads and persists tokens/user metadata securely across sessions using a hardware-backed secure storage engine (`FlutterSecureStorage`).
2.  **`OwnerProvider`**:
    *   *Role*: Manages owner business metrics, subscription tiers, e-wallet transactions, public platform config (`fetchPlatformConfig`), registered employee roster (`fetchEmployees`), and job cancellation.
3.  **`MarketplaceProvider`**:
    *   *Role*: Handles service directory search, booking creation, customer order history (`fetchCustomerJobs`), price counter-offers, ratings, and job cancellation.
4.  **`EmployeeJobsProvider` & `EmployeeLocationProvider`**:
    *   *Role*: Manages assigned worker task lists, COD/non-COD job completion, and live GPS location stream updates with rate-limit and speed error suppression.
5.  **`ChatProvider` & `NotificationsProvider`**:
    *   *Role*: Real-time WebSocket channel communication, complaint ticket creation (`createTicket`), and SSE alert notification streams.

## API Route Mappings
Flutter HTTP requests map directly onto the backend's microservices through the centralized API Gateway.
*   For the complete listing of microservice route endpoints, request/response models, and database effects, consult **[docs/APPLICATION_MAP.md](../APPLICATION_MAP.md)**.
*   Authentication & KYC endpoints map specifically to:
    *   `POST /auth/signup` -> `SignupScreen` / `AuthProvider.signup`
    *   `POST /auth/login` -> `LoginScreen` / `AuthProvider.login`
    *   `POST /auth/verify-otp` -> `OtpScreen` / `AuthProvider.verifyOtp`
    *   `GET /auth/employees` -> `EmployeeScreen` / `OwnerProvider.fetchEmployees`
    *   `GET /auth/kyb-kye/pending` -> `KybKyeReviewScreen` / `AuthProvider.fetchPendingSubmissions`
    *   `GET /auth/documents/view` -> `DocumentViewerDialog` / `AuthProvider.fetchDocumentBytes`
    *   `POST /auth/kyb-kye/review` -> `DocumentViewerDialog` / `AuthProvider.reviewSubmission`

## Real-Time Subscriptions
*   *WebSocket Chat*: Real-time channel messaging via `wss://` gateway proxy connection (`/chat/ws?token=<token>`). Integrated in `ChatProvider` / `ChatScreen`.
*   *SSE Notifications*: Server-Sent Events alerts via `NotificationsProvider` subscribing to `/notifications/stream?token=<token>`. Integrated in `NotificationsScreen`.
