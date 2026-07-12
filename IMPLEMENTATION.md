# Frontend Implementation Plan: saas-core Marketplace

This document details the step-by-step implementation plan for the Flutter frontend client. To ensure stability and ease of integration, features are built sequentially.

---

## Implementation Sequence

We will proceed in the following order:

```
[Phase 1: Project Setup & Auth] -> [Phase 2: Owner Core] -> [Phase 3: Employee Core] -> [Phase 4: Customer Flow] -> [Phase 5: Real-time Chat] -> [Phase 6: SSE Notifications] -> [Phase 7: Ratings & Subscriptions]
```

---

## Phase 1: Project Setup & Shared Auth Flow

1.  **Initialize Flutter App**:
    *   Create directory `frontend` and initialize Flutter.
    *   Configure dependencies in `pubspec.yaml`:
        ```yaml
        dependencies:
          flutter:
            sdk: flutter
          provider: ^6.1.5
          http: ^1.6.0
          web_socket_channel: ^2.4.5
          flutter_client_sse: ^1.0.0
        ```

2.  **Base Networking Client**:
    *   Implement [ApiClient](DESIGN.md#1-core-architecture) in `lib/core/api_client.dart` with header interceptors injecting query parameter tokens/headers for the microservices.

3.  **Auth State Store**:
    *   Create `AuthProvider` in `lib/providers/auth_provider.dart` to manage the currently authenticated user's profile, role, and active session.

4.  **Register / Login Screens**:
    *   **Signup Page**: Role selection (Owner or Customer). If Employee signup, Owner must trigger it through the Employee Management screen (passing owner's tenant binding). Sends request to [Signup Endpoint](services/auth-service/internal/handlers/auth.go#L115).
    *   **Login Page**: E-mail and password credentials. Sends request to [Login Endpoint](services/auth-service/internal/handlers/auth.go#L269).
    *   **OTP Page**: Prompts user for a 4-digit code. In development, auto-populates/displays the `dev_otp` returned by the server. Sends to [Verify OTP Endpoint](services/auth-service/internal/handlers/auth.go#L413).
    *   **KYC Banner (Owner only)**: Displays a banner at the top of the owner dashboard indicating "KYC Pending Approval" if `kyc_status == "pending_super_admin_approval"`.

---

## Phase 2: Owner Core Functionality

1.  **Dashboard Layout**:
    *   Grid view containing wallet balance, current subscription status (Free/Paid), employee counts, and active jobs list.

2.  **Wallet Management**:
    *   Visual representation of balance and transactions history from [GetWallet](services/user-service/internal/handlers/handlers.go#L561) and [GetLedger](services/user-service/internal/handlers/handlers.go#L680).
    *   Deposit dialog calling [WalletDeposit](services/user-service/internal/handlers/handlers.go#L589) (requires approved KYC).

3.  **Employee Management**:
    *   Register new employee (automates password generation and sets current tenant ID binding).
    *   Freeze / Activate toggle invoking [ToggleEmployee](services/auth-service/internal/handlers/auth.go#L505).
    *   Audit Log list calling [GetAuditLog](services/auth-service/internal/handlers/auth.go#L786).

4.  **Service Directory Configuration**:
    *   Add service (category choice of `shipping`, `delivery`, `transport`, coordinates, rates) calling [CreateService](services/user-service/internal/handlers/handlers.go#L147). Gated by KYC.

---

## Phase 3: Employee Dashboard & Audit Simulator

1.  **Job Assignment List**:
    *   Retrieve all jobs assigned to the current employee.
    *   Job detail card showing destination coordinates, customer information, status (Pending / Active / Completed).

2.  **Employee Action Simulator**:
    *   Text field and action button allowing employees to execute a task (e.g., "Arrived at Pickup", "Job in Route").
    *   Calls [SimulateEmployeeAction](services/auth-service/internal/handlers/auth.go#L617) to log employee actions into the tenant audit trail. Blocks operations if employee's status is frozen or owner KYC is not approved.

---

## Phase 4: Customer Directory & Job Booking Flow

1.  **Marketplace Directory**:
    *   Map and list views querying services near a custom latitude/longitude coordinate.
    *   Sort and filter selectors (by base price, category) calling [ListServices](services/user-service/internal/handlers/handlers.go#L126).

2.  **Booking Workflow (COD Only)**:
    *   Book service button.
    *   Forced payment method selection: "Cash on Delivery (COD)" only. Clarifies that escrow payments are currently deferred.
    *   Creates job by calling [TrackJob](services/user-service/internal/handlers/handlers.go#L210).

3.  **Real-Time Status Screen**:
    *   Visual progress indicator (Pending -> Active -> Completed) linking directly to live job updates.

---

## Phase 5: Real-Time Messaging Integration

1.  **WebSocket Manager**:
    *   `ChatProvider` in `lib/providers/chat_provider.dart` to handle socket connection/reconnection events pointing to [HandleWebSocket](services/chat-service/internal/handlers/chat.go#L204).

2.  **REST History Sync**:
    *   Loads prior message history on screen initialization calling [GetHistory](services/chat-service/internal/handlers/chat.go#L288).

3.  **WebSocket Actions**:
    *   On connection: sends subscribe frame `{"action":"subscribe", "channel":"job:<job_id>"}`.
    *   Message input: sends payload `{"action":"message", "channel":"job:<job_id>", "content":"..."}`.
    *   Listen stream updates and appends to visual chat room logs.

---

## Phase 6: Server-Sent Events Notifications

1.  **SSE Subscriber Service**:
    *   `SseProvider` in `lib/providers/sse_provider.dart` using the `flutter_client_sse` library to initialize connection to [Stream](services/notification-service/internal/handlers/handlers.go#L76).

2.  **In-App Alerts Overlay**:
    *   Main App wrapper listens to the notification streams and displays transient overlay pop-up snackbars or banners when a new job alert or status change is broadcast by the server.

---

## Phase 7: Ratings & Subscriptions (Final Polish)

1.  **Upgrade Page**:
    *   "Upgrade to Paid" tier button on the Owner dashboard.
    *   Submits subscription change request via [Subscription POST](services/user-service/internal/handlers/handlers.go#L848).
    *   Honest pending payment screen display informing owner to contact platform administrators for manual processing (no simulated fake checkouts).

2.  **Job Rating Forms**:
    *   On job completion (where COD cash has been confirmed by Owner), prompts a rating screen.
    *   Owner rates Employee and Employee rates Owner via [RateJob](services/user-service/internal/handlers/handlers.go#L981).
    *   Display averages using [GetRatings](services/user-service/internal/handlers/handlers.go#L1068).

---

## Verification & Validation Plan

*   **API URL Setup**: Set `http://localhost:8080` (API Gateway) as base client target.
*   **Audit logs check**: Log in as Owner and verify employee toggles trigger audit log insertions in real-time.
*   **KYC / Sub DB commands**: Use standard MongoDB scripts to approve/verify KYC states to simulate the manual out-of-band flow.
