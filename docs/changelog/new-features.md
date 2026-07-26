# New Features Changelog

This file tracks historical entries for the primary category: **New Features Changelog**.

---

## Negotiable Transport Pricing Handler Wiring & Endpoints

- **Implementation Detail**: Updated `TrackJob` for `transport` category services to initialize `JobStatusAwaitingPriceResponse`, compute `SuggestedPrice`, validate optional customer initial proposal, and defer escrow locking. Added endpoints `POST /users/jobs/propose-price` (single-shot proposal enforcement, ±50% bound check, 5m expiry timer) and `POST /users/jobs/respond-price` (accept sets `AgreedPrice` and activates job; decline cancels with `price_disagreement`). Implemented lazy proposal expiry in `GetJob` and proposal endpoints. Added unit test suite `TestNegotiableTransportPricing`.
- **Commit SHA**: ``036901ba292a73d2bf67cd14603f643d5d25e74c``
- **Verification**: Verified via `gofmt -l .`, `go vet ./...`, `go test ./... -v -race -count=1`, `make docs-check`, and pre-push CI gate. ✅

## Negotiable Transport Pricing Data Model Foundation

- **Implementation Detail**: Added negotiable pricing fields to `Job` struct (`SuggestedPrice`, `ProposedPrice`, `ProposedBy`, `AgreedPrice`, `PriceProposalExpiresAt`), defined explicit `JobStatusAwaitingPriceResponse` enum state, and implemented `ValidPriceProposal` validation helper enforcing bounds $[0.5 \times P_{\text{system}}, 1.5 \times P_{\text{system}}]$.
- **Commit SHA**: ``beac4e3030b1909cbc08ee6cdefe32923198b185``
- **Verification**: Verified via `go test ./... -v -race -count=1` from `services/user-service` passing all table-driven unit tests. ✅

## Owner Employee Listing Endpoint (GET /auth/employees)

- **Implementation Detail**: Added GET /auth/employees endpoint letting tenant owners list all employees registered under their account. Authenticated via JWT (Authorization Bearer header or owner_token query parameter), IDOR-protected by resolving owner ID directly from claims, returns employee ID, username, email, is_active status (including frozen accounts), and created_at while omitting sensitive fields. Protected by Redis-backed rate limiting (30 req/min per owner).
- **Commit SHA**: ``13e6c2b832667cec57135811e3a122727b730eea``
- **Verification**: Verified via auth-service unit tests (TestGetEmployees) and E2E curl testing against Docker stack. ✅

## COD Platform Fee Overdraft

- **Implementation Detail**: Deducts 15% platform fee directly from Owner e-wallet upon job completion, allowing negative balances.
- **Commit SHA**: ``6edf1b7c825b37cc15b16dbc348026c4b689724b``
- **Verification**: Verified in `user-service/internal/store/mongodb.go`. ✅

## Rating & Comment System

- **Implementation Detail**: Rating and comment submissions on completed jobs with average rating queries.
- **Commit SHA**: ``6edf1b7c825b37cc15b16dbc348026c4b689724b``
- **Verification**: Verified in `user-service/internal/handlers/handlers.go`. ✅

## Job Cancellation & Escrow Refund

- **Implementation Detail**: Added job status cancelled, CancelJob handler, validation checks, and automatic escrow refund to owner.
- **Commit SHA**: ``6edf1b7c825b37cc15b16dbc348026c4b689724b``
- **Verification**: Verified via user-service integration tests. ✅

## Live Location Tracking

- **Implementation Detail**: Broadcast real-time employee locations via WebSockets to owner and client.
- **Commit SHA**: ``6b473a730fa632e45dea42335c2b899488e0aad3``
- **Verification**: Verified via integration tests and E2E simulation. ✅

## Redis Rate Limiting Stage 1: Wrapper & Config

- **Implementation Detail**: Created shared ratelimit package wrapping Redis client with atomic Lua scripts, and updated all 5 config packages to load REDIS_URI.
- **Commit SHA**: ``b8e33bf7f793d6bcf4a67927a4db4bc182daf275``
- **Verification**: Verified via compilation and unit tests. ✅

## Redis Rate Limiting Stage 2: api-gateway

- **Implementation Detail**: Migrated the api-gateway edge rate limiter to use the Redis-backed wrapper.
- **Commit SHA**: ``198123af7a0597195afc587c036b29bd42ee15b3``
- **Verification**: Verified via compilation. ✅

## Redis Rate Limiting Stage 3: auth-service

- **Implementation Detail**: Migrated the auth-service dual-key (IP + email) rate limiter to use Redis.
- **Commit SHA**: ``a1011c78986282bc86368cac253804b2b04a79d5``
- **Verification**: Verified via compilation and test execution. ✅

## Redis Rate Limiting Stage 4: chat, user & notification services

- **Implementation Detail**: Migrated rate limiters in chat, user, and notification services to use Redis-backed wrapper.
- **Commit SHA**: ``315a0aa7cf056b4782759c5b6c5c75d46792e5e5``
- **Verification**: Verified via compilation and test execution. ✅

## Redis Rate Limiting Stage 6: Verification & Concurrency Tests

- **Implementation Detail**: Created concurrency and cross-instance rate limit tests, and ran full test suite verification.
- **Commit SHA**: ``a24759a6621f053c202fdcfeded9e0c1117be9c8``
- **Verification**: Verified via integration and concurrency tests. ✅

## Resilience Stage 1: Wrapper Client

- **Implementation Detail**: Created shared resilience package implementing retry-with-backoff + jitter and circuit-breaker wrapper around http.Client.
- **Commit SHA**: ``d44b18ef176d2a3877d065376f67ecad374afe27``
- **Verification**: Verified via compilation. ✅

## Resilience Stage 2 & 3: Wiring & Fail-Closed Errors

- **Implementation Detail**: Wired separate circuit breaker and retry instances into internal HTTP clients and proxies, returning 503 Service Unavailable and failing closed on timeouts.
- **Commit SHA**: ``d81e578f9c6c7042cea715d7f6eba8a57922764f``
- **Verification**: Verified via compilation and test execution. ✅

## Resilience Stage 4: Observability & Health Integration

- **Implementation Detail**: Configured structured logs for circuit breaker transitions and exposed dependency breaker status on /health endpoints.
- **Commit SHA**: ``c6a6013cd021e518650a80280b29aa6d298f8c95``
- **Verification**: Verified via compilation and test execution. ✅

## Resilience Stage 5: Resilience Tests & Verification

- **Implementation Detail**: Created unit and integration tests verifying retry limit capping, circuit breaker trip/recovery transitions, and fail-closed security properties.
- **Commit SHA**: ``c7a5049f90956626b333ea1fbaf1dfcc593fc5b4``
- **Verification**: Verified via integration tests. ✅

## Complaint Routing Stage 1: Data Model

- **Implementation Detail**: Added database collections, Go model structs, and indexes for support agents and complaint tickets in chat-service store.
- **Commit SHA**: ``d4d6e95a5a2d2dec1ca4ed2cc0b91ddc5ac41a0c``
- **Verification**: Verified via compilation. ✅

## Complaint Routing Stage 3, 4, 5: WebSocket & HTTP Wiring

- **Implementation Detail**: Wired complaint ticket channel/access checks into chat WebSocket/Hub, added structured security audit logging, and applied Redis rate limiter.
- **Commit SHA**: ``e211e6dc8c79bf271e66f6fe63b54e5d38598a28``
- **Verification**: Verified via compilation. ✅

## Complaint Routing Stage 6: Concurrency & Access Tests

- **Implementation Detail**: Added unit and concurrency tests proving atomic support agent assignment, queueing, and IDOR mitigation for ticket access.
- **Commit SHA**: ``16dc62ede98c8bb0ce5aaf41ceea267e0cbe11c7``
- **Verification**: Verified via test execution. ✅

## KYB/KYE Data Model

- **Implementation Detail**: Extended auth-service User model to support IDFrontDoc, IDBackDoc, SelfieDoc, BusinessProofDoc, and review metadata.
- **Commit SHA**: ``d4d6e95a5a2d2dec1ca4ed2cc0b91ddc5ac41a0c``
- **Verification**: Verified via compilation. ✅

## KYB/KYE Local Storage

- **Implementation Detail**: Created local-disk storage implementation (securing document files on disk and generating short-lived signed token URLs).
- **Commit SHA**: ``2fc19e412253afda248acab62720bdaa2bbe9da4``
- **Verification**: Verified via compilation. ✅

## KYB/KYE Uploads & Reviews

- **Implementation Detail**: Implemented file validation, multipart uploads, pending submissions list, review gating, signed document views, and audit logging.
- **Commit SHA**: ``35dab58ce5cc4150e778b32c1ca66c66de43431e``
- **Verification**: Verified via integration tests. ✅

## Reviewers Collection

- **Implementation Detail**: Added reviewers collection, unique token indexing, and query/insert methods in auth-service store.
- **Commit SHA**: ``1f46ed23763eca30135f43afdd0f52589174ec0f``
- **Verification**: Verified via compilation. ✅

## Username Field & Validation

- **Implementation Detail**: Added `Username` field to the `User` model and `SignupRequest` structs (required, not omitempty). Added a validation check to `Signup` handler requiring 3-30 character username length (measured by runes to support multi-byte strings) and allowed character whitelist supporting both Latin and Arabic scripts (U+0600–U+06FF) alongside spaces, digits, and underscores, while blocking unsafe injection strings. Enforced global uniqueness on `username` via a MongoDB unique index in `ensureIndexes`, returning clear, differentiated errors (`username already taken` vs `email already registered`) on duplicate key conflicts.
- **Commit SHA**: ``7fa065a742bb209cfc8fe9e0a13a960495066bf0``
- **Verification**: Verified via `TestSignupUsernameValidation` covering success, missing, short/long, invalid chars, valid Arabic, mixed Arabic/Latin, XSS tag rejection, and differentiated duplicate-key errors. ✅

- **Implementation Detail**: Updated `GET /auth/user` response to return `username`. Updated `GET /auth/kyb-kye/pending` (`GetPendingKYBKYESubmissions`) response to return `username` per submission. Updated `chat-service` to cache usernames upon WebSocket handshake (refreshed at connection init time or every 60 seconds on cache expiry), attach it to WebSocket clients, and embed `sender_username` inside real-time messages and the persisted database schema as a point-in-time snapshot captured at send-time (historical messages preserve the username active when sent). Support agents are assigned a fallback display name matching `Agent <agent_id>` because they are system operators who do not have a standard `models.User` record.
  On the frontend: added a username input field to the signup and employee registration forms with rune-aware length check and dynamic RTL text direction detection for Arabic script input. Updated `UserProfile` and `ChatMessage` Dart models to parse `username` and `sender_username` respectively. Propagated the username display to the chat screen (with agent/legacy user fallbacks), home dashboard banners, profile detail tables, and employee dashboard screen.
  
  *Security & Minimal Disclosure Design*: To resolve employee usernames on the job status screen client-side without exposing sensitive attributes (such as `kyc_status`, `role`, `tenant_id`, `email`), a scoped public profile endpoint (`GET /auth/user/public-profile`) was introduced. It requires a valid signed requester token and returns only the target user's `id` and `username` (public display name lookups are allowed, but sensitive account data is strictly protected from disclosure).
- **Commit SHA (backend)**: `0c7930212a897a3f31daa42dab802597089fd0f5`
- **Commit SHA (frontend)**: `74ffbb7e4d269c405b6caff4c883459430508e22`
- **Verification**: Verified via backend integration tests in `auth-service` and `chat-service`, and Flutter widget tests in `widget_test.dart` asserting signup validation logic and chat sender name rendering. ✅

## Programmatic Dark Theme

- **Implementation Detail**: Added programmatic dark theme support to the Flutter frontend application using `quickDeliveryDarkTheme`. Seeded the dark scheme from `Color(0xFF0D1321)` with `Brightness.dark`, overriding the `secondary` role to preserve the brand gold (`Color(0xFFFFC107)`). Configured `MaterialApp` with both light and dark themes and set `themeMode` to `ThemeMode.system`.
- **Commit SHA**: ``149c3a823908a144511f1226767f17d4505ee80b``
- **Verification**: Verified via `flutter analyze` and widget tests confirming clean compilation and theme initialization. ✅

## Server-Sent Events Notifications

- **Implementation Detail**: Built the SSE notifications screen (Phase 6 - SSE) on the frontend. Created `NotificationModel` and `NotificationsProvider` to subscribe to the API Gateway proxied SSE stream `/notifications/stream?token=<token>` using the `flutter_client_sse` package. Implemented `NotificationsScreen` with category chip filtering, chronological group splits (Today, Yesterday, Earlier), dynamic connection status/errors banner, and deep-link tracking to `JobStatusScreen`. Registered the provider in `main.dart` and added a notification bell icon with an unread badge to dashboard AppBars in `home_screen.dart`, `customer_marketplace_screen.dart`, and `employee_jobs_screen.dart`.
- **Commit SHA**: ``a025ecebaad7edfeeb4f2dd7f620856c664d7cf9``
- **Verification**: Verified via `flutter analyze` and widget tests checking clean compilation, state mapping, and setup. ✅

## Subscription Plans Screen

- **Implementation Detail**: Built the Subscription screen (Phase 7 - Ratings & Subscriptions) on the frontend. Created `SubscriptionScreen` and wired it to `OwnerProvider.updateSubscription` to interact with POST `/users/subscription`. Displays the current subscription tier, supports instant downgrades/switches to the Free Plan, and alerts/warns the user when the Professional Plan is selected and activation is pending manual approval. Integrated the page navigation as a tap interaction on the "Subscription Tier" dashboard card in `home_screen.dart`.
- **Commit SHA**: ``eed6786bb28254b553cd272e6d979c18ff58abfb``
- **Verification**: Verified via `flutter analyze` and widget tests checking clean compilation and metric integration. ✅

## Blind Rating Screen

- **Implementation Detail**: Built the Blind Rating screen (Phase 7 - Ratings & Subscriptions) on the frontend. Created `RatingScreen` supporting 1-5 star score selection and text comment inputs. Wired it via `MarketplaceProvider.rateJob` to query POST `/users/jobs/rate`. Implemented a fallback in the backend handler `RateJob` so that it accepts the raw ratee user ID directly when JWT resolution fails, correcting a design gap where the frontend previously had to pass the other party's private token. Queries the user's received ratings via GET `/users/ratings` to dynamically determine if the partner has rated the job, displaying a live blind status card. Added the navigation trigger button to `JobStatusScreen` for completed jobs.
- **Commit SHA**: ``8d3d17752486b92d71435108f6803e4ac22d07d9``
- **Verification**: Verified via backend unit tests (`TestUserServiceHandlers`) and frontend static analysis + widget tests. ✅

## Rating Summary Component

- **Implementation Detail**: Built the reusable `RatingSummaryCard` (Phase 7 - Ratings & Subscriptions) on the frontend. Renders an average star rating using full, half, and empty icons, alongside a total review count. Embedded the component inside the Owner dashboard welcome panel to show service reputation, and inside Customer Marketplace service cards to highlight carrier trustworthiness.
- **Commit SHA**: ``f01d25be38c7d0cdd70f59ca696c043e2f0db08e``
- **Verification**: Verified via `flutter analyze` and widget tests confirming clean layout integration. ✅

## Request Field Token Aliases

- **Implementation Detail**: Added clearer `_token` field name aliases alongside legacy `_id` and raw parameter names across Go backend handlers (`user-service` and `auth-service`) to resolve naming clarity issues (since these fields carried signed JWT tokens instead of raw database IDs). Implemented alias mappings for: `user_token` (as alias for `user_id` / `id`), `owner_token` (as alias for `owner_id`), `employee_token` (as alias for `employee_id`), `requester_token` (as alias for `requester_token`), `tenant_token` (as alias for `tenant_id`), and `rated_by_token`/`rated_user_token` (as aliases for `rated_by`/`rated_user`). Enforced backward compatibility by resolving either variant, preferring the new naming. Updated API generator `KnownEndpoints` descriptions and updated `APPLICATION_MAP.md` via `make docs`.
- **Commit SHA**: ``f967906b413fedadc38dae163766697c9e7aeb60``
- **Verification**: Verified via backend integration test suites (`TestTokenNameAliasesCompatibility` in `user-service`, `TestTokenNameAliasesInAuth` in `auth-service`) and local `make docs-check`. ✅

## Resend Email OTP Dispatcher

- **Implementation Detail**: Implemented `ResendDispatcher` in `services/auth-service/internal/otp/resend_dispatcher.go` to dispatch 2FA and signup OTP codes via the Resend REST API (`POST https://api.resend.com/emails`). Configured non-local mode (`APP_ENV!=local`) to activate `ResendDispatcher` when `RESEND_API_KEY` is present and fall back to `MockSMSDispatcher` with a warning when omitted. Preserved `MockSMSDispatcher` for local development (`APP_ENV=local`). Input parameters and log outputs are sanitized against carriage return/newline characters to prevent header and log injection vulnerabilities (satisfying gosec G704/G705/G706 rules). Added `RESEND_API_KEY` and `RESEND_FROM_EMAIL` configuration settings to `auth-service` and `infrastructure/.env.example`.
- **Commit SHA**: ``a95e5254d6b58706f6174a67187b0b722c43f711``
- **Verification**: Verified via unit tests (`TestResendDispatcher_Dispatch_Success`, `TestResendDispatcher_Dispatch_APIErrorResponse`, `TestResendDispatcher_Dispatch_NetworkError`, `TestResendDispatcher_Dispatch_InputSanitizationAndValidation`) using an `httptest.Server` mock, and full-scope gosec scanning. ✅







