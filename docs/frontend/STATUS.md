# Frontend Status Tracker

> [!NOTE]
> This is a lean tracker mapping the current implementation state of the Flutter frontend application. For the complete step-by-step roadmap, consult [IMPLEMENTATION.md](../../IMPLEMENTATION.md).

---

## Phase Progress (Per IMPLEMENTATION.md Sequence)

*   **Phase 1: Project Setup & Shared Auth Flow** — **[100% COMPLETE & VERIFIED]**
    *   *Auth Flow Logic*: **[VERIFIED]** contract-matching works against the live docker-compose backend for signup, 2FA OTP, direct employee login, and KYC dashboard warning banners.
    *   *Platform Builds*:
        *   *Android*: **[VERIFIED]** successfully compiled debug APK using local Adoptium JDK 17 and Android SDK platforms-36/build-tools-34. Output location: `frontend/build/app/outputs/flutter-apk/app-debug.apk` (Size: 153,369,344 bytes).
        *   *iOS*: **[UNVERIFIED]** macOS/Xcode toolchain unavailable (build execution requires a Mac environment).
*   **Phase 2: Owner Core Functionality** — **[IN PROGRESS]**
    *   *Dashboard Layout*: **[VERIFIED]** Owner dashboard metrics grid displays wallet balance (via GetWallet) and subscription status (via Subscription) with active jobs placeholder layout. Confirmed working end-to-end against live docker-compose backend using real signed owner JWT token resolve logic.
    *   *Wallet Management*: **[VERIFIED]** Balance display (total, withdrawable, escrow), reverse-chronological transaction ledger, and deposit dialog with inline error notice for production environment gating. Verified end-to-end against live backend with local/production environment check.
    *   *Employee Management*: **[NOT STARTED]** Registration, toggling (freeze/activate), and audit logs.
    *   *Service Directory Configuration*: **[NOT STARTED]** KYC-gated service creation form.
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
