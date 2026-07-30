# ADR-0006: Negotiable Transport Pricing Model

- **Status**: Accepted
- **Date**: 2026-07-26
- **Related Commit SHA**: TBD
- **Related audit finding**: Real-time Ride Pricing & Flexible Fare Escalation

## Context

Currently, as documented in [ADR-0002](0002-per-job-escrow-integrity.md) and implemented in `services/user-service/internal/handlers/handlers.go` (`TrackJob`), job pricing across all categories (`delivery`, `transport`, `shipping`) is calculated deterministically at booking time using a fixed formula:

$$P_{\text{system}} = \text{TenantBasePrice} + (\text{Distance} \times \text{TenantPricePerKM})$$

For non-COD bookings, `TrackJob` immediately locks the computed $P_{\text{system}}$ in the tenant owner's wallet (`LockedEscrowAmount`). At completion (`CompleteJob`) or cancellation (`CancelJob`), escrow funds are released or refunded based on $P_{\text{system}}$, capped strictly at `LockedEscrowAmount`.

While this fixed-pricing model works well for standardized logistics (`delivery` and `shipping`), passenger ride-hailing (`transport`) requires price flexibility to account for peak demand, premium vehicle types, vehicle amenities (e.g. air conditioning, extra luggage space, child seats), and real-time market negotiation. 

To increase platform liquidity for passenger rides while preserving strict escrow security boundaries, we are introducing a **Negotiable Transport Pricing Model** specifically for the Transport/Rides (`transport`) category.

---

## Decision

We decided to implement negotiable pricing for the **Transport/Rides category only**, while preserving existing fixed pricing and initial-booking escrow flows for Delivery and Shipping.

### 1. Fixed Product Constraints (Non-Negotiable)

1. **Category Boundary**: Negotiable pricing applies exclusively to jobs in the `transport` category. `delivery` and `shipping` categories remain 100% unchanged (fixed $P_{\text{system}}$ computed at booking time, escrow pre-locked at `TrackJob` time).
2. **Formula Extension**: The system computes a baseline suggested price $P_{\text{system}}$ extending the base formula with vehicle-type and amenity multipliers:
   $$P_{\text{system}} = (\text{TenantBasePrice} + (\text{Distance} \times \text{TenantPricePerKM})) \times \text{VehicleTypeMultiplier} \times \prod \text{AmenityMultipliers}$$
3. **Single-Shot Take-It-Or-Leave-It Proposal**: Either party (customer or employee — whichever acts first) may propose exactly ONE adjusted price within the strict range $[0.5 \times P_{\text{system}}, 1.5 \times P_{\text{system}}]$. The counterparty gets exactly one decision: **Accept** or **Decline**. No counter-proposals are permitted. Any second proposal attempt on the same job must be rejected by the server with HTTP 400 (`proposal_already_submitted`).
4. **5-Minute Auto-Cancellation**: If a proposal in `awaiting_price_response` state is not Accepted or Declined within 5 minutes (`PriceProposalExpiresAt`), it automatically expires: the job transitions to `JobStatusCancelled` with `CancellationReason = "price_proposal_expired"`, and the pre-selected employee is released.
5. **Deferred Escrow Locking for Rides**: For non-COD `transport` jobs, wallet/card escrow locking does **not** occur at initial `TrackJob` booking. Instead, escrow locking occurs only after a final `AgreedPrice` is established via acceptance. Once locked, the escrow allocation reuses the exact per-job isolation, `LockedEscrowAmount` persistence, and atomic deduction guarantees from [ADR-0002](0002-per-job-escrow-integrity.md).
6. **No Cooldown Required**: Because single-shot negotiation permits only one proposal per match, abusive counter-proposal loops are structurally impossible, eliminating the need for complex decline cooldown mechanisms.

---

### 2. Detailed Technical Decisions & Justifications

#### Q1: Who can initiate the first price proposal, and when?
- **Decision**: Either party (customer or employee — whichever acts first) may initiate a price proposal.
- **Justification**: The customer may include a target custom price proposal during job creation (`POST /users/jobs/track`), OR leave it empty to use the system-computed price $P_{\text{system}}$. Once an assigned employee reviews the pre-selected job, if no customer proposal is active, the employee may propose an adjusted price upon reviewing job details. Allowing either party to propose first aligns with real-world ride-hailing dynamics (e.g. InDrive/Uber bidding), permitting budget-conscious customers to offer a fare up front while giving drivers flexibility to adjust fares based on real-time traffic or road conditions.

#### Q2: What happens to the job if a proposal is declined?
- **Decision**: Declining a price proposal ends that job session immediately — it transitions to terminal `JobStatusCancelled` with `CancellationReason = "price_disagreement"`. The pre-selected employee is released, and no automatic reassignment occurs. To request service again, the customer must submit a new booking request.
- **Justification**: This decision is supported by two fundamental considerations:
  1. *Architecture Scope*: The existing platform architecture assigns a specific employee directly at booking time via `EmployeeID` in `TrackJob`; no dynamic driver broadcast or matching pool exists in the codebase today, making employee re-matching out of scope for this feature v1.
  2. *Product Semantics for Rides*: Unlike delivery or shipping (where the courier fulfilling the delivery is interchangeable and does not alter the underlying product), a passenger transport proposal is anchored directly to that specific employee's vehicle type and amenities (e.g. vehicle size, comfort level, AC). Silently re-assigning a different driver or vehicle for the same negotiated price range would violate the customer's explicit choice of vehicle class and amenities.

#### Q3: When does the 5-minute clock start?
- **Decision**: We enforce **a single 5-minute timer**: the **Negotiation Response Timer** (`PriceProposalExpiresAt`), which starts immediately when a price proposal enters the `awaiting_price_response` state.
- **Justification**: Because the employee is pre-selected at booking time (`EmployeeID` set in `TrackJob`), there is no driver matching or broadcast phase to measure. A single 5-minute timer cleanly governs the counterparty decision window.

#### Q4: Vehicle type & amenities data model and administrative governance
- **Decision**: Vehicle types and amenity multipliers are configured at the **Tenant Owner level** (`tenant_vehicle_pricing` and `tenant_amenities` tables), editable **strictly by Tenant Owners (`RoleOwner`)**. Employees select their registered vehicle type and active amenities from their tenant's approved catalog during vehicle registration or shift check-in.
- **Justification**: Restricting configuration to Tenant Owners prevents individual drivers from arbitrarily inflating base pricing factors, ensures uniform fleet pricing standards, and preserves tenant financial governance over base tariffs.

#### Q5: Cash on Delivery (COD) payment handling for Rides
- **Decision**: Price negotiation operates **identically for COD payments and non-COD payments**. For COD rides, no pre-lock occurs in the wallet; instead, the finalized `AgreedPrice` is collected in cash by the employee upon job completion.
- **Justification**: Decoupling price negotiation from the underlying payment collection mechanism ensures drivers and riders enjoy consistent fare negotiation capabilities regardless of whether the ride is settled via cash or wallet escrow.

---

## Confirmed Design Decisions

The following 5 design decisions are finalized for v1 implementation:

1. **Initiation**: Either party (customer at `TrackJob` booking, or pre-selected employee upon job review) can propose the first fare.
2. **Decline Handling**: Declining a proposal immediately cancels the job (`JobStatusCancelled`, reason `"price_disagreement"`). The customer must create a new booking request if they wish to rebook.
3. **Timer Management**: A single 5-minute timer (`PriceProposalExpiresAt`) governs the proposal decision window in `awaiting_price_response`.
4. **Vehicle/Amenity Governance**: Multipliers are configured strictly by Tenant Owners (`RoleOwner`). Employees select approved vehicle/amenity options from their tenant's catalog.
5. **COD Compatibility**: Negotiable pricing applies identically to COD rides, with the finalized `AgreedPrice` collected in cash at ride completion.

---

## Consequences

- **Positive**:
  - Provides flexible, market-responsive pricing for passenger rides (`transport`), increasing driver acceptance rates and rider fulfillment.
  - Preserves 100% of existing fixed-pricing and initial-booking escrow guarantees for `delivery` and `shipping` categories.
  - Maintains strict per-job escrow isolation and atomic wallet accounting ([ADR-0002](0002-per-job-escrow-integrity.md)) for `transport` rides by executing wallet locks immediately after `AgreedPrice` confirmation.
- **Resource Footprint**: Minimal overhead; adds state transition (`awaiting_price_response`) and background timer cleanup for expired proposals.
- **Security & Integrity**: Bounded proposals $[0.5 \times P_{\text{system}}, 1.5 \times P_{\text{system}}]$ and single-shot enforcement prevent price manipulation, runaway fare inflation, and counter-bidding spam.

---

## Alternatives Considered

- **Multi-Round Counter-Proposals**: Allowing iterative counter-bidding (customer $\leftrightarrow$ employee) was considered but rejected to avoid infinite negotiation loops, high latency, and client UI complexity.
- **Initial Booking Escrow Pre-Lock for Rides**: Pre-locking $P_{\text{system}}$ at `TrackJob` time for rides and adjusting escrow later was considered but rejected because fare negotiations frequently alter the final price, which would cause unnecessary wallet lock/release churn. Locking escrow upon reaching `AgreedPrice` provides a cleaner, atomic financial lifecycle.
