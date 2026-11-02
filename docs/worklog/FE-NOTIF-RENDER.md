# Worklog: FE-NOTIF-RENDER — notifications from structured data + admin announcements

## Task and scope
- Task ID: FE-NOTIF-RENDER
- Item IDs covered: item 1, item 2, item 3, item 4, item 5
- Allowed paths (lane from the task prompt): frontend/lib/**, frontend/test/**, frontend/docs/**, docs/worklog/FE-NOTIF-RENDER.md
- Agent branch: agent/FE-NOTIF-RENDER-notif-render, created from logic-exploitation (2263a516)

## Decisions taken
- Parsed `params` and `texts` gracefully from Map and JSON string encodings, tolerating missing and malformed structures in old history payloads.
- Added `NotificationLocalizedText` with `title` and `body` mapping to server template localization structure.
- In `NotificationModel.fromPushData`, parsed `deep_link` and retained it under `params['deep_link']`.
- In `notificationCopy`, prioritized `texts[lang]` over local l10n and server title/body; for `admin_announcement`, resolved `params.title_ar/body_ar` vs `title_en/body_en` by locale with fallback to the opposite language, never falling back to raw English sender text when localized text exists.
- Removed body-text regex parsing (`jobIdFromBody`, `ticketIdFromBody`) and English keyword check (`n.body.contains('approved')`). Links now resolve strictly from `n.jobId`, `params['ticket_id']`, and `params['variant']`. When `variant` is missing (push tap), default to My jobs. Deleted body parse helpers.
- Added campaign megaphone icon (`Icons.campaign`) styled with redesign tokens (`c.gold`, `c.onGold`) for `admin_announcement` in `_NotificationTile`. Enforced `maxLines: 2, overflow: TextOverflow.ellipsis` on title and `maxLines: 3, overflow: TextOverflow.ellipsis` on body so long announcements never break tile layouts.
- Added strict `parseAnnouncementDeepLink` parsing `/orders/{id}` and `/jobs/{id}` (user -> job, owner -> order, employee -> jobs), `/tickets[/{id}]` (ticket/tickets for all roles), plan forms (owner only), and verification forms (owner/employee only). Rejects invalid protocols, schemes, whitespace, over-long IDs (> 64 chars), and illegal paths.
- Added `AnnouncementDetailSheet` bottom sheet modal to display full title and body when tapping an announcement without a usable deep link.
- Wired deep link resolution and detail sheet presentation on push tap (`push_tap_handler.dart`).
- Updated `frontend/docs/PUSH.md` with the routing table, "structured data, not body text" rule, and documented known backend limits.

## New files for owner to fold into docs/frontend/STATUS.md
- `frontend/lib/features/account/notifications/announcement_detail_sheet.dart` — Bottom sheet modal displaying full localized title and body for announcements
- `frontend/test/features/account/notification_structured_links_test.dart` — Unit tests for structured link resolution without body text parsing
- `frontend/test/features/account/announcement_deep_link_test.dart` — Deep link parser table tests, announcement icon/tile/sheet widget tests, and push-tap tests

## Changes per commit (message only — NO SHAs)
1. `FE-NOTIF-RENDER: item 1 - keep params and texts on NotificationModel`
2. `FE-NOTIF-RENDER: item 2 - prioritize server texts and localize admin announcements`
3. `FE-NOTIF-RENDER: item 3 - link resolution from structured data without body parsing`
4. `FE-NOTIF-RENDER: item 4 - admin announcement icon, tile rendering, and deep link routing`
5. `FE-NOTIF-RENDER: item 5 - update push documentation and record status files`

## Verification
- `flutter test test/models/notification_model_test.dart` — PASS (6/6 unit tests)
- `flutter test test/features/account/notification_copy_test.dart` — PASS (7/7 unit tests)
- `flutter test test/features/account/notification_structured_links_test.dart` — PASS (9/9 unit tests)
- `flutter test test/features/account/announcement_deep_link_test.dart` — PASS (16/16 table, widget, and push-tap tests)
- `flutter test test/features/account/notifications_test.dart` — PASS (24/24 tests)
- `grep -rn "FromBody\|contains('approved')" frontend/lib` — empty (exit code 1)
- `make check` — PASS

## Unverified (Owner device checks)
- Real device delivery of push notifications (unverified end to end; tested via unit and widget test harnesses).
- Owner manual checks on a physical device:
  1. Admin announcement push with a deep link (e.g. `/orders/{id}`) in AR and EN, verifying tap navigation to the role-specific order view.
  2. Admin announcement push without a deep link in AR and EN, verifying tapping opens the `AnnouncementDetailSheet` with localized title and body.
  3. `cancellation_resolved` push on an Arabic device, verifying it opens My jobs cleanly instead of falling to the Task screen due to English substring matching.

## Follow-ups / out-of-lane findings
- Backend gap (NOTIF-CUSTOMER): Notification history and SSE filter by tenant_id, so customers (empty tenant) may not see job notifications in the in-app list, and announcements may be missing from some users' lists. Push is not affected.
- Backend gap: Push data has no `variant` or `ticket_id`. Adding `params` (or those two keys) to the FCM data would let push taps be exact.

## Open questions
- none
