# Comprehensive Behavioral UI/UX Audit — Full 30-Screen & Widget Sweep

> **Audit Date**: September 18, 2026  
> **Baseline Audited**: `logic-exploitation` @ `8c2ef82`  
> **Scope**: All 30 screen files in `frontend/lib/screens/` and 33 reusable widget files in `frontend/lib/widgets/`.  
> **Primary Focus**: Interactive and runtime behavior (what happens when a user clicks, inputs, submits, transitions, or loses network connection) — contrasting with the static/visual baseline in `docs/frontend/UI_UX_AUDIT.md`.  
> **Verification Tools Used**: AST/grep regular expression sweeps, widget lifecycle and call tree tracing, test harness simulations (`flutter test`), and Go backend handler contract verification.

---

## 1. Method Note

This behavioral audit evaluates how the Flutter frontend functions dynamically during active user workflows. While the previous audit (`docs/frontend/UI_UX_AUDIT.md`) evaluated token compliance, Stitch design fidelity, hardcoded colors, and static typography, this audit inspects the runtime mechanics of user interactions.

### Auditing Techniques Applied

| Technique | Scope & Execution | What It Uncovers |
| :--- | :--- | :--- |
| **AST & Grep Pattern Sweeps** | Swept all 63 Dart files in `screens/` and `widgets/` for event handlers (`onPressed`, `onTap`, `onChanged`, `onCompleted`), form submission flows, state setters (`setState`, `notifyListeners`), and provider invocations. | Missing submit guards, unhandled async errors, dangling callbacks, missing input validation bypass checks. |
| **Widget Lifecycle & Call-Tree Tracing** | Traced `initState`, `didChangeDependencies`, `dispose`, and `WidgetsBinding.instance.addPostFrameCallback` across all `StatefulWidget` classes. | Memory leaks, WebSocket subscription leaks, post-dispose context access, un-cancelled streams and timers. |
| **Backend-Frontend Contract Alignment** | Cross-referenced client requests (`ApiClient`, `Provider`) against Go microservice handlers (`api-gateway`, `auth-service`, `chat-service`, `user-service`, `notification-service`). | Role mismatches (e.g. 403 on ratings), missing endpoints, unhandled HTTP status codes (402, 403, 409, 422). |
| **Automated Test Harness Simulations** | Evaluated existing widget and provider tests (`flutter test`) and identified execution pathways not exercised in CI. | Asynchronous race conditions, optimistic UI failures, double-submit vulnerability windows. |

### Verification Boundary: Static/Simulated vs. Physical Device Testing

- **Verified via Static Code & Call-Tree Analysis**: Form validation logic, loading flags, network retry callback correctness, disposal teardown routines, role-based conditional navigation, and double-submit prevention.
- **Strictly Requires Physical Hardware Testing (Detailed in Section 6)**: Multi-touch gesture conflicts on interactive maps inside scrollable bottom sheets/dialogs, soft keyboard viewport resizing (`resizeToAvoidBottomInset`), hardware back-button race conditions, fast-fling list scroll desynchronization, and OS-level push notification wakeups from terminated app states.

---

## 2. Per-Screen Behavioral Findings Table

The table below catalogs behavioral findings across all 30 screens in `frontend/lib/screens/` and key interactive dialogs in `frontend/lib/widgets/`.

| Screen / Widget | Category | Behavioral Finding Description | File & Line Citation | Severity | Fix Suggestion |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`ticket_chat_screen.dart`** | Real-Time / Leaks | **[RESOLVED] Dead Dispose Hook / Leaking WebSocket & Timer**: Inside `dispose()`, `chat.disconnect()` was wrapped in `addPostFrameCallback((_) { if (mounted) { chat.disconnect(); } })`. In Flutter, `mounted` is always `false` after `dispose()`. Fixed by caching `ChatProvider` in `didChangeDependencies()` and calling `disconnect()` synchronously in `dispose()`. Verified via `a6_disposal_test.dart`. | `ticket_chat_screen.dart:65-70` | **Critical** | Resolved: Cached provider ref and synchronous disconnect in `dispose()`. |
| **`rating_screen.dart`** | Auth / Role Lockout | **[RESOLVED] Customer Rating Hard 403 Rejection**: In `job_status_screen.dart:1175`, customers were prompted to "Rate Your Experience" for completed jobs, but `RateJob` strictly allowed only Owner <-> Employee ratings. Fixed: backend authorization expanded to allow Customer <-> Courier and Customer <-> Owner ratings with self-rating & completed status guards; frontend `_determineParties()` updated to route employee -> customer, owner -> employee/customer, and customer -> employee/owner. Verified via `TestRateJob_RoleAuthorizationMatrix` and `rating_screen_test.dart`. | `rating_screen.dart:65-68` vs `ratings_handlers.go:86-89` | **Critical** | Resolved: Backend authorization matrix expanded + frontend party routing aligned. |
| **`deposit_funds_dialog.dart`** | Error Recovery | **[RESOLVED] Pseudo-Retry on Deposit Error Banner**: When a wallet deposit failed, `ThemedErrorBanner`'s "Retry" button merely dismissed the error banner. Fixed by extracting `_handleDeposit()` and wiring `ThemedErrorBanner.onRetry: _isSubmitting ? null : _handleDeposit`. Verified via `deposit_funds_dialog_test.dart`. | `deposit_funds_dialog.dart:130` | **High** | Resolved: Wired onRetry to `_handleDeposit`. |
| **`payout_request_dialog.dart`** | Error Recovery | **[RESOLVED] Pseudo-Retry on Payout Error Banner**: Tapping "Retry" on payout failure banners merely dismissed `_dialogError`. Fixed by extracting `_handlePayout()` and wiring `ThemedErrorBanner.onRetry: _isSubmitting ? null : _handlePayout`. Verified via `payout_request_dialog_test.dart`. | `payout_request_dialog.dart:155, 282` | **High** | Resolved: Wired onRetry to `_handlePayout`. |
| **`customer_jobs_screen.dart`** | Navigation / Crash | **Empty State CTA Pops Root App Shell**: When `CustomerJobsScreen` is embedded as Tab 2 in `CustomerHomeScreen`, the empty state action button ("Browse Services", line 165) calls `Navigator.pop(context)` instead of switching the parent `IndexedStack` to Tab 1 (`Browse Services`). This pops `CustomerHomeScreen`, exiting the app or returning to the login screen. | `customer_jobs_screen.dart:165` | **High** | Pass an `onBrowseServices` callback from `CustomerHomeScreen` to set `_selectedIndex = 1`, falling back to `Navigator.pop` only when pushed standalone. |
| **`chat_screen.dart` / `chat_provider.dart`** | Real-Time / Data Loss | **[RESOLVED] Message Deduplication Silently Drops Repeated Text**: In `ChatProvider._handleIncomingData`, incoming WebSocket messages were deduplicated on raw text alone, dropping repeated messages (e.g. "Yes", "OK"). Fixed by adding `id` and `created_at` to `chat.Message`, persisting & returning them from MongoDB, and updating `ChatProvider` deduplication to check message ID and 2-second timestamp windows instead of collapsing repeated content. Verified via `chat_provider_deduplication_test.dart` and `mongodb_test.go`. | `chat_provider.dart:194-201` | **High** | Resolved: Message ID + timestamp deduplication in backend and frontend. |
| **`ticket_chat_screen.dart`** | Real-Time / Race | **Concurrent History & WebSocket Race**: `initState` invokes `chat.fetchChannelHistory(channel, token)` and `chat.connectAndSubscribeChannel(channel, token)` concurrently. In `ChatProvider`, `fetchChannelHistory` executes `_messages = []` upon start and re-assigns `_messages = history` upon HTTP completion, overwriting and dropping any live WebSocket message received during page load. | `ticket_chat_screen.dart:55-57` | **High** | Await `fetchChannelHistory` before calling `connectAndSubscribeChannel` (matching the pattern established in `chat_screen.dart:55-59`). |
| **`customer_tickets_screen.dart`** | Stale State | **Unrefreshed Ticket Status on Return from Chat**: Tapping a ticket card navigates to `TicketChatScreen` via `Navigator.of(context).push(...)` without `await`. If an agent resolves or updates the ticket during the chat, popping back to `CustomerTicketsScreen` leaves the card displaying "Pending" until a manual pull-to-refresh. | `customer_tickets_screen.dart:159-164` | **Medium** | Use `await Navigator.of(context).push(...)` followed by `if (mounted) _loadTickets()`. |
| **`notifications_screen.dart`** | Navigation / Routing | **Missing Notification Tap Navigation & Missing Tracking Button**: Only `ticket_resolved` notifications navigate (to `TicketChatScreen` or `CustomerTicketsScreen`). Tapping `job_offer`, `job_completed`, `kyc_approved`, `kyc_rejected`, or `ticket_assigned` only marks them as read without navigating. Furthermore, the previously available "Track Shipment" action button for active jobs has disappeared from the notification card. | `notifications_screen.dart:87-123, 532-567` | **Medium** | Implement routing in `_handleCardTap` for job events (navigating to `JobStatusScreen(jobId: notif.contextId)`), KYC events (navigating to `KycDocumentUploadScreen`), and restore the "Track Job" CTA. |
| **`employee_jobs_screen.dart`** | Conceptual Integrity | **Credits Displayed as Road Distance in Route Timeline**: In `_buildActiveJobCard`, the escrow credit amount (`job.lockedEscrowAmount`) is passed into `RouteTimeline(distanceText:)` via `l10n.ownerHomeCreditsAmount(...)`. This renders a monetary value (e.g. "50 Credits") directly adjacent to the `Icons.route` road/distance icon, misrepresenting distance to couriers. | `employee_jobs_screen.dart:995-998` | **Medium** | Calculate and display physical distance (e.g., `"${dist.toStringAsFixed(1)} km"`) or pass `standardRouteLabel` when distance is uncomputed, placing credits in a dedicated financial chip. |
| **`employee_history_screen.dart`** | Conceptual Integrity | **Credits Displayed as Road Distance in Historical Route Timeline**: Identical to `employee_jobs_screen.dart`, `RouteTimeline` in historical cards formats `job.lockedEscrowAmount` as credits and passes it to `distanceText`. | `employee_history_screen.dart:185-188` | **Medium** | Replace with actual trip distance or route status label. |
| **`owner_configuration_screen.dart`** | Paid-Tier (402) Gating | **Free-Tier Form Completion Blindness**: Free-tier business owners can spend minutes configuring service locations, pricing, and operating radii. Upon tapping "Save Configuration", the request is rejected with HTTP 402, rendering a generic error banner without a direct navigation path or upgrade button to `SubscriptionScreen`. | `owner_configuration_screen.dart:284` | **Medium** | Proactively check `ownerProvider.subscriptionTier` on screen load, displaying an informational upgrade banner and providing a direct "Upgrade Plan" CTA that navigates to `SubscriptionScreen`. |
| **`employee_screen.dart`** | Paid-Tier (402) Gating | **Blind Form Failure on Worker Registration**: Free-tier owners attempting to add or toggle employees fill out credentials only to encounter an unlinked 402 error banner after submission. | `employee_screen.dart:648` | **Medium** | Proactively disable employee creation for free-tier owners with an inline upgrade card linking to `SubscriptionScreen`. |
| **`subscription_screen.dart`** | Auth / Parameters | **Token Passed as Tenant ID Parameter**: `_changeSubscription` invokes `ownerProvider.updateSubscription(tenantId: auth.token!, tier: tier)`. While the backend's `Subscription` handler currently falls back to `resolveTokenWithRole(req.TenantID, "owner")`, passing a raw JWT where a tenant ID is expected breaks architectural convention and will fail if gateway strict schema validation is enabled. | `subscription_screen.dart:37` | **Medium** | Pass `tenantId: auth.user?.id ?? auth.tenantId ?? ''` and supply the auth token in standard `Authorization` headers. |
| **`ticket_chat_screen.dart`** | Error Feedback | **Silent Swallowing of Message Send Failures**: In `_sendMessage()`, the `catch (e)` block logs `debugPrint('Error sending ticket message: $e')` and silently exits. The user is provided with no snackbar, banner, or retry prompt, leaving them uncertain why the message did not appear. | `ticket_chat_screen.dart:99-106` | **Medium** | Display `ThemedSnackBar.showError(context, friendlyErrorMessage(e))` in the `catch` block while retaining the unsent text in `_messageController`. |
| **`customer_job_map_screen.dart`** | Real-Time / Fallback | **Silent Disconnect on Live Courier Map**: If the courier tracking WebSocket drops or fails to connect, the map displays the last received coordinate without an inline warning banner or automatic REST fallback polling (`fetchJobStatus`). | `customer_job_map_screen.dart:65-80` | **Medium** | Surface a reconnection banner when `provider.isConnected == false` and initiate periodic REST polling every 10s. |
| **`owner_fleet_map_screen.dart`** | Real-Time / Fallback | **Fleet Map Telemetry Drop Without Alert**: Map displays empty/frozen vehicle markers if WebSocket telemetry disconnects, without indicating offline socket state to the fleet manager. | `owner_fleet_map_screen.dart:70-95` | **Medium** | Render an overlay banner when socket connection is lost. |
| **`create_ticket_dialog.dart`** | UI / Localization | **Description Field Label Duplication**: The description input field uses `l10n.settingsCustomerServiceSub` ("Help & Support Tickets") for both `labelText` and `hintText`. This duplicates the title/subject context rather than prompting the user for descriptive details. | `create_ticket_dialog.dart:141-142` | **Low** | Change `labelText` to `l10n.ticketDescriptionLabel` and `hintText` to `l10n.ticketDescriptionHint`. |
| **`forgot_password_screen.dart`** | Form Validation | **Validation Rule Discrepancy**: `_requestCode()` checks `!email.contains("@")`, whereas the form validator enforces a full RFC regex. A user submitting via keyboard submit action with `user@` can trigger an invalid network request before form validation catches it. | `forgot_password_screen.dart:56` | **Low** | Align `_requestCode()` with `_formKey.currentState!.validate()`. |
| **`otp_screen.dart`** | Concurrency / Race | **Rapid Pin Entry Double-Submit Race**: Entering the 6th digit immediately triggers `onCompleted: (pin) => _submit(pin)`. However, the "Verify" button is also active. Tapping the button simultaneously with entering the final digit can fire two concurrent `verifyOtp` calls. | `otp_screen.dart:241` | **Low** | Add `if (_isSubmitting) return;` at the beginning of `_submit()`. |
| **`wallet_screen.dart`** | Formatting | **Raw UTC Timestamp Display**: Transaction history dates in the ledger are formatted directly from UTC without calling `.toLocal()`, showing inaccurate transaction hours for users outside UTC+0. | `wallet_screen.dart:422` | **Low** | Call `item.createdAt.toLocal()` before formatting with `intl` or date helper. |
| **`customer_marketplace_screen.dart`** | Stale State | **Marketplace Background Stale After Booking**: Confirming a booking in `_BookingDialog` pops the dialog and pushes `JobStatusScreen`. Upon returning from `JobStatusScreen`, the marketplace services list is not refreshed, showing outdated courier availability. | `customer_marketplace_screen.dart:800-808` | **Low** | Invoke `_loadServices()` upon dialog completion. |
| **`kyc_document_upload_screen.dart`** | Navigation / Flow | **No Auto-Advance on Successful Upload**: After documents are uploaded and user profile is refreshed, the user remains on the upload screen with a success banner until they manually tap the back button. | `kyc_document_upload_screen.dart:120-135` | **Low** | Automatically pop or transition to dashboard after a brief delay (e.g. 1.5s). |
| **`job_status_screen.dart`** | UI Completeness | **Missing Destination Trip Distance Display**: Despite pickup and destination coordinates now being stored on jobs, the tracking screen shows courier proximity but omits total trip distance. | `job_status_screen.dart:750-810` | **Low** | Render calculated trip distance (pickup to destination) alongside status timeline. |
| **`employee_home_screen.dart`** | Concurrency | **Driver Status Switch Lacks Rapid-Tap Debounce**: Toggling the online/offline switch rapidly triggers un-debounced status update requests to the backend. | `employee_home_screen.dart:180-210` | **Low** | Debounce switch changes using a 500ms timer guard. |
| **`home_screen.dart`** | Ephemeral State | **Dismissed Urgent Actions Reappear on Re-entry**: Dismissing the urgent actions banner updates a local `_urgentActionsDismissed` state variable, which resets whenever the screen is rebuilt or re-entered. | `home_screen.dart:988` | **Low** | Persist dismissed alert IDs in `SharedPreferences` or provider state. |
| **`login_screen.dart`** | UX Cleanliness | **Dangling Snackbars on Forced Auth Redirect**: When an expired session redirects the user to `LoginScreen`, previous error snackbars or banners can persist across the transition. | `login_screen.dart:100-115` | **Low** | Call `ScaffoldMessenger.of(context).clearSnackBars()` in `initState`. |
| **`settings_screen.dart`** | Cache / State Sync | **Cache Clear Omits Provider Reset**: Clearing cache via the Settings row empties local preferences and image cache, but in-memory provider data remains loaded until app restart. | `settings_screen.dart:180-205` | **Low** | Notify providers to clear cached in-memory models upon cache purge. |
| **`update_required_screen.dart`** | Error Recovery | **Store Launcher Failure Leaves Deadlock**: If launching the external store URL fails, the screen displays a snackbar, but `PopScope(canPop: false)` leaves the user completely stuck with no secondary action. | `update_required_screen.dart:60-80` | **Low** | Provide a manual "Copy Download Link" or "Retry" button. |
| **`owner_reconciliation_queue_screen.dart`** | State Sync | **Manual Refresh Required After Job Resolution**: Resolving a stuck job pops the dialog and updates the item, but full queue metrics require manual pull-to-refresh if socket event does not arrive. | `owner_reconciliation_queue_screen.dart:150-175` | **Low** | Automatically re-fetch queue upon successful resolution. |
| **`component_library_screen.dart`** | Navigation | **Root Deep-Link Pop Vulnerability**: Tapping the back button on the standalone component library screen pops the Navigator; if accessed as the initial route in testing, it produces a black screen. | `component_library_screen.dart:20-35` | **Low** | Check `Navigator.canPop(context)` before popping, falling back to home route. |
| **`my_account_screen.dart`** | Feedback | **Account Deletion Confirmation Polish**: Dialog requires standard confirmation; consider requiring user to re-type username for high-risk irreversible action. | `my_account_screen.dart:210-240` | **Low** | Add re-auth or username confirmation prompt. |
| **`signup_screen.dart`** | Form Polish | **Missing Real-Time Password Strength Feedback**: Password validator enforces length client-side, but does not provide real-time entropy or strength indicators. | `signup_screen.dart:150-180` | **Low** | Add password strength bar under input field. |
| **`cancel_job_dialog.dart`** | Validation | **Whitespace-Only Reason Allowed**: Trimming validation is present on submission, but input field does not visually warn before submission if only spaces are entered. | `cancel_job_dialog.dart:85-95` | **Low** | Trim reason controller text in real-time validator. |
| **`email_change_dialog.dart`** | Validation | **Same-Email Submission Unchecked**: Does not verify whether the entered email is identical to the current email before dispatching request. | `email_change_dialog.dart:75-90` | **Low** | Validate `newEmail != currentEmail` client-side. |

---

## 3. Double-Submit Guard Matrix

All 42 interactive controls that trigger asynchronous network mutations across screens and dialogs were evaluated for double-submit resistance. Controls are categorized as:
- **Guarded (Y)**: Button explicitly sets `isLoading: true` and disables tap (`onPressed: null`), has an early return flag (`if (_isBusy) return;`), or applies a debounce guard.
- **Partial (P)**: Sets a flag in state or provider, but the UI button remains clickable during the initial microtask or lacks an immediate local disabled state.
- **Unguarded (N)**: Control can be tapped repeatedly during network latency, firing duplicate requests.

| # | Control Description | Screen / Dialog File | Guard Status | Code Location | Protection Mechanism |
| :---: | :--- | :--- | :---: | :--- | :--- |
| **1** | Login Submit Button | `login_screen.dart` | **Y** | `login_screen.dart:276` | `PrimaryButton.isLoading` bound to `_isSubmitting`; debounced via `_lastSubmitTime`. |
| **2** | Signup Submit Button | `signup_screen.dart` | **Y** | `signup_screen.dart:349` | `PrimaryButton.isLoading` bound to `_isSubmitting`; debounced via `_lastSubmitTime`. |
| **3** | Verify OTP Button | `otp_screen.dart` | **Partial** | `otp_screen.dart:285` | `PrimaryButton.isLoading` bound to `_isSubmitting`, but `OtpPinInput.onCompleted` can fire concurrently. |
| **4** | Resend OTP Button | `otp_screen.dart` | **Y** | `otp_screen.dart:312` | `onPressed: _resendCountdown > 0 ? null : _resendOtp`; timer-guarded (60s countdown). |
| **5** | Send Reset Code Button | `forgot_password_screen.dart` | **Y** | `forgot_password_screen.dart:268` | `PrimaryButton.isLoading` bound to `_isLoading`; `onPressed: _isLoading ? null : _requestCode`. |
| **6** | Confirm Reset Password Button | `forgot_password_screen.dart` | **Y** | `forgot_password_screen.dart:362` | `PrimaryButton.isLoading` bound to `_isLoading`; `onPressed: _isLoading ? null : _resetPassword`. |
| **7** | Confirm Booking Button | `customer_marketplace_screen.dart` | **Y** | `customer_marketplace_screen.dart:1078` | `onPressed: (_isSubmitting \|\| !hasDestination) ? null : _confirmBooking`; `isLoading: _isSubmitting`. |
| **8** | Marketplace Services Pull-to-Refresh | `customer_marketplace_screen.dart` | **Y** | `customer_marketplace_screen.dart:179` | `RefreshIndicator` internally guards against concurrent pull-triggers. |
| **9** | Marketplace Retry Fetch Button | `customer_marketplace_screen.dart` | **Y** | `customer_marketplace_screen.dart:192` | `ThemedErrorBanner(onRetry: _loadServices)`; provider sets loading state. |
| **10** | Customer Jobs Pull-to-Refresh | `customer_jobs_screen.dart` | **Y** | `customer_jobs_screen.dart:140` | `RefreshIndicator` internal concurrency lock. |
| **11** | Customer Jobs Retry Fetch Button | `customer_jobs_screen.dart` | **Y** | `customer_jobs_screen.dart:150` | `ThemedErrorBanner(onRetry: _loadJobs)`. |
| **12** | Map Tracking Socket Reconnect | `customer_job_map_screen.dart` | **Y** | `customer_job_map_screen.dart:72` | Provider `_isConnecting` flag suppresses redundant connection attempts. |
| **13** | Customer Tickets Pull-to-Refresh | `customer_tickets_screen.dart` | **Y** | `customer_tickets_screen.dart:105` | `RefreshIndicator` internal concurrency lock. |
| **14** | Customer Tickets Retry Button | `customer_tickets_screen.dart` | **Y** | `customer_tickets_screen.dart:118` | `ThemedErrorBanner(onRetry: _loadTickets)`. |
| **15** | Create Ticket Submit Button | `create_ticket_dialog.dart` | **Y** | `create_ticket_dialog.dart:160` | `PrimaryButton.isLoading` bound to `_isSubmitting`; `onPressed: _isSubmitting ? null : _handleSubmit`. |
| **16** | Ticket Chat Send Button | `ticket_chat_screen.dart` | **Y** | `ticket_chat_screen.dart:290` | `IconButton(onPressed: _isSending ? null : _sendMessage)`. |
| **17** | Ticket Chat History Retry | `ticket_chat_screen.dart` | **Y** | `ticket_chat_screen.dart:135` | Provider loading guard on history fetch. |
| **18** | Job Chat Send Button | `chat_screen.dart` | **Y** | `chat_screen.dart:260` | `IconButton(onPressed: _isSending ? null : _sendMessage)`. |
| **19** | Job Chat History Retry | `chat_screen.dart` | **Y** | `chat_screen.dart:142` | Provider loading guard on history fetch. |
| **20** | Cancel Job Dialog Show Button | `job_status_screen.dart` | **Y** | `job_status_screen.dart:1189` | Modal dialog display blocks interaction with underlying screen. |
| **21** | Counter-Offer Submit Button | `job_status_screen.dart` | **Partial** | `job_status_screen.dart:1550` | Relies on provider busy state; local button lacks instantaneous `isLoading` lock. |
| **22** | Accept Price Proposal Button | `job_status_screen.dart` | **Partial** | `job_status_screen.dart:1472` | `_respondToProposal('accept')` calls provider without local button disabled state. |
| **23** | Decline Price Proposal Button | `job_status_screen.dart` | **Partial** | `job_status_screen.dart:1482` | `_respondToProposal('decline')` calls provider without local button disabled state. |
| **24** | Submit Rating Button | `rating_screen.dart` | **Y** | `rating_screen.dart:340` | `PrimaryButton.isLoading` bound to `_isSubmitting`; `onPressed: (_isSubmitting \|\| _selectedStars == 0) ? null : _submitRating`. |
| **25** | Accept Job Offer Button | `employee_jobs_screen.dart` | **Y** | `employee_jobs_screen.dart:820` | Guarded by `_actionBusyJobId == job.id`; disables sibling buttons for that job. |
| **26** | Decline Job Offer Button | `employee_jobs_screen.dart` | **Y** | `employee_jobs_screen.dart:835` | Guarded by `_actionBusyJobId == job.id`; disables sibling buttons for that job. |
| **27** | Complete Job Button | `employee_jobs_screen.dart` | **Y** | `employee_jobs_screen.dart:1115` | `PrimaryButton.isLoading` bound to `_actionBusyJobId == job.id`. |
| **28** | Simulate Driver Action Button | `employee_jobs_screen.dart` | **Partial** | `employee_jobs_screen.dart:1130` | Disables when `_actionBusyJobId == job.id`, but rapid successive stage taps can race. |
| **29** | Driver Online/Offline Switch | `employee_home_screen.dart` | **N** | `employee_home_screen.dart:195` | **Unguarded**: rapid flipping of the switch dispatches concurrent online/offline pings. |
| **30** | Employee History Pull-to-Refresh | `employee_history_screen.dart` | **Y** | `employee_history_screen.dart:110` | `RefreshIndicator` internal concurrency lock. |
| **31** | Register Employee Button | `employee_screen.dart` | **Y** | `employee_screen.dart:495` | `PrimaryButton.isLoading` bound to `_isSubmittingReg`; `onPressed: _isSubmittingReg ? null : _registerEmployee`. |
| **32** | Toggle Employee Status Button | `employee_screen.dart` | **Y** | `employee_screen.dart:630` | `PrimaryButton.isLoading` bound to `_isSubmittingTog`; `onPressed: _isSubmittingTog ? null : _toggleEmployee`. |
| **33** | Save Service Configuration Button | `owner_configuration_screen.dart` | **Y** | `owner_configuration_screen.dart:620` | `PrimaryButton.isLoading` bound to `_isSubmitting`; `onPressed: _isSubmitting ? null : _saveConfiguration`. |
| **34** | Resolve Stuck Job Button | `owner_reconciliation_queue_screen.dart` | **Y** | `owner_reconciliation_queue_screen.dart:180` | Guarded by `_isResolving` flag and modal dialog confirmation. |
| **35** | Subscription Upgrade / Change Button | `subscription_screen.dart` | **Y** | `subscription_screen.dart:340` | `PrimaryButton.isLoading` bound to `_isSubmitting`; `onPressed: _isSubmitting ? null : () => _changeSubscription(tier)`. |
| **36** | Wallet Pull-to-Refresh | `wallet_screen.dart` | **Y** | `wallet_screen.dart:210` | `RefreshIndicator` internal concurrency lock. |
| **37** | Confirm Deposit Funds Button | `deposit_funds_dialog.dart` | **Y** | `deposit_funds_dialog.dart:147` | `PrimaryButton.isLoading` bound to `_isSubmitting`; `onPressed: _isSubmitting ? null : _handleDeposit`. |
| **38** | Confirm Payout Request Button | `payout_request_dialog.dart` | **Y** | `payout_request_dialog.dart:315` | `PrimaryButton.isLoading` bound to `_isSubmitting`; `onPressed: _isSubmitting ? null : _handlePayout`. |
| **39** | Confirm Job Cancel Button | `cancel_job_dialog.dart` | **Y** | `cancel_job_dialog.dart:93` | `PrimaryButton.isLoading` bound to `_isSubmitting`; `onPressed: (isReasonEmpty \|\| _isSubmitting) ? null : _handleCancel`. |
| **40** | Request Email Change Button | `email_change_dialog.dart` | **Y** | `email_change_dialog.dart:110` | `PrimaryButton.isLoading` bound to `_isSubmitting`; `onPressed: _isSubmitting ? null : _submitEmailChange`. |
| **41** | Upload KYC Document Button | `kyc_document_upload_screen.dart` | **Y** | `kyc_document_upload_screen.dart:185` | `PrimaryButton.isLoading` bound to `_isSubmitting`; `onPressed: (_isSubmitting \|\| _selectedFile == null) ? null : _uploadDocument`. |
| **42** | Clear All Notifications Button | `notifications_screen.dart` | **Partial** | `notifications_screen.dart:75` | Tapping directly triggers `provider.clearAll()`; lacks double-tap debounce or confirm modal. |

---

## 4. Cross-Reference Section: Known/Deferred vs. Newly Uncovered

To maintain documentation integrity and avoid duplicate tracking, this section explicitly delineates previously known and deferred items from newly uncovered findings.

### Previously Documented Baseline (Confirmed Present or Deferred)

- **A4 (Double-Submit Guards)**: Tracked in `STATUS.md`. The majority of primary form buttons (`login`, `signup`, `booking`, `deposit`, `payout`, `kyc`) correctly employ `PrimaryButton.isLoading` and disabled handlers. Residual partial gaps (driver status toggle, proposal responses) are cataloged in Section 3.
- **A5 (Raw Exception / String Leaks)**: Documented in `STATUS.md`. The previous bug where `subscription_screen.dart` rendered `l10n.ratingFailed(...)` was resolved in commit `4cbfac1...`. All exceptions are now routed through `friendlyErrorMessage(...)`.
- **A6 (WebSocket Teardown on Dispose)**: Documented in `STATUS.md` as resolved for `chat_screen.dart` via `ProviderConnectionCleanup`. As discovered below, this was re-introduced in `ticket_chat_screen.dart`.
- **A7 (Dead Code / Unreachable UI)**: Documented in `STATUS.md`. Audit confirmed no dead classes or orphaned routes in `screens/`.
- **A8 (Job Cancellation Parity)**: Documented in `STATUS.md`. `CancelJobDialog` is shared across customer and owner screens.
- **GAP-01 through GAP-05**: Tracked in `STATUS.md` (Escrow deferred to beta, multi-drop routing deferred, advanced dispute evidence deferred).

### Newly Uncovered Behavioral Findings (This Audit)

1. **`ticket_chat_screen.dart` WebSocket & Timer Teardown Regression**: Exact recurrence of the A6 defect. Wrapping `chat.disconnect()` in a post-frame `if (mounted)` callback inside `dispose()` results in dead code because `mounted` is guaranteed `false`. The WebSocket and reconnect timers leak indefinitely after leaving the screen.
2. **Customer Rating Flow Hard Lockout (403 Forbidden)**: `JobStatusScreen` provides a "Rate Your Experience" button to customers, but the Go backend handler `RateJob` strictly allows only `Owner <-> Employee` ratings. Customer ratings fail with 403 Forbidden. Furthermore, when an employee rates, `RatingScreen` assigns `_otherPartyId` to the business owner rather than the customer.
3. **Pseudo-Retry in Money Dialogs (`deposit_funds_dialog.dart` & `payout_request_dialog.dart`)**: In both dialogs, `ThemedErrorBanner.onRetry` is wired to `() => setState(() => _dialogError = null)`. Tapping "Retry" merely closes the error message rather than retrying the deposit or payout.
4. **Chat Message Deduplication Dropping Repeated Messages**: `ChatProvider._handleMessage` deduplicates solely based on sender, content, and message type. Any user sending identical words twice in a conversation (e.g. "Yes", "OK", "Thank you") has their second message silently discarded.
5. **Chat History vs WebSocket Subscription Race**: `ticket_chat_screen.dart` calls history fetch and WebSocket subscription concurrently. History fetch resets `_messages = []`, overwriting live messages received during screen loading.
6. **Embedded Tab Pop Crash in `customer_jobs_screen.dart`**: The empty state "Browse Services" CTA calls `Navigator.pop(context)`, popping the entire `CustomerHomeScreen` root shell when tapped from Tab 2.
7. **Broken Notification Routing & Missing Tracking Action**: Notifications for jobs and KYC do not navigate on tap. The previous "Track Shipment" button has disappeared from notification cards.
8. **Credits Displayed as Road Distance in `RouteTimeline`**: `employee_jobs_screen.dart` and `employee_history_screen.dart` pass `job.lockedEscrowAmount` as `distanceText` into `RouteTimeline`, displaying "50 Credits" next to the road icon.
9. **Paid-Tier Blind Form Submission**: Free-tier owners can complete entire forms in `owner_configuration_screen.dart` and `employee_screen.dart`, only to be rejected with an unlinked 402 error banner without an upgrade button.

---

## 5. Prioritized Remediation Order

Remediations are organized into three sequential tiers based on financial impact, authentication security, resource leaks, and navigation stability.

### Tier 1: Critical Core Defects (Resource Leaks, Money Flow, Auth/Rating Lockout) [RESOLVED]
*Target: Immediate hotfix — Completed and verified.*

1. **Fix `ticket_chat_screen.dart` Teardown Leak [RESOLVED]**:
   - Caches `ChatProvider` in `didChangeDependencies()` and invokes `disconnect()` synchronously in `dispose()`.
   - Hardened `chat_provider.dart` `disconnect()` to absorb `notifyListeners()` errors if called during widget tree disposal phases.
   - Verified via `test/a6_disposal_test.dart` (7/7 passing).
2. **Resolve Rating Flow Authorization & Role Assignment [RESOLVED]**:
   - In Go backend `ratings_handlers.go`: Updated `RateJob` authorization matrix to allow Customer <-> Courier (`job.UserID` <-> `job.EmployeeID`) and Customer <-> Owner (`job.UserID` <-> `job.OwnerID`), with 400 Bad Request guards for self-rating (`RatedBy == RatedUser`) and incomplete jobs (`Status != JobStatusCompleted`).
   - In `rating_screen.dart`: Updated `_determineParties()` to dynamically route employee -> customer (`userId`), owner -> employee (`employeeId`) or customer (`userId`), and customer -> employee (`employeeId`) or owner (`ownerId`).
   - Verified via backend unit suite `ratings_target_guard_regression_test.go` (9/9 role authorization scenarios passing), `test/rating_screen_test.dart` (9/9 passing), and golden tests in `test/golden_screens_test.dart`.
3. **Correct Pseudo-Retry in Deposit & Payout Dialogs [RESOLVED]**:
   - In `deposit_funds_dialog.dart`: Extracted `_handleDeposit()` and wired `onRetry: _isSubmitting ? null : _handleDeposit` and `onDismiss`.
   - In `payout_request_dialog.dart`: Extracted `_handlePayout()` and `_handleContinue()` and wired `onRetry: _isSubmitting ? null : _handlePayout` in both confirmation and form views.
   - Verified via `test/deposit_funds_dialog_test.dart` (9/9 passing) and `test/payout_request_dialog_test.dart` (9/9 passing).
4. **Fix Chat Message Deduplication in `chat_provider.dart` [RESOLVED]**:
   - In `chat-service` (`hub.go` and `mongodb.go`): Added message `ID` and `CreatedAt` fields to `chat.Message`, persisting and returning them via MongoDB.
   - In `chat_message.dart`: Added `id` and `createdAt` parsing with backwards-compatible fallbacks.
   - In `chat_provider.dart`: Updated `_handleIncomingData` deduplication to verify message ID match or 2-second timestamp window proximity, ensuring legitimate repeated content (e.g. "Yes", "OK") is preserved.
   - Verified via `mongodb_test.go` and `test/chat_provider_deduplication_test.dart` (7/7 passing).

### Tier 2: Flow Traps, Real-Time Sync & Gating UX
*Target: Next sprint / stabilization pass.*

1. **Fix Customer Jobs Empty State Pop Trap**:
   - In `customer_jobs_screen.dart:165`: Provide an optional `VoidCallback? onBrowseServices`. In `CustomerHomeScreen`, pass a callback that sets `_selectedIndex = 1`.
2. **Order History Fetch and WebSocket Subscription in `ticket_chat_screen.dart`**:
   - Update `_initChat()`: Await `chat.fetchChannelHistory()` before calling `chat.connectAndSubscribeChannel()`.
3. **Implement Notification Deep-Linking & Action Buttons**:
   - In `notifications_screen.dart:87-123`: Route `job_*` notifications to `JobStatusScreen(jobId: notif.contextId)`.
   - Add "Track Order" CTA button to active job notification cards.
4. **Enhance Paid-Tier (402) Gating UX**:
   - In `owner_configuration_screen.dart` and `employee_screen.dart`: Proactively inspect `ownerProvider.subscriptionTier`. If `free`, display an informational banner and provide an "Upgrade Plan" button linking directly to `SubscriptionScreen`.
5. **Add Error Feedback to Ticket Chat Message Send**:
   - In `ticket_chat_screen.dart:99-106`: Surface `ThemedSnackBar.showError(context, friendlyErrorMessage(e))` on failure.
6. **Await Ticket Chat Push in `customer_tickets_screen.dart`**:
   - Change `Navigator.push(...)` to `await Navigator.push(...)` and invoke `_loadTickets()` on return.

### Tier 3: Conceptual Consistency, Labels & Formatting Polish
*Target: Quality-of-life release.*

1. **Correct `RouteTimeline` Distance vs Credits**:
   - In `employee_jobs_screen.dart:995` and `employee_history_screen.dart:185`: Pass physical distance (e.g. `"${job.tripDistanceKm} km"`) or standard route label to `distanceText`, moving credit badges to payment metadata.
2. **Fix `create_ticket_dialog.dart` Description Field Labels**:
   - Replace `l10n.settingsCustomerServiceSub` with dedicated `ticketDescriptionLabel` and `ticketDescriptionHint`.
3. **Format Raw UTC Ledger Timestamps in `wallet_screen.dart`**:
   - Call `.toLocal()` before formatting transaction dates.
4. **Align Validation Rules in `forgot_password_screen.dart`**:
   - Unify email regex validation between `_requestCode` and form validator.
5. **Debounce Driver Status Toggle in `employee_home_screen.dart`**:
   - Add a 500ms debounce guard to online/offline state changes.

---

## 6. Explicit "Requires Manual Device Testing" Section

Certain behavioral dimensions cannot be verified through static analysis, AST scanning, or headless unit tests. The following user experience characteristics **strictly require physical hardware device testing**:

### 1. Interactive Dual-Map Gestures Inside Dialogs (`_BookingDialog` & `LocationPickerMap`)
- **Behavioral Risk**: When dragging or zooming `LocationPickerMap` within `_BookingDialog` or bottom sheets, Android and iOS gesture recognizers can experience conflict between parent dialog scroll physics and map touch handlers (`PointerMoveEvent`).
- **Physical Test Procedure**: On a physical 5-inch to 6.7-inch device, open `_BookingDialog`, drag the map rapidly, perform two-finger pinch-to-zoom, and ensure the outer dialog does not scroll, jank, or dismiss unintentionally.

### 2. Virtual Keyboard Viewport Inset & Focus Trapping
- **Behavioral Risk**: Opening virtual keyboards on devices with different aspect ratios (e.g. 19.5:9 vs 16:9) can obscure primary submit buttons or create `RenderFlex` overflow errors in dialogs (`DepositFundsDialog`, `PayoutRequestDialog`, `CreateTicketDialog`, `TicketChatScreen`).
- **Physical Test Procedure**: Focus the description field in `CreateTicketDialog` and the message text field in `TicketChatScreen` on physical Android and iOS devices. Verify that `resizeToAvoidBottomInset: true` functions smoothly, input fields remain visible above the keyboard, and tapping outside dismisses the keyboard cleanly.

### 3. Rapid Fling-Scroll & Tile Desynchronization
- **Behavioral Risk**: Fast-fling scrolling across long lists (`CustomerJobsScreen`, `NotificationsScreen`, `EmployeeJobsScreen`) can cause memory pressure, image tile flickering on maps, or frame drops under low-power hardware constraints.
- **Physical Test Procedure**: Perform repeated, high-velocity fling scrolls across 50+ item lists on mid-tier and low-tier Android hardware while monitoring Flutter DevTools performance overlay (16.6ms / 60fps frame budget).

### 4. Background Push Notification & Wakeup Transitions
- **Behavioral Risk**: Tapping a system push notification when the app is in the background or terminated can fail to hydrate the user session or corrupt the navigation back-stack.
- **Physical Test Procedure**: Send a remote push alert (e.g., `ticket_resolved` or `job_offer`) while the app process is terminated. Tap the system tray notification and verify that the app initializes auth state, navigates directly to `TicketChatScreen` or `JobStatusScreen`, and allows the user to press back to reach the dashboard without crashing.
