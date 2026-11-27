# Worklog: ADDR-GEO — address fields: search suggestions and pin-to-address

## Task and scope
- Task ID: ADDR-GEO (Issue #49, 2 of 4)
- Item IDs covered: 1 (done), 2 (done), 3 (pending), 4 (pending)
- Allowed paths (lane from the task prompt):
  - `services/user-service/internal/config/**`
  - `services/user-service/internal/geo/**`
  - new files under `services/user-service/internal/handlers/` (+ tests)
  - `services/user-service/internal/handlers/handlers.go` (route registration / wiring)
  - `tests/contracts/**`, `tests/e2e/**`
  - `docs/APPLICATION_MAP.md` (via `make docs` only), `docs/api/**`
  - `frontend/lib/**`, `frontend/test/**`
  - `docs/worklog/ADDR-GEO.md`
- Agent branch: `agent/ADDR-GEO-address-autocomplete`, created from `logic-exploitation` at `12111e7c` (post `MAPS-SDK` merge)

## Decisions taken
- Verified `services/api-gateway/internal/config/config.go` and `internal/proxy/proxy.go`: `/api/v1/users/` already reverse-proxies all subpaths to `user-service` (stripping `/api/v1`) with `WithUpstream5xxPassthrough()`, so 503 `geo_unavailable` and all `/users/geo/*` routes pass through with no `api-gateway` code changes.
- `GOOGLE_MAPS_SERVER_KEY` in `services/user-service/internal/config/config.go` is optional and trimmed; when empty, config loads cleanly with zero warnings (including in `production`) and geo endpoints answer `503 geo_unavailable`.
- `services/user-service/internal/geo` uses `net/http` (zero new Go dependencies), Places API (New) (`places:autocomplete` and `places/{place_id}` with `X-Goog-Api-Key` header) and Geocoding API (`geocode/json` with `region=eg` and error/key redaction), keeping `RoutesBaseURL` configurable for the upcoming `ROAD-DISTANCE` task.
- In-memory LRU+TTL caches (24h TTL, bounded to 5000 entries each) key Place Details by `place_id|lang` and Reverse Geocode by `round4(lat),round4(lng)|lang` (~11 m grid) so `ar` and `en` responses do not collide while avoiding repeat upstream calls.
- Per-user rate limits (ADR-0016, 1-minute Redis windows keyed by authenticated `user_id`):
  - `GET /users/geo/autocomplete`: **30 req/min** (`user:geo_autocomplete`) — matches ADR-0016's 30 req/min interactive browsing tier; covers ~5–8 debounced (400 ms) autocomplete queries per stop across pickup + drop-off while capping scraping.
  - `GET /users/geo/place`: **20 req/min** (`user:geo_place`) — matches ADR-0016's 20 req/min interactive selection tier; only fired when a user taps a suggestion, allowing repeated re-picks without opening Place Details SKU abuse.
  - `GET /users/geo/reverse`: **30 req/min** (`user:geo_reverse`) — matches ADR-0016's 30 req/min tier; fired once per camera-idle pin stop (with 4-decimal cache hits absorbing nearby re-stops) while protecting Geocoding SKU quota.

## Changes per commit (message only — NO SHAs)
1. `feat(user-service): add Google geo proxy endpoints, cache, and API docs (ADDR-GEO)`
2. `feat(frontend): add address search field with autocomplete and session tokens (ADDR-GEO)`

## Deploy note
- Backend can release first: geo endpoints return `503 geo_unavailable` until `GOOGLE_MAPS_SERVER_KEY` is set in the production environment (ADR-0012); nothing else in `user-service` changes.
- Owner setup before enabling in production: enable **Places API (New)** and **Geocoding API** on the GCP project, create the server API key restricted to the production VM egress IP and those two APIs, set per-API daily quotas and billing alerts, and set `GOOGLE_MAPS_SERVER_KEY` in production env.

## Verification
- `go test -v -count=1 ./internal/geo/... ./internal/config/...` (in `services/user-service`) — PASS
- `go test -v -count=1 ./internal/handlers -run TestGeoHandlers` (in `services/user-service`) — PASS
- `make check` (Item 1) — PASS (`scope: go=services/user-service contracts docs infra-tests docgen`)
- `flutter test test/core/geo/address_search_field_test.dart` — PASS (6/6)
- Pending `make check` for Item 2.

## Unverified
- Live calls against real Google Places API (New) and Geocoding API (tests use an `httptest` fake of Google; real GCP key not present in workspace).

## Follow-ups / out-of-lane findings
- `docs/APPLICATION_MAP.md` shows `<!-- TODO: verify manually -->` in the `Targets` column for the 3 new `/users/geo/*` routes because `KnownEndpoints` in `shared/infra/docgen/generator.go` is out-of-lane (`shared/**`).

## Open questions
- none
