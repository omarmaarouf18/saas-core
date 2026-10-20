# Worklog: FIX-COD-RECON — a COD delivery with a GPS distance mismatch must still complete

## Task and scope
- Task ID: FIX-COD-RECON
- Item IDs covered: 1–4
- Allowed paths (lane): `services/user-service/**`, a NEW file under `tests/e2e/`, this worklog.
  Not touched: `frontend/**` (FE-CUST-2, FE-LINUX-BUILD), `tests/e2e/contract_auth_test.go` and the
  release-gate workflow (FIX-E2E-EMAIL), hot paths, ADRs, AI_CONTEXT, changelogs.
- Agent branch: agent/FIX-COD-RECON-cod-complete-before-recon, created from logic-exploitation (28326739)

## Decisions taken
- **Flag shape**: a dedicated optional sub-document `distance_review {actual_km, booked_km, flagged_at, source}`
  on `Job` (`models.DistanceReview`), not the `reconciliation_note` fields. Reason: `reconciliation_note` /
  `escrow_failure_reason` belong to the escrow queue and `ResolveReconciliation` overwrites them; a separate
  field keeps the COD flag independent of escrow state. `source` is `complete_job` (set by CompleteJob) or
  `stuck_job_repair` (set by the repair CLI, where the cash is the booked amount, not a courier entry).
- **Item 1**: for `payment_method == "cod"` the ADR-0007 check still runs, still logs and still ships the
  existing `TRACKED_DISTANCE_MISMATCH` security event, then falls through to the unchanged COD path.
  `CompleteCODJob` gained a `review *models.DistanceReview` argument and writes it in the same atomic
  update as the status flip and cash. The COD path still requires `cash_collected: true` (400 otherwise,
  as for every COD job); the security event is shipped before that check, as before. The non-COD branch
  is byte-for-byte the same code (now an `else if`).
- **Item 2**: `OwnerJobResponse.DistanceReview` (omitempty). Customer and employee DTOs do not carry it.
  The reconciliation queue is status-based and COD jobs now complete, so no queue change was needed.
- **Item 3**: the count matches exactly what the task asked (COD, `escrow_reconciliation_required`,
  `locked_escrow_amount` 0 or missing) and reports `by_reason` plus `repairable`. The repair only touches
  the subset with `escrow_failure_reason == "under_distance_mismatch"` (the reason CompleteJob wrote) and
  reports the others as skipped. In the current code the other reconciliation writers (escrow rollback
  failures in TrackJob/RespondPrice) store a positive locked amount, so in practice the subset is the
  whole count; the restriction is a safety belt against repairing a job stuck for an unrelated reason.
- Repair cash = agreed price if > 0, else `TenantBasePrice + booked km × TenantPricePerKM` (CompleteJob's
  formula) using the service's **current** pricing; booked km = `booked_distance`, else the value parsed
  from the reconciliation note. An `actual_cash_amount` already on the job is kept. The repair also
  releases the courier's `employee_locations.active_job_id` lock, because the pre-fix early return never
  released it (CompleteJob releases it on every completion). `reconciliation_note` is kept as audit trail.
- Without `--confirm` the repair is a dry run (prints the plan, writes nothing). Any argument other than
  `--confirm` is refused with exit 2 before config or DB access.

## Changes per commit (message only — NO SHAs)
1. `FIX-COD-RECON: complete COD jobs despite GPS under-distance mismatch`
2. `FIX-COD-RECON: expose COD distance_review in the owner job DTO`
3. `FIX-COD-RECON: CLI to count and repair stuck COD reconciliation jobs`
4. `FIX-COD-RECON: E2E case for COD under-distance completion`
5. `FIX-COD-RECON: worklog` (this file)

## Regression proof (test → failed before the fix?)

| Test | Failed before fix | Evidence |
| :--- | :--- | :--- |
| `TestCompleteJob_CODUnderDistanceCompletesWithReviewFlag` (item 1) | yes | run on logic-exploitation code, output below |
| `TestCompleteJob_CODNormalDistanceUnchanged` (item 1) | no — guard, passes before and after | same run |
| `TestCompleteJob_WalletUnderDistanceStillReconciles` (item 1) | no — guard, passes before and after | same run |
| ADR-0007 subtest (c) in `handlers_test.go`, `TestADR0007_E2E_DeliveryGPSReconciliation` step 3 | n/a — they pinned the old COD behaviour; rewritten to the new contract | — |
| `TestOwnerJobDTO_DistanceReviewOwnerOnly` (item 2) | yes | run on the item-1 commit, output below |
| `TestCODDistanceReview_VisibleToOwnerNotInReconciliationQueue` (item 2) | yes (owner view assertion). Its queue assertion alone would already pass on the item-1 commit; against logic-exploitation it fails too (the COD job is in the queue there — the E2E run below shows that) | output below |
| `TestStuckCODReconciliation_CountAndRepair`, `TestParseDistanceMismatchNote` (item 3) | yes — did not compile (new feature) | `go vet` output below |
| `TestCOD_UnderDistanceCompletion` (item 4, E2E) | yes — against the running staging stack, which does not have this fix | output below |

Item 1, before the fix (literal, from `go test -run ...` with only the new test file added):
```
--- FAIL: TestCompleteJob_CODUnderDistanceCompletesWithReviewFlag (0.50s)
    cod_distance_review_regression_test.go:88: response cash_amount_recorded = <nil>, want 150.25 (COD path must run)
    cod_distance_review_regression_test.go:93: status = escrow_reconciliation_required, want completed (COD completion must never be blocked by the distance check)
    cod_distance_review_regression_test.go:96: actual_cash_amount = <nil>, want 150.25 (collected cash was never recorded)
FAIL	github.com/project/user-service/internal/handlers	1.522s
```
(The `:103` "distance_review flag missing" line also printed; it is omitted here because it embeds a long
job JSON dump.)

Item 2, before the fix (literal, test added on top of the item-1 commit; the long JSON in each line is cut
here with `…`):
```
--- FAIL: TestOwnerJobDTO_DistanceReviewOwnerOnly (0.00s)
    cod_distance_review_owner_visibility_test.go:37: owner DTO lacks distance_review: map[created_at:0001-01-01T00:00:00Z …]
--- FAIL: TestCODDistanceReview_VisibleToOwnerNotInReconciliationQueue (1.04s)
    cod_distance_review_owner_visibility_test.go:100: owner job view lacks distance_review: {"id":"job-cod-review-visible", … "actual_cash_amount":209.8, …}
FAIL	github.com/project/user-service/internal/handlers	1.043s
```

Item 3, before the fix (literal `go vet ./internal/store/` with only the test file added):
```
# github.com/project/user-service/internal/store
# [github.com/project/user-service/internal/store]
vet: internal/store/stuck_cod_reconciliation_test.go:66:17: undefined: CountStuckCODReconciliationJobs
```

## Verification
- `go test -count=1 ./...` in `services/user-service` (run under `scripts/ci-lock.sh`, `MONGO_URI` set to
  the local dev URI the gate uses), on the item-4 commit — summary lines:
  ```
  ?   	github.com/project/user-service/cmd	[no test files]
  ok  	github.com/project/user-service/internal/config	0.002s
  ok  	github.com/project/user-service/internal/handlers	180.052s
  ok  	github.com/project/user-service/internal/models	0.004s
  ok  	github.com/project/user-service/internal/store	34.074s
  ```
- `make check` before each commit. Items 1–3: scope `go=services/user-service contracts docgen`, all
  passed. Item 4 (`tests/e2e/` is an unmapped path, so the gate ran full scope) — last lines:
  ```
  [timing] flutter-analyze-test 88.1s
  [timing] total 755.1s
  == pre-push gate: all checks passed (scope: full) ==
  ```
  The first item-1 run FAILED on `TestADR0007_E2E_DeliveryGPSReconciliation` step 3 (it pinned the old COD
  behaviour); that test was updated and the rerun passed before the commit.
- CLI argument guard (local, no DB access): `go run ./cmd --repair-stuck-cod-reconciliation-jobs --yes`
  printed `unknown argument "--yes" (only --confirm is accepted)`, `exit status 2`.
- E2E (`go test -count=1 -v -run TestCOD_UnderDistanceCompletion ./` in `tests/e2e`) against the local
  staging stack. That stack was built from the FIX-E2E-EMAIL worktree (another agent's, without this fix);
  I did not rebuild shared staging. The case FAILED as expected, which confirms the bug end to end
  (literal; long response bodies cut with `…`):
  ```
  cod_under_distance_test.go:93: ASSERTION FAILED: cash_amount_recorded = <nil>, want 150 (body {… "message":"job flagged for escrow reconciliation review due to tracked distance mismatch", … "status":"escrow_reconciliation_required"}
  cod_under_distance_test.go:96: ASSERTION FAILED: completion response lacks distance_review: {…}
  cod_under_distance_test.go:112: ASSERTION FAILED: owner view status=escrow_reconciliation_required actual_cash_amount=<nil>, want completed / 150
  cod_under_distance_test.go:116: ASSERTION FAILED: owner view distance_review = <nil>, want booked_km 100
  cod_under_distance_test.go:133: ASSERTION FAILED: COD job job-cod-recon-271165 must not be in the escrow reconciliation queue
  --- FAIL: TestCOD_UnderDistanceCompletion (0.12s)
  FAIL	github.com/project/tests/e2e	0.130s
  ```
  The test cleans up its seeded tenant, users and job when it finishes.

`git log --oneline logic-exploitation..HEAD` (before this worklog commit; the short SHAs are replaced by
`<sha>` because they change on merge, per docs/worklog/README.md, and are in the chat report):
```
<sha> FIX-COD-RECON: E2E case for COD under-distance completion
<sha> FIX-COD-RECON: CLI to count and repair stuck COD reconciliation jobs
<sha> FIX-COD-RECON: expose COD distance_review in the owner job DTO
<sha> FIX-COD-RECON: complete COD jobs despite GPS under-distance mismatch
```

`git diff --stat logic-exploitation..HEAD | tail -5` (before this worklog commit):
```
 services/user-service/internal/store/mongodb.go    |  13 +-
 .../internal/store/stuck_cod_reconciliation.go     | 231 +++++++++++++++++++++
 .../store/stuck_cod_reconciliation_test.go         | 143 +++++++++++++
 tests/e2e/cod_under_distance_test.go               | 136 ++++++++++++
 12 files changed, 986 insertions(+), 33 deletions(-)
```

## Owner actions
Run after this branch is deployed. Neither command was run by the agent against any real database.

1. Count (read-only, never writes):
   ```
   docker exec saas-user-service /bin/service --count-stuck-cod-reconciliation-jobs
   ```
   It prints JSON like `{"total":N,"by_reason":{"under_distance_mismatch":N},"repairable":N}`.
2. If `repairable > 0`, dry run first (writes nothing, prints the plan with each job's cash amount):
   ```
   docker exec saas-user-service /bin/service --repair-stuck-cod-reconciliation-jobs
   ```
3. If the plan looks right, apply it (idempotent, so a rerun repairs nothing more):
   ```
   docker exec saas-user-service /bin/service --repair-stuck-cod-reconciliation-jobs --confirm
   ```
   Jobs listed under `skipped` (another `escrow_failure_reason`, or a missing service) stay in the
   reconciliation queue and need a manual decision.

The container name and `/bin/service` path come from the SEC-PAY worklog's command for
`--count-unfunded-digital-jobs`. I did not check them against the production compose file.

## Unverified
- The E2E case has NOT passed against a staging build that includes this fix (staging belongs to another
  running agent; I did not rebuild it). It passes in-process: the same flow is covered by the handler
  tests above.
- The CLI commands were exercised only through the store test (`RepairStuckCODReconciliationJobs` /
  `CountStuckCODReconciliationJobs` against a throwaway DB) and the argument guard; the `main.go` wiring
  of the two flags against a real Mongo was not run.
- Repaired cash is computed from the service's current pricing. If an owner repriced the service after
  booking, the repaired `actual_cash_amount` differs from what was quoted. The real cash taken at the door
  is unknown for these jobs; `source: "stuck_job_repair"` marks them.

## Follow-ups / out-of-lane findings
- ADR-0007 §2 Phase 1 point 4 and §3 still say an under-distance mismatch moves the job to
  `escrow_reconciliation_required` for all payment methods; ADR-0028 §1.2 item 5/6 say the fix is
  scheduled under FIX-COD-RECON. An owner addendum should record the COD exception (ADRs are owner-edited).
- `ResolveReconciliation` `release_to_employee` for COD calls `CompleteCODJob(ctx, job.ID, 0, nil)`, which
  records `actual_cash_amount: 0`. That stays reachable for COD jobs already stuck until the repair runs.
  Not changed here (the task scoped item 1 to CompleteJob).
- The frontend does not read `distance_review` yet. That needs a frontend task (out of lane).
- `scripts/changed-scope.sh` treats `tests/e2e/**` as unmapped, so any E2E-only change runs the full gate
  (~12.5 min here).

## Open questions
- none
