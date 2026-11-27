# Geo & Address Proxy API (`user-service`)

This document specifies the server-proxied Google Maps Platform endpoints exposed by `user-service` (proxied externally through `api-gateway` at `/api/v1/users/geo/*`, see [ADR-0032](../adr/0032-google-maps-platform.md)).

## Configuration & Availability

- Environment variable: `GOOGLE_MAPS_SERVER_KEY` (optional).
- When `GOOGLE_MAPS_SERVER_KEY` is empty or unset, all three geo endpoints return HTTP `503 Service Unavailable` with stable error code `geo_unavailable`; all other `user-service` endpoints continue operating normally.
- The server key is never logged and never returned to clients. Upstream Google error text is never returned verbatim; failures map to stable machine error codes (`SafeError` body: `{"error": "...", "code": "...", "request_id": "..."}`).
- Google terms: no caching except `place_id` / `lat-lng` (addresses and other Google content are never cached server-side; every `/users/geo/place` and `/users/geo/reverse` request queries Google directly).

## Authentication & Localization

- **Authentication**: Required (`Authorization: Bearer <jwt>`). Any valid non-revoked user role (`user`, `customer`, `owner`, `employee`) is accepted.
- **Language**: Read from `Accept-Language` (`ar` when the preferred tag starts with `ar`, otherwise `en`).
- **Egypt Bias**: Places requests send `includedRegionCodes: ["eg"]` and `regionCode: "eg"`; Geocoding requests send `region=eg`.

## Rate Limiting (ADR-0016)

Each endpoint enforces an independent per-user Redis sliding-window rate limit (`1m` window, keyed by authenticated `user_id`):

| Endpoint | Limit | Limiter Namespace |
| :--- | :--- | :--- |
| `GET /users/geo/autocomplete` | 30 req/min | `user:geo_autocomplete` |
| `GET /users/geo/place` | 20 req/min | `user:geo_place` |
| `GET /users/geo/reverse` | 30 req/min | `user:geo_reverse` |

Rate-limit rejections return HTTP `429 Too Many Requests` with `"code": "rate_limited"`.

## Endpoints

### 1. `GET /users/geo/autocomplete`

Queries Google Places API (New) `places:autocomplete` and returns up to 5 suggestions.

**Query Parameters**
- `q` (required): search text, 3–100 Unicode runes after trimming.
- `session` (optional): opaque autocomplete session token, ≤ 64 runes, no whitespace or control characters.

**Response `200 OK`**
```json
{
  "suggestions": [
    {
      "place_id": "ChIJ...",
      "primary": "15 Kasr El Nil",
      "secondary": "Downtown, Cairo, Egypt"
    }
  ]
}
```

### 2. `GET /users/geo/place`

Resolves coordinates, formatted address, and area for a `place_id` via Places API (New), ending the autocomplete session token for session-based billing. Google terms: no caching except `place_id` / `lat-lng`.

**Query Parameters**
- `place_id` (required): 1–300 runes, no whitespace, control characters, `/`, `?`, or `#`.
- `session` (optional): opaque session token, ≤ 64 runes, no whitespace or control characters.

**Response `200 OK`**
```json
{
  "lat": 30.0444,
  "lng": 31.2357,
  "address": "15 Kasr El Nil, Abdeen",
  "area": "Abdeen"
}
```

### 3. `GET /users/geo/reverse`

Reverse-geocodes coordinates via Google Geocoding API. Google terms: no caching except `place_id` / `lat-lng`. Client pickers skip `/geo/reverse` in widget state when the camera stops within 15 m of the last reverse-geocoded point in the current picker session.

**Query Parameters**
- `lat` (required): finite float in `[-90, 90]`.
- `lng` (required): finite float in `[-180, 180]`.

**Response `200 OK`**
```json
{
  "address": "15 Kasr El Nil, Qasr El Nil, Cairo",
  "area": "Qasr El Nil"
}
```
When Google returns `ZERO_RESULTS`, returns `200 OK` with empty `address` and `area` strings.

## Error Codes

| HTTP Status | `code` | Meaning |
| :--- | :--- | :--- |
| `400` | `invalid_query` | `q` missing or outside 3–100 runes after trim |
| `400` | `invalid_session` | `session` exceeds 64 runes or contains whitespace/control chars |
| `400` | `invalid_place_id` | `place_id` missing, exceeds 300 runes, or contains invalid chars |
| `400` | `invalid_coordinates` | `lat` or `lng` missing, non-numeric, or out of range |
| `401` | `unauthorized` / `invalid_token` | Missing, malformed, expired, or revoked Bearer JWT |
| `404` | `geo_place_not_found` | Upstream `place_id` not found |
| `429` | `rate_limited` | Per-user rate limit exceeded |
| `429` | `geo_rate_limited` | Upstream Google quota/rate limit exceeded |
| `502` | `geo_upstream_error` | Upstream Google transport, status, or parse failure |
| `503` | `geo_unavailable` | `GOOGLE_MAPS_SERVER_KEY` is not configured |
