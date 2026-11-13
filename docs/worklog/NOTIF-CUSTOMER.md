# Worklog: NOTIF-CUSTOMER — user-targeted notifications reach their user; FCM params; deep-link

## Task and scope
- Task ID: NOTIF-CUSTOMER (GitHub issues #8, #9, and server part of #33)
- Item IDs covered: 1, 2, 3, 4, 5
- Allowed paths (lane):
  - `services/notification-service/**`, except `go.mod` / `go.sum`
  - `tests/e2e/**`, only the notification/push tests and their fakes
  - `tests/contracts/**`, only where they cover notification-service
  - `frontend/docs/PUSH.md` (the payload documentation only, no app code)
  - `docs/APPLICATION_MAP.md` (only via `make docs`) and `docs/api/**` if they document these payloads
  - `docs/worklog/NOTIF-CUSTOMER.md`
- Agent branch: agent/NOTIF-CUSTOMER-user-targeted-notifications, created from logic-exploitation at a9e8e53b

## Sender Table (Item 1 Pre-coding Audit)

| Sender | Notification Type | tenant_id Source | user_id / user_ids | roles | Relies on tenant_id to restrict user-targeted delivery? |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `auth-service` (`auth.go:2214`) | `kyc_approved`, `kyc_rejected` | `targetUser.TenantID` | `user_id = targetUser.ID` | none (empty) | No |
| `auth-service` (`auth.go:2762`) | `account_suspended`, `account_reactivated` | `targetUser.TenantID` | `user_id = targetUser.ID` | none (empty) | No |
| `chat-service` (`admin_tickets.go:183`) | `ticket_resolved` | none (`global: true`) | `user_id = ticket.CustomerID` | none (empty) | No |
| `chat-service` (`admin_tickets.go:349`) | `ticket_assigned` | none (`global: true`) | `user_id = ticket.CustomerID` | none (empty) | No |
| `user-service` (`admin_services_handlers.go:43`) | `service_approved`, `service_rejected` | `svc.TenantID` | `user_id = svc.TenantID` (owner) | `["owner"]` | No |
| `user-service` (`jobs_handlers.go:2797`) | `job_offer` | `job.OwnerID` | `user_id = employeeID` | `["employee"]` | No |
| `user-service` (`jobs_handlers.go:2858`) | `job_accepted` | `job.OwnerID` | `user_id = job.UserID` (customer) | `["client", "user"]` | No (previously dropped customer delivery) |
| `user-service` (`jobs_handlers.go:2912`) | `job_unavailable` | `job.OwnerID` | `user_id = job.UserID` (customer) | `["client", "user"]` | No (previously dropped customer delivery) |
| `user-service` (`jobs_handlers.go:2965`) | `job_cancelled` (escrow lock failed) | `job.OwnerID` | `user_id = job.UserID` (customer) | `["client", "user"]` | No (previously dropped customer delivery) |
| `user-service` (`jobs_handlers.go:3153`) | `job_alert` (broadcast) | `job.OwnerID` | `employee_id = job.EmployeeID` (payload field, stored as empty `user_id` on persistence) | `["owner", "employee", "client"]` | N/A (role broadcast) |
| `user-service` (`jobs_handlers.go:3626` / `notifyJobEvent`) | `job_booked` | `job.OwnerID` | `user_id = job.OwnerID` (owner) | `["owner"]` | No |
| `user-service` (`jobs_handlers.go:3626` / `notifyJobEvent`) | `job_picked_up` | `job.OwnerID` | `user_id = job.UserID` (customer) | `["client", "user"]` | No (previously dropped customer delivery) |
| `user-service` (`jobs_handlers.go:3626` / `notifyJobEvent`) | `job_delivered` | `job.OwnerID` | `user_id = job.UserID` (customer) or `job.OwnerID` (owner) or `job.EmployeeID` (courier) | `["client", "user"]` or `["owner"]` or `["employee"]` | No (previously dropped customer delivery) |
| `user-service` (`jobs_handlers.go:3626` / `notifyJobEvent`) | `job_cancelled` | `job.OwnerID` | `user_id = job.UserID` (customer) or `job.OwnerID` or `job.EmployeeID` | `["client", "user"]` or `["owner"]` or `["employee"]` | No (previously dropped customer delivery) |
| `user-service` (`jobs_handlers.go:3586`) | `job_cancelled` (cancellation party) | `job.OwnerID` | `user_id = userID` | `[role]` | No |
| `user-service` (`reconciliation_handlers.go:587`) | `dispute_resolved` | `job.OwnerID` | `user_id = target.userID` (customer, owner, courier) | none (empty) | No (previously dropped customer delivery) |
| `notification-service` (`admin_notification_handlers.go:391`) | `admin_announcement` | none (`""`) | `user_id = uid` | none (empty) | No (previously dropped by tenant gate) |

**Conclusion**: No sender relies on `tenant_id` to restrict a user-targeted notification. In every case with an explicit recipient (`user_id` or `user_ids`), the notification belongs directly to that user.

## Decisions taken
- Defined a single shared predicate `hub.MatchesClient(n Notification, client *SSEClient) bool` (or client fields) used for live SSE delivery.
- Defined a single shared Mongo filter builder in `store.UserNotificationFilter(tenantID, userID string, roles []string) bson.M` used across `ListForUser`, `MarkRead`, `MarkAllRead`, `Delete`, and `DeleteAll`.
- Added compound indexes in `store.EnsureIndexes`: `(user_id: 1, timestamp: -1)` and `(user_ids: 1, timestamp: -1)` to cover queries without tenant prefix.
- Stored notifications require no data migration: old stored notifications become visible immediately to their recipient upon deployment because the query filter now scopes on recipient rather than requiring matching tenant.
- FCM data params allow-list: `variant`, `ticket_id`, `deep_link`. Derived by grepping `frontend/lib` (read-only):
  - `variant`: read in `notification_rules.dart:278` for cancellation routing (`accept` -> My jobs, `decline` -> current task).
  - `ticket_id`: read in `notification_rules.dart:242` for support ticket navigation.
  - `deep_link`: read in `notification_rules.dart:155` and `notification_tap_router.dart:23` for announcement routing.
  - Excluded free-text keys: `title_ar`, `title_en`, `body_ar`, `body_en`, `note`, `reason`, `agent_name`, etc.
- Detail sheet bilingual text analysis:
  On a push tap, `NotificationModel.fromPushData` only receives `title` and `body` in the recipient device's language (rendered by the server at push dispatch). Because `data['params']` strictly omits `title_*`/`body_*` to enforce the 4096-byte FCM limit, `notificationCopy` falls back to `(n.title, n.body)` in that language. It does not get the alternate language's text unless fetched from history by ID. This is recorded as a follow-up for the frontend (see below).
- Validated deep links reject id segments that are `.` or `..` or contain `..`.

## Changes per commit (message only — NO SHAs)
1. `notif: recipient-first scoping for live delivery and history`
2. `notif: add filtered params to FCM data payload`

## Verification
- `services/notification-service` unit & integration tests:
  - `go test -v -run TestSSEHub_RecipientFirstScoping ./services/notification-service/internal/hub` — PASS
  - `go test -v -count=1 -run TestMongoDB_RecipientFirstScoping_Issue8 ./services/notification-service/internal/store` — PASS
  - `go test -v -count=1 ./services/notification-service/internal/handlers -run TestHistory` — PASS
  - `go test -v -run TestBuildPushDataMap_AllowListAndSizeLimit ./services/notification-service/internal/hub` — PASS (worst-case payload: 288 bytes, well under 4096-byte limit)
  - All unit & integration tests in `services/notification-service` pass cleanly against local Mongo & Redis.
- `make check` — PASS (scope: full).

## Unverified
- Releases / remote CI (agents do not push).

## Follow-ups / out-of-lane findings
- `govulncheck` in `scripts/govulncheck-module.sh` failed on third-party vulnerability `GO-2026-6865` (CVE-2026-116591, panic in `github.com/klauspost/compress` on two-block frames) against `github.com/klauspost/compress v1.18.7`, pulled indirectly by `go.mongodb.org/mongo-driver/v2 v2.8.0`.
- The user granted lane permission to bump `github.com/klauspost/compress` to `v1.20.2` in `services/notification-service/go.mod` and `go.sum`, resolving the vulnerability cleanly.
- The same failure exists on clean `logic-exploitation` (`a9e8e53b`) across other services using mongo-driver (`user-service`, `chat-service`, etc.), which should be updated on the base branch by the owner.
- Frontend follow-up (Item 2): When tapping a push for an announcement that opens the `AnnouncementDetailSheet`, the app receives only the active device locale's text. To view the alternate language, the app should be updated to fetch the full bilingual notification model from `/notifications` history by ID when presenting the sheet.

## Open questions
- none (resolved: lane permission granted to bump klauspost/compress in services/notification-service).



