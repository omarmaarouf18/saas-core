# Worklog: FE-V2-CONSUME — show and send the ADR-0028 fields in the redesigned app

## Task and scope
- Task ID: FE-V2-CONSUME
- Item IDs covered: 0 (owner plan row), 1 (url_launcher + real launches), 2 (booking recipient / package / address text), 3 (customer order timeline / phase / ETA / recipient / call), 4 (owner detail, list, Today), 5 (courier address text + package), 6 (tests + goldens)
- Allowed paths (lane): `frontend/lib/features/{customer,owner,courier,account}/**`, `frontend/lib/ui/**` (additive), `frontend/pubspec.yaml` + `pubspec.lock` (url_launcher only, own commit), android / ios manifest entries for url_launcher, ARB + generated l10n, `frontend/test/**`. Providers additive and tested. Flags unchanged. Nothing under `services/**` or `tests/e2e/**`.
- Agent branch: agent/FE-V2-CONSUME-recipient-eta-timeline, created from logic-exploitation at e56c099a.

## Decisions taken
- **Item 0**: the owner shell calls `fetchDashboardData` (wallet + plan + ledger, one existing call) every time the Account tab opens, and when the shell starts on it. "No switch to free on the free plan" and the verification file name (no image preview) are unchanged.
- **url_launcher 6.3.2**, exact pin (resolves with Flutter 3.44.6 / its Dart; it was already in the local pub cache). Android `<queries>`: `DIAL tel`, `VIEW geo`, `VIEW https`; iOS `LSApplicationQueriesSchemes`: `tel`, `https`. The app never calls `canLaunchUrl`; it calls `launchUrl` and treats `false` or a thrown error as "did not open".
- **Launcher helper** `lib/ui/qd_launch.dart` (additive, exported from `qd_ui.dart`): `QdLauncher` / `UrlQdLauncher` (external app), `QdLauncherScope` (tests inject a fake), `phoneCallUri` (keeps digits and a leading `+`), `mapsUris` (Android `geo:` then Google Maps web; iOS Apple Maps then Google Maps web; others Google Maps web), `openOrCopy` (tries the links in order; when none opens it copies the text and the page shows its notice). No routing / geocoding API.
- **Copy-instead sites replaced**: courier "open in maps" and courier "call recipient" (the two FE-COURIER sites), customer "call courier" (new), owner "call recipient" / "call courier" (new). The auth `update_required_page` copy action is outside the lane and was left as is.
- **Booking layout**: the recipient ("Who receives it?", rides: "Who's riding?") and package sections sit after the payment card, so route, price and payment stay above the fold at 360x800 (A-Book has no recipient section to follow). "I'm the recipient" is the default and sends no `recipient`. The package section shows for delivery and shipping only.
- **Address text** is a new picker field (<= 250, above the landmark note); the search-area picker has neither field. Stops show the address first, the note second.
- **Client validation** (`features/customer/booking_rules.dart`) mirrors `validateV2BookingFields`: runes 250 / 100 / 200 / 200; phone = Egyptian mobile `^(?:\+20|0)?1[0125][0-9]{8}$` or E.164 `^\+[1-9][0-9]{7,14}$`, <= 20 chars; size small / medium / large. The client drops spaces and dashes from the phone before checking and sending (the server only trims). It also checks the landmark note at **500 UTF-8 bytes**, because TrackJob compares `len(AddressNote)` (bytes), so ~250+ Arabic letters are refused even though the picker allows 500 characters.
- **Server 400 mapping**: the body is `{"error": "<code>", "message": ...}`; `ApiClient` keeps a plain-string `error` as the exception message (`errorCode` stays null), so the mapping reads `errorCode ?? message`. `address_too_long` / `address_note_too_long` do not say which stop, so they show under the route; the others show on their field. A banner "Check the highlighted fields" sits next to the button.
- **Timeline** (`features/customer/order/job_timeline.dart`, pure, shared with the owner pages): requested → accepted → picked up → delivered. "Accepted" is the first `active` or `awaiting_price_response` entry after the last dispatch entry (a re-dispatch restarts it); "delivered" is the first `completed` (or reconciliation) entry. Cancelled / unavailable jobs end with that step and drop the steps never reached. A status that says a step was reached without a history entry marks it done with no time. Legacy jobs (no history) return null and keep the created_at-only timeline (customer active view) or no timeline (customer completed / cancelled, owner detail), as before.
- **ETA**: `estimated_duration_minutes` added to the latest history entry of the current phase (`heading_to_pickup` → to the pickup, `picked_up` → to the drop-off), which is when the server computed it. Text: "At the pickup around 3:42 PM" / "Arrives around 3:36 PM" (device 12/24-hour setting); once that time has passed: "Should reach the pickup / arrive any minute"; hidden without minutes, without a known phase, or without the history entry. The courier's own "about N min" line (FE-COURIER) is unchanged.
- **Phase wording** per category (ADR-0028 §2.9.3): delivery / shipping "The courier is on the way to pick up your order" / "On the way to you"; rides "The driver is on the way to pick you up" / "On the way to your destination". Customer: category from the already-loaded marketplace services; owner: from `OwnerProvider.services` when loaded; delivery wording otherwise (no extra request).
- **Owner Today**: a completed order counts on the day of its `completed` history entry; without history, on the day of `created_at` (old rule). The caption says which applied: "orders delivered today", "orders placed today" (none had a delivery time, or no completed order is loaded), or the mixed sentence.
- **Owner list**: the phase chip ("Going to pickup", "Picked up") replaces the "On the way" chip for jobs with a sub_status.
- **Provider**: `MarketplaceProvider.bookJobWithDetails` (new) takes the v2 inputs; `bookJob` keeps its exact signature and delegates, because three existing test doubles (`a5_error_handling_test`, `job_cancellation_test`, `customer_marketplace_screen_test`) override it. Empty / whitespace-only values are not sent, so a booking without v2 input is the old request (tested on the JSON body).
- **ARB**: new keys `lnch*`, `book*`, `tl*`, `phase*`, `eta*`, `ord{Recipient,Passenger,Package,CallCourier}`, `courCallRecipient`, `own{TodayNoteDelivered,TodayNoteMixed,RowDelivered,RowEta,CallRecipient,CallCourier,TimelineTitle}`. No existing key changed. Now unused: `courCoordsCopied`, `courPhoneCopied`, `courCopyPhone` (left in place, same precedent as FE-CUST-2).

## Changes per commit (message only — NO SHAs)
1. `FE-V2-CONSUME: item 0 - owner Account tab loads the plan on open`
2. `FE-V2-CONSUME: item 1a - add url_launcher 6.3.2 (pinned)`
3. `FE-V2-CONSUME: item 1b - real launches with a copy fallback`
4. `FE-V2-CONSUME: item 2 - booking recipient, package and address text`
5. `FE-V2-CONSUME: item 3 - customer order timeline, phase, ETA, recipient`
6. `FE-V2-CONSUME: item 4 - owner order detail, list and Today on job v2`
7. `FE-V2-CONSUME: item 5 - courier address text and package, tested`
8. `FE-V2-CONSUME: item 6 - goldens for the job model v2 states`
9. `FE-V2-CONSUME: worklog` (this file)

## Items
0. **done**.
1. **done**. url_launcher 6.3.2 (own commit with the manifests). Courier goldens did not change (button labels are semantic only).
2. **done**.
3. **done**.
4. **done**.
5. **done**, no code change needed: FE-COURIER already rendered address text → note → "Pinned location" and the package line on the offer and the current job; item 1 made the call button dial. Item 5's commit adds explicit tests for it.
6. **done**. Unit tests: timeline (full, out of order, partial, missing entry, re-dispatch, cancelled before / after acceptance, unavailable, ride price step, legacy none), phase, ETA (absent, current phase, latest entry, EN / AR / past), booking validation and every 400 code, launcher links, provider bodies. Widget tests: booking v2, order page v2, owner detail / list / Today v2, courier places, owner Account plan load. Goldens below.

## Provider / model changes and why
- `providers/marketplace_provider.dart` (additive, `test/providers/marketplace_provider_v2_test.dart`): `bookJobWithDetails(..., pickupAddress, destinationAddress, recipient, packageDetails)`; `bookJob` delegates with its signature unchanged.
- `models/job.dart`: unchanged (FE-COURIER already parses every v2 field).
- Other providers: unchanged. The owner shell only calls the existing `OwnerProvider.fetchDashboardData`.

## Goldens

Changed (only where the new fields render):
- `customer/goldens/cust_book_{ar_rtl,en_ltr}`: the "Who receives it?" header and toggle and the "Package" header now show at the bottom of the page.
- `customer/goldens/cust_picker_{ar_rtl,en_ltr}`: the new address field above the landmark note.
- `owner/goldens/own_account_{ar_rtl,en_ltr}`: the plan row now shows its value ("Free"), loaded when the tab opens (item 0).

New:
- `customer/goldens/cust_book_v2_{ar_rtl,en_ltr}`: booking with "someone else", an invalid phone (field error + banner), notes, package size and notes.
- `customer/order/goldens/ord_v2_active_{ar_rtl,en_ltr}`: phase, ETA, call + chat, history timeline with times.
- `customer/order/goldens/ord_v2_active_details_{ar_rtl,en_ltr}`: route card with address + note, recipient, package.
- `customer/order/goldens/ord_v2_completed_{ar_rtl,en_ltr}`: full timeline with the delivery time.
- `owner/goldens/own_order_v2_{ar_rtl,en_ltr}`: phase chip, recipient / package rows with call, courier call, ETA.
- `owner/goldens/own_order_v2_timeline_{ar_rtl,en_ltr}`: scrolled to the owner timeline.

All were reviewed by eye. The review changed one string (`bookErrPhone` ended in "+.", which flipped in RTL) and localized the fixture's landmark notes.

## Verification

Literal output, local, Flutter 3.44.6, captured on the tree of commit 8 (before this worklog):

```
$ flutter analyze
Analyzing frontend...                                           
No issues found! (ran in 0.9s)
$ flutter test
01:00 +1831: All tests passed!
$ git log --oneline logic-exploitation..HEAD
FE-V2-CONSUME: item 6 - goldens for the job model v2 states
FE-V2-CONSUME: item 5 - courier address text and package, tested
FE-V2-CONSUME: item 4 - owner order detail, list and Today on job v2
FE-V2-CONSUME: item 3 - customer order timeline, phase, ETA, recipient
FE-V2-CONSUME: item 2 - booking recipient, package and address text
FE-V2-CONSUME: item 1b - real launches with a copy fallback
FE-V2-CONSUME: item 1a - add url_launcher 6.3.2 (pinned)
FE-V2-CONSUME: item 0 - owner Account tab loads the plan on open
$ git diff --stat logic-exploitation...HEAD | tail -5
 .../providers/marketplace_provider_v2_test.dart    | 134 +++++++
 frontend/test/ui/qd_launch_test.dart               | 102 ++++++
 .../windows/flutter/generated_plugin_registrant.cc |   3 +
 frontend/windows/flutter/generated_plugins.cmake   |   1 +
 71 files changed, 4673 insertions(+), 137 deletions(-)
$ git diff --name-status logic-exploitation...HEAD -- "*.png"
M	frontend/test/features/customer/goldens/cust_book_ar_rtl_360x800.png
M	frontend/test/features/customer/goldens/cust_book_en_ltr_360x800.png
A	frontend/test/features/customer/goldens/cust_book_v2_ar_rtl_360x800.png
A	frontend/test/features/customer/goldens/cust_book_v2_en_ltr_360x800.png
M	frontend/test/features/customer/goldens/cust_picker_ar_rtl_360x800.png
M	frontend/test/features/customer/goldens/cust_picker_en_ltr_360x800.png
A	frontend/test/features/customer/order/goldens/ord_v2_active_ar_rtl_360x800.png
A	frontend/test/features/customer/order/goldens/ord_v2_active_details_ar_rtl_360x800.png
A	frontend/test/features/customer/order/goldens/ord_v2_active_details_en_ltr_360x800.png
A	frontend/test/features/customer/order/goldens/ord_v2_active_en_ltr_360x800.png
A	frontend/test/features/customer/order/goldens/ord_v2_completed_ar_rtl_360x800.png
A	frontend/test/features/customer/order/goldens/ord_v2_completed_en_ltr_360x800.png
M	frontend/test/features/owner/goldens/own_account_ar_rtl_360x800.png
M	frontend/test/features/owner/goldens/own_account_en_ltr_360x800.png
A	frontend/test/features/owner/goldens/own_order_v2_ar_rtl_360x800.png
A	frontend/test/features/owner/goldens/own_order_v2_en_ltr_360x800.png
A	frontend/test/features/owner/goldens/own_order_v2_timeline_ar_rtl_360x800.png
A	frontend/test/features/owner/goldens/own_order_v2_timeline_en_ltr_360x800.png
```

The `git log` lines are shown with their short SHAs removed (CLAUDE.md: SHAs only in the chat report).

`make check` ran before every commit (scope: docgen frontend) and ended with `== pre-push gate: all checks passed (scope: docgen frontend) ==` each time. Two runs failed first and were fixed before committing: an unnecessary import in a new test (item 1b) and literal U+2066 / U+2069 characters in a new test (item 3, replaced by `⁦` / `⁩` escapes).

## Unverified
- **Run against a backend** with `QD_REDESIGN_CUSTOMER=true` and a booking with a recipient: **not done** (no backend / device run in this session). The request shape is verified only by the provider test against a mocked HTTP server, built from `validateV2BookingFields` / `CreateJobRequest` as read in `services/user-service`.
- **Real launches**: `tel:`, `geo:` and the map URLs were not opened on a device or emulator. In tests the launcher is a fake (`QdLauncherScope`), so the "opened" and "copy fallback" paths are tested, but `UrlQdLauncher`'s call into the plugin (and its catch of a thrown error) is not exercised.
- The Android `<queries>` / iOS `LSApplicationQueriesSchemes` entries were not checked with a device build.
- GitHub CI: not run (agents do not push).

## Out-of-lane / side effects (flagged)
- `flutter pub get` regenerated `frontend/{linux,macos,windows}/flutter/generated_plugin_registrant*` and `generated_plugins.cmake` for url_launcher. These are generated files, outside the listed lane; they are in the item 1a commit so the tree is not left dirty. If the owner prefers, drop them from that commit and let the next desktop build regenerate them.
- No shared widget under `frontend/lib/widgets/` was touched. `features/owner/owner_widgets.dart` `OwnerInfoRow` got two optional parameters (note, trailing); it is an owner feature widget, not a shared one.

## Follow-ups / out-of-lane findings
- `features/auth/update_required_page.dart` still copies the store URL instead of opening it (auth is outside this lane); `openOrCopy` can replace it.
- Backend: TrackJob caps `address_note` by **bytes** (`len()`), while the v2 fields use runes and the picker allows 500 characters. Arabic notes over ~250 letters are refused. Worth aligning on runes in user-service.
- Backend: the 400 body uses a plain-string `error`; `ApiClient` treats that as a message, so `errorCode` is null for these codes. A structured `{"error": {"code": ...}}` (or a `code` field) would make the mapping independent of the message text.
- The customer order page has no category unless the marketplace services are loaded (jobs carry only `service_id`), so ride wording appears only then; same for the owner unless the services list is loaded.
- `docs/frontend/STATUS.md` rows for the new files (`booking_rules.dart`, `order/job_timeline.dart`, `order/job_v2_sections.dart`, `ui/qd_launch.dart`) — owner-only file.

## Open questions
- none
