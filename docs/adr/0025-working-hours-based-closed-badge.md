# ADR-0025: Working-Hours-Based Out-of-Service Badge and Booking Gate

- **Status**: Proposed
- **Date**: 2026-09-23
- **Related**: ADR-0024 (Expired-Subscription Closed Status for Marketplace Listing and Booking)

## Context

Services carry a free-text `working_hours` string (`Service.WorkingHours`, set via Owner Configuration), but nothing in the platform reasons about it: the marketplace never shows whether a business is currently open, and `TrackJob` accepts bookings at any hour. Customers can book a business at 3 AM that opens at 9 AM, with failure surfacing only later as courier-unavailability or owner-side cancellation.

ADR-0024 solved the adjacent problem of subscription-expiry closure by *removing* services from the listing entirely. Hours-based closure is the opposite visibility case: the business is legitimate and subscribing, just not serving right now. Removing it from the listing on every off-hour would churn the directory twice a day and hide genuinely useful information (where the business is, what it charges, when it reopens). The service must therefore stay listed, be visibly marked, and refuse bookings while closed — both gates applying independently to the same service.

## Decision

### 1. New structured schedule fields (additive, no migration)

Five additive fields on `Service` (persisted), `CreateServiceRequest`, and `UpdateServiceRequest` (pointers/`omitempty` on the request types, matching the existing `WorkingHours`/`CoverageRadiusKM` pattern). The existing `working_hours` string is NOT removed or migrated — it remains as a free-text display fallback:

```go
ScheduleMode   string           // "same_daily" | "per_day", empty = unknown
OpenTime       string           // "HH:mm" 24h, required when same_daily
CloseTime      string           // "HH:mm" 24h, required when same_daily
PerDaySchedule []DaySchedule    // required when per_day: exactly 7 entries
Timezone       string           // IANA (e.g. "Africa/Cairo"); default "Africa/Cairo"

// DaySchedule element:
Day       string // "mon".."sun"
OpenTime  string // "HH:mm", required unless IsOff
CloseTime string // "HH:mm", required unless IsOff
IsOff     bool   // weekday closed all day
```

AM/PM vs 24-hour is a FRONTEND INPUT CONCERN ONLY. The owner may pick a time via a 12h-with-AM/PM or 24h picker in the Flutter form, but whatever is picked is always normalized to 24h `"HH:mm"` before being sent to the backend. The backend never stores or reasons about AM/PM — validation accepts `"HH:mm"` only.

No auto-migration of the legacy `working_hours` string is performed (parsing free text like "9-5 weekdays" is unreliable and would silently invent schedules). Existing services simply have all five fields unset/empty until the owner re-fills them via Owner Configuration.

### 2. "Unknown schedule" is open

A service with all five fields empty — the case for every existing service until its owner updates it — MUST NOT be treated as closed. It behaves exactly as today: always listed, no badge, bookable (subject only to ADR-0024's gate). Only a service WITH a complete structured schedule gets hours-based open/closed evaluation. The pure evaluation function therefore returns `(isOpen=true, reopensAt=nil)` for unknown schedules by contract, and this is covered by tests.

### 3. Enforcement (opposite visibility rule from ADR-0024 — deliberate)

a. **`GET /users/services` (ListServices) — flag, never filter.** Hours-closed services REMAIN in the response. Each item carries two computed, non-persisted fields evaluated server-side at request time against the tenant's timezone: `is_open_now: bool` and `reopens_at: string|null` (RFC3339, when computable; null when unknown or not computable). This is deliberately the opposite rule from ADR-0024's removal — stated here explicitly so no future reader assumes the two gates behave the same way.

b. **`POST /users/jobs/track` (TrackJob) — reject with 402 while hours-closed.** Error code `outside_working_hours` (same 402 status-code precedent as `enforcePaidTier`/ADR-0024's gate, but a distinct error code so the frontend can tell the two 402 cases apart). Message: "This business is out of service right now." with the opening time appended when `reopens_at` is computable. The check runs before escrow/KYC work, mirroring where ADR-0024's gate was inserted. Both gates apply independently: a service can be subscription-open but hours-closed (402 `outside_working_hours`), or subscription-closed (removed from listing; hours evaluation moot).

### 4. Badge/copy semantics

The user-facing term for this state is **"Out of Service" (EN) / "مغلق دلوقتي" (AR)** — never a bare "Closed", which could be confused with ADR-0024's permanent-removal case. This state is explicitly temporary/hours-based. The term drives both the marketplace badge and the 402 message copy.

### 5. Timezone computation

Evaluation uses Go's `time.LoadLocation(service.Timezone)` with `"Africa/Cairo"` as the fallback on empty value or load failure — never panic, never 500 on a bad/missing timezone (log and fall back). The default is `"Africa/Cairo"` for any tenant that hasn't set one explicitly. Per-tenant timezone (rather than one platform-wide constant) is chosen deliberately to avoid a second migration if the platform expands beyond Egypt.

### 6. Non-goals

No separate day-off/holiday calendar beyond per-weekday `is_off`; no admin override to force-open/force-close a service; no push notification when a business reopens.

## Consequences

- **Positive**: customers see at a glance which listed businesses are serving now; off-hours bookings fail fast with an explanatory 402 instead of becoming stranded/unavailable jobs; legacy services change behavior not at all (unknown schedule = open).
- **Negative / accepted costs**:
  - `ListServices` evaluates the schedule function per returned item (pure CPU, no I/O beyond data already fetched) — negligible.
  - `reopens_at` is best-effort (null when the next opening isn't computable, e.g. unknown schedule or `per_day` with all days off); clients must treat null as "no info", never as a time.
  - Owner Configuration gains a schedule editor (Flutter work); until an owner fills it, their service stays "unknown" — the feature is strictly opt-in per service.
  - Overnight ranges (e.g. 22:00–04:00) must span midnight correctly in the evaluator — covered by a dedicated table-driven test.
- **Explicitly deferred**: holiday calendars, force-open/force-close overrides, reopen push notifications (see Non-goals).

## Alternatives Considered

- **Parse the legacy `working_hours` string into a schedule**: rejected — free text ("9-5 weekdays", "open late", Arabic variants) cannot be parsed reliably; silent mis-parses would close businesses at wrong hours, worse than no schedule.
- **Remove hours-closed services from the listing (ADR-0024 rule)**: rejected — twice-daily directory churn, hides pricing/location/reopening info customers need, and conflates a temporary state with permanent removal.
- **Client-side open/closed computation**: rejected — every client (mobile, console, API consumers) would reimplement timezone/daylight-saving logic; the server already owns the data and Go's tz database.
- **Single platform-wide timezone constant**: rejected — bakes in an Egypt-only assumption the per-tenant field avoids for free.
- **Reusing ADR-0024's `service_unavailable` error code for the 402**: rejected — the frontend must distinguish "renew your subscription" (owner problem, invisible to customers) from "come back at opening time" (customer-actionable); distinct codes make that possible.
