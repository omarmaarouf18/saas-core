# Worklog: FE-CUST-1 — customer shell and booking path on redesign A

## Task and scope
- Task ID: FE-CUST-1
- Item IDs covered: 0 (FE-DS follow-ups), 1 (job_rules), 2 (CustomerShell), 3 (Home), 4 (Marketplace), 5 (Location picker), 6 (Booking), 7 (My Orders), 8 (tests + goldens)
- Allowed paths (lane): frontend/lib/features/customer/** (new), frontend/lib/ui/** (additive), frontend/lib/core/feature_flags.dart (new), frontend/lib/core/job_rules.dart (new), frontend/lib/screens/home_screen.dart (role 'user' branch only), frontend/lib/main.dart (font license registration only), frontend/lib/providers/marketplace_provider.dart (not touched), l10n ARB + generated files, frontend/test/** (new tests/goldens only), .github/workflows/regen-goldens.yml (item 0 only)
- Agent branch: agent/FE-CUST-1-customer-booking, created from logic-exploitation

## Decisions taken
- **Commit order follows dependencies, not item numbers**, so every commit compiles and passes `make check` on its own: 0, 1, strings, lib/ui components, 5 (picker), 6 (booking), 4 (marketplace), 3 (home), 7 (orders), 2 (shell + flag + home_screen hook), 8 (widget tests + goldens), worklog. The strings and components commits are shared prerequisites of every page. Pure-function unit tests ship with their item (job_rules with 1, price estimate with 6); widget tests and goldens are item 8.
- **Item 0b**: the license registration lives in `lib/ui/qd_licenses.dart` (`registerQdFontLicenses()`, unit-tested); `main.dart` only calls it.
- **Item 0c**: the new chip test is a new file (`test/ui/qd_status_chip_terminal_test.dart`) instead of an edit to the FE-DS test (lane: new tests only).
- **Theme**: the prompt's `QdTheme.light()` is `qdLightTheme` / `qdDarkTheme` in FE-DS. `CustomerTheme` wraps the shell and every page pushed with `customerRoute()` (pushed routes live in the navigator overlay, outside the shell's Theme). It picks dark when the ambient app theme is dark. The Account tab (existing SettingsScreen) and the old screens the new pages hand off to (JobStatusScreen, NotificationsScreen) keep the app theme.
- **Flag**: `customerRootScreen({redesign = kRedesignCustomer})` in `customer_shell.dart`; `home_screen.dart` calls it in the role-user branch. Its import line changed from `customer_home_screen.dart` to the shell file (otherwise an unused import) — the only other line touched in that file.
- **Order detail hand-off**: `CustomerNav` (swappable through `CustomerNavScope` for tests) pushes the existing JobStatusScreen. After a booking it uses `pushAndRemoveUntil(isFirst)` so back returns to the shell, and refreshes `fetchCustomerJobs` in the background. The booking page then stays non-bookable.
- **Loading / error state for jobs**: `MarketplaceProvider` shares one `isLoading` / `error` between services, booking and jobs, so the pages keep their own state (`CustomerJobsController` for Home + Orders, local state on Marketplace / Booking) and read `provider.error` right after each awaited call. No provider change was needed.
- **Sort**: "nearest" sends `sort_by=distance` (the backend sorts only for `price`; any other value keeps the `$nearSphere` distance order) and the client also sorts by `distance_km`; "cheapest" sends `sort_by=price`. Closed companies are listed last in both orders. `near_by=true` always; radius default 50 km (old default); filter sheet offers 5/10/25/50/100 km.
- **Marketplace card price** is the server's `final_price` (tenant base + distance from the search point to the company × price per km), shown as "about X", like the old card. The booking page shows the trip estimate (pickup → drop-off) with the old dialog formula, now `estimateTripPrice()` with unit tests.
- **Payment**: COD only. The booking page never offers another method; the row says "electronic payment is coming soon". `DIGITAL_PAYMENTS` is respected by never sending anything but `cod` (the client has no gateway). The customer app does not fetch `/users/platform/config` (only OwnerProvider does today).
- **Picker**: the old `widgets/location_picker_map.dart` is tap-to-place; A-Picker needs a fixed centre pin, so the picker has its own FlutterMap with the same `mapTileUrlTemplate`, user agent and tile error callback. The tile provider is swappable (`CustomerMapTilesScope`) so tests use blank in-memory tiles. The old widget is untouched.
- **Address text**: `jobPlaceLabel()` uses `JobLocation.addressSummary()` and replaces its coordinate fallback with "Pinned location". A place from the device location reads "Your current location". No coordinates appear in the UI.
- **Order titles**: jobs carry only `service_id`. The title is the service category when that service is already in `MarketplaceProvider.services` (no extra request), else "Order". The Home card adds `#QD-` + 8 id characters, LTR-isolated so it keeps its order inside Arabic.
- **Home ongoing card**: no courier name (not in the API); the second line is "To <drop-off>". Progress has 4 steps: looking for a courier (pending, pending_dispatch, awaiting price) → assigned → on the way → done / under review.
- **My Orders**: jobs that are neither ongoing nor finished (unknown status) are listed under "Past". The mockup's "this week" grouping is not done. The ongoing tab label is "Ongoing · N" (the ARB guard test forbids parentheses).
- **Row layout**: trailing status chips are width-capped (`kChipsMaxWidth` 150), not `Flexible`, so the title keeps the rest of the row; long chips wrap or ellipsize at 360 dp.
- **New ARB keys** are prefixed `cust*`; existing keys are untouched.

## Changes per commit (message only — NO SHAs)
1. `FE-CUST-1: FE-DS follow-ups (golden regen, Plex license, chip rule)` — item 0
2. `FE-CUST-1: add shared job_rules (ongoing / finished)` — item 1
3. `FE-CUST-1: add redesigned customer screen strings (EN + AR)`
4. `FE-CUST-1: add customer kit components to lib/ui`
5. `FE-CUST-1: add full-screen location picker (A-Picker)` — item 5
6. `FE-CUST-1: add booking page (A-Book) with tested price estimate` — item 6
7. `FE-CUST-1: add marketplace page (A-Market)` — item 4
8. `FE-CUST-1: add customer home (A-Home)` — item 3
9. `FE-CUST-1: add My Orders page (A-Orders)` — item 7
10. `FE-CUST-1: add CustomerShell behind QD_REDESIGN_CUSTOMER` — item 2
11. `FE-CUST-1: widget tests and goldens for the customer pages` — item 8
12. `FE-CUST-1: worklog` (this file)

## Items
0. **done** — a) regen-goldens.yml also runs `test/ui/qd_gallery_golden_test.dart` and `test/features/` with `--update-goldens` and uploads `test/ui/goldens/` + `test/features/**/goldens/` as a second artifact; b) Plex OFL registered with LicenseRegistry; c) no "cancellation requested" chip on completed / cancelled jobs (test).
1. **done** — `core/job_rules.dart`: isOngoing / isFinished (+ status variants), newest-first sort, newestOngoingJob; a unit test per status.
2. **done** — CustomerShell with QdBottomNav (Home / My orders / Account); Account = existing SettingsScreen; bell → existing NotificationsScreen (on Home); flag-gated in home_screen.dart.
3. **done** — Home per A-Home with loading / error + retry / no-ongoing states.
4. **done** — Marketplace per A-Market, without ratings (see data gaps).
5. **done** — Picker per A-Picker, without saved-address chips (see data gaps).
6. **done** — Booking per A-Book.
7. **done** — My Orders per A-Orders, without the "this week" grouping.
8. **done for tests and goldens** — widget tests per page with fake providers; 10 goldens; flag test. The device end-to-end booking was **not done** (see Unverified).

## Verification
Literal output, captured on the final code tree (after commit 11, before this worklog), local Flutter 3.44.6 (same as ci.yml):

```
$ flutter analyze
Analyzing frontend...                                           
No issues found! (ran in 0.8s)
$ flutter test
00:37 +1019: All tests passed!
$ flutter test test/features test/ui test/core
00:06 +216: All tests passed!
$ git diff --stat logic-exploitation..HEAD -- frontend/test/goldens
(end)
$ git diff --stat logic-exploitation..HEAD -- frontend/test/ui/goldens
 .../ui/goldens/qd_gallery_booking_ar_rtl_360x800.png    | Bin 0 -> 35022 bytes
 .../ui/goldens/qd_gallery_booking_en_ltr_360x800.png    | Bin 0 -> 37228 bytes
 .../test/ui/goldens/qd_gallery_tiles_ar_rtl_360x800.png | Bin 0 -> 27531 bytes
 .../test/ui/goldens/qd_gallery_tiles_en_ltr_360x800.png | Bin 0 -> 27119 bytes
 4 files changed, 0 insertions(+), 0 deletions(-)
$ git diff --stat logic-exploitation..HEAD | tail -5
 .../ui/goldens/qd_gallery_tiles_en_ltr_360x800.png | Bin 0 -> 27119 bytes
 frontend/test/ui/qd_customer_kit_test.dart         | 234 ++++++++++
 frontend/test/ui/qd_licenses_test.dart             |  18 +
 frontend/test/ui/qd_status_chip_terminal_test.dart |  33 ++
 60 files changed, 6713 insertions(+), 7 deletions(-)
```

`(end)` is a marker echoed after the command: the diff on `frontend/test/goldens` printed nothing, so the existing screen goldens are byte-identical. The `frontend/test/ui/goldens` diff shows only 4 added files (new gallery sections); the 20 FE-DS gallery goldens are unchanged.

`make check` ran before every commit (scope: full, because the branch touches `.github/`). Last lines of the check before commit 11:

```
[timing] total 361.7s
== pre-push gate: all checks passed (scope: full) ==
```

New goldens (`frontend/test/features/customer/goldens/`, 360x800, light): `cust_home_`, `cust_orders_`, `cust_market_`, `cust_book_`, `cust_picker_` × `ar_rtl` / `en_ltr`. New gallery goldens (`frontend/test/ui/goldens/`): `qd_gallery_tiles_*`, `qd_gallery_booking_*`.

Device end-to-end run: **not done**, see Unverified.

## Provider changes
None. `marketplace_provider.dart` is unchanged.

## Components added to lib/ui
QdIconTile, QdIconButton, QdChoiceChips, QdRouteStops, QdPriceBreakdown, QdMapPin, QdMapLabel, QdDockedPanel, QdFooterBar (plus `lib/ui/qd_licenses.dart` for item 0b). Each has widget tests in `test/ui/qd_customer_kit_test.dart` and a gallery entry: two new gallery sections (`tiles`, `booking`) with 4 new gallery goldens. The 20 FE-DS gallery goldens are unchanged.

## Data gaps hit
- **Saved addresses**: `UserProfile.frequentAddresses` are plain strings without coordinates, so the A-Picker "Home / Work" chips are not shown.
- **Ratings**: a company rating needs `GET /users/ratings` per company (the old card made one request per row) and is not part of the services list. Ratings are hidden on the card and the "top rated" sort is dropped.
- **Service name / category on a job**: `/users/jobs/mine` jobs carry only `service_id`. Titles use the category of an already-loaded service, else "Order".
- **Courier name** for "<courier> is on the way" (A-Home): not in the job payload; the card shows the drop-off instead.
- **Text address**: only coordinates + optional landmark note; a place without a note is "Pinned location".
- **City for past orders** ("to <city>" in A-Orders): no city field; the drop-off label is shown.
- **Electronic payment**: none on the client; COD only.
- Already known from FE-DS and not needed by these screens: recipient, ETA, vehicle, package size, per-status timestamps.

## Unverified
- **Device end-to-end booking** (`flutter run --dart-define=QD_REDESIGN_CUSTOMER=true`): not run, no job id to report. No Android emulator or device is attached (`flutter devices` lists only Linux desktop and Chrome), the Linux desktop window cannot be driven from this agent session, and the web target cannot use the app's `dart:io` HTTP client. A local staging stack is up, but booking through it needs a seeded customer login and an open, subscribed service, i.e. writes to the shared staging database, outside this lane. The booking path is covered only by widget tests with a fake MarketplaceProvider (asserted request fields: service id, token, pickup / destination lat/lon + notes, payment_method `cod`).
- **CI rendering of the new goldens**: generated locally with Flutter 3.44.6 (the CI version) on Fedora; not yet seen on ubuntu-latest. If CI shows pixel diffs, dispatch regen-goldens.yml (item 0a) and land its artifact.
- **regen-goldens.yml**: edited by hand, not run on GitHub.
- **Dark mode**: only a smoke test (the shell picks `QdColors.dark` and builds without exceptions); no dark goldens (the task asked for light).
- **Real geolocation and network map tiles**: replaced by fakes in all tests.

## Follow-ups / out-of-lane findings
- FE-CUST-2: replace the JobStatusScreen hand-off (`CustomerNav.openOrder`) with the new order detail. FE-CLEANUP: delete the old customer screens and the flag.
- The Account tab is still the old SettingsScreen (A-Settings not rebuilt).
- Backend: a list-level rating (average + count) on `/users/services` would allow ratings and "top rated"; a `service_name` / `category` on customer jobs would remove the "Order" fallback.
- `docs/frontend/STATUS.md` should list `lib/features/customer/**` and the flag when the owner folds this in (out of lane).

## Open questions
- Should "nearest" keep sending `sort_by=distance` (ignored by the backend, only logged) or `none` like the old screen?
- Marketplace card price: keep the server `final_price` (distance from the search point to the company), as the old card did, or show "from <opening fee>" until a drop-off is known?
