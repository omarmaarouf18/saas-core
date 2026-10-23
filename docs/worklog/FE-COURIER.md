# Worklog: FE-COURIER — courier app on redesign A, behind QD_REDESIGN_COURIER

## Task and scope
- Task ID: FE-COURIER
- Item IDs covered: 1 (job model v2 parsing), 2 (CourierShell, KYE banner, suspended / frozen screen), 3 (offer, C-Offer), 4 (current job, A-Courier), 5 (my jobs, C-History), 6 (courier account rows), 7 (tests + goldens)
- Allowed paths (lane): `frontend/lib/features/courier/**` (new), `frontend/lib/models/job.dart` (additive v2 parsing), `frontend/lib/ui/**` (additive; not touched in the end), `frontend/lib/core/feature_flags.dart`, `frontend/lib/screens/home_screen.dart` (employee branch only), `frontend/lib/features/account/**` (courier rows only), ARB + generated l10n, `frontend/test/**`. Providers additive and tested. No hot path touched; nothing under `services/**` or `tests/e2e/**`.
- Agent branch: agent/FE-COURIER-courier-offer-active-history, created from logic-exploitation at 10b1855c.

## Decisions taken
- **Base**: the prompt says the base has JOB-V2-BE and FE-OWNER-2 merged. At branch time it had JOB-V2-BE but **not** FE-OWNER-2 (FE-OWNER-2 was merged into logic-exploitation after this branch was cut, see "Rebase note" below). FE-OWNER-2 never created a `features/verification` module either (checked every agent branch), so the KYE banner and the account verification row open the existing `KycDocumentUploadScreen`, exactly as the old courier app's verification button did.
- **Commit order = item order**, each commit passing `make check` on its own. Widget tests shipped with the item they test; item 7 added the goldens. Until items 3–5 landed, the Task tab showed a status-chip placeholder for an offer / current job and My jobs was empty (behind the default-off flag).
- **Flag**: `kRedesignCourier` (`QD_REDESIGN_COURIER`, default false). `home_screen.dart` employee branch calls `courierRootScreen(initialIndex:, legacy: () => EmployeeHomeScreen(...))`; off = the old app, unchanged. The old tab order (0 jobs, 1 history, 2 settings) maps onto Task / My jobs / Account.
- **Task tab**: an offer (pending_dispatch) wins, else the current job, else a waiting state (online: "no task right now" + refresh; offline: one tap to become available).
- **Buckets**: courier-finished = completed, cancelled, unavailable and under review (`escrow_reconciliation_required`); those are listed under My jobs. Current = anything else that is not an offer (active, awaiting price, pending, unknown statuses: the old screen listed those as job cards too). With several running jobs one is shown with a banner and a picker (the old screen stacked all cards).
- **Offer**: countdown total = 60 s (user-service `time.Now().UTC().Add(60 * time.Second)`); an offer without `offer_expires_at` counts as over (old rule). The countdown ending refetches (the server expires offers lazily). A 409 / 404 / 410 answer says "this offer is no longer available"; other errors the friendly message; refetch after every answer (old rule).
- **Places**: address text (v2) → landmark note → "Pinned location" (existing `custPinnedLocation`); the note is a second line under an address. Coordinates are never shown.
- **Distances**: straight-line (haversine). "x km from you" only when the location provider already has a position; the trip distance only with a destination. No routing API (ADR-0028 §2.5).
- **Price / cash**: agreed price, else suggested; "not set yet" when neither. "You'll collect cash" for COD, "Order price" otherwise.
- **Maps**: the courier's own position comes from `EmployeeLocationProvider.lastKnownPosition` (the provider already tracks it); no second GPS stream like the old map screen. The offer map is static; the current-job map pans / zooms (pinch) with a recenter button.
- **No `url_launcher`** (not a dependency; pubspec is a hot path): "open in maps" copies the next stop's coordinates (`lat,lng`, pickup until picked up, then the drop-off) and the recipient call button copies the number; each shows a notice saying it was copied and where to paste it.
- **Primary action**: `heading_to_pickup` → "I picked up the order" (`POST /users/jobs/pickup`; 409 → "already marked as picked up", 403 / 404 → "no longer assigned to you", refetch in every case). `picked_up`, or no `sub_status` (pre-v2 jobs), or an unknown phase → "Delivered" (COD: "Delivered, collected <amount>") with a confirm sheet. Nothing while awaiting a price (the negotiation panel acts there).
- **Complete**: COD sends `cash_collected: true` (server requires it); "I collected a different amount" sends `actual_cash_amount` (must be > 0). Non-COD sends `cash_collected: false`. A failure keeps the sheet open with the message (409 → "the order changed" + refetch). On success: `stopTracking()` as before, then a refetch, which restarts the availability heartbeat at once (the old screen only restarted it on the next refresh).
- **Negotiation**: reuses the customer's `counterOfferBounds` / `validateCounterOffer` / `kPriceProposalWindow` (`features/customer/order/order_view.dart`). Error rules ported from the old card: propose 429 verbatim, no retry, no refetch; propose 400 / 409 refetch then raced (`employeeProposalRacedError`) / changed / out-of-range copy; respond 409 → changed, 400 / 429 verbatim, refetch on 400 / 409, retry except 429. Accepting the customer's fare asks first (sheet instead of the old dialog). Buttons stacked full width (side by side the amount labels truncated at 360 dp).
- **Cancellation request**: reason required, sheet not dismissible by an outside tap (old dialog rule), kept open on failure; pending banner hides the button; rejected banner keeps it.
- **job_alert**: refresh + the same notice text as before, but only for alerts that arrive after the shell opened and once per notification id (the old listener fired on every list change while the newest item was a job_alert).
- **Blocked screen**: the auth service reports both a reviewer suspension and a company freeze as `account_status: suspended` (`EffectiveAccountStatus`: suspended or `!IsActive`). With `suspension_reason` the screen says "suspended" and shows the reason; without it neutral "paused" copy that names both the company and Quick Delivery. Actions: check again (profile refetch), support, sign out. Note: a freeze revokes sessions (SEC-07), so a frozen courier is normally signed out; this screen covers the profile read that shows the state.
- **KYE banner copy** does not say the courier is blocked from orders: user-service has no KYE check in dispatch (grep found none), so the banner only says documents are missing / under review / not accepted.
- **Account**: `AccountPage` shows courier rows for role `employee`: verification (status value → document upload), my details, security, language, theme, support, sign out. Saved addresses and the notifications row stay customer-only (the courier shell has the bell). Customer rows and goldens unchanged.
- **Chat**: the shared `CustomerChatPage` on `job:<id>` (title "Customer", courier empty-state copy).
- **ARB**: new keys `cour*` and five `acct*`; no existing key changed (checked with a script against the base).

## Changes per commit (message only — NO SHAs)
1. `FE-COURIER: item 1 - Job model v2 parsing (ADR-0028)`
2. `FE-COURIER: item 2 - CourierShell behind QD_REDESIGN_COURIER`
3. `FE-COURIER: item 3 - offer page (C-Offer)`
4. `FE-COURIER: item 4 - current job page (A-Courier)`
5. `FE-COURIER: item 5 - my jobs page (C-History)`
6. `FE-COURIER: item 6 - courier account rows`
7. `FE-COURIER: item 7 - courier goldens and shell account test`
8. `FE-COURIER: worklog` (this file)

## Items
1. **done**: `Job` parses `sub_status`, `status_history` (`JobStatusHistoryEntry`), `estimated_duration_minutes`, `recipient`, `package_details`, `location.address` / `destination.address`, `courier_phone`, `distance_review`; all optional, wrong types / blank strings → null or empty, never a throw; legacy JSON parses as before (tested field by field). `Job.historyTimeOf`.
2. **done**: CourierShell (Task / My jobs / Account, bell with unread count), KYE banner, blocked screen, controller with the old tracking rule.
3. **done**: offer page.
4. **done**: current-job page, pickup, complete, cancellation, negotiation, location state.
5. **done**: My jobs (availability, permission banner, KYE banner, today's numbers, finished list).
6. **done**: courier account rows.
7. **done**: widget tests (per item) + 20 goldens. Device / emulator run **not done** (see Unverified).

## Provider / model changes and why
- `models/job.dart` (additive): the v2 fields above plus `JobRecipient`, `JobPackageDetails`, `JobStatusHistoryEntry`, `JobDistanceReview`, `JobLocation.address`; `toJson` adds `address` only when present.
- `providers/employee_jobs_provider.dart` (additive, `test/providers/employee_jobs_provider_v2_test.dart`):
  - `pickupJob(jobId)`: `POST /users/jobs/pickup {job_id}` with the bearer token (the handler reads `Authorization` / `requester_token`, not `requester_id`); takes the server's `job` when returned, else marks `picked_up` locally; rethrows with `lastErrorStatusCode`.
  - `completeJobWithAmount(jobId, {cashCollected, actualCashAmount})`: `actual_cash_amount` only when > 0. `completeJob` keeps its exact signature and delegates, because two existing test doubles (`employee_jobs_screen_test.dart`, `employee_jobs_screen_audit_test.dart`) override it and an added parameter broke them.
  - The provider's local job rebuilds (complete, accept fallback, cancellation request, respond-price fallback) now carry the v2 fields; `sub_status` is kept only on the cancellation request (status unchanged), so the current-job page keeps its phase until the refetch.
- `EmployeeLocationProvider`, `MapTrackingProvider`: unchanged.
- Components added to `lib/ui`: **none**. Courier-local widgets instead: `CourierStops` (route with a note line), `CourierMap`, sheets, negotiation panel.

## Verification

Literal output, local, Flutter 3.44.6, captured on the tree of commit 7 (before this worklog):

```
$ flutter analyze
Analyzing frontend...                                           
No issues found! (ran in 0.9s)
$ flutter test
00:59 +1572: All tests passed!
$ flutter test test/features/courier test/providers test/models
00:04 +113: All tests passed!
$ git diff --stat logic-exploitation..HEAD -- frontend/test/goldens
(end)
$ git log --oneline logic-exploitation..HEAD
FE-COURIER: item 7 - courier goldens and shell account test
FE-COURIER: item 6 - courier account rows
FE-COURIER: item 5 - my jobs page (C-History)
FE-COURIER: item 4 - current job page (A-Courier)
FE-COURIER: item 3 - offer page (C-Offer)
FE-COURIER: item 2 - CourierShell behind QD_REDESIGN_COURIER
FE-COURIER: item 1 - Job model v2 parsing (ADR-0028)
$ git diff --stat logic-exploitation...HEAD | tail -5
 .../features/courier/negotiation_panel_test.dart   | 174 +++++
 .../test/features/courier/offer_page_test.dart     | 150 ++++
 frontend/test/models/job_v2_test.dart              | 200 +++++
 .../providers/employee_jobs_provider_v2_test.dart  | 191 +++++
 58 files changed, 8423 insertions(+), 20 deletions(-)
```

`(end)` is a marker echoed after the command: the diff on `frontend/test/goldens` printed nothing, so the old screen goldens are byte-identical. The `git log` lines are shown with their short SHAs removed, per CLAUDE.md (they are in the chat report).

Other goldens: `git diff --stat logic-exploitation...HEAD -- '*.png' ':!frontend/test/features/courier/goldens'` (three-dot = this branch's own changes) printed nothing, so the existing customer, owner, account, auth and ui goldens are untouched. The two-dot form lists 10 owner goldens because logic-exploitation moved after this branch was cut (FE-OWNER-2 merge); those are not changes of this branch.

`make check` ran before every commit (scope: docgen frontend) and ended with `== pre-push gate: all checks passed (scope: docgen frontend) ==` each time. Two runs failed first and were fixed before committing: an unused test parameter (item 3) and an unnecessary import (item 6), both analyzer findings in new test files.

New goldens (`frontend/test/features/courier/goldens/`, 360x800, light, Plex font), `cour_<page>_{ar_rtl,en_ltr}_360x800.png` for: `offer`, `active_pickup`, `active_deliver`, `negotiation`, `complete_sheet`, `cancel_sheet`, `idle`, `jobs`, `blocked`, `account` (20 files). All reviewed by eye; the review found the truncated negotiation buttons, fixed in item 7.

## Behaviour checklist (old screens → new)

EmployeeHomeScreen
- ✓ Jobs refreshed on open; tabs keep the old order and `initialTabIndex`.
- ✓ `job_alert` notification → refresh + the same notice (`newDispatchAlertMessage`, key `job_alert_dispatch_snackbar`), now once per new alert.
- ✓ Notification bell with unread count (header of Task and My jobs).
- ✓ Verification button → KYE banner (when not approved) and the account verification row, both to `KycDocumentUploadScreen`.

EmployeeJobsScreen
- ✓ Online / offline toggle, locked during an active job (moved to My jobs, as in C-History).
- ✓ Location heartbeat (~60 s) and job tracking (10 m distance filter, 3.5 s gate): `EmployeeLocationProvider` untouched; the controller's refresh applies the old `_refreshJobs` rule (tested: track the active job / availability while online / stop while offline).
- ✓ Location-permission banner with "open settings" (My jobs, and on the current job).
- ✓ GPS state: the old header badge (live / off) is now the "customer sees your location" chip on the current job's map (live / starting / off / not updating). Gap: no GPS badge while idle; the availability card says the location is sent every minute.
- ✓ Offer countdown; accept / decline / chat disabled on expiry; in-flight guard; refetch after every answer; race → "no longer available".
- ✓ Price negotiation: propose within 0.5×–1.5× / respond / waiting; 409 / 400 race handling; 429 verbatim without retry.
- ✓ Complete with "cash collected" for COD (now with an optional different amount); error shown with a retry (the sheet stays open).
- ✓ Request cancellation + pending / rejected banners; button hidden while pending.
- ✓ Chat with the customer (offer and current job).
- ✓ Live location indicator and location error banner on the active job.
- ✓ Cancellation reason shown (My jobs row; known server tokens translated).
- ✗ Not ported on purpose: the "Action simulator" card.
- Gap: the per-card details toggle (customer id, payment method, escrow amount chips) is gone; payment shows as "Cash" / the price line, the customer id and escrow amount are not shown.
- Gap: skeleton loaders → a spinner on first load.

EmployeeJobMapScreen
- ✓ Pickup, drop-off and own position on one map, fitted to the known points; denied location degrades to the trip markers (no "you" marker).
- ✓ Recenter. Gap: no +/- zoom buttons (pinch zoom only).
- New: "open in maps" (copies coordinates, no `url_launcher`).

EmployeeHistoryScreen
- ✓ Completed and cancelled jobs, pull to refresh, error with retry, empty state. Now also unavailable and under-review jobs.

Notifications
- Gap: the old NotificationsScreen opened EmployeeJobsScreen from job notifications; the redesigned NotificationsPage gives the courier role no links (customer-only by design), so a tap only marks the notification read. The shell's job_alert refresh still brings the offer up.

## Data gaps
- The pickup endpoint answers with the raw `models.Job` (not `EmployeeJobResponse`): it includes fields the courier DTO hides (e.g. `actual_cash_amount`, unredacted fields). The client only re-parses it with `Job.fromJson` and refetches; worth a backend look.
- No category / service name on `EmployeeJobResponse`: the offer title is the generic "New order", not "Deliver an order" / "Ride".
- The courier never receives the cash amount actually recorded, so "cash today" is the order price of today's completed COD jobs (labelled that way).
- Older jobs have no `status_history`: today's count uses their creation day (the page says so).
- `estimated_duration_minutes` is a snapshot from accept / pickup time, shown as "Estimate: about N min to the pickup / drop-off".

## Unverified
- Device / emulator run with a real backend: **not done** (no device in this session). Pickup against the real endpoint was verified only by the provider unit test with a mocked HTTP server matching the handler's request / response shape (read from `jobs_handlers.go`).
- Real map tiles: goldens use blank tiles (as every map golden in the repo).
- Icons render as boxes in goldens (no icon font loaded in tests, same as the other goldens).
- GitHub CI: not run (agents do not push).

## Rebase note (for the owner)
logic-exploitation moved after this branch was cut (FE-OWNER-2 and FIX-APK-SITE merged). A read-only `git merge-tree --write-tree logic-exploitation HEAD` reports conflicts only in `frontend/lib/l10n/app_en.arb`, `app_ar.arb` and the three generated `app_localizations*.dart` files: both sides appended keys at the end. A script check found no key collisions (164 keys added on their side, 270 here, none shared, no existing key changed by either). Resolution: keep both key sets, then `flutter gen-l10n`. `home_screen.dart` auto-merges.

## Follow-ups / out-of-lane findings
- Add `url_launcher` (hot path: pubspec) so "open in maps" can open a `geo:` / maps URL and the call button can dial; the two call sites are `_openInMaps` and `_RecipientCard._copyPhone` in `features/courier/active_job_page.dart`.
- Pickup endpoint response DTO (see Data gaps).
- Courier notification deep links (NotificationsPage is customer-only).
- `docs/frontend/STATUS.md` rows for `features/courier/**` (owner-only file).

## Open questions
- none
