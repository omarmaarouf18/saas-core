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
- Agent branch: agent/NOTIF-CUSTOMER-user-targeted-notifications, rebased onto logic-exploitation at ac8a79a3 (originally created from a9e8e53b)

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
- History role scoping: history now applies the notification's roles to user-targeted notifications too (before, ListForUser ignored roles when user_id matched). This aligns history with live SSE delivery, and the pre-coding sender table shows every user-targeted sender sets roles that match the recipient, so nothing becomes hidden.
- Delete semantics: `isExclusiveRecipient` no longer excludes notifications that carry roles, so a user-targeted notification with roles is now hard-deleted on Delete instead of soft-dismissed.
- Added compound indexes in `store.EnsureIndexes`: `(user_id: 1, timestamp: -1)` and `(user_ids: 1, timestamp: -1)` to cover queries without tenant prefix.
- Stored notifications require no data migration: old stored notifications become visible immediately to their recipient upon deployment because the query filter now scopes on recipient rather than requiring matching tenant.
- FCM data params allow-list: `variant`, `ticket_id`, `deep_link`. Derived by grepping `frontend/lib` (read-only):
  - `variant`: read in `notification_rules.dart:278` for cancellation routing (`accept` -> My jobs, `decline` -> current task).
  - `ticket_id`: read in `notification_rules.dart:242` for support ticket navigation.
  - `deep_link`: read in `notification_rules.dart:155` and `notification_tap_router.dart:23` for announcement routing.
  - Excluded free-text keys: `title_ar`, `title_en`, `body_ar`, `body_en`, `note`, `reason`, `agent_name`, etc.
- Detail sheet bilingual text analysis:
  On a push tap, `NotificationModel.fromPushData` only receives `title` and `body` in the recipient device's language (rendered by the server at push dispatch). Because `data['params']` strictly omits `title_*`/`body_*` to enforce the 4096-byte FCM limit, `notificationCopy` falls back to `(n.title, n.body)` in that language. It does not get the alternate language's text unless fetched from history by ID. This is recorded as a follow-up for the frontend (see below).
- Validated deep links reject id segments that are `.` or `..` or contain `..` (issue #33).

## Changes per commit (message only — NO SHAs)
1. `notif: recipient-first scoping for live delivery and history`
2. `notif: add filtered params to FCM data payload`
3. `notif: reject dot segments in admin announcement deep-link ids`
4. `tests: update e2e push assertions for params`
5. `docs: document FCM data params and complete NOTIF-CUSTOMER worklog`
6. `docs: record rebase onto logic-exploitation at ac8a79a3`
7. `docs: record role scoping and delete semantics, clarify DEPS-COMPRESS bump`

## Verification
- `services/notification-service` unit & integration tests:
  - `go test -v -run TestSSEHub_RecipientFirstScoping ./services/notification-service/internal/hub` — PASS
  - `go test -v -count=1 -run TestMongoDB_RecipientFirstScoping_Issue8 ./services/notification-service/internal/store` — PASS
  - `go test -v -count=1 ./services/notification-service/internal/handlers -run TestHistory` — PASS
  - `go test -v -run TestBuildPushDataMap_AllowListAndSizeLimit ./services/notification-service/internal/hub` — PASS (worst-case payload: 288 bytes, well under 4096-byte limit)
  - `go test -v -run TestValidateDeepLink_RejectDotSegments ./services/notification-service/internal/handlers` — PASS (42/42 valid/invalid route test cases)
  - All unit & integration tests in `services/notification-service` pass cleanly against local Mongo & Redis.
- Contract tests (`cd tests/contracts && go test -v -count=1 ./...`):
  - PASS (all 10 tests passed in 0.044s)
- E2E tests (`tests/e2e`):
  - `STAGING_REDIS_URI="redis://:devpassword123@localhost:6380/0" STAGING_MONGO_URI="mongodb://root:devpassword123@localhost:27017/?authSource=admin" go test -v -run "TestPushBE_NotificationServiceDeliversViaFCMOAuth|TestPushL10N_DeviceLanguagePerToken" ./tests/e2e`
    - `--- PASS: TestPushBE_NotificationServiceDeliversViaFCMOAuth (1.40s)`
    - `--- PASS: TestPushL10N_DeviceLanguagePerToken (3.57s)`
  - Full staging suite tests (`contract_notif_test.go`, `admin_api_test.go`): require the full staging compose stack (`api-gateway` on 8088, `auth-service`, `console` on 8091), which is not active locally; the standalone push e2e tests were executed directly against local Mongo & Redis.
- `make docs`:
  - `go run tools/docgen/main.go`: No changes to APPLICATION_MAP.md.
- `make check` — PASS (scope: full).

## Unverified
- Releases / remote CI (agents do not push).
- Full staging compose suite (local stack down; standalone push tests verified against local DBs).

## Follow-ups / out-of-lane findings
- `govulncheck` in `scripts/govulncheck-module.sh` previously failed on third-party vulnerability `GO-2026-6865` against `github.com/klauspost/compress v1.18.7`. This vulnerability was fixed across the repository via `DEPS-COMPRESS` (merged at `ec32f249`), and the Go toolchain was upgraded to 1.26.11 via `GO-1-26-11` (merged at `ac8a79a3`). Following rebase onto `logic-exploitation` (`ac8a79a3`), all services and tool caches are on Go 1.26.11 with 0 vulnerabilities.
- Frontend follow-up (Item 2): When tapping a push for an announcement that opens the `AnnouncementDetailSheet`, the app receives only the active device locale's text. To view the alternate language, the app should be updated to fetch the full bilingual notification model from `/notifications` history by ID when presenting the sheet.
- Out-of-lane note (Item 3): `kyc-reviewer-console` maintains its own deep-link allow-list in a separate repository (out of lane). Client-side deep-link validation on the Flutter mobile app side is deferred to a future frontend task.

## Deploy note
- **VM / Infrastructure**: No VM or infrastructure changes required.
- **Database / Data Migration**: Zero data migration required. Old stored notifications in MongoDB become immediately accessible to their recipient upon deployment because the query filter now scopes on recipient rather than requiring matching tenant. Compound indexes `(user_id, timestamp desc)` and `(user_ids, timestamp desc)` are ensured automatically on service startup by `EnsureIndexes`.
- **Backward Compatibility**: Fully backward compatible. Senders and clients do not require coordinated deployment.

## Open questions
- none. (Clarification: no hot-path grant was given in this lane; the `github.com/klauspost/compress` bump was executed across the repo by separate task `DEPS-COMPRESS`, merged into `logic-exploitation` at `ec32f249`).





