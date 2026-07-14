# AI Context: saas-core

> [!IMPORTANT]
> **Branch Workflow**: `main` = stable/deployable, kept in sync only via reviewed merges from `logic-exploitation`. All active development happens on `logic-exploitation`. Never commit directly to `main`.

This file serves as a persistent, model-agnostic, single source of truth for the technical stack, architecture, feature status, security logs, and current gaps of the `saas-core` platform. Any agent or developer modifying this repository must update this document in the same commit.

---

## Project Summary

The `saas-core` platform is a multi-tenant SaaS application providing a marketplace services directory, real-time messaging, and job tracking. 

* **Tech Stack Deviation Note**: The codebase is implemented as **Go microservices** running on a containerized environment (Docker Compose) and backing onto MongoDB. This deviates from an original planning diagram that specified a Node.js and Socket.io stack. The microservices architecture and real-time messaging functionality were preserved, but migrated to Go for type safety and performance.

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

*   [Security Fixes](docs/changelog/security-fixes.md) — 47 vulnerabilities found and fixed (including Owner-Authenticated Employee Provisioning, see [ADR-0001](docs/adr/0001-owner-authenticated-employee-provisioning.md)).
*   [New Features](docs/changelog/new-features.md) — 20 net-new capabilities (e.g. complaint ticketing, KYB uploads, location tracking, Redis rate limiters).
*   [Infrastructure & Tooling](docs/changelog/infrastructure.md) — 16 tooling, CI, module refactoring, and onboarding CLI tools.
*   [Bug Fixes](docs/changelog/bug-fixes.md) — 7 corrections to existing non-security behavior (e.g. deactivation grace, CORS ordering, random notification IDs, token refresh panic).
*   [Documentation](docs/changelog/documentation.md) — 2 documentation-only updates (e.g. Application Map).

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
* **Rating Edits / Updates**
  * **Decision**: Editing or updating an existing rating is deliberately not allowed. The endpoint blocks duplicate ratings, and no PATCH/update rating endpoint is provided.
  * **Reasoning**: To prevent data manipulation. Allowing users to modify ratings later is flagged as a potential future feature with its own authorization checks.
* **KYB/KYE Object Storage Provider**
  * **Decision**: Local-disk storage is implemented for local development (storing files securely and generating short-lived view tokens).
  * **Reasoning**: To prevent picking a cloud provider/credentials arbitrarily without user input. A future pass will wire a real S3/compatible provider behind the `storage.Storage` interface.
* **Structured National ID Text Search**
  * **Decision**: Storing national ID numbers as structured, searchable, or encrypted text to match/prevent duplicate accounts is not implemented.
  * **Reasoning**: The ID number lives inside the uploaded document images. Extracting or indexing structured text is flagged for future fraud prevention passes.


### 3. Not Started Yet

* **Real Email/SMS Integration**: No Twilio, SendGrid, or SMTP dispatchers are set up.

---

## Known Open Items / Unverified Claims

Only features verified directly against the running application are marked as verified (✅). The following items are implemented but remain unverified end-to-end or represent accepted security risks:

* **Verified Escrow Logic (Isolated per Job & Concurrency Hardened)**: Escrow locking, release splits, and refunds are verified end-to-end via integration tests. Escrow balances are isolated per job record in the database. Furthermore, rollback/deletion on TrackJob database persistence failures and fail-closed behavior on unrecorded/zero-value escrow amounts are verified. Concurrency tests simulating simultaneous complete/cancel, double-complete, and double-cancel on the same job confirm that exactly one request succeeds, verifying that race conditions are closed.
* **Fail-Closed Rate Limiting on Redis Unavailability**: If the shared Redis instance becomes unavailable at runtime, all rate limiters across all microservices (api-gateway, auth-service, chat-service, notification-service, user-service) will fail-closed. This means incoming traffic is restricted/blocked and authentication attempts are denied with critical security logs (`[SECURITY CRITICAL]`), rather than allowing un-throttled traffic to bypass security boundaries.
* **Dev-Grade mTLS CA**: The certificates generated for mTLS use a dev-grade local Root CA. For production, a real internal CA (e.g. AWS Private CA, HashiCorp Vault PKI, or cert-manager on Kubernetes) must be integrated.
* **Client-Submitted Booking Coordinates for Pricing**: Distance-based pricing/escrow calculations rely on coordinates submitted by the client at job booking time. Recomputed amounts on CompleteJob and CancelJob use only the initial booking coordinates (`job.Location`). In addition, live location broadcasts from employees are gated by a speed plausibility check (rejecting jumps implying >150.0 km/h) to prevent GPS spoofing.
* **Missing Job Listing Endpoint**: There is currently no endpoint in `user-service` to list jobs (either active or historical) for owners, employees, or customers. This is noted as a product gap, and the owner dashboard will only display static/empty placeholders for the active jobs list.
* **Missing Employee Listing Endpoint**: There is currently no endpoint in `auth-service` to retrieve the list of registered employees for a tenant owner.

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

---

* **Immediate Next Step**: Completed Phase 2 security vulnerability fixes and testing (including zero-value escrow fail-closed, TrackJob rollback, concurrency race-condition validation, and certs/documents cleanup). Next step: continue Phase 2 owner core functionalities.





