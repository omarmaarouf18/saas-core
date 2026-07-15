# Frontend Status Tracker

> [!NOTE]
> This is a lean tracker mapping the current implementation state of the Flutter frontend application. For the complete step-by-step roadmap, consult [IMPLEMENTATION.md](../../IMPLEMENTATION.md).

---

## Phase Progress (Per IMPLEMENTATION.md Sequence)

*   **Phase 1: Project Setup & Shared Auth Flow** — **[100% COMPLETE & VERIFIED]**
    *   *Auth Flow Logic*: **[VERIFIED]** contract-matching works against the live docker-compose backend for signup, 2FA OTP, direct employee login, and KYC dashboard warning banners.
    *   *Branding & Re-Theming*: **[VERIFIED]** Re-skinned the entire application layout (login, signup, OTP, home/dashboard, wallet, employee management, service directory) to use the Quick Delivery brand kit (Deep Navy, Amber Gold, Light Gray, White, Poppins typography). Removed all hardcoded Material indigo/blue values and routed styling through `ThemeData` and `theme.dart`.
    *   *Platform Builds*:
        *   *Android*: **[VERIFIED]** successfully compiled debug APK using local Adoptium JDK 17 and Android SDK platforms-36/build-tools-34. Output location: `frontend/build/app/outputs/flutter-apk/app-debug.apk` (Size: 153,369,344 bytes).
        *   *iOS*: **[UNVERIFIED]** macOS/Xcode toolchain unavailable (build execution requires a Mac environment).
*   **Phase 2: Owner Core Functionality** — **[100% COMPLETE & VERIFIED]**
    *   *Dashboard Layout*: **[VERIFIED]** Owner dashboard metrics grid displays wallet balance (via GetWallet) and subscription status (via Subscription) with active jobs placeholder layout. Confirmed working end-to-end against live docker-compose backend using real signed owner JWT token resolve logic.
    *   *Wallet Management*: **[VERIFIED]** Balance display (total, withdrawable, escrow), reverse-chronological transaction ledger, and deposit dialog with inline error notice for production environment gating. Verified end-to-end against live backend with local/production environment check.
    *   *Employee Management*: **[VERIFIED]** Worker registration, worker freeze/activate status toggling (with owner password re-auth), and tenant audit log retrieval (using paired RAW ID + JWT token). Tested end-to-end against live backend including worker action simulation and audit trail verification.
    *   *Service Directory Configuration*: **[VERIFIED]** KYC-gated service creation form with name, category (mapped to Delivery, Ride, Shipping), base price, rate per KM, and coordinates. Tested end-to-end against the live backend user-service.
*   **Phase 3: Employee Dashboard & Audit Simulator** — **[NOT STARTED]**
    *   *Planned*: Assigned jobs list, action simulation, and worker audit logs.
*   **Phase 4: Customer Directory & Job Booking Flow** — **[NOT STARTED]**
    *   *Planned*: Service directory search, booking requests, and real-time status trackers.
*   **Phase 5: Real-Time Messaging Integration** — **[NOT STARTED]**
    *   *Planned*: WebSocket client managers and REST chat history sync.
*   **Phase 6: Server-Sent Events Notifications** — **[NOT STARTED]**
    *   *Planned*: SSE subscriber services and in-app popup notifications.
*   **Phase 7: Ratings & Subscriptions (Final Polish)** — **[NOT STARTED]**
    *   *Planned*: Subscription checkout forms, BLIND rating forms, and averages display.

---

## Verified Capabilities
*   **Owner/Customer Signup**: Sends email/password/role parameters to backend. Returns `dev_otp` in development.
*   **2FA OTP Verification**: Validates 4-digit code and securely stores signed JWT session details.
*   **Employee Direct Authentication**: Logs in directly bypassing 2FA.
*   **Dashboard KYC Banner**: Renders alert banner to Owners when `kyc_status` is `pending_super_admin_approval`.

## File Tracking Index

The following Dart implementation files are currently active in the codebase and tracked by the structural drift check:
* **Models**:
  * `user_profile.dart`
* **Theme**:
  * `theme.dart`
* **Providers**:
  * `auth_provider.dart`
  * `owner_provider.dart`
* **Screens**:
  * `employee_screen.dart`
  * `home_screen.dart`
  * `login_screen.dart`
  * `otp_screen.dart`
  * `service_screen.dart`
  * `signup_screen.dart`
  * `wallet_screen.dart`
