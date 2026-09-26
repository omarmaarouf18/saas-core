# Frontend UX Patterns (Established by Fixing)

> Source: these rules were extracted from the actual diffs that fixed audit
> groups A (Auth), C (Customer), and E (Employee/Owner) of
> [UI_UX_AUDIT_2026-09.md](UI_UX_AUDIT_2026-09.md), not written upfront.
> Each rule cites the reference implementation that proves it. This doc
> grows incrementally — one section per fixed audit group — so a future
> reader can trust every rule below is already the codebase norm, not an
> aspiration.

## 1. Error display: persistent inline banner, snackbar as supplement only

Any auth/form failure the user must act on renders a persistent
`ThemedErrorBanner(message: <provider error>, onRetry: <same action>)`
anchored above the relevant field — never a snackbar alone. The
snackbar (`ThemedSnackBar.showError`, keeping its `onRetry`) stays as a
transient supplement, not the sole signal.

Reference implementations: `forgot_password_screen.dart:137-143` (the
original), then `login_screen.dart` (`login_error_banner`),
`signup_screen.dart` (`signup_error_banner`), `otp_screen.dart`
(`otp_verify_error_banner` / `otp_resend_error_banner` — two sites
because verify and resend need different retries, selected by a local
failure-source flag so only one renders),
`reset_password_otp_screen.dart:177-188`, and
`kyc_document_upload_screen.dart` (`kyc_refresh_error_banner`).

Supporting invariants established with the rule: providers store
failures on `_error` (e.g. `fetchUserProfile` now stores instead of
bare-`debugPrint`) so screens have something to read; `logout()` /
`forceLogout()` clear `_error` so logged-out screens never render a
previous session's failure.

Framework note learned while codifying this: a `SnackBar` carrying an
action persists by Material default
(`persist = persist ?? action != null` in the framework's `SnackBar`),
so retry-bearing snackbars legitimately outlive the 2s
`snackBarDisplay` window. Tests assert the *banner* survives past the
window, not snackbar absence.

## 2. OTP completion: full-length entry verifies immediately (call-site contract)

Every production `OtpPinInput` usage wires
`onCompleted: (_) => <that screen's verify action>`, guarded by the
verify path's in-flight check (`auth.isLoading` early-return) so a
paste-then-tap or double-completion cannot double-submit. The Verify
`PrimaryButton` additionally disables via `isLoading` plus its own
in-flight lock.

Deliberately a call-site contract, NOT a widget default:
`OtpPinInput.onCompleted` is optional and already fires consistently on
every full-length entry; the widget cannot verify (no provider access,
no form validation, no navigation, no busy-state ownership), so an
"auto-verify default" inside the widget would couple a reusable input
to auth flows. Reference: `otp_screen.dart:324-327` (original),
`reset_password_otp_screen.dart:212-221` (aligned by the A7 fix).

## 3. Focal action: one PrimaryButton per screen state

Each screen state has exactly one focal CTA — the `PrimaryButton`
(amber filled). Secondary actions are `SecondaryButton(isOutlined: true)`,
never filled, so they cannot compete for attention.

Reference before/after: `reset_password_otp_screen.dart` stacked a
filled Verify `PrimaryButton` over a filled Resend `SecondaryButton`
(two equal-weight amber CTAs); Resend is now outlined + refresh-icon,
full-width, matching `otp_screen.dart:385-393`. Same demotion applied
per-slot in `kyc_document_upload_screen.dart`: only the first
incomplete upload slot keeps the focal `PrimaryButton`
(`firstIncompleteKey`); remaining incomplete slots render outlined
`SecondaryButton`s with identical keys/text/handlers.

## 4. Busy state: every manual refresh/retry shows busy and locks re-trigger

Any manually-triggered refresh or retry action must show a busy
indicator and refuse re-trigger until it resolves. Reference:
`kyc_document_upload_screen.dart` (`_isRefreshing` flag set around
`fetchUserProfile`, early-return guard, AppBar refresh icon swapped for
an 18px spinner `kyc_refresh_busy` until resolve) — covering the
post-frame auto-refresh, the AppBar tap, and pull-to-refresh, which all
share `_refreshUserData`.

Size exception, recorded not hidden: the AppBar spinner is intentionally
a raw `CircularProgressIndicator`, because `ThemedLoadingIndicator` is a
centered full-size widget that cannot fit AppBar action bounds (tracked
against open audit item X-01's remaining-sites list).

## 5. Loading vs failure vs empty — three distinct states

Every fetch has three outcomes — in-flight, failed, genuinely empty —
and each renders visually distinctly. A screen that only branches on
`isEmpty` is presumed incomplete: loading flashes the empty card, and
failure masquerades as "nothing to show".

Reference implementations (audit group C):
- Provider flags distinguish in-flight from settled:
  `chat_provider.dart:25,52,73,98` (`_isLoadingHistory` set/cleared
  around `fetchChannelHistory`; the pre-existing `_isLoading` was owned
  by other flows and could never fire these branches).
- Screens gate the loader on the flag, not on emptiness:
  `ticket_chat_screen.dart:300` (`isLoading || isLoadingHistory`),
  `chat_screen.dart:281` (added `isLoadingHistory` arm —
  `isConnecting` is still false during history fetch),
  `customer_home_screen.dart:664-670` (activity skeleton while
  `isLoading && activeJobs.isEmpty`).
- Failures surface Rule 1's banner with retry instead of the empty
  render: `ticket_chat_screen.dart:289-294`
  (`chat.error != null && subscriptionError == null` →
  `ThemedErrorBanner(onRetry: _connectAndLoad)`, mirroring
  `chat_screen.dart:262-266`); `rating_screen.dart:38,105,131,136,440-446`
  (`_otherPartyStatusError` flag → `rating_status_error_banner`
  instead of the "waiting" visualizer); per-card
  `customer_marketplace_screen.dart:1309,1333-1361` (`_failed` flag →
  compact refresh retry instead of `noRatingsLabel`, which is now
  reserved for genuine zero counts).
- Home error composition: `customer_home_screen.dart` renders error,
  loading, list, or empty exclusively — the failure banner no longer
  co-renders above a contradictory "no orders" card.
- Send-failure parity: `ticket_chat_screen.dart:200`
  (`onRetry: _sendMessage`, straight copy of
  `chat_screen.dart:102-106`).

## 6. Dismiss gesture consistency: input dialogs lock, read-only dialogs may not

Any dialog collecting user input is `barrierDismissible: false` by
convention — an outside tap must never discard a draft. Read-only or
confirmation-only dialogs may remain dismissible.

Reference: the two locked outliers
`customer_tickets_screen.dart:56` and `job_status_screen.dart:1275`
(both `CreateTicketDialog` sites), matching the pre-existing majority
`customer_marketplace_screen.dart:757` (`_BookingDialog`) and
`cancel_job_dialog.dart:41`. The existing Cancel/close buttons remain
the single exit; no dialog named outside this set was touched. Invariance
re-verified in Group E (finding E18): `cancel_job_dialog.dart:41`
remains intentionally `barrierDismissible: false` to lock against accidental
draft destruction when collecting typed cancellation reasons.

## 7. Background progress indicator: animate unbounded waits

Any unbounded background wait the user cannot observe directly —
dispatch searching for a courier, polling, reconnect — gets a
lightweight animated signal, never static text alone.

Reference: shared `pending_pulse_dot.dart` (`PendingPulseDot`, 8px
fade loop on `AppMotion` tokens — one widget for all sites, not three
bespoke animations), wired where each screen's own pending condition
holds: `job_status_screen.dart:727,766,822-824` (`showPendingPulse`,
true only while status is exactly `pending_dispatch`),
`customer_jobs_screen.dart:356` (existing `isPendingDispatch` flag),
`customer_job_map_screen.dart:297` (the waiting notice itself only
renders while no marker arrived, so the dot renders and clears with
it — that screen carries no status field).

## 8. High-stakes action confirmation & decision-specific feedback

Irreversible, destructive, or financially consequential operations
(cancellations triggering customer escrow refunds, rejecting courier
cancellation requests, freezing worker access) must never fire immediately
on tap. They require explicit confirmation via `ConfirmActionDialog.show`
with `isDestructive: true`, explaining the concrete consequences upfront
(escrow refund amount, courier assignment status, login revocation).
Opposing outcomes must provide distinct, localized feedback rather than
generic status toasts.

Reference implementations:
- Owner cancellation request decisions (`home_screen.dart:1283-1324` /
  `_respondCancellationRequest`): Approve explains full escrow customer
  refund; Decline explains courier remains assigned to active job; both
  wrapped in `ConfirmActionDialog.show`. Success yields distinct localized
  snackbars (`ownerCancelRequestApproved`, `ownerCancelRequestDeclined`)
  and surfaces specific server error feedback on failure (audit E12, E26).
- Owner job cancellation (`home_screen.dart:1354-1375` / `_handleCancelJob`):
  Active job cancellation specifies upfront escrow refund warning
  (`ownerCancelJobEscrowWarning(amount)`) or plain cancellation notice
  (`ownerCancelJobPlainWarning`) inside `CancelJobDialog.show(bodyText: ...)`
  (audit E13).
- Worker account freeze/unfreeze (`employee_screen.dart:656-690`): Wrapped in
  `ConfirmActionDialog.show` with explicit warning copy
  (`freezeWorkerConfirmMessage(targetEmail)`) stating immediate login
  block and dispatch hiding (audit E14).

## 9. Actionable filtered empty states with one-tap recovery

When a search query, category, or status filter yields zero results, screens
must never render bare unstyled text or dead-end copy. Filtered views must
render `ThemedEmptyState` with a search-off icon
(`Icons.search_off_outlined`), clear descriptive copy explaining the zero
state, and a primary CTA ("Clear Filters") that resets the filter and search
controllers back to baseline in one tap. On empty map/location views, provide
a prominent refresh affordance.

Reference implementations:
- Employee roster (`employee_screen.dart:304-320`):
  `filtered_empty_employees_state` resets `_searchController` and
  `_statusFilter = 'all'` via `clearFiltersBtn` (audit E4).
- Owner history (`owner_history_screen.dart:373-387`):
  `filtered_empty_jobs_state` resets `_jobsSearchController` and
  `_jobsStatusFilter = 'all'` (audit E5).
- Reconciliation queue (`owner_reconciliation_queue_screen.dart:280-297`):
  `filtered_empty_recon_state` resets `_searchController` and
  `_selectedCategory = 'all'` (audit E6).
- Fleet live map (`owner_fleet_map_screen.dart:454-485`):
  `empty_fleet_refresh_button` inside empty fleet notice directly calls
  `hydrateOwnerFleet` (audit E7).

Supporting invariant: Empty states render only when fetch succeeded
(`error == null && !isLoading`); network failures branch to Rule 1 error
banners instead.

## 10. Touch target standard: 44×44px minimum bound

All interactive controls (filter chips, segmented pills, expansion/collapse
chevrons, icon toggles) must meet the standard 44×44px minimum touch target
size (`minWidth: 44, minHeight: 44`), even when visually compact. Use
`BoxConstraints(minHeight: 44, minWidth: 44)` with centered child alignment or
padded `ConstrainedBox` bounds.

Reference implementations:
- Shared `pill_filter_bar.dart:106-125`: `PillFilterBar` chip containers
  upgraded from fixed `height: 36` to `constraints: BoxConstraints(minHeight: 44, minWidth: 44)`
  and `alignment: Alignment.center`. Per repo shared-widget discipline, this
  single shared fix elevated touch target compliance across employee roster
  (`employee_screen.dart`), owner history (`owner_history_screen.dart`), and
  reconciliation queue (`owner_reconciliation_queue_screen.dart`) (audit E20).
- Fleet live map (`owner_fleet_map_screen.dart:320-448`): Floating filter pills
  (`fleet_filter_pill_all`, `fleet_filter_pill_on_route`,
  `fleet_filter_pill_idle`) constrained with `minHeight: 44, minWidth: 44`
  (audit E21).
- Employee jobs screen (`employee_jobs_screen.dart:1016-1046`): Job card detail
  expansion toggle wrapped in `ConstrainedBox(constraints: BoxConstraints(minHeight: 44, minWidth: 44))`
  with rounded ripple bounds (audit E22).

## 11. Form validation separation & progressive disclosure

Client-side input validation must be cleanly separated from top-level network
retry banners. Field-level validation belongs inline beneath the respective
inputs (`AutovalidateMode.onUserInteraction`) and must never trigger a
top-of-screen API retry banner. Non-text inputs (such as location/coordinate
pickers) require dedicated inline error notices. Long or multi-section
configuration forms must employ progressive disclosure (e.g. collapsible
`ExpansionTile` panels) to prevent form fatigue without removing
configuration capabilities.

Reference implementations:
- `owner_configuration_screen.dart`:
  - `ThemedErrorBanner(key: Key('owner_config_fetch_error_banner'))` is
    reserved exclusively for initial service fetch network failures
    (`_fetchError != null && services.isEmpty`) (audit E10).
  - Top-of-screen `_errorMessage` banner is reserved strictly for mutation API
    failures (`createService` / `updateOwnerServiceConfig`), while form
    validation errors (address, working hours, missing coordinates via
    `owner_config_location_inline_error`) render inline beneath their respective
    controls (audit E11, E15).
  - Progressive disclosure: 7-day schedule configuration wrapped in
    `ExpansionTile(key: Key('schedule_per_day_expansion_tile'))` inside
    transparent `Material` wrapper within `ThemedCard` (audit E17).
- Shared widget: `ThemedTextField` (`themed_text_field.dart`) exposes
  `autovalidateMode` parameter to allow declarative form validation on
  interaction without altering global defaults across the app.

## 12. Stale-while-revalidate telemetry & non-blocking background signals

Background network synchronization or telemetry revalidation on screens with
existing active content (such as live courier maps or job dispatch queues) must
NOT clear or flash existing data. Stale data must remain visible while
revalidating ("stale-while-revalidate"), accompanied by a slim, non-blocking
progress signal (`LinearProgressIndicator`) rather than full-screen blocking
loaders. Incoming push events (e.g. new dispatch alerts) surface transient
feedback (`ThemedSnackBar.showSuccess`) without interrupting current workflow.

Reference implementations:
- `map_tracking_provider.dart:84-176` and `owner_fleet_map_screen.dart:142-236`:
  `hydrateOwnerFleet` preserves existing `_employeeMarkers` during fetch,
  swapping atomically upon receipt; screen renders non-blocking
  `fleet_map_revalidating_indicator` (`LinearProgressIndicator`) across the
  top of the map instead of blanking the canvas (audit E16).
- `employee_jobs_screen.dart:230-265`: Refreshes render
  `LinearProgressIndicator(key: Key('employee_jobs_refresh_indicator'))` when
  jobs already exist, preventing silent content swaps under active couriers
  (audit E19).
- `employee_home_screen.dart:50-65`: Incoming `job_alert` WebSocket/push
  signals trigger transient
  `ThemedSnackBar.showSuccess(key: Key('job_alert_dispatch_snackbar'), l10n.newDispatchAlertMessage)`
  (audit E19).

## 13. Focal hierarchy elevation on multi-card control panels

When a control panel contains multiple configuration cards, the primary
operational entity (e.g. active employee roster) must visually dominate over
secondary or destructive management forms. Primary entities use elevated cards
(`variant: ThemedCardVariant.elevated`, semantic top accent colors, and domain
icon badges). Secondary or destructive operations (e.g. worker freeze/unfreeze)
must be demoted into warning-styled or collapsed disclosure panels. Deceptive
static or mock chips with no real functionality must be excised completely in
favor of genuine pending action queues.

Reference implementations:
- `employee_screen.dart:194-700`: Roster card elevated with primary brand
  accent and user-group badge; destructive freeze/unfreeze form demoted to an
  administrative warning panel with warning border and
  `ExpansionTile(key: Key('freeze_worker_expansion_tile'), initiallyExpanded: false)`
  (audit E23).
- `owner_configuration_screen.dart`: Business identity and pricing cards
  elevated with semantic icons (`Icons.storefront_outlined`,
  `Icons.payments_outlined`) and primary save CTA wrapped in dedicated
  `ThemedPanel` (audit E24).
- `home_screen.dart:1046-1120`: Excised static mock maintenance chip
  ("Van #402 engine warning") that routed to employee roster without
  maintenance functionality, preserving only real pending reconciliation queue
  alerts (`urgent_reconciliation_chip`) (audit E25).

## 14. Card-geometry-matched skeleton loaders

Initial loading states for structured lists, rosters, and administrative queues
must render animated skeleton placeholders matching the exact card geometry of
loaded data (avatar, title, subtitle badges, and actions), rather than bare
centered spinners. This prevents layout shifts and gives users immediate spatial
orientation. Reserve pull-to-refresh spinners exclusively for subsequent
updates when data is already displayed.

Reference implementations:
- Shared `skeleton_loader.dart`: Extended with `EmployeeRosterCardSkeleton`
  (worker avatar, username, email, ID badge, status chip),
  `AuditTrailCardSkeleton` (audit action, timestamp, client IP),
  `LedgerCardSkeleton` (financial category icon, description, job ID, amount),
  and `ReconciliationCardSkeleton` (escrow order header, failure detail rows,
  dual resolution actions).
- `employee_screen.dart:130-180`: Roster initial load uses `ListView.separated`
  of `EmployeeRosterCardSkeleton` (`employees_roster_skeleton_list`); audit trail
  uses `ListView.builder` of `AuditTrailCardSkeleton` (`audit_trail_skeleton_list`)
  (audit E1).
- `owner_history_screen.dart`: All three history tabs render dedicated card
  skeletons during initial fetch: `AuditTrailCardSkeleton` list
  (`owner_history_activity_skeleton_list`), `EmployeeJobCardSkeleton` list
  (`owner_history_jobs_skeleton_list`), and `LedgerCardSkeleton` list
  (`owner_history_ledger_skeleton_list`) (audit E2).
- `owner_reconciliation_queue_screen.dart`: Supplies `ReconciliationCardSkeleton`
  list (`reconciliation_queue_skeleton_list`) as `loadingWidget` to
  `ListScreenTemplate` (audit E3).

Test-harness note: `SkeletonLoader` uses an infinite shimmer loop on
`AppMotion` tokens; widget tests must pump fixed frames (`tester.pump()` and
`tester.pump(const Duration(milliseconds: 50))`), never `pumpAndSettle()`, which
would time out against the infinite animation.

## Scope (what is NOT in this doc yet)

Rules 1–4 came from audit group A (A1–A10); Rules 5–7 from audit group C
(C1–C10); Rules 8–14 from audit group E (E1–E26). All 26 E-group findings are
addressed across these patterns (0 deferred). Audit group S (Shared/System,
S1–S16) remains deferred for a future pass following the same extract-after-building
discipline.
