# Worklog: TST-02 — seed writes get their own ctx and fail loudly

## Task and scope
- Task ID: TST-02
- Item IDs covered: none
- Allowed paths (lane from the task prompt): `services/user-service/internal/handlers/*_test.go`, `docs/worklog/TST-02.md`. No production code.
- Agent branch: agent/TST-02-seed-ctx, created from logic-exploitation (11d863e6)

## Problem
Handler integration tests did
`ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)`, passed
that ctx to `store.NewMongoDB` (connect, indexes, platform config, seed data) and
then reused it for seed writes with the error dropped
(`_ = s.UpsertSubscription(ctx, …)`, `s.CreateService(ctx, …)`). When setup used up
the budget on a loaded local stack, the seed was never written and the handler
correctly answered 402 `upgrade_required` (or `service not found`), so the test
failed far from the cause. `store.CreateService` returns nothing and only logs
insert errors, so its failures were invisible even without `_ =`.

## Decisions taken
- Setup ctx split, applied to every handler test where a
  `context.WithTimeout(context.Background(), D)` ctx is passed to `store.NewMongoDB`
  **and** used again afterwards (37 sites in 19 files): `NewMongoDB` now gets
  `connectCtx` with the original budget `D` (so a missing Mongo still skips fast,
  same as before), and `ctx` becomes a separate 60 s context created alongside it.
  The existing `defer cancel()` / `t.Cleanup(cancel)` / cleanup-func handling of
  `ctx` is unchanged. Sites where the timeout ctx is used only for `NewMongoDB`
  (12 sites) were left alone: nothing reuses it.
- Every seed write whose error was discarded (`_ =`, `_, _ =`, or a bare call) on a
  store write method (CreateJob, UpsertSubscription, UpsertEmployeeLocation, Deposit,
  LockEscrow, UpdateJob*, GetOrCreateWallet, TryAcquireCourierLock,
  CreatePayoutRequest, RejectPayoutRequest) now does
  `if err := …; err != nil { t.Fatalf("seed <Method>: %v", err) }` — 283 sites in
  all handler test files, not only the ones with a timeout ctx, because a dropped
  seed error is the same silent failure whatever the ctx.
- New test helper `mustCreateService` (`seed_helpers_test.go`): calls
  `store.CreateService`, reads the service back with `GetServiceByID` and fails with
  `seed CreateService "<id>": not written (ctx err: …)` if it is missing. 98 bare
  `CreateService` seed calls use it. Changing `CreateService` to return an error is
  production code, out of lane (follow-up).
- The rewrite was done with a throwaway go/ast tool (outside the repo), then
  `gofmt -w`. It only touches calls whose first argument is a context
  (`ctx`, `*Ctx`, `context.Background()`), so handler calls like
  `u.CreateService(rec, req)` are untouched.
- Left as is: `_ = s.LockEscrow(…)` inside the goroutines of the concurrency test in
  `money_state_repro_test.go` (the race is the point, and `t.Fatalf` must not run off
  the test goroutine); `_ = s.DropDatabase(…)`, `Close`, Redis `FlushAll`/`Del` in
  cleanup.
- Two writes were failing on **every** run and only "passed" because the error was
  dropped. Fixed in the test, behaviour unchanged:
  - `handlers_test.go` (TestUserServiceHandlers, CompleteJob internal-token subtest):
    "Reset job status to active" ran `UpdateJobStatus(completed -> active)`, which the
    store rejects (`job_state_changed: … invalid status transition to active`). The
    call is removed with a comment; step B fails on the requester check before
    status matters and step C uses its own job.
  - `handlers_test.go` ("UpdateJobLocation Throttle Error Rollback"): the subtest's
    "self-contained" seed re-created `active-job-777`, which an earlier subtest
    already created (`job "active-job-777" already exists`). Now created only when
    absent (`s.GetJob == nil`), so the subtest still works on its own.

## Changes per commit (message only — NO SHAs)
1. `TST-02: handler tests seed on their own ctx and fail loudly on seed errors`
2. `TST-02: worklog`

## Verification
- Probe "artificially short setup budget": a temporary
  `time.Sleep(2500 * time.Millisecond)` inserted right after every
  `s, err := store.NewMongoDB(…)` in the target files (not committed), run under the
  shared CI lock with the gate's `MONGO_URI`/`REDIS_URI`:
  - **Original code** (HEAD of logic-exploitation), service_owner_config tests:
    `--- FAIL: TestOwnerConfigurationSave_ReproLiveError (3.17s)` …
    `Expected 200 OK for UpdateService, got 402. Body: {"error":"upgrade_required",…}`
    and `--- FAIL: TestService_OwnerConfigurationAndUpdates (3.00s)` …
    `Expected 201 Created, got 402` (followed by a nil-map panic in a later subtest).
    This is the silent 402 seen on 2026-10-16.
  - **New code**, same probe: `ok  	github.com/project/user-service/internal/handlers	6.360s`.
  - **New code, seed ctx shrunk to 1 ms** (seeding must fail loudly):
    `service_owner_config_repro_test.go:86: seed UpsertSubscription: … context deadline exceeded`
    and `service_owner_config_test.go:108: seed UpsertSubscription: … context deadline exceeded`.
- Same probe for the two other one-off failures from 2026-10-16:
  - Original code: `TestTrackJob_RedisBackedIdempotency_MultiInstanceAndTTL` →
    `Expected status 201 Created on instance 1, got 400. Body: {"error":"service not found"}`
    — the exact message from the OPS-HARDEN run (the `CreateService` seed was lost to
    the expired 2 s ctx). `TestTrackJob_EscrowRollbackFailure_ReconciliationRequired` →
    `Failed to deposit funds: … context deadline exceeded`.
  - New code: both `--- PASS`.
- Full handler package with the gate env (`MONGO_URI`/`REDIS_URI` as in
  `.githooks/pre-push`), before the two test-bug fixes: FAIL with exactly the two
  always-failing writes above (`seed UpdateJobStatus`, `seed CreateJob`); all else
  passed, 0 skips. After the fixes: `ok  	github.com/project/user-service/internal/handlers	102.244s`,
  0 skips.
- `make ci` before commit 1 — PASS (`All tests passed!`,
  `== pre-push gate: all checks passed ==`).
- `make ci` before commit 2 (this worklog) — see the final chat report.

## Unverified
- That the escrow-rollback failure in RB-01 had the same message as the probe: its
  original failure text is not in this worktree. The probe shows the same setup-ctx
  pattern breaks that test (2 s ctx reused for `CreateService`, `Deposit`,
  `UpsertEmployeeLocation`), and its new code passes under the probe; the RB-01 text
  itself was not compared.
- The Redis-backed idempotency test's original failure (OPS-HARDEN worklog) matched
  the probe's message exactly; whether its run actually exceeded 2 s of setup is
  inferred, not measured.

## Follow-ups / out-of-lane findings
- `store.CreateService` (production) swallows insert errors (`log.Printf` only). It
  should return `error`; `mustCreateService` could then shrink to an error check.
- `store.NewMongoDB` runs `ensurePlatformConfig` and `ensureSeedData` without
  returning their errors. With the unchanged short connect budget, an expired
  `connectCtx` there leaves platform config / seed data missing silently. Also, an
  expired budget in `ensureIndexes` makes these tests **skip** ("MongoDB not
  available"), which `make ci` reports as a pass. Worth a longer connect budget or
  a hard fail when `MONGO_URI` is set.
- Several handler tests default to `mongodb://localhost:27017` without credentials
  and skip when `MONGO_URI` is unset (the gate sets it, so CI is unaffected; a bare
  `go test` silently skips them).

## Open questions
- none
