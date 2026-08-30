# ADR-0016: Tiered Rate Limits for UX over Uniform Security Floor

- **Status**: Accepted
- **Date**: 2026-08-07
- **Related Commit SHA**: `131a8a8133b8a4b7f58ada9a92cb0ed0cc0e6e96`
- **Related Frontend Commit SHA**: `901eefab742e44f443e54231fe8867e194e2ef2f`
- **Supersedes**: Extends rate-limiting architecture established in ADR-0001 and ADR-0005

## Context

During initial microservice development, a single uniform rate limit of 5 requests per minute (managed via `shared/infra/ratelimit` backed by Redis) was applied across nearly every authenticated endpoint in `chat-service`, `notification-service`, and `user-service`. The design treated all endpoints as equally sensitive under a blanket security floor.

While effective at stopping brute-force and spam attacks, this uniform 5-request/minute limit caused severe, reproducible UX breakage in real-world mobile app usage:

1. **WebSocket Connection Lockouts (`GET /chat/ws`)**:
   The WebSocket handshake endpoint in `chat-service` shared the blanket 5-req/min limiter. In normal mobile client lifecycles (app backgrounding/foregrounding, brief Wi-Fi/cellular handoffs, screen transitions), a client reconnects multiple times per minute. Exceeding 5 reconnects within 60 seconds triggered HTTP 429 lockouts, locking real users out of real-time messaging entirely.

2. **Read-Heavy Data Browsing Bottlenecks**:
   Read-only endpoints (`GET /users/jobs/owner`, `GET /users/jobs/mine`, `GET /users/ledger`, `GET /users/ratings`, `GET /users/jobs/reconciliation-queue`) shared the same 5-req/min write-action rate limiter. Standard mobile browsing actions—such as pulling to refresh, switching tabs, or toggling filters—exhausted the 5-request quota almost instantly, surfacing generic "Please try again later" errors during normal navigation.

3. **Systemic Double-Tap UX Races**:
   Rapid double-tapping on buttons before Flutter widget loading states (`isLoading`) re-rendered would fire duplicate asynchronous HTTP requests in parallel, causing the second request to hit 429 rate limits.

## Decision

We chose to explicitly prioritize legitimate user experience over a uniform, maximally-strict security floor by introducing **Endpoint-Classified Tiered Rate Limiting**:

1. **Connection-Lifecycle Tier (30 req/min)**:
   Assigned a dedicated Redis rate limiter (`chat:ws`, 30 req/min, 1-minute window) exclusively to `GET /chat/ws` in `services/chat-service/internal/handlers/chat.go`. This provides headroom for legitimate mobile network drops and app resume events while preserving lockout protection against aggressive connection flooding.

2. **Read-Heavy Browsing Tier (30 req/min)**:
   Created a dedicated read rate limiter (`user:read`, 30 req/min, 1-minute window) in `services/user-service/internal/handlers/handlers.go` for all high-frequency read endpoints (`GetOwnerJobs`, `GetCustomerJobs`, `GetLedger` at both IP and tenant call sites, `GetRatings`, `GetReconciliationQueue`).

3. **Infrequent Write-Action Tier (5 req/min - Unchanged)**:
   Preserved the original tight 5 req/min rate limiters on genuinely infrequent, high-risk write operations (`WalletDeposit`, `RateJob`, `CancelJob`, `ProposePrice`, `RespondPrice`, `TrackJob`, `ResolveReconciliation`, `HandleCreateTicket`). These actions do not require high frequency and benefit from tight anti-abuse controls (preventing financial fraud, review manipulation, and ticket spam).

4. **Shared Frontend Widget Tap-Debounce (600ms)**:
   Converted `PrimaryButton` and `SecondaryButton` (`frontend/lib/widgets/`) to `StatefulWidget` incorporating a built-in 600ms tap-debounce guard alongside `isLoading` state handling, eliminating double-tap 429 races across all mobile screens without modifying individual call sites.

## Endpoint Classification & Rate Limit Matrix

| Endpoint | Handler / Service | Old Limit | New Limit | Rate Limit Key / Namespace | Classification Tier | Rationale |
|---|---|---|---|---|---|---|
| `GET /chat/ws` | `HandleWebSocket` (`chat-service`) | 5 / min | **30 / min** | `chat:ws:<ip>` | Connection-Lifecycle | Mobile backgrounding, network switches, and tab navigation cause normal reconnects. |
| `GET /users/jobs/owner` | `GetOwnerJobs` (`user-service`) | 5 / min | **30 / min** | `user:read:jobs_owner:<owner_id>` | Read-Heavy Browsing | Tenant owners refresh job lists frequently while managing active orders. |
| `GET /users/jobs/mine` | `GetCustomerJobs` (`user-service`) | 5 / min | **30 / min** | `user:read:jobs_customer:<cust_id>` | Read-Heavy Browsing | Customers check order status and list views repeatedly during active bookings. |
| `GET /users/ledger` | `GetLedger` (`user-service`) | 5 / min | **30 / min** | `user:read:get_ledger_ip:<ip>` & `ledger_tenant:<id>` | Read-Heavy Browsing | Financial statement review involves frequent pagination and date range filtering. |
| `GET /users/ratings` | `GetRatings` (`user-service`) | 5 / min | **30 / min** | `user:read:get_ratings:<ip>` | Read-Heavy Browsing | Rating summary cards are fetched during profile browsing and job reviews. |
| `GET /users/jobs/reconciliation-queue` | `GetReconciliationQueue` (`user-service`) | 5 / min | **30 / min** | `user:read:jobs_reconciliation_queue:<owner_id>` | Read-Heavy Browsing | Escalated job queue requires regular review by tenant owners. |
| `POST /users/wallet/deposit` | `WalletDeposit` (`user-service`) | 5 / min | **5 / min** | `user:<ip>` | Infrequent Write-Action | Financial deposit attempts should remain strictly rate-limited against payment abuse. |
| `POST /users/jobs/rate` | `RateJob` (`user-service`) | 5 / min | **5 / min** | `user:rate_job:<ip>` | Infrequent Write-Action | Rating submission occurs once per completed job. |
| `POST /users/jobs/cancel` | `CancelJob` (`user-service`) | 5 / min | **5 / min** | `user:<tenant_id>` | Infrequent Write-Action | Cancellation is an infrequent state-change operation. |
| `POST /users/jobs/propose-price` | `ProposePrice` (`user-service`) | 5 / min | **5 / min** | `user:<ip>` | Infrequent Write-Action | Counter-offer submission occurs within structured 5-minute negotiation windows. |
| `POST /users/jobs/respond-price` | `RespondPrice` (`user-service`) | 5 / min | **5 / min** | `user:<ip>` | Infrequent Write-Action | Accepting/declining price proposals is a single state-changing decision. |
| `POST /users/jobs/track` | `TrackJob` (`user-service`) | 5 / min | **5 / min** | `user:<ip>` | Infrequent Write-Action | Booking creation occurs once per customer order session. |
| `POST /users/jobs/reconciliation/resolve` | `ResolveReconciliation` (`user-service`) | 5 / min | **5 / min** | `user:<ip>` | Infrequent Write-Action | Escrow dispute resolution is a deliberate operator intervention. |
| `POST /chat/tickets` | `HandleCreateTicket` (`chat-service`) | 5 / min | **5 / min** | `chat:ticket_create:<user_id>` | Infrequent Write-Action | Support ticket creation is an infrequent complaint action. |
| `POST /notifications/send` | `Send` (`notification-service`) | 5 / min | **5 / min** | `notification:<ip>` | Service-to-Service | Internal endpoint gated by `X-Internal-Token`, separate scaling domain. |

## Consequences

### Positive
- **Eliminated Chat Lockouts**: Client reconnections no longer lock users out of real-time messaging during ordinary mobile app use.
- **Smooth Browsing Experience**: Pull-to-refresh and tab navigation on job lists, ledgers, and ratings operate without false-positive 429 lockouts.
- **Double-Tap Protection**: Shared Flutter button widgets absorb rapid accidental taps client-side before network requests are dispatched.
- **Targeted Security Floor**: High-risk write endpoints remain tightly rate-limited (5 req/min), preserving anti-abuse protection where it matters most.

### Negative / Accepted Security Tradeoffs
- **Slightly Increased Scraping Headroom**: Raising read endpoint limits to 30 req/min allows a determined scraper 30 requests per minute per IP/identity instead of 5. Accepted as a necessary tradeoff since blocking real users is a far worse failure mode.
- **Monitoring & Revisit Triggers**: If automated scraping or resource exhaustion patterns are observed on read endpoints via CloudWatch logs or Redis rate-limit telemetry (`security event shipping`), individual endpoint limits can be tuned dynamically via config without structural code refactoring.

## Implementation Reference & Verification

- **Backend Rate Limit Separation**: Implemented in commit [`131a8a8133b8a4b7f58ada9a92cb0ed0cc0e6e96`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/services/chat-service/internal/handlers/chat.go). Verified via unit tests (`TestHandleWebSocket_RateLimiting`, `TestGetJobsByOwner`, `TestGetJobsByCustomer`, `TestRateJob_RateLimiting`, `TestGetLedger_RateLimiting`, `TestGetReconciliationQueue`), `gofmt`, `go build`, and `go vet`.
- **Frontend Button Tap Debounce**: Implemented in commit [`901eefab742e44f443e54231fe8867e194e2ef2f`](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/frontend/lib/widgets/primary_button.dart). Verified via `dart format`, `flutter analyze` (0 issues), and `flutter test` (159/159 full suite pass).

---

## Addendum: Independent Per-Endpoint Limiters & Ledger Double-Charge Resolution (2026-08-14)

### Problem Identified
During a systematic audit of rate-limiting telemetry in `user-service`, two critical flaws were discovered in the initial implementation of ADR-0016:

1. **Shared Counter Across Unrelated Read Endpoints**:
   A single shared `readLimiter` instance (`user:read`, 30 req/min) was passed to `GetOwnerJobs`, `GetCustomerJobs`, `GetLedger`, `GetRatings`, and `GetReconciliationQueue`. As a result, standard user navigation across screens (e.g. checking Wallet, viewing Job History, viewing Ratings) drained a single common 30-request counter. Hitting the limit on one screen blocked navigation on all other screens.

2. **Double-Charge Bug in `GetLedger`**:
   `GetLedger` executed two consecutive `CheckAndRecord` calls against the same `readLimiter` instance—first with `"get_ledger_ip:" + ip` and then with `tenantKey`. Every single HTTP request to `GET /users/ledger` deducted 2 tokens from the 30-req quota, effectively halving the endpoint's actual capacity to 15 req/min.

### Refactored Architecture & Correction
1. **Independent `RateLimiter` Instances**:
   Replaced the single `readLimiter` field in `UserService` with dedicated, decoupled limiter instances:
   - `ownerJobsLimiter` (`user:owner_jobs`, 60 req/min)
   - `customerJobsLimiter` (`user:customer_jobs`, 60 req/min)
   - `ledgerLimiter` (`user:ledger`, 60 req/min)
   - `ledgerIPLimiter` (`user:ledger_ip`, 60 req/min)
   - `ratingsLimiter` (`user:ratings`, 30 req/min)
   - `reconciliationLimiter` (`user:reconciliation`, 30 req/min)

2. **Correction — Independent Dual-Layer Protection for `GetLedger`**:
   The initial refactoring in commit `45431d5` removed the IP-based rate-limit check on `GetLedger` entirely, relying solely on tenant-scoped checks and edge gateway limits. This was an unauthorized deviation from the target architecture. The IP-based check has been restored via `ledgerIPLimiter` (`user:ledger_ip`, 60 req/min), running BEFORE token/role resolution to protect against unauthenticated ledger-scraping attempts. The tenant-based check (`ledgerLimiter`, 60 req/min) runs AFTER resolution. Crucially, each layer operates on its own dedicated `RateLimiter` instance, providing true dual-layer protection without double-charging a single counter.

3. **Cross-Service Audit**:
   Confirmed that `chat-service`, `notification-service`, `auth-service`, and `api-gateway` do not share rate limiters across unrelated endpoints. `user-service` was the sole service requiring structural limiter separation.

4. **Automated Test Coverage**:
   Added `TestGetLedger_IPRateLimitCheck`, `TestGetLedger_TenantRateLimitCheck`, and `TestReadRateLimiters_Independence` in `services/user-service/internal/handlers/read_rate_limiters_test.go`, explicitly verifying that IP-based rate limiting (keyed by IP) and tenant-based rate limiting (keyed by tenant ID) trigger independently without interfering with each other or unrelated endpoints.

---

## Addendum 2: Full Write-Action Limiter Isolation & Cascade Dispatch Headroom (2026-08-30)

### Motivation & Scope
While Addendum 1 decoupled read endpoints, write actions in `user-service` initially remained on a shared limiter (`newHandlerLimiter(5, "user")`). As the product added transport price negotiations and sequential cascade dispatch, sharing a single 5-req/min write bucket created artificial collisions (e.g. submitting a price proposal drained the budget needed to respond or track a job). Furthermore, API Gateway edge rate limiting (300 req/min) required isolation for long-lived Server-Sent Events (SSE) and container healthcheck loopback exemptions.

### Architectural Alignment
1. **Per-Action Write Limiters (`services/user-service/internal/handlers/handlers.go`)**:
   - `trackLimiter` (`user:track`, 20 req/min): Booking creation and active job tracking.
   - `proposePriceLimiter` (`user:propose_price`, 20 req/min): Counter-offer proposals during active negotiation.
   - `respondPriceLimiter` (`user:respond_price`, 20 req/min): Acceptance or rejection of transport price proposals.
   - `cancelJobLimiter` (`user:cancel_job`, 10 req/min): Job cancellations (accommodates retries while preventing state churn).
   - `rateJobLimiter` (`user:rate_job`, 10 req/min): Completion rating submissions.
   - `depositLimiter` (`user:deposit`, 10 req/min): E-wallet deposit operations.
   - `ticketLimiter` (`user:ticket`, 10 req/min): Support/complaint ticket creation.
   - `completeJobLimiter` (`user:complete_job`, 30 req/min): Order delivery completion confirmations.
   - `resolveReconLimiter` (`user:reconciliation_resolve`, 30 req/min): Dispute resolution by tenant owners.
   - `payoutLimiter` (`user:payout`, 30 req/min): Driver/owner withdrawal requests.
   - `subscriptionLimiter` (`user:subscription`, 30 req/min): Subscription status and tier upgrades.
   - `acceptOfferLimiter` (`user:accept_offer`, 30 req/min): Sequential courier offer acceptance.
   - `declineOfferLimiter` (`user:decline_offer`, 30 req/min): Sequential courier offer decline.

2. **Edge Gateway Isolation (`services/api-gateway/`)**:
   - **Baseline Edge Limit**: 300 req/min across standard client routes.
   - **SSE Stream Bucket**: Dedicated isolated Redis bucket (`gateway-sse`, 100 req/min) for `/api/v1/notifications/stream` so reconnection churn cannot starve general REST API traffic.
   - **Loopback Healthcheck Exemption**: Container healthcheck probes (`127.0.0.1`, `::1`) are completely exempt from rate limiting to prevent false-positive flapping of Docker container health status.


