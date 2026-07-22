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

*   [Security Fixes](docs/changelog/security-fixes.md) — 67 vulnerabilities found and fixed (including Owner-Authenticated Employee Provisioning, see [ADR-0001](docs/adr/0001-owner-authenticated-employee-provisioning.md), Employee Assignment Tenant Binding, see [ADR-0003](docs/adr/0003-employee-assignment-tenant-binding-check.md), and Customer Booking Employee Pre-Assignment Gating, see [ADR-0004](docs/adr/0004-customer-booking-employee-assignment-order.md)).
*   [New Features](docs/changelog/new-features.md) — 27 net-new capabilities (e.g. complaint ticketing, KYB uploads, location tracking, Redis rate limiters, username propagation, request field token aliases).
*   [Infrastructure & Tooling](docs/changelog/infrastructure.md) — 24 tooling, CI, module refactoring, and onboarding CLI tools.
*   [Bug Fixes](docs/changelog/bug-fixes.md) — 16 corrections to existing non-security behavior (e.g. deactivation grace, CORS ordering, random notification IDs, token refresh panic, signup rollback on OTP set failure, resilience client connection leak).
*   [Documentation](docs/changelog/documentation.md) — 7 documentation-only updates (e.g. Application Map, Audit Correction, Auto-Doc System, DESIGN.md Link Alignment).

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
* **Partial Job Listing Coverage**: GET /users/jobs/get supports employee-side job listing (via `requester_id`, IDOR-protected, returns jobs assigned to that employee) — implemented and verified in Phase 3. However, there is still no endpoint for an owner to list all jobs across their tenant, or for a customer to list their own booking history. The owner dashboard and customer profile will only show static/empty placeholders for these views until this is built.
* **Missing Employee Listing Endpoint**: There is currently no endpoint in `auth-service` to retrieve the list of registered employees for a tenant owner.
* **Documentation-Tooling Gap**: The structural drift test (`shared/infra/docgen/structural_drift_test.go`) only verifies that Dart files are cataloged in `STATUS.md` and package constraints match. It does NOT verify that the descriptions, auth paths, or data access parameters in `APPLICATION_MAP.md` align with actual Go handler implementations, leaving a possibility for undocumented API deviations.
* **Local govulncheck stdlib warning (GO-2026-5856)**: The local govulncheck stdlib warning (GO-2026-5856 in crypto/tls) will disappear once the local Go installation is upgraded to go1.26.5 or later (the vulnerability is already patched there) — no code change needed, just a toolchain upgrade whenever convenient. This is a low-priority cleanup, not a blocker.

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


* **Immediate Next Step**: Completed the comprehensive E2E integration audit checks on the active Docker orchestration stack (signup/login flows, KYC/frozen gates, COD booking, WebSocket access control, and resolved username caching). All 14 frontend screens are 100% design-system complete, and all unit, integration, and security checks are passing.







