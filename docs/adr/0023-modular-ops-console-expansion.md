# 0023. Modular Operations Console Expansion

Date: 2026-09-01

## Status

Proposed (Draft for Product Owner Build-Order Confirmation)

## Context

In [ADR-0021](0021-kyc-kyb-kye-reviewer-console.md), the standalone reviewer console (`kyc-reviewer-console`) was intentionally scoped narrowly to KYC/KYB/KYE identity verification, explicitly deferring broader operational capabilities (e.g. ticket resolution, dispute management, subscription activations, ledger inspection) with the note: *"do NOT build a general Ops Console or add speculative modules... a future broadening is planned as a separate, later effort."*

In [ADR-0022](0022-account-suspension-and-reviewer-directory.md), this scope was extended to include an Account Directory, Search, and Account Suspension/Reactivation.

The product owner has now formally approved expanding the console from a dedicated identity review tool into a **Modular Operations Console** (`kyc-reviewer-console`, deployed at `kyc.logiclinkeg.tech`) to serve as the unified administrative, financial oversight, and customer operations interface for the Quick Delivery SaaS platform.

This record documents the scope expansion, restates non-negotiable security boundaries, provides the audited administrative capability catalog, and establishes the tiered implementation plan.

---

## Permanent Security & Operational Boundaries

The following core boundaries are permanent invariants for all current and future console modules:

1. **No Self-Service Admin/Reviewer Provisioning**:
   - Console accounts can **never** be created, registered, or invited from the web console UI or any public/authenticated API endpoint.
   - Reviewer credentials are created exclusively through manual server-side CLI execution (`cmd/onboard-reviewer` over SSH).
   - Reviewer credentials are cryptographically hashed at rest (SHA-256) in MongoDB (`reviewers` collection).
2. **Uniform Operator Permission Model**:
   - In accordance with product-owner direction, all onboarded console operators share the same permission level (no complex RBAC or reviewer/admin role fragmentation).
   - Any operator possessing a valid `X-Reviewer-Token` has access to all active console modules.
3. **Mandatory Reasons for Destructive & Financial Override Actions**:
   - Every state transition that rejects, suspends, cancels, refunds, or denies funds/access requires an explicit, trimmed reason (1–1000 characters).
4. **Compare-And-Swap (CAS) Transitions & Audit Logging**:
   - All status transitions must execute atomically via CAS queries (e.g., transitioning only from `requested` or `escrow_reconciliation_required`).
   - Every state mutation writes an immutable entry to the `audit_log` and emits structured security events (`handlerutil.ShipSecurityEvent`).
5. **Single Integrated Deployment**:
   - The console remains a single web application with modular tabs rather than independent micro-frontends or separate admin portals.
6. **Two-Token Proxy Security Architecture**:
   - The browser session holds only the operator's `X-Reviewer-Token` in `sessionStorage` (cleared on tab close).
   - The console backend proxy injects `X-Internal-Token` server-side across internal container networks.
   - The edge `api-gateway` strips `X-Internal-Token` from all inbound client requests, preventing external bypass.

---

## Administrative Capability Catalog & Priority Tiering

A systematic audit across all 6 microservices identified administrative workflows that currently require direct database/SSH access or lack a console interface:

```
+---------------------------------------------------------------------------------------------------+
| Tier 1: Financial Correctness & Escrow Safety (Build First)                                       |
|---------------------------------------------------------------------------------------------------|
| 1. Escrow Reconciliation & Dispute Oversight (user-service)                                       |
|    - Global queue of all jobs flagged with escrow_reconciliation_required                        |
|    - GPS waypoint distance discrepancy inspection                                                 |
|    - Reviewer resolution overrides: Release to Courier vs Refund to Customer                      |
|                                                                                                   |
| 2. Tenant Owner Payouts & Cash Outflow (user-service)                                             |
|    - Global queue of withdrawal requests (status: requested) across all tenant owners            |
|    - Reviewer action to approve & mark paid with transfer reference                               |
|    - Reviewer action to reject with mandatory reason and atomic fund restoration to wallet        |
|                                                                                                   |
| 3. Global Financial Ledger & Wallet Oversight (user-service)                                      |
|    - Read-only cross-tenant transaction ledger inspection and search                             |
|    - Tenant wallet balance oversight, locked escrow audit, and COD settlement logs                |
+---------------------------------------------------------------------------------------------------+
| Tier 2: Operational Visibility & Account Governance                                               |
|---------------------------------------------------------------------------------------------------|
| 4. Platform-Wide Audit Log Viewer (auth-service)                                                  |
|    - Searchable audit trail of all reviewer/admin actions (KYC, suspensions, payouts, disputes)  |
|                                                                                                   |
| 5. Cross-Entity Global Search (Cross-cutting)                                                     |
|    - Universal ID lookup across Users, Jobs, Payouts, Ledgers, and Wallets                        |
|                                                                                                   |
| 6. Tenant Subscription Plan Management (user-service)                                             |
|    - Reviewer queue for pending_payment paid subscriptions                                        |
|    - Manual activation of paid tier upon offline/invoice confirmation and tier revoking          |
+---------------------------------------------------------------------------------------------------+
| Tier 3: Support Ticketing & Platform Health                                                       |
|---------------------------------------------------------------------------------------------------|
| 7. Support & Complaint Ticketing (chat-service)                                                   |
|    - Customer and courier complaint ticket queue with chat context and resolution controls        |
|                                                                                                   |
| 8. Notification Delivery Failure Logs & System Alerts (notification-service)                      |
|    - View failed notification dispatches and broadcast emergency announcements                    |
|                                                                                                   |
| 9. Gateway Health & Version Gate Visibility (api-gateway)                                         |
|    - Circuit breaker statistics and mobile client minimum version gate configuration              |
+---------------------------------------------------------------------------------------------------+
```

---

## Implementation Strategy

Each tier will be implemented in sequential, self-contained passes:

1. **Backend Endpoints & CAS Store Methods**: Expose internal endpoints with `X-Internal-Token` and `X-Reviewer-Token` validation, atomic CAS transitions, and audit logs.
2. **Reviewer Console Proxy**: Add pass-through proxy routes with local payload validation.
3. **Reviewer Console UI Module**: Add dedicated navigation tabs, toolbars, tables, badges, and action dialogs.
4. **Verification Gate**: 100% test coverage (Go unit/integration, contract tests, security scan, and documentation freshness).
5. **Safety Gate**: Feature branch verification with no production deployment to `main` without explicit product-owner sign-off.
