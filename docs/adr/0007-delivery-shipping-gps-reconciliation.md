# ADR-0007: Delivery and Shipping GPS Trail Settlement Reconciliation

- **Status**: Proposed (Phase 0 is a hard prerequisite for Phase 1)
- **Date**: 2026-07-27
- **Related Commit SHA**: e0c3ab014b45c2eafffd70b33b2bffd7fb2fc270
- **Related audit finding**: Delivery/Shipping Coordinate-Pricing Fraud & Employee GPS Reconciliation

## Context

In the Quick Delivery platform, job pricing across all categories is calculated deterministically at booking time using client-submitted coordinates via `TrackJob` in `services/user-service/internal/handlers/handlers.go`:

$$P_{\text{system}} = \text{TenantBasePrice} + (\text{Distance} \times \text{TenantPricePerKM})$$

For non-COD bookings, `TrackJob` locks $P_{\text{system}}$ in the tenant owner's e-wallet (`LockedEscrowAmount`). At job completion (`CompleteJob`), escrow funds are released to the tenant owner.

However, relying on customer-submitted booking coordinates creates a structural vulnerability to coordinate-pricing fraud in **delivery** and **shipping** services:
1. A dishonest customer can deliberately submit inaccurate or manipulated coordinates during booking (e.g., setting the drop-off location close to the pickup point) to lock an artificially low $P_{\text{system}}$ escrow amount.
2. Conversely, client-side GPS coordinates from customer mobile devices cannot be trusted as an absolute ground truth, as they can be easily faked prior to physical movement using location-spoofing software or manual input.

### Codebase Verification of Existing Speed Check Gap

Before designing a settlement mechanism based on the employee's tracked GPS updates (`UpdateJobLocation`), we independently inspected `services/user-service/internal/handlers/handlers.go` lines 1766–1798:

```go
// Speed/plausibility check
prevLat := job.Location.Latitude
prevLon := job.Location.Longitude
if job.CurrentLocation != nil {
    prevLat = job.CurrentLocation.Latitude
    prevLon = job.CurrentLocation.Longitude
}

dist := haversineKm(req.Latitude, req.Longitude, prevLat, prevLon)
var lastTime time.Time
if exists {
    lastTime = lastUpdate
} else {
    lastTime = job.CreatedAt
}
timeDiff := now.Sub(lastTime)
hours := timeDiff.Hours()
if hours > 0 {
    speed := dist / hours
    if speed > MaxReasonableSpeedKmh { ... }
}
```

**Finding**: The existing speed check calculates velocity (`speed`) exclusively by measuring the distance `dist` between the *immediately-previous location point* (`job.CurrentLocation` or `job.Location`) and the incoming update (`req`), divided by elapsed time since the previous update (`now.Sub(lastTime)`). 

This is a **per-step check only**. It does **not** evaluate cumulative distance from job start divided by total elapsed time since job initiation (`now.Sub(job.CreatedAt)`). Consequently, a sequence of small, individually plausible coordinate jumps (e.g. 20 km jumps every 15 minutes = 80 km/h) can accumulate into an implausible total route distance over the job's lifespan without ever exceeding `MaxReasonableSpeedKmh = 150.0` km/h on any single step.

Because the employee's GPS trail is intended to serve as the harder-to-fake reference point for settlement reconciliation, this gap must be eliminated before GPS trail-based settlement logic can be safely introduced.

---

## Decision

We decided to implement a **Two-Phase GPS Reconciliation Model** for **Delivery and Shipping categories only**, anchoring final job settlement to the employee's verified GPS trail with a guaranteed payout floor for honest couriers.

### 1. Scope Confirmation (Category Boundaries)

* **Transport (`transport`)**: Explicitly **OUT OF SCOPE**. Passenger ride-hailing is self-verifying because the customer is physically present inside the vehicle with the driver, preventing unverified coordinate fraud. Furthermore, transport fare negotiation is governed separately by [ADR-0006](0006-negotiable-transport-pricing.md).
* **Delivery (`delivery`) & Shipping (`shipping`)**: **IN SCOPE**. The customer is not physically present during transit, creating a structural need for server-side settlement reconciliation.

---

### 2. Two-Phase Phasing Structure

#### Phase 0: Speed & Plausibility Check Hardening (Hard Prerequisite)

Before Phase 1 settlement logic is activated, `UpdateJobLocation` in `services/user-service/internal/handlers/handlers.go` must be hardened to perform **dual-layer velocity validation**:

1. **Per-Step Speed Check (Existing)**: Validates distance between consecutive updates against interval time to catch instantaneous teleportation jumps ($>150\text{ km/h}$).
2. **Cumulative Route Speed Check (New)**: Validates cumulative distance from job origin against total elapsed time since job start (`now.Sub(job.CreatedAt)`). If cumulative average speed exceeds `MaxReasonableSpeedKmh`, the update is rejected and logged as a security event.

Both checks will coexist: per-step catches sudden leaps, while cumulative check prevents slow-drip coordinate drift accumulation.

**In-Memory Throttle State Decision**:
`UpdateJobLocation` currently uses in-memory maps (`u.locationLastUpdate` and `u.locationInFlight`) protected by `u.locationThrottleMu`. For Phase 0, we decide to **inherit this pre-existing in-memory limitation** for single-instance deployments. Distributing location throttle state across multi-instance service replicas via Redis is explicitly flagged as future horizontal scaling infrastructure work (consistent with the phased Redis migration approach in [ADR-0005](0005-realtime-hub-horizontal-scaling.md)).

#### Phase 1: GPS Trail Settlement Reconciliation & Guaranteed-Floor Mechanism

Phase 1 alters final settlement math during job completion (`CompleteJob` in `services/user-service/internal/handlers/handlers.go`):

1. **Trigger Window**: Re-evaluation occurs strictly during `CompleteJob` execution (lines 644–702), prior to escrow release or COD fee deduction.
2. **"Actual Distance Traveled" Computation**:
   * **Decision**: Computed as the **cumulative sum of Haversine distances between consecutive validated GPS waypoints** along the employee's recorded route from start to finish ($\sum \text{haversine}(P_{i}, P_{i+1})$).
   * **Justification**: Straight-line (point-to-point) distance undercounts physical distance for non-direct road routes, detours, and urban navigation. Because Phase 0 guarantees that every recorded GPS waypoint is physically plausible and free of teleportation jumps, cumulative waypoint summation accurately reflects actual road distance traveled, providing a fairer compensation model for couriers.
3. **Guaranteed-Floor Mechanism & Payment Method Behavior**:
   * Recomputed Actual Amount: $A_{\text{actual}} = \text{TenantBasePrice} + (\text{ActualDistance} \times \text{TenantPricePerKM})$.
   * **COD Jobs**: COD jobs have no pre-locked escrow balance limit. If $A_{\text{actual}} > \text{LockedEscrowAmount}$, the courier receives $A_{\text{actual}}$ in full, deducted from the tenant owner's wallet/cash collection.
   * **Escrow (Non-COD) Jobs**: Per [ADR-0002](0002-escrow-wallet-system.md), non-COD escrow release is strictly capped at $\text{LockedEscrowAmount}$ to prevent drawing down funds allocated to other jobs' locked escrow balances. Because no automated second-charge or top-up mechanism exists, for non-COD escrow jobs, the guaranteed floor cannot pay out more than $\text{LockedEscrowAmount}$—it guarantees the courier receives exactly $\text{LockedEscrowAmount}$ (never less). If $A_{\text{actual}} > \text{LockedEscrowAmount}$, payout is capped at $\text{LockedEscrowAmount}$ and emits an `ESCROW_LIMIT_EXCEEDED` security log line, flagging the underpayment for potential operator manual compensation review.
   * **Worker Protection**: An honest employee is **never paid less than $\text{LockedEscrowAmount}$**, ensuring workers are never shortchanged below locked booking estimates by route recalculations.
4. **Under-Distance Suspicion & Manual Review Flag**:
   * If $\text{ActualDistance}$ is suspiciously shorter than the booked distance (e.g. $\text{ActualDistance} < 0.70 \times \text{BookedDistance}$), the system does **not** automatically penalize the courier or reduce payout automatically.
   * Instead, the job transitions to `models.JobStatusEscrowReconciliationRequired` (`escrow_reconciliation_required`), appending audit details to `ReconciliationNote` (e.g. `"tracked_distance_mismatch: actual 2.1km vs booked 10.5km"`).
   * This flags the transaction for manual operator review, stopping potential payout fraud without imposing automated wage deductions on workers.

---

### 3. Manual Review Flag Infrastructure

Rather than introducing a new job status or schema entity, Phase 1 standardizes on extending the existing `models.JobStatusEscrowReconciliationRequired` status and `UpdateJobReconciliation` storage helper in `user-service`. This reuses the established administrative review pattern built for stuck-escrow recovery (see [security-fixes.md](file:///mnt/windows_data/CS tools/Antigravity/SaaS prototype/docs/changelog/security-fixes.md#L463)).

---

### 4. Repeat-Offender Tracking (Customer Reputation Scope)

* **Decision**: Repeat-offender customer tracking and risk scoring are **explicitly deferred to a future ADR**.
* **Justification**: A search across the codebase confirms that ratings (`POST /users/jobs/rate`, `GET /users/ratings`) exist solely for post-job reviews, and no customer fraud-scoring, reputation history, or blacklist infrastructure currently exists. Deferring reputation tracking keeps ADR-0007 focused strictly on core GPS reconciliation.

---

## Consequences

### Positive
* **Fraud Mitigation**: Eliminates customer coordinate-pricing manipulation in delivery and shipping jobs.
* **Worker Fairness**: The guaranteed-floor mechanism ($\max$) ensures couriers are paid fairly for actual distance traveled and are never penalized below locked booking fees.
* **Dual-Layer Speed Validation**: Phase 0 closes the slow-drip speed spoofing gap across GPS updates.
* **Architectural Alignment**: Reuses established `JobStatusEscrowReconciliationRequired` review queues without schema fragmentation.

### Tradeoffs & Known Limitations
* **Operator Workload**: Jobs flagged for significant under-distance mismatches require human review in the admin queue.
* **Redis-Backed Throttle State**: Location tracking throttle state (`loc:inflight:`, `loc:lastupdate:`) is fully migrated to Redis, supporting multi-replica deployments without in-memory state leakage.

---

## Alternatives Considered

1. **IP Geolocation as Primary Verification Signal**:
   * *Rejected*: IP geolocation provides coarse city-level resolution, fails under mobile carrier CGNAT, and is easily bypassed using consumer VPNs.
2. **Frontend GPS Alone**:
   * *Rejected*: Mobile app GPS coordinates originate from untrusted client environments and can be spoofed using Android Developer Options or mock location apps.
3. **Pre-Movement Customer Location Proof**:
   * *Rejected*: Mathematically and structurally impossible to verify customer location prior to movement without a third-party physical witness on site.
