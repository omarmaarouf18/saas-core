# Frontend System Architecture

This document describes the design patterns, state management models, directory structures, and API connections used in the Flutter frontend application.

## Directory Layout
*   **`lib/main.dart`**: Main entrypoint setting up dependency injection (Providers), custom route configurations, and HTTP overrides.
*   **`lib/core/`**: Utility code and shared libraries.
    *   `api_client.dart`: HTTP client wrapper configured for local development SSL overrides (gated by `kDebugMode`) and bearer token authorization header injection.
*   **`lib/models/`**: Clean serialization data schemas.
    *   `user_profile.dart`: Representation of active logged-in user profile, role, and KYC states.
    *   `job.dart`: Job tracking model with status transitions and location coordinates.
    *   `marketplace_service.dart`: Marketplace service directory model.
    *   `chat_message.dart`: Real-time chat message schema.
    *   `notification_model.dart`: Real-time SSE alert notification model.
*   **`lib/providers/`**: Core app logic and state models (Provider Pattern).
    *   `auth_provider.dart`: Tracks session authentication state, loading indicators, error triggers, and persists JWT parameters via `flutter_secure_storage`.
    *   `owner_provider.dart`: Owner subscription management and wallet operations.
    *   `employee_jobs_provider.dart`: Assigned worker job listing state.
    *   `marketplace_provider.dart`: Service browsing, filtering, job booking, and rating state.
    *   `chat_provider.dart`: WebSocket connection, channels, and message history state.
    *   `notifications_provider.dart`: Real-time SSE alerts stream and unread badge tracking.
*   **`lib/screens/`**: UI Views and layout definitions.
    *   `login_screen.dart`: Forms for logins. Handles routing for 2FA-bound roles (Owners, Customers) vs. immediate redirect (Employees).
    *   `signup_screen.dart`: Account registration form.
    *   `otp_screen.dart`: OTP 2FA verify form with auto-populating dev capabilities.
    *   `home_screen.dart`: Dashboard wrapper incorporating role-based widgets and Owner KYC-pending alert banners.
    *   `employee_screen.dart`: Employee audit action simulator view.
    *   `employee_jobs_screen.dart`: Employee assigned job task list view.
    *   `service_screen.dart`: Owner service directory management view.
    *   `wallet_screen.dart`: Owner e-wallet balance and transaction ledger.
    *   `customer_marketplace_screen.dart`: Customer service directory search/filter view.
    *   `job_status_screen.dart`: Real-time job tracking status screen.
    *   `chat_screen.dart`: Real-time channel messaging view.
    *   `notifications_screen.dart`: SSE alert notifications center.
    *   `subscription_screen.dart`: Owner subscription tier management.
    *   `rating_screen.dart`: 1-5 star blind rating screen.

## State Management Approach
The frontend uses the **Provider** pattern for state management and change notifications:
1.  **`AuthProvider`**:
    *   *Role*: Single source of truth for current session authentication, user profile fields, network activity indicators (`isLoading`), and validation errors (`error`).
    *   *Persistence*: Automatically loads and persists tokens/user metadata securely across sessions using a hardware-backed secure storage engine (`FlutterSecureStorage`).

## API Route Mappings
Flutter HTTP requests map directly onto the backend's microservices through the centralized API Gateway.
*   For the complete listing of microservice route endpoints, request/response models, and database effects, consult **[docs/APPLICATION_MAP.md](../APPLICATION_MAP.md)**.
*   Authentication screens map specifically to:
    *   `POST /auth/signup` -> `SignupScreen` / `AuthProvider.signup`
    *   `POST /auth/login` -> `LoginScreen` / `AuthProvider.login`
    *   `POST /auth/verify-otp` -> `OtpScreen` / `AuthProvider.verifyOtp`

## Real-Time Subscriptions
*   *WebSocket Chat*: Real-time channel messaging via `wss://` gateway proxy connection (`/chat/ws?token=<token>`). Integrated in `ChatProvider` / `ChatScreen`.
*   *SSE Notifications*: Server-Sent Events alerts via `NotificationsProvider` using `flutter_client_sse` subscribing to `/notifications/stream?token=<token>`. Integrated in `NotificationsScreen`.
