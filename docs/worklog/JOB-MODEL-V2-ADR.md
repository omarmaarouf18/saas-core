# Worklog: JOB-MODEL-V2-ADR — Architecture Decision Record 0028 (Job Model v2)

## Task and scope
- **Task ID**: `JOB-MODEL-V2-ADR`
- **Goal**: Propose ADR-0028 "Job model v2" (proposal, documentation only, no code changes).
- **Lane**:
  - `docs/adr/0028-job-model-v2.md` (new)
  - `docs/adr/README.md` (index line only)
  - `docs/worklog/JOB-MODEL-V2-ADR.md` (worklog, committed alone)
- **Branch**: `agent/JOB-MODEL-V2-ADR-job-model-v2`, branched from `logic-exploitation` @ `20bc2532`.
- **Parallel Tasks**: `FE-CUST-1` editing `frontend/**` (lane untouched).

## Status per item
1. **ADR-0028 (`docs/adr/0028-job-model-v2.md`) and Index (`docs/adr/README.md`)** — Done (committed in `b895254e`).
2. **Worklog (`docs/worklog/JOB-MODEL-V2-ADR.md`)** — Done (committed in this step, alone).

## Summary of Decisions in ADR-0028
- **Current State Lifecycle & Inconsistencies**: Documented full Mermaid state diagram matching backend handlers and store transitions. Catalogued 5 inconsistencies between frontend and backend (`assigned` frontend-only status, status alias mismatch, `unavailable` cancellation 409 trap, direct dispatch to `active` bypass, and COD distance discrepancy escrow flag).
- **Recipient Entity**: Added embedded `JobRecipient` struct (`name`, `phone`, `notes`). Exposed to couriers only during ongoing jobs (`active` / `awaiting_price_response`), phone redacted upon completion or cancellation.
- **Structured Address Text**: Added `Address` string to `Location` without paid geocoding APIs. Text is sourced from saved address selection, customer input, or merchant service defaults.
- **Status History**: Added `status_history` append-only audit trail appended via MongoDB `$push` on every transition.
- **Picked-Up Step & Umbrella Active State**: Maintained top-level `status: "active"` to prevent breaking >25 MongoDB query filters across escrow and location tracking; introduced `sub_status` (`heading_to_pickup`, `picked_up`, `heading_to_dropoff`) and new endpoint `POST /users/jobs/pickup`.
- **Zero-Paid-API ETA**: Straight-line Haversine estimation padded for Egyptian urban city traffic (20 km/h average + 3 min buffer) rendered on Flutter client; optional server snapshot on assignment.
- **Courier Contact Exposure**: In-app chat via `chat-service` as primary channel; courier phone exposed to customer strictly during active trip and cleared on completion.
- **Package Details**: Included `PackageDetails` (`size`: small/medium/large, `notes`: max 200 chars).
- **Saved Addresses with Coordinates**: Extended `auth-service` `User` model with `saved_addresses: []SavedAddress` while synchronizing legacy `frequent_addresses: []string` for backward compatibility.
- **Rollout Plan**: Sequenced into 6 independent, non-breaking pull requests.

## Code Inconsistencies Catalogued
1. `assigned` status: Checked in `frontend/lib/screens/customer_home_screen.dart:263` and `frontend/lib/ui/components/qd_status_chip.dart:48`, but nonexistent in backend `models.JobStatus` (`models.go:99-107`).
2. `reconciliation_required` vs `escrow_reconciliation_required`: `frontend/lib/utils/enum_labels.dart:18` and `qd_status_chip.dart:52` check `reconciliation_required`, whereas backend canonical constant is `JobStatusEscrowReconciliationRequired = "escrow_reconciliation_required"` (`models.go:106`).
3. `unavailable` state lock: `store/mongodb.go:835` sets `JobStatusUnavailable` on dispatch cascade exhaustion, but `jobs_handlers.go:2905` returns 409 Conflict when attempting to cancel an unavailable job.
4. Direct dispatch to `active`: `jobs_handlers.go:431` directly transitions a job with `employee_id` to `JobStatusActive` without requiring employee acceptance.
5. COD escrow reconciliation flag: `jobs_handlers.go:731` pushes delivery jobs into `escrow_reconciliation_required` upon GPS discrepancy even when `payment_method == "cash"` and `locked_escrow_amount == 0`.

## Open Questions for the Owner & Recommendations
1. **Courier Phone Display Window**: Expose phone on initial acceptance (`heading_to_pickup`) or only after pickup (`picked_up`)?
   - *Recommendation*: Expose on initial acceptance (`heading_to_pickup`) to facilitate pickup gate navigation.
2. **Package Size Pricing Multipliers**: Alter suggested pricing based on package size?
   - *Recommendation*: No automated multipliers in v2; keep as informational capacity signal. Price remains negotiable via `ProposePrice` / `RespondPrice`.
3. **Transport Service Sub-Status Wording**: Use generic backend tokens or mode-specific ones?
   - *Recommendation*: Use generic backend tokens (`heading_to_pickup`, `picked_up`, `heading_to_dropoff`); Flutter ARB handles contextual localization.
4. **Historical Job Backfill Strategy**: CLI migration script vs lazy on-read defaulting?
   - *Recommendation*: Lazy on-read defaulting; historical completed jobs are immutable audit records.
5. **Saved Address Deletion Cascade**: Affect active jobs?
   - *Recommendation*: No; jobs snapshot address and coordinates at booking creation time.
6. **Handover Code Extension Point**: Pickup, delivery, or both?
   - *Recommendation*: Provide placeholders for both in `HandoverVerification` value object.

## Git Verification

### `git log --oneline logic-exploitation..HEAD`
```text
b895254e JOB-MODEL-V2-ADR: propose ADR-0028 job model v2
```

### `git diff --stat logic-exploitation..HEAD`
```text
 docs/adr/0028-job-model-v2.md | 517 ++++++++++++++++++++++++++++++++++++++++++
 docs/adr/README.md            |   1 +
 2 files changed, 518 insertions(+)
```
