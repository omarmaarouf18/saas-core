# Worklog: FE-AUTH-ACCOUNT — auth, account, notifications and support on redesign A

## Task and scope
- Task ID: FE-AUTH-ACCOUNT
- Item IDs covered: 0 (FE-CUST-2 follow-ups), 1 (sign in / sign up / OTP), 2 (password reset), 3 (account), 4 (notifications), 5 (support), 6 (update required), 7 (tests + goldens)
- Allowed paths (lane): frontend/lib/features/auth/** and frontend/lib/features/account/** (new), frontend/lib/features/customer/** (wiring only), frontend/lib/ui/** (additive), frontend/lib/core/feature_flags.dart, the AuthGate / route switch in main.dart and screens/home_screen.dart only where the flags select old vs new, ARB + generated l10n, frontend/test/**. Providers: additive, tested changes only.
- Agent branch: agent/FE-AUTH-ACCOUNT-auth-account-support, created from logic-exploitation (125c8e54, FE-DS, FE-CUST-1, FE-CUST-2 merged)

## Decisions taken
- **Flags.** `kRedesignAuth` (`QD_REDESIGN_AUTH`, default false) selects the signed-out screens and the update-required screen in three places: main.dart AuthGate (→ `RedesignAuthGate`), main.dart `onUpdateRequired` (→ `RedesignUpdateGate`), home_screen.dart's `user == null` branch (→ `signedOutRootScreen()`). Customer account, notifications and support open from the customer shell and stay behind `kRedesignCustomer`. Owner / courier keep SettingsScreen. home_screen.dart also lost its now-unused `login_screen.dart` import.
- **New gate, not the old one.** The old AuthGate shows the splash whenever `AuthProvider.isLoading` is true, which is also true during every sign-in request: it unmounts the sign-in screen mid-request, so a 2FA sign-in started from the app's first screen never reaches the code screen (reproduced with a throwaway widget test: `login called`, `splash: 1`, `OTP screens found: 0`). `RedesignAuthGate` shows the splash only until the first session restore ends. The old gate is unchanged (see follow-ups).
- **Commit per item, in item order.** Item 1 opened the old ForgotPasswordScreen through `AuthNav.openPasswordReset` so it compiled on its own; item 2 switched that to the new page. Widget tests ship with each item; item 7 adds goldens and flag tests.
- **Item 0.** "Cheapest" now always sends `sort_by=none` and sorts client-side by opening fee (`baseFareOf`), then `tenant_price_per_km`, closed last, stable; `final_price` is not used. QdRings got a gallery section (`rings`).
- **One shared code form** (`OtpCodeForm`): sign-in / sign-up code page, reset step 2, email change step 2. 60 s client resend countdown (the server has none, see follow-ups); counted in timer ticks so tests can drive it. A full code verifies on its own; a second completion during a verify is ignored.
- **Password reset is one page in three steps** with a step bar. Back goes one step back (step 3 → step 2, as the old screens did). A 401 / missing token on step 3 says the reset ran out and "Start again" goes to step 1 with the email kept. Success pops to sign in with the email prefilled.
- **Sign-up preselects "customer"** (the mockup); the old screen preselected owner.
- **weak_password localized.** The provider's banner text for it is English (mapped without a BuildContext); the new pages read the new `lastErrorCode` / `lastErrorReason` and call `weakPasswordServerMessage` with the current locale.
- **Account page.** Mockup's "notifications" switch became a row that opens the notifications page (there is no push opt-out API). The security state is the row's subtitle, not a trailing value: the mockup's value overflowed at 360 dp (`QdListTile.value` is not flexible). Wallet is a disabled "Soon" row as in the mockup. Language / theme open choice sheets (phone setting / Arabic / English; light / dark / phone setting).
- **My details** saves username + phone only; addresses have their own page and save on every change (add / edit / delete with undo), restoring the list and offering retry if a save fails. The old screen saved addresses with the profile button. Edit is new.
- **Email change** is a sheet (no outside-tap / drag dismiss, close disabled while a request runs), step 2 on the code boxes with resend (= the same request again). New client check: the new email must differ from the current one.
- **Notifications.** Day groups (Today / Yesterday / date), relative times under 12 h. Known customer types get localized copy (server text is English and `job_accepted` quotes the fare in "$"); others show the server text. Category filter dropped (not in the mockup). Swipe to dismiss, with a semantics action. Links: `notificationTarget(n, role)` returns nothing unless role is `user`; order types open the shell's My orders tab (through `OrdersTabScope`, provided by the shell); ticket types open the ticket chat (id parsed from the body) or the support list.
- **Support.** The ticket API takes only `context_id`, so subject + description stay packed in it, same format as the old dialog (`Job #<id> - <subject>: <description>`), and are parsed back for the cards. Tabs: open / resolved (the "all" filter is dropped). Card: subject, status chip, "About order #QD-… · when" or "General · when", and the description (or the resolution once resolved): there is no "last message" in the list API.
- **Ticket chat = CustomerChatPage** with new optional `ticketId` / `resolved` / `resolutionNote` / `pickAttachment`: attach (jpg / png / pdf, ≤ 10 MB, not empty) through `uploadTicketAttachment`, file / image rows in bubbles, system lines for `ticket_resolution` / `system` messages, read-only (composer replaced) when resolved on open or when a resolution arrives. Job chat behaviour is unchanged (system lines are ticket-only); its goldens did not change.
- **Order view complaint** (FE-CUST-2 active view, wiring) opens the new complaint sheet with the order preselected, then a notice; it does not open the chat (the old dialog did not either).
- **Update required.** url_launcher is not a dependency, so the button copies the download link (also shown, selectable) and says so. The server's `download_url` is used; without it, the same release URL the old screen hard-coded. Versions are shown only when the server sent them (the old screen showed made-up defaults). The "what's new" list (static copy) is dropped. Back is blocked.
- **Strings**: new ARB keys prefixed `auth*`, `reset*`, `acct*`, `ntf*`, `sup*`, `upd*` (191 keys); no existing key changed. Reused: `retry`, `passwordToo*` (through `weakPasswordServerMessage` / `validatePassword`), `qdStatus*`.
- **Formatting slip, fixed.** `dart format test` in the support commit reformatted five unrelated old test files (formatting only); a separate commit restores them byte-identical to the base. No amend.

## Changes per commit (message only — NO SHAs)
1. `FE-AUTH-ACCOUNT: FE-CUST-2 follow-ups (cheapest sort by tariff, QdRings in gallery)` — item 0
2. `FE-AUTH-ACCOUNT: sign in, sign up and code entry behind QD_REDESIGN_AUTH (A-Login, A-Signup, A-OTP)` — item 1
3. `FE-AUTH-ACCOUNT: password reset in three steps on the new components` — item 2
4. `FE-AUTH-ACCOUNT: customer account (A-Settings) with details, addresses, 2FA and email change` — item 3
5. `FE-AUTH-ACCOUNT: notifications (A-Notifs) with role-checked links and mark all read` — item 4
6. `FE-AUTH-ACCOUNT: support (A-Tickets), complaint sheet and ticket chat on CustomerChatPage` — item 5
7. `FE-AUTH-ACCOUNT: restore five unrelated test files reformatted by mistake in the support commit`
8. `FE-AUTH-ACCOUNT: update-required screen behind QD_REDESIGN_AUTH (button copies the download link)` — item 6
9. `FE-AUTH-ACCOUNT: goldens for the auth, account, notifications and support pages; flag tests` — item 7
10. `FE-AUTH-ACCOUNT: worklog` (this file)

## Items
0. **done** — cheapest = client tariff sort with `sort_by=none` (unit + widget test); QdRings gallery section + 2 gallery goldens.
1. **done** — LoginPage, SignupPage, OtpPage, `RedesignAuthGate`, flag wiring.
2. **done** — ResetPasswordPage (3 steps).
3. **done** — AccountPage, MyDetailsPage, EmailChangeSheet, SavedAddressesPage, SecurityPage; shell Account tab.
4. **done** — NotificationsPage + notification_rules; customer bell and account row open it.
5. **done** — TicketsPage, NewComplaintSheet, ticket chat on CustomerChatPage; account row, notification links and the order view complaint use them.
6. **done** — UpdateRequiredPage + RedesignUpdateGate (copy link instead of opening it: no url_launcher).
7. **done for tests and goldens** — widget tests per screen with fake providers, 34 screen goldens + 2 gallery goldens, flag tests for both flags. Device run **not done** (see Unverified).

## Verification

Literal output, local Flutter 3.44.6 (same as ci.yml), captured on the final code tree (after commit 9, before this worklog):

```
$ flutter analyze
Analyzing frontend...                                           
No issues found! (ran in 0.8s)
$ flutter test
00:52 +1305: All tests passed!
$ git diff --stat logic-exploitation..HEAD -- frontend/test/goldens
(end)
$ git diff --stat logic-exploitation..HEAD -- frontend/test/features/customer frontend/test/ui/goldens | grep png
 .../ui/goldens/qd_gallery_auth_ar_rtl_360x800.png  | Bin 0 -> 23529 bytes
 .../ui/goldens/qd_gallery_auth_en_ltr_360x800.png  | Bin 0 -> 25693 bytes
 .../ui/goldens/qd_gallery_rings_ar_rtl_360x800.png | Bin 0 -> 16253 bytes
 .../ui/goldens/qd_gallery_rings_en_ltr_360x800.png | Bin 0 -> 15975 bytes
```

`(end)` is a marker echoed after the command: the diff on `frontend/test/goldens` printed nothing, so the existing screen goldens are byte-identical. No customer feature golden changed (item 0 did not change the market goldens: they render the default "nearest" sort); only 4 gallery goldens were added.

`logic-exploitation` moved after this branch was cut (FIX-COD-RECON merge, backend only), so `git diff --stat logic-exploitation..HEAD` also lists those backend files as reversed. Against the task's base commit:

```
$ git diff --stat 125c8e54..HEAD | tail -5
 .../ui/goldens/qd_gallery_auth_en_ltr_360x800.png  |  Bin 0 -> 25693 bytes
 .../ui/goldens/qd_gallery_rings_ar_rtl_360x800.png |  Bin 0 -> 16253 bytes
 .../ui/goldens/qd_gallery_rings_en_ltr_360x800.png |  Bin 0 -> 15975 bytes
 frontend/test/ui/qd_auth_kit_test.dart             |  129 +++
 99 files changed, 11573 insertions(+), 92 deletions(-)
$ git diff --stat 125c8e54..HEAD -- services tests/e2e
(end)
```

`git log --oneline logic-exploitation..HEAD` before this worklog commit, short SHAs removed per CLAUDE.md (they are in the chat report):

```
FE-AUTH-ACCOUNT: goldens for the auth, account, notifications and support pages; flag tests
FE-AUTH-ACCOUNT: update-required screen behind QD_REDESIGN_AUTH (button copies the download link)
FE-AUTH-ACCOUNT: restore five unrelated test files reformatted by mistake in the support commit
FE-AUTH-ACCOUNT: support (A-Tickets), complaint sheet and ticket chat on CustomerChatPage
FE-AUTH-ACCOUNT: notifications (A-Notifs) with role-checked links and mark all read
FE-AUTH-ACCOUNT: customer account (A-Settings) with details, addresses, 2FA and email change
FE-AUTH-ACCOUNT: password reset in three steps on the new components
FE-AUTH-ACCOUNT: sign in, sign up and code entry behind QD_REDESIGN_AUTH (A-Login, A-Signup, A-OTP)
FE-AUTH-ACCOUNT: FE-CUST-2 follow-ups (cheapest sort by tariff, QdRings in gallery)
```

`make check` ran before every commit (scope: docgen frontend). Last lines before commit 9:

```
00:49 +1305: All tests passed!
== pre-push gate: all checks passed (scope: docgen frontend) ==
```

New goldens (360x800, light, Plex font), all reviewed by eye:
- `frontend/test/features/auth/goldens/auth_{login,signup,otp,reset_email,reset_code,reset_password,update}_{ar_rtl,en_ltr}_360x800.png` (14; `signup` shows the empty-form validation)
- `frontend/test/features/account/goldens/acct_{account,suspended,details,addresses,security,email_change,notifications}_{ar_rtl,en_ltr}_360x800.png` (14)
- `frontend/test/features/account/goldens/sup_{tickets,complaint,ticket_chat}_{ar_rtl,en_ltr}_360x800.png` (6)
- `frontend/test/ui/goldens/qd_gallery_{rings,auth}_{ar_rtl,en_ltr}_360x800.png` (4)

## Behaviour checklist (old → new)

login_screen
- ✓ Email required + format check; password required.
- ✓ Server error as a persistent banner with retry (the transient error snackbar is dropped: one place).
- ✓ Accounts signed in directly (2FA off, employees) → home; others → code page with the dev OTP.
- ✓ Theme switch (light → dark → system cycle) and language switch.
- ✓ Links to password reset and sign-up with a double-tap guard.
- ✓ Loading state on the button; a second tap during a request is ignored.

signup_screen
- ✓ Name 3–30 runes, Latin / Arabic letters, digits, spaces, `_`; the field follows a Latin name's direction (LTR) in Arabic.
- ✓ Email check; SEC-03 password length rules (min 8 runes, max 72 bytes).
- ✓ Customer or business owner only; note that couriers get accounts from their owner. Default changed to customer (mockup).
- ✓ Server error banner with retry; `weak_password` localized.
- ✓ Success → code page (replacing sign-up) with the dev OTP.

otp_screen
- ✓ Dev OTP auto-fill + banner, also after a resend.
- ✓ 6 boxes, paste support, auto-advance, backspace (single hidden field).
- ✓ Full code verifies on its own; incomplete code refused with a message.
- ✓ Verify and resend failures, each with its own retry.
- ✓ Resend success notice. New: 60 s resend countdown.
- ✓ Success replaces the stack with home.
- Dropped by the mockup: logo, brand footer, trust note.

forgot_password / reset_password_otp / reset_password_new
- ✓ Email prefilled from sign in; code request with dev OTP; resend = the same request.
- ✓ verifyResetCode arms the single-use token; a 429 lockout shows the server text without retry.
- ✓ Full code verifies on its own, in-flight guard.
- ✓ New password: SEC-03 length, both fields equal.
- ✓ Missing token / 401 → "ran out, start again" → step 1 (no doomed request when no token).
- ✓ `weak_password` reasons localized (EN + AR tested).
- ✓ Success notice → sign in (prefilled).
- ✓ Step-specific back (3 → 2 → 1 → close).

settings_screen (customer path) + my_account_screen
- ✓ Profile re-fetched on open, load error with retry.
- ✓ Suspension banner with the server reason (default copy otherwise); edits disabled while suspended (details save, email change, addresses).
- ✓ Username required, phone free text, email read-only with "change".
- ✓ Save error = provider message else friendly; success notice and back.
- ✓ Addresses: required, max 10, delete with undo at the same index. Changed: saved immediately; new: edit.
- ✓ 2FA on: switch locked with a spinner for the round trip, notice on success / error.
- ✓ 2FA off: confirm, then password dialog (no outside-tap close); 401 → wrong password, 429 → server lockout text, other → provider message; password cleared after use.
- ✓ Theme (light / dark / system) and language (phone / English / Arabic).
- ✓ Support tickets entry; notifications entry (was an app-bar bell).
- ✓ Logout: notifications stream closed, session revoked, signed-out start screen (flag-selected).
- Dropped: role badge and "active" status badge (the suspended banner remains); KYC row is owner / employee only and they keep SettingsScreen.

email_change_dialog
- ✓ Two steps (new email → code), dev OTP filled with a banner, provider errors, no outside-tap close, close disabled during a request, success notice. New: resend after the countdown, same-email check.

notifications_screen
- ✓ History fetched on open when empty; loader (not the empty state) during the first fetch.
- ✓ Pull to refresh (full reload), load more.
- ✓ Tap marks read (500 ms double-tap guard).
- ✓ Dismiss one; clear all after a confirmation.
- ✓ Live / offline state; stream error with reconnect (initSse).
- ✓ Day grouping (today / yesterday, then dates instead of "earlier").
- ✓ "Mark all read" wired (existed only in the provider).
- ✓ Deep links check the role: customers only, customer screens only (the old screen opened EmployeeJobsScreen, KYC, wallet for anyone).
- Dropped: category filter chips (not in the mockup), the separate "view ticket" link (the card itself links).

customer_tickets_screen + create_ticket_dialog
- ✓ Full reload on open, after a ticket and on pull to refresh; loader only while empty; error with retry.
- ✓ Resolution note on resolved tickets.
- ✓ New complaint: subject + description required (trimmed), same `context_id` format, error shown in the sheet, no outside-tap close, list reload then chat opens.
- ✓ Fixed: the description field had the customer-service subtitle as label and hint.
- New: order picker (recent 6 + none; fetched when not loaded; works without orders on failure).
- Dropped: "all" filter, the agent-id line, the ticket id in the success notice.

ticket_chat_screen
- ✓ History then websocket on `ticket:<id>`, disconnect on close.
- ✓ Resolved on open or on a live `ticket_resolution` message → read-only with the resolution.
- ✓ Attach jpg / png / pdf; empty and > 10 MB refused; upload failure notice; in-flight guard.
- ✓ Image attachments preview, others as a file row with size.
- ✓ Send guard, failure with retry, history error banner with retry, denied state (from CustomerChatPage).
- Gap: no pull-to-refresh of the history (CustomerChatPage has none; the error banner's retry reloads).

update_required_screen
- ✓ Versions from the server info, back blocked, shown once per session, stack replaced.
- ✓ Fixed: the button did nothing; it now copies the download link (url_launcher is not a dependency).
- Dropped: made-up default versions, the static "what's new" list.

Providers
- auth_provider: one additive change (below). notifications_provider, chat_provider: unchanged.

## Provider changes
- `AuthProvider.lastErrorCode` / `lastErrorReason`: machine code and raw server message of the last failed auth call, set next to `error` (through a private `_fail(e)` that replaces the eleven `_error = _authBannerMessage(e)` lines) and cleared wherever `error` is cleared. Banner text (`error`) is unchanged. Why: `weak_password` reasons were only available as English text. Tested in `test/features/auth/auth_provider_error_code_test.dart` (signup, reset, login, non-API error, clearError).

## Components added to lib/ui
- `QdOtpInput` (code boxes, paste), `QdOptionCard` (radio card), `QdThemeScope` + `qdPageRoute` (redesign theme for pages outside the customer shell). Widget tests in `test/ui/qd_auth_kit_test.dart`; gallery section `auth` (QdOtpInput, QdOptionCard) with 2 goldens.

## Data gaps hit
- **Notification → order**: notifications carry no job id (notification-service does not store one; `dispute_resolved` sends `job_id` but it is dropped), so order notifications open My orders, not the order.
- **Notification copy**: server titles / bodies are English; `job_accepted` quotes the fare in "$". Localized client-side for known customer types only.
- **Ticket subject / description / last message**: the create API takes only `context_id`; `subject` is never set; the list has no last message. Cards show the parsed subject and description.
- **Resend for sign-in codes**: `/auth/resend-otp` answers success for an existing account without sending a new code (it only re-sends for pending sign-ups), so "send again" on the 2FA code screen does nothing server-side (same as before).
- **Saved addresses**: plain strings, no coordinates (no map, as the task said).
- **Error copy**: `friendlyErrorMessage` is English; non-coded errors stay English in the Arabic UI (as in the old screens).

## Unverified
- **Device run** with `--dart-define=QD_REDESIGN_AUTH=true --dart-define=QD_REDESIGN_CUSTOMER=true`: not run. No Android device / emulator here (same as FE-CUST-1 / FE-CUST-2); everything is covered only by widget tests with fake providers.
- **Real services**: SSE stream, websocket, ticket attachment upload, file picker, clipboard and the 426 gate were not exercised against a backend or a device.
- **CI rendering of the new goldens**: generated locally (Fedora, Flutter 3.44.6), not yet seen on ubuntu-latest; regen-goldens.yml already covers `test/features/` and `test/ui/`.
- **Dark mode**: smoke-tested only (account theme switch builds without exceptions); no dark goldens (the task asked for light).
- **Image attachment preview** renders through `Image.network` with a file-row fallback; only the fallback ran in tests (no network in tests).

## Follow-ups / out-of-lane findings
- **Old AuthGate bug** (main.dart, flag off): the splash replaces the root LoginScreen during every sign-in request, so 2FA sign-in from the first screen never opens the code screen. Fix: show the splash only for the first restore (as `RedesignAuthGate` does). main.dart was in lane only for the flag switch.
- **utils/logout_helper.dart** always pushes the old LoginScreen: with QD_REDESIGN_AUTH on, owner / courier logout from SettingsScreen lands on the old sign-in. It should call `signedOutRootScreen()` (out of lane).
- **Backend**: resend-otp for existing accounts (2FA) does not send a code; notifications should carry `job_id` (store + payload) for order deep links; tickets could accept `subject` / `description` and return a last message; a resend cooldown on the server.
- **Old LoginScreen** overflows by 32 px at 360 dp with the test font (seen in `test/features/account/flags_test.dart`; that test uses the default viewport).
- `dart format test` reformats five old test files (auth_splash_gate, customer_home_screen, notifications_dispose_race, password_policy_sec03, sec07b_status_flows): they are not formatted on the base, so the format gate apparently checks changed files only.
- FE-CLEANUP: delete LoginScreen, SignupScreen, OtpScreen, the three reset screens, UpdateRequiredScreen + UpdateGate, MyAccountScreen, NotificationsScreen, CustomerTicketsScreen, TicketChatScreen, EmailChangeDialog, CreateTicketDialog once both flags ship and owner / courier have their own account pages; then `QD_REDESIGN_AUTH`.
- `docs/frontend/STATUS.md` should list `lib/features/auth/**`, `lib/features/account/**` and the new flag (owner).
- This branch is behind `logic-exploitation` by the FIX-COD-RECON merge (backend only, no shared files); rebase before the merge.

## Open questions
- Sign-up preselects "customer" (mockup) instead of "owner" (old screen). OK?
- The account mockup's notifications switch is a row to the notifications page (no push opt-out API). OK, or should a backend setting come first?
- Wallet shown to customers as a disabled "Soon" row (mockup). OK?
- Saved addresses save on every change instead of with a save button. OK?
- Update screen: keep the old hard-coded GitHub release URL as the fallback when the server sends no `download_url`, or show no link?
- Resend countdown: 60 s, client-only. The right value?
- Order view complaint: notice only, no chat opened (as before). OK?
