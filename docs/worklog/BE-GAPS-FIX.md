# Worklog: BE-GAPS-FIX — close the gaps FE-BE-GAPS found between the USER-AUTH-BE worklog and the code

## Task and scope
- Task ID: BE-GAPS-FIX
- Item IDs covered: 1, 2 (partly, by owner decision), 3, 4, 5, 6, 7
- Allowed paths (lane from the task prompt): this worktree, everything except `frontend/**` (read only). No AI_CONTEXT / changelog / STATUS edits. Hot path `shared/infra/storage` granted by the owner during the task (item 4); no other hot path touched.
- Agent branch: agent/BE-GAPS-FIX-events-codes-photo-delete, created from logic-exploitation (a5b36670)

## Decisions taken
- **Item 1**: one sender (`notifyJobEvent`) behind the existing `notifyCancellationParty`. New events: `job_booked` to the owner (both TrackJob create paths, any initial status, including `unavailable`), `job_delivered` to the customer (COD and escrow completion), `job_cancelled` to the customer when someone other than the customer cancels (owner, approved courier request, system). A customer cancelling their own job gets nothing (no new spam). `job_accepted`, `job_picked_up`, `job_offer`, `job_unavailable` recipients unchanged. Reconciliation completion still sends only `dispute_resolved` (no extra `job_delivered`).
- **Item 1, `job_in_transit`**: not emitted. There is no distinct step: `sub_status: picked_up` is the on-the-way state (ADR-0028 §2.4), so `job_picked_up` covers it.
- **Item 1, `event_type`**: derived in notification-service (`hub.JobEventType`), = `type` for every notification with a `job_id`, absent otherwise; on SSE frames, history items and FCM data. Not stored, so history written before this task carries it too. user-service does not send it (one source). The app routes on `type`, unchanged.
- **Item 1, `job_picked_up` pool bug** (found by the new e2e test): pickup was sent with roles `["user"]`, but notification-service puts customer connections in the `client` pool, so the event never reached a customer. Now `["client","user"]` like every other customer event (separate commit).
- **Item 1, owner overlap**: on a booking pre-assigned to a courier, the owner's history may show both the existing `job_alert` (stored as a tenant role broadcast) and the new `job_booked`. Left as is (job_booked was asked for; job_alert is unchanged).
- **Item 2, owner decision "leave them out"**: the `*_required` codes (`address_required`, `recipient_name_required`, `recipient_phone_required`, `package_details_required`) are NOT added. ADR-0028 makes these fields optional and the app also treats them as optional (`booking_rules.dart` validates only lengths/format; `marketplace_provider.dart` omits empty fields), so enforcing them would reject bookings that work today. The app maps them anyway, harmless.
- **Item 2, lost race**: `409 {"error","message": "job state changed during pickup", "code": "job_state_changed"}`. HTTP status kept. `conflict` dropped for this case: the app maps `job_not_active`, `job_state_changed` and `conflict` to the same notice (`courier_rules.dart` `pickupErrorText`), so it does not rely on `conflict`. Real store failures keep the generic `conflict`.
- **Item 3**: no PROD-PHOTO-STORAGE fail-closed code exists on any branch (its branch has no commits of its own, clean worktree), so this task defines the one code: `503 {"error": "photo storage unavailable", "code": "photo_storage_unavailable", "request_id"}` for storage never initialized (upload and read) and for a failed write. PROD-PHOTO-STORAGE should reuse it.
- **Item 4**: the app removes with `PUT /users/services` `photo_url: ""`, so that is supported exactly; no DELETE endpoint added. The old object is deleted after the field update, also on replace (`PUT` with another key, or an upload under a different key such as `photo.jpg` → `photo.png`). Only keys under `services/<service id>/` or `services/<owner id>/` are deleted, and only through the existing tenant check, so pointing `photo_url` at another tenant's key cannot delete it. Best effort: a failed delete is logged and the request still succeeds.
- **Item 4, hot path**: storage had no delete. Owner granted `shared/infra/storage`: new optional `storage.Deleter` interface + `LocalStorage.Delete` (missing key = nil; traversal, a sibling dir sharing the base's name prefix, and the base itself are refused). `Storage` is unchanged, so other implementations stay valid.
- **Item 5**: label required (non-empty after trim, 400 `label is required for saved address`), max 100 runes (already there; ADR-0028 §2.8 and the app use 100). Plain `error` body like the sibling saved-address errors.
- **Item 6**: the generated endpoint descriptions live in `shared/infra/docgen` (not granted), so contract notes went into a hand-written section of `docs/APPLICATION_MAP.md` under the generated table; corrections in ADR-0028 Implementation Notes (not in USER-AUTH-BE's worklog).
- **Staging**: the running stack was built from the USER-AUTH-BE worktree on 2026-10-26 and nothing was using it (no e2e / compose process); rebuilt from this worktree with `scripts/staging_up.sh` (env = the example, same as that stack's), then user-service rebuilt once more after the pickup pool fix.

## Corrections: worklog claim → actual before → after
| USER-AUTH-BE claim | Before (logic-exploitation a5b36670) | After |
| :--- | :--- | :--- |
| Lifecycle notifications `job_booked`, `job_accepted`, `job_picked_up`, `job_in_transit`, `job_delivered`, `job_cancelled` with `job_id` | `job_booked`, `job_delivered` never sent; `job_cancelled` only on escrow lock failure; `job_picked_up` sent to the `user` pool, never delivered to customers | all sent (recipients above); `job_picked_up` reaches customers; `job_in_transit` does not exist (= picked_up) |
| `event_type` in payload and SSE | no `event_type` anywhere | `event_type` = `type` on SSE, history, FCM for job notifications |
| booking codes `address_required`, `recipient_name_required`, `recipient_phone_required`, `package_details_required` | never returned (fields optional) | still not returned, by owner decision (ADR-0028: optional) |
| pickup code `job_state_changed` | lost race answered `code: conflict` | `code: job_state_changed`, 409 |
| photo storage unavailable | `500 "storage not initialized"`; failed write `500 internal_error` | `503 photo_storage_unavailable` for both |
| photo removal | `PUT photo_url ""` cleared the field, object kept; replace with another ext kept the old object | object deleted on removal and replace (tenant-scoped) |
| saved address label non-empty | only capped at 100 runes; empty stored as `""` | required after trim, max 100 runes |

## Changes per commit (message only — NO SHAs)
1. `BE-GAPS-FIX: item 1 - job lifecycle notifications with stable event types`
2. `BE-GAPS-FIX: item 2 - pickup lost race returns job_state_changed`
3. `BE-GAPS-FIX: item 3 - photo storage unavailable is 503 photo_storage_unavailable`
4. `BE-GAPS-FIX: item 5 - saved address label required, max 100 runes`
5. `BE-GAPS-FIX: item 4 - removing or replacing a service photo deletes the stored object`
6. `BE-GAPS-FIX: item 6 - docs: contract notes and ADR-0028 corrections`
7. `BE-GAPS-FIX: item 1 - deliver job_picked_up to the customer client pool`
8. `BE-GAPS-FIX: item 7 - e2e test for items 1-5`
9. `BE-GAPS-FIX: worklog` (this file)

## Tests added and which failed before
Each was run against the code before its change (source file stashed, test kept); literal failure lines:
- **Item 1** `notification-service/internal/hub/job_event_type_test.go` `TestSSEHub_JobNotificationCarriesEventType`:
  `job_event_type_test.go:46: job notification SSE frame lacks event_type/job_id: event: notification` and `job_event_type_test.go:76: FCM data for job notification = map[id:n-job job_id:job-42 tenant_id:tenant-A type:job_picked_up]`
- **Item 1** `notification-service/internal/handlers/job_event_type_history_test.go` `TestNotificationHistory_JobItemsCarryEventType`: `job_event_type_history_test.go:84: job item = map[body:Job job-evt-1 was delivered. ... type:job_delivered user_id:cust-evt], want event_type job_delivered and job_id` (line shortened here; full line in the session)
- **Item 1** `user-service/internal/handlers/job_lifecycle_notifications_test.go` `TestJobLifecycleNotifications_StableEventsWithJobID` (constants replaced by literals to compile on the old code): `job_lifecycle_notifications_test.go:157: job_booked: expected exactly 1 notification, got 0: []`. After the pool fix the test asserts the `client` pool; on the previous code: `job_lifecycle_notifications_test.go:170: job_picked_up: roles [user] lack "client"`
- **Item 2** `user-service/internal/handlers/job_pickup_race_code_test.go` `TestPickupJob_LostRaceReturnsJobStateChanged`: `job_pickup_race_code_test.go:57: unexpected body for lost pickup race: {"error":"job state changed during pickup","code":"conflict","request_id":"99be62c5bd88f10d"}`
- **Item 3** `user-service/internal/handlers/service_photo_storage_unavailable_test.go` `TestServicePhoto_StorageUnavailable_503StableCode`: `service_photo_storage_unavailable_test.go:53: upload with failing write: expected 503, got 500: {"error":"failed to store photo","code":"internal_error","request_id":"61c4fd3674472a43"}`
- **Item 4** `user-service/internal/handlers/service_photo_delete_test.go` `TestServicePhoto_RemoveAndReplaceDeleteStoredObject`: `service_photo_delete_test.go:88: stored object "services/svc-photo-del/photo.jpg" still exists after removal` (plus lines 95, 109, 112). `shared/infra/storage/storage_delete_test.go` `TestLocalStorage_Delete`: `storage/storage_delete_test.go:31:8: undefined: Deleter` (build failure).
- **Item 5** `auth-service/internal/handlers/saved_address_label_test.go` `TestSavedAddresses_LabelRequiredAndMax100Runes`: `saved_address_label_test.go:41: label "": expected 400 label is required, got 200: {"message":"profile updated successfully",...` (shortened) and `saved_address_label_test.go:46: rejected writes must not store anything, got [{ID:addr_1793088334569481346_0 Label: Address:15 شارع النيل AddressNote: Latitude:30 Longitude:31}]`
- **Item 7** `tests/e2e/be_gaps_fix_test.go` `TestE2E_BEGapsFix`: first run against staging built from this branch before the pool fix: `be_gaps_fix_test.go:122: no job_picked_up SSE event for job c2937664dd832aa8: timeout waiting for SSE event`. Not run against pre-task staging.

## Verification
- `go test -count=1 ./...` per changed module (under `scripts/ci-lock.sh`, final code):
```text
== services/auth-service
ok  	github.com/project/auth-service/cmd	0.003s
ok  	github.com/project/auth-service/cmd/approve-kyc	1.005s
?   	github.com/project/auth-service/cmd/encrypt-documents	[no test files]
ok  	github.com/project/auth-service/cmd/onboard-reviewer	0.989s
ok  	github.com/project/auth-service/internal/config	0.002s
ok  	github.com/project/auth-service/internal/handlers	56.800s
ok  	github.com/project/auth-service/internal/models	0.001s
ok  	github.com/project/auth-service/internal/otp	0.003s
ok  	github.com/project/auth-service/internal/otpcrypto	0.001s
ok  	github.com/project/auth-service/internal/storage	0.002s
ok  	github.com/project/auth-service/internal/store	7.119s
== services/notification-service
?   	github.com/project/notification-service/cmd	[no test files]
ok  	github.com/project/notification-service/internal/config	0.001s
ok  	github.com/project/notification-service/internal/fcm	0.004s
ok  	github.com/project/notification-service/internal/handlers	0.808s
ok  	github.com/project/notification-service/internal/hub	0.523s
ok  	github.com/project/notification-service/internal/store	2.179s
== services/user-service
?   	github.com/project/user-service/cmd	[no test files]
ok  	github.com/project/user-service/internal/config	0.002s
ok  	github.com/project/user-service/internal/handlers	225.584s
ok  	github.com/project/user-service/internal/models	0.023s
ok  	github.com/project/user-service/internal/store	28.359s
== shared/infra
ok  	github.com/project/shared/infra	0.661s
ok  	github.com/project/shared/infra/docgen	0.035s
ok  	github.com/project/shared/infra/handlerutil	0.056s
ok  	github.com/project/shared/infra/jwtutil	1.699s
ok  	github.com/project/shared/infra/passwordpolicy	0.002s
ok  	github.com/project/shared/infra/ratelimit	14.617s
ok  	github.com/project/shared/infra/redact	0.002s
ok  	github.com/project/shared/infra/resilience	1.384s
ok  	github.com/project/shared/infra/storage	0.002s
ok  	github.com/project/shared/infra/testutil	0.002s
ok  	github.com/project/shared/infra/tlsutil	0.041s
```
- `make check` last lines (run before the item 7 commit; full scope because `shared/infra` changed):
```text
00:34 +1319: All tests passed!
[timing] flutter-analyze-test 39.3s
[timing] total 396.3s
== pre-push gate: all checks passed (scope: full) ==
```
- New e2e file against local staging built from this worktree (after the pool fix; staging was not busy, see Decisions):
```text
=== RUN   TestE2E_BEGapsFix
=== RUN   TestE2E_BEGapsFix/JobLifecycleNotifications
=== RUN   TestE2E_BEGapsFix/PickupLostRace_JobStateChanged
=== RUN   TestE2E_BEGapsFix/ServicePhoto_RemoveAndReplaceDeleteObject
=== RUN   TestE2E_BEGapsFix/SavedAddressLabel_RequiredMax100
--- PASS: TestE2E_BEGapsFix (1.61s)
    --- PASS: TestE2E_BEGapsFix/JobLifecycleNotifications (1.58s)
    --- PASS: TestE2E_BEGapsFix/PickupLostRace_JobStateChanged (0.00s)
    --- PASS: TestE2E_BEGapsFix/ServicePhoto_RemoveAndReplaceDeleteObject (0.01s)
    --- PASS: TestE2E_BEGapsFix/SavedAddressLabel_RequiredMax100 (0.01s)
PASS
ok  	github.com/project/tests/e2e	1.613s
```
- Whole e2e suite against the same staging (regression check): `ok  	github.com/project/tests/e2e	10.261s`

## Unverified
- Item 3 on staging: the 503 is covered by unit tests only; staging storage cannot be made to fail from a test.
- FCM `event_type`: covered by a fake dispatcher only; Firebase is not configured in the app (see FE-BE-GAPS).
- No device / app run: the app's routing on these events was read, not exercised.
- The e2e test was not run against the pre-task code (only its pickup failure on this branch before the pool fix is recorded).

## Follow-ups / out-of-lane findings
- `frontend/lib/features/account/notifications/notification_rules.dart` still says `job_booked`, `job_in_transit`, `job_delivered`, `job_completed` are not emitted; `job_booked` and `job_delivered` now are, `job_in_transit` / `job_completed` never will be (frontend, out of lane).
- PROD-PHOTO-STORAGE: reuse `photo_storage_unavailable` for its fail-closed path (e.g. instead of the temp-dir fallback in `NewUserService`).
- `PUT /users/services` accepts any `photo_url` string (another tenant's key can be set and is then served); deletion is prefix-guarded, but the write itself is not. Validating `photo_url` against the tenant's prefixes would close it.
- Photo key `services/<id>/photo.<ext>` is still reused on replace with the same extension (cache issue noted by FE-BE-GAPS).
- Generated endpoint descriptions (`shared/infra/docgen`) still mention nothing of the new codes; hand-written notes cover them.

## Open questions
- None open. Answered during the task by the owner: item 4 → grant `shared/infra/storage`; item 2 → leave the `*_required` codes out.
