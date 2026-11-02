# Worklog: FE-NOTIF-RENDER — notifications from structured data + admin announcements

## Task and scope
- Task ID: FE-NOTIF-RENDER
- Item IDs covered: item 1
- Allowed paths (lane from the task prompt): frontend/lib/**, frontend/test/**, frontend/docs/**, docs/worklog/FE-NOTIF-RENDER.md
- Agent branch: agent/FE-NOTIF-RENDER-notif-render, created from logic-exploitation (2263a516)

## Decisions taken
- Parsed `params` and `texts` gracefully from Map and JSON string encodings, tolerating missing and malformed structures in old history payloads.
- Added `NotificationLocalizedText` with `title` and `body` mapping to server template localization structure.
- In `NotificationModel.fromPushData`, parsed `deep_link` and retained it under `params['deep_link']`.

## Changes per commit (message only — NO SHAs)
1. `FE-NOTIF-RENDER: item 1 - keep params and texts on NotificationModel`

## Verification
- `flutter test test/models/notification_model_test.dart` — PASS (6/6 unit tests)
- `make check` — PASS

## Unverified
- Real device delivery of push notifications (unverified end to end; tested via unit and widget test harnesses).

## Follow-ups / out-of-lane findings
- Backend gap (NOTIF-CUSTOMER): Notification history and SSE filter by tenant_id, so customers (empty tenant) may not see job notifications in the in-app list, and announcements may be missing from some users' lists. Push is not affected.
- Backend gap: Push data has no `variant` or `ticket_id`. Adding `params` (or those two keys) to the FCM data would let push taps be exact.

## Open questions
- none
