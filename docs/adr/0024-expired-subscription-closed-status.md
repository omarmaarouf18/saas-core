# ADR-0024: Expired-Subscription Closed Status for Marketplace Listing and Booking

- **Status**: Accepted
- **Date**: 2026-09-23
- **Related**: ADR-0017 (Zero-Commission Subscription-Only Revenue Model), verification report 2026-09-23 (public company profile card / closed-status / closed-booking-log gaps)
- **Implementation**: definition + listing filter + booking gate implemented and tested in the user-service step-3 commit; `BOOKING_ATTEMPT_CLOSED_BUSINESS` audit event and this status flip in the step-4 commit (see `docs/changelog/new-features.md` and `docs/changelog/security-fixes.md`).

## Context

The platform's sole revenue source is the SaaS subscription fee (ADR-0017), enforced at request time by `requireTier` (`services/user-service/internal/handlers/handlers.go`). That check has a hole: it compares only `sub.Tier != models.PlanPaid` and never compares `sub.ExpiresAt` against the current time — anywhere in non-test code. A tenant whose paid subscription expired last month passes every paid gate exactly like a current subscriber.

Two customer-facing paths consequently serve businesses that cannot legitimately operate:

1. `GET /users/services` (`ListServices`, `services/user-service/internal/handlers/services_handlers.go`) is fully public and unauthenticated. Its Mongo filter is either empty or `$nearSphere`-only; no subscription, tenant-status, or expiry cross-reference exists. Expired tenants' services are listed and bookable-looking.
2. `POST /users/jobs/track` (`TrackJob`, `services/user-service/internal/handlers/jobs_handlers.go`) performs no subscription check at all (the only `requireTier` call in that file guards `UpdateJobLocation`, i.e. live GPS on an already-created job). A customer can book, fund escrow for, and dispatch couriers to a business whose subscription lapsed.

There is also no audit signal for such attempts: no `CLOSED`-family `ShipSecurityEvent` exists, so "customer tried to book an expired business" is invisible to analytics and security review.

## Decision

Define one predicate, enforce it lazily at request time in exactly two places. No sweeper, no cron (the repo runs no scheduled jobs today), no second divergent definition.

### 1. Definition of "closed"

A tenant is **closed** when its subscription is missing, unpaid, or expired, computed from stored data at request time:

```go
// Closed == sub == nil, sub.Tier != PlanPaid,
// or (non-zero sub.ExpiresAt before now).
```

This is implemented once as a nil-safe helper on `models.Subscription` (e.g. `IsClosed(now time.Time) bool`), and `requireTier`'s existing `PlanPaid` branch delegates to it instead of comparing tiers inline. Zero `ExpiresAt` keeps its documented meaning ("zero = no expiry", `models.go`) and stays open while the tier is paid — preserving backward compatibility for paid rows written before expiry tracking. Concretely, the only behavior change inside `requireTier` is: `paid tier + past ExpiresAt` now returns `ErrUpgradeRequired`. `nil sub`, `free`, `pending_payment`, and `cancelled` tiers reject exactly as before.

### 2. Where enforced

a. **`GET /users/services` (ListServices) — filter, don't flag.** Closed tenants' services must not appear in the public listing at all. Implementation: a store-layer method (e.g. `ListServicesOpenOnly`) that reuses the existing `ListServices` geo query unchanged and drops services whose tenant is closed (per-tenant subscription lookup, de-duplicated per page). The existing unfiltered `ListServices` store method is kept for owner/debug/test use. Filtering is post-query, so a page can come back short when closed tenants occupy slots — accepted and documented (closed tenants are expected to be rare; pushing the tenant set into the Mongo query would require an unbounded subscriptions scan per listing request, which is worse).

b. **`POST /users/jobs/track` (TrackJob) — reject with 402 before escrow/KYC work begins.** The gate runs through the same `requireTier` predicate at the earliest point the tenant is known in each path: after owner-JWT resolution when an owner token is supplied, and after owner derivation from the service record in the lookup path — in both cases before employee verification, payment validation, KYC lookup, dispatch, and escrow locking. The rejection is HTTP 402 (matching `enforcePaidTier`'s existing status code) with customer-safe copy that leaks no subscription-tier language, e.g. error `service_unavailable`, message "This business is temporarily closed and cannot accept new bookings right now." It deliberately does NOT reuse `enforcePaidTier`'s `upgrade_required` copy, which addresses the tenant owner, not the customer.

### 3. Owner-facing scope boundary (deliberate, not an oversight)

No separate owner-scoped service-list endpoint exists: `OwnerProvider.fetchServices()` calls the same public `GET /users/services`, and `OwnerConfigurationScreen` matches its tenant client-side. Closed filtering therefore also applies to that screen — a closed owner's form loads unpopulated. This is accepted because a closed owner cannot write services anyway (`CreateService`/`UpdateService` are already `enforcePaidTier`-gated and now additionally expiry-gated, returning the existing 402), and the subscription renewal path (`GET/POST /users/subscription`, `SubscriptionScreen`) is untouched, so the road back to open is: renew → services reappear → configure again. No owner bypass query parameter is introduced (it would be a new endpoint contract plus an owner-match authorization check — out of scope).

### 4. Audit logging (implemented as the follow-up step, same predicate)

`TrackJob`'s closed rejection ships a dedicated audit event (e.g. `BOOKING_ATTEMPT_CLOSED_BUSINESS`) via the existing `handlerutil.ShipSecurityEvent` call shape (event name, `user-service`, customer actor ID, tenant target ID, human message, client IP), so closed-booking attempts are queryable for analytics and security review. No other new events are introduced.

## Consequences

- **Positive**: expired tenants vanish from the marketplace and cannot accrue bookings/escrow; every paid gate (`CreateService`, `UpdateService`, wallet deposit, payout request, reconciliation resolve, location updates, internal subscription check) goes fail-closed on expiry for free via the shared predicate — no per-endpoint edits.
- **Negative / accepted costs**:
  - `ListServices` performs up to one subscription read per distinct tenant per page (bounded by page size); acceptable at current scale, flagged for a future indexed/pushed-down filter if it ever shows in profiles.
  - Short pages (see Decision 2a) when closed tenants are present.
  - Closed owners see an empty service-configuration form until they renew (see Decision 3).
  - Existing backend tests that exercise `TrackJob`/`ListServices` without seeding an open subscription (or with fixtures the new predicate closes) must seed one — test-only maintenance, no production behavior compromise.
- **Explicitly deferred**: admin console surfacing of closed tenants, customer-visible "closed" badges, expiry-reminder notifications, and any background expiry sweeper. If a sweeper ever appears, it must derive closed-ness from this same predicate, never a copy.

## Alternatives Considered

- **Scheduled sweeper flipping tiers on expiry**: rejected — the repo has no cron/scheduler infrastructure, a sweeper introduces windows where stored tier and true status disagree, and it duplicates the definition this ADR centralizes.
- **Flag closed services in the listing instead of filtering**: rejected — pushes enforcement logic onto every present and future client (mobile, console, API consumers) instead of deciding once server-side.
- **Booking-time gate only, listing untouched**: rejected — customers would browse businesses they can never book; the listing is the first lie to fix.
- **Owner bypass parameter on ListServices**: rejected — new contract surface plus a tenant-match authorization check, for a screen whose writes are paid-gated anyway (Decision 3).
- **Separate `IsExpired` helper alongside the tier check**: rejected — two call sites, two definitions, guaranteed future divergence; the single nil-safe predicate is the whole point.
