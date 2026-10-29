# Worklog: ADMIN-API — reviewer console operator endpoints and edge security gate

## Task and scope
- **Task ID**: ADMIN-API
- **Items covered**: Items 1, 2, 3, 4, 5, 6, 7, 8, 9, 9b, 9c, 9d, 10, 11
- **Lane**:
  - `services/api-gateway/**`
  - `services/auth-service/**`
  - `services/user-service/**`
  - `services/chat-service/**`
  - `services/notification-service/**`
  - `infrastructure/deploy/**`
  - `infrastructure/staging/**`
  - `shared/infra/docgen/**`
  - `docs/api/ADMIN_API.md`
  - `docs/APPLICATION_MAP.md`
  - `tests/e2e/admin_api_test.go` (new e2e test suite)
  - `tests/e2e/e2e_helpers.go` (ConnectConsoleWS subprotocol only)
  - `docs/worklog/ADMIN-API.md` (this file)
- **Untouched paths**: `frontend/**`, `Makefile`, `scripts/**`, `.githooks/**`, `.github/workflows/ci.yml`, `docs/RELEASE.md`, `docs/WORKFLOW.md`, `AI_CONTEXT.md`, and `docs/changelog/**`.
- **Reviewer Contract**: `X-Internal-Token` + `X-Reviewer-Token` authenticated via `/auth/reviewer/verify`. Mutations require explicit reasons (1–1000 characters), atomic CAS state transitions, audit trail logging, and `ShipSecurityEvent`.

---

## Decisions taken per item

- **Item 1: Edge Caddy basic_auth and Security Headers**:
  - Pinned `caddy` in `infrastructure/deploy/Caddyfile` for `kyc.logiclinkeg.tech` using HTTP basic authentication configured with `KYC_CONSOLE_BASIC_AUTH_HASH` and `KYC_CONSOLE_BASIC_AUTH_USER`.
  - Fail-closed security: If `KYC_CONSOLE_BASIC_AUTH_HASH` or `KYC_CONSOLE_BASIC_AUTH_USER` is empty or unset, Caddy responds immediately with HTTP `503 Service Unavailable`.
  - Added strict security headers at edge: `Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"`, `X-Content-Type-Options "nosniff"`, `X-Frame-Options "DENY"`, `Content-Security-Policy "frame-ancestors 'none'"`.
  - Pinned console image tag `${KYC_CONSOLE_IMAGE_TAG}` in `docker-compose.prod.yml` with no fallback to `latest` (preflight deploy failure if unset). Documented owner instructions in `DEPLOYMENT.md` and `.env.example`.

- **Item 2: Reviewer Rate Limiting Behind Console**:
  - In `auth-service` (`/auth/reviewer/verify`), all console requests arrive from the console container's proxy IP.
  - Implemented rate limiting keying failed attempts by `reviewer_token_hash_prefix` + forwarded client IP (`X-Forwarded-For` / `X-Real-IP`), trusted exclusively when valid internal token is presented, with a global ceiling limit.

- **Item 3: Overview Aggregation**:
  - Implemented `GET /admin/overview` and `GET /users/admin/overview` in `user-service`.
  - Aggregates user-service domain metrics (pending payment subscriptions, GPS disputes, stuck COD jobs, jobs today grouped by status, new accounts today/7d, suspended accounts).
  - Queries `auth-service` for pending KYB/KYE counts and `chat-service` for open/assigned ticket counts with isolated 2.5-second HTTP timeouts and graceful `"unavailable"` degradation instead of failing the entire overview response.

- **Item 4: Jobs Lookup & Full Detail View**:
  - Implemented `GET /admin/jobs` with multi-field search (job ID, customer/owner/courier ID, exact phone match, status, date range; paginated).
  - Implemented `GET /admin/jobs/{id}` returning complete v2 job domain state: status, sub_status, status_history, unmasked recipient and courier phone numbers (for operator dispatch support), addresses, price, package, payment method, rating, reconciliation flags, and recent notifications.
  - Every job view is strictly audit-logged via `ShipSecurityEvent` (`ADMIN_JOB_VIEWED`).

- **Item 5: Admin Job Mutations**:
  - Implemented `POST /admin/jobs/{id}/cancel` for non-terminal jobs (`active`, `pending`, `pending_dispatch`, `awaiting_price_response`, `escrow_reconciliation_required`). Requires 1–1000 character reason, enforces atomic CAS state transition, releases courier lock, records status history, ships `ADMIN_JOB_CANCELLED`, and emits cancellation notification.
  - Implemented `POST /admin/jobs/{id}/complete-stuck-cod` reusing store method `RepairSingleStuckCODJob` (the FIX-COD-RECON path) to atomically transition stuck under-distance COD jobs to `completed` with audit trail and courier lock release.

- **Item 6: Services Marketplace Moderation**:
  - Implemented `GET /admin/services` with filtering by tenant ID, query, `has_photo`, and `hidden`.
  - Implemented `POST /admin/services/{id}/hide` and `POST /admin/services/{id}/unhide` with reason validation and `ADMIN_SERVICE_HIDDEN`/`ADMIN_SERVICE_UNHIDDEN` security events. Hidden services are strictly excluded from the customer marketplace `ListServices`.
  - Implemented `POST /admin/services/{id}/photo/remove` to delete the stored photo object from disk/storage, clear the photo URL, and notify the owner.

- **Item 7: Subscriptions Queue**:
  - Verified and enhanced `GET /admin/subscriptions/queue` and `GET /users/admin/subscriptions/queue`.
  - Returns subscriptions waiting in `pending_payment` oldest first (`started_at` ASC), with tenant ID, tenant name, requested plan, requested timestamp, and owner contact details.

- **Item 8: Merged Audit Log Viewer**:
  - Implemented `GET /admin/audit` in `auth-service` with pagination and filtering by actor reviewer, action type, target ID, and timestamp range.
  - Returns stored `audit_log` records along with explicit storage notice informing that transient security events from user and chat services are emitted directly to logging streams.

- **Item 9: Persisted Gateway App Version Policy**:
  - Created MongoDB-backed version policy store in `api-gateway` (`gateway_db.platform_versions`).
  - Added reviewer-authenticated endpoints `GET /admin/version` and `PUT /admin/version` (and `/api/v1/admin/version`) requiring `ValidateDownloadURL`, non-empty audit reason, and `ShipSecurityEvent` (`ADMIN_VERSION_POLICY_UPDATED`). Kept existing `ADMIN_API_TOKEN` bearer authentication intact.

- **Item 9b: Input Hygiene & Dispute Data**:
  - Enforced strict alphanumeric/context pattern validation on `context_id` in `chat-service` ticket creation, rejecting XSS/malformed strings with stable code `invalid_context_id`.
  - Enriched `AdminReconciliationJobItem` in `user-service` with `EmployeeID`, `Category`, `PickupAddress`, and `DropoffAddress`.

- **Item 9c: WebSocket Auth & Token Body Migration**:
  - Enhanced `chat-service` `/chat/ws` to accept authentication tokens from `kyc-console-auth` WebSocket subprotocol and headers, deprecating URL query tokens.
  - Updated `tests/e2e/e2e_helpers.go` `ConnectConsoleWS` to connect via the `kyc-console-auth` subprotocol.
  - Migrated reviewer user-documents audit endpoint `POST /auth/reviewer/user-documents` to accept JSON body `{"user_id":"...","reason":"..."}` while preserving backward-compatible GET query handling during migration.

- **Item 9d: Admin Announcements & Push Fan-out**:
  - Implemented `POST /admin/notifications/send` in `notification-service`: supports audience targeting (`single_user`, `role`, `tenant`, `everyone`), bilingual Arabic/English titles and bodies, in-app deep link validation against registered app paths, dry-run capacity estimation, "send test to me" mode, and 5 sends/hour rate limiting.
  - Implemented asynchronous batch fan-out (500 users/batch) respecting FCM limits, skipping suspended accounts, and providing idempotency key protection.
  - Implemented `GET /admin/notifications/sends` and `GET /admin/notifications/sends/{id}` for job tracking.

- **Item 10: Authoritative API Documentation**:
  - Created comprehensive documentation at `docs/api/ADMIN_API.md` covering all reviewer console endpoints (overview, jobs, mutations, moderation, subscriptions, audit, version, tickets, and notifications) with request/response schemas, error codes, and mobile companion app guidelines.

- **Item 11: End-to-End Test Suite**:
  - Implemented end-to-end integration tests in `tests/e2e/admin_api_test.go` covering Items 3 through 9d against local staging stack.
  - Configured `api-gateway` reverse proxy director to retain `X-Internal-Token` when `X-Reviewer-Token` is present, allowing authorized reviewer requests to route through the gateway to microservices.

---

## Changes per commit (message only — NO SHAs)
1. `ADMIN-API: item 1 - Caddy basic_auth console gate, edge security headers, pinned image`
2. `ADMIN-API: item 2 - reviewer rate limiting by token hash prefix, forwarded client IP, global ceiling`
3. `ADMIN-API: item 3 - GET /admin/overview aggregation with resilient fallbacks`
4. `ADMIN-API: item 4 - GET /admin/jobs and GET /admin/jobs/{id} full v2 lookup with unmasked phones`
5. `ADMIN-API: item 5 - admin job actions cancel non-terminal and complete stuck COD`
6. `ADMIN-API: item 6 - services moderation hide unhide and photo removal`
7. `ADMIN-API: item 7 - subscriptions queue for pending_payment`
8. `ADMIN-API: item 8 - GET /admin/audit merged paginated viewer`
9. `ADMIN-API: item 9 - persisted gateway version config with reviewer endpoints`
10. `ADMIN-API: item 9b - context_id input hygiene and dispute data enrichment`
11. `ADMIN-API: item 9c - token out of URLs for chat ws and reviewer documents`
12. `ADMIN-API: item 9d - admin notifications announcement fan-out and safety controls`
13. `ADMIN-API: item 10 - comprehensive admin API documentation`
14. `ADMIN-API: item 11 - e2e test suite for admin console endpoints`
15. `ADMIN-API: worklog` (this file)

---

## Verification

### 1. `go test -count=1` per changed service

#### `services/auth-service/...`
```
ok  	github.com/project/auth-service/cmd	0.003s
ok  	github.com/project/auth-service/cmd/approve-kyc	0.005s
?   	github.com/project/auth-service/cmd/encrypt-documents	[no test files]
ok  	github.com/project/auth-service/cmd/onboard-reviewer	0.005s
ok  	github.com/project/auth-service/internal/config	0.002s
ok  	github.com/project/auth-service/internal/handlers	53.942s
ok  	github.com/project/auth-service/internal/models	0.001s
ok  	github.com/project/auth-service/internal/otp	0.004s
ok  	github.com/project/auth-service/internal/otpcrypto	0.002s
ok  	github.com/project/auth-service/internal/storage	0.002s
ok  	github.com/project/auth-service/internal/store	1.019s
```
*New Tests*: `TestVerifyReviewerRateLimit_IPKeyed`, `TestAdminAuditLogViewer`, `TestReviewerUserDocuments_POSTBody`.

#### `services/user-service/...`
```
?   	github.com/project/user-service/cmd	[no test files]
ok  	github.com/project/user-service/internal/config	0.002s
ok  	github.com/project/user-service/internal/handlers	252.645s
ok  	github.com/project/user-service/internal/models	0.015s
ok  	github.com/project/user-service/internal/store	12.747s
```
*New Tests*: `TestAdminOverviewAggregation`, `TestAdminJobsLookup`, `TestAdminJobDetail`, `TestAdminCancelJob`, `TestAdminCompleteStuckCODJob`, `TestAdminServicesModeration`, `TestAdminSubscriptionQueue`, `TestAdminReconciliationHygiene`.

#### `services/chat-service/...`
```
?   	github.com/project/chat-service/cmd	[no test files]
ok  	github.com/project/chat-service/cmd/onboard-agent	0.316s
ok  	github.com/project/chat-service/internal/chat	0.449s
ok  	github.com/project/chat-service/internal/config	0.001s
ok  	github.com/project/chat-service/internal/handlers	30.261s
ok  	github.com/project/chat-service/internal/store	5.393s
```
*New Tests*: `TestTicketContextIDHygiene`, `TestChatWS_TokenFromSubprotocolAndHeaders`.

#### `services/notification-service/...`
```
?   	github.com/project/notification-service/cmd	[no test files]
ok  	github.com/project/notification-service/internal/config	0.002s
ok  	github.com/project/notification-service/internal/fcm	0.107s
ok  	github.com/project/notification-service/internal/handlers	0.770s
ok  	github.com/project/notification-service/internal/hub	0.526s
ok  	github.com/project/notification-service/internal/store	3.305s
ok  	github.com/project/notification-service/internal/templates	0.001s
```
*New Tests*: `TestAdminSendNotification_AudienceResolution`, `TestAdminSendNotification_SafetyAndConfirm`, `TestAdminSendNotification_DryRun`, `TestAdminSendNotification_RateLimit`, `TestAdminNotificationSendsList`.

#### `services/api-gateway/...`
```
ok  	github.com/project/gateway/cmd	1.148s
ok  	github.com/project/gateway/internal/config	0.001s
ok  	github.com/project/gateway/internal/iputil	0.002s
ok  	github.com/project/gateway/internal/middleware	0.009s
ok  	github.com/project/gateway/internal/proxy	2.101s
ok  	github.com/project/gateway/internal/version	0.111s
```
*New Tests*: `TestPersistedVersionStore`, `TestReviewerVersionHandlers`.

---

### 2. `make check` last lines (full scope)
```
[timing] flutter-analyze-test 45.9s
[timing] total 446.2s
== pre-push gate: all checks passed (scope: full) ==
gate stamp written: /home/omarmaarouf/CS tools/Antigravity/SaaS prototype/.git/gate-stamps/9bbed5d6... (scope: full)
```

---

### 3. Docker Compose Production Configuration (Redacted Console & Caddy Block)
Command: `KYC_CONSOLE_IMAGE_TAG="2026-09-22-prod" docker compose --env-file infrastructure/staging/.env.staging -f infrastructure/deploy/docker-compose.prod.yml config`

```yaml
  caddy:
    restart: unless-stopped
    container_name: saas-caddy
    environment:
      GOMEMLIMIT: 32MiB
      KYC_CONSOLE_BASIC_AUTH_HASH: [REDACTED_BCRYPT_HASH]
      KYC_CONSOLE_BASIC_AUTH_USER: reviewer_ops
    image: caddy:2.11.4-alpine
    logging:
      driver: json-file
      options:
        max-file: "3"
        max-size: 10m
    mem_limit: "41943040"
    networks:
      saas-net: null
    volumes:
      - type: bind
        source: /home/omarmaarouf/CS tools/Antigravity/saas-core-wt/ADMIN-API/infrastructure/deploy/Caddyfile
        target: /etc/caddy/Caddyfile
        read_only: true
      - type: volume
        source: caddy_data
        target: /data
      - type: volume
        source: caddy_config
        target: /config
    depends_on:
      api-gateway:
        condition: service_started
        required: true
      kyc-reviewer-console:
        condition: service_started
        required: true
    ports:
      - mode: ingress
        target: 80
        published: "80"
        protocol: tcp
      - mode: ingress
        target: 443
        published: "443"
        protocol: tcp
      - mode: ingress
        target: 443
        published: "443"
        protocol: udp

  kyc-reviewer-console:
    restart: unless-stopped
    container_name: saas-kyc-reviewer-console
    environment:
      APP_ENV: production
      AUTH_SERVICE_URL: https://auth-service:3002
      CHAT_SERVICE_URL: https://chat-service:3001
      INTERNAL_SERVICE_TOKEN: [REDACTED]
      PORT: "8090"
      TLS_CA_PATH: /app/certs/ca.crt
      TLS_CERT_PATH: /app/certs/reviewer-console.crt
      TLS_KEY_PATH: /app/certs/reviewer-console.key
      USER_SERVICE_URL: https://user-service:3003
    image: ghcr.io/omarmaarouf18/kyc-reviewer-console:2026-09-22-prod
    logging:
      driver: json-file
      options:
        max-file: "3"
        max-size: 10m
    mem_limit: "16777216"
    networks:
      saas-net: null
    volumes:
      - type: bind
        source: /home/omarmaarouf/CS tools/Antigravity/saas-core-wt/ADMIN-API/infrastructure/deploy/certs/ca.crt
        target: /app/certs/ca.crt
        read_only: true
      - type: bind
        source: /home/omarmaarouf/CS tools/Antigravity/saas-core-wt/ADMIN-API/infrastructure/deploy/certs/reviewer-console.crt
        target: /app/certs/reviewer-console.crt
        read_only: true
      - type: bind
        source: /home/omarmaarouf/CS tools/Antigravity/saas-core-wt/ADMIN-API/infrastructure/deploy/certs/reviewer-console.key
        target: /app/certs/reviewer-console.key
        read_only: true
    depends_on:
      mongo:
        condition: service_healthy
        required: true
      redis:
        condition: service_healthy
        required: true
    ports:
      - mode: ingress
        host_ip: 127.0.0.1
        target: 8090
        published: "8090"
        protocol: tcp
```

---

### 4. New E2E File against Local Staging
Command: `go test -v -count=1 ./tests/e2e -run TestE2E_AdminConsoleEndpoints`

```
=== RUN   TestE2E_AdminConsoleEndpoints
=== RUN   TestE2E_AdminConsoleEndpoints/Item_3_-_Overview_Aggregation
    admin_api_test.go:260: Verified Item 3: Overview successfully aggregated metrics
=== RUN   TestE2E_AdminConsoleEndpoints/Item_4_-_Jobs_Lookup_and_Full_Detail
    admin_api_test.go:312: Verified Item 4: Jobs lookup and full unmasked V2 detail
=== RUN   TestE2E_AdminConsoleEndpoints/Item_5_-_Admin_Job_Mutations
    admin_api_test.go:349: Verified Item 5: Admin job cancel and stuck COD complete mutations
=== RUN   TestE2E_AdminConsoleEndpoints/Item_6_-_Services_Moderation
    admin_api_test.go:407: Verified Item 6: Services moderation hide, unhide, and photo removal
=== RUN   TestE2E_AdminConsoleEndpoints/Item_7_-_Subscriptions_Queue
    admin_api_test.go:444: Verified Item 7: Subscriptions queue returns pending_payment oldest first
=== RUN   TestE2E_AdminConsoleEndpoints/Item_8_-_Audit_Log_Viewer
    admin_api_test.go:471: Verified Item 8: Audit log viewer returns entries and storage notice
=== RUN   TestE2E_AdminConsoleEndpoints/Item_9_-_Persisted_Version_Config
    admin_api_test.go:514: Verified Item 9: Persisted version policy read and update with reason
=== RUN   TestE2E_AdminConsoleEndpoints/Item_9b_-_Ticket_Context_Hygiene
    admin_api_test.go:538: Verified Item 9b: Ticket context_id rejected invalid string with stable error code
=== RUN   TestE2E_AdminConsoleEndpoints/Item_9c_-_WebSocket_Subprotocol_&_Documents_POST
    admin_api_test.go:551: Verified Item 9c: WebSocket connected cleanly with kyc-console-auth subprotocol
    admin_api_test.go:567: Verified Item 9c: Reviewer user-documents accepts POST JSON body
=== RUN   TestE2E_AdminConsoleEndpoints/Item_9d_-_Admin_Announcements
    admin_api_test.go:629: Verified Item 9d: Admin notification dry run, test send, and sends list
--- PASS: TestE2E_AdminConsoleEndpoints (0.12s)
    --- PASS: TestE2E_AdminConsoleEndpoints/Item_3_-_Overview_Aggregation (0.02s)
    --- PASS: TestE2E_AdminConsoleEndpoints/Item_4_-_Jobs_Lookup_and_Full_Detail (0.01s)
    --- PASS: TestE2E_AdminConsoleEndpoints/Item_5_-_Admin_Job_Mutations (0.01s)
    --- PASS: TestE2E_AdminConsoleEndpoints/Item_6_-_Services_Moderation (0.01s)
    --- PASS: TestE2E_AdminConsoleEndpoints/Item_7_-_Subscriptions_Queue (0.00s)
    --- PASS: TestE2E_AdminConsoleEndpoints/Item_8_-_Audit_Log_Viewer (0.01s)
    --- PASS: TestE2E_AdminConsoleEndpoints/Item_9_-_Persisted_Version_Config (0.00s)
    --- PASS: TestE2E_AdminConsoleEndpoints/Item_9b_-_Ticket_Context_Hygiene (0.01s)
    --- PASS: TestE2E_AdminConsoleEndpoints/Item_9c_-_WebSocket_Subprotocol_&_Documents_POST (0.01s)
    --- PASS: TestE2E_AdminConsoleEndpoints/Item_9d_-_Admin_Announcements (0.02s)
PASS
ok  	github.com/project/tests/e2e	0.118s
```

---

## Owner Deployment Instructions

1. **Generate Edge Basic Auth Hash**:
   Run the Caddy CLI utility inside the Caddy image (never echo or expose the plain password in command logs):
   ```bash
   docker run --rm -it caddy:2.11.4-alpine caddy hash-password
   ```
2. **Set Environment Variables on the Host**:
   Configure the following in the host environment or `/etc/environment` (chmod 600):
   ```bash
   KYC_CONSOLE_BASIC_AUTH_USER="<your_console_operator_username>"
   KYC_CONSOLE_BASIC_AUTH_HASH="<bcrypt_hash_from_step_1>"
   KYC_CONSOLE_IMAGE_TAG="<specific_image_tag_e.g._2026-09-22-prod>"
   ```
3. **Execute Deployment Preflight & Redeploy**:
   ```bash
   docker compose -f infrastructure/deploy/docker-compose.prod.yml config
   docker compose -f infrastructure/deploy/docker-compose.prod.yml up -d --remove-orphans
   ```
4. **Edge Verification**:
   Verify the edge responds with HTTP 401 when unauthenticated and HTTP 200 when basic auth credentials are provided:
   ```bash
   curl -I https://kyc.logiclinkeg.tech
   # Returns: HTTP/2 401 Unauthorized, www-authenticate: Basic realm="Restricted Reviewer Console"

   curl -I -u "<username>:<password>" https://kyc.logiclinkeg.tech
   # Returns: HTTP/2 200 OK
   ```
