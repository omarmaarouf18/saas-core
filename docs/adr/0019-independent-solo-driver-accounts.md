# ADR-0019: Independent ("Solo") Driver Accounts

- **Status**: Proposed
- **Date**: 2026-08-25
- **Related**: ADR-0001 (Owner-Authenticated Employee Provisioning), ADR-0003 (Employee Assignment Tenant Binding), ADR-0004 (Customer Booking Employee Pre-Assignment), ADR-0017 (Zero-Commission Subscription-Only Revenue Model)

## Context

Today every driver ("employee") is provisioned by a tenant **owner** through an authenticated owner-only flow. `POST /auth/signup` with `role=employee` hard-rejects requests without `owner_id` (`services/auth-service/internal/handlers/auth.go:210`, audit event `UNAUTHORIZED_EMPLOYEE_PROVISION_BLOCKED`). Employees are tenant-bound via `User.OwnerID` (KYE binding, ADR-0003), and every booking verifies the assigned employee belongs to the job's owner's tenant (`jobs_handlers.go:146-166`). Services always belong to a tenant (`Service.TenantID` = owner ID), and owner-scoped surfaces (wallet, payouts, service config, reconciliation queue, fleet map) are keyed to that owner identity.

This model excludes **self-employed individual drivers** who have no fleet owner: they cannot register, cannot publish a service in the directory, and therefore cannot receive bookings — even though the platform's zero-commission COD-only reality (ADR-0017) means they need almost none of the tenant financial infrastructure to operate.

## Decision

Introduce a first-class **independent driver account** as a variant of the existing employee role — NOT a new role, and NOT a synthetic owner persona.

1. **Signup**: `POST /auth/signup` accepts `role=employee` with `owner_id` absent **only when** a new explicit flag `independent=true` is supplied. The existing block stays intact for plain missing-`owner_id` requests (no silent behavior change for current clients). New User field: `Independent bool` + `AccountMode string` (`"tenant" | "independent"`, default `"tenant"`).
2. **Tenant binding relaxation is scoped, not global**: independent drivers keep `OwnerID == ""`. All existing tenant-binding checks gain one branch: *if target resource OwnerID == actor's own user ID and actor is an independent employee → allow*. This applies to:
   - Booking pre-assignment validation (`jobs_handlers.go` TrackJob): `Job.OwnerID` is set to the **independent driver's own user ID** when their service is booked.
   - Job execution gates (`CompleteJob`, `CancelJob`, `UpdateJobLocation`, chat channel `job:<id>`, location broadcast authorization).
3. **Services**: independent drivers create their own single service record via a new self-service path (same `CreateService` handler; `tenant_id` resolved from their own JWT instead of an owner token). `TenantPricePerKM`/`TenantBasePrice` become self-set. Directory display requires KYE `approved`.
4. **KYE**: independent drivers pass the existing KYE document review flow (`/auth/documents` upload + `/auth/kyb-kye/review` by Support Agent Console per ADR-0013). Recommended stricter default: `selfie` + `id_front` + `id_back` mandatory before the service becomes publicly listable (business proof not applicable).
5. **Money (Phase 1)**: COD-only, pure log entry per ADR-0017 — no wallet changes required. Escrow/payout parity for independents is explicitly deferred (see Consequences).
6. **Frontend**: signup role card gains "Drive independently" option; independent employees get the existing employee shell plus a lightweight "My Service" config surface reusing `OwnerConfigurationScreen` patterns; owner-only screens stay hidden.

## Alternatives Considered

- **Synthetic linked owner persona (1:1 hidden owner account)**: maximal reuse of owner paths (wallet, payouts, reconciliation work unchanged) but introduces dual-account auth confusion, two JWT identities for one human, and leaks tenant semantics into what should be a personal account. Rejected for Phase 1 complexity.
- **New third role `"solo_driver"`**: touches every `resolveTokenWithRole(...)` call site (~18+) and every RBAC test; high blast radius for no behavioral gain over the flagged-employee variant. Rejected.

## Consequences

- ADR-0001's provisioning invariant is amended, not removed: owners still provision tenant employees exactly as before; only the new explicit independent path bypasses it, gated by its own flag + KYE approval.
- ~6 authorization sites need the scoped self-ownership branch; each ships with a dedicated unit test (positive + cross-IDOR negative).
- Independent drivers initially have **no wallet/payout surface** — acceptable while payments remain COD log-only (ADR-0017); must be revisited if electronic payments ship.
- Fleet map (`fleet:<owner_id>` channel) works unchanged for independents since `Job.OwnerID ==` driver ID; customer map view needs no change.

## Phased Roadmap

| Phase | Scope | Verification gate |
|---|---|---|
| B0 | Model fields (`Independent`, `AccountMode`) + migration-free index review | unit tests on defaults |
| B1 | Signup path + auth tests (flag required, tenant path unchanged) | `go test ./auth-service` |
| B2 | Self-service CreateService (KYE-gated) | unit tests |
| B3 | Booking/execution authorization branches + IDOR negatives | unit + concurrency tests |
| F1 | Flutter: signup option, employee-shell service config, booking display | widget tests |
| F2 | Directory badge for independent services | widget tests |

*Open questions for the project owner*: max services per independent driver (proposal: 1); whether independents may also be hired by tenants later (proposal: out of scope).
