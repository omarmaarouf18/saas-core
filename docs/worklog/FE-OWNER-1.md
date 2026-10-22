# Worklog: FE-OWNER-1 — owner daily work on redesign A, behind QD_REDESIGN_OWNER

## Task and scope
- Task ID: FE-OWNER-1
- Item IDs covered: 0 (customer wallet row), 1 (OwnerShell + flag), 2 (Today), 3 (Orders), 4 (Order detail), 5 (Payment review), 6 (Team, courier page, add-courier sheet), 7 (tests + goldens)
- Allowed paths (lane): frontend/lib/features/owner/** (new), frontend/lib/ui/** (additive), frontend/lib/core/feature_flags.dart, frontend/lib/screens/home_screen.dart (owner branch switch only), ARB + generated l10n, frontend/test/**, item 0's frontend/lib/features/account/account_page.dart. Providers: additive, tested changes only.
- Agent branch: agent/FE-OWNER-1-owner-today-orders-team, created from logic-exploitation (40965554)
- Not touched: JOB-V2-BE's and WF-GOWORK-OFF's paths, hot paths, AI_CONTEXT, changelogs, STATUS.md, frontend/lib/ui/** (no component was needed), the old owner screens and widgets.

## Decisions taken
- **Commit order follows dependencies, not item numbers**, so each commit compiles and passes `make check` alone: 0, shared foundation (rules, controller, nav, provider fields), 4 (detail), 3 (orders, links to detail), 5 (payment review), 6 (team), 2 (Today, links to all of them), 1 (shell + flag + home_screen switch), 7 (goldens + controller tests), worklog. Widget tests shipped with each page (as FE-CUST-2 did); item 7 added the goldens and the controller tests; flag and shell tests went with item 1. Goldens were generated and reviewed while building each page and committed in item 7.
- **Flag**: `kRedesignOwner` (`QD_REDESIGN_OWNER`, default false). home_screen.dart's owner branch returns `ownerRootScreen(legacy: () => _buildOwnerShell(user, l10n))` (one import + that return line). Off = the unchanged old dashboard.
- **Theme**: the shell renders under `QdThemeScope`; new pages are pushed with `OwnerNav.push` (redesign theme + the shell's `OwnerDataController` re-provided, because pushed routes are outside the shell's providers). The Account tab is the old `SettingsScreen` under the app theme captured outside the scope. Sheets wrap themselves in `QdThemeScope` and get data through callbacks.
- **Own loading state**: `OwnerProvider` shares one `isLoading` / `error` across all calls, so `OwnerDataController` runs profile → jobs → employees one after the other and reads new per-call errors (see provider changes). A refresh while one runs joins it.
- **Today's numbers** (honest only): "ongoing now" counts every loaded ongoing job; "delivered today" and "cash recorded today" count jobs **created** today (device calendar day), because `created_at` is the only fixed job timestamp (`updated_at` moves with any change, there is no completed-at). Cash is the sum of `actual_cash_amount` — which the owner DTO **does** return (FIX-COD-RECON era DTO), contrary to the prompt's example — over today's completed COD jobs; if one of them has no amount the tile is left out. A caption says what is counted; when all 100 loaded jobs (server limit in `GetJobsByOwner`) are from today the counts show "N+" with a note.
- **Courier state** from the lists we have: on a job = an `assigned` / `active` job with their `employee_id`; free = active account and no such job; frozen = `is_active == false`. No presence data exists, so there is no online / offline / last seen; the chip says "Free", not "Available".
- **Orders tabs**: ongoing = `isOngoing` (core/job_rules.dart); cancelled = cancelled / canceled / unavailable; done = everything else (completed and unknown statuses). Search matches the order id (with or without `#QD-`) or the **assigned** courier's name.
- **Rows with a pending cancellation request** are tinted and show only the "cancellation requested" chip (O-Orders); both chips at once were truncated at 360 dp. The detail page shows the status chip and the request card. A "pending" request on a finished job is ignored (not actionable).
- **409 on respond-cancellation**: localized "this request already changed, it may have run out" + the order list is reloaded. The old card showed the raw English server text instead (see open questions).
- **Owner cancel**: same statuses as the old card (`pending`, `active`), same reason rule, same COD vs held-amount wording and success messages; the sheet is not dismissible by an outside tap / drag (like CancelJobDialog) and keeps errors inline.
- **Freeze / unfreeze**: one sheet is both the confirm step and the password prompt (O-Employee: "we'll ask for your password"). Errors mapped from the auth-service handler: 403 "invalid owner credentials" → wrong password (field cleared), 403 "…KYC approval is pending" → KYB first, 402 `upgrade_required` → paid plan, 503 → SEC-07b "temporarily unavailable" copy, 429 → server text, other → friendly message.
- **Payment review** keeps one resolution at a time (every button disabled while a resolve is in flight); the old search and category filters are not in O-Recon and were dropped. Both actions are secondary buttons, stacked full width (the mockup uses two outlined buttons; side by side they truncated in English).
- **Customer on the order**: the owner DTO has `user_id` only, so the row says "Account <first 6 id chars>".
- **Today header**: the owner's username above "Today" (no company name is loaded; the services list is not fetched by these pages).
- **One gold button per screen** on Today: the oldest cancellation request's "Respond" is gold, other rows are secondary.
- **Links to FE-OWNER-2 screens** live in a "Your business" group on Today (service setup, wallet, subscription, activity and history = OwnerHistoryScreen) plus payment review and all orders; fleet map from Team, the order detail and the courier page; KYB upload from the banner; notifications from the bell.
- **Strings**: 176 new ARB keys prefixed `own` + capital (`ownTodayTitle`, …), Egyptian Arabic; no existing key changed (the customer `acctWallet` / `acctSoon` keys stay, now unused). After the goldens, the EN request buttons were shortened to "Keep order" / "Approve" (item 7 commit).
- **Formatting**: `dart format` ran only on new / edited files; no unrelated file changed.

## Changes per commit (message only — NO SHAs)
1. `FE-OWNER-1: hide the wallet "coming soon" row on the customer account page` — item 0
2. `FE-OWNER-1: owner data rules, controller and additive OwnerProvider fields` — shared prerequisite
3. `FE-OWNER-1: owner order detail page (O-Order)` — item 4
4. `FE-OWNER-1: owner orders list (O-Orders)` — item 3
5. `FE-OWNER-1: owner payment review (O-Recon)` — item 5
6. `FE-OWNER-1: team, courier page and add-courier sheet (O-Team, O-Employee)` — item 6
7. `FE-OWNER-1: owner Today page (A-Owner)` — item 2
8. `FE-OWNER-1: OwnerShell behind QD_REDESIGN_OWNER` — item 1
9. `FE-OWNER-1: owner page goldens and controller tests` — item 7
10. `FE-OWNER-1: worklog` (this file)

## Items
0. **done** — AccountPage (customer shell only) no longer shows the disabled wallet row; only `acct_account_*` and `acct_suspended_*` goldens changed (both render AccountPage).
1. **done** — OwnerShell: Today / Orders / Team / Account (= SettingsScreen), bell → NotificationsScreen, flag-gated in home_screen.dart.
2. **done** — Today with KYB banner, needs-you, honest tiles, team now, rating summary, empty / error states.
3. **done** — Orders tabs, search, chips incl. cancellation request, pull to refresh, tap → detail.
4. **done** — Order detail with request card (approve / keep, confirm sheet, 409), route + fleet map link, customer, courier, payment, recorded cash, created time, distance_review note, owner cancel.
5. **done** — Payment review list, reason chip, amounts, note, release / refund with confirm, one at a time, error with retry, COD note.
6. **done** — Team (all / active / frozen, state chips, current job), courier page (counts from loaded data, current job, all orders, map, freeze / unfreeze with password), add-courier sheet. KYE status: shown only if the payload carries it — `/auth/employees` does not today (see data gaps).
7. **done** — widget tests per page with fake providers (loading, empty, error, data, 409 race, freeze wrong password), 30 goldens, flag tests. Device run against a backend: **not done** (see Unverified).

## Verification

Literal output, local Flutter 3.44.6 (same as ci.yml), on the final code tree (after commit 9, before this worklog):

```
$ flutter analyze
Analyzing frontend...                                           
No issues found! (ran in 0.8s)
$ flutter test
00:46 +1459: All tests passed!
$ flutter test test/features/owner
00:03 +145: All tests passed!
$ git diff --stat logic-exploitation..HEAD -- frontend/test/goldens
(end)
```

`(end)` is a marker echoed after the command: the diff on `frontend/test/goldens` printed nothing, so the existing screen goldens are byte-identical. Outside the new owner goldens, the only PNGs that changed are the four item-0 account goldens:

```
$ git diff --stat logic-exploitation...HEAD -- frontend/test/features/account/goldens
 .../account/goldens/acct_account_ar_rtl_360x800.png | Bin 30845 -> 28782 bytes
 .../account/goldens/acct_account_en_ltr_360x800.png | Bin 34399 -> 32517 bytes
 .../goldens/acct_suspended_ar_rtl_360x800.png       | Bin 35228 -> 33090 bytes
 .../goldens/acct_suspended_en_ltr_360x800.png       | Bin 40088 -> 38026 bytes
 4 files changed, 0 insertions(+), 0 deletions(-)
```

Linux build with the flag on (compiles; not run, see Unverified):

```
$ flutter build linux --debug --dart-define=QD_REDESIGN_OWNER=true
Building Linux application...                                   
✓ Built build/linux/x64/debug/bundle/frontend
```

`make check` ran before every commit (scope: docgen frontend), all passed. Last line of the check before commit 9:

```
== pre-push gate: all checks passed (scope: docgen frontend) ==
```

The first `make commit` of commit 9 was refused because `frontend/lib/l10n/app_localizations.dart` (EN doc comments) was not in FILES; it was added and the commit went through on the same stamp.

`git log --oneline logic-exploitation..HEAD` before this worklog commit, short SHAs removed per CLAUDE.md (they are in the chat report):

```
FE-OWNER-1: owner page goldens and controller tests
FE-OWNER-1: OwnerShell behind QD_REDESIGN_OWNER
FE-OWNER-1: owner Today page (A-Owner)
FE-OWNER-1: team, courier page and add-courier sheet (O-Team, O-Employee)
FE-OWNER-1: owner payment review (O-Recon)
FE-OWNER-1: owner orders list (O-Orders)
FE-OWNER-1: owner order detail page (O-Order)
FE-OWNER-1: owner data rules, controller and additive OwnerProvider fields
FE-OWNER-1: hide the wallet "coming soon" row on the customer account page
```

`git diff --stat logic-exploitation...HEAD | tail -5` before this worklog commit:

```
 frontend/test/features/owner/owner_shell_test.dart |  139 +++
 frontend/test/features/owner/recon_page_test.dart  |  131 +++
 frontend/test/features/owner/team_pages_test.dart  |  346 +++++++
 frontend/test/features/owner/today_page_test.dart  |  247 +++++
 69 files changed, 9387 insertions(+), 11 deletions(-)
```

New goldens (`frontend/test/features/owner/goldens/`, 360x800, light, Plex font), `own_<name>_{ar_rtl,en_ltr}_360x800.png` for: `shell`, `today`, `today_kyb_pending`, `orders`, `order`, `order_review`, `recon`, `recon_empty`, `team`, `employee`, `employee_frozen`, `add_courier`, `freeze_sheet`, `cancel_sheet`, `respond_sheet` (30 files). All were reviewed by eye; three layout problems found that way were fixed before committing (row fills covering the group border, truncated chips, truncated buttons).

## Behaviour checklist (old → new)

home_screen.dart (owner dashboard)
- ✓ Data on open: profile (KYB status) + owner jobs; also on pull to refresh and when coming back to a data tab. Wallet / subscription / ledger (`fetchDashboardData`) are not shown by the new pages; HomeScreen still loads them (see follow-ups).
- ✓ KYB banner when not approved: under review, rejected (server reason, else default copy), not uploaded; button → KycDocumentUploadScreen.
- ✓ Load error with retry → error state; a failed refresh over loaded data → stale banner.
- ✓ Pending cancellation request: reason, approve / decline behind a confirm (approve destructive), success notices, refresh after. Changed: on Today it is a "needs you" row that opens the order, where the card lives. 409 → localized explanation + reload (old: raw server text).
- ✓ Owner cancel: only `pending` / `active`; required reason; COD plain wording, non-COD held amount (locked escrow > 0, else agreed / proposed / suggested); not dismissible; inline error; COD vs refunded success notice.
- ✓ Bell with unread count → NotificationsScreen.
- ✓ Reconciliation entry points (app-bar gavel, escrow chip, urgent row) → "needs you" row when there are reviews + "Payment review" link always.
- ✓ Fleet map card → Team "on the map", order "see on the map", courier "where they are on the map".
- ✓ Service config card → "Service setup" link; wallet badge / card → "Wallet" link; subscription chip → "Subscription" link; History tab → "Activity and history" link (OwnerHistoryScreen).
- ✓ Rating summary from `fetchRatings(token)`: average + count, loader while loading, hidden on error. New: "no ratings yet" for count 0.
- ✓ Owner jobs preview (3 + view all) → Orders tab. Job card id / status / payment → Orders rows + detail. Locked escrow is no longer printed with "$" (QdMoney, EGP).
- Changed: metrics (jobs count, active fleet X / Y + bar) → ongoing now / delivered today / cash today tiles + "team now"; wallet balance and tier are not shown on Today (links only).
- Dropped: the dismissible urgent-actions row (replaced by "needs you"), the hero card with tenant id, the empty-jobs "manage services" action (the service setup link is on Today).

employee_screen.dart
- ✓ Employees fetched on open and on pull to refresh (the refresh button is gone).
- ✓ All / active / frozen filters. Changed: only "All · N" carries a count.
- ✓ Loading state; the staff-list outage (500, fails closed) is an error state with retry, never "no couriers"; empty state with the add button visible.
- ✓ Courier: name, email (courier page, LTR), active / frozen state. Changed: worker id badge dropped; state now also "on a job" / "free".
- ✓ Register: username 3–30 runes, Latin / Arabic letters, digits, spaces, `_`; email pattern; SEC-03 password policy; server `weak_password` localized; in-flight guard; success notice; roster reload. Changed: the notice no longer prints the new user id.
- ✓ Freeze / unfreeze with the owner's password and a confirm; SEC-07b 503 → "temporarily unavailable"; roster reload. Changed: started from the courier's page (no typing their email, no set-active switch); one sheet confirms and asks for the password; specific wrong-password / KYB / paid-plan messages; localized success notice instead of the server message.
- Dropped: search by username / email on the roster (not in O-Team). The audit trail tab is reachable through "Activity and history" (OwnerHistoryScreen's activity tab).

owner_history_screen.dart (jobs tab)
- ✓ Finished jobs → Done / Cancelled tabs (cancelled also holds `unavailable`).
- ✓ Cancellation reason → order detail row; payment info → detail.
- ✓ Empty and filtered-empty states, error banner, pull to refresh.
- Changed: search matches id or courier name (old: id, customer id, cancellation reason); per-filter counts → ongoing count only.

owner_reconciliation_queue_screen.dart
- ✓ Queue fetched on open, pull to refresh, loading, error with retry, empty state.
- ✓ Card: order reference, failure reason (now a short chip), note, held amount, courier (name instead of id), customer (account id).
- ✓ Refund (destructive confirm) / release (confirm), success notices, failure with the provider's message and a retry that reopens the confirm.
- ✓ One resolution at a time (QA audit A4): every action disabled while a resolve is in flight; re-entry refused.
- Dropped: search, category filter pills, service id line.

Providers / widgets
- ✓ owner_provider: additive fields only (below); every existing call is unchanged.
- ✓ reconciliation_provider, marketplace_provider.fetchRatings: unchanged, used as they are.
- ✓ cancel_job_dialog / confirm_action_dialog: not used by the new pages; their rules (required reason, not dismissible, inline error, destructive confirm) are kept by the owner sheets. The widgets are unchanged.

## Provider changes
- `OwnerProvider.ownerJobJson(jobId)`: raw JSON of each job from the last successful `fetchOwnerJobs`, because `Job.fromJson` drops the owner-only `actual_cash_amount` and `distance_review` (models are outside the lane). Cleared with the list on a non-list payload; kept on a failure (the list is kept too).
- `OwnerProvider.ownerJobsError` / `employeesError`: the error of the last `fetchOwnerJobs` / `fetchEmployees` alone, null after a success; the shared `error` can be cleared by any other call before a page reads it.
- Tested in `frontend/test/features/owner/owner_provider_additions_test.dart` (mock HTTP).

## Components added to lib/ui
- None. Owner-only layout pieces live in `frontend/lib/features/owner/owner_widgets.dart` (info rows, app bar, scrollable centre) and `owner_sheets.dart` / `team_sheets.dart`.

## Data gaps hit
- **Customer name**: the owner job DTO has `user_id` only → "Account <id prefix>".
- **Courier presence / last seen**: not in either list → no online / offline; "free" means "active, not on an order".
- **Courier ID check (KYE)**: `/auth/employees` returns id, username, email, is_active, created_at only. The row appears only if `kye_status` is ever added.
- **Courier rating** (O-Employee "average rating"): not shown; it would need one `/users/ratings` call per courier, and whether that endpoint lets an owner read an employee's ratings was not checked.
- **Completion time**: no completed-at; "today" counts orders created today.
- **Company name** on Today: the owner's username is shown.
- **Offer countdown** ("offered to X · N s left" in O-Orders): `offer_expires_at` exists but the list shows "offered to X" without a ticking countdown.
- **100-job server limit** on the owner jobs list: counts and courier totals cover the loaded jobs only (said on the pages).
- Not shown until JOB-V2-BE lands: ETA, recipient, text address, per-status history.

## Unverified
- **Device / desktop run against a backend** (`flutter run -d linux --dart-define=QD_REDESIGN_OWNER=true`): not run — no owner credentials for a backend in this session. Only `flutter build linux --debug` with the flag was done (it compiles). Every flow is covered by widget tests with fake providers only.
- **Server behaviour read from code, not exercised**: the toggle error bodies (403 messages, 402, 503), the 409 on respond-cancellation, `actual_cash_amount` / `distance_review` in `GET /users/jobs/owner`, the 100-job limit.
- **CI rendering of the new goldens**: generated locally (Fedora, Flutter 3.44.6); not yet seen on ubuntu-latest. regen-goldens.yml already covers `test/features/`.
- **Dark mode**: not checked (light goldens only).
- **Duplicate first load**: with the flag on, HomeScreen's own `_refreshData` (profile, dashboard data, owner jobs) still runs next to the shell's refresh; harmless in tests, not measured on a device.

## Follow-ups / out-of-lane findings
- FE-OWNER-2: service configuration, fleet map (O-Fleet), wallet / subscription, unified activity log, KYB upload, owner settings — all linked from the new shell today.
- home_screen.dart: when the flag is on, skip the old `_refreshData` dashboard fetch (outside "owner branch switch only").
- `docs/frontend/STATUS.md` should list `lib/features/owner/**` and the new flag (owner).
- Backend (JOB-V2 / auth): customer display name in the owner DTO, `kye_status` (and maybe last-seen) in `/auth/employees`, a `completed_at` timestamp.
- Optional: offer countdown on dispatching rows; search on the Team tab if owners with many couriers ask for it.
- FE-CLEANUP: delete the old owner dashboard part of home_screen.dart, EmployeeScreen, the jobs tab of OwnerHistoryScreen and OwnerReconciliationQueueScreen, then the flag, once FE-OWNER-2 ships.

## Open questions
- 409 on a cancellation response: localized "already changed, refreshed" instead of the raw server text the old card showed. OK?
- Freeze / unfreeze: one sheet that confirms and asks for the password, instead of a confirm dialog followed by a password field. OK?
- Orders tabs: `unavailable` under Cancelled, unknown statuses under Done. OK?
- Rows with a pending request show only the "cancellation requested" chip (status chip on the detail page). OK?
- Team search (old roster) dropped because O-Team has none. OK?
- Customer shown as "Account <id>" until the DTO has a name. OK, or hide the row?
