# Admin & Reviewer Operations API Reference

This specification defines the HTTP API contract exposed by `saas-core` for the KYC Reviewer Console (`kyc-reviewer-console`), companion mobile apps, and edge infrastructure. It serves as the authoritative contract for **CONSOLE-V2** and related administrative tooling.

---

## 1. Edge Security & Authentication Architecture

### 1.1 Edge Gate (Caddy `basic_auth`)
The console frontend and edge ingress at `kyc.logiclinkeg.tech` enforce HTTP Basic Authentication at the Caddy edge layer before any traffic reaches internal services:
- **Environment Variables**:
  - `KYC_CONSOLE_BASIC_AUTH_USER`: Username for the edge gate.
  - `KYC_CONSOLE_BASIC_AUTH_HASH`: Bcrypt password hash generated using `caddy hash-password`.
- **Fail-Closed Behavior**: If `KYC_CONSOLE_BASIC_AUTH_HASH` or `KYC_CONSOLE_BASIC_AUTH_USER` is empty or unset, Caddy responds with `503 Service Unavailable` and the body `Console basic auth is not configured`.
- **Security Headers** (set by Caddy on every `kyc.logiclinkeg.tech` response, `infrastructure/deploy/Caddyfile`):
  - `Strict-Transport-Security: max-age=31536000; includeSubDomains; preload`
  - `Content-Security-Policy: frame-ancestors 'none';`
  - `X-Frame-Options: DENY`
  - Caddy does not add `X-Content-Type-Options`; the console sets its own response headers.
- **Container Pinning**: Compose services pin `${KYC_CONSOLE_IMAGE_TAG}` with no `latest` fallback; compose preflight fails if unset.

### 1.2 Reviewer Authentication Contract
All administrative endpoints require two authentication headers:
1. `X-Internal-Token`: Pre-shared service secret matching `INTERNAL_SERVICE_TOKEN`. The gateway strips it from every client request, so reviewer endpoints are only reachable on the internal network (the console calls each service directly over mTLS).
2. `X-Reviewer-Token`: Reviewer bearer token issued to verified human operators.

**Verification Flow**:
Downstream services authenticate requests via `auth-service` at `GET /auth/reviewer/verify`:
- Checks `X-Internal-Token` and `X-Reviewer-Token`.
- Returns HTTP 200 with reviewer metadata (`{"id": "...", "name": "..."}`).
- Rejects a bad internal token, a missing or invalid reviewer token with `401 Unauthorized` (`{"error": "unauthorized"}`), and a locked-out key (section 1.3) with `429 Too Many Requests` (`{"error": "too many failed reviewer login attempts. Please try again in N seconds."}`).
- The calling services (user, chat, notification, gateway) answer `401` with their own plain `{"error": ...}` body when verification fails.

### 1.3 Rate Limiting Architecture
`authenticateReviewer` in auth-service (used by `/auth/reviewer/verify` and every reviewer endpoint) counts failed attempts on three keys:
- **Per client IP**: 3 failures lock the key for 5 minutes. The key is the `X-Console-Client-IP` header **only** when the request also carries a valid `X-Internal-Token` and the value parses as an IP; otherwise it is the TCP peer (`RemoteAddr`). `X-Forwarded-For` and `X-Real-IP` are never used for this key: rotating them used to reset the budget.
- **Per token hash prefix** (`tok_prefix:` + first 16 hex chars of SHA-256 of the presented token): 3 failures lock that prefix for 5 minutes, whatever IP the attempts come from.
- **Global ceiling**: 20 failures across all keys lock reviewer authentication for everyone for 5 minutes.

The console must set `X-Console-Client-IP` to the reviewer's browser IP (as seen by the console behind Caddy). Until it does, every console request keys on the console container IP, so the per-IP budget is shared by all reviewers (the token-prefix and global limits are unaffected). The gateway's reviewer version handler (section 11) applies the same rule: it forwards `X-Console-Client-IP` from the console after its own internal token check, or the peer IP, and never forwards a client `X-Forwarded-For`.

### 1.4 Mutation Contract & Safety
- **Mandatory Reason**: every mutation below except subscription activation and ticket accept takes a body field `reason` (1-1000 characters after trimming). user-service answers `400` with `{"error": "reason is required"}` or `{"error": "reason cannot exceed 1000 characters"}`; the gateway with `{"error": "reason is required (1-1000 characters)"}`; notification-service with `code: invalid_reason`.
- **Error bodies**: user-service, chat-service and the gateway answer `{"error": "<message>"}` without a `code`; notification-service adds `code` and `message`; `WriteSafeError` paths add `code` and `request_id`.
- **Compare-And-Swap (CAS)**: state changes are conditional updates on the current status. A job or record in the wrong state answers `409 Conflict` with the store error as `error`.
- **Audit**: every mutation and unmasked view writes an `admin_audit` record in the owning service (section 10) and still emits its `ShipSecurityEvent`.
- **PII Protection**: `GET /admin/jobs/{id}` returns customer, courier and recipient phones unmasked (audited as `job.view`); `GET /admin/jobs` returns recipient phones unmasked (audited as `job.search` when a page contains any). Other reviewer listings do not return phones, except the subscription queue's owner contact.

---

## 2. Overview

### `GET /admin/overview`
Aggregates operational counts. user-service computes its own figures and asks auth-service (`/auth/internal/overview-stats`) and chat-service (`/chat/internal/overview-stats`) for theirs, each with a 2 second timeout. A figure from a service that fails or times out is the string `"unavailable"` instead of a number; the response is still `200`.

- **Service**: `user-service` (also `GET /users/admin/overview`)
- **Permissions**: Reviewer Token & `X-Internal-Token`
- **Query Parameters**: None

**Response `200 OK`**:
```json
{
  "pending_kyb_kye": 14,
  "pending_payment_subscriptions": 3,
  "open_tickets": 5,
  "assigned_tickets": 2,
  "gps_disputes": 2,
  "stuck_cod_jobs": 1,
  "jobs_today": {
    "pending_dispatch": 5,
    "active": 12,
    "completed": 45,
    "cancelled": 2
  },
  "new_accounts_today": 18,
  "new_accounts_7d": 114,
  "suspended_accounts": "unavailable"
}
```
`pending_kyb_kye`, `new_accounts_today`, `new_accounts_7d` and `suspended_accounts` come from auth-service, `open_tickets` and `assigned_tickets` from chat-service. `jobs_today` counts today's jobs by `status`.

**Audit**: `ShipSecurityEvent` `ADMIN_OVERVIEW_VIEWED` only (no `admin_audit` record; counts only).

---

## 3. Jobs Lookup & Mutations

### `GET /admin/jobs`
Searches jobs across tenants, newest first.

- **Service**: `user-service` (also `GET /users/admin/jobs`)
- **Permissions**: Reviewer Token & `X-Internal-Token`
- **Query Parameters** (all optional, combined with AND):
  - `job_id` (aliases `id`, `search`): Exact job ID.
  - `customer_id` (alias `user_id`), `owner_id` (alias `tenant_id`), `courier_id` (alias `employee_id`).
  - `phone`: Exact match on the customer's phone (looked up in auth-service) or the recipient phone.
  - `status`: A job status: `pending`, `pending_dispatch`, `unavailable`, `awaiting_price_response`, `active`, `completed`, `cancelled`, `escrow_reconciliation_required`. Courier progress (picked up, in transit, ...) is in `sub_status`, not `status`.
  - `from` (alias `start_date`), `to` (alias `end_date`): RFC 3339 or `YYYY-MM-DD`, on `created_at`.
  - `page` (default 1), `limit` (default 20, 1-100; other values fall back to 20).

**Response `200 OK`**:
```json
{
  "jobs": [
    {
      "id": "job-98712",
      "status": "active",
      "sub_status": "in_transit",
      "owner_id": "tenant-xyz",
      "user_id": "usr-101",
      "employee_id": "usr-202",
      "service_id": "svc-555",
      "location": {"lat": 30.0444, "lng": 31.2357, "address": "..."},
      "destination": {"lat": 30.0500, "lng": 31.2400, "address": "..."},
      "payment_method": "cod",
      "suggested_price": 85.5,
      "customer_name": "Mona",
      "recipient": {"name": "Mona Recipient", "phone": "+201011112222"},
      "created_at": "2026-10-29T08:15:00Z",
      "updated_at": "2026-10-29T08:35:12Z"
    }
  ],
  "total": 1,
  "page": 1,
  "limit": 20
}
```
Optional fields (`sub_status`, `employee_id`, `agreed_price`, `actual_cash_amount`, `locked_escrow_amount`, `customer_name`, `recipient`, `package_details`, `distance_review`) are omitted when empty.

**Audit**: `ShipSecurityEvent` `ADMIN_JOBS_LISTED`, plus an `admin_audit` `job.search` record when the page returns any recipient phone (unmasked).

---

### `GET /admin/jobs/{id}`
Returns the complete V2 job model including full status history, unmasked customer and courier phones (for operator dispatch resolution), address text, reconciliation flags, and recent notifications.

- **Service**: `user-service`
- **Permissions**: Reviewer Token & `X-Internal-Token`
- **Audit**: `admin_audit` record `job.view` (target `job`) and `ShipSecurityEvent` `ADMIN_JOB_VIEWED`. Every call is recorded because the response carries unmasked phones.
- **Response fields** (`AdminJobDetailResponse`): `id`, `status`, `sub_status`, `status_history`, `location`, `destination`, `current_location`, `waypoints`, `recipient`, `package_details` (and `package`), `price` (object), `suggested_price`, `agreed_price`, `actual_cash_amount`, `locked_escrow_amount`, `payment_method`, `tenant`, `owner_id`, `courier`, `employee_id`, `courier_phone`, `customer_id`, `user_id`, `customer_name`, `customer_phone`, `ratings`, `reconciliation_flags`, `notifications` (recent notifications for the job from notification-service), `created_at`, `updated_at`. The example below is abridged.

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
Cancels a job on behalf of support. Releases courier locks, clears any pending cancellation request, appends a `status_history` entry (`actor_role: admin`) and notifies the parties. A wallet-paid job (not `cod`, not `pending_dispatch`) with locked escrow has the escrow refunded to the tenant's withdrawable balance.

- **Service**: `user-service` (also `POST /users/admin/jobs/{id}/cancel`)
- **Permissions**: Reviewer Token & `X-Internal-Token`
- **Cancellable statuses**: `pending`, `pending_dispatch`, `awaiting_price_response`, `active`, `escrow_reconciliation_required`. `completed` and `cancelled` answer `409` (`job already in terminal state`); `unavailable` answers `409` (`job state conflict during update`).
- **Request Body** (`job_id` in the body is accepted instead of the path; price or address fields are rejected with `400 editing prices or addresses is not allowed`):
```json
{
  "reason": "Customer called support: duplicate order created accidentally"
}
```

**Response `200 OK`**:
```json
{
  "success": true,
  "message": "job cancelled successfully",
  "job_id": "job-98712",
  "status": "cancelled"
}
```

**Audit**: `admin_audit` `job.cancel` (target `job`, with the reason) and `ShipSecurityEvent` `ADMIN_JOB_CANCELLED`.
**Errors** (`{"error": ...}`):
- `400`: `reason is required`, `reason cannot exceed 1000 characters`, `job_id is required`, `invalid request body`.
- `404`: `job not found`.
- `409`: the job is not in a cancellable status (see above).

---

### `POST /admin/jobs/{id}/complete-stuck-cod`
Completes one COD job stuck in `escrow_reconciliation_required` (for example the courier's phone died after the cash handover) through the same repair path as the FIX-COD-RECON sweep, records the cash amount and releases the courier lock.

- **Service**: `user-service` (also `POST /users/admin/jobs/{id}/complete-stuck-cod`)
- **Permissions**: Reviewer Token & `X-Internal-Token`
- **Preconditions**: `payment_method` is `cod`, `status` is `escrow_reconciliation_required`, and no escrow is locked. Anything else answers `409` (`job is not a stuck COD reconciliation job`).
- **Request Body**:
```json
{
  "reason": "Verified with both recipient and courier via phone that cash was collected."
}
```

**Response `200 OK`**:
```json
{
  "success": true,
  "message": "stuck COD job completed successfully",
  "job_id": "job-98712",
  "status": "completed",
  "actual_cash_amount": 85.5
}
```

**Audit**: `admin_audit` `job.complete_stuck_cod` and `ShipSecurityEvent` `ADMIN_JOB_COMPLETED_STUCK_COD`.
**Errors** (`{"error": ...}`): `400` reason/body errors as for cancel; `404` `job not found`; `409` precondition not met or concurrent change.

---

## 4. Services Marketplace Moderation

### `GET /admin/services`
Lists business services with filters for tenant, moderation status, and photo presence.

- **Service**: `user-service`
- **Permissions**: Reviewer Token & `X-Internal-Token`
- **Query Parameters**:
  - `tenant_id` (alias `tenant`): Filter by tenant.
  - `name`: Search on the service name.
  - `has_photo` (`true` / `false`): Filter by presence of a photo.
  - `hidden` (`true` / `false`): Filter by moderation status.
  - `page` (default 1), `limit` (default 20).

**Response `200 OK`**:
```json
{
  "services": [
    {
      "id": "svc-555",
      "tenant_id": "tenant-fast-courier",
      "name": "Express Same-Day Delivery",
      "photo_url": "https://storage.logiclinkeg.tech/services/svc-555.jpg",
      "is_hidden": true,
      "hidden_reason": "Prohibited items listed in description",
      "hidden_by": "rev-sarah-1",
      "hidden_notice": "hidden by support: Prohibited items listed in description"
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
  "success": true,
  "service_id": "svc-555",
  "is_hidden": true,
  "hidden_reason": "Prohibited items listed in description",
  "hidden_notice": "hidden by support: Prohibited items listed in description",
  "message": "service hidden successfully"
}
```
**Audit**: `admin_audit` `service.hide` and `ShipSecurityEvent` `ADMIN_SERVICE_HIDDEN`. Hidden services are left out of the public marketplace listing.
**Errors** (`{"error": ...}`): `400` `service_id is required` / reason errors; `404` `service not found`.

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
  "success": true,
  "service_id": "svc-555",
  "is_hidden": false,
  "message": "service unhidden successfully"
}
```
**Audit**: `admin_audit` `service.unhide` and `ShipSecurityEvent` `ADMIN_SERVICE_UNHIDDEN`.

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
  "success": true,
  "service_id": "svc-555",
  "message": "service photo removed successfully"
}
```
**Audit**: `admin_audit` `service.photo_remove` and `ShipSecurityEvent` `ADMIN_SERVICE_PHOTO_REMOVED`.
**Errors** (`{"error": ...}`): `400` `service has no photo to remove` / reason errors; `404` `service not found`.

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
      "id": "sub-771",
      "subscription_id": "sub-771",
      "tenant_id": "tenant-cairo-express",
      "tenant_name": "Cairo Express Logistics",
      "requested_plan": "pro",
      "requested_at": "2026-10-28T14:30:00Z",
      "owner_contact": {
        "username": "mkamel",
        "name": "Moustafa Kamel",
        "company_name": "Cairo Express Logistics",
        "email": "moustafa@cairoexpress.com",
        "phone": "+201001122334"
      },
      "tier": "pro",
      "status": "pending_payment",
      "started_at": "2026-10-28T14:30:00Z"
    }
  ],
  "subscriptions": ["... same items as queue ..."],
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
**Audit**: `admin_audit` `subscription.activate` and `ShipSecurityEvent` `ADMIN_SUBSCRIPTION_ACTIVATED`.

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
**Audit**: `admin_audit` `subscription.revoke` and `ShipSecurityEvent` `ADMIN_SUBSCRIPTION_REVOKED`.

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
**Audit**: `admin_audit` `reconciliation.resolve` and `ShipSecurityEvent` `ADMIN_ESCROW_RECONCILIATION_RESOLVED`.

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
**Audit**: `admin_audit` `payout.reject` and `ShipSecurityEvent` `ADMIN_PAYOUT_REJECTED`.

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
- **Audit**: `admin_audit` `ticket.accept` and `ShipSecurityEvent` `ADMIN_TICKET_ACCEPTED`.

---

### `POST /admin/tickets/resolve`
Resolves a complaint ticket with resolution notes and closes the chat thread.

- **Service**: `chat-service`
- **Permissions**: Reviewer Token & `X-Internal-Token`
- **Request Body**:
```json
{
  "ticket_id": "tkt-0042",
  "resolution_note": "Refund processed to client wallet."
}
```
`resolution_note` is required (1-1000 characters); it is posted in the ticket chat, sent to the customer and stored as the audit `reason`.
- **Audit**: `admin_audit` `ticket.resolve` and `ShipSecurityEvent` `ADMIN_TICKET_RESOLVED`.

---

### 8.1 Ticket Context Hygiene
Ticket creation validates `context_id` against strict format requirements:
- Allowed: empty string, or alphanumeric characters, hyphens, and underscores up to 64 characters (e.g. `order-1234`, `job_98712`).
- Payloads containing HTML, script tags, or oversized strings reject with:
  `400 Bad Request` (`{"error": "invalid_context_id", "code": "invalid_context_id", "message": "context_id must be empty or a valid identifier format (up to 64 alphanumeric characters, dashes, and underscores)"}`).

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

**Audit**: `admin_audit` `account.suspend` and `ShipSecurityEvent` `ACCOUNT_SUSPENDED` (the employee `audit_log` entry `ACCOUNT_SUSPENDED` is still written too).

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

**Audit**: `admin_audit` `account.reactivate` and `ShipSecurityEvent` `ACCOUNT_REACTIVATED` (plus the employee `audit_log` entry).

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
  "email": "owner@example.com",
  "username": "owner101",
  "role": "owner",
  "kyc_status": "pending",
  "id_front_url": "<signed short-lived URL for GET /auth/documents/view>",
  "id_back_url": "<signed short-lived URL for GET /auth/documents/view>",
  "selfie_url": "<signed short-lived URL for GET /auth/documents/view>",
  "business_proof_url": "<signed short-lived URL for GET /auth/documents/view>"
}
```
URLs are signed and short-lived; a document that cannot be signed is reported in `document_errors` instead.

**Audit**: `admin_audit` `user_documents.view` (with the reason), `ShipSecurityEvent` `USER_DOCUMENTS_RETRIEVED` and one `DOCUMENT_VIEWED` per signed document. Opening a signed URL (`GET /auth/documents/view`) writes `document.view`.

---

## 10. Audit Log Viewer

### 10.1 Where records are stored
Every reviewer mutation and every unmasked view writes one record to the **owning service's own** `admin_audit` collection (no service reads another service's database). The record is written after the action succeeded; if the write fails the action is not undone, and the service logs the failure and ships an `ADMIN_AUDIT_WRITE_FAILED` security event. The existing `ShipSecurityEvent` calls are unchanged and still go to the log stream.

| Field | Meaning |
| :--- | :--- |
| `id` | Random record id. |
| `source` | Owning service: `auth-service`, `user-service`, `chat-service`, `notification-service`, `api-gateway`. |
| `actor_id` | Reviewer id returned by `/auth/reviewer/verify`. |
| `action` | One of the action names below. |
| `target_type`, `target_id` | The entity acted on (`job`, `service`, `subscription`, `payout`, `ticket`, `notification_send`, `version_policy`, `user`, `document`). |
| `reason` | The reviewer's reason, when the endpoint takes one. |
| `details` | Short extra context (e.g. `decision=refund_to_customer`, `tenant=...`). |
| `request_id` | The caller's `X-Request-ID` when it matches `[A-Za-z0-9._-]{1,64}`, else a generated id. |
| `created_at` | UTC time the record was written. |

**Action names** (one scheme: `<resource>.<verb>`, lower snake case):

| Action | Service | Written by |
| :--- | :--- | :--- |
| `job.search` | user-service | `GET /admin/jobs` when the page returns at least one unmasked recipient phone (`details` lists those job ids) |
| `job.view` | user-service | `GET /admin/jobs/{id}` (unmasked phones) |
| `job.cancel` | user-service | `POST /admin/jobs/{id}/cancel` |
| `job.complete_stuck_cod` | user-service | `POST /admin/jobs/{id}/complete-stuck-cod` |
| `service.hide` | user-service | `POST /admin/services/{id}/hide` |
| `service.unhide` | user-service | `POST /admin/services/{id}/unhide` |
| `service.photo_remove` | user-service | `POST /admin/services/{id}/photo/remove` |
| `subscription.activate` | user-service | `POST /admin/subscriptions/activate` |
| `subscription.revoke` | user-service | `POST /admin/subscriptions/revoke` |
| `payout.reject` | user-service | `POST /admin/payouts/reject` |
| `reconciliation.resolve` | user-service | `POST /admin/reconciliation/resolve` |
| `ticket.accept` | chat-service | `POST /admin/tickets/accept` |
| `ticket.resolve` | chat-service | `POST /admin/tickets/resolve` |
| `notification.send` | notification-service | `POST /admin/notifications/send` (real and test sends; dry runs write nothing) |
| `version.update` | api-gateway | `PUT`/`POST /admin/version` |
| `kyc.review` | auth-service | `POST /auth/kyb-kye/review` |
| `account.suspend` | auth-service | `POST /auth/accounts/suspend` |
| `account.reactivate` | auth-service | `POST /auth/accounts/reactivate` |
| `user_documents.view` | auth-service | `POST`/`GET /auth/reviewer/user-documents` |
| `document.view` | auth-service | `GET /auth/documents/view` |

Records written before this change are not migrated: earlier KYC reviews and suspensions remain in auth-service's employee `audit_log` (served by `/auth/audit-log`) and in the security event log stream.

### 10.2 Per-service source endpoints (internal)
`GET /users/internal/admin-audit`, `GET /chat/internal/admin-audit`, `GET /notifications/internal/admin-audit` and the gateway's `GET /admin/internal/audit` (which, like `/admin/version`, also requires an internal-CA client certificate) return `{"entries": [...], "total": N}` for one service. They require `X-Internal-Token` only (auth-service has already authenticated the reviewer) and accept `actor_id`, `action`, `target_id`, `from`, `to` (RFC 3339) and `limit` (1-1000, default 100). Only auth-service calls them.

### `GET /admin/audit`
Merges the records of all five services, newest first (`created_at`, then `id`).

- **Service**: `auth-service` (also `GET /auth/admin/audit`)
- **Permissions**: Reviewer Token & `X-Internal-Token`
- **Query Parameters**:
  - `actor_id` (string; aliases `actor`, `reviewer_id`, `employee_id`): Filter by reviewer id.
  - `action` (string): Exact action name from the table above.
  - `target_id` (string; aliases `target`, `user_id`, `tenant_id`): Filter by target id.
  - `from` / `start_date`, `to` / `end_date` (RFC 3339 or `YYYY-MM-DD`), or `date` (`YYYY-MM-DD`, that whole UTC day).
  - `page` (int, default 1) and `limit` (int, default 20, max 100). `page * limit` must be at most 1000, else `400`.
- **Fan-out**: auth-service reads its own collection and calls the four internal endpoints in parallel, each with a 3 second timeout, asking each for its newest `page * limit` matches. A source that errors, answers non-200 or times out is reported as `"unavailable"` in `sources`; the response is still `200` with the other sources' records, and `total` counts only the sources that answered.

**Response `200 OK`**:
```json
{
  "entries": [
    {
      "id": "6f1c2a9e0b7d4c3a8e5f1b2c",
      "source": "user-service",
      "actor_id": "rev-sarah-1",
      "action": "job.cancel",
      "target_type": "job",
      "target_id": "job-8812",
      "reason": "Courier vehicle broke down",
      "details": "owner=tenant-55",
      "request_id": "c0ffee12ab34",
      "created_at": "2026-10-29T08:30:15Z"
    }
  ],
  "total": 1,
  "page": 1,
  "limit": 20,
  "sources": {
    "auth-service": "ok",
    "user-service": "ok",
    "chat-service": "ok",
    "notification-service": "unavailable",
    "api-gateway": "ok"
  }
}
```

---

## 11. Platform Version Policy

### `GET /admin/version`
Returns the active minimum supported version, latest release version, and mandatory store download URL enforced by `api-gateway`. Data is persisted in MongoDB (`gateway_db.platform_versions`).

- **Service**: `api-gateway`
- **Permissions**: Reviewer Token & `X-Internal-Token`
- **Reachability**: internal network only, enforced three ways. (1) The gateway answers `403` (`internal client certificate required`) unless the TLS connection presented a client certificate signed by the internal CA (`TLS_CA_PATH`); the console and auth-service present theirs, the edge Caddy hop and internet clients do not. (2) The production edge answers `404` for `/admin`, `/admin/*` and `/api/v1/admin/*` on `api.logiclinkeg.tech` (staging blocks `/admin`, `/admin/*`). (3) There is no `/api/v1/admin/version` alias: the gateway's own mux handlers do not go through the proxy's `X-Internal-Token` strip. The console calls `${GATEWAY_INTERNAL_URL}/admin/version` (`https://api-gateway:${API_GATEWAY_PORT}` on saas-net, SNI `api-gateway`, which gets the gateway's internal certificate).
- **Response `200 OK`**:
```json
{
  "id": "global",
  "latest_version": "1.5.2",
  "minimum_supported_version": "1.4.0",
  "enforce_minimum_version": false,
  "download_url": "https://play.google.com/store/apps/details?id=tech.logiclinkeg.app",
  "revision": 7,
  "updated_at": "2026-10-29T08:30:15Z"
}
```

---

### `PUT /admin/version` (also `POST`)
Updates the mobile client version policy. `reason` is required (1-1000 characters). Fields left empty keep their current value; `enforce_minimum_version` is changed only when present. Both versions must be semver; `download_url` must be an `https` URL on `github.com` or `play.google.com` (SEC-02).

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
  "message": "version configuration updated successfully",
  "config": {
    "id": "global",
    "latest_version": "1.5.2",
    "minimum_supported_version": "1.5.0",
    "enforce_minimum_version": false,
    "download_url": "https://play.google.com/store/apps/details?id=tech.logiclinkeg.app",
    "revision": 8,
    "updated_at": "2026-10-29T09:00:00Z"
  }
}
```

**Audit**: `admin_audit` `version.update` (target `version_policy` / `global`, in `gateway_db.admin_audit`) and `ShipSecurityEvent` `ADMIN_VERSION_CONFIG_CHANGED`.
**Errors** (`{"error": ...}`):
- `400`: `reason is required (1-1000 characters)`, `invalid JSON body`, `invalid download_url: ...`, `invalid latest_version: ...` / `invalid minimum_supported_version: ...`.
- `401`: missing/invalid internal or reviewer token; `429` when auth-service rate-limits the reviewer.
- `403`: no internal client certificate (see Reachability).
- `503`: the MongoDB write failed; nothing was saved (section 11.1).

*(Note: Legacy script automation endpoint `PUT /api/v1/admin/version-config` authenticated via `X-Admin-Token` remains active).*

### 11.1 Storage and failure behaviour
- With `MONGO_URI` set, the gateway connects to MongoDB, pings it and seeds `platform_versions` at startup. If any of that fails it **refuses to start** (`[GATEWAY] FATAL: refusing to start: version store unavailable ...`), except with `APP_ENV=local` or `APP_ENV=test`, where it logs a loud `WARNING ... falling back to IN-MEMORY stores` and keeps running in memory (version changes and gateway admin audit records are then lost on restart). Without `MONGO_URI` both stores are in memory.
- A version update whose MongoDB write fails answers `503` (`code: service_unavailable`) on both `PUT /admin/version` and `PUT /api/v1/admin/version-config`. The new policy is not cached, so the gateway never reports or serves an unsaved change.

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

**Response `200 OK`** (idempotent replay: an earlier send used the same `idempotency_key`): `{"job_id", "status", "audience_size", "message": "idempotent replay of existing send job", "send": {...}}`. No new send and no new audit record.

**Audit**: real and test sends write `admin_audit` `notification.send` (target `notification_send` / `job_id`, with the reason and `audience=<kind> size=<n> test=<bool>` in `details`) and `ShipSecurityEvent` `ADMIN_NOTIFICATION_SENT`. Dry runs write neither.

**Error Codes**:
- `invalid_reason` (`400`): Reason missing or >1000 characters.
- `invalid_title` (`400`): Missing or oversized Arabic or English title.
- `invalid_body` (`400`): Missing or oversized Arabic or English body.
- `invalid_deep_link` (`400`): Deep link does not match allowed internal routes.
- `invalid_audience` (`400`): `audience.kind` is not `user`, `role`, `tenant` or `everyone`.
- `confirmation_required` (`400`): `confirm_audience_size` missing or does not match audience total (not required for test sends).
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
