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

---

## Feature Status

Features are classified into three groups: Done & Verified, Explicitly Deferred by Decision, and Not Started Yet. Only features verified directly against the repository are marked as verified.

### 1. Done & Verified

The detailed project history is distributed across categorized changelog files. Please consult the specific category files for complete details (including file/line references, commit SHAs, and verification details):

*   [Security Fixes](docs/changelog/security-fixes.md) — 58 vulnerabilities found and fixed (including Owner-Authenticated Employee Provisioning, see [ADR-0001](docs/adr/0001-owner-authenticated-employee-provisioning.md), Employee Assignment Tenant Binding, see [ADR-0003](docs/adr/0003-employee-assignment-tenant-binding-check.md), and Customer Booking Employee Pre-Assignment Gating, see [ADR-0004](docs/adr/0004-customer-booking-employee-assignment-order.md)).
*   [New Features](docs/changelog/new-features.md) — 20 net-new capabilities (e.g. complaint ticketing, KYB uploads, location tracking, Redis rate limiters).
*   [Infrastructure & Tooling](docs/changelog/infrastructure.md) — 22 tooling, CI, module refactoring, and onboarding CLI tools.
*   [Bug Fixes](docs/changelog/bug-fixes.md) — 10 corrections to existing non-security behavior (e.g. deactivation grace, CORS ordering, random notification IDs, token refresh panic, signup rollback on OTP set failure, resilience client connection leak).
*   [Documentation](docs/changelog/documentation.md) — 5 documentation-only updates (e.g. Application Map, Audit Correction, Auto-Doc System, DESIGN.md Link Alignment).

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
  * **Decision**: SMS dispatching is stubbed using a mock that logs OTPs to stdout. In local environment (`APP_ENV=local`), OTPs are exposed directly in response payloads as `dev_otp`.
  * **Reasoning**: Speeds up development and avoids dependencies on external paid SMS gateways during local testing. Currently, no real SMS/Email dispatcher is wired for non-local/production environments; all environments fall back to `MockSMSDispatcher` which prints OTPs to stdout.
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


### 3. Not Started Yet

* **Real Email/SMS Integration**: No Twilio, SendGrid, or SMTP dispatchers are set up.

---

## Known Open Items / Unverified Claims

Only features verified directly against the running application are marked as verified (✅). The following items are implemented but remain unverified end-to-end or represent accepted security risks:

* **Verified Customer-Initiated Employee Assignment Gating**: Customer-initiated bookings with employee pre-assignment are fully supported and verified. The handler logic resolves the owner ID from the service tenant ID prior to the employee verification check, ensuring active role and tenant binding validations are correctly performed. Valid active employees succeed, while deactivated employees, mismatching tenants, and invalid roles are successfully gated and rejected.
* **Verified Escrow Logic & COD Completion (Isolated per Job & Concurrency Hardened)**: Escrow locking, release splits, and refunds are verified end-to-end via integration tests. Escrow balances are isolated per job record in the database. Furthermore, rollback/deletion on TrackJob database persistence failures and fail-closed behavior on unrecorded/zero-value escrow amounts are verified. Concurrency tests simulating simultaneous complete/cancel, double-complete, and double-cancel on the same job (for both escrow-based and COD payment methods) confirm that exactly one request succeeds, verifying that race conditions are closed.
* **Fail-Closed Rate Limiting on Redis Unavailability**: If the shared Redis instance becomes unavailable at runtime, all rate limiters across all microservices (api-gateway, auth-service, chat-service, notification-service, user-service) will fail-closed. This means incoming traffic is restricted/blocked and authentication attempts are denied with critical security logs (`[SECURITY CRITICAL]`), rather than allowing un-throttled traffic to bypass security boundaries.
* **Dev-Grade mTLS CA**: The certificates generated for mTLS use a dev-grade local Root CA. For production, a real internal CA (e.g. AWS Private CA, HashiCorp Vault PKI, or cert-manager on Kubernetes) must be integrated.
* **Client-Submitted Booking Coordinates for Pricing**: Distance-based pricing/escrow calculations rely on coordinates submitted by the client at job booking time. Recomputed amounts on CompleteJob and CancelJob use only the initial booking coordinates (`job.Location`). In addition, live location broadcasts from employees are gated by a speed plausibility check (rejecting jumps implying >150.0 km/h) to prevent GPS spoofing.
* **Missing Job Listing Endpoint**: There is currently no endpoint in `user-service` to list jobs (either active or historical) for owners, employees, or customers. This is noted as a product gap, and the owner dashboard will only display static/empty placeholders for the active jobs list.
* **Missing Employee Listing Endpoint**: There is currently no endpoint in `auth-service` to retrieve the list of registered employees for a tenant owner.
* **Documentation-Tooling Gap**: The structural drift test (`shared/infra/docgen/structural_drift_test.go`) only verifies that Dart files are cataloged in `STATUS.md` and package constraints match. It does NOT verify that the descriptions, auth paths, or data access parameters in `APPLICATION_MAP.md` align with actual Go handler implementations, leaving a possibility for undocumented API deviations.

---

## Breaking Token Policy Change (JWT Integration)

With JWT support enabled:
1. Client-facing endpoints expecting a `token` (such as `chat-service` WebSocket `?token=` and `notification-service` SSE stream `?token=`) must now pass a valid signed JWT token instead of raw user IDs.
2. `user-service` JSON fields/query params (`owner_id`, `tenant_id`, `requester_id`, `user_id`, `rated_by`, `rated_user`) support JWT tokens. The backend will validate the token signature/expiry locally, extract the raw user ID, and map it.

---

## Standing Working Rule

This file is a persistent document tracking the real state of the repository.

> [!IMPORTANT]
> **Every code change must update `AI_CONTEXT.md` in the SAME commit.**
> Any pull request or commit that changes application behavior, adds endpoints, modifies security boundaries, or changes the tech stack but does not update `AI_CONTEXT.md` is considered incomplete. 
> Keep the feature status and unverified claims list strictly in sync with actual code implementations.
> **Commit SHA must be the real, full git hash of the commit being documented, captured via `git rev-parse HEAD` immediately after committing — never a placeholder.**
> **docs/APPLICATION_MAP.md must be updated in the same commit whenever a change adds, removes, renames, or changes the auth/permission requirements of an HTTP endpoint, or changes an inter-service call path. The "as of Git commit" note at the top must be refreshed to the new commit's short SHA in that same commit.**
> **Auto-Commit Policy**: After completing any logical unit of work (e.g. a bug fix, security fix, or feature phase) and verifying that the corresponding test suites pass, immediately stage files, commit using conventional style (`fix:`, `feat:`, `docs:`, `ci:`), and push to origin. Never batch multiple unrelated changes into one commit or wait until the end of the session to commit them.


---

* **Immediate Next Step**: Re-themed the entire frontend application (login, signup, OTP, home/dashboard, wallet, employee management, service directory) to use the Quick Delivery brand kit (Deep Navy, Amber Gold, Light Gray, White, Poppins typography), verifying that it passes analysis and widget tests and launches successfully on the Genymotion emulator. Next step: begin Phase 3 employee dashboard and audit simulator. Completed shared/infra test coverage expansion (jwtutil, ratelimit, resilience, tlsutil, handlerutil) focusing on failure modes under commit 40c6c9698cb5aba51e6efc401908889495690ae2, closed auth-service test gaps under commit ba166a25fa6b04221b674d0e116fb54c02b3d4a7, closed user-service test gaps under commit 1b6424cf629722870aa8dd1cc4a2f1cd6cf34c59, closed chat-service test gaps under commit dce438236e89d2143f886e487e7475cc9a03e292, closed notification-service test gaps under commit bbe7f85b4706f2b74be4dc56b6b45cac2ea7945b, and closed api-gateway test gaps under commit 4a2122ab54b9b59c2aa9caae280ef32c7fc1489f.







