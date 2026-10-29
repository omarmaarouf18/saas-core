# Admin & Reviewer Operations API Reference

This specification defines the HTTP API contract exposed by `saas-core` for the KYC Reviewer Console (`kyc-reviewer-console`), companion mobile apps, and edge infrastructure. It serves as the authoritative contract for **CONSOLE-V2** and related administrative tooling.

---

## 1. Edge Security & Authentication Architecture

### 1.1 Edge Gate (Caddy `basic_auth`)
The console frontend and edge ingress at `kyc.logiclinkeg.tech` enforce HTTP Basic Authentication at the Caddy edge layer before any traffic reaches internal services:
- **Environment Variables**:
  - `KYC_CONSOLE_BASIC_AUTH_USER`: Username for the edge gate.
  - `KYC_CONSOLE_BASIC_AUTH_HASH`: Bcrypt password hash generated using `caddy hash-password`.
- **Fail-Closed Behavior**: If `KYC_CONSOLE_BASIC_AUTH_HASH` or `KYC_CONSOLE_BASIC_AUTH_USER` is empty or unset, Caddy responds with `503 Service Unavailable` (`"Admin reviewer console is not configured on this host."`).
- **Security Headers**:
  - `Strict-Transport-Security: max-age=31536000; includeSubDomains; preload`
  - `Content-Security-Policy: frame-ancestors 'none'`
  - `X-Frame-Options: DENY`
  - `X-Content-Type-Options: nosniff`
- **Container Pinning**: Compose services pin `${KYC_CONSOLE_IMAGE_TAG}` with no `latest` fallback; compose preflight fails if unset.

### 1.2 Reviewer Authentication Contract
All administrative endpoints require two authentication headers:
1. `X-Internal-Token`: Pre-shared service secret matching `INTERNAL_SERVICE_TOKEN` / `INTERNAL_ADMIN_TOKEN`.
2. `X-Reviewer-Token`: Reviewer bearer token issued to verified human operators.

**Verification Flow**:
Downstream services authenticate requests via `auth-service` at `GET /auth/reviewer/verify`:
- Checks `X-Internal-Token` and `X-Reviewer-Token`.
- Returns HTTP 200 with reviewer metadata (`{"id": "...", "name": "...", "role": "reviewer"}`).
- Rejects unauthenticated or invalid reviewer sessions with `401 Unauthorized` (`{"code": "unauthorized", "message": "invalid reviewer credentials"}`).

### 1.3 Rate Limiting Architecture
To prevent lockout of the entire console when all requests route through a single egress IP, `/auth/reviewer/verify` and admin handlers enforce a composite rate limiter:
- **Key**: Reviewer token SHA-256 hash prefix (first 16 hex chars) + Forwarded Client IP (from `X-Forwarded-For` or `RemoteAddr`).
- **Trusted Forwarding**: Client IP is only accepted from forwarded headers when the request bears a valid `X-Internal-Token`.
- **Tiered Budget**: Per-reviewer-client limit (10 failed attempts/min) plus a global fallback ceiling (100 req/min) to shield the authentication store.

### 1.4 Mutation Contract & Safety
All mutation operations (state transitions, cancellations, hides, suspensions, version bumps) strictly follow these principles:
- **Mandatory Reason**: Body field `reason` must contain between 1 and 1000 characters. Empty or oversized reasons reject with `400 Bad Request` (`code: invalid_reason`).
- **Compare-And-Swap (CAS)**: State updates enforce preconditions on the existing record status. Concurrently modified entities reject with `409 Conflict`.
- **Security Audit Events**: Mutations and sensitive read operations emit structured security audit events (`handlerutil.ShipSecurityEvent`) containing actor ID, target entity, client IP, and justification.
- **PII Protection**: User phone numbers are masked throughout standard views and only revealed in explicit support lookup contexts (`GET /admin/jobs/{id}`).

---

## 2. Overview

### `GET /admin/overview`
Aggregates high-level operational counts across `user-service`, `auth-service`, and `chat-service`. Downstream service failures degrade gracefully with `null` count values rather than failing the overall overview response.

- **Service**: `user-service`
- **Permissions**: Reviewer Token & `X-Internal-Token`
- **Query Parameters**: None

**Response `200 OK`**:
```json
{
  "pending_kyb_kye": 14,
  "pending_payment_subscriptions": 3,
  "open_assigned_tickets": 7,
  "gps_disputes": 2,
  "stuck_cod_jobs": 1,
  "jobs_today_by_status": {
    "pending": 5,
    "assigned": 12,
    "picked_up": 8,
    "completed": 45,
    "cancelled": 2
  },
  "new_accounts_today": 18,
  "new_accounts_7d": 114,
  "suspended_accounts": 4
}
```

**Audit Event**: None (Read-only operational metric).

---

## 3. Jobs Lookup & Mutations

### `GET /admin/jobs`
Searches and lists platform jobs with comprehensive filtering and cursor/offset pagination.

- **Service**: `user-service`
- **Permissions**: Reviewer Token & `X-Internal-Token`
- **Query Parameters**:
  - `id` (string): Exact job ID match.
  - `customer_id` (string): Filter by customer ID.
  - `owner_id` (string): Filter by business tenant owner ID.
  - `courier_id` (string): Filter by courier/driver ID.
  - `phone` (string): Exact match on customer or recipient phone number.
  - `status` (string): Job status (`pending`, `assigned`, `arrived_at_pickup`, `picked_up`, `arrived_at_dropoff`, `completed`, `cancelled`).
  - `from` (string): RFC 3339 start timestamp.
  - `to` (string): RFC 3339 end timestamp.
  - `page` (int, default: 1): Page number.
  - `limit` (int, default: 20, max: 100): Results per page.

**Response `200 OK`**:
```json
{
  "jobs": [
    {
      "id": "job-98712",
      "tenant_id": "tenant-xyz",
      "customer_id": "usr-101",
      "courier_id": "usr-202",
      "status": "picked_up",
      "sub_status": "in_transit",
      "price": 85.50,
      "payment_method": "cod",
      "created_at": "2026-10-29T08:15:00Z",
      "updated_at": "2026-10-29T08:35:12Z"
    }
  ],
  "total": 1,
  "page": 1,
  "limit": 20
}
```

---

### `GET /admin/jobs/{id}`
Returns the complete V2 job model including full status history, unmasked customer and courier phones (for operator dispatch resolution), address text, reconciliation flags, and recent notifications.

- **Service**: `user-service`
- **Permissions**: Reviewer Token & `X-Internal-Token`
- **Audit Event**: `ADMIN_JOB_VIEWED` (`detail: "viewed full job details for job-98712"`)

**Response `200 OK`**:
```json
{
  "id": "job-98712",
  "tenant_id": "tenant-xyz",
  "customer_id": "usr-101",
  "customer_name": "Ahmed Mansour",
  "customer_phone": "+201012345678",
  "courier_id": "usr-202",
  "courier_name": "Tariq Courier",
  "courier_phone": "+201098765432",
  "status": "arrived_at_dropoff",
  "sub_status": "waiting_for_customer",
  "status_history": [
    {"status": "pending", "timestamp": "2026-10-29T08:15:00Z"},
    {"status": "assigned", "timestamp": "2026-10-29T08:18:22Z"},
    {"status": "picked_up", "timestamp": "2026-10-29T08:30:10Z"},
    {"status": "arrived_at_dropoff", "timestamp": "2026-10-29T08:52:00Z"}
  ],
  "pickup_address": "15 Nile Corniche, Maadi, Cairo",
  "dropoff_address": "44 El-Tahrir St, Dokki, Giza",
  "recipient": {
    "name": "Nour Mahmoud",
    "phone": "+201123456789"
  },
  "package": {
    "description": "Electronics - Laptop charger",
    "weight_kg": 0.8
  },
  "price": 85.50,
  "payment_method": "cod",
  "rating": {
    "score": 5,
    "feedback": "Fast delivery"
  },
  "reconciliation": {
    "stuck_cod": false,
    "gps_dispute": false
  },
  "notifications_sent": [
    {
      "id": "notif-1",
      "type": "job_assigned",
      "sent_at": "2026-10-29T08:18:22Z"
    }
  ]
}
```

---

### `POST /admin/jobs/{id}/cancel`
Cancels a non-terminal job (i.e. not already `completed` or `cancelled`). Performs a CAS state transition, releases courier assignment, dispatches cancellation notifications to parties, and writes an audit event.

- **Service**: `user-service`
- **Permissions**: Reviewer Token & `X-Internal-Token`
- **Request Body**:
```json
{
  "reason": "Customer called support: duplicate order created accidentally"
}
```

**Response `200 OK`**:
```json
{
  "message": "job cancelled successfully",
  "job_id": "job-98712",
  "previous_status": "arrived_at_dropoff",
  "new_status": "cancelled"
}
```

**Audit Event**: `ADMIN_JOB_CANCELLED`
**Error Codes**:
- `invalid_reason` (`400`): Reason missing or >1000 characters.
- `job_not_found` (`404`): No job found with specified ID.
- `invalid_status_transition` (`409`): Job already completed or cancelled.

---

### `POST /admin/jobs/{id}/complete-stuck-cod`
Resolves a stuck COD job where physical delivery and cash handover occurred, but network issues or courier battery failure prevented completion. Reuses the core reconciliation pipeline to close the ledger balance.

- **Service**: `user-service`
- **Permissions**: Reviewer Token & `X-Internal-Token`
- **Request Body**:
```json
{
  "reason": "Verified with both recipient and courier via phone that cash was collected."
}
```

**Response `200 OK`**:
```json
{
  "message": "stuck COD job completed successfully",
  "job_id": "job-98712",
  "previous_status": "arrived_at_dropoff",
  "new_status": "completed"
}
```

**Audit Event**: `ADMIN_JOB_COMPLETED_STUCK_COD`
**Error Codes**:
- `invalid_reason` (`400`): Reason missing or >1000 characters.
- `not_stuck_cod` (`400`): Job does not satisfy stuck COD criteria.
- `job_not_found` (`404`): Specified job does not exist.

---

## 4. Services Marketplace Moderation

### `GET /admin/services`
Lists business services with filters for tenant, moderation status, and photo presence.

- **Service**: `user-service`
- **Permissions**: Reviewer Token & `X-Internal-Token`
- **Query Parameters**:
  - `tenant_id` (string): Filter by tenant.
  - `name` (string): Substring search on service title.
  - `has_photo` (bool): Filter by presence of service photo.
  - `hidden` (bool): Filter by hidden moderation status (`true` / `false`).
  - `page` (int, default: 1): Page number.
  - `limit` (int, default: 20): Items per page.

**Response `200 OK`**:
```json
{
  "services": [
    {
      "id": "svc-555",
      "tenant_id": "tenant-fast-courier",
      "name": "Express Same-Day Delivery",
      "has_photo": true,
      "photo_url": "https://storage.logiclinkeg.tech/services/svc-555.jpg",
      "is_hidden": false,
      "hide_reason": "",
      "created_at": "2026-09-15T10:00:00Z"
    }
  ],
  "total": 1,
  "page": 1,
  "limit": 20
}
```

---

### `POST /admin/services/{id}/hide`
Hides an offensive, non-compliant, or misleading service listing from the public marketplace. Owner receives notification with reason.

- **Service**: `user-service`
- **Permissions**: Reviewer Token & `X-Internal-Token`
- **Request Body**:
```json
{
  "reason": "Prohibited items listed in description"
}
```

**Response `200 OK`**:
```json
{
  "message": "service hidden successfully",
  "service_id": "svc-555",
  "is_hidden": true
}
```
**Audit Event**: `ADMIN_SERVICE_HIDDEN`

---

### `POST /admin/services/{id}/unhide`
Restores a previously hidden service listing to the marketplace.

- **Service**: `user-service`
- **Permissions**: Reviewer Token & `X-Internal-Token`
- **Request Body**:
```json
{
  "reason": "Merchant updated description to comply with terms"
}
```

**Response `200 OK`**:
```json
{
  "message": "service unhidden successfully",
  "service_id": "svc-555",
  "is_hidden": false
}
```
**Audit Event**: `ADMIN_SERVICE_UNHIDDEN`

---

### `POST /admin/services/{id}/photo/remove`
Removes an inappropriate or copyright-infringing service photo. Physically deletes the object from object storage and updates the service record.

- **Service**: `user-service`
- **Permissions**: Reviewer Token & `X-Internal-Token`
- **Request Body**:
```json
{
  "reason": "Inappropriate or copyrighted promotional image"
}
```

**Response `200 OK`**:
```json
{
  "message": "service photo removed successfully",
  "service_id": "svc-555"
}
```
**Audit Event**: `ADMIN_SERVICE_PHOTO_REMOVED`

---

## 5. Subscriptions Queue & Management

### `GET /admin/subscriptions/queue`
Retrieves pending subscription upgrade requests awaiting manual verification of offline bank transfer or cash collection (oldest first).

- **Service**: `user-service`
- **Permissions**: Reviewer Token & `X-Internal-Token`
- **Query Parameters**:
  - `page` (int, default: 1): Page number.
  - `limit` (int, default: 20): Results per page.

**Response `200 OK`**:
```json
{
  "queue": [
    {
      "tenant_id": "tenant-cairo-express",
      "tenant_name": "Cairo Express Logistics",
      "requested_plan": "enterprise",
      "status": "pending_payment",
      "requested_at": "2026-10-28T14:30:00Z",
      "owner_name": "Moustafa Kamel",
      "owner_phone": "+201001122334",
      "owner_email": "moustafa@cairoexpress.com"
    }
  ],
  "total": 1,
  "page": 1,
  "limit": 20
}
```

---

### `POST /admin/subscriptions/activate`
Activates a `pending_payment` subscription upon verifying offline payment receipt.

- **Service**: `user-service`
- **Permissions**: Reviewer Token & `X-Internal-Token`
- **Request Body**:
```json
{
  "tenant_id": "tenant-cairo-express",
  "plan": "enterprise",
  "reason": "Bank transfer receipt #TRX-998812 verified via CIB account"
}
```

**Response `200 OK`**:
```json
{
  "message": "subscription activated successfully",
  "tenant_id": "tenant-cairo-express",
  "plan": "enterprise",
  "status": "active"
}
```
**Audit Event**: `ADMIN_SUBSCRIPTION_ACTIVATED`

---

### `POST /admin/subscriptions/revoke`
Revokes or cancels a subscription with an operator justification.

- **Service**: `user-service`
- **Permissions**: Reviewer Token & `X-Internal-Token`
- **Request Body**:
```json
{
  "tenant_id": "tenant-cairo-express",
  "reason": "Merchant requested downgrade to free tier"
}
```

**Response `200 OK`**:
```json
{
  "message": "subscription revoked successfully",
  "tenant_id": "tenant-cairo-express",
  "status": "inactive"
}
```
**Audit Event**: `ADMIN_SUBSCRIPTION_REVOKED`

---

## 6. Reconciliation Queue & Actions

### `GET /admin/reconciliation/queue`
Retrieves jobs flagged for GPS discrepancy, delivery dispute, or stuck COD. Returns enriched fields required by reviewer consoles: courier `employee_id`, `category`, and human-readable `pickup_address` / `dropoff_address`.

- **Service**: `user-service`
- **Permissions**: Reviewer Token & `X-Internal-Token`
- **Response `200 OK`**:
```json
{
  "items": [
    {
      "job_id": "job-10928",
      "tenant_id": "tenant-xyz",
      "employee_id": "EMP-401",
      "category": "parcel_express",
      "pickup_address": "Building 12, Smart Village, Giza",
      "dropoff_address": "Villa 4, Palm Hills, 6th of October",
      "dispute_type": "gps_discrepancy",
      "distance_meters": 820.5,
      "flagged_at": "2026-10-29T07:20:00Z"
    }
  ],
  "total": 1
}
```

---

### `POST /admin/reconciliation/resolve`
Resolves an active delivery reconciliation dispute.

- **Service**: `user-service`
- **Permissions**: Reviewer Token & `X-Internal-Token`
- **Request Body**:
```json
{
  "job_id": "job-10928",
  "resolution": "approved_override",
  "reason": "Courier parked at gate due to compound security restrictions."
}
```

**Response `200 OK`**:
```json
{
  "message": "reconciliation dispute resolved",
  "job_id": "job-10928",
  "resolution": "approved_override"
}
```
**Audit Event**: `ADMIN_RECONCILIATION_RESOLVED`

---

## 7. Payouts Management

### `GET /admin/payouts`
Lists requested payouts across courier partners.

- **Service**: `user-service`
- **Permissions**: Reviewer Token & `X-Internal-Token`

---

### `POST /admin/payouts/reject`
Rejects a requested payout with mandatory operator reason.

- **Service**: `user-service`
- **Permissions**: Reviewer Token & `X-Internal-Token`
- **Request Body**:
```json
{
  "payout_id": "pay-881",
  "reason": "Discrepancy detected in pending COD settlements"
}
```

**Response `200 OK`**:
```json
{
  "message": "payout rejected successfully",
  "payout_id": "pay-881",
  "status": "rejected"
}
```
**Audit Event**: `ADMIN_PAYOUT_REJECTED`

---

## 8. Tickets & Dispute Management

### `GET /admin/tickets`
Lists user complaints and tickets with status and queue filters.

- **Service**: `chat-service`
- **Permissions**: Reviewer Token & `X-Internal-Token`

---

### `POST /admin/tickets/accept`
Assigns the calling reviewer to handle a complaint ticket.

- **Service**: `chat-service`
- **Permissions**: Reviewer Token & `X-Internal-Token`
- **Request Body**:
```json
{
  "ticket_id": "tkt-0042"
}
```

---

### `POST /admin/tickets/resolve`
Resolves a complaint ticket with resolution notes and closes the chat thread.

- **Service**: `chat-service`
- **Permissions**: Reviewer Token & `X-Internal-Token`
- **Request Body**:
```json
{
  "ticket_id": "tkt-0042",
  "note": "Refund processed to client wallet.",
  "reason": "Merchant confirmed package damage."
}
```

---

### 8.1 Ticket Context Hygiene
Ticket creation validates `context_id` against strict format requirements:
- Allowed: empty string, or alphanumeric characters, hyphens, and underscores up to 64 characters (e.g. `order-1234`, `job_98712`).
- Payloads containing HTML, script tags, or oversized strings reject with:
  `400 Bad Request` (`{"code": "invalid_context_id", "message": "context_id must be alphanumeric/hyphens/underscores up to 64 chars"}`).

### 8.2 WebSocket Token Security
Reviewer WebSocket upgrades (`/chat/ws`) accept credentials without exposing tokens in URL query strings:
- **Subprotocol**: `Sec-WebSocket-Protocol: kyc-console-auth, <reviewer-token>` (Recommended for console clients).
- **Header**: `Authorization: Bearer <reviewer-token>` or `X-Reviewer-Token: <reviewer-token>`.
- **Query Parameter**: `?token=<token>` remains available for backwards compatibility with legacy clients but is marked deprecated.

---

## 9. Accounts & KYB/KYE Document Review

### `GET /auth/accounts`
Lists registered accounts with filters for role (`client`, `business`, `courier`), status (`active`, `suspended`), and keyword search.

- **Service**: `auth-service`
- **Permissions**: Reviewer Token & `X-Internal-Token`

---

### `POST /auth/accounts/suspend`
Suspends an account, terminating active JWT sessions and dispatching push/in-app alert.

- **Service**: `auth-service`
- **Permissions**: Reviewer Token & `X-Internal-Token`
- **Request Body**:
```json
{
  "user_id": "usr-101",
  "reason": "Repeated non-delivery complaints and uncollected COD balances."
}
```

**Audit Event**: `ACCOUNT_SUSPENDED`

---

### `POST /auth/accounts/reactivate`
Reactivates a suspended account.

- **Service**: `auth-service`
- **Permissions**: Reviewer Token & `X-Internal-Token`
- **Request Body**:
```json
{
  "user_id": "usr-101",
  "reason": "Account owner provided proof of identity and settled pending balance."
}
```

**Audit Event**: `ACCOUNT_REACTIVATED`

---

### `POST /auth/reviewer/user-documents`
Retrieves pre-signed secure URLs to inspect encrypted KYB/KYE identity documents. The audit reason is provided via the POST JSON body to prevent URL leakage in proxy access logs (GET with query params remains supported during transition).

- **Service**: `auth-service`
- **Permissions**: Reviewer Token & `X-Internal-Token`
- **Request Body**:
```json
{
  "user_id": "usr-101",
  "reason": "Reviewing commercial register and national ID for KYB tier 2 verification"
}
```

**Response `200 OK`**:
```json
{
  "user_id": "usr-101",
  "documents": [
    {
      "type": "national_id_front",
      "url": "https://storage.logiclinkeg.tech/kyc/usr-101/id_front.jpg?signed=...",
      "expires_at": "2026-10-29T10:00:00Z"
    }
  ]
}
```

**Audit Event**: `DOCUMENT_VIEWED`

---

## 10. Audit Log Viewer

### `GET /admin/audit`
Merges and paginates recorded audit log entries from the primary `audit_log` MongoDB collection in `auth-service`.

- **Service**: `auth-service`
- **Permissions**: Reviewer Token & `X-Internal-Token`
- **Query Parameters**:
  - `actor_id` (string): Filter by reviewer or admin operator ID.
  - `action` (string): Filter by action name (e.g. `ACCOUNT_SUSPENDED`, `DOCUMENT_VIEWED`, `APP_VERSION_CONFIG_UPDATED`).
  - `target_id` (string): Filter by impacted target entity ID.
  - `from` (string): RFC 3339 start timestamp.
  - `to` (string): RFC 3339 end timestamp.
  - `page` (int, default: 1): Page number.
  - `limit` (int, default: 20, max: 100): Records per page.

**Response `200 OK`**:
```json
{
  "entries": [
    {
      "id": "audit-7712",
      "timestamp": "2026-10-29T08:30:15Z",
      "actor_id": "rev-sarah-1",
      "action": "ACCOUNT_SUSPENDED",
      "target_id": "usr-101",
      "reason": "Repeated non-delivery complaints",
      "client_ip": "197.38.12.9"
    }
  ],
  "total": 1,
  "page": 1,
  "limit": 20,
  "notice": "Audit logs reflect all persisted database security actions. Real-time microservice security events without persistence are shipped directly to CloudWatch log groups."
}
```

---

## 11. Platform Version Policy

### `GET /admin/version`
Returns the active minimum supported version, latest release version, and mandatory store download URL enforced by `api-gateway`. Data is persisted in MongoDB (`gateway_db.platform_versions`).

- **Service**: `api-gateway`
- **Permissions**: Reviewer Token & `X-Internal-Token`
- **Response `200 OK`**:
```json
{
  "minimum_supported_version": "1.4.0",
  "latest_version": "1.5.2",
  "download_url": "https://play.google.com/store/apps/details?id=tech.logiclinkeg.app"
}
```

---

### `PUT /admin/version`
Updates the mobile client enforcement policy. Reason is required. The download URL is strictly validated (must be HTTPS and belong to Google Play, Apple App Store, or company domain `*.logiclinkeg.tech`).

- **Service**: `api-gateway`
- **Permissions**: Reviewer Token & `X-Internal-Token`
- **Request Body**:
```json
{
  "minimum_supported_version": "1.5.0",
  "latest_version": "1.5.2",
  "download_url": "https://play.google.com/store/apps/details?id=tech.logiclinkeg.app",
  "reason": "Deprecating API v1 endpoints; requiring security patch in v1.5.0"
}
```

**Response `200 OK`**:
```json
{
  "message": "version policy updated successfully",
  "config": {
    "minimum_supported_version": "1.5.0",
    "latest_version": "1.5.2",
    "download_url": "https://play.google.com/store/apps/details?id=tech.logiclinkeg.app"
  }
}
```

**Audit Event**: `APP_VERSION_CONFIG_UPDATED`
**Error Codes**:
- `invalid_reason` (`400`): Reason missing or >1000 characters.
- `invalid_download_url` (`400`): Download URL fails scheme, domain, or syntax validation.
- `invalid_version_format` (`400`): Semantic version format error or minimum version > latest version.

*(Note: Legacy script automation endpoint `PUT /api/v1/admin/version-config` authenticated via `X-Admin-Token` remains active).*

---

## 12. Admin Announcements & Broadcast Notifications

### `POST /admin/notifications/send`
Dispatches administrative announcements to users across in-app message lists and Firebase Cloud Messaging (FCM) push notifications.

- **Service**: `notification-service`
- **Permissions**: Reviewer Token & `X-Internal-Token`
- **Rate Limit**: 5 sends per hour per reviewer.
- **Request Body Schema**:
```json
{
  "reason": "Emergency platform maintenance notification",
  "audience": {
    "kind": "role",
    "role": "customers"
  },
  "title": {
    "en": "Scheduled System Maintenance",
    "ar": "صيانة مجدولة للنظام"
  },
  "body": {
    "en": "Our services will undergo scheduled maintenance tonight at 2:00 AM.",
    "ar": "ستخضع خدماتنا لصيانة مجدولة الليلة في تمام الساعة 2:00 صباحاً."
  },
  "deep_link": "/plan",
  "dry_run": false,
  "confirm_audience_size": 0,
  "test_user_id": "",
  "idempotency_key": "announce-20261029-01"
}
```

**Fields**:
- `reason` (string, required): 1–1000 characters.
- `audience` (object, required):
  - `kind`: `"user"` (single user), `"role"` (`"customers"`, `"owners"`, `"couriers"`), `"tenant"` (tenant owner + couriers), or `"everyone"`.
  - `user_id` / `email` / `phone`: Required when `kind == "user"`.
  - `role`: Required when `kind == "role"`.
  - `tenant_id`: Required when `kind == "tenant"`.
- `title` (object, required): Both `en` and `ar` strings required (max 120 chars each).
- `body` (object, required): Both `en` and `ar` strings required (max 1000 chars each).
- `deep_link` (string, optional): Internal mobile app navigation route. Free external URLs are rejected. Allowed route prefixes:
  - `/orders/{id}` or `/jobs/{id}`
  - `/plan`
  - `/verification` or `/kyc`
  - `/tickets/{id}`
- `dry_run` (bool, default `false`): When `true`, resolves audience size without creating a send job or dispatching messages.
- `confirm_audience_size` (int, optional): When `kind == "everyone"` or resolved audience size is $\ge 1,000$, this field is mandatory and must match the exact resolved count.
- `test_user_id` (string, optional): "Send test to me" mode. Dispatches the notification solely to the specified user ID to preview formatting before full broadcast.
- `idempotency_key` (string, optional): Deduplicates accidental double-clicks. Replays return the existing job.

**Response `202 Accepted`** (Queued for background fan-out):
```json
{
  "job_id": "send-1793255745373574323",
  "status": "queued",
  "audience_size": 450,
  "message": "admin notification queued for delivery"
}
```

**Response `200 OK`** (Dry Run):
```json
{
  "dry_run": true,
  "audience_size": 450,
  "audience": {
    "kind": "role",
    "role": "customers"
  }
}
```

**Error Codes**:
- `invalid_reason` (`400`): Reason missing or >1000 characters.
- `invalid_title` (`400`): Missing or oversized Arabic or English title.
- `invalid_body` (`400`): Missing or oversized Arabic or English body.
- `invalid_deep_link` (`400`): Deep link does not match allowed internal routes.
- `confirmation_required` (`400`): `confirm_audience_size` missing or does not match audience total.
- `rate_limit_exceeded` (`429`): Operator exceeded 5 sends/hour budget.

---

### `GET /admin/notifications/sends`
Lists previous administrative notification send jobs with status and delivery counters.

- **Service**: `notification-service`
- **Permissions**: Reviewer Token & `X-Internal-Token`
- **Query Parameters**:
  - `page` (int, default: 1): Page number.
  - `limit` (int, default: 20): Results per page.

**Response `200 OK`**:
```json
{
  "sends": [
    {
      "id": "send-1793255745373574323",
      "created_at": "2026-10-29T09:35:45Z",
      "reviewer_id": "rev-sarah-1",
      "reason": "Emergency platform maintenance notification",
      "audience": {
        "kind": "role",
        "role": "customers"
      },
      "audience_size": 450,
      "status": "completed",
      "sent_count": 450,
      "failed_count": 0,
      "is_test_send": false,
      "deep_link": "/plan"
    }
  ],
  "total": 1,
  "page": 1,
  "limit": 20
}
```

---

### `GET /admin/notifications/sends/{id}`
Returns the granular delivery status and counters of an individual send job.

- **Service**: `notification-service`
- **Permissions**: Reviewer Token & `X-Internal-Token`

---

## 13. Mobile Companion App Contract (`admin_announcement`)

This section specifies the frontend contract for the Flutter client application to consume notifications produced by the admin announcements system.

### 13.1 Notification Item Model
Admin announcements are delivered with:
- `type`: `"admin_announcement"`
- `event_type`: `"admin_announcement"`
- `params`:
  - `title_en`: English title
  - `body_en`: English message body
  - `title_ar`: Arabic title
  - `body_ar`: Arabic message body
  - `deep_link`: Optional internal route string (e.g. `"/plan"`, `"/orders/ord-123"`)

### 13.2 Visual & Rendering Requirements
1. **Iconography**:
   - The notification list item MUST display a dedicated megaphone / broadcast announcement badge (e.g. `Icons.campaign_outlined` or `Icons.announcement_outlined`) distinct from transactional job alerts.
2. **Localization**:
   - The app must read the device's active locale.
   - For `ar` or `ar_EG`, render `params["title_ar"]` and `params["body_ar"]` with RTL alignment.
   - For any other locale, render `params["title_en"]` and `params["body_en"]`.
3. **Deep Link Navigation**:
   - When tapped, if `params["deep_link"]` is present:
     - `/plan` $\rightarrow$ Navigates to Subscription Plans page.
     - `/verification` $\rightarrow$ Navigates to KYC / Business Verification submission screen.
     - `/orders/{id}` or `/jobs/{id}` $\rightarrow$ Opens Order Details screen for `{id}`.
     - `/tickets/{id}` $\rightarrow$ Opens Support Ticket chat screen for `{id}`.
   - If `deep_link` is absent or empty, tapping marks the notification as read and expands or displays the full announcement text in a bottom sheet dialog.
