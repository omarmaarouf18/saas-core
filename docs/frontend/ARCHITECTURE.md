# Frontend System Architecture

This document describes the design patterns, state management models, directory structures, and API connections used in the Flutter frontend application.

## Directory Layout
*   **`lib/main.dart`**: Main entrypoint setting up dependency injection (Providers), custom route configurations, and HTTP overrides.
*   **`lib/core/`**: Utility code and shared libraries.
    *   `api_client.dart`: HTTP client wrapper configured for local development SSL overrides (gated by `kDebugMode`) and bearer token authorization header injection.
*   **`lib/models/`**: Clean serialization data schemas.
    *   `user_profile.dart`: Representation of active logged-in user profile, role, and KYC states.
*   **`lib/providers/`**: Core app logic and state models (Provider Pattern).
    *   `auth_provider.dart`: Tracks session authentication state, loading indicators, error triggers, and persists JWT parameters via `flutter_secure_storage`.
*   **`lib/screens/`**: UI Views and layout definitions.
    *   `login_screen.dart`: Forms for logins. Handles routing for 2FA-bound roles (Owners, Customers) vs. immediate redirect (Employees).
    *   `signup_screen.dart`: Account registration form.
    *   `otp_screen.dart`: OTP 2FA verify form with auto-populating dev capabilities.
    *   `home_screen.dart`: Dashboard wrapper incorporating role-based widgets and Owner KYC-pending alert banners.

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
