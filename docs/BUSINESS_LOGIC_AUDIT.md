# Business Logic & Escrow Financial Safety Audit Report

> [!NOTE]
> **Audit Freshness & Scope Pinning**:
> This report documents confirmed business-logic vulnerabilities, verified-sound security controls, and scope limitations in `services/user-service` and related authorization flows as of Git commit `7a41b95`.

---

## 1. Executive Summary

| Severity | Count | Status | Description |
| :--- | :--- | :--- | :--- |
| **Critical** | 1 | **Confirmed** | COD job `CompleteJob` vs `CancelJob` race condition permitting balance mutation on cancelled jobs. |
| **Medium** | 1 | **Confirmed** | Negotiated `AgreedPrice` ignored in `CancelJob` escrow refund calculation, resulting in locked fund leakage. |
| **Sound / Safe** | 4 | **Verified Safe** | Escrow release double-complete protection, backend KYC enforcement, tenant scope isolation, and employee IDOR protection. |

### Scope Statement
This review was concentrated on the highest-financial-risk surface (job lifecycle + escrow logic in `user-service`, ~12,000 lines in `handlers.go` alone) due to the practical scope of a single review pass, not an exhaustive line-by-line audit of all 5 services. Broader coverage (full `auth-service` review, rate-limiting edge cases, chat/notification scoping, input validation/injection surface) was NOT completed in this pass and would require dedicated follow-up review sessions per area — do not imply broader coverage than what was actually checked.

---

## 2. Finding 1 (Critical): COD Job Cancel/Complete Race Condition

* **Title**: Cash on Delivery (COD) Job `CancelJob` vs `CompleteJob` Race Condition
* **Severity**: Critical
* **Status**: Confirmed
* **Citations**:
  * Store Implementation: [`services/user-service/internal/store/mongodb.go`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/services/user-service/internal/store/mongodb.go#L903-L917) (`CancelJob` lines 903–917)
  * Store Comparisons: [`services/user-service/internal/store/mongodb.go`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/services/user-service/internal/store/mongodb.go#L531-L565) (`ReleaseEscrowWithSplit` lines 531–565), [`services/user-service/internal/store/mongodb.go`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/services/user-service/internal/store/mongodb.go) (legacy COD fee deduction), [`services/user-service/internal/store/mongodb.go`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/services/user-service/internal/store/mongodb.go#L920-L948) (`RefundEscrow` lines 920–948)
  * Handler Implementation: [`services/user-service/internal/handlers/jobs_handlers.go`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/services/user-service/internal/handlers/jobs_handlers.go) (`CancelJob` — *originally `handlers.go` lines 2379–2415 before handlers decomposition*)

> [!NOTE]
> **Business Model Update**: Root cause identified — see [ADR-0017](adr/0017-zero-commission-subscription-only-revenue-model.md) for the corrected business model; code remediation tracked separately.

### Detail & Verification Findings
In `services/user-service/internal/store/mongodb.go`, job status state transitions for non-COD lifecycle operations (`ReleaseEscrowWithSplit`, legacy COD fee deduction, `RefundEscrow`) are all guarded using an atomic compare-and-swap (CAS) pattern. Specifically:
- `ReleaseEscrowWithSplit` conditions its `UpdateOne` query on `status: {$in: [JobStatusActive, JobStatusEscrowReconciliationRequired]}`.
- Legacy COD fee deduction conditioned its `UpdateOne` query on `status: JobStatusActive`.
- `RefundEscrow` conditions its `UpdateOne` query on `status: {$in: [JobStatusActive, JobStatusPending, JobStatusEscrowReconciliationRequired]}`.

In contrast, `CancelJob` in `mongodb.go` (line 904) executes an unguarded database update:
```go
res, err := s.jobs.UpdateOne(ctx, bson.M{"_id": id},
    bson.M{"$set": bson.M{
        "status":              models.JobStatusCancelled,
        "cancellation_reason": reason,
        "updated_at":          time.Now().UTC(),
    }})
```
The query filters strictly on `{"_id": id}` with **no status precondition**.

### Exploitability Path & Concrete Race Scenario
1. **Exploitability Path**: In `services/user-service/internal/handlers/handlers.go` (`CancelJob` handler, line 2379), non-COD jobs invoke `store.RefundEscrow(...)`, which executes the guarded CAS update. However, COD jobs (`job.PaymentMethod == "cod"`) skip `RefundEscrow` entirely and proceed directly to `store.CancelJob(ctx, job.ID, req.Reason)`.
2. **Concrete Concurrency Race**:
   - A `POST /users/jobs/complete` request and a `POST /users/jobs/cancel` request for the same active COD job arrive concurrently.
   - At time of request receipt, both handlers read the job document from MongoDB and observe `Status == JobStatusActive`.
   - `CompleteJob` invokes the completion path (formerly fee deduction), which checks `status: JobStatusActive`, updates the job status to `Completed`, and records a transaction ledger entry.
   - Concurrently, `CancelJob` skips `RefundEscrow` (because `PaymentMethod == "cod"`) and calls `store.CancelJob`.
   - Because `store.CancelJob`'s `UpdateOne` did not filter on `status: JobStatusActive`, it executed successfully after completion committed. It overwrote the job status from `Completed` to `Cancelled` without error.
3. **Financial & State Impact**: The owner's wallet had state mutation in legacy model, while the database retained a final job status of `Cancelled`. The state machine is corrupted and financial metrics diverge.

---

## 3. Finding 2 (Medium): AgreedPrice Ignored in CancelJob Refund Calculation

* **Title**: Negotiated `AgreedPrice` Omitted from `CancelJob` Refund Calculation
* **Severity**: Medium
* **Status**: Confirmed
* **Citations**:
  * `CompleteJob` Handler: [`services/user-service/internal/handlers/jobs_handlers.go`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/services/user-service/internal/handlers/jobs_handlers.go) (originally `handlers.go` lines 888–892)
  * `CancelJob` Handler: [`services/user-service/internal/handlers/jobs_handlers.go`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/services/user-service/internal/handlers/jobs_handlers.go) (originally `handlers.go` lines 2385–2409)
  * Escrow Locking (`RespondPrice`): [`services/user-service/internal/handlers/jobs_handlers.go`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/services/user-service/internal/handlers/jobs_handlers.go) (originally `handlers.go` lines 2744–2784)
  * Store Refund (`RefundEscrow`): [`services/user-service/internal/store/mongodb.go`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/services/user-service/internal/store/mongodb.go#L932-L950) (lines 932–950)

> [!NOTE]
> **Business Model Update**: Root cause identified — see [ADR-0017](adr/0017-zero-commission-subscription-only-revenue-model.md) for the corrected business model; code remediation tracked separately.

### Detail & Verification Findings
In `handlers.go`, `CompleteJob` recalculates the amount to release using the base service pricing formula, but explicitly checks for a negotiated price:
```go
dist := haversineKm(job.Location.Latitude, job.Location.Longitude, svc.Latitude, svc.Longitude)
amount := math.Round((svc.TenantBasePrice+(dist*svc.TenantPricePerKM))*100) / 100
if job.AgreedPrice != nil && *job.AgreedPrice > 0 {
    amount = *job.AgreedPrice
}
```
However, in `CancelJob` (lines 2385–2386), the refund calculation recomputes the amount purely from the base formula:
```go
dist := haversineKm(job.Location.Latitude, job.Location.Longitude, svc.Latitude, svc.Longitude)
amount := math.Round((svc.TenantBasePrice+(dist*svc.TenantPricePerKM))*100) / 100
```
`CancelJob` omits the `if job.AgreedPrice != nil` check entirely.

### Tracing Escrow Locking vs Refund Logic
Tracing `TrackJob` and `RespondPrice` confirms how `LockedEscrowAmount` is established:
1. For standard non-transport jobs, escrow is locked during `TrackJob` based on the standard formula.
2. For transport jobs (`svc.Category == "transport"`), `TrackJob` skips escrow locking (`if isTransport { return }`). Escrow locking is deferred until price negotiation completes in `RespondPrice`.
3. When a price proposal is accepted in `RespondPrice` (lines 2744–2784), the active negotiated price (`activePrice`) is used to lock escrow:
   - `s.LockEscrow(ctx, job.OwnerID, job.ID, activePrice)` locks `activePrice` in the wallet.
   - `s.UpdateJobLockedEscrow(ctx, job.ID, activePrice)` persists `job.LockedEscrowAmount = activePrice`.
   - `s.UpdateJobAgreedPrice(...)` sets `job.AgreedPrice = &activePrice`.

### Analysis & Resolution: Confirmed Defect
Because `LockedEscrowAmount` for negotiated transport jobs is set to `AgreedPrice` rather than the base formula price, `CancelJob`'s failure to consider `AgreedPrice` introduces two defect behaviors:
* **Case 1 (`AgreedPrice` > Base Formula Price)**: E.g., formula price = $100, negotiated `AgreedPrice` = $130 (which locked $130 in escrow). When `CancelJob` executes, it recomputes `amount` = $100 and passes $100 to `RefundEscrow`. `RefundEscrow` deducts $100 from `job.LockedEscrowAmount` ($130 − $100 = $30 remaining) and refunds only $100 to the owner's `withdrawable_balance`. **$30 remains permanently locked in `escrow_balance` and `LockedEscrowAmount`**, trapping owner funds.
* **Case 2 (`AgreedPrice` < Base Formula Price)**: E.g., formula price = $100, negotiated `AgreedPrice` = $70 (locking $70). `CancelJob` recomputes `amount` = $100. Line 2399 (`if amount > job.LockedEscrowAmount { amount = job.LockedEscrowAmount }`) caps `amount` at $70, preventing an over-refund. However, relying on a safety cap rather than correctly calculating `amount` from `AgreedPrice` is asymmetrical with `CompleteJob`.

Finding 2 is **Confirmed** as a medium-severity business logic defect.

---

## 4. Reviewed and Found Sound

The following four security and financial integrity mechanisms were re-verified against the codebase and confirmed to be correctly implemented:

1. **Non-COD Job Double-Complete / Double-Release Protection**:
   * **Citation**: [`services/user-service/internal/store/mongodb.go`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/services/user-service/internal/store/mongodb.go#L549-L564) (lines 549–564)
   * **Mechanism**: In `ReleaseEscrowWithSplit`, `s.jobs.UpdateOne` uses a compare-and-swap filter on `_id`, `status: {$in: [JobStatusActive, JobStatusEscrowReconciliationRequired]}`, and `locked_escrow_amount: {$gte: amount}`. If a duplicate completion request arrives concurrently or sequentially, `resJob.MatchedCount` returns `0`, causing the operation to fail closed with `"escrow release failed: job %s is not active or has insufficient locked escrow"` without mutating wallet balances.

2. **Backend-Level KYC Enforcement**:
   * **Citations**:
     * [`services/auth-service/internal/handlers/auth.go`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/services/auth-service/internal/handlers/auth.go#L745) (line 745, `ToggleEmployee`: `owner.KYCStatus != models.KYCApproved`)
     * [`services/auth-service/internal/handlers/auth.go`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/services/auth-service/internal/handlers/auth.go#L872) (line 872, `SimulateEmployeeAction`: `owner.KYCStatus != models.KYCApproved`)
     * [`services/user-service/internal/handlers/handlers.go`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/services/user-service/internal/handlers/handlers.go#L311) (line 311, `CreateService`)
     * [`services/user-service/internal/handlers/handlers.go`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/services/user-service/internal/handlers/handlers.go#L395) (line 395, `UpdateService`)
     * [`services/user-service/internal/handlers/handlers.go`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/services/user-service/internal/handlers/handlers.go#L630) (line 630, `TrackJob`)
     * [`services/user-service/internal/handlers/handlers.go`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/services/user-service/internal/handlers/handlers.go#L1384) (line 1384, `WalletDeposit`)
   * **Mechanism**: KYC gating is enforced server-side in Go backend handlers, rejecting unapproved owner accounts with HTTP 403 Forbidden and logging `KYC_BLOCKED` security audit events. It does not rely solely on frontend UI controls.

3. **Tenant-Scope Authorization Enforcement on `CompleteJob` and `CancelJob`**:
   * **Citations**:
     * [`services/user-service/internal/handlers/handlers.go`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/services/user-service/internal/handlers/handlers.go#L850-L868) (lines 850–868, `CompleteJob`)
     * [`services/user-service/internal/handlers/handlers.go`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/services/user-service/internal/handlers/handlers.go#L2345-L2354) (lines 2345–2354, `CancelJob`)
   * **Mechanism**: Both handlers resolve the caller's JWT identity and verify that `resolvedRequester` matches either the job's `OwnerID`, `UserID` (customer, where permitted), or assigned `EmployeeID`. Violations trigger a `TENANT_SCOPE_BLOCKED` security event audit log and an HTTP 403 Forbidden response.

4. **IDOR Protection on `GetJob` Employee-Scoped Query Path**:
   * **Citations**: [`services/user-service/internal/handlers/handlers.go`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/services/user-service/internal/handlers/handlers.go#L1050-L1056) (lines 1050–1056)
   * **Mechanism**: When querying employee jobs via `GetJob` / `GET /users/jobs/get`, if a client supplies an explicit `employee_id` query parameter, the handler compares it against `resolvedRequester` (from verified JWT claims). If they mismatch, it logs `[IDOR DETECTED]` and returns HTTP 403 Forbidden.

---

## 5. Not Yet Reviewed / Follow-Up Needed

The following surfaces were explicitly **out of scope** for this initial review pass and require dedicated follow-up audit sessions:

1. **Full `auth-service` Implementation Review**: Comprehensive audit of password reset token lifetimes, 2FA OTP entropy and rate limits, session invalidation on credential changes, and KYB/KYE document handling.
2. **Rate-Limiting Edge Cases Across Microservices**: Audit of Redis failover modes, distributed rate-limit synchronization under extreme concurrency, and IP spoofing vectors across reverse-proxy headers (`X-Forwarded-For` vs gateway proxy striping).
3. **Chat and Notification Channel Authorization Scoping**: Exhaustive check of WebSocket channel subscription rules (`chat-service`) and SSE stream filtering (`notification-service`) under multi-tenant edge cases.
4. **Input Validation and Injection Surface**: Systematic audit of all HTTP request body decoders, query parameter parsers, MongoDB query document construction (preventing BSON injection), and log sanitization across all 5 microservices.
