# 0023. Modular Operations Console Expansion

Date: 2026-09-01

## Status

Accepted (Final Console Scope Closed — 5 Active Tabs)

## Context

In [ADR-0021](0021-kyc-kyb-kye-reviewer-console.md), the standalone reviewer console (`kyc-reviewer-console`) was intentionally scoped narrowly to KYC/KYB/KYE identity verification, explicitly deferring broader operational capabilities (e.g. ticket resolution, dispute management, subscription activations, ledger inspection) with the note: *"do NOT build a general Ops Console or add speculative modules... a future broadening is planned as a separate, later effort."*

In [ADR-0022](0022-account-suspension-and-reviewer-directory.md), this scope was extended to include an Account Directory, Search, and Account Suspension/Reactivation.

The product owner subsequently authorized expanding the console into a **Modular Operations Console** (`kyc-reviewer-console`, deployed at `kyc.logiclinkeg.tech`) to serve as the unified administrative interface for the platform.

### Scope Closure Decision (5 Tabs Final)

Following the delivery of Module 1.1 (Disputes & Reconciliation), the product owner finalized the operational console scope to exactly 5 core tabs:

1. **Pending Submissions (KYC/KYB/KYE)** — Identity verification and document review (ADR-0021).
2. **Accounts Directory** — Universal search, user directory, and account suspension/reactivation (ADR-0022).
3. **Disputes & Reconciliation** — Cross-tenant escrow mismatch queue, GPS distance audit, and dispute resolution overrides (ADR-0023 Module 1.1).
4. **Subscriptions** — Tenant subscription queue (`pending_payment`), manual tier activation upon offline payment/invoice, and subscription revocation with mandatory reasons (ADR-0023 Module A).
5. **Support Tickets** — Support and complaint ticket inbox across customer/courier issues, chat context inspection, and dispute resolution with mandatory notes (ADR-0023 Module B).

### Dropped Catalog Items & Rationale

All other exploratory items from the initial 6-service capability catalog are permanently closed from the console build plan:

- **Tenant Owner Payouts Queue**: *Decided: not building in console* — Tenant withdrawals will transition to an automated payment gateway integration (e.g., Paymob / bank API) rather than manual operator-driven console approval.
- **Global Financial Ledger & Wallet Oversight**: *Decided: not building in console* — Financial ledger and balance tracking are auditing concerns handled via direct database query and immutable transaction logs, not an interactive console screen.
- **Platform-Wide Audit Log Viewer**: *Decided: not building in console* — Reviewer security events and audit trails are streamed to CloudWatch / centralized logging pipelines (`handlerutil.ShipSecurityEvent`).
- **Cross-Entity Global Search**: *Decided: not building in console* — Search functionality is embedded directly within each functional module (Accounts search, Disputes filter, Subscriptions filter).
- **Notification Failure Logs & System Alerts**: *Decided: not building in console* — Notification health and retries are managed by infra monitoring alerts.
- **Gateway Health & Circuit Breaker Stats**: *Decided: not building in console* — Monitored via Prometheus / Grafana infrastructure metrics.

---

## Permanent Security & Operational Boundaries

The following core boundaries are permanent invariants for all console modules:

1. **No Self-Service Admin/Reviewer Provisioning**:
   - Console accounts can **never** be created, registered, or invited from the web console UI or any public/authenticated API endpoint.
   - Reviewer credentials are created exclusively through manual server-side CLI execution (`cmd/onboard-reviewer` over SSH).
   - Reviewer credentials are cryptographically hashed at rest (SHA-256) in MongoDB (`reviewers` collection).
2. **Uniform Operator Permission Model**:
   - In accordance with product-owner direction, all onboarded console operators share the same permission level (no complex RBAC or reviewer/admin role fragmentation).
   - Any operator possessing a valid `X-Reviewer-Token` has access to all active console modules.
3. **Mandatory Reasons for Destructive & Financial Override Actions**:
   - Every state transition that rejects, suspends, cancels, refunds, revokes, or denies funds/access requires an explicit, trimmed reason (1–1000 characters).
4. **Compare-And-Swap (CAS) Transitions & Audit Logging**:
   - All status transitions must execute atomically via CAS queries (e.g., transitioning only from `pending_payment` or `escrow_reconciliation_required`).
   - Every state mutation writes an immutable entry to the audit log and emits structured security events (`handlerutil.ShipSecurityEvent`).
5. **Single Integrated Deployment**:
   - The console remains a single web application with modular tabs rather than independent micro-frontends or separate admin portals.
6. **Two-Token Proxy Security Architecture**:
   - The browser session holds only the operator's `X-Reviewer-Token` in `sessionStorage` (cleared on tab close).
   - The console backend proxy injects `X-Internal-Token` server-side across internal container networks.
   - The edge `api-gateway` strips `X-Internal-Token` from all inbound client requests, preventing external bypass.
7. **Zero Consumer Endpoint Modification**:
   - New admin operations are exposed strictly through new administrative endpoints (`/admin/*`), never altering the behavior, contract, or permissions of existing consumer endpoints.

