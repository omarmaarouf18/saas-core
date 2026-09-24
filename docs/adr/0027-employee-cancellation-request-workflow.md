# ADR-0027: Employee Cancellation-Request Workflow (Owner-Approved)

- **Status**: Accepted
- **Date**: 2026-09-24
- **Related**: Prior "employee/customer cancel" task (direct employee cancel via `CancelJob`, now superseded for employees — flagged as BREAKING in the changelog); ADR-0024 (deliberate no-sweeper precedent for request-time enforcement); negotiable-pricing cascade (`ProposePrice`/`RespondPrice` patterns reused throughout)
- **Implementation**: backend request/respond endpoints + lazy expiry land as the step-2 commit; employee request UI + owner respond UI land as the step-3 commit (see `docs/changelog/new-features.md`).

## Context

`POST /users/jobs/cancel` (`CancelJob`, `jobs_handlers.go:2653`) currently lets an assigned employee cancel a job outright — same power as the job owner, with money movement (escrow refunds) attached and no second pair of eyes. Cancellation is the one job action that destroys the trip itself (unlike location updates or price proposals), so employee-initiated cancellation should be a *request* the owner approves, not a unilateral act. Customer-initiated cancellation is explicitly out of scope here and stays exactly as it is (immediate, via the existing endpoint, no approval step); owner-initiated cancellation is likewise unchanged.

## Decision

### 1. Employees lose direct access to CancelJob

Remove `"employee"` from `CancelJob`'s `resolveTokenWithRole` list (`jobs_handlers.go:2734`). Owner and customer/user entries stay; the state rules below it (completed/cancelled → 409, active → owner-only, pending/pending_dispatch → owner+customer) are untouched. Note the role list was already nearly moot for employees — the tenant-scope check below it only admits the job's owner or customer — but removing it closes the role grant explicitly rather than relying on the scope check to do the work.

### 2. New endpoint: employee submits a cancellation REQUEST

`POST /users/jobs/request-cancellation`, accepting `{job_id, reason}` (+ the standard requester-token shapes this file already accepts). Rules, mirroring `CancelJob`'s existing validation verbatim:

- Caller must resolve to role `employee` AND equal `job.EmployeeID` (the *assigned* employee — offered-but-unaccepted couriers in `pending_dispatch` already have the decline path; this endpoint is for post-acceptance detachment).
- Job status must be `active` or `awaiting_price_response` (the two assigned states). Completed/cancelled/unavailable → 409 via the same state-rule style as `CancelJob`.
- `reason` required, non-empty after trim, ≤ 500 runes — identical messages to `CancelJob`'s `reason is required` / `reason cannot exceed 500 characters`.
- Only one live request: if `CancellationRequestStatus == "pending"` → 409 already-requested. A new request is allowed when the field is empty/`rejected`/`expired` (overwrite).

New `Job` model fields, mirroring the `ProposedPrice`/`ProposedBy`/`PriceProposalExpiresAt` naming style:

```go
CancellationRequestReason  string     // the employee's original reason (≤500)
CancellationRequestedAt    *time.Time // when the request was submitted
CancellationRequestStatus  string     // "pending" | "approved" | "rejected" | "expired"
```

The job's own `Status` does NOT change on submit — the trip stays exactly as visible/active as today. `CustomerJobResponse` deliberately does NOT gain these fields (zero JSON difference for customers); `OwnerJobResponse` and `EmployeeJobResponse` do (owner must see/respond; employee must see pending/rejected outcome — decision #3).

### 3. New endpoint: owner responds, accept/reject

`POST /users/jobs/respond-cancellation`, accepting `{job_id, decision}` with `decision` in `"accept"`/`"decline"` — the exact `RespondPrice` vocabulary (`respondPriceRequest.Decision`), not a third wording. Caller must resolve to role `owner` AND equal `job.OwnerID`.

- **CAS guard (race, decision #5)**: the state transition goes through a store update filtered on `{_id, cancellation_request_status: "pending"}` (the `UpdateJobPriceProposal` pattern: filter carries the expected pre-state, `MatchedCount == 0` → conflict). On zero-match the handler re-reads: if status is now `"expired"` → 409 with a clear already-expired/auto-resolved message; otherwise 409 `job_state_changed`. A late owner response therefore can never re-apply on top of an already-reassigned job.
- **Reject**: sets status to `"rejected"`, keeps the reason and timestamp. Judgment call, stated explicitly: the task text says both "clear the pending-request fields" AND "the state must be visible somewhere on next fetch, not silently dropped" — clearing everything satisfies the first but violates the second, so the resolution is: the *pending* marker is gone (status leaves `"pending"`, the job continues normally, the employee stays assigned) but the terminal outcome persists queryably until superseded by a future request. NoSilentDrop wins over full-clear.
- **Accept**: performs the real cancellation NOW by calling a shared internal function factored out of `CancelJob`'s existing body (refund/escrow-release path, reason recording, status transition, courier-lock release, `JOB_CANCELLED` audit — `jobs_handlers.go:2784-2851`), passing the employee's original `CancellationRequestReason` as the recorded reason. No logic is duplicated; `CancelJob` (owner/customer path) calls the same function. The request status is stamped `"approved"` alongside for audit traceability.

### 4. Timeout: 15 minutes, lazy, assignment-release (NOT cancellation)

`CancellationRequestExpiry = 15 min` from `CancellationRequestedAt`, evaluated by `checkLazyCancellationRequestExpiry` — written as a sibling to `checkLazyPriceProposalExpiry` (`jobs_handlers.go:2860`) and wired at exactly the same call sites (single-job read in `GetJob`, plus the two new endpoints; mirroring `ProposePrice`/`RespondPrice`). No background job/cron: the price-proposal precedent is lazy-only by ADR-0024-era decision. (Honesty note: a `startCascadeSweeper`/`sweepExpiredOffers` goroutine DOES exist for dispatch-offer expiry — the "no sweeper anywhere" claim is true for price proposals and remains the pattern followed here; no new background goroutine is added.)

On expiry (status `pending` + deadline passed), in one store update:

- `EmployeeID` cleared; `Status` → `pending_dispatch`; offer fields reset (`CurrentOfferedEmployeeID` → `""`, `OfferExpiresAt` → nil); the departed ID appended to `OfferedEmployeeIDs` (exclusion so a *different* employee is found); negotiation leftovers cleared (`proposed_price`, `proposed_by`, `agreed_price`, `price_proposal_expires_at` — `AcceptJobOffer` recomputes suggested price and re-locks escrow but never overwrites a stale `agreed_price`, so leaving it would corrupt the next negotiation round); request status → `"expired"` (reason kept for audit).
- Escrow per decision #6 (rollback + zero, never leave-behind).
- Then `advanceCascade` re-offers through the REAL discovery mechanism (sequential offers via `findNextAvailableEmployee` + `sendJobOfferNotification`, falling back to `SetJobUnavailable` + `broadcastJobUnavailable` when no candidates — all automatic inside the existing function). No parallel dispatch mechanism is invented: a brand-new, never-assigned job is exactly `{status: pending_dispatch}` + cascade offer fields, and that is the state reproduced here.

The crux distinction, stated explicitly: **the request timing out is not the same as the cancellation being approved.** The trip/order is NOT cancelled by a timeout — only that employee's assignment is released and the job returns to dispatch. Approval cancels the trip; expiry merely frees the courier.

### 5. Late owner response is a no-op (race handling)

Covered by the CAS guard in decision #3: filter-on-`pending` makes accept/reject atomic against the lazy expiry's own status flip. Whichever lands first wins; the loser gets a clear 409 (`already expired and was auto-resolved` vs `job_state_changed`), never a silent double-apply. No plain read-then-write anywhere on this path.

### 6. Escrow finding (traced, not assumed — double-check this section)

Traced call-site by call-site; this is the money-critical part:

- Escrow locks ONLY at acceptance, never before: `AcceptJobOffer` locks `finalPrice` for non-transport non-COD jobs (line ~2019, `LockEscrow`), and `RespondPrice`-accept locks for non-COD transport (line ~3186). `pending_dispatch` jobs therefore NEVER hold escrow — confirmed by the closest existing analog to detachment, `DeclineJobOffer` (pre-acceptance offer decline), which touches no escrow code at all and just calls `advanceCascade`.
- Active/`awaiting_price_response` jobs, by contrast, MAY hold `LockedEscrowAmount > 0` (locked at their acceptance).
- `RefundEscrow` (`store/mongodb.go:1583`) is cancel-COUPLED and unusable at expiry: its filter requires status active/pending and it flips the job to cancelled itself. Using it on timeout would cancel the trip — exactly what decision #4 forbids.
- Therefore the expiry transition uses `performRollbackEscrow` → `RollbackEscrow` (`store/mongodb.go:1700`), which is wallet-only (escrow_balance → withdrawable_balance + ledger entry) and touches no job state, PLUS an explicit zeroing of `locked_escrow_amount` in the same expiry update. The zeroing is load-bearing, not cosmetic: without it, a later customer/owner `CancelJob` would still see `locked_escrow_amount >= amount` and `RefundEscrow` a second time — a real double-refund. COD jobs and zero-escrow jobs skip the money path entirely (nothing locked, nothing to return).
- Net effect: owner wallet is made whole at unassignment; the NEXT accepting employee re-locks fresh escrow through the normal `AcceptJobOffer` path. Money is never stranded, never double-counted, and never left attached to a job with no assigned courier.

### 7. Non-goals and reuse list

- No change to the customer cancel flow (screens, provider, endpoint behavior all byte-identical); no change to owner-initiated cancellation.
- No new notification system: status-change visibility reuses the existing fire-and-forget `POST /notifications/send` broadcast shape (`broadcastCourierAccepted` pattern: goroutine + panic guard + internal token) for owner↔employee signals, with the job fields as the queryable source of truth.
- New rate limiters mirror the existing `newHandlerLimiter(rate, key)` precedent (`cancelJobLimiter` @10 in `handlers.go:225`); the two new endpoints are never unprotected.
- `APPLICATION_MAP.md` gains both endpoints via the normal `make docs` regeneration (auto-generated from `RegisterRoutes`).
