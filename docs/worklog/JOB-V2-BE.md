# Worklog: JOB-V2-BE — Task 2 backend of ADR-0028 (Job Model v2)

## Task and scope
- Task ID: JOB-V2-BE
- Item IDs covered: 1 (models/DTOs), 2 (booking validation), 3 (status_history), 4 (pickup endpoint + sub_status), 5 (ETA), 6 (courier phone), 7 (indexes), 8 (ratings duplicate-key typed detection), 9 (ADR status documentation), 10 (e2e test)
- Allowed paths (lane from the task prompt): `services/user-service/internal/**` (models, handlers, store for the v2 items), `tests/e2e/job_model_v2_test.go` (new file only), `docs/adr/0028-job-model-v2.md` (status-line documentation update), plus this worklog. No hot-path files (`shared/infra/**`, `go.mod`/`go.sum`, `infrastructure/**`, `.github/**`, `Makefile`, `frontend/**`, `scripts/**`) were touched.
- Agent branch: agent/JOB-V2-BE-job-model-v2-backend, created from logic-exploitation.

## Decisions taken
- Kept the v1 driver packages wherever only non-error APIs are used; ONLY the ratings duplicate-key check (item 8) switched to the v2 `mongo.IsDuplicateKeyError` (covers 11000/11001/12582 and the 16460 "E11000 ..." message shape) — the handler previously imported the old (v1) `go.mongodb.org/mongo-driver/mongo` and also string-matched "11000"/"duplicate key" containment; the string fallback and the v1 import are removed.
- Store `PickupJob` uses a strict CAS filter {active, heading_to_pickup, employee_id: courierID}; on MatchedCount==0 it re-reads and returns STABLE errors: `job_not_found:`, `access_denied: courier %s is not the assigned employee` (rather than 409-style codes), `already_picked_up:`, `job_state_changed:` — the HTTP layer maps these to user-safe messages without leaking internal identifiers.
- The pickup CAS appends the status_history entry as `{status: "active", actor_role: "employee", actor_id: courier, sub_status: "picked_up"}` and, atomically in the same update, `$set`s `sub_status:"picked_up"` and (if provided) `estimated_duration_minutes` (item 5) — no separate doc rewrite, no read-modify-write race.
- `notifyCancellationParty(job, job.UserID, "user", "job_picked_up", ...)` is called by the HANDLER (not the store) after the CAS won; store stays event-agnostic.
- sub_status (`heading_to_pickup` -> `picked_up`) exists ONLY while `status == "active"`. Every store operation that leaves `active` (`$set` to completed/cancelled/etc.) $sets `sub_status: ""` in the same atomic update; only entering-active paths (CourierOffer accept, direct-assignment activation, price-agreement prose advance) write the column from the entry payload.
- Item 3 wiring: 16 store transition methods take `hist ...models.JobStatusHistoryEntry` and `$push` atomically inside the SAME update as the CAS $set (withHistory wrapper: `$set`-prefixed pipeline + arrayUnion-style hist push). Redundant status-writing calls whose state is fully described by their history entries (e.g. `UpdateJobStatus(models.JobStatusTimeoutCompleted)` at the completion path) pass NO entries (documented in-line). Handlers own actor identity resolution: customer token -> user_id, service account -> system+admin (ActorID stripped), owner -> owner_id, courier -> employee/courierID, reviewer->admin/respond cancel/reassign.
- `validateV2BookingFields` (item 2) appends its failures as typed, stable string pairs by "code" + "message" strings — handlers respond with those codes verbatim (API contract unchanged for legacy callers).
- DTO redaction was re-derived in items 1+6: `CustomerJobResponse/OwnerJobResponse/EmployeeJobResponse` all REDACT details when `status != active || employee_id/courier` — the courier PHONE window additionally closes when the job is `completed` (item 6's handlers fetch the phone from the auth service into `CourierPhone` ONLY when active && assigned). No shared hot-path files were edited for this; the DTO change stayed within user-service models.
- The courier-phone lookup uses the INTERNAL service token via `GET /auth/user?id=` — it is keyed by BOTH requester role AND requester id inside `handlers.go`, wrapped in a small per-request memo {employeeID -> phone}; when the auth service fails or the phone is empty the DTO simply omits courier_phone (no promise of presence).
- Item 7: 3 compound jobs indexes per the ADR §4.2 — (user_id,status,created_at:-1), (employee_id,status,sub_status), (owner_id,status,created_at:-1) — created idempotently through the same ensureIndexes loop as existing indexes; no hot-path infra file touched.
- Item 10 (e2e) reseeds fresh `<tenant>_v2_<ts>` identities per run and DERIVES the courier phone from the run timestamp — the fixed "+2010..." pretend phone tripped the auth-db unique phone index on a second run with leftover docs; scrubbing old leftovers manually was needed after an earlier E2E_NO_CLEANUP diagnostic run.

## Changes per commit (message only — NO SHAs)
1. `JOB-V2-BE: add ADR-0028 v2 model fields, DTO projections, redaction and validators`
2. `JOB-V2-BE: TrackJob v2 booking validation (recipient, package, address) with first status_history entry`
3. `JOB-V2-BE: item 3 - server-generated status_history on every transition (ADR-0028 2.3)`
4. `JOB-V2-BE: item 4 - sub_status lifecycle + POST /users/jobs/pickup (ADR-0028 2.9)`
5. `JOB-V2-BE: item 5 - ETA snapshots at accept and pickup (ADR-0028 2.10)`
6. `JOB-V2-BE: item 6 - courier_phone contact window (ADR-0028 2.11)`
7. `JOB-V2-BE: item 7 - ADR-0028 4.2 list-query indexes`
8. `JOB-V2-BE: item 8 - ratings duplicate detection via v2 typed error`
9. `JOB-V2-BE: items 9+10 - ADR status and e2e job model v2 test` (ADR-0028 status line; new tests/e2e/job_model_v2_test.go)

## Verification
- `make check` (equivalent to `make ci`) — PASS before every commit; its output ends with `== pre-push gate: all checks passed (scope: ...)` and `gate stamp OK for this commit`. Items 1-6 ran in prior sessions of this task; item 7 and item 8 ran in this session with scope `go=services/user-service contracts docs infra-tests docgen`; the final commit ran with `scope: full` (378.6s total timing line).
- `gofmt -w/-l` — all touched files formatted; `gofmt -l` returned nothing for the branch's files.
- `go vet` — PASS on `services/user-service/...` where touched in this session; PASS on `tests/e2e/` before the final commit.
- Full user-service suite under ci-lock (`bash scripts/ci-lock.sh bash -c 'cd services/user-service && go test ./... -count=1'` with the dev Mongo/Redis exported) — PASS before the item 7 commit (`handlers 172.106s`, `store 24.250s`, models/config PASS lines, `cmd [no test files]`) and again before the item 8 commit (`handlers 169.994s`, `store 23.637s`, both PASS). All lines captured from the actual runs.
- Focused runs: `TestJobV2Indexes` PASS (0.72s, item 7); `TestV2RateJob_DuplicateTypedDetection` PASS (0.55s, item 8: duplicate POST -> 409 with the exact conflict message, sibling-job sanity insert 201).
- Item 10 e2e against the live staging stack (`bash scripts/staging_up.sh`, then `cd tests/e2e && go test . -run TestE2E_JobModelV2_CODPickupAndPhoneWindow -count=1`): PASS twice back-to-back (cleanup restored both runs). Spot-run of `TestContract_UserService` after the e2e change: PASS (`ok github.com/project/tests/e2e 0.205s`). All e2e requests went through the real gateway at http://localhost:8088/api/v1/users/... .

## Unverified
- The FULL tests/e2e module suite (all CUJ/contract/security files) was NOT re-run on this branch — only the new test (twice) and TestContract_UserService. Reason: the e2e change is a NEW FILE ONLY; no existing e2e file was edited. The owner's CI should be allowed to run the full module at merge time.
- The staging containers' rebuilt binaries were verified only indirectly (the e2e pass requires the deployed user-service to accept `address`/`recipient`/`package_details` and serve courier_phone). No explicit image tag/inspection was done beyond confirming the running /bin/service contains the v2 validation strings (`address_too_long`, docker strings grep count 1).
- Items 1-6's per-run test outputs pre-date this session; their PASS state is recorded from the task's prior sessions and re-confirmed collectively by the full-suite PASSes above (handlers+store include the v2 lifecycle tests added in items 1-6).

## Follow-ups / out-of-lane findings
- `scripts/staging_up.sh` reads `infrastructure/staging/.env.staging` where `MONGO_INITDB_ROOT_PASSWORD=CHANGE_ME_PASSWORD` (leftover placeholder as a real value in the repo's runtime env file). Not touched (hot-path lane); worth an owner cleanup task.
- The auth `users` phone unique index means e2e readers MUST NOT hardcode a shared phone across runs (see the item 10 decision above).

## Open questions
- none
