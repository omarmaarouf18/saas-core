# ADR-0008: Live Employee Map Tracking Architecture & Provider Selection

- **Status**: Proposed
- **Date**: 2026-07-27
- **Related Commit SHA**: c14e7e8e82b69715ffae7b5fca4d941d3410ae43
- **Related audit finding**: Live Employee Map Tracking & Fleet Visualization Provider Selection

## Context

The Quick Delivery platform collects live location coordinates from active employees via the existing `UpdateJobLocation` endpoint in `services/user-service/internal/handlers/handlers.go` (`POST /users/jobs/location/update`). While location coordinates are persisted in MongoDB (`job.CurrentLocation`), there is currently no frontend visualization mechanism to render these coordinates on a live map.

We need to introduce a live map tracking feature for two primary user roles:
1. **Tenant Owners**: A fleet view rendering the real-time positions of all active employees belonging to their tenant.
2. **Customers**: A single-job tracking view rendering the position of the specific employee assigned to their active delivery or transport request.

### Constraints & Existing Frontend Audit

* **Hard Constraint**: The map SDK and tile provider must be **100% free with no paid API keys, usage-based billing, or credit card requirements**.
* **Frontend Dependency Audit**: An audit of `frontend/pubspec.yaml` and `frontend/lib/` confirms **zero existing map dependencies** in the codebase. This decision is a from-scratch architectural choice, not a migration from a legacy provider.

---

## Decision

We decided to adopt **`flutter_map` with OpenStreetMap (OSM) / Carto raster tile providers** for frontend rendering, paired with **`chat-service` WebSocket channels (ADR-0005)** for real-time location streaming.

---

### 1. Map SDK & Tile Provider Selection

We evaluated three potential map packages against our strict zero-cost constraint:

| Provider / SDK | Licensing & Billing Model | Usage Limits & Risks | Recommendation |
|---|---|---|---|
| **`flutter_map` + OpenStreetMap (OSM) / Carto** | **100% Free & Open Source (MIT)** | Standard OSM tile servers (`tile.openstreetmap.org`) require a descriptive HTTP `User-Agent` header and prohibit high-volume abuse per the OSM Tile Usage Policy. Free-tier third-party hosts (e.g. Carto Voyager raster tiles) provide generous usage tiers without credit card registration. | **SELECTED** |
| **`google_maps_flutter`** | Proprietary SDK; requires Google Cloud Platform (GCP) Billing Account | Offers a monthly $200 free credit, but **requires linking a valid credit card / billing account during setup**. Spikes in map tile loads or compromised API keys expose the project to un-capped, unexpected financial liabilities. | **REJECTED** |
| **`maplibre_gl` / Mapbox** | Open source SDK, but requires custom vector tile server hosting | Vector tiles require hosting a TileServer GL or Mapbox access token. Mapbox requires billing registration beyond free tier limits. | **REJECTED** |

#### Justification for `flutter_map` Selection
* **Zero Financial Liability**: `flutter_map` is an open-source Flutter package that renders tile layers natively without requiring native mobile SDK initialization or proprietary API key registration.
* **Tile Provider Strategy**:
  * For local development and low-volume staging: standard OpenStreetMap raster tiles (`https://tile.openstreetmap.org/{z}/{x}/{y}.png`) configured with a custom platform `User-Agent` header (`QuickDeliveryApp/1.0`).
  * For production deployment: Carto Voyager raster tiles (`https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png`) or an open proxy, seamlessly configurable via environment constants without code refactoring.

---

### 2. Live-Update Transport Selection

We evaluated how location broadcasts reach active map clients by inspecting the implementation of both real-time hubs in `services/chat-service/internal/chat/hub.go` and `services/notification-service/internal/hub/hub.go` (ADR-0005):

#### Inspection Findings:
1. **`notification-service` (`services/notification-service/internal/hub/hub.go`)**:
   * Uses unidirectional Server-Sent Events (SSE) scoped by role (`RoleOwner`, `RoleEmployee`, `RoleClient`) and tenant (`TenantID`).
   * Broadcasts rely on `PSubscribe("notify:*")` across all instances. It is designed for discrete push alerts (`Notification` struct) and lacks granular, channel-scoped topic filtering per job session.
2. **`chat-service` (`services/chat-service/internal/chat/hub.go`)**:
   * Uses bidirectional WebSockets with dynamic Redis Pub/Sub channel subscriptions (`chat:channel:<channel_name>`).
   * **Pre-Existing Location Support**: Inspection of `chat/hub.go` lines 24–27 reveals that `Message` **already includes native fields** for location broadcasts:
     ```go
     type Message struct {
         Channel    string   `json:"channel"`
         Type       string   `json:"type,omitempty"`     // "message", "join", "leave", "location_update"
         Latitude   *float64 `json:"latitude,omitempty"`  // live tracking latitude
         Longitude  *float64 `json:"longitude,omitempty"` // live tracking longitude
         EmployeeID string   `json:"employee_id,omitempty"`
     }
     ```
   * Instances dynamically subscribe to Redis Pub/Sub topics only when local clients join a channel (`Subscribe`) and include built-in instance de-duplication (`OriginInstanceID`).

#### Decision: Reusing `chat-service` WebSockets (Option A + Hybrid Hydration)
* **Real-Time Stream**: We reuse `chat-service` WebSockets for streaming live map markers.
  * **Customer Channel**: `job:<job_id>` — customer subscribes to receive location updates for their active job.
  * **Owner Fleet Channel**: `fleet:<owner_id>` — tenant owner subscribes to receive location updates for all active employees under their fleet.
* **Initial State Hydration**: When opening a map view, the frontend first performs an HTTP GET request to `user-service` (`GET /users/jobs/get` for customers or `GET /users/jobs/owner` for owners) to fetch initial marker coordinates before listening on the WebSocket channel for incremental updates.

---

### 3. Scope of Who Sees What & Authorization Boundaries

We strictly enforce tenant isolation and identity-scoped access control, reusing authorization patterns established in `user-service`:

1. **Tenant Owner (Fleet View)**:
   * **Visible Markers**: All employees registered under the owner's tenant who are **currently active**.
   * **Definition of "Currently Active"**: An employee is considered active if they have a job in `models.JobStatusActive` state OR have transmitted an `UpdateJobLocation` update within the last 15 minutes.
   * **Authorization**: The endpoint / channel subscription verifies `resolveTokenWithRole(token, "owner")` and validates `owner_id == authenticated_owner_id`.
2. **Customer (Job View)**:
   * **Visible Markers**: Strictly the single employee (`job.EmployeeID`) assigned to the customer's active job (`job.CustomerID == authenticated_customer_id` and `job.Status == JobStatusActive`).
   * **Authorization**: The endpoint / channel subscription verifies `resolveTokenWithRole(token, "customer", "user")` and asserts `job.CustomerID == resolvedRequester`. Access attempts for unauthorized job IDs trigger HTTP 403 / `[TENANT SCOPE BLOCKED]` security log events.

---

### 4. Explicit Non-Goals

The following capabilities are **explicitly OUT OF SCOPE** for this ADR:
* **Geocoding & Reverse Geocoding**: Converting text addresses to latitude/longitude or vice-versa.
* **Routing & Turn-by-Turn Navigation**: Fetching road polylines or driving directions (which requires routing engines like OSRM or Valhalla).
* **Place Search & Autocomplete**: Searching for business names or points of interest.

These features require distinct infrastructure decisions (e.g. self-hosting OSRM or Nominatim) and must be evaluated in separate future ADRs.

---

## Consequences

### Positive
* **Zero Cost & Billing Safety**: Eliminates monthly cloud map API bills and key compromise financial risks.
* **Infrastructure Reuse**: Eliminates duplicate real-time code by reusing `chat-service` Redis Pub/Sub channels (ADR-0005).
* **Strict Security Boundaries**: Reuses existing `user-service` JWT role verification and tenant isolation checks.

### Tradeoffs & Known Limitations
* **Tile Usage Restrictions**: Standard OpenStreetMap tile servers require compliance with tile usage policies; high-volume production requires pointing tile URLs to Carto or a dedicated tile proxy.
* **Raster Tiles**: `flutter_map` uses raster image tiles by default, which require network fetching per zoom level compared to client-side rendered vector tiles.

---

## Alternatives Considered

1. **Google Maps Platform (`google_maps_flutter`)**:
   * *Rejected*: Requires GCP billing setup, linking a credit card, and managing restricted API keys with risk of un-capped charges.
2. **Dedicated Location SSE Stream (`notification-service`)**:
   * *Rejected*: `notification-service` is designed for role/tenant push alerts (`notify:*`) and lacks channel-based per-job subscription isolation.
3. **HTTP Polling Endpoint Only (Option C)**:
   * *Rejected*: Polling introduces excessive server overhead and delays location updates compared to existing WebSocket channels.
