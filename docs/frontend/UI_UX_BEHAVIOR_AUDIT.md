# Frontend UI/UX Behavior & Interaction Audit

> **Date**: September 19, 2026  
> **Status**: PART A, BATCH 1 & BATCH 2 REMEDIATED & VERIFIED (Batches 3–5 Pending)  
> **Scope**: All 30 screens (29 production screens + 1 debug catalog) in [`frontend/lib/screens/`](../../frontend/lib/screens/) across all 3 user roles (Customer, Owner, Employee).  
> **Preceding Audits**: [`FRONTEND_CONSISTENCY_AUDIT.md`](../FRONTEND_CONSISTENCY_AUDIT.md) (Design Token Consistency — 100% Landed) and [`STITCH_VISUAL_AUDIT_V2.md`](STITCH_VISUAL_AUDIT_V2.md) (Design Brief Fidelity).  

---

## 1. Executive Summary

A comprehensive behavioral and interaction audit was performed across all 30 screens and shared interaction widgets in the Quick Delivery (SaaS Prototype) Flutter application.

While prior audits strictly evaluated static visual styling, design token compliance (`AppColors`, `AppSpacing`, `AppTypography`), and Stitch visual fidelity, this audit focuses on **live runtime behavior, navigation mechanics, state synchronization, edge cases, and user ergonomics**. The goal is identifying subtle UX-breaking bugs, dead ends, unhandled race conditions, silent failures, and missing confirmation safeguards that pass static unit and widget tests but degrade real-world usability.

### Summary Metrics & Remediation Status

* **Total Screens Audited**: 30 (29 production screens + `ComponentLibraryScreen`)
* **Total User Roles Evaluated**: 3 (Customer, Owner/Tenant, Employee/Courier)
* **Part A Manual Findings (A1–A4)**: 4 / 4 **Resolved & Verified** ✅
* **Audit Roadmap Findings (26 total)**:
  * **Batch 1 (Navigation Traps & High-Severity Role Gating)**: 4 / 4 **Resolved & Verified** ✅ (`C-01`, `O-01`, `E-01`, `O-02`)
  * **Batch 2 (Customer Job Lifecycle & Real-Time Interaction)**: 6 / 6 **Resolved & Verified** ✅ (`C-04`, `C-05`, `C-06`, `C-07`, `C-02`, `C-03`)
  * **Batches 3–5**: 16 findings planned for subsequent execution
* **Test Verification**: 547 / 547 Flutter tests passing, `flutter analyze` 0 issues, Go microservice test suites 100% green.

---

## 2. Part A — Manual Testing UX Issues (Remediated)

Four high-friction UX issues identified during manual end-to-end testing were investigated, diagnosed against code, and resolved:

### Finding A1: Area-Name Search Box Visual Overflow & Tab Redirection
* **Reported Behavior**: Area search box text overflows visually; tapping it redirects to the wrong screen ("service screen").
* **Live Reproduction Evidence (Diagnose-First)**:
  - Located widget at `customer_home_screen.dart:383-418` (`InkWell(key: Key('home_quick_search_card'))`).
  - Tapping this card previously executed `onTap: widget.onGoToServices`, which switched the tab shell to Tab 1 (`CustomerMarketplaceScreen`, aka "Services"). Users expected an area search/location input rather than an abrupt tab transition.
  - Furthermore, `customerHomeSearchHint` ("Enter destination or pickup area...") lacked `maxLines: 1` and `overflow: TextOverflow.ellipsis`. On narrow viewports (320–360dp) or long localized strings (Arabic), the hint wrapped onto two lines, pushing down screen contents by 16px and clipping child layouts.
* **Remediation**:
  - Tapping the search box now opens `Dialog(key: Key('home_search_location_picker_dialog'))` allowing the customer to select a delivery/pickup location on `LocationPickerMap` or confirm their location.
  - Selecting and confirming a location invokes `_navigateToServicesWithLocation(lat, lon)`, switching to the Services tab with customer coordinates populated so nearby services calculate accurate proximity and pricing.
  - Added `maxLines: 1` and `overflow: TextOverflow.ellipsis` to the hint text in `customer_home_screen.dart`.
  - Verified via `frontend/test/a1_diagnosis_test.dart` (2/2 passing).

### Finding A2: Map Not Centered on User Location & Missing "Use Current Location" Action
* **Reported Behavior**: Map is not centered on the customer's current location when booking, and there is no one-tap button to use current GPS.
* **Remediation**:
  - In `CustomerMarketplaceScreen`: Added `_initLocation()` on mount to request location permissions and retrieve the user's current GPS position via `Geolocator.getCurrentPosition()`, falling back gracefully to Cairo coordinates (`30.0444, 31.2357`).
  - Added `setCustomerLocation(double lat, double lon)` to update search and booking coordinates.
  - In `_BookingDialog`: Centered `LocationPickerMap` on the active pickup coordinates (`_pickupLat, _pickupLon`).
  - Added a dedicated "Use current location" button (`Key('use_current_location_pickup_button')`) in the pickup location section allowing one-tap GPS coordinate assignment.
  - Verified via `flutter test test/customer_marketplace_screen_test.dart`.

### Finding A3: Missing Two-Factor Authentication (2FA) Enable/Disable Option
* **Reported Behavior**: Users cannot choose whether to enforce 2FA OTP verification upon login.
* **Remediation**:
  - **Backend (`auth-service`)**: Added `TwoFactorEnabled *bool` to `models.User` (defaults to `true` via `Is2FAEnabled()`). Updated `Login` to check `user.Is2FAEnabled()`; if disabled, login immediately issues JWT session tokens without an OTP challenge. Updated `UpdateProfile` to accept and persist `two_factor_enabled` patches. Verified via `go test ./...`.
  - **Frontend**: Added `twoFactorEnabled` to `UserProfile`, `updateOwnProfile`, and implemented `AuthProvider.toggleTwoFactor(bool enabled)`.
  - **Settings Screen**: Added a new "Security" card with `Key('settings_two_factor_switch')`.
  - **Product Safeguard**: Disabling 2FA prompts a confirmation dialog (`ConfirmActionDialog`, `disableTwoFactorConfirmTitle`) warning the user about reduced account security before applying the change. Toggling on activates immediately.
  - Verified via `gap05_account_status_test.dart`, `my_account_screen_test.dart`, and `golden_screens_test.dart`.

### Finding A4: Ticket Chat Username Truncation & Support Agent Privacy
* **Reported Behavior**: Long sender usernames overflow chat bubble headers; customer sees reviewer internal identity.
* **Remediation**:
  - **Frontend (`ticket_chat_screen.dart`)**: Added `maxLines: 1, overflow: TextOverflow.ellipsis` to sender username labels, preventing layout overflow on lengthy names.
  - **Backend (`chat-service`)**: In `chat.go`, updated WebSocket message dispatch on `ticket:` channels: if the sender is not the ticket's customer (`msg.SenderID != ticket.CustomerID`), the outgoing payload masks `SenderUsername` to `"Support Team"`, shielding internal reviewer names while preserving customer usernames.
  - Verified via Go unit test `TestTicketChatMessageMasking` in `chat_test.go` and `ticket_chat_screen_test.dart`.

---

## 3. Definitive Confirmation on Screen Duplication

### Historical Question: Was `service_screen.dart` / `owner_configuration_screen.dart` Resolved?

**YES, DEFINITIVELY RESOLVED.**

During early iterations of Phase 26, two overlapping screens existed for service management:
1. `service_screen.dart` (along with `create_service_dialog.dart`) — An older CRUD interface for owner services.
2. `owner_configuration_screen.dart` — A comprehensive business onboarding and service configuration screen.

#### Git Verification & Timeline
* In commit [`a486414e4316391bb40201415d20658222a37c48`](https://github.com/omarmaarouf18/saas-core/commit/a486414e4316391bb40201415d20658222a37c48) titled *"refactor(frontend): consolidate owner service creation into OwnerConfigurationScreen and delete ServiceScreen"*, dated August 29, 2026:
  * [`frontend/lib/screens/service_screen.dart`](../../frontend/lib/screens/) was **deleted** (387 lines removed).
  * [`frontend/lib/widgets/create_service_dialog.dart`](../../frontend/lib/widgets/) was **deleted** (276 lines removed).
  * All service creation, pricing, category assignment, and coverage radius configuration logic was consolidated into [`OwnerConfigurationScreen`](../../frontend/lib/screens/owner_configuration_screen.dart).
* A full repository search confirms **zero remaining references** or import statements to `service_screen.dart` or `create_service_dialog.dart` anywhere in `frontend/`.

---

## 3. Scope and Inventory of Audited Screens

The 30 screens evaluated in this audit span authentication, role-specific operational hubs, shared settings, and debug infrastructure:

### Customer Experience (12 Screens)
1. [`signup_screen.dart`](../../frontend/lib/screens/signup_screen.dart) — Customer registration with role selector
2. [`login_screen.dart`](../../frontend/lib/screens/login_screen.dart) — Unified credential entry
3. [`otp_screen.dart`](../../frontend/lib/screens/otp_screen.dart) — 6-digit MFA verification
4. [`customer_home_screen.dart`](../../frontend/lib/screens/customer_home_screen.dart) — Main customer hub (Active jobs banner, service categories, bottom nav shell)
5. [`customer_marketplace_screen.dart`](../../frontend/lib/screens/customer_marketplace_screen.dart) — Service discovery, category filtering, search, and booking modal
6. [`job_status_screen.dart`](../../frontend/lib/screens/job_status_screen.dart) — Live tracking, status stepper, counter-offer negotiation, cancellation
7. [`chat_screen.dart`](../../frontend/lib/screens/chat_screen.dart) — Real-time customer-to-courier messaging
8. [`rating_screen.dart`](../../frontend/lib/screens/rating_screen.dart) — Dual-blind 5-star rating and review submission
9. [`customer_jobs_screen.dart`](../../frontend/lib/screens/customer_jobs_screen.dart) — Order history and active order monitoring
10. [`customer_tickets_screen.dart`](../../frontend/lib/screens/customer_tickets_screen.dart) — Support ticket list and creation
11. [`ticket_chat_screen.dart`](../../frontend/lib/screens/ticket_chat_screen.dart) — Live support agent conversation
12. [`my_account_screen.dart`](../../frontend/lib/screens/my_account_screen.dart) — Profile, phone number, address management, email change

### Owner / Business Operations (11 Screens)
13. [`home_screen.dart`](../../frontend/lib/screens/home_screen.dart) — Owner dashboard (Metric cards, active fleet count, revenue summary)
14. [`kyc_document_upload_screen.dart`](../../frontend/lib/screens/kyc_document_upload_screen.dart) — Commercial register and ID card image uploads
15. [`subscription_screen.dart`](../../frontend/lib/screens/subscription_screen.dart) — SaaS tier comparison, upgrade actions, feature matrix
16. [`owner_configuration_screen.dart`](../../frontend/lib/screens/owner_configuration_screen.dart) — Business profile, service catalog, pricing rules, coverage map
17. [`employee_screen.dart`](../../frontend/lib/screens/employee_screen.dart) — Worker roster, invitation form, freeze/unfreeze actions, audit trail
18. [`owner_fleet_map_screen.dart`](../../frontend/lib/screens/owner_fleet_map_screen.dart) — Live GPS fleet tracking map, driver status markers
19. [`wallet_screen.dart`](../../frontend/lib/screens/wallet_screen.dart) — Ledger balance, credit transactions, deposit & payout history
20. [`owner_reconciliation_queue_screen.dart`](../../frontend/lib/screens/owner_reconciliation_queue_screen.dart) — Discrepancy queue, manual ledger adjustments
21. [`owner_history_screen.dart`](../../frontend/lib/screens/owner_history_screen.dart) — Historical order archive with multi-tier status filters
22. [`deposit_funds_dialog.dart`](../../frontend/lib/widgets/deposit_funds_dialog.dart) — In-app wallet deposit flow
23. [`payout_request_dialog.dart`](../../frontend/lib/widgets/payout_request_dialog.dart) — Bank / InstaPay payout submission

### Employee / Courier Experience (5 Screens)
24. [`employee_home_screen.dart`](../../frontend/lib/screens/employee_home_screen.dart) — Shift metrics, earnings summary, recent jobs
25. [`employee_jobs_screen.dart`](../../frontend/lib/screens/employee_jobs_screen.dart) — Online/offline toggle, incoming dispatch offers, active job route
26. [`employee_history_screen.dart`](../../frontend/lib/screens/employee_history_screen.dart) — Completed jobs archive with fare and route timeline
27. [`employee_screen.dart`](../../frontend/lib/screens/employee_screen.dart) — Shared worker directory view
28. [`notifications_screen.dart`](../../frontend/lib/screens/notifications_screen.dart) — Dispatch alerts, job offers, system messages

### Cross-Cutting & Debug (2 Screens)
29. [`settings_screen.dart`](../../frontend/lib/screens/settings_screen.dart) — Language selection, theme toggle, session termination
30. [`component_library_screen.dart`](../../frontend/lib/screens/component_library_screen.dart) — Design system showcase & token verification

---

## 4. Comprehensive Findings Matrix

| Finding ID | Status | Screen / Component | Role | Severity | Flaw Category | UX Impact Summary | Target Code Location |
| :--- | :---: | :--- | :--- | :---: | :--- | :--- | :--- |
| **C-01** | ✅ Resolved | `CustomerJobsScreen` | Customer | **High** | Navigation Trap | "Browse Services" button in empty state calls `pop()`, exiting the app when embedded in home tab shell. | [`customer_jobs_screen.dart:165`](../../frontend/lib/screens/customer_jobs_screen.dart#L165) |
| **C-02** | ✅ Resolved | `CustomerMarketplaceScreen` | Customer | **Low** | Stale Data | Courier availability and service list are not refreshed upon returning from a completed booking flow. | [`customer_marketplace_screen.dart:800-808`](../../frontend/lib/screens/customer_marketplace_screen.dart#L800-L808) |
| **C-03** | ✅ Resolved | `CustomerMarketplaceScreen` | Customer | **Low** | Localization | Hardcoded `$` currency prefix in `_BookingDialog` estimated price conflicts with Egyptian `EGP` locale. | [`customer_marketplace_screen.dart:1006`](../../frontend/lib/screens/customer_marketplace_screen.dart#L1006) |
| **C-04** | ✅ Resolved | `JobStatusScreen` / `RatingScreen` | Customer | **High** | State Leak / 400 Error | "Rate Your Experience" button remains active after rating; tapping again causes a 400 Bad Request error. | [`job_status_screen.dart:1173-1185`](../../frontend/lib/screens/job_status_screen.dart#L1173-L1185) |
| **C-05** | ✅ Resolved | `TicketChatScreen` | Customer | **High** | Race Condition | Concurrent fetch of history and WebSocket subscribe in `initState` wipes live incoming messages on load. | [`ticket_chat_screen.dart:55-57`](../../frontend/lib/screens/ticket_chat_screen.dart#L55-L57) |
| **C-06** | ✅ Resolved | `TicketChatScreen` | Customer | **Medium** | Silent Failure | Ticket message send failures are silently caught and printed to debug console without notifying the user. | [`ticket_chat_screen.dart:99-106`](../../frontend/lib/screens/ticket_chat_screen.dart#L99-L106) |
| **C-07** | ✅ Resolved | `CustomerTicketsScreen` | Customer | **Medium** | Stale List | Navigating into ticket chat does not refresh the ticket list on pop; resolved tickets continue to show as "Pending". | [`customer_tickets_screen.dart:159-164`](../../frontend/lib/screens/customer_tickets_screen.dart#L159-L164) |
| **C-08** | Open | `MyAccountScreen` | Customer | **Medium** | Data Loss | Typing a new frequent address and clicking "Save Changes" discards the typed address without "+ Add". | [`my_account_screen.dart:109-137`](../../frontend/lib/screens/my_account_screen.dart#L109-L137) |
| **C-09** | Open | `MyAccountScreen` | Customer | **High** | Stale Profile | Completing an email change does not update `_emailController.text`, permanently displaying the old email. | [`my_account_screen.dart:655-657`](../../frontend/lib/screens/my_account_screen.dart#L655-L657) |
| **C-10** | Open | `EmailChangeDialog` | Customer | **Low** | Redundant Request | Submitting the current existing email address is not blocked client-side before sending an API request. | [`email_change_dialog.dart:45-55`](../../frontend/lib/widgets/email_change_dialog.dart#L45-L55) |
| **C-11** | Open | `SettingsScreen` | Common | **Medium** | Destructive Action | Tapping "Logout" immediately clears authentication and destroys session without confirmation dialog. | [`settings_screen.dart:438-446`](../../frontend/lib/screens/settings_screen.dart#L438-L446) |
| **O-01** | ✅ Resolved | `EmployeeScreen` | Owner | **Critical** | Broken Navigation | "Add Worker" empty state button calls `animateTo(1)`, navigating to Audit Trail instead of registration. | [`employee_screen.dart:288-295`](../../frontend/lib/screens/employee_screen.dart#L288-L295) |
| **O-02** | ✅ Resolved | `HomeScreen` | Owner | **High** | Gating Blindness | Owner Dashboard has zero mention of KYC verification; owners cannot see why services cannot receive orders. | [`home_screen.dart`](../../frontend/lib/screens/home_screen.dart) |
| **O-03** | Open | `OwnerConfigurationScreen` | Owner | **High** | Gating Blindness | Unverified or free-tier owners can enter full business details only to hit 403 or 402 on final save. | [`owner_configuration_screen.dart:382, 919`](../../frontend/lib/screens/owner_configuration_screen.dart#L382) |
| **O-04** | Open | `OwnerConfigurationScreen` | Owner | **Medium** | Data Truncation | Creating a new service drops `description`, `coverageRadiusKm`, `photoUrl`, `address`, and `workingHours`. | [`owner_configuration_screen.dart:299-307`](../../frontend/lib/screens/owner_configuration_screen.dart#L299-L307) |
| **O-05** | Open | `EmployeeScreen` | Owner | **Medium** | Poor Ergonomics | Worker roster cards cannot be tapped to select or freeze; owner must manually re-type email into bottom form. | [`employee_screen.dart:348-385, 555-640`](../../frontend/lib/screens/employee_screen.dart#L348-L385) |
| **O-06** | Open | `WalletScreen` | Owner | **Low** | Timezone Display | Payout history timestamps format raw UTC `createdAt` without `.toLocal()`, displaying times 2–3 hours behind. | [`wallet_screen.dart:421-423`](../../frontend/lib/screens/wallet_screen.dart#L421-L423) |
| **O-07** | Open | `PayoutRequestDialog` | Owner | **Medium** | Stale Ledger | Submitting a payout request refreshes balance dashboard but fails to refresh payout history list. | [`payout_request_dialog.dart:74-76`](../../frontend/lib/widgets/payout_request_dialog.dart#L74-L76) |
| **E-01** | ✅ Resolved | `NotificationsScreen` | Employee | **Critical** | Dead End Navigation | Tapping `job_offer`, `job_completed`, or `kyc_*` notifications marks as read but does not navigate anywhere. | [`notifications_screen.dart:87-123`](../../frontend/lib/screens/notifications_screen.dart#L87-L123) |
| **E-02** | Open | `NotificationsScreen` | Employee | **Medium** | Copy Defect | Empty state displays identical title and description ("Notifications" / "Notifications"). | [`notifications_screen.dart:231-236`](../../frontend/lib/screens/notifications_screen.dart#L231-L236) |
| **E-03** | Open | `EmployeeJobsScreen` | Employee | **Medium** | Misleading Toast | Accepting or declining a job offer displays raw status labels ("Active" / "Decline Offer") in snackbars. | [`employee_jobs_screen.dart:917, 923`](../../frontend/lib/screens/employee_jobs_screen.dart#L917) |
| **E-04** | Open | `EmployeeJobsScreen` / `History` | Employee | **Medium** | Semantic Misuse | `RouteTimeline` `distanceText:` receives `lockedEscrowAmount`, rendering "50 Credits" next to the distance road icon. | [`employee_jobs_screen.dart:995-998`](../../frontend/lib/screens/employee_jobs_screen.dart#L995-L998) |
| **E-05** | Open | `EmployeeJobsScreen` | Employee | **Medium** | Missing Debounce | Courier online/offline `Switch.adaptive` lacks debounce protection, allowing rapid toggling network spam. | [`employee_jobs_screen.dart:523-535`](../../frontend/lib/screens/employee_jobs_screen.dart#L523-L535) |
| **X-01** | Open | `Chat` / `JobStatus` / `TicketChat` | Cross | **Low** | Design Token | Raw `CircularProgressIndicator` used instead of canonical `ThemedLoadingIndicator`. | [`chat_screen.dart:154`](../../frontend/lib/screens/chat_screen.dart#L154) |
| **X-02** | Open | `PrimaryButton` | Cross | **Medium** | RTL Directionality | Forward arrow trailing icon (`Icons.arrow_forward`) does not mirror in RTL mode, pointing backward in Arabic. | [`primary_button.dart:110`](../../frontend/lib/widgets/primary_button.dart#L110) |
| **X-03** | Open | Map Controls & Modals | Cross | **Low** | Touch Target | Compact 24-32dp visual touch frames in map overlay buttons fall below standard 48dp guidelines. | [`customer_job_map.dart:180-220`](../../frontend/lib/widgets/customer_job_map.dart#L180-L220) |

---

## 5. Detailed Findings & Root Cause Analysis

### 5.1 Customer Journey Findings

#### Finding C-01: Empty State "Browse Services" Pops App Shell
* **Severity**: High
* **Category**: Navigation Trap
* **File & Lines**: [`customer_jobs_screen.dart:165`](../../frontend/lib/screens/customer_jobs_screen.dart#L165)
* **User Symptom**: A customer navigating to their "My Jobs" tab when they have no orders sees an empty state card with a "Browse Services" button. Tapping this button immediately closes the application or pops the main navigation shell, kicking the user out of the app.
* **Root Cause**: The empty state handler executes `onActionPressed: () => Navigator.pop(context)`. When `CustomerJobsScreen` is pushed as a standalone route, `pop()` works; however, when embedded as Tab 2 within [`CustomerHomeScreen`](../../frontend/lib/screens/customer_home_screen.dart), calling `pop()` on the root shell pops the entire screen from the navigator stack.
* **Remediation**: Check `Navigator.canPop(context)`. If embedded in the tab shell, invoke the tab switcher callback (`onNavigateToTab(1)`) or push `CustomerMarketplaceScreen`.

#### Finding C-02: Stale Marketplace Services After Returning from Booking Flow
* **Severity**: Low
* **Category**: Stale Catalog State
* **File & Lines**: [`customer_marketplace_screen.dart:800-808`](../../frontend/lib/screens/customer_marketplace_screen.dart#L800-L808)
* **User Symptom**: After successfully placing a booking and tracking it on `JobStatusScreen`, navigating back to the Marketplace leaves the courier list in a stale state.
* **Root Cause**: The route push to `JobStatusScreen` is not awaited with a subsequent `_loadServices()` invocation on completion.
* **Remediation**: Await the navigation future: `await Navigator.push(...); if (mounted) _loadServices();`.

#### Finding C-03: Hardcoded Dollar Currency Symbol in Booking Dialog
* **Severity**: Low
* **Category**: Hardcoded String / Localization Defect
* **File & Lines**: [`customer_marketplace_screen.dart:1006`](../../frontend/lib/screens/customer_marketplace_screen.dart#L1006)
* **User Symptom**: During the booking confirmation step, the estimated price displays as `"\$${estimate}"` instead of adhering to the Egyptian Pound (`EGP`) currency locale.
* **Root Cause**: String interpolation directly prefixes `"\$"` instead of consuming `l10n.priceInEgp` or `l10n.ownerHomeCreditsAmount`.
* **Remediation**: Use `l10n.creditsAmountLine(...)` or localized currency formatting.

#### Finding C-04: Rating Screen Duplicate Submission & Bad Request Error
* **Severity**: High
* **Category**: State Leak / Unhandled Error
* **File & Lines**: [`job_status_screen.dart:1173-1185`](../../frontend/lib/screens/job_status_screen.dart#L1173-L1185) vs [`rating_screen.dart:132-160`](../../frontend/lib/screens/rating_screen.dart#L132-L160)
* **User Symptom**: After rating a delivered order and returning to `JobStatusScreen`, the "Rate Your Experience" button remains prominently visible. Tapping it re-opens `RatingScreen`, allowing the user to submit a second review, which immediately fails with a `400 Bad Request` snackbar.
* **Root Cause**: `JobStatusScreen` does not persist or observe `_hasRated` state locally. When `RatingScreen` pops with `Navigator.pop(context, true)`, the result is discarded. Furthermore, `RatingScreen` does not verify whether the current user has already submitted a rating for this job on `initState`.
* **Remediation**: Await `Navigator.push(...)` in `JobStatusScreen`. If `true` is returned, update local state to hide the button and show a "Rating Submitted" badge. Add an upfront check in `RatingScreen` to disable submission if `job.hasRated == true`.

#### Finding C-05: Real-Time Race Condition in Ticket Chat Screen Load
* **Severity**: High
* **Category**: Race Condition / Message Loss
* **File & Lines**: [`ticket_chat_screen.dart:55-57`](../../frontend/lib/screens/ticket_chat_screen.dart#L55-L57)
* **User Symptom**: When opening a support ticket, messages sent by an agent while the screen is loading occasionally vanish from the conversation view.
* **Root Cause**: In `initState`, `chat.fetchChannelHistory(...)` and `chat.connectAndSubscribeChannel(...)` are fired concurrently without awaiting. In `ChatProvider`, `fetchChannelHistory` resets `_messages = []` upon completion. If the WebSocket subscription receives an incoming message before the HTTP history response finishes, the HTTP handler wipes the incoming message.
* **Remediation**: Await `fetchChannelHistory` before invoking `connectAndSubscribeChannel`, or deduplicate messages by ID in `ChatProvider`.

#### Finding C-06: Silent Message Send Failure in Support Ticket Chat
* **Severity**: Medium
* **Category**: Error Handling / Silent Failure
* **File & Lines**: [`ticket_chat_screen.dart:99-106`](../../frontend/lib/screens/ticket_chat_screen.dart#L99-L106)
* **User Symptom**: If network connectivity drops while sending a message in ticket chat, the input field remains disabled or clears without any feedback, leaving the user unaware of the failure.
* **Root Cause**: The `try/catch` block inside `_sendMessage()` catches the exception and only executes `debugPrint('Error sending ticket message: $e')`.
* **Remediation**: Display `ThemedSnackBar.showError(context, friendlyErrorMessage(e))` and retain the typed text in `_messageController` so the user can retry.

#### Finding C-07: Stale Ticket Status on Return to Tickets List
* **Severity**: Medium
* **Category**: Stale State Synchronization
* **File & Lines**: [`customer_tickets_screen.dart:159-164`](../../frontend/lib/screens/customer_tickets_screen.dart#L159-L164)
* **User Symptom**: A customer enters a support ticket, resolves the issue with an agent, and navigates back to the tickets list. The ticket card still displays as "Pending" or "Open" until the user manually triggers pull-to-refresh.
* **Root Cause**: The tap handler executes `Navigator.push(...)` without awaiting or attaching a `.then((_) => _loadTickets())` callback.
* **Remediation**: Await the navigation route and call `_loadTickets()` upon returning.

#### Finding C-08: Silent Discard of Typed Frequent Address on Save
* **Severity**: Medium
* **Category**: Form Data Loss
* **File & Lines**: [`my_account_screen.dart:109-137`](../../frontend/lib/screens/my_account_screen.dart#L109-L137)
* **User Symptom**: A user types a new frequent address into the address field and clicks the primary "Save Changes" button at the bottom of the screen. The screen saves, but the typed address is completely discarded because the user forgot to tap the small "+ Add" icon button.
* **Root Cause**: `_submitForm()` only serializes the `_frequentAddresses` array. It does not check whether `_addressController.text.trim()` contains un-added text.
* **Remediation**: Inside `_submitForm()`, if `_addressController.text.trim().isNotEmpty`, automatically append it to `_frequentAddresses` before executing the profile update.

#### Finding C-09: Stale Email Display After Successful Email Change
* **Severity**: High
* **Category**: Stale Account State
* **File & Lines**: [`my_account_screen.dart:655-657`](../../frontend/lib/screens/my_account_screen.dart#L655-L657)
* **User Symptom**: A customer changes their email via `EmailChangeDialog`. The dialog completes successfully, but the email field on `MyAccountScreen` continues to display the old email address indefinitely until the user completely logs out and logs back in.
* **Root Cause**: `_showEmailChangeDialog` awaits `EmailChangeDialog.show(context)` but never re-fetches the user profile or updates `_emailController.text`.
* **Remediation**: Await the dialog result; if true, call `await authProvider.fetchUserProfile()` and update `_emailController.text = authProvider.user?.email ?? ''`.

#### Finding C-10: Redundant Duplicate Email Change Submissions
* **Severity**: Low
* **Category**: Validation / Redundant API Call
* **File & Lines**: [`email_change_dialog.dart:45-55`](../../frontend/lib/widgets/email_change_dialog.dart#L45-L55)
* **User Symptom**: If a user re-enters their current email into the change email dialog and taps "Submit", the app makes an unnecessary network request to the backend.
* **Root Cause**: Lack of client-side validation comparing `newEmail == auth.user?.email`.
* **Remediation**: Add validation rule in `ThemedTextField` returning an error message if the entered email matches the current active email.

#### Finding C-11: Immediate Destructive Logout Without Confirmation
* **Severity**: Medium
* **Category**: Destructive Action Safeguard
* **File & Lines**: [`settings_screen.dart:438-446`](../../frontend/lib/screens/settings_screen.dart#L438-L446)
* **User Symptom**: Accidental tap on the "Logout" button immediately terminates the user's session and clears local auth tokens with zero confirmation or chance to cancel.
* **Root Cause**: `PrimaryButton(text: l10n.settingsLogout, onPressed: () => logoutAndClearProviders(context))` executes immediately on tap.
* **Remediation**: Show a `ThemedDialog` or confirmation modal: "Are you sure you want to log out?" with "Cancel" and "Logout" actions.

---

### 5.2 Owner Journey Findings

#### Finding O-01: Empty State "Add Worker" Action Switches to Audit Trail Tab
* **Severity**: Critical
* **Category**: Broken Navigation / Tab Index Misdirection
* **File & Lines**: [`employee_screen.dart:288-295`](../../frontend/lib/screens/employee_screen.dart#L288-L295)
* **User Symptom**: A business owner with no registered workers navigates to the "Manage Workers" tab. An empty state card appears with the action button "Add Worker". Tapping "Add Worker" abruptly switches the view to the **Audit Trail** tab instead of presenting the worker invitation/registration form.
* **Root Cause**: The empty state handler invokes `onActionPressed: () => _tabController.animateTo(1)`. Tab 0 is `Manage Workers` and Tab 1 is `Audit Trail`.
* **Remediation**: Change `onActionPressed` to scroll directly to the "Register New Worker" section within Tab 0, or open an invitation bottom sheet modal.

#### Finding O-02: Zero Visibility into KYC Verification Status on Owner Dashboard
* **Severity**: High
* **Category**: Role Gating Visibility Gap
* **File & Lines**: [`home_screen.dart`](../../frontend/lib/screens/home_screen.dart)
* **User Symptom**: A new business owner logs in and arrives at the Owner Dashboard (`HomeScreen`). The dashboard displays metric cards, active orders, and fleet statistics, but provides **zero notification or banner** that their account is unverified. The owner has no idea why incoming customer orders cannot be routed to their business.
* **Root Cause**: `HomeScreen` contains zero references, banners, or checks for `authProvider.user?.kycStatus`. KYC upload is buried under Tab 3 (Settings) -> Account.
* **Remediation**: Add a prominent `ThemedCard` / warning banner at the top of `HomeScreen` when `kycStatus != 'approved'` (e.g., "Verification Required — Upload business documents to start accepting orders"), with a direct button linking to `KycDocumentUploadScreen`.

#### Finding O-03: Owner Configuration Form Permits Submissions for Unverified / Free Tier Accounts
* **Severity**: High
* **Category**: Form Gating Blindness
* **File & Lines**: [`owner_configuration_screen.dart:382, 919`](../../frontend/lib/screens/owner_configuration_screen.dart#L382)
* **User Symptom**: An owner fills out 10+ detailed fields (business name, category, pricing, GPS coordinates, coverage radius), only to have the save button fail with a `403 Forbidden` (unverified KYC) or `402 Payment Required` (subscription limit reached) banner after submission.
* **Root Cause**: The primary save button is completely enabled and no upfront gating message warns the owner before they invest time entering configuration data.
* **Remediation**: Check `user.kycStatus` and tenant tier on `initState`. Display a descriptive informational banner at the top of the form and adjust the primary action button or disable it with clear guidance when gating criteria are not met.

#### Finding O-04: Silent Truncation of Service Fields on Initial Creation
* **Severity**: Medium
* **Category**: Data Loss / Incomplete API Parameter Binding
* **File & Lines**: [`owner_configuration_screen.dart:299-307`](../../frontend/lib/screens/owner_configuration_screen.dart#L299-L307)
* **User Symptom**: When an owner creates their initial service offering, inputs entered for `description`, `coverageRadiusKm`, `photoUrl`, `address`, and `workingHours` are completely ignored and lost upon saving.
* **Root Cause**: While `ownerProvider.updateService` passes all 12 configuration parameters, the `ownerProvider.createService` call in `_submitForm()` only passes `name`, `category`, `tenantBasePrice`, `tenantPricePerKM`, `latitude`, and `longitude`. The remaining 5 fields are omitted from the method call.
* **Remediation**: Update `ownerProvider.createService` call to include `description`, `coverageRadiusKm`, `photoUrl`, `address`, and `workingHours`.

#### Finding O-05: Absence of Tap Action on Employee Roster Cards
* **Severity**: Medium
* **Category**: Ergonomics & Manual Data Entry Burden
* **File & Lines**: [`employee_screen.dart:348-385, 555-640`](../../frontend/lib/screens/employee_screen.dart#L348-L385)
* **User Symptom**: An owner reviewing the employee list has no way to tap an employee card to freeze/unfreeze them or view their stats. The owner is forced to scroll to the very bottom of the screen, remember the employee's exact email address, and manually type it character-by-character into the freeze input field.
* **Root Cause**: Worker roster cards are rendered as inert display items without tap or long-press handlers, and the freeze form is isolated at the bottom of the page.
* **Remediation**: Add a kebab menu (`...`) or action buttons ("Freeze", "Edit", "View History") directly on each employee card that pre-fills the action modal.

#### Finding O-06: UTC Timestamp Format in Wallet Payout History
* **Severity**: Low
* **Category**: Timezone Formatting
* **File & Lines**: [`wallet_screen.dart:421-423`](../../frontend/lib/screens/wallet_screen.dart#L421-L423)
* **User Symptom**: Payout request records in the wallet ledger display timestamps in raw UTC, showing hours that are 2 to 3 hours behind the owner's actual local Egyptian time.
* **Root Cause**: `payout.createdAt` is formatted without calling `.toLocal()`.
* **Remediation**: Call `final localDate = payout.createdAt.toLocal();` before formatting `dateStr`.

#### Finding O-07: Missing Payout History Refresh on Payout Submission
* **Severity**: Medium
* **Category**: Stale Financial Ledger State
* **File & Lines**: [`payout_request_dialog.dart:74-76`](../../frontend/lib/widgets/payout_request_dialog.dart#L74-L76)
* **User Symptom**: After requesting a payout, the wallet balance decreases, but the newly submitted request does not appear in the "Payout Requests" list below until the user navigates away and returns.
* **Root Cause**: The dialog awaits `ownerProvider.fetchDashboardData(auth.token!)`, which updates balances, but fails to call `ownerProvider.fetchPayoutRequests()`.
* **Remediation**: Add `await ownerProvider.fetchPayoutRequests(auth.token!);` before closing the dialog.

---

### 5.3 Employee Journey Findings

#### Finding E-01: Dead-End Taps on Job Offer & KYC Notifications
* **Severity**: Critical
* **Category**: Dead-End Navigation
* **File & Lines**: [`notifications_screen.dart:87-123`](../../frontend/lib/screens/notifications_screen.dart#L87-L123)
* **User Symptom**: A courier receives a notification that a new dispatch offer has arrived or that their KYC documents were approved. Tapping the notification card marks it as read but performs **no navigation whatsoever**. The courier is stranded on the notification screen and must manually back out and switch tabs to find the job offer.
* **Root Cause**: `_handleCardTap` only contains navigation logic for `notif.type == 'ticket_resolved'`. Types `job_offer`, `job_completed`, `kyc_approved`, `kyc_rejected`, and `payout_processed` have zero navigation branching.
* **Remediation**: Add navigation dispatch handlers for all core notification types:
  * `job_offer` -> Navigate to `EmployeeJobsScreen`
  * `job_completed` / `job_update` -> Navigate to `JobStatusScreen`
  * `kyc_*` -> Navigate to `KycDocumentUploadScreen`
  * `payout_*` -> Navigate to `WalletScreen`

#### Finding E-02: Repetitive Title & Description in Notifications Empty State
* **Severity**: Medium
* **Category**: Copy & Localization Defect
* **File & Lines**: [`notifications_screen.dart:231-236`](../../frontend/lib/screens/notifications_screen.dart#L231-L236)
* **User Symptom**: When there are no notifications, the empty state displays:
  * Title: **"Notifications"**
  * Description: **"Notifications"**
* **Root Cause**: Both `title` and `description` parameters pass `l10n.notificationsTitle`.
* **Remediation**: Change `description` to `l10n.notificationsEmptyDescription` ("You have no notifications right now").

#### Finding E-03: Misleading Toast Copy on Job Offer Accept / Decline
* **Severity**: Medium
* **Category**: Toast Copy / User Feedback
* **File & Lines**: [`employee_jobs_screen.dart:917, 923`](../../frontend/lib/screens/employee_jobs_screen.dart#L917)
* **User Symptom**: When a courier accepts a job offer, a green snackbar pops up saying literally: **"Active"**. When declining, a warning snackbar pops up saying: **"Decline Offer"**.
* **Root Cause**: The snackbars use `l10n.statusActive` and `l10n.declineOffer` instead of dedicated confirmation strings.
* **Remediation**: Use `l10n.jobOfferAcceptedSuccess` ("Job offer accepted. Route activated.") and `l10n.jobOfferDeclinedSuccess` ("Job offer declined.").

#### Finding E-04: Escrow Credit Amount Rendered as Route Distance
* **Severity**: Medium
* **Category**: Component Misuse & Semantic Confusion
* **File & Lines**: [`employee_jobs_screen.dart:995-998`](../../frontend/lib/screens/employee_jobs_screen.dart#L995-L998) & [`employee_history_screen.dart:185`](../../frontend/lib/screens/employee_history_screen.dart#L185)
* **User Symptom**: On the courier job card, the route timeline widget displays an icon of a road/distance alongside the text **"50 Credits"** instead of the actual trip distance in kilometers.
* **Root Cause**: The `distanceText:` parameter of `RouteTimeline` is populated with `l10n.ownerHomeCreditsAmount(job.lockedEscrowAmount)`.
* **Remediation**: Pass actual distance (`"${job.tripDistanceKm ?? '--'} km"`) to `distanceText:`, and render the locked escrow / payment amount as a distinct fare badge or chip.

#### Finding E-05: Missing Debounce Protection on Courier Availability Toggle
* **Severity**: Medium
* **Category**: Rapid State Mutation / Missing Debounce
* **File & Lines**: [`employee_jobs_screen.dart:523-535`](../../frontend/lib/screens/employee_jobs_screen.dart#L523-L535)
* **User Symptom**: A courier can rapidly flip the "Online / Offline" switch, flooding the WebSocket connection and location dispatch service with contradictory state updates.
* **Root Cause**: `Switch.adaptive.onChanged` directly invokes `locationProvider.setAvailableOnline(...)` with no debounce guard or local optimistic loading state.
* **Remediation**: Wrap state change in `AppMotion.debounceGuard` (600ms) or disable the switch until the async provider response resolves.

---

### 5.4 Cross-Cutting UI/UX System Findings

#### Finding X-01: Raw CircularProgressIndicator Usages
* **Severity**: Low
* **Category**: Design Token Deviation
* **File & Lines**: [`chat_screen.dart:154`](../../frontend/lib/screens/chat_screen.dart#L154), [`job_status_screen.dart:469`](../../frontend/lib/screens/job_status_screen.dart#L469), [`ticket_chat_screen.dart:549`](../../frontend/lib/screens/ticket_chat_screen.dart#L549), [`location_picker_map.dart:155`](../../frontend/lib/widgets/location_picker_map.dart#L155)
* **User Symptom**: Inconsistent spinner stroke width and accent coloring across real-time screens.
* **Root Cause**: Unmigrated usages of raw `CircularProgressIndicator` instead of `ThemedLoadingIndicator`.
* **Remediation**: Replace with `ThemedLoadingIndicator()`.

#### Finding X-02: Forward Arrow Trailing Icons in PrimaryButton Inverted in RTL
* **Severity**: Medium
* **Category**: RTL Directionality Defect
* **File & Lines**: [`primary_button.dart:110`](../../frontend/lib/widgets/primary_button.dart#L110)
* **User Symptom**: In Arabic mode, primary CTA buttons (such as "Save Changes", "Continue", or "Rate Experience") render an arrow pointing to the right (`->`), which represents *backward* motion in right-to-left typography.
* **Root Cause**: `Icon(widget.trailingIcon)` defaults to `matchTextDirection: false` in Material `Icons.arrow_forward`.
* **Remediation**: Use `matchTextDirection: true` or wrap with directional mirroring based on `Directionality.of(context)`.

#### Finding X-03: Sub-48dp Touch Target Frames on Map Overlays
* **Severity**: Low
* **Category**: Mobile Accessibility & Touch Target Standard
* **File & Lines**: [`customer_job_map.dart:180-220`](../../frontend/lib/widgets/customer_job_map.dart#L180-L220)
* **User Symptom**: Zoom and re-center controls on mobile devices require high tap precision while in motion.
* **Root Cause**: Visual container dimensions of 32x32dp lack standard minimum 48x48dp tap target padding.
* **Remediation**: Set `constraints: const BoxConstraints(minWidth: 48, minHeight: 48)` on all interactive map overlays.

---

## 6. Phased Implementation Roadmap (Batches 1–5)

To ensure zero downtime, regressions, or documentation drift, remediation is structured into five focused batches matching the discipline of Phase 26:

```
┌────────────────────────────────────────────────────────────────────────┐
│                   PHASE 27 REMEDIATION ROADMAP                         │
├────────────────────────────────────────────────────────────────────────┤
│ Batch 1: Navigation Traps & High-Severity Role Gating                  │
│          (C-01, O-01, E-01, O-02)                                      │
├────────────────────────────────────────────────────────────────────────┤
│ Batch 2: Customer Job Lifecycle & Real-Time Interaction                │
│          (C-04, C-05, C-06, C-07, C-02, C-03)                          │
├────────────────────────────────────────────────────────────────────────┤
│ Batch 3: Owner Operations, Forms & Financial Refresh                   │
│          (O-03, O-04, O-05, O-06, O-07)                                │
├────────────────────────────────────────────────────────────────────────┤
│ Batch 4: Employee Workflow, Dispatch & Telemetry Integrity             │
│          (E-02, E-03, E-04, E-05)                                      │
├────────────────────────────────────────────────────────────────────────┤
│ Batch 5: Cross-Cutting UX Polish, RTL & Accessibility                  │
│          (C-08, C-09, C-10, C-11, X-01, X-02, X-03)                    │
└────────────────────────────────────────────────────────────────────────┘
```

### Batch 1: Navigation Traps & High-Severity Role Gating [RESOLVED & VERIFIED ✅]
* **Target Findings**: `C-01`, `O-01`, `E-01`, `O-02`
* **Status**: **100% Resolved & Verified**
* **Implemented Resolutions**:
  1. `C-01`: Updated `CustomerJobsScreen` empty state "Browse Services" button to check `onBrowseServices?.call()`, then `Navigator.canPop(context)`, then push `CustomerMarketplaceScreen`. In `CustomerHomeScreen`, wired `onBrowseServices: () => onTabTapped(1)`.
  2. `O-01`: Updated `EmployeeScreen` empty state "Add Worker" button to scroll to `_registerFormKey` context on Tab 0 using `Scrollable.ensureVisible` rather than animating to Tab 1 (Audit Trail).
  3. `E-01`: Wired comprehensive notification deep-routing in `NotificationsScreen._handleCardTap`: `job_offer` navigates to `EmployeeJobsScreen`, `job_completed` & `job_update` navigate to `CustomerJobsScreen`, `kyc_*` navigates to `KycDocumentUploadScreen`, and `payout_*` navigates to `WalletScreen`.
  4. `O-02`: Added `_buildKycWarningBanner` to `HomeScreen` (Owner Dashboard) when `authUser.kycStatus != 'approved'`, rendering verification warning and direct "Upload Documents" CTA to `KycDocumentUploadScreen`.

### Batch 2: Customer Job Lifecycle & Real-Time Interaction [RESOLVED & VERIFIED ✅]
* **Target Findings**: `C-04`, `C-05`, `C-06`, `C-07`, `C-02`, `C-03`
* **Status**: **100% Resolved & Verified**
* **Implemented Resolutions**:
  1. `C-04`: In `JobStatusScreen`, tracked `_hasRated` state locally. Awaiting `RatingScreen` returns `true`, which updates `_hasRated = true` and displays `rating_already_submitted_badge`. In `RatingScreen`, popped `true` on success and handled 400 conflict gracefully.
  2. `C-05`: In `TicketChatScreen.initState`, sequentialized history loading: `await chat.fetchChannelHistory(...)` executes before calling `connectAndSubscribeChannel`, eliminating the race condition that overwrote incoming live messages.
  3. `C-06`: In `TicketChatScreen._sendMessage`, caught exceptions and displayed user-facing `ThemedSnackBar.showError(context, friendlyErrorMessage(e))` while preserving typed text in `_messageController`.
  4. `C-07`: In `CustomerTicketsScreen`, awaited the `TicketChatScreen` route push and reloaded ticket list via `_loadTickets()` upon return.
  5. `C-02`: In `CustomerMarketplaceScreen._showBookingDialog`, awaited `JobStatusScreen` and refreshed services list on return: `if (mounted) _loadServices()`.
  6. `C-03`: In `CustomerMarketplaceScreen._BookingDialog`, replaced hardcoded `"\$${...}"` with localized `l10n.creditsAmountLine(...)`.

### Batch 3: Owner Operations, Forms & Financial Refresh
* **Target Findings**: `O-03`, `O-04`, `O-05`, `O-06`, `O-07`
* **Focus Area**: Business configuration and financial workflows.
* **Key Tasks**:
  1. Add upfront tier/KYC validation banner to `OwnerConfigurationScreen`.
  2. Pass all 12 configuration fields to `ownerProvider.createService`.
  3. Add contextual freeze/unfreeze actions directly to worker cards in `EmployeeScreen`.
  4. Refresh payout requests list on successful payout dialog submission.
  5. Format payout history timestamps using `.toLocal()`.

### Batch 4: Employee Workflow, Dispatch & Telemetry Integrity
* **Target Findings**: `E-02`, `E-03`, `E-04`, `E-05`
* **Focus Area**: Courier ergonomics, feedback clarity, and telemetry safety.
* **Key Tasks**:
  1. Fix notifications empty state duplicate copy.
  2. Replace raw status labels with actionable confirmation copy in job offer toasts.
  3. Disentangle escrow credits from distance display in `RouteTimeline`.
  4. Add 600ms debounce protection to courier online/offline toggle.

### Batch 5: Cross-Cutting UX Polish, RTL & Accessibility
* **Target Findings**: `C-08`, `C-09`, `C-10`, `C-11`, `X-01`, `X-02`, `X-03`
* **Focus Area**: Accessibility, session safety, and RTL symmetry.
* **Key Tasks**:
  1. Add confirmation modal to logout action in `SettingsScreen`.
  2. Auto-commit typed frequent address on profile save.
  3. Re-fetch user profile and update text controllers after email change.
  4. Block redundant identical email submissions client-side.
  5. Replace remaining raw `CircularProgressIndicator` instances with `ThemedLoadingIndicator`.
  6. Enable directional mirroring for button trailing arrows in RTL mode.
  7. Enforce 48dp minimum touch targets on map overlay controls.

---

## 7. Conclusion & Next Steps

This behavioral audit documents 26 high-impact findings that directly influence user satisfaction, error prevention, and operational integrity across all three roles. Unlike visual token checks, these findings represent runtime logic and state bugs that require deliberate, test-driven remediation.

Following human review and approval of this findings document, remediation will commence according to the 5-batch roadmap outlined above.
