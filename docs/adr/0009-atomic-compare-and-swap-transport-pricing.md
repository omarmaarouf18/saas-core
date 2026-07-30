# ADR-0009: Atomic Compare-and-Swap Filter Guards for Negotiable Transport Pricing

- **Status**: Accepted
- **Date**: 2026-07-28
- **Related Commit SHA**: ffb75f989bd25ed0ac5bb54f46094a66ecad0080
- **Related audit finding**: Negotiable Transport Pricing TOCTOU Race Audit (Gap 1 & Gap 2)

## Context

During a manual security audit of the negotiable transport pricing flow (ADR-0006), two Time-of-Check to Time-of-Use (TOCTOU) race conditions were identified in `services/user-service/internal/handlers/handlers.go` and `services/user-service/internal/store/mongodb.go`:

1. **Gap 1 (`RespondPrice` Double Escrow Lock Race)**:
   The `RespondPrice` handler fetched a job record via `GetJob`, checked `job.Status == AwaitingPriceResponse` in memory, and then executed `LockEscrow` followed by `UpdateJobAgreedPrice` or `UpdateJobCancellation`. Neither `UpdateJobAgreedPrice` nor `UpdateJobCancellation` conditioned their MongoDB update filters on `status == AwaitingPriceResponse` (querying only `{"_id": id}`). Two concurrent `accept` requests could both pass the in-memory status check before either wrote to the database, both invoke `LockEscrow` independently, and both succeed if the wallet balance covered the fare twice — resulting in double escrow deduction for a single job.

2. **Gap 2 (`ProposePrice` Overwritten Proposal Race)**:
   The `ProposePrice` handler checked `job.ProposedPrice != nil` against a stale in-memory snapshot before invoking `UpdateJobPriceProposal`. Because `UpdateJobPriceProposal` queried `{"_id": id}` unconditionally, two concurrent price proposals from opposing parties could silently overwrite each other in MongoDB rather than rejecting the second attempt.

## Decision

We implemented atomic Compare-and-Swap (CAS) query filters across MongoDB store operations for negotiable transport pricing:

1. **Status-Conditioned Agreed Price & Cancellation Updates**:
   `UpdateJobAgreedPrice` and `UpdateJobCancellation` now condition their MongoDB `UpdateOne` filter on `{"_id": id, "status": models.JobStatusAwaitingPriceResponse}`. If `MatchedCount == 0`, the operation fails and returns a specific `job_state_changed` error.

2. **Compare-and-Swap Price Proposal Updates**:
   `UpdateJobPriceProposal` now conditions its `UpdateOne` filter on `{"_id": id, "status": models.JobStatusAwaitingPriceResponse, "proposed_price": priceMatch}` (where `priceMatch` allows `nil` for initial proposals or matching current proposal for timestamp updates). If `MatchedCount == 0`, the operation fails and returns a `job_state_changed` error.

3. **Escrow Lock Rollback on State Conflict**:
   If `RespondPrice` encounters a `job_state_changed` error during `UpdateJobAgreedPrice`, it immediately invokes `performRollbackEscrow` to refund the temporarily locked escrow amount to the owner's wallet and returns `409 Conflict` to the client.

## Consequences

- **Financial Integrity**: Double escrow locks are mathematically prevented under concurrent request execution. Unsuccessful concurrent accept attempts release their temporary escrow locks automatically.
- **State Consistency**: Price proposals cannot be silently overwritten by concurrent submitters; losing requests receive `409 Conflict` with `"error": "job_state_changed"`.
- **Database Overhead**: Minimal — MongoDB evaluates indexed `_id` and scalar `status`/`proposed_price` fields in single atomic update operations.

## Alternatives Considered

- **Application-Level Mutex Locking**: Using Go `sync.Mutex` per job ID in memory. Rejected because it does not protect against multi-replica horizontally scaled deployments.
- **Distributed Redis Lock (`redlock`)**: Acquiring a distributed lock prior to reading `GetJob`. Deferred in favor of native MongoDB atomic compare-and-swap filters, which require zero external locking infrastructure and guarantee database-level atomicity.

## Follow-up Hardening (Gap 3: Escrow Lock Rollback Failure & Reconciliation Queue Fallback)

- **Context**: In the initial `job_state_changed` escrow lock rollback logic, if `performRollbackEscrow` failed (e.g. transient DB network error), the single failure was logged and `409 Conflict` was returned without retrying or persisting a reconciliation record. This created a potential financial leak where locked escrow funds could remain orphaned in the owner's wallet balance with no operational trace.
- **Hardening Implemented**:
  1. **Retry Mechanism**: On `performRollbackEscrow` failure in the `job_state_changed` branch of `RespondPrice`, the handler logs a warning and retries `performRollbackEscrow` once.
  2. **Operator Reconciliation Fallback**: If the retry also fails, the handler invokes `u.store.UpdateJobReconciliation` to transition the job status to `models.JobStatusEscrowReconciliationRequired` with durable context in `ReconciliationNote` and `EscrowFailureReason`.
  3. **Response Parity**: The handler continues to return HTTP `409 Conflict` (`"error": "job_state_changed"`) to the client, while preserving the job for operator reconciliation in the reconciliation queue.
- **Verification**: Verified via `TestRespondPrice_JobStateChanged_RollbackFailure_ReconciliationFallback` asserting single retry attempt, status transition to `escrow_reconciliation_required`, reconciliation note generation, and HTTP 409 response parity.
