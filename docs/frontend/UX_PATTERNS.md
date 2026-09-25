# Frontend UX Patterns (Established by Fixing)

> Source: these rules were extracted from the actual diffs that fixed audit
> groups A (Auth) and C (Customer) of
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
the single exit; no dialog named outside this set was touched.

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

## Scope (what is NOT in this doc yet)

Rules 1–4 came from audit group A (A1–A10); Rules 5–7 from audit
group C (C1–C9). Deliberately unwritten: C10 (duplicate retry CTA —
a one-off structural dedup, not a reusable pattern), Confirmation
Dialog, Empty State, Skeleton Screens as a general rule, Optimistic
UI, and Progressive Disclosure. Later audit groups (employee/owner,
shared) add their sections here only when their fixes land, following
this same extract-after-building discipline.
