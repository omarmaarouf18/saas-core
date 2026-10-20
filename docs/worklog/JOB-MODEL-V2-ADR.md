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
1. **ADR-0028 Proposal (`docs/adr/0028-job-model-v2.md`) and Index (`docs/adr/README.md`)** — Done (committed in `b895254e`).
2. **Revision after Owner Review (`docs/adr/0028-job-model-v2.md`)** — Done (committed in `b941aa62`).
3. **Worklog Updates (`docs/worklog/JOB-MODEL-V2-ADR.md`)** — Done (committed in this step, alone).

## Summary of Decisions in ADR-0028 (Revised)
- **Current State Lifecycle & Inconsistencies**: Documented full Mermaid state diagram matching backend handlers and store transitions. Catalogued 6 code inconsistencies and behavioral caveats.
- **Recipient Entity**: Added embedded `JobRecipient` struct (`name`, `phone`, `notes`). Set at booking creation only. Exposed to couriers symmetrically with courier phone to customers: from acceptance (`heading_to_pickup`) until completion or cancellation; phone redacted post-trip.
- **Structured Address Text**: Added `Address` string to `Location` without paid geocoding APIs. Text is sourced from saved address selection, customer input, or merchant service defaults.
- **Status History**: Added `status_history` append-only audit trail appended via MongoDB `$push` on every transition.
- **Picked-Up Step & Umbrella Active State**: Maintained top-level `status: "active"` to prevent breaking >25 MongoDB query filters across escrow and location tracking; `sub_status` is defined strictly when `status == "active"` (`heading_to_pickup` | `picked_up`). `POST /users/jobs/pickup` advances between the two. Legacy active jobs without `sub_status` render as plain "active" without guessing.
- **Zero-Paid-API ETA**: Straight-line Haversine estimation padded for Egyptian urban city traffic (20 km/h average + 3 min buffer) rendered on Flutter client; optional server snapshot on assignment.
- **Courier Contact Exposure**: In-app chat via `chat-service` as primary channel; courier phone exposed to customer symmetrically during ongoing active trips (`heading_to_pickup` to terminal state) and cleared on completion.
- **Package Details**: Included `PackageDetails` (`size`: small/medium/large, `notes`: max 200 chars). Informational only with no price multipliers; default unset in backend.
- **Saved Addresses with Coordinates**: Extended `auth-service` `User` model with `saved_addresses: []SavedAddress` while synchronizing legacy `frequent_addresses: []string` for backward compatibility. Address data is snapshotted into jobs at booking time.
- **Non-Destructive Lazy-Only Migration**: No synthetic migration script. Legacy jobs maintain empty/omitted `status_history`.
- **Database Indexes**: Listed all 7 existing indexes on `jobs` from `store/mongodb.go:104-138`; proposed only the 3 missing composite indexes for customer history, courier active job lookups, and owner fleet monitoring.
- **Rollout Plan**: Sequenced into 6 independent, non-breaking pull requests targeting modern modular frontend directories (`frontend/lib/features/customer/**`, `frontend/lib/features/courier/**` on `frontend/lib/ui/**`).

## Code Inconsistencies Catalogued
1. `assigned` status: Checked in `frontend/lib/screens/customer_home_screen.dart:263` and `frontend/lib/ui/components/qd_status_chip.dart:48`, but nonexistent in backend `models.JobStatus` (`models.go:99-107`).
2. `reconciliation_required` vs `escrow_reconciliation_required`: `frontend/lib/utils/enum_labels.dart:18` and `qd_status_chip.dart:52` check `reconciliation_required`, whereas backend canonical constant is `JobStatusEscrowReconciliationRequired = "escrow_reconciliation_required"` (`models.go:106`).
3. `unavailable` terminal state handling: `store/mongodb.go:835` sets `JobStatusUnavailable` on dispatch cascade exhaustion. It is a terminal state (customer re-books; nothing stuck). `jobs_handlers.go:2905` returns 409 Conflict when attempting to cancel an already-terminal unavailable job.
4. Direct assignment path via employee credential: `jobs_handlers.go:224-250` and `409-425`, `514` (`TrackJob` with `employee_id`) sets `status: JobStatusActive` immediately. Requires a valid employee bearer token and verified tenant binding; transitions directly to active because assignment is pre-arranged.
5. COD distance discrepancy escrow flag: `jobs_handlers.go:756` pushes delivery jobs into `escrow_reconciliation_required` upon GPS discrepancy even when `payment_method == "cod"` and `locked_escrow_amount == 0`.
6. NEW: GPS under-distance check aborts COD cash recording: In `CompleteJob` (`jobs_handlers.go:738-770`), the GPS under-distance check runs before the COD cash collection branch (line 782). If actual distance < 70% of booked distance, the handler immediately flags `escrow_reconciliation_required` (line 756) and returns early (line 769). The courier's cash collection is never recorded, and the order is halted awaiting owner review despite holding zero platform funds. (Fix scheduled separately in `FIX-COD-RECON`).

## Owner Decisions Recorded in ADR (§2.9)
1. **Phone Window**: Courier phone and recipient phone exposed symmetrically from offer acceptance (`heading_to_pickup`) until terminal state (`completed`/`cancelled`); hidden thereafter.
2. **Package Size**: Informational only, no price effect. Default unset/empty in backend.
3. **Category Nomenclature**: Generic tokens in backend (`heading_to_pickup`, `picked_up`); localized contextually in app per category.
4. **Migration**: Strictly lazy on-read; no synthetic history generated.
5. **Address Immutability**: Jobs snapshot address and coordinates at creation; profile edits never touch jobs.
6. **Handover Codes**: Parked; will be added as an optional sub-document on Job when unparked.

## Git Verification

### `git log --oneline logic-exploitation..HEAD`
```text
b941aa62 JOB-MODEL-V2-ADR: revise after owner review
8488dc06 JOB-MODEL-V2-ADR: record job model v2 proposal in worklog
b895254e JOB-MODEL-V2-ADR: propose ADR-0028 job model v2
```

### `git diff --stat logic-exploitation..HEAD`
```text
 docs/adr/0028-job-model-v2.md    | 525 +++++++++++++++++++++++++++++++++++++++
 docs/adr/README.md               |   1 +
 docs/worklog/JOB-MODEL-V2-ADR.md |  62 +++++
 3 files changed, 588 insertions(+)
```
