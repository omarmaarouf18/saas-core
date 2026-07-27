# Architecture Decision Records (ADRs)

This directory contains Architectural Decision Records (ADRs) for the Quick Delivery platform. (Note: The codebase is internally referred to as `saas-core`.) Every significant architectural, design, or security-boundary decision must be documented here in a numbered, markdown format (`NNNN-short-title.md`).

## ADR Process and Template

When adding a new ADR, use the following template:

```markdown
# ADR-NNNN: <Title>

- **Status**: Accepted | Proposed | Deprecated | Superseded
- **Date**: YYYY-MM-DD
- **Related Commit SHA**: <sha>
- **Related audit finding**: <finding or issue reference>

## Context
<What problem/vulnerability/tradeoff prompted this decision. Include exact file/handler references.>

## Decision
<What was decided and implemented, precisely.>

## Consequences
<Positive and negative tradeoffs, follow-up work, anything explicitly deferred.>

## Alternatives Considered
<Other options and why they were rejected.>
```

## Record Index

*   [ADR-0001: Owner-Authenticated Employee Provisioning](0001-owner-authenticated-employee-provisioning.md)
*   [ADR-0002: Per-Job Escrow Integrity and Location Validation](0002-per-job-escrow-integrity.md)
*   [ADR-0003: Employee Assignment Tenant Binding Check](0003-employee-assignment-tenant-binding-check.md)
*   [ADR-0004: Customer Booking Employee Assignment Ordering Correctness](0004-customer-booking-employee-assignment-order.md)
*   [ADR-0005: Realtime Hub Horizontal Scaling via Redis Pub/Sub](0005-realtime-hub-horizontal-scaling.md)
*   [ADR-0006: Negotiable Transport Pricing Model](0006-negotiable-transport-pricing.md)
*   [ADR-0007: Delivery and Shipping GPS Trail Settlement Reconciliation](0007-delivery-shipping-gps-reconciliation.md)
*   [ADR-0008: Live Employee Map Tracking Architecture & Provider Selection](0008-live-employee-map-tracking.md)


