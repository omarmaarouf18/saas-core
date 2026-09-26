# Destination Address: Proposal (Issue-2, Employee UX)

> **Status**: Option A **implemented** this pass (frontend-only, no new
> dependency). Option B **proposed — STOPPED for decision**, no backend/API
> work started (per task scope: backend/API-dependency scope needs explicit
> go-ahead).

## Root cause (confirmed, not assumed)

`frontend/lib/models/job.dart` → `JobLocation` carries ONLY
`latitude`/`longitude`. No address field exists anywhere in the data
model, frontend or backend (verified by grep over both trees:
`address` appears in the job path only as `pickupAddress`/
`dropoffAddress` *section-title* l10n keys, never as data). That is why
`employee_jobs_screen.dart` renders
`job.destination?.formatCoordinates()` — there is literally nothing
else to show. No geocoding package is in `pubspec.yaml`; the map stack
is `flutter_map` 7 + OSM raster tiles (`mapTileUrlTemplate`, Carto
override documented in `core/constants.dart`), not Google Maps.

## Option A — embedded map thumbnail (IMPLEMENTED)

Replace the raw-coordinates-first presentation with a small
non-interactive `flutter_map` thumbnail + pin at the destination
(`JobLocationMiniMap`, `RouteTimeline.dropoffMap` slot), reusing the
exact tile template + User-Agent constants the app already ships.
Exact numbers stay as a small caption for precision.

- **Effort**: done (~150 lines widget + slot + 2 call sites + tests).
- **Cost**: $0. No new packages, no new services, no new license
  surface — same OSM tile stack already loaded by the fleet map, job
  map, and picker (same UA `QuickDeliveryApp/1.0`, same Carto override
  path). A third-party static-image service
  (e.g. staticmap.openstreetmap.de) was evaluated and REJECTED:
  unofficial, rate-limited, unsuitable for production traffic.
- **Rate-limit risk**: marginal. A 110px thumbnail at z15 loads ~4
  tiles per visible card vs dozens for the full-screen maps already in
  the app. Gestures disabled (no pan/zoom tile churn), error tiles
  swallowed. Same OSM tile-usage policy posture as today.
- **Offline**: same as the rest of the app (no tiles offline) — no
  better, no worse.
- **Backend change**: none.

## Option B — real reverse geocoding via Nominatim (PROPOSED, not started)

Resolve lat/lng → human-readable address with OSM's own Nominatim
(consistent with the existing OSM stack; no Google Maps dependency).

- **Where computed (recommended)**: backend at job-creation time,
  stored as optional `destination_address` / `pickup_address` display
  strings on the `Job` document. Rationale: one lookup per booking
  (not N per card render), consistent across owner/employee/customer,
  readable offline, immune to render-time failures. Frontend
  on-demand lookup is explicitly NOT recommended (per-render network
  fan-out per card = Nominatim policy violation at any real scale).
- **Caching**: jobs are location-immutable → store once, read many; no
  TTL needed on the job fields. If a shared lookup cache is wanted for
  repeated coordinates, backend Redis keyed by rounded
  (lat,lng,zoom) — optional, not required for v1.
- **Rate limits (do not understate)**: public Nominatim usage policy
  caps at **1 request/sec**, requires a valid HTTP
  Referer/User-Agent, and forbids heavy/bulk use. At booking-time
  volume this is fine for launch (bookings ≪ 1/sec), but ANY scale
  beyond that needs either a **self-hosted Nominatim** (planet import
  ~1TB+, real ops burden) or a **commercial geocoder** (real cost).
  This is the decision that must be made before building.
- **Effort**: backend model fields + TrackJob resolution + tests,
  frontend `Job` model fields + card adoption with Option-A
  thumbnail as the null-address fallback (~2–3 sessions).
- **Migration**: old jobs have no stored addresses — Option A stays
  as the permanent fallback renderer, so no backfill is required.

## Decision needed before Option B

1. Approve backend scope (new optional address fields on `Job`)?
2. Self-hosted Nominatim vs commercial geocoder at scale (vs.
   launch-only public API with the 1/sec ceiling monitored)?
3. Optional backend coordinate cache now or later?

Until decided, Option A ships and the caption keeps exact coordinates.
