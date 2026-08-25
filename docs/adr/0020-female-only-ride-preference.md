# ADR-0020: Female-Only Ride Preference Flag

- **Status**: Proposed
- **Date**: 2026-08-25
- **Related**: ADR-0006 (Negotiable Transport Pricing), ADR-0019 (Independent Solo Driver Accounts), ADR-0013 (Support Agent Console)

## Context

The platform's `transport` category (customer-facing "Ride") currently matches customers to drivers with no passenger-preference constraints. Several regional ride-hailing markets expect a **female-only** option: a customer can request that only female drivers be assigned to their ride. There is no gender attribute anywhere in the data model (`User`, `Service`, `Job` — verified against `services/auth-service/internal/models/models.go` and `services/user-service/internal/models/models.go`), and no auto-dispatcher exists: drivers are either pre-assigned at booking (`TrackJob`, gated by ADR-0004) or assigned afterwards by the tenant owner.

## Decision

Add a minimal, server-enforced **booking flag** — not a matching engine, not a separate category.

1. **Data model**:
   - `User.Gender string` (`""` | `"female"` | `"male"` | `"unspecified"`), self-declared at signup, editable via `PATCH /auth/user`. Treated as sensitive PII: never rendered in public profiles, never included in directory/service payloads, never logged.
   - `Job.FemaleOnlyRequested bool` (bson `female_only_requested`), accepted **only for `category=transport`** jobs; rejected with 400 for delivery/shipping categories.
2. **Enforcement points (server-side, fail-closed)**:
   - `TrackJob` pre-assignment: if `FemaleOnlyRequested && employee.Gender != "female"` → 400 `female_only_conflict` + audit event `FEMALE_ONLY_ASSIGNMENT_BLOCKED`.
   - Owner-side later assignment onto an open transport job with the flag set uses the same validation path.
   - No behavioral change for jobs without the flag.
3. **Privacy surface rules**:
   - Drivers' gender is exposed ONLY as a derived boolean `is_female_driver` on service cards / job detail payloads — the raw field never crosses the API to other users.
   - Customer gender is used exclusively inside enforcement logic; drivers see nothing about it (a female-only job shows a neutral badge, never customer attributes).
4. **Frontend**:
   - Signup: optional gender selector (defaults `unspecified`, skippable).
   - Booking dialog (transport only): "Female driver only" toggle with explanatory copy; shown as badge on job status/maps/history screens.
   - Directory: "Female drivers" filter chip using the derived boolean.
5. **Interaction with ADR-0019**: independent drivers use the same `Gender` field; female-only bookings can match independent female drivers exactly like tenant employees.

## Alternatives Considered

- **Separate female-only service category/tier**: duplicates directory semantics, complicates pricing/negotiation paths (ADR-0006), fragments analytics. Rejected — one boolean on transport jobs achieves the goal.
- **Driver-side exclusivity (female drivers accept only female customers)**: deferred. Requires exposing customer gender to assignment logic visible to owners; revisit if demand exists.
- **Gender verified from KYE documents**: makes document reviewers arbiters of gender identity and adds legal friction; self-declaration chosen for launch.

## Consequences

- Two new fields + one validation branch per assignment site; each ships with positive/negative unit tests including IDOR negatives.
- The flag has deliberately **no override path** once set (fail-closed); owners see the constraint inline before assigning.
- Gender PII enters the schema: add explicit redaction to log scrubbers (same discipline as query-string tokens) and keep it out of audit payloads beyond the boolean blocking decision.
- Unmet female-only demand is measurable from existing job timestamps — no new instrumentation.

## Phased Roadmap

| Phase | Scope | Verification gate |
|---|---|---|
| B0 | `User.Gender` + `Job.FemaleOnlyRequested` model fields | unit tests on defaults/serialization |
| B1 | Signup + PATCH profile gender handling (validation, PII redaction in logs) | auth-service unit tests |
| B2 | TrackJob enforcement branch + category gating + audit event | unit tests incl. cross-tenant negatives |
| F1 | Flutter signup selector + booking toggle + badges (en/ar localization) | widget tests |
| F2 | Directory filter chip + service payload `is_female_driver` | widget tests |

*Open questions for the project owner*: is gender selection mandatory for employees (proposal: yes — required to make the flag meaningful) while optional for customers (proposal: yes)?
