# QA Strategy & Regression Coverage Matrix

## 1. Executive Summary

This document serves as the persistent single source of truth for end-to-end quality assurance, release gates, and regression protection across the Quick Delivery SaaS platform. It documents verified system invariants, end-to-end Critical User Journeys (CUJs) executed against live staging infrastructure, and the gap analysis informing subsequent QA phases.

---

## 2. Currently Protected Workflows (Phase 0 Baseline)

The following journeys are actively executed and protected by the automated CI Release Gate (`.github/workflows/release-gate-e2e.yml`) and local staging test suite (`tests/e2e`):

### CUJ-A: Cascade Dispatch, Offer Isolation, Pricing Lock & Live GPS Tracking
* **Test Implementation**: `tests/e2e/cuj_a_test.go` (`TestCUJ_A_CascadeOfferAcceptAndLiveTracking`)
* **Infrastructure Path**: Client -> Caddy (`:8088`) -> API Gateway (`:8080`) -> `user-service` / `chat-service` / `notification-service` -> MongoDB & Redis.
* **Verified Invariants**:
  1. **Cascade Dispatch Initial State**: Customer booking creates a job in `pending_dispatch` and directs an offer strictly to the nearest available courier based on spatial distance.
  2. **Price Deferral**: Job distance (`booked_distance`) and escrow (`locked_escrow_amount`) remain zero/deferred until courier acceptance.
  3. **Notification Isolation (N-01 & N-02)**:
     - **N-01**: Only the offered courier receives the real-time `job_offer` event over live SSE. Un-offered couriers receive 0 events.
     - **N-02**: The un-offered courier's historical notifications query (`GET /api/v1/notifications`) contains zero leaked job details.
  4. **Pricing Lock on Acceptance**: When the courier accepts the offer, distance is calculated from the courier's actual coordinates and the escrow amount is atomically locked from the tenant's wallet.
  5. **Navigation Resilience (F-01)**: Courier app navigation (querying profile, jobs list, and notifications) does not disrupt active job tracking or state.
  6. **WebSocket Live Map Updates**: Full-duplex WebSocket stream through Caddy and API Gateway delivers live coordinate updates to customer subscribers within the 3-second throttle interval.

### CUJ-B: KYC Reviewer Console, Mandatory Reason & Live Proxy SSE Delivery
* **Test Implementation**: `tests/e2e/cuj_b_test.go` (`TestCUJ_B_KYCSubmissionReviewAndSSEOutcomeDelivery`)
* **Infrastructure Path**: Client / Reviewer -> Caddy (`:8088` & `:8091`) -> API Gateway & KYC Reviewer Console -> `auth-service` & `notification-service`.
* **Verified Invariants**:
  1. **Console Queue Discovery**: Pending KYC verification submissions appear immediately in the Reviewer Console queue (`GET /api/queue`).
  2. **Mandatory Rejection Reason Enforcement ([ADR-0021](docs/adr/ADR-0021-reviewer-rejection-reason.md))**:
     - Submitting a rejection without a reason is rejected with `400 Bad Request`.
     - Submitting a whitespace-only rejection reason (`"   "`) is rejected with `400 Bad Request`.
     - Submitting a valid reason returns `200 OK` and persists the rejection reason.
  3. **Real SSE Delivery via Edge Proxy**:
     - Customer connects to real SSE stream through Caddy and API Gateway.
     - Rejection and approval events (`kyc_rejected`, `kyc_approved`) are flushed immediately across Caddy and API Gateway without reverse-proxy buffering delay or dropped events.
  4. **WebSocket Protocol Upgrade Integrity**: Gateway resilience transport preserves `io.ReadWriteCloser` for `101 Switching Protocols`, preventing bad handshake errors.

---

## 3. Coverage Gaps & Phase 1 Roadmap

The following areas are identified as gaps and form the baseline scope for Phase 1:

| Domain | Current State | Phase 1 Objective | Risk Level |
| :--- | :--- | :--- | :--- |
| **Contract Testing** | Integration tests rely on live DBs | Add Pact/consumer-driven contract tests across service boundaries | Medium |
| **Reconciliation Journey** | Handled in unit tests | End-to-end journey for Cash-on-Delivery (COD) reconciliation (CUJ-C) | High |
| **Dispute Escalation** | Unit tested in isolation | End-to-end journey for customer dispute and refund escalation (CUJ-D) | High |
| **Super Admin KYB** | Reviewer Console covered | End-to-end multi-tier approval workflow for enterprise tenants (CUJ-E) | Medium |
| **FCM Push Notifications** | Mock dispatcher in staging | Real device token dispatch and background wakeups | Medium |
| **Chaos & Node Failure** | Zero chaos testing | Automated kill-test of Redis/Mongo nodes during active cascades | High |

---

## 4. Living Reference Links

- **Staging Runbook & Topology**: [docs/STAGING.md](docs/STAGING.md)
- **Reviewer Console Rejection Reason**: [docs/adr/ADR-0021-reviewer-rejection-reason.md](docs/adr/ADR-0021-reviewer-rejection-reason.md)
- **Reverse-Proxy SSE Buffering Resolution**: [docs/changelog/bug-fixes.md](docs/changelog/bug-fixes.md)
- **Dispatch Notification Isolation (N-01/N-02)**: [docs/changelog/security-fixes.md](docs/changelog/security-fixes.md)
- **Offered Courier Details Access (F-01)**: [docs/changelog/security-fixes.md](docs/changelog/security-fixes.md)
- **Production Deployment Standards**: [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)
