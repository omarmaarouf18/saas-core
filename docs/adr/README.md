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
*   [ADR-0009: Atomic Compare-and-Swap Filter Guards for Negotiable Transport Pricing](0009-atomic-compare-and-swap-transport-pricing.md)
*   [ADR-0010: Separate Repositories vs. Branches for Deployment Artifacts](0010-separate-repos-for-deployment-artifacts.md)
*   [ADR-0011: Containerized Caddy Reverse Proxy in Docker Compose Stack](0011-containerized-caddy-in-compose-stack.md)
*   [ADR-0012: Single Source of Truth for Production .env (Self-Hosted Runner Workspace vs. Persistent Backup)](0012-single-source-of-truth-for-production-env.md)
*   [ADR-0013: Support Agent Console as a Separate Client Application](0013-support-agent-console-as-separate-client-application.md)
*   [ADR-0014: Unified Account Settings and Role Home Redesign](0014-unified-account-settings-and-role-home-redesign.md)
*   [ADR-0015: Strict CD Pre-Flight Validation (Pre-Flight Env Check, Health-Gated Rollback)](0015-strict-cd-preflight-validation.md)
*   [ADR-0016: Tiered Rate Limits for UX over Uniform Security Floor](0016-tiered-rate-limits-for-ux-over-uniform-security-floor.md)
*   [ADR-0017: Zero-Commission Subscription-Only Revenue Model](0017-zero-commission-subscription-only-revenue-model.md)
*   [ADR-0018: Client Application Semantic Versioning & Version-Gating Middleware](0018-client-app-semantic-versioning-and-enforcement-gate.md)




