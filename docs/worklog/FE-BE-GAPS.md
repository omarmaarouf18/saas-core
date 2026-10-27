# Worklog: FE-BE-GAPS — consume the USER-AUTH-BE backend in the redesigned app

## Task and scope
- Task ID: FE-BE-GAPS
- Item IDs covered: 1–10 (item 9 delivered inside items 1–8, see below)
- Allowed paths (lane from the task prompt): frontend/lib/**, frontend/test/**, ARB + generated l10n, frontend/pubspec.* (not touched), android/ios manifests (not touched), docs/frontend/**, docs/design/redesign-a/00-SCREEN-MAP.html (status column), docs/worklog/FE-BE-GAPS.md. No services/**, infrastructure/deploy/** or docs/runbooks/** change (parallel PROD-PHOTO-STORAGE).
- Agent branch: agent/FE-BE-GAPS-consume-user-auth-be, created from logic-exploitation (c3fe2c5d)

## Items status
- 1 service photo — done. Owner: camera / library (scaled to 1600 px, JPEG quality 85), client check (JPEG / PNG magic bytes, ≤ 5 MB), multipart upload (`photo` field) to `POST /users/services/{id}/photo`, or `POST /users/services/photo` before the service exists (key sent as `photo_url` on create); progress, retry, errors (503 or 500 "storage not initialized" → "Photo upload is unavailable right now", KYB 403, plan 402, 400 refused, network); change; remove (`PUT photo_url: ""`). Display: `ServicePhotoTile` on the service setup page, the marketplace card and the booking page (the service detail). Read: `GET /users/services/{id}/photo` with the JWT (the API returns a storage key, no signed URL), cached in memory per service + key; placeholder initial when absent / failed / a device path. `photo_url` is only ever a key the server returned.
- 2 service create — done. One `POST /users/services` with every field (address, coverage radius, photo key, structured schedule); the old create-then-PUT and its "partly saved" error are gone. Test: create → GET round trip against a mock user-service.
- 3 saved addresses — done. Account page: list / add / edit / delete with undo, max 10, label Home / Work / custom, address, note, pin from the map picker; PATCH `saved_addresses` (whole list). Booking picker: "Saved places" first, one tap fills pin + address + note; old string-only `frequent_addresses` fill the text only and ask for a pin.
- 4 customer name / KYE — done. `customer_name` on orders list, order detail, Today request rows (fallback: today's text); orders search matches it. `kye_status` chip on team rows and the member page (Verified / Under review / Not accepted / Not uploaded, the account verification wording); the team chip opens the member page with its verification sheet.
- 5 notification links — done in code and tests; push taps not verified on a device (Firebase not initialized, see Unverified).
- 6 error codes — done (booking field + banner codes, pickup codes; unknown code → server text).
- 7 rune limits — done (booking note was counted in bytes; counters on all server-limited text fields). Only exception: the password stays in UTF-8 bytes on purpose (bcrypt, 72 bytes).
- 8 2FA resend — done. The login challenge page already called `/auth/resend-otp`; now covered by a test through the login page; 429 localized, no retry, countdown restarted with the server's wait.
- 9 tests + goldens — done inside each item's commit (no separate commit: every item carries its unit, widget and golden tests). Unit: saved-address validation (`saved_addresses_test.dart` rules group), notification routing per role / type (`notification_job_links_test.dart`), error-code mapping (`error_codes_test.dart`), rune counters (`test/core/text_limits_test.dart`), photo pre-checks (`service_photo_test.dart`).
- 10 docs — done: STATUS.md rows + index, screen-map status column, manual test plan below.

## Decisions taken
- Photo store is an InheritedWidget (`ServicePhotoScope`) above the navigator in `main.dart`; pages without it (tests, previews) show the placeholder.
- A photo for a not-yet-created service is uploaded right away without an id; the returned key goes into the create request (item 2). For an existing service the upload itself stores it, so the page's save never sends `photo_url`.
- The server reuses the key `services/<id>/photo.<ext>` on replace: the cache is cleared for that service on upload / remove. Other phones keep the old image until the app restarts (no ETag / version in the key) — see Follow-ups.
- Saved-address labels "Home" / "Work" are stored in English and shown in the app language (the Arabic words are recognized too); other labels as typed. The app requires a label (the server allows an empty one).
- The server rebuilds `frequent_addresses` from `saved_addresses` on every write, so a write drops old unpinned string addresses. The page asks before such a write ("Older addresses will be removed"); pinning the last old one asks nothing.
- "tap → member verification": owners cannot open a courier's documents (`/auth/kyb-kye/user-documents` is reviewer-only), so the KYE chip opens the member page with a sheet that states the status and what it means (the courier uploads from Verification in the courier app). Open question below.
- Notification links: `job_id` + a job event type → a `job` target with the old by-type target as fallback; each shell resolves the job (customer: `GET /users/jobs/get`; owner: owner jobs list, one reload; courier: refreshed jobs list → offer / current = Task tab, finished = My jobs, since My jobs has no per-job page). Not found / not yours → "We couldn't open that order…" and the role's order list.
- Push: a new `NotificationTapRouter` (Firebase `getInitialMessage`, `onMessageOpenedApp`, `onMessage`) holds taps; `PushTapHandler` inside each shell follows them with the same links; a foreground push shows a SnackBar with "View".
- Booking field errors keep the 400-only rule (field codes always come with 400); non-field codes get a localized banner.
- `QdTextField` gains an optional `maxRunes` (shared component, additive; called out in the item 3 commit).
- STATUS.md was edited on this branch: the task's lane and item 10 grant it, and the docgen drift gate requires every new `lib/providers` / `lib/models` file to be named there (item 1 failed the gate without it).

## Backend contract vs USER-AUTH-BE worklog (mismatches; services/** not changed)
1. Notification payloads have no `event_type` key: the stable type is `type` (SSE, history and FCM data carry `type` and `job_id`). The app uses `type`.
2. `job_booked`, `job_in_transit`, `job_delivered` (and `job_completed`) are not sent by any service; user-service sends `job_offer`, `job_accepted`, `job_unavailable`, `job_cancelled`, `job_picked_up`, `cancellation_requested`, `cancellation_resolved`, `cancellation_request_expired`, `dispute_resolved`; notification-service sends `job_alert` with `job_id`. The app routes all of them anyway.
3. Item 10 codes `address_required`, `recipient_name_required`, `recipient_phone_required`, `package_details_required` are not returned by TrackJob (`validateV2BookingFields` treats every v2 field as optional). `job_state_changed` is not a pickup code: a lost pickup race answers `{"error": "job state changed during pickup", "code": "conflict"}`; `job_state_changed` appears as the `error` value of other handlers (offer accept / decline, etc.). TrackJob also returns `address_note_too_long` and `package_size_invalid`, and pickup `job_id_required`, `unauthorized`, `role_mismatch`, `job_not_active`, which the worklog does not list. All are mapped.
4. The photo upload never answers 503 for storage: storage not set up is `500 {"error": "storage not initialized"}` (503 only when the auth service is down for the KYC check). Both show "unavailable right now".
5. There is no photo delete endpoint; removal is `PUT /users/services` with `photo_url: ""` (UpdateService stores it).
6. The worklog says the saved-address label must be non-empty; the handler only caps it at 100 runes.
7. `kye_status` is `omitempty` in `EmployeeResponse`; an empty value is left out (the app shows it as "Not uploaded").

## Changes per commit (message only — NO SHAs)
1. `FE-BE-GAPS: item 1 - service photo upload, authenticated display and cache`
2. `FE-BE-GAPS: item 2 - service create sends every field in one POST`
3. `FE-BE-GAPS: item 3 - saved addresses with map pins, saved places in the booking picker`
4. `FE-BE-GAPS: item 4 - customer name for owners, courier KYE chips`
5. `FE-BE-GAPS: item 5 - notifications open the exact job (list and push taps)`
6. `FE-BE-GAPS: item 6 - booking and pickup errors by stable code`
7. `FE-BE-GAPS: item 7 - text limits in characters (runes) with counters`
8. `FE-BE-GAPS: item 8 - 2FA sign-in resend: login challenge, cooldown, lockout text`
9. `FE-BE-GAPS: item 10 - docs: STATUS rows and index, screen-map status column`
10. `FE-BE-GAPS: worklog` (this file)

## Packages
- None added. `image_picker` (already in pubspec, used by verification) picks and scales the service photo.

## Verification (literal lines)
- Baseline on the branch start: `No issues found! (ran in 2.5s)`; `00:37 +1221: All tests passed!`
- item 1, `make check`: `00:34 +1245: All tests passed!`; `== pre-push gate: all checks passed (scope: docs infra-tests docgen frontend) ==` (the analyze line of this run was not captured; the first run of the gate for item 1 failed in shared/infra/docgen with `Dart file "service_photo_store.dart" ... is not mentioned anywhere in docs/frontend/STATUS.md!`, fixed in the same commit)
- item 2, `make check`: `== pre-push gate: all checks passed (scope: docs infra-tests docgen frontend) ==` (analyze and test summary lines not captured for this run)
- item 3, `make check`: `No issues found! (ran in 0.9s)`; `00:45 +1271: All tests passed!`; gate passed
- item 4, `make check`: `No issues found! (ran in 1.3s)`; `00:45 +1287: All tests passed!`; gate passed
- item 5, `make check`: `No issues found! (ran in 0.7s)`; `00:34 +1300: All tests passed!`; gate passed
- item 6, `make check`: `No issues found! (ran in 0.7s)`; `00:31 +1308: All tests passed!`; gate passed
- item 7, `make check`: `No issues found! (ran in 0.8s)`; `00:33 +1315: All tests passed!`; gate passed
- item 8, `make check`: `No issues found! (ran in 0.9s)`; `00:35 +1319: All tests passed!`; gate passed
- item 10, `make check`: `No issues found! (ran in 0.7s)`; `00:32 +1319: All tests passed!`; `== pre-push gate: all checks passed (scope: docs infra-tests docgen frontend) ==`

## Goldens
New (light EN-LTR + AR-RTL, one dark EN-LTR per new screen / state):
- owner: `own_service_photo_{en_ltr,ar_rtl,dark_en_ltr}` (service with a photo), `own_order_customer_*` (order detail with customer name), `own_orders_customer_*` (orders list with customer name), `own_team_kye_*` (team with KYE chips)
- customer: `cust_market_photo_*` (card with photo and one placeholder), `cust_picker_saved_*` (picker with saved places)
- account: `acct_addresses_pinned_*` (saved addresses), `acct_address_editor_*` (editor), `acct_address_editor_errors_{en_ltr,ar_rtl}` (editor validation)

Changed, with the reason:
- `own_service_{en_ltr,ar_rtl}`, `own_service_errors_{en_ltr,ar_rtl}`: the photo row (placeholder + "Add photo") replaces the "photo upload is coming" note.
- `own_team_*`: KYE chip under each courier's state chip.
- `own_employee_*`, `own_employee_frozen_*`: the ID check row is always shown (chip).
- `own_add_courier_*`, `own_freeze_sheet_*`: the team / member page behind the sheet changed as above.
- `own_orders_*`: search hint "Order number, customer or courier".
- `acct_addresses_*`: fixture has pinned addresses and one old string address.
- `acct_account_*`, `acct_suspended_*`: saved-address count includes the old string address.
- `cust_picker_*`: character counters under the address and note fields.
- `cust_book_v2_*`: character counters under recipient name, recipient notes and package notes.

## MANUAL TEST PLAN — 2.0.0, whole app
Prepare: one customer, one business owner (KYB approved, paid plan for service edits and photos), two couriers under that owner (one with documents approved, one without documents), a second customer for "not yours" checks. Run every role once in English and once in Arabic (Account > Language), and once with dark mode (Account > Appearance). Note the build number from Account > About.

### Auth
1. Sign up as a customer: weak password shows the policy text; a valid form sends a code; enter it → customer home.
2. Sign up as a business owner: same flow → owner Today with the KYB banner.
3. Sign in with a wrong password → banner; 5+ wrong tries → lockout text with the wait.
4. Sign in to an account with 2-step verification: the code page shows the email; wait 60 s → "Send it again" → a new code arrives (email or test-mode banner), "We sent you a new code"; the countdown restarts. Ask again several times quickly until the server locks: the banner says "Too many codes sent. You can ask for a new one in N seconds" (Arabic in AR), no Retry, the countdown shows the wait.
5. Enter a wrong code → error with Retry; the right code → home.
6. Forgot password: email → code → new password → sign in with it.
7. Account > Security: turn 2-step verification off (confirm + password) and on again.
8. Sign out from each role → sign-in page; relaunch → still signed out. Sign in, kill the app, relaunch → splash, then the role's home.
9. A staff account (admin / reviewer) → unsupported-role page with sign out.
10. Server minimum version above the build → update page; "Download the update" opens the browser.

### Customer
1. Home: choose a service type → marketplace near the device location (or pick an area when location is off).
2. Marketplace: companies with photo (the owner's uploaded photo) or the initial when none; open / closed chip; sort nearest / cheapest; filters (radius, area).
3. Booking (tap an open company): the company photo at the top; pickup = current place; choose the drop-off on the map. In the picker: "Saved places" chips first — tap Home → the pin moves, address and note are filled → Confirm. Tap an old address without pin → only the text is filled and "No map pin yet" shows; move the map → the warning goes.
4. Counters: type a long Arabic note with diacritics in the landmark note — the counter shows characters and stops at 500; recipient name 100, notes 200, package notes 200.
5. Someone else receives it: wrong phone (0123) → the error on the phone field; a valid Egyptian mobile works.
6. Order now → order page (searching → courier assigned → picked up → on the way → completed); price proposal accept / decline; cancel with a reason; chat with the courier; rating after completion.
7. Error cases: book while the company is closed (button off); book twice fast (one order); turn the network off and book → connection message.
8. My orders: ongoing / past lists, open an order.
9. Account > Saved addresses: add Home with a pin, Work with a pin, Other with a custom name; edit one (pin starts where it was); delete + Undo; reach 10 → add is off; an account with old string addresses shows "Not on the map yet", "Pin it" opens the editor with the text; saving another address asks before removing the other old ones.
10. Account > My details (name, phone), email change with a code, Support: new complaint, ticket chat, resolved ticket read-only.
11. Notifications: an accepted / picked-up / cancelled order notification opens that exact order page; a notification for another customer's job (or a deleted job) shows "We couldn't open that order…" and My orders; ticket notifications open the ticket.

### Owner
1. Today: summary tiles, "Needs you" (cancellation requests show "For <customer name>"), team now, links.
2. Service setup: add a photo (camera and library); see "Uploading… N%"; the photo shows; change it; remove it; a >5 MB / non-image file is refused before upload; with the server's storage off the message is "Photo upload is unavailable right now". New service (fresh owner): fill every field incl. hours and a photo, Save once → reopen the page: address, radius, hours, photo are all there (no "partly saved").
3. Customers then see the photo on the marketplace card and the booking page.
4. Orders: each row shows "<customer name> · #QD-…" (old orders: "#QD-… · courier"); search by customer name; order detail shows the customer name in the Customer row (old orders: "Customer #…"); respond to a cancellation request; cancel an order.
5. Team: each courier row has the ID check chip (Verified / Under review / Not accepted / Not uploaded); tap the chip → the courier page with the verification sheet; add a courier; freeze / unfreeze with the password.
6. Fleet map, activity log, wallet (read only), plan (read only), payment review.
7. Verification (KYB): upload the four documents, see "Under review"; a rejection while signed in shows the dialog → "Fix my documents".
8. Notifications: cancellation request / expired / dispute → that order's detail; a job not in the owner's list → notice and Orders.

### Courier
1. Task tab: go online; an offer arrives (job_alert notice); accept / decline before the countdown ends.
2. Current job: map, call / chat, "Picked up" → if it was already confirmed, "This order is already marked as picked up."; if the job changed, "This job changed. We refreshed it."; no longer the assigned courier → "This order is no longer assigned to you."; deleted → "This job no longer exists".
3. Deliver: cash collected (amount), job moves to My jobs; cancellation request to the owner.
4. My jobs: today tiles and finished list.
5. Verification (KYE): upload three documents; the owner's team chip changes to Under review, then Verified after review.
6. Notifications: an offer → Task tab; a cancellation resolved → Task (still mine) or My jobs (cancelled); a job that is no longer theirs → notice and My jobs.
7. Suspended / paused account → blocked page.

### Notifications (all roles)
1. In-app list: grouped by day, unread dots, tap marks read, mark all read, clear all, pull to refresh, load more, live stream reconnect.
2. Push (only once Firebase is configured in the build — not today): with the app closed, tap a push → the app opens on that job after sign-in restores (cold start); app in background → tap → same; app open → a SnackBar with the title and "View" → that job. Unknown type or no job id → the app just opens (as today).

### Dark mode and languages
- Every page above once in dark mode: text readable, photos and chips visible, map tiles unaffected.
- Arabic: right-to-left layout, counters "n / max" readable, saved-address labels Home / Work shown as البيت / الشغل, error texts in Arabic (booking, pickup, resend lockout, photo).

## Unverified
- No device or emulator run: everything is verified by unit, widget and golden tests.
- No run against local staging: a staging stack was up, but it was started by someone else shortly before, built from an unknown branch (the parallel PROD-PHOTO-STORAGE task works on photo storage), and the gateway did not answer on `https://localhost:8080` (curl exit 7). No photo upload or saved-address booking was sent to it.
- Push taps on a device: the app never calls `Firebase.initializeApp()` and has no `google-services.json`, so `FirebasePushTapSource` is a no-op; the routing is covered with a fake source only.
- New goldens not yet rendered on CI.

## Follow-ups / out-of-lane findings
- Firebase is not initialized in `main.dart` and no Firebase config is in the Android / iOS projects; FCM registration and push taps cannot work until that is done (out of this lane: platform config).
- Service photo key is reused on replace (`services/<id>/photo.<ext>`); other clients keep the old image in memory until restart. A version in the key or an ETag (`Cache-Control: private, max-age=86400` is set today) would fix it (backend).
- No `event_type` key and no `job_booked` / `job_in_transit` / `job_delivered` notifications (backend; see mismatches 1–2).
- Owners have no way to see a courier's documents; if the product wants owners to review them, an owner-scoped read endpoint is needed (backend + decision).

## Open questions
- Item 4 "tap → member verification": is the member page's verification sheet (status + explanation, no documents) what you meant, or should owners see the courier's documents (needs a backend endpoint)?
