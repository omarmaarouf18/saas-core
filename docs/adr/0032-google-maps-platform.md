# ADR-0032: Google Maps Platform for Maps, Address Search, and Road Distance

- **Status**: Accepted (owner decision, 2026-11-27)
- **Date**: 2026-11-27
- **Related**: GitHub issue #49; ADR-0008 (Live Employee Map Tracking — tile provider choice superseded here; `chat-service` WebSocket transport and authorization boundaries unchanged); ADR-0028 (Job Model v2); ADR-0030 (Three client apps from one codebase: `app.waddify`, `app.waddify.console`, `app.waddify.employees`); ADR-0031 (reserved for `docs/business/BUSINESS_MODEL.md`).

---

## Context

When live employee map tracking was introduced (ADR-0008), `frontend/` adopted `flutter_map` with OpenStreetMap raster tiles (`mapTileUrlTemplate` defaulting to `https://tile.openstreetmap.org/{z}/{x}/{y}.png` in `frontend/lib/core/constants.dart`) to avoid GCP billing setup during early prototyping.

Two constraints block shipping the three Waddify store apps (`customer`, `console`, `employees`, ADR-0030) on that setup:

1. **OpenStreetMap tile usage policy**: `tile.openstreetmap.org` is a community resource whose Tile Usage Policy forbids heavy or commercial use by distributed mobile apps without prior permission and allows servers to throttle or block clients without notice. Relying on public OSM tiles in store releases means maps across all three apps can stop working at any time.
2. **Egypt address quality**: Waddify targets Egypt in English and Egyptian Arabic (`ar_EG`). Upcoming features — address search/autocomplete and pin-to-address reverse geocoding (`ADDR-GEO`), plus road-distance routing and pricing (`ROAD-DISTANCE`) — require accurate bilingual Egyptian street, neighborhood, and landmark coverage that OSM/Nominatim lacks in many areas.
3. **Google Maps Platform Terms of Service (Geocoding display rule)**: Under the Google Maps Platform Terms of Service, Geocoding and Places results must be displayed on a Google map and must not be displayed on top of a non-Google map (such as OpenStreetMap). Moving address search to Google therefore requires moving every map surface in the app to Google Maps, not only the address picker.

---

## Decision

### 1. Adopt Google Maps Platform across all three apps

Google Maps Platform is the single map, geocoding/places, and road-distance provider for all three apps built from `frontend/` (`customer` / `app.waddify`, `console` / `app.waddify.console`, `employees` / `app.waddify.employees`).

- Map rendering in Flutter uses `google_maps_flutter`, wrapped behind one app widget (`AppMap` in `frontend/lib/core/maps/app_map.dart`). Screens never import `google_maps_flutter` directly.
- All four map surfaces move off `flutter_map` and OSM tiles:
  - `features/courier/courier_map.dart`
  - `features/customer/order/track_map.dart`
  - `features/customer/picker_page.dart`
  - `features/owner/fleet_map_page.dart`
- Google logo and map attributions must remain visible and unobstructed in every layout.
- If the Maps SDK key is absent at build time (e.g., local development without secrets or default CI), `AppMap` renders a short localized "map unavailable" state without instantiating a native map view, and the rest of the screen continues to work.

### 2. Strict key split (app key vs. server key)

Credentials are split by trust boundary and API surface:

| Key | Where it lives | APIs permitted | Restrictions |
| :--- | :--- | :--- | :--- |
| **App key** (client SDK key) | Native mobile builds only (`AndroidManifest.xml` via `MAPS_API_KEY` manifest placeholder; `Info.plist` / `AppDelegate.swift` via `MAPS_API_KEY` build setting; `--dart-define=MAPS_API_KEY`). Empty by default. | **Maps SDK for Android**, **Maps SDK for iOS** only | Restricted in GCP to those two SDKs and to the three package names / bundle IDs (`app.waddify`, `app.waddify.console`, `app.waddify.employees`) plus their Android release signing SHA-1 certificates. |
| **Server key** | Backend `user-service` environment only. **Never** compiled into or shipped in `frontend/**`. | **Geocoding API**, **Places API**, **Routes API** | Restricted in GCP to those server APIs (and server egress IP / backend credentials). All address search, reverse geocoding, and road-distance calls flow strictly through `user-service`. |

### 3. Cost controls

- **Maps SDK for Android & iOS**: No per-load usage charge (unlimited free standard mobile map loads). `MAPS-SDK` adds zero Geocoding, Places, or Routes requests.
- **Metered server APIs (`ADDR-GEO`, `ROAD-DISTANCE`)**: Google Maps Platform grants a free monthly allowance per SKU (tiered by Essentials / Pro / Enterprise SKU limits rather than a single flat pooled credit).
- **Owner controls**: Before metered server APIs go live, the owner enables billing on the GCP project, sets per-API / per-day quotas, keeps `user-service` rate limits and caching in place (subject to Google Maps Platform caching terms), and configures a Cloud Billing budget alert in the GCP Console.

### 4. Four-task implementation plan

1. **`MAPS-SDK` (Issue #49 — this task)**:
   - Record this ADR (ADR-0032).
   - Add `google_maps_flutter` behind one `AppMap` widget with test-fake injection seam, markers, polylines, camera move / fit bounds, `onCameraIdle` center callback, tap callback, and missing-key fallback.
   - Migrate all four map screens (`courier_map.dart`, `track_map.dart`, `picker_page.dart`, `fleet_map_page.dart`) and remove `flutter_map`, `mapTileUrlTemplate`, OSM tiles, and obsolete tile test stubs.
   - Wire `MAPS_API_KEY` build configuration for Android and iOS (empty by default so local and CI builds pass).
2. **`ADDR-GEO`**:
   - Add server-proxied address autocomplete and reverse geocoding in `user-service` (using the server key), wired to `picker_page.dart` via `AppMap`'s `onCameraIdle` center callback.
3. **`MAPS-QA`**:
   - Verify map rendering, styles, gestures, markers, and flavor key restrictions across `app.waddify`, `app.waddify.console`, and `app.waddify.employees` on physical Android/iOS devices with the real restricted app key.
4. **`ROAD-DISTANCE`** (in parallel with `MAPS-QA`):
   - Add server-proxied road distance and ETA calculation via `user-service` (Routes API, server key), upgrading straight-line haversine trip estimates and distance calculations.

---

## Consequences

### Positive
- Eliminates production outage risk from public OSM tile server rate limits or blocks.
- Enables accurate bilingual (Arabic and English) Egyptian address search, reverse geocoding, and road routing while staying compliant with Google Maps Platform display rules.
- Zero usage cost for mobile map rendering itself (`Maps SDK for Android` / `Maps SDK for iOS`); empty-by-default build wiring keeps local builds and unkeyed CI green.
- Single `AppMap` wrapper keeps `google_maps_flutter` isolated from feature screens and makes widget testing deterministic without platform views.

### Tradeoffs and follow-up work
- Requires a GCP project with billing enabled, restricted app and server API keys, and budget/quota alerts configured by the owner.
- Mobile release workflows (`frontend/.github/workflows/build-apk.yml`, `store-testing.yml`, Fastlane lanes) must pass `MAPS_API_KEY` for all three flavors before store builds show live Google maps.
- Real-device visual/rendering verification cannot run in headless widget tests and is deferred to `MAPS-QA`.

---

## Alternatives Considered

1. **Keep `flutter_map` with Carto / self-hosted OSM tile server**:
   - *Rejected*: Solves OSM rate limits only for map tiles, not Egypt address search/geocoding quality or road routing. Self-hosting Nominatim + OSRM/Valhalla adds operational burden and still lacks Google's Egyptian POI/street data; mixing Google Geocoding with OSM tiles violates Google Maps Platform Terms of Service.
2. **Mapbox / MapLibre**:
   - *Rejected*: Adds a separate vendor/billing integration and still cannot display Google Geocoding/Places results under Google Maps Platform display rules.
