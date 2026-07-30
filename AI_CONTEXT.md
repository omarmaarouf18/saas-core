# AI Context: Quick Delivery

> [!IMPORTANT]
> **Branch Workflow**: `main` = stable/deployable, kept in sync only via reviewed merges from `logic-exploitation`. All active development happens on `logic-exploitation`. Never commit directly to `main`.

This file serves as a persistent, model-agnostic, single source of truth for the technical stack, architecture, feature status, security logs, and current gaps of the Quick Delivery platform. Any agent or developer modifying this repository must update this document in the same commit. (Note: The repository and codebase are internally named saas-core for historical reasons.)

---

## Project Summary

The Quick Delivery platform is a multi-tenant SaaS application providing a marketplace services directory, real-time messaging, and job tracking. 

* **Tech Stack Deviation Note**: The codebase is implemented as **Go microservices** running on a containerized environment (Docker Compose) and backing onto MongoDB. This deviates from an original planning diagram that specified a Node.js and Socket.io stack. The microservices architecture and real-time messaging functionality were preserved, but migrated to Go for type safety and performance.

---

## Documentation System

To prevent documentation drift, the repository enforces structural and automated checks that must pass CI before any PR or merge:

1. **Auto-Generated Content**: 
   * **Endpoint Mapping**: The HTTP endpoint table in [docs/APPLICATION_MAP.md](docs/APPLICATION_MAP.md) is auto-generated from `RegisterRoutes` AST declarations across Go services. Edits inside the `<!-- GENERATED:ENDPOINTS:START -->` and `<!-- GENERATED:ENDPOINTS:END -->` markers will be overwritten and must never be edited by hand.
   * **Regenerating**: Run `make docs` to regenerate the endpoint table and refresh the Git commit short SHA note.
2. **Structurally-Checked Content**:
   * **File Indexing**: Every `.dart` file under `frontend/lib/` (screens, providers, models) must be mentioned in [docs/frontend/STATUS.md](docs/frontend/STATUS.md).
   * **Dependency Version Constraints**: Any package dependency constraints mentioned in [DESIGN.md](DESIGN.md) (e.g. `flutter_client_sse`) must match `frontend/pubspec.yaml` exactly.
3. **Manual Content (Enforced via Commit policy)**:
   * **Changelogs, ADRs, & Runbooks**: Additions to `docs/changelog/` (with valid 40-character hex commit SHAs), ADRs under `docs/adr/`, and README guidelines remain manual but must be updated in the same commit.
4. **Verifying Locally**:
   * Run `make docs-check` to execute the complete freshness and drift-catching verification suite locally.
   * Run `make setup` once after cloning to activate the `.githooks/pre-push` hook, which automatically blocks pushes that fail `gofmt`, changelog SHA validation, or `go build/vet/test` for any module. Run `make ci` to execute the same gate manually.

## Tooling & CI Security Scanner

The CI/CD pipeline and local pre-push hooks run a full-scope, unfiltered security scan using **gosec** (`gosec ./...`).

> [!IMPORTANT]
> **Gosec Taint Analysis Rules**:
> The CI workflow installs gosec via `go install github.com/securego/gosec/v2/cmd/gosec@latest`, which fetches a development build ("Gosec: dev" built from the latest master branch). This build includes newer taint-analysis rules beyond the last tagged release that may not be documented in the public `RULES.md`.
> 
> Future contributors must be aware of these rules and resolve them appropriately:
> * **`G704` (CWE-918)**: SSRF via taint analysis (triggered when unsanitized variables propagate to outgoing HTTP requests).
> * **`G705` (CWE-79)**: XSS via taint analysis (triggered when unescaped parameters propagate to HTTP responses).
> * **`G706` (CWE-117)**: Log injection via taint analysis (triggered when potentially untrusted parameters write directly to logs).
> 
> **Resolving Findings**:
> * **Genuine Fixes**: Apply domain prefix validation for SSRF, sanitize inputs inline by stripping carriage returns and newlines (`\r`/`\n`) for log injection, and use structured sanitizers for XSS.
> * **False Positives**: Justify explicitly using a `//nolint:gosec -- <reason>` comment (with both `#nosec` and `//nolint:gosec` headers) on the exact warning line. Do not narrow the scan scope or invent dummy rule IDs to bypass checks.
> 
> *Refer to [docs/changelog/security-fixes.md](docs/changelog/security-fixes.md) for specific G704, G705, and G706 fixes applied in the codebase.*

## CI/CD & Pre-Push Parity

To ensure that code which passes local checks is guaranteed to pass CI (and vice versa), the local pre-push hook ([.githooks/pre-push](file:///mnt/windows_data/CS tools/Antigravity/SaaS prototype/.githooks/pre-push)) and the GitHub Actions workflow ([ci.yml](file:///mnt/windows_data/CS tools/Antigravity/SaaS prototype/.github/workflows/ci.yml)) are synchronized to execute the same checks:

1. **Lint & Formatting**:
   - Go Formatting (`gofmt -l .`)
   - Dart Formatting (`dart format --set-exit-if-changed lib/`)
   - Changelog Commit SHA check (ensures SHAs referenced in `docs/changelog/` exist in Git)
2. **Build, Vet, & Test** (for all microservices and `shared/infra`):
   - `go build ./...`
   - `go vet ./...`
   - `go test ./... -count=1`
3. **Security & Vulnerability Scans**:
   - `govulncheck` (checks Go dependencies for known vulnerabilities; local execution filters for uncalled packages and stdlib vulnerabilities due to Go version mismatch, printing a loud warning in the terminal for each skipped standard library vulnerability)
   - `gosec` (runs full default Go security scans)
4. **Frontend Analysis**:
   - `flutter analyze` (strict checks)
   - `flutter test`

> [!IMPORTANT]
> **Strict Parity Principle**:
> If a check is ever added to `ci.yml`, it must be added to `.githooks/pre-push` in the same commit, and vice versa. Divergence between these two was a root cause of confusing CI failures earlier in this project's history.

> [!NOTE]
> **Pre-Push Hook Activation & Fresh Clone Enforcement**:
> Local git hooks (`.githooks/pre-push`) are NOT automatically activated on fresh clones because `core.hooksPath` is a local git configuration. To prevent commits or pushes that bypass local validation on fresh clones or new agent sessions, all primary `Makefile` targets (`setup`, `docs`, `docs-check`, `ci`, `commit`, `push`) execute an automated `ensure-hooks` prerequisite step that checks `git config --get core.hooksPath` and automatically runs `git config core.hooksPath .githooks` before proceeding. Furthermore, the `CLAUDE.md` auto-commit policy requires `git config core.hooksPath .githooks` as the literal first command before `git add` in every commit sequence.

---

## Architecture Table

The platform uses a microservices architecture coordinated via a reverse-proxy API Gateway.

| Service | Default Port | Role | Data Store / Key Libraries |
| :--- | :--- | :--- | :--- |
| **api-gateway** | `8080` | Reverse proxy/routing edge for clients. Implements edge rate limiting and path rewriting. | Go Standard Library |
| **auth-service** | `3002` | Handles tenant registration, password hashing (bcrypt), multi-role login, and encrypted 2FA OTPs. | MongoDB, `golang.org/x/crypto` |
| **chat-service** | `3001` | Real-time WebSocket hub for messaging, segregated per job. | MongoDB, `github.com/gorilla/websocket` |
| **notification-service** | `3004` | Real-time client alerts via Server-Sent Events (SSE). | Go Standard Library |
| **user-service** | `3003` | Services directory (using spatial indexes), job tracking, e-wallets, ledger, and subscriptions. | MongoDB (with `2dsphere` index) |
| **shared/infra** | `N/A` | Compile-time shared library module for cross-cutting infrastructure packages. | `github.com/redis/go-redis/v9`, `github.com/sony/gobreaker/v2`, `github.com/golang-jwt/jwt/v5` |

* **Shared Infrastructure Module (`shared/infra`)**: Created to eliminate duplicate copy-pasted codebase files (saving ~2,150 duplicate lines of code) without compromising microservice independence. It acts purely as a compile-time dependency, similar to third-party modules (no shared runtime processes, databases, or in-memory state). It contains:
  * `shared/infra/resilience`: HTTP client wrapper for retries, exponential backoff, jitter, and circuit breaking.
  * `shared/infra/ratelimit`: Redis-backed sliding window and login-lockout rate limiting.
  * `shared/infra/tlsutil`: TLS config loaders for mutual TLS (mTLS) server and client setup.
  * `shared/infra/jwtutil`: Cryptographically signed JSON Web Token (JWT) generation and validation helpers.

* **Security Decisions & Architecture Records**: Refer to [docs/adr/README.md](docs/adr/README.md) as the source of truth for security-boundary decisions going forward. Numbered ADR files detail exact context, implementation decisions, and consequences. Future contributors must document significant design and security changes as ADRs.
* **Realtime Hub Horizontal Scaling Architecture**: Real-time hubs (`chat-service` and `notification-service`) use Redis Pub/Sub for cross-replica event fan-out (see [ADR-0005](docs/adr/0005-realtime-hub-horizontal-scaling.md)). Phase 1 migration for `notification-service` (`2794adc70d938df54f97fad003f210eadc9d115f`) and Phase 2 migration for `chat-service` (`203111290514c71a25de3ada16bd43a46fac8f68`) are fully implemented, verified, and committed. Both services dynamically support Redis Pub/Sub cross-replica fan-out and degrade gracefully to local-only delivery if Redis is unreachable.
* **Negotiable Transport Pricing Architecture**: Transport/Rides category pricing model documented in [ADR-0006](docs/adr/0006-negotiable-transport-pricing.md) (`47edf8498d1d294dc00a04845f50fb17ae423fe1`). Data model foundation committed in `beac4e3030b1909cbc08ee6cdefe32923198b185`. Handler wiring, endpoints (`propose-price`, `respond-price`), lazy proposal expiry, and test suite committed in `036901ba292a73d2bf67cd14603f643d5d25e74c`. Defines single-shot take-it-or-leave-it fare proposals $[0.5 \times P_{\text{system}}, 1.5 \times P_{\text{system}}]$, single 5-minute proposal timeout, pre-selected employee assignment, owner-governed vehicle/amenity multipliers, and deferred wallet escrow locking upon reaching `AgreedPrice`.
* **Delivery & Shipping GPS Reconciliation Architecture**: Documented in [ADR-0007](docs/adr/0007-delivery-shipping-gps-reconciliation.md) (`e0c3ab014b45c2eafffd70b33b2bffd7fb2fc270`). Defines a two-phase architecture for Delivery and Shipping categories only: Phase 0 hardens `UpdateJobLocation` to evaluate cumulative speed from job start (closing the slow-drip coordinate drift accumulation gap while inheriting single-instance in-memory throttle state), and Phase 1 introduces `CompleteJob` settlement reconciliation using cumulative Haversine waypoint distance with a guaranteed payout floor ($\max(LockedEscrowAmount, ActualAmount)$) and manual review flagging via `models.JobStatusEscrowReconciliationRequired`.
* **Live Employee Map Tracking Architecture**: Documented in [ADR-0008](docs/adr/0008-live-employee-map-tracking.md) (`c14e7e8e82b69715ffae7b5fca4d941d3410ae43`). Defines zero-cost frontend rendering using `flutter_map` with OpenStreetMap / Carto raster tiles (avoiding GCP billing registration risks), live location streaming by reusing `chat-service` WebSocket channels (ADR-0005) with native `location_update` payload fields, hybrid initial state hydration via HTTP GET endpoints, identity-scoped tenant fleet views (owner sees active fleet employees) vs single-job customer views, and explicit non-goals (geocoding, routing/OSRM, place autocomplete deferred to future ADRs).

---

## Feature Status

Features are classified into three groups: Done & Verified, Explicitly Deferred by Decision, and Not Started Yet. Only features verified directly against the repository are marked as verified.

### 1. Done & Verified

The detailed project history is distributed across categorized changelog files. Please consult the specific category files for complete details (including file/line references, commit SHAs, and verification details):

*   [Security Fixes](docs/changelog/security-fixes.md) — 70 vulnerabilities found and fixed (including Owner-Authenticated Employee Provisioning, see [ADR-0001](docs/adr/0001-owner-authenticated-employee-provisioning.md), Employee Assignment Tenant Binding, see [ADR-0003](docs/adr/0003-employee-assignment-tenant-binding-check.md), and Customer Booking Employee Pre-Assignment Gating, see [ADR-0004](docs/adr/0004-customer-booking-employee-assignment-order.md)).
*   [New Features](docs/changelog/new-features.md) — 29 net-new capabilities (e.g. complaint ticketing, KYB uploads, location tracking, Redis rate limiters, username propagation, request field token aliases).
*   [Infrastructure & Tooling](docs/changelog/infrastructure.md) — 32 tooling, CI, module refactoring, and onboarding CLI tools.
*   [Bug Fixes](docs/changelog/bug-fixes.md) — 17 corrections to existing non-security behavior (e.g. deactivation grace, CORS ordering, random notification IDs, token refresh panic, signup rollback on OTP set failure, resilience client connection leak).
*   [Documentation](docs/changelog/documentation.md) — 9 documentation-only updates (e.g. Application Map, Audit Correction, Auto-Doc System, DESIGN.md Link Alignment, Flutter Backend Connectivity Setup).

### 2. Explicitly Deferred by Decision

* **CloudWatch Event Rate Limiting/Batching**
  * **Decision**: Log shipping performs a separate CloudWatch Logs `PutLogEvents` API call per event rather than using client-side batching or queuing.
  * **Reasoning**: Accepted as a known limitation in the initial rollout. A genuine high-volume abuse burst could hit CloudWatch's per-stream PutLogEvents throttling limit and silently drop events at exactly the moment they matter most. Batching/queuing events client-side is flagged for future implementation.
* **E-Wallet and Bank Card Payment Flows**
  * **Decision**: Only Cash on Delivery (`cod`) is allowed as a payment method for now; other methods are rejected during tracking/booking. Similarly, the public `/users/wallet/deposit` endpoint is gated to reject deposits in non-local/non-test environments. An intentional testing exception is permitted in `TrackJob` where non-COD payment methods (such as `wallet`) are allowed only when `APP_ENV` is `local` or `test` to support integration testing of the escrow lock/release/refund paths; all other environments hard-reject non-COD payments.
  * **Reasoning**: The interface for Stripe or other bank card gateways is placeholder-only. To prevent actual security vulnerabilities or un-auditable fund flows, all payment pathways besides `cod` (outside of local/test environments) and all real environment wallet deposits are explicitly blocked. Bypassing this block in local or test environments is required to verify the correctness of the escrow logic (see [ADR-0002](docs/adr/0002-per-job-escrow-integrity.md)).
* **Manual KYC Approval Process (Ops Runbook)**
  * **Decision**: Initial KYC status approval for tenant owners is deliberately not automated or exposed via API endpoints and must be handled manually directly in the database.
  * **Reasoning**: To maintain security and avoid exposing administrative endpoints that could be targeted by attackers. In contrast, KYB/KYE document reviews are performed via the `/auth/kyb-kye/review` endpoint, which is secured by individual reviewer credentials and internal network token validations.
* **Mock OTP SMS/Email Dispatcher**
  * **Decision**: SMS dispatching is stubbed using a mock that logs OTPs to stdout. In local environment (`APP_ENV=local`), OTPs are exposed directly in response payloads as `dev_otp` and `MockSMSDispatcher` is used. In non-local/production environments, if `RESEND_API_KEY` is configured, email OTPs are dispatched via the Resend REST API (`ResendDispatcher`); if `RESEND_API_KEY` is not set, a warning is logged and `MockSMSDispatcher` is used as a fallback. `RESEND_FROM_EMAIL` is a required companion setting whenever `RESEND_API_KEY` is set, failing fast at startup if omitted.
  * **Reasoning**: Speeds up development and avoids dependencies on external paid SMS gateways during local testing, while providing a real email dispatch path via Resend when configured for production.
* **Query Parameter Transport of Session/Signed Tokens**
  * **Decision**: Transporting authentication tokens via query parameters for WebSocket connections (`chat-service`), SSE connections (`notification-service`), and document viewing (`auth-service/documents/view`) is accepted as an intentional design tradeoff.
  * **Reasoning**: This matches standard patterns for browser APIs (like WebSockets and EventSource/SSE) which do not natively support setting custom headers during the initial handshake.
  * **Observability Verification**: The `api-gateway` access logging (`Logging` middleware) and proxy error handlers log only the URL path (`r.URL.Path`) rather than full URLs, natively ensuring query parameter tokens are redacted and never leaked to persistent logs.
* **Rating Edits / Updates**
  * **Decision**: Editing or updating an existing rating is deliberately not allowed. The endpoint blocks duplicate ratings, and no PATCH/update rating endpoint is provided.
  * **Reasoning**: To prevent data manipulation. Allowing users to modify ratings later is flagged as a potential future feature with its own authorization checks.
* **KYB/KYE Object Storage Provider**
  * **Decision**: Local-disk storage is implemented for local development (storing files securely and generating short-lived view tokens).
  * **Reasoning**: To prevent picking a cloud provider/credentials arbitrarily without user input. A future pass will wire a real S3/compatible provider behind the `storage.Storage` interface.
* **Structured National ID Text Search**
  * **Decision**: Storing national ID numbers as structured, searchable, or encrypted text to match/prevent duplicate accounts is not implemented.
  * **Reasoning**: The ID number lives inside the uploaded document images. Extracting or indexing structured text is flagged for future fraud prevention passes.
* **4th Service Category for Cargo/Goods Transport**
  * **Decision**: A 4th service category for cargo/goods transport (distinct from passenger "Ride") is deferred and not scoped for the current launch. The customer-facing home screen displays exactly 3 service tiles (Delivery, Ride, Shipping), where "Ride" maps to the backend's `transport` category.
  * **Reasoning**: Keeping the scope limited to a 3-category directory for launch. If added later, cargo/goods transport will require a brand new backend category value distinct from `transport` (which is reserved for passenger rides) to avoid ambiguity.


---

## Known Open Items / Unverified Claims

Only features verified directly against the running application are marked as verified (✅). The following items are implemented but remain unverified end-to-end or represent accepted security risks:

* **Verified Owner Employee Listing Endpoint**: `GET /auth/employees` is implemented, IDOR-protected, rate-limited (30 req/min), and verified via unit tests (`TestGetEmployees`) and Docker E2E curl testing. Tenant owners can list all employees registered under their account (including frozen accounts) while sensitive fields (`password`, `otp_code`, `id_front_doc`) are omitted.
* **Verified Customer-Initiated Employee Assignment Gating**: Customer-initiated bookings with employee pre-assignment are fully supported and verified. The handler logic resolves the owner ID from the service tenant ID prior to the employee verification check, ensuring active role and tenant binding validations are correctly performed. Valid active employees succeed, while deactivated employees, mismatching tenants, and invalid roles are successfully gated and rejected.
* **Verified Escrow Logic & COD Completion (Isolated per Job & Concurrency Hardened)**: Escrow locking, release splits, and refunds are verified end-to-end via integration tests. Escrow balances are isolated per job record in the database. Furthermore, rollback/deletion on TrackJob database persistence failures and fail-closed behavior on unrecorded/zero-value escrow amounts are verified. If `RollbackEscrow` itself fails after `UpdateJobLockedEscrow` error during `TrackJob`, the job record is preserved in MongoDB under status `escrow_reconciliation_required` with `ReconciliationNote` and `EscrowFailureReason` rather than deleted, guaranteeing stuck escrow funds remain queryable for manual operator resolution. In addition, `TrackJob` enforces request idempotency via `Idempotency-Key` / `X-Idempotency-Key` headers (and `idempotency_key` JSON parameter); duplicate requests return the existing job (200 OK) without creating extra jobs or double-locking escrow. Concurrency tests simulating simultaneous complete/cancel, double-complete, and double-cancel on the same job (for both escrow-based and COD payment methods) confirm that exactly one request succeeds, verifying that race conditions are closed.
* **Verified Admin/Owner Escrow Reconciliation Review Endpoints & Frontend Screen**: `GET /users/jobs/reconciliation-queue` and `POST /users/jobs/reconciliation-resolve` backend endpoints and Flutter frontend (`ReconciliationProvider`, `OwnerReconciliationQueueScreen`, `ReconciliationJob` model) are fully implemented, owner-role gated (`resolveTokenWithRole`), tenant-isolated with IDOR protection, and rate-limited (30 req/min). Tenant owners can query jobs in status `escrow_reconciliation_required` (with human-readable failure reason mapping like "Distance mismatch — under 70% of booked distance", `ReconciliationNote`, and `LockedEscrowAmount`) and resolve stuck escrow via `release_to_employee` (executing profit split payout) or `refund_to_customer` (refunding locked escrow). Interactive confirmation dialogs prevent accidental fund movement. Resolutions update job status atomically, record resolution notes, update wallets/ledger, ship audit events (`ESCROW_RECONCILIATION_RESOLVED`), surface 409 conflict & 429 rate-limit responses, and update the queue dynamically. Verified via backend integration tests and Flutter widget tests (`test/reconciliation_queue_test.dart` 5/5 pass). (Commit `cd94f15851ca13b561f05aad65b424e598461f22`).
* **Fail-Closed Rate Limiting on Redis Unavailability**: If the shared Redis instance becomes unavailable at runtime, all rate limiters across all microservices (api-gateway, auth-service, chat-service, notification-service, user-service) will fail-closed. This means incoming traffic is restricted/blocked and authentication attempts are denied with critical security logs (`[SECURITY CRITICAL]`), rather than allowing un-throttled traffic to bypass security boundaries.
* **Dev-Grade mTLS CA**: The certificates generated for mTLS use a dev-grade local Root CA. For production, a real internal CA (e.g. AWS Private CA, HashiCorp Vault PKI, or cert-manager on Kubernetes) must be integrated.
* **Client-Submitted Booking Coordinates for Pricing & Dual-Layer Speed Plausibility Checks**: Distance-based pricing/escrow calculations rely on coordinates submitted by the client at job booking time. Recomputed amounts on `CompleteJob` and `CancelJob` use only the initial booking coordinates (`job.Location`). In addition, live location broadcasts from employees in `UpdateJobLocation` are gated by dual-layer speed plausibility checks (rejecting updates with `IMPLAUSIBLE_SPEED_DETECTED` audit logs):
  1. *Per-Step Speed Check*: Calculates Haversine distance between consecutive location updates divided by time elapsed since last update (`now.Sub(lastTime)`), rejecting step jumps implying `>150.0 km/h` (`MaxReasonableSpeedKmh`).
  2. *Cumulative Route Speed Check (Phase 0, Commit 12dd2f3)*: Calculates total cumulative Haversine distance across all recorded waypoints (`job.Location`, `job.Waypoints...`, and candidate coordinate) divided by total time elapsed since job creation (`now.Sub(job.CreatedAt)`), rejecting cumulative routes implying `>150.0 km/h` (`MaxReasonableSpeedKmh`).
* **Verified Owner and Customer Job Listing Endpoints**: `GET /users/jobs/owner` and `GET /users/jobs/mine` are implemented, tenant-isolated, rate-limited, and verified via dedicated unit tests (`TestGetJobsByOwner`, `TestGetJobsByCustomer`) and Docker E2E curl testing against the live stack. Security is anchored by identity-scoped authorization (database queries filter strictly by the authenticated JWT claims identity) combined with parameter validation (explicit target `owner_id` / `user_id` query parameters, if passed, are checked against JWT claims and trigger 403 `[IDOR DETECTED]` logs on mismatch). Owners list tenant jobs via `GET /users/jobs/owner` (with `OwnerJobResponse` DTO), customers list booking history via `GET /users/jobs/mine` (with `CustomerJobResponse` DTO), and rate limiting blocks excessive requests with 429.
* **Verified Rate Limiting Across Rating Endpoints (Item #3)**: `POST /users/jobs/rate` (`RateJob`) and `GET /users/ratings` (`GetRatings`) invoke IP-keyed rate limiting via `u.limiter.CheckAndRecord` matching `TrackJob` and `WalletDeposit`, preventing spam and enumeration with HTTP 429 responses. Verified via `TestRateJobAndGetRatings_RateLimiting`.
* **Verified Redis-Backed TrackJob Idempotency & 24h TTL (Item #2 Remediation)**: Replaced the single-instance in-memory `idempotencyJobs` map with Redis-backed key storage (`idempotency:job:<key> -> job_id`) with 24-hour TTL (`24 * time.Hour`). Removed `idempotencyMu` and `idempotencyJobs` fields from `UserService`. Cross-replica duplicate detection and key TTL expiration verified via multi-instance unit test (`TestTrackJob_RedisBackedIdempotency_MultiInstanceAndTTL`).
* **Verified Token Role Gating in resolveTokenWithRole & Removal of Dead Wrapper (Item #4 & Task 2)**: Audited all call sites in `handlers.go` and enforced explicit variadic role checks (`resolveTokenWithRole`) across all 18 endpoint token resolution locations (`CreateService`, `TrackJob`, `GetJob`, `CompleteJob`, `CancelJob`, `UpdateJobLocation`, `GetWallet`, `WalletDeposit`, `GetSubscription`, `UpdateSubscription`, `RateJob`, `GetRatings`). Removed the unused legacy `resolveToken` wrapper function. Verified via grep audit and comprehensive role enforcement test suite (`TestRoleEnforcement_*`).
* **Verified Public/Owner Rating Summary Access Model (Item #5)**: `GetRatings` (`GET /users/ratings`) authenticates the caller via JWT token while accepting candidate employee/user target IDs in query parameter `user_id`. This enables owners to view candidate employee ratings before hiring without requiring possession of the candidate's JWT token. Verified via `TestUserServiceHandlers/GetRatings`.
* **Verified Dual-Layer Rate Limiting for GetLedger (Item #6)**: `GetLedger` (`GET /users/ledger`) enforces both IP-based and tenant-based rate limiting via `u.limiter.CheckAndRecord`, matching `WalletDeposit`'s financial security layer. Verified via `TestGetLedger_RateLimiting`.
* **Verified Test Payment Bypass Gating & Production Safeguard (Item #7)**: Test payment method bypasses (in `TrackJob` and `WalletDeposit`) require the explicit environment variable `ALLOW_TEST_PAYMENT_BYPASS=true` in addition to non-production environment settings (`APP_ENV=test` or `local`). Configuring `ALLOW_TEST_PAYMENT_BYPASS=true` when `APP_ENV=production` fails service startup immediately. Verified via `TestLoad_AllowTestPaymentBypass` and `TestTestPaymentBypass_Gating`.
* **Verified RateJob Comment Sanitization & Length Bound (Item #8)**: `RateJob` (`POST /users/jobs/rate`) enforces a 1000-character maximum length limit on incoming comments and sanitizes comments server-side using `html.EscapeString`. In addition, frontend rendering in `frontend/lib` uses standard Flutter `Text` widgets, ensuring comments are rendered strictly as plain text. Verified via `TestRateJob_CommentSanitizationAndLengthLimit`.
* **Verified Redis-Backed Location Update Throttle State (ADR-0005 Correction Remediation)**: Replaced in-memory `locationInFlight` and `locationLastUpdate` maps in `user-service` (`UpdateJobLocation`) with Redis-backed atomic key evaluation (`loc:inflight:<job_id>` and `loc:lastupdate:<job_id>`) using an atomic Lua script. Closed cross-replica throttling gaps and verified fail-closed behavior on Redis unavailability. Verified via multi-instance unit test.
* **Known Limitation: notification-service Redis Pub/Sub Self-Delivery Dependency**: In `notification-service` (`services/notification-service/internal/hub/hub.go`), `Broadcast()` relies on the instance's own pattern subscription (`PSubscribe("notify:*")`) to loop messages back to local clients on the origin replica. Every notification incurs a Redis Pub/Sub network round-trip. If the publishing instance's subscriber connection experiences a transient hiccup at the moment of publish, local clients on the origin instance could miss an alert. (Documented in [ADR-0005](docs/adr/0005-realtime-hub-horizontal-scaling.md)).
* **Verified Go Version Standardization & Automated Drift Guard**: All sources of truth (`go.work`, 7 `go.mod` files, `.github/workflows/ci.yml`, and 5 `Dockerfile`s) are standardized to Go 1.26 (latest stable patch release 1.26.5). An automated drift guard step in `.githooks/pre-push` and `ci.yml` enforces strict Go version consistency across all files.
* **Verified Resend Email OTP Delivery End-to-End (`info@logiclinkeg.tech` / `ResendDispatcher`)**: Queried Resend API `/domains` endpoint and confirmed verified sending status (`status: verified`, `sending: enabled`) for domain `logiclinkeg.tech`. Real end-to-end email OTP dispatching was verified from sender `info@logiclinkeg.tech` via `ResendDispatcher` (`github.com/resend/resend-go/v3`) against live Resend API infrastructure (`Resend email ID: 3f0843d1-5682-455d-9ebe-00fcec6590be`). Verified full lifecycle: user signup (`POST /api/v1/auth/signup`), `dev_otp` suppression in non-local mode (`APP_ENV=production`), AES-256-GCM OTP ciphertext storage at rest in MongoDB, live email delivery, 2FA authentication via `POST /api/v1/auth/verify-otp` (HTTP 200 OK + JWT issued), and confirmed graceful error logging on invalid API keys without crashing `auth-service`.

---

## Request Field Naming Compatibility (JWT Integration)

To address naming clarity issues where request fields expected signed JWT tokens rather than raw database IDs, the backend supports newer `_token` field aliases alongside legacy `_id` / raw parameter names:
| Legacy Field Name | New Preferred Alias | Affected Endpoints |
|---|---|---|
| `user_id` / `id` | `user_token` | GET /auth/user, GET /auth/user/public-profile, POST /users/jobs/track, GET /users/ratings |
| `owner_id` | `owner_token` | POST /users/services, POST /users/jobs/track |
| `employee_id` | `employee_token` | POST /users/jobs/track, GET /users/jobs/get |
| `requester_id` | `requester_token` | GET /auth/audit-log, GET /auth/user/public-profile, GET /users/jobs/get, POST /users/jobs/complete, POST /users/jobs/cancel, POST /users/subscription, POST /users/jobs/location/update |
| `tenant_id` | `tenant_token` | GET /users/wallet, POST /users/wallet/deposit, GET /users/ledger, GET /users/subscription, POST /users/subscription |
| `rated_by` / `rated_user` | `rated_by_token` / `rated_user_token` | POST /users/jobs/rate |

The Go backend handles both legacy and preferred naming conventions compatibly (preferring `_token` if both are supplied). *Note: The Flutter frontend has not yet been updated to use the preferred fields.*

---

## Standing Working Rule

This file is a persistent document tracking the real state of the repository.

> [!IMPORTANT]
> **Every code change must update `AI_CONTEXT.md` in the SAME commit.**
> Any pull request or commit that changes application behavior, adds endpoints, modifies security boundaries, or changes the tech stack but does not update `AI_CONTEXT.md` is considered incomplete. 
> Keep the feature status and unverified claims list strictly in sync with actual code implementations.
> **Commit SHA must be the real, full git hash of the commit being documented, captured via `git rev-parse HEAD` immediately after committing — never a placeholder.**
> **docs/APPLICATION_MAP.md must be updated in the same commit whenever a change adds, removes, renames, or changes the auth/permission requirements of an HTTP endpoint, or changes an inter-service call path. The "as of Git commit" note at the top must be refreshed to the new commit's short SHA in that same commit.**
> **Auto-Commit Policy**: After completing any logical unit of work (e.g. a bug fix, security fix, or feature phase) and verifying that the corresponding test suites pass, immediately stage files, commit using conventional style (`fix:`, `feat:`, `docs:`, `ci:`), and push to origin. Before committing any Go file changes, run `gofmt -w` on the modified files (or `gofmt -l .` repo-wide) and confirm no output, since CI enforces gofmt as a blocking gate. Never batch multiple unrelated changes into one commit or wait until the end of the session to commit them.
> **Dependency Drift Prevention**: Any change to shared/infra that adds a new external dependency must be followed by `go mod tidy && go build ./...` in every service that imports shared/infra, and a full `docker compose down && build --no-cache && up` verification, before considering the change complete — go.sum drift can pass CI's module resolution while still breaking local/production Docker builds.
> **Environment Verification Disclosure**: Any report or documentation claiming test suite pass status must explicitly specify whether verification was performed against local execution, GitHub Actions CI execution, or both, to prevent environment divergence.
> **Backend Contract Verification**: Before building a frontend feature that depends on a specific backend contract (channel name, endpoint, payload shape), verify that contract actually exists in the current code first (grep for it), and if it doesn't, stop and inform the user instead of building against assumed or planned contracts.


* **Verified Endpoint Map Regeneration & Role Description Alignment (Task 1)**: Regenerated `docs/APPLICATION_MAP.md` via `make docs` and updated `KnownEndpoints` in `shared/infra/docgen/generator.go` to reflect exact role requirements following Gap 1 remediation (`resolveTokenWithRole`). Verified via `make docs-check`.
* **ADR-0007 Phase 1 Actual Distance Settlement & Reconciliation Review Flag**: Implemented GPS trail actual distance calculation, guaranteed floor payout `max(LockedEscrowAmount, A_actual)`, and under-distance manual review flag (`ActualDistance < 0.70 * BookedDistance`) transitioning jobs to `escrow_reconciliation_required` in `user-service` (`CompleteJob`). For non-COD escrow jobs, payouts exceeding `LockedEscrowAmount` are capped at `LockedEscrowAmount` per ADR-0002 to preserve wallet isolation and emit `ESCROW_LIMIT_EXCEEDED` operator audit logs. Verified via `TestCompleteJob_ADR0007_Phase1_SettlementAndReconciliation`. (Commit `44e51b2efdc925c6862df04658b73429a9680154`).
* **E2E Integration Test Redis Port Resolution & Nil Safety Guards**: Resolved CI gate failure in `adr0006_e2e_integration_test.go` and `adr0007_e2e_integration_test.go` caused by hardcoded `localhost:6380` Redis addresses. Updated Redis initialization to dynamically parse `REDIS_URI` / `REDIS_ADDR` with fallback to default port `6379`, added `Ping` connectivity checks to skip gracefully if Redis is unavailable, and added explicit HTTP response status assertions and nil checks before dereferencing struct fields. Verified via local Go test execution.
* **ADR-0008 Backend Live Employee Map Tracking & End-to-End Verification**: Extended `canAccessChannel` in `chat-service` to authorize `fleet:<owner_id>` for owner role users. Wired `UpdateJobLocation` in `user-service` to broadcast `location_update` messages to both `job:<id>` and `fleet:<owner_id>` channels via `chat-service`. Added `active_only=true` query filtering to `GET /users/jobs/owner` for initial fleet hydration. Built `TestADR0008_E2E_LiveEmployeeMapTracking` integration test confirming real WebSocket connections, `fleet:<owner_id>` channel authorization, and real-time location broadcast delivery. Updated ADR-0008 status to Accepted. (Commit `17ebd52e1d88246c5141f793abfd08c5515cc133`).
* **Verified Centralized Friendly Error Messages Utility & Raw Error Leakage Prevention**: Created `frontend/lib/core/error_messages.dart` (`friendlyErrorMessage(Object? error)`) mapping `ApiClientException` status codes (400, 401, 403, 404, 409, 429, 5xx) to friendly English error messages without branching on backend raw error strings or leaking internal error details. Replaced raw error displays across all frontend providers and screens with `friendlyErrorMessage(e)` while preserving developer debug logging via `debugPrint`. Verified via `dart format --set-exit-if-changed lib/`, `flutter analyze` (0 issues), and `flutter test` (all tests passed including 4 table-driven friendly error unit tests). (Commit `fc4456efed1f6f86787943ad15133a7b9f0845e1`).
* **Verified Flutter Client Backend Connectivity Setup Guide (CONNECTING_TO_BACKEND.md)**: Produced `frontend/CONNECTING_TO_BACKEND.md` covering backend health checks (`/health`), `API_BASE_URL` resolution via `--dart-define`, per-platform host configurations (Android Emulator `10.0.2.2`, physical Android `adb reverse tcp:8080 tcp:8080`, iOS Simulator `localhost`, physical iOS `192.168.x.x`), HTTPS dev cert bypass mechanics (`DevHttpOverrides`), clean rebuild workflow using verified Application ID / Bundle ID (`com.saascore.frontend`), real-time log streaming, and troubleshooting matrix. Added pointers in `README.md` and `frontend/README.md`. Verified via `make docs-check`. (Commit `c054907795e113e7d47edbd4776e6a52536032f1`).
* **Verified Flutter KYB/KYE Document Upload Screen**: Implemented `KycDocumentUploadScreen` (`frontend/lib/screens/kyc_document_upload_screen.dart`), updated `UserProfile` (`frontend/lib/models/user_profile.dart`), extended `AuthProvider` (`frontend/lib/providers/auth_provider.dart`), and wired banner prompts + AppBar actions in `home_screen.dart`. Dynamically renders role-conditional document upload slots (4 slots for owner: `id_front`, `id_back`, `selfie`, `business_proof`; 3 slots for employee: `id_front`, `id_back`, `selfie`). Integrates `StatusBadge` for KYC status displays, shows prominent rejection reason banner when status is `rejected`, enforces client-side file size ($\le 10$MB) and MIME format rules prior to network calls, handles per-slot upload loading and error states independently, and locks/disables upload actions when status is `approved`. Verified via `flutter analyze` (clean 0 issues) and `flutter test` (`test/kyc_document_upload_screen_test.dart` 5/5 pass). (Commit `05cbbc7136de2a6a630ff2ebe16a72426ce289aa`).
* **Verified Backend Forgot Password & Reset Password Endpoints**: Implemented `POST /auth/forgot-password` and `POST /auth/reset-password` in `auth-service` reusing existing AES-256-GCM encrypted OTP store methods (`SetOTP` / `VerifyOTP`). `POST /auth/forgot-password` provides anti-enumeration 200 OK responses, IP/email rate limiting, 5-minute encrypted OTP generation, and dispatch via `a.dispatcher.Dispatch`. `POST /auth/reset-password` validates `email`/`otp`/`new_password`, enforces rate limit lockouts, calls `store.VerifyOTP`, bcrypt-hashes passwords, updates user record, and clears OTP fields to prevent replay attacks. Built 6 unit tests covering anti-enumeration response parity, rate limiting, password reset & old password invalidation, generic wrong OTP error & rate-limit failure recording, missing password validation, and OTP reuse prevention. Regenerated `docs/APPLICATION_MAP.md` via `make docs`. (Commit `ee443e39358b7f4c06fe7eb2f2a57b2f4e4c8d79`).
* **ADR-0009 Negotiable Transport Pricing Atomic Compare-and-Swap TOCTOU Hardening**: Remediated TOCTOU race conditions in `RespondPrice` and `ProposePrice` in `user-service`. Added status-conditioned compare-and-swap update filters to `UpdateJobAgreedPrice`, `UpdateJobCancellation`, and `UpdateJobPriceProposal` (`status: AwaitingPriceResponse`), returning `job_state_changed` on zero matched documents. Wired `RespondPrice` to execute automatic compensating `performRollbackEscrow` and return `409 Conflict` on `job_state_changed`. Built concurrency race tests (`TestRespondPrice_ConcurrencyRace_DoubleEscrowPrevention` and `TestProposePrice_ConcurrencyRace_OverwrittenProposalPrevention`). Published ADR-0009 (`docs/adr/0009-atomic-compare-and-swap-transport-pricing.md`). (Commit `ffb75f989bd25ed0ac5bb54f46094a66ecad0080`).
* **ADR-0009 Hardening (Gap 3: Job State Changed Rollback Failure Retry & Reconciliation Fallback)**: Hardened `RespondPrice` (`user-service`). When `UpdateJobAgreedPrice` returns `job_state_changed` post-escrow lock, if initial `performRollbackEscrow` fails, handler retries `performRollbackEscrow` once. If retry fails, handler invokes `u.store.UpdateJobReconciliation` to mark job `models.JobStatusEscrowReconciliationRequired` with reconciliation notes while maintaining HTTP `409 Conflict` (`job_state_changed`) client response. Built unit test `TestRespondPrice_JobStateChanged_RollbackFailure_ReconciliationFallback`. Appended follow-up note to ADR-0009. (Commit `42e5843b3471bb272f1deef9846ad14b79414e35`).
* **Verified ListServices Spatial Coordinate Bounds Validation**: Resolved "Flagged for Next Pass" item 3 in `docs/audit/shared-module-review.md`. Added `isValidCoordinate(refLat, refLon)` bounds validation (`-90 <= lat <= 90`, `-180 <= lon <= 180`) to `ListServices` in `user-service` when `near_by=true` or when explicit `lat`/`lon` parameters are provided. On invalid coordinates, logs `[SECURITY WARNING]`, ships audit event (`INVALID_COORDINATES_DETECTED`), and returns HTTP 400 (`invalid_coordinates`). Built 4 unit tests in `list_services_test.go`. (Commit `679667f9c994edd582d5c6d79226e78d1b277320`).
* **Verified Android Emulator End-to-End Backend Connectivity**: Verified Android Emulator connectivity end-to-end against the live Docker Compose backend using `API_BASE_URL=https://10.0.2.2:8080/api/v1`. Confirmed backend health check (`curl -k https://localhost:8080/health` -> `{"status":"ok"}`), debug-mode self-signed certificate bypass (`DevHttpOverrides` / `bypassBadCertificate` in `kDebugMode`), and exercised actual API Gateway route `GET /api/v1/users/services` returning HTTP 200 OK with 15 seeded service entries. Verified via local execution against live backend stack. (Commit `807f98bbca30bf072824b11892a60af02ff310ba`).
* **Verified Android Gradle compileSdk Pinning for AAR Metadata Alignment**: Resolved Android APK build failure (`checkDebugAarMetadata... Dependency 'flutter_plugin_android_lifecycle' requires 'compileSdkVersion' 36 or higher`) by pinning `compileSdk = 36` in `frontend/android/app/build.gradle.kts`. Updated troubleshooting matrix in `frontend/CONNECTING_TO_BACKEND.md`. Verified via `flutter analyze` and `flutter test`. (Commit `c1f00d3d026207acb4f78741afaae121c07afa88`).
* **Verified AI_CONTEXT.md Orphaned Commit SHA Narrative Formatting Mitigation**: Truncated full 40-character orphaned commit SHA in historical narrative text in `docs/changelog/bug-fixes.md` to short ref `05b5ca7...` to prevent global CI regex scanning from matching non-citation narratives as live commit references. Verified via whole-repo markdown SHA verification check (0 BLOCKED lines) and `make docs-check`. (Commit `3a032f138f47d0a9b140f12518e9ee59fe4ce266`).
* **Verified Markdown Commit SHA Validation Regex Narrowing & No-Amend Policy**: Narrowed regex scanning in `.githooks/pre-push` and `.github/workflows/ci.yml` to citation lines (`Commit SHA`, `Commit:`, `Related Commit SHA`, `Fix Commit SHA`, `(Commit `) to eliminate false positives on historical reflog narratives. Added rule #6 to `CLAUDE.md` prohibiting `git commit --amend` on already-cited commits. Verified via whole-repo SHA check (229 citations verified, 0 false positives) and `make docs-check`. (Commit `3a032f138f47d0a9b140f12518e9ee59fe4ce266`).
* **Verified Restored Full-Coverage Markdown Commit SHA Validation & Non-Citation Truncation Rule**: Superseded the citation-marker narrowing and two-tier warning pass by restoring strict repo-wide 40-character hex SHA scanning (blocking on any unresolvable 40-char SHA) in `.githooks/pre-push` and `.github/workflows/ci.yml` to close citation keyword coverage gaps. Added rule #7 to `CLAUDE.md` mandating that non-authoritative historical/orphaned commit mentions in prose be written truncated (`05b5ca7...`). Verified via repo-wide check (0 BLOCKED lines) and fabricated hash regression check (BLOCKED, exit 1). (Commit `c14bac58208173e914b376cf0bb8c89b4f90f433`).
* **Verified Negotiable Transport Pricing UI (ADR-0006)**: Added API client methods `proposePrice` (`POST /users/jobs/propose-price`) and `respondPrice` (`POST /users/jobs/respond-price`) in `ApiClient` and `MarketplaceProvider`. Built negotiation counter-offer UI with $[0.5 \times P_{\text{suggested}}, 1.5 \times P_{\text{suggested}}]$ validation in `JobStatusScreen` for transport-category jobs in `awaiting_price_response` state. Added incoming proposal card displaying proposer role, proposed fare, original system fare, and percentage difference comparison. Handled 409 `job_state_changed` conflict responses with user-friendly notification and auto-refresh. Integrated 5-minute negotiation window timer with live ticker and explicit expired banner. Verified via `flutter analyze` (0 issues) and `flutter test` (`test/negotiable_transport_pricing_test.dart` 5/5 pass, entire suite 40/40 pass).









