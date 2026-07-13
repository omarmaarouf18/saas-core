# ADR-0002: Per-Job Escrow Integrity and Location Validation

- **Status**: Accepted
- **Date**: 2026-07-13
- **Related Commit SHA**: `logic-exploitation`
- **Related audit finding**: Escrow Recalculation Depletion via Spoofed Employee Location

## Context
Commit 111d094 ("source destination coordinates from live GPS feed for pricing") changed `CompleteJob` and `CancelJob` in `services/user-service/internal/handlers/handlers.go` to prefer `job.CurrentLocation` over `job.Location` when recalculating price/escrow amounts. `job.CurrentLocation` was populated by `UpdateJobLocation`, which accepted arbitrary, unvalidated latitude/longitude from the assigned employee with no plausibility checks.

This allowed assigned employees to spoof coordinates to artificially inflate completion prices and deplete the tenant's wallet escrow pool. Furthermore, the escrow pool was shared globally across a tenant's wallet, meaning a single spoofed job could drain escrow deposits belonging to other, unrelated jobs for the same tenant.

## Decision
We decided to enforce structural integrity in escrow accounting and location reporting.

Specifically:
1. **Revert Unsafe Location Pricing**: Reverted the changes from commit 111d094 to go back to using `job.Location` (locked at booking time) as the sole pricing input.
2. **Persist Locked Escrow**: Added the `LockedEscrowAmount` field to the `Job` struct and persisted it to the database at `TrackJob` time.
3. **TrackJob Persistence Failure Handling**: If `UpdateJobLockedEscrow` fails after the wallet escrow lock succeeds, we roll back the escrow lock (releasing funds back to the owner's withdrawable balance) and delete the job record, returning a 500 error to the client to fail cleanly.
4. **Per-Job Escrow Isolation**: Refactored `ReleaseEscrowWithSplit` and `RefundEscrow` in the MongoDB store to atomically verify and deduct against the specific job's `locked_escrow_amount` (filtering by job ID, active/pending status, and sufficient locked amount via `UpdateOne`).
5. **Fail-Closed on Unrecorded Escrow**: In `CompleteJob` and `CancelJob`, if `LockedEscrowAmount == 0` (and payment method is not COD), we do not cap to zero. Instead, we fail-closed with `escrow_amount_unrecorded` error, log a `[SECURITY WARNING]`, and ship a security event.
6. **Standalone MongoDB Fallback**: Implemented a graceful fallback to sequential atomic updates if multi-document transactions fail due to the database running as a standalone server without replica sets (common in local development).
7. **Capped Settlement Ceiling**: Enforced a ceiling on `CompleteJob` and `CancelJob` recalculations. If the recomputed price exceeds `job.LockedEscrowAmount`, we cap the release/refund at the locked amount and log/audit-event `ESCROW_LIMIT_EXCEEDED`.
8. **Speed Plausibility Check**: Rejected `UpdateJobLocation` requests that imply a speed exceeding `150.0` km/h since the last update (or job creation as a fallback).
9. **Test-Enablement Exception for Non-COD Payments**: Allowed non-COD payment methods (such as `wallet`) to bypass the `TrackJob` hard-reject check ONLY when `APP_ENV` is explicitly set to `local` or `test`. This allows verification of the per-job escrow isolation, locking, and release pathways via unit/integration tests; in all production deployments, any non-COD payment method continues to be blocked at the edge.

## Consequences
- **Security Posture**: Closes the escrow depletion vulnerability. Spoofed employee coordinates are rejected if they imply implausible speeds, and even if they are accepted, they are not used for price recalculation.
- **Escrow Integrity**: The escrow pool for a tenant is isolated per-job. Unrelated jobs under the same tenant are fully isolated; one job's completion cannot draw down the escrow reserved for another.
- **Testability**: Enabling non-COD payments dynamically in `local`/`test` environments allows full end-to-end integration and concurrency testing of the escrow management and profit-splitting algorithms, while maintaining a strict `cod`-only security boundary in production.
- **Race Condition Verification**: Restricted escrow drawdown to `UpdateOne` calls that filter on status transitions and deduct from the specific job's `locked_escrow_amount`. Concurrency testing (firing concurrent complete/cancel requests, complete/complete, and cancel/cancel) confirmed that the atomic state transition pattern successfully closes the race-condition: exactly one request succeeds, returning a conflict/forbidden status for concurrent calls, while the wallet and ledger record exactly one payout/refund.
- **Developer Experience**: Standalone MongoDB fallback allows tests and local developer setups to run seamlessly without needing replica set configurations.

## Alternatives Considered
- **Strict Transaction Requirement**: Requiring replica sets for all environments was considered but rejected to maintain lightweight local development and testing workflows on standalone instances.
- **Dynamic Escrow Auto-Replenishment**: Automatically withdrawing additional funds from the tenant's wallet to cover recomputed overages was rejected to protect tenants from unexpected budget drawdowns and potential fraud.
