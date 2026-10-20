# Worklog: FE-CUST-2 — customer order detail and everything after booking

## Task and scope
- Task ID: FE-CUST-2
- Item IDs covered: 0 (FE-CUST-1 follow-ups), 1 (OrderDetailPage + orderViewFor), 2 (searching / unavailable), 3 (price proposal), 4 (active + map), 5 (completed + rating), 6 (chat page), 7 (tests + goldens)
- Allowed paths (lane): frontend/lib/features/customer/** (new files + the FE-CUST-1 call sites that opened JobStatusScreen), frontend/lib/ui/** (additive), ARB + generated l10n, frontend/test/**. Providers: additive only. Old screens untouched. Everything behind QD_REDESIGN_CUSTOMER.
- Agent branch: agent/FE-CUST-2-order-detail, created from logic-exploitation

## Decisions taken
- **Commit order follows dependencies, not item numbers**, so every commit compiles and passes `make check` on its own: 0, 1, 6 (chat, needed by the searching and active views), 2, 3, 4, 5, 7, worklog. Item 1 shipped the page, `orderViewFor`, the controller, the call-site switch and the final cancelled / under-review / unknown views; until items 2–5 landed, the other kinds showed a route + price summary (removed in the item 5 commit). Widget tests for each view shipped with its view; item 7 added the page-level tests and all goldens.
- **Call sites**: the three FE-CUST-1 call sites (home ongoing card, booking submit, orders tap) all go through `CustomerNav.openOrder`, so that one method now opens `OrderDetailPage.open(context, job, replaceStack:)` instead of JobStatusScreen. `customer_nav.dart` no longer imports the old screen. After a booking `replaceStack` still drops the marketplace and booking pages (tested).
- **One route, one job id**: `OrderDetailPage(jobId, initialJob)`. The caller's copy shows at once; the first fetch runs right after. "Order again" on the unavailable view books a new job and the same page follows the new id (the old screen did the same).
- **An 8th view kind, `unknown`**: the prompt lists 7 views; a status this client does not know (`picked_up`, typos, future values) renders a summary with no actions instead of being forced into one of them. `assigned` (client-only alias) maps to `active`.
- **Expiry**: `orderViewFor(job, now)` returns `cancelled` for an `awaiting_price_response` job whose `price_proposal_expires_at` is not after `now`; `isProposalExpired` also matches the server reason `price_proposal_expired`, and both read "the price offer ran out of time" (the raw reason is not shown). The countdown's `onExpired` rebuilds the page at once and refetches.
- **Countdown window**: the API has no proposal start time. The bar is sized on the server's 5-minute window (`exp := now.Add(5 * time.Minute)` in user-service `jobs_handlers.go`), constant `kPriceProposalWindow`.
- **Polling** stops on `isFinished` (core/job_rules.dart), so it now also stops on `unavailable` (the old screen kept polling it until completed / cancelled). Unknown statuses keep polling. A tick is skipped while a fetch is in flight; a generation counter keeps an older fetch from overwriting an action's response.
- **Courier name**: `GET /auth/user/public-profile` as before, through `CourierLookup` (swappable with `CourierLookupScope`). It is also used for the courier currently looking at the offer during `pending_dispatch` (that endpoint lets any signed-in user read a username), so the A-Searching card says "Karim is looking at your order"; a failure falls back to generic copy.
- **Company name** on the searching text and the courier card comes from the already-loaded marketplace services (jobs carry only `service_id`); nothing is shown when it is not loaded. No extra request.
- **Notices**: the old `ThemedSnackBar` is replaced by a plain SnackBar (`showOrderNotice`) under the redesign theme, with the same retry actions.
- **Cancel**: still only for `pending` / `pending_dispatch`. The reason sheet cannot be dismissed by an outside tap or drag (the old dialog was `barrierDismissible: false`); a failure keeps it open with the error. The refund wording rule is unchanged (non-COD and not `pending_dispatch`).
- **Price label**: "Cash · estimated" before acceptance, "You'll pay cash" while ongoing, "Paid cash" when completed, plain "Price" on cancelled / unknown. Price = agreed, else suggested; "Not set yet" when neither exists (old: "matching courier").
- **Active layout**: the app bar stays (title "Your order") above the map, instead of the mockup's back button floating on the map, so every view has the same back affordance.
- **Rating**: five stars stay preselected (old behaviour; the mockup shows 4 as an example). After a rating the completed view shows a thank-you line; the API has no "did I rate this job" read, so this is per page session (`OrderController.rated`), and a second try is answered "already rated", which counts as success (as before).
- **Item 0 sort**: "nearest" sends `sort_by=none` and the client sorts by `distance_km`; "cheapest" still sends `sort_by=price` and sorts by `final_price` on the client (unchanged, see open questions).
- **Item 0 card price**: "From <opening fee> + <price per km>/km" with `baseFareOf()` (tenant base, else service base) and `tenant_price_per_km`, under the label "Price". `custEstimatedPrice` / `custAboutAmount` stay in the ARB (`custAboutAmount` is still used by the booking page; `custEstimatedPrice` is now unused, left in place because existing keys are not removed).
- **Item 0 orders font**: `QdText.rowTitleSm` (15) / `QdText.bodyStrong` (14) with `w700`, the same sizes and weight as the hard-coded values, so the orders goldens did not change.
- **New ARB keys** are prefixed `ord*`, `chat*`, `rate*` (plus `custFromPrice`); no existing key was changed. `rateStar` is an ICU plural.
- **Formatting side effect**: running `dart format` on `test/features/customer` reformatted 2 lines of the FE-CUST-1 file `test/features/customer/home_page_test.dart` (no content change), committed with item 1.

## Changes per commit (message only — NO SHAs)
1. `FE-CUST-2: FE-CUST-1 follow-ups (nearest sort, card tariff, orders font tokens)` — item 0
2. `FE-CUST-2: order detail page with orderViewFor and polling` — item 1
3. `FE-CUST-2: chat page (one component for job and later ticket chat)` — item 6
4. `FE-CUST-2: searching and unavailable views (A-Searching)` — item 2
5. `FE-CUST-2: price proposal view (A-Negotiate)` — item 3
6. `FE-CUST-2: active order view with live map (A-Track)` — item 4
7. `FE-CUST-2: completed view and rating page (A-Rate)` — item 5
8. `FE-CUST-2: order detail page tests and goldens` — item 7
9. `FE-CUST-2: worklog` (this file)

## Items
0. **done** — nearest = `sort_by=none` + client distance sort; card tariff instead of `final_price`; orders price style on QdText tokens. Market goldens regenerated (only those two).
1. **done** — `features/customer/order/`: `OrderDetailPage`, `OrderController` (5 s polling via `fetchJobStatus` while not finished, stops on finished and dispose, pull to refresh, stale-data banner), pure `orderViewFor(job, now)` with unit tests; call sites switched.
2. **done** — searching (rings, offered-courier card with early chat, route + price, cancel sheet) and unavailable ("Order again" with the same service / locations / notes / payment method).
3. **done** — courier proposal (comparison, difference, countdown, accept / decline), own proposal (waiting), counter-offer (0.5×–1.5×); 409 / 400 / 429 notice + retry + refetch; expiry → cancelled view.
4. **done** — map on top (`MapTrackingProvider` hydrate + `job:<id>` websocket, waiting / reconnecting / denied notices, zoom, recenter), courier card with chat, knowable timeline, route + price, complaint via `CreateTicketDialog`.
5. **done** — completed view (paid amount, rate button until rated) and `CustomerRatingPage` (stars, private comment, blind note, already-rated = success, not now).
6. **done** — `features/customer/chat/chat_page.dart`, one component per channel (`job:<id>` today).
7. **done** — unit tests, widget tests per view with fake providers and a fake clock (testWidgets' fake async + an injected `now`), 24 goldens. Device run **not done** (see Unverified).

## Verification

Literal output, captured on the final code tree (after commit 8, before this worklog), local Flutter 3.44.6 (same as ci.yml):

```
$ flutter analyze
Analyzing frontend...                                           
No issues found! (ran in 2.8s)
$ flutter test
00:48 +1158: All tests passed!
$ flutter test test/features test/ui test/core
00:14 +355: All tests passed!
$ git diff --stat logic-exploitation..HEAD -- frontend/test/goldens
(end)
$ git diff --stat logic-exploitation..HEAD -- frontend/test/ui/goldens frontend/test/features/customer/goldens
 .../customer/goldens/cust_market_ar_rtl_360x800.png | Bin 41013 -> 40226 bytes
 .../customer/goldens/cust_market_en_ltr_360x800.png | Bin 43984 -> 42843 bytes
 2 files changed, 0 insertions(+), 0 deletions(-)
$ git diff --stat logic-exploitation..HEAD | tail -5
 .../features/customer/order/order_page_test.dart   | 301 +++++++++
 .../features/customer/order/order_view_test.dart   | 171 ++++++
 .../customer/order/proposal_view_test.dart         | 237 +++++++
 .../customer/order/searching_views_test.dart       | 181 ++++++
 64 files changed, 7017 insertions(+), 33 deletions(-)
```

`(end)` is a marker echoed after the command: the diff on `frontend/test/goldens` printed nothing, so the existing screen goldens are byte-identical. Among the FE-DS / FE-CUST-1 goldens only the two market goldens changed (item 0, as asked).

`git log --oneline logic-exploitation..HEAD` before this worklog commit, with the short SHAs removed per CLAUDE.md (they are in the chat report):

```
FE-CUST-2: order detail page tests and goldens
FE-CUST-2: completed view and rating page (A-Rate)
FE-CUST-2: active order view with live map (A-Track)
FE-CUST-2: price proposal view (A-Negotiate)
FE-CUST-2: searching and unavailable views (A-Searching)
FE-CUST-2: chat page (one component for job and later ticket chat)
FE-CUST-2: order detail page with orderViewFor and polling
FE-CUST-2: FE-CUST-1 follow-ups (nearest sort, card tariff, orders font tokens)
```

`make check` ran before every commit (scope: docgen frontend). Last lines before commit 8:

```
01:22 +1158: All tests passed!
== pre-push gate: all checks passed (scope: docgen frontend) ==
```

During item 2 one `make check` failed: the not-yet-committed golden test still had cancelled goldens rendered before the price-label change. They were regenerated and the check re-ran green before committing. That golden file was kept out of commits 4–7 and committed in commit 8.

New goldens (`frontend/test/features/customer/order/goldens/`, 360x800, light, Plex font) — `ord_<view>_{ar_rtl,en_ltr}_360x800.png` for: `searching`, `unavailable`, `proposal`, `proposal_counter`, `active`, `completed`, `cancelled`, `cancelled_expired`, `unknown`, `under_review`, `rating`, `chat` (24 files). All were reviewed by eye.

Device end-to-end run: **not done**, see Unverified.

## Behaviour checklist (old screens → new)

JobStatusScreen
- ✓ Polls `fetchJobStatus` every 5 s; stops when finished. Now `isFinished` (also stops on `unavailable`, see decisions) and on dispose.
- ✓ Countdown ticks while awaiting a price (QdCountdown, 250 ms).
- ✓ Courier username via `/auth/user/public-profile`, generic fallback on failure; re-resolved when the courier changes.
- ✓ Manual refresh → pull to refresh (every view).
- ✓ Refresh error banner with retry, last data kept.
- ✓ Live tracking: the map is inline in the active view instead of a separate screen. It no longer opens before a courier accepts: it would only show the pickup.
- ✓ Negotiation: comparison of suggested vs proposed with the signed difference. The percentage is dropped (A-Negotiate shows the amount only).
- ✓ Expired negotiation (server reason or past expiry) → explained cancelled view.
- ✓ "Waiting for response" when the customer made the proposal.
- ✓ Accept / decline with loading, 409 → "the order changed", other errors → friendly message (400, 429), retry action, refetch; success notices.
- ✓ Counter-offer only when nobody proposed: number check, 0.5×–1.5× bounds with the same epsilon, clears on success, notice, 409 handling, retry, refetch.
- ✓ Progress stepper → searching rings + active timeline. The "pending pulse" during dispatch is replaced by the rings illustration.
- ✓ Unavailable: retry booking with the same service, pickup / destination (destination falls back to pickup), payment method and both notes; success notice; error notice; double-tap guard; courier name reset (new job id).
- ✓ Itinerary with the drop-off note; the pickup note is shown too now.
- ✓ Fare: payment method (cash wording, or "Price" for non-COD), agreed price else suggested, "not set yet" when none. The proposed price is in the proposal view. Locked escrow is shown in the under-review view only, not in other states (old: in the fare details of any state).
- ✓ Assigned courier card with chat; offered courier card with early chat while dispatching.
- ✓ Cancellation reason shown on cancelled jobs.
- ✓ Rate button when completed; after rating a "rated" line instead.
- ✓ Cancel for pending / pending_dispatch only, required reason, refund wording rule, refetch.
- ✓ Complaint for active jobs → CreateTicketDialog with the job id, not dismissible by outside tap.
- ✓ Back → app bar back.
- ✓ `#QD-` reference + status chips (incl. "cancellation requested") on the cancelled, under-review, unknown, unavailable, active and completed views. Not on searching / proposal, which follow their mockups.

CustomerJobMapScreen
- ✓ `hydrateCustomerJob` + `connectAndSubscribe('job:<id>')`; `disconnect` registered through ProviderConnectionCleanup.
- ✓ Re-hydrate → pull to refresh in the active view.
- ✓ Loader while loading with no markers.
- ✓ Pickup, drop-off and courier markers. The courier marker no longer prints a truncated employee id.
- ✓ "Waiting for courier" notice until a position arrives.
- ✓ Reconnecting notice while the socket is down; refused channel → access notice (localized; the provider's English `ErrorMessages.forbidden` text is not shown).
- ✓ Zoom in / out and recenter.
- ✓ Bottom sheet (id, in-transit line, back to status) → the active view itself.

RatingScreen (customer path)
- ✓ Rated party: assigned courier, else owner.
- ✓ Other side already rated? (ratings received for this job by that party) with its own error + retry. The old app-bar re-check is only offered as retry after a failure.
- ✓ Five stars preselected, per-star semantics (now a radio group).
- ✓ Comment trimmed.
- ✓ Identity error when no party can be determined.
- ✓ Success → back to the order with a thank-you; the post-submit re-check of the other side is dropped because the page closes right away (as before, it closed right after too).
- ✓ "already rated" / "conflict" in the error → success.
- ✓ Other failures → notice with retry.
- ✓ The three explanatory info cards are replaced by the one blind-rating note of A-Rate.
- ✓ New: "not now" / close return without rating.

ChatScreen
- ✓ Socket torn down when the page closes (ProviderConnectionCleanup).
- ✓ History first; websocket only when history was not refused.
- ✓ Send: trims, ignores empty, in-flight guard against double taps, clears after success, scrolls to the end, failure notice with retry.
- ✓ Live / connecting / offline / denied indicator.
- ✓ Job context (ref) in the app bar subtitle.
- ✓ Error banner with retry when not refused.
- ✓ Access denied: banner with retry, composer hidden.
- ✓ Loader while history loads (no empty-state flash); empty state otherwise.
- ✓ Bubbles mine / theirs; sender: "You" (now localized), username, or "User <6 chars>".
- ✓ Scrolls to the end when the message count changes (old: after every build).

## Provider changes
None. `marketplace_provider.dart`, `map_tracking_provider.dart` and `chat_provider.dart` are unchanged. The test harness gained fakes (`FakeMarketplace` order methods, `FakeChat` with history / connect / send / disconnect, `FakeMapTracking`).

## Components added to lib/ui
- `QdRings` (`lib/ui/components/qd_rings.dart`, exported from `qd_ui.dart`): the A-Searching concentric gold discs. Covered by the order goldens; no gallery entry yet (see follow-ups).

## Data gaps hit
- **ETA, vehicle, recipient, picked-up step**: not in the API; not shown (JOB-MODEL-V2).
- **Per-status times**: only `created_at` ("You ordered", time "Today · 2:05 PM"); accepted / on-the-way have no time ("Now" marks the current step); the completed view and the rating page show no delivery date/time (A-Rate shows one).
- **Courier contact**: chat only.
- **Company name on a job**: only when the service is already loaded in `MarketplaceProvider.services`.
- **Proposal window length**: not in the payload; 5 minutes taken from the server code.
- **Has the customer rated this job?**: no read endpoint; the rated state lasts for the page session.
- Seams: each section is its own widget (`OrderRouteCard`, `OrderPriceRow`, `OrderCourierCard`, `OrderTimeline`, `OrderStateHeader`, `OrderDeliveredHeader`), so v2 fields slot in without touching the views.

## Unverified
- **Device end-to-end COD run** (`flutter run --dart-define=QD_REDESIGN_CUSTOMER=true`, booking → completed): not run, no job id to report. `flutter devices` lists only Linux desktop and Chrome; no Android device or emulator is attached, and the run needs a courier on the other side to accept and complete. Covered only by widget tests with fake providers. The owner will run it.
- **Real websocket / map tiles / public-profile**: replaced by fakes in all tests.
- **CI rendering of the new goldens**: generated locally (Fedora, Flutter 3.44.6, the CI version), not yet seen on ubuntu-latest. If CI shows pixel diffs, dispatch regen-goldens.yml (it already covers `test/features/`).
- **Dark mode**: not checked (no dark goldens; the task asked for light).
- **Server behaviour assumed from code reading**: the public-profile lookup for the offered (not yet assigned) courier; the 5-minute proposal window.

## Follow-ups / out-of-lane findings
- FE-CLEANUP: delete JobStatusScreen, CustomerJobMapScreen, RatingScreen, ChatScreen (customer path) and the flag once the redesign ships. The employee / owner paths still use the old RatingScreen and ChatScreen.
- Ticket chat: reuse `CustomerChatPage` with the ticket channel (and attachments, which the job chat does not need).
- Add `QdRings` to the debug gallery (and its gallery goldens).
- JOB-MODEL-V2: delivery time for the completed header, per-status times for the timeline, ETA / vehicle on the courier card.
- Backend: a "my rating for this job" read would let the completed view hide the rate button across sessions.
- `docs/frontend/STATUS.md` should list `lib/features/customer/order/**` and `lib/features/customer/chat/**` (out of lane, owner).

## Open questions
- Cheapest sort still orders by the server `final_price` (search point → company distance), the same figure the card no longer shows. Sort by `baseFareOf` + `tenant_price_per_km` on the client instead, or keep the server order?
- Map before acceptance: the old screen let the customer open the map while searching (pickup only). The new page shows the map only once a courier is on it. OK?
