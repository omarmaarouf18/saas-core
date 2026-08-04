# New Features Changelog

This file tracks historical entries for the primary category: **New Features Changelog**.

## Unified Settings Screen (Account Action Center) & Theme Persistence (ADR-0014 Part 1)

- **Implementation Detail**: Implemented Part 1 of the Unified Settings screen per ADR-0014. Created `ThemeProvider` (`frontend/lib/providers/theme_provider.dart`) managing dynamic `ThemeMode` (Light, Dark, System) and persisting choices across app restarts via `FlutterSecureStorage` under key `theme_mode`. Wired `ThemeProvider` into `main.dart` `MultiProvider` and `MaterialApp`. Created `SettingsScreen` (`frontend/lib/screens/settings_screen.dart`) featuring: (1) 3-way SegmentedButton theme mode selector, (2) Language row with "Coming Soon" badge and feedback snackbar, (3) Role-conditional sections ("Owner Configuration" for owner, "My Account" for customer/user, omitted for employee) with "Coming Soon" badges, (4) Support section ("Customer Service") with coming-soon feedback and `// TODO: wire to POST /chat/tickets once built` comment, and (5) Centralized red Logout button calling `logoutAndClearProviders`. Replaced duplicated Logout buttons in `home_screen.dart`, `customer_marketplace_screen.dart`, and `employee_jobs_screen.dart` with a single Settings gear icon. Created unit/widget test suite in `frontend/test/settings_screen_test.dart`.
- **Commit SHA**: ``136676acc0f7359507d29c73d1751d0109fbe7e6``
- **Verification**: Verified via `flutter analyze` (0 issues found) and `flutter test` (112/112 unit & widget tests pass cleanly). ✅

## Frontend Batch 1 Auth & Token Lifecycle Wiring

- **Implementation Detail**: Implemented full Auth & Token Lifecycle wiring (Batch 1 of `FRONTEND_INTEGRATION_SCOPE.md`). Updated `ApiClient` (`frontend/lib/core/api_client.dart`) with a concurrency-locked HTTP 401 response interceptor that executes silent `/auth/refresh` calls using current JWT, retries original requests on success, and invokes `onAuthFailed` on failure. Extended `AuthProvider` (`frontend/lib/providers/auth_provider.dart`) with `logout()` (calling `POST /auth/logout` and unregistering FCM device token), `forgotPassword(email)` (calling `POST /auth/forgot-password`), and `resetPassword(email, otp, newPassword)` (calling `POST /auth/reset-password`). Created `ForgotPasswordScreen` and `ResetPasswordScreen` following existing OTP/themed UI conventions (`ThemedTextField`, `PrimaryButton`, `ThemedErrorBanner`). Added "Forgot password?" link to `LoginScreen` and wired `logoutAndClearProviders` across all main role screens (`home_screen.dart`, `customer_marketplace_screen.dart`, `employee_jobs_screen.dart`). Updated `STATUS.md` file tracking index. Verified end-to-end against live backend at `https://api.logiclinkeg.tech`.
- **Commit SHA**: ``272294b8b51621928c08c7ee649c0d8e65255889``
- **Verification**: Verified via `flutter test` (46/46 full suite pass), `flutter analyze` (0 issues), live backend `curl` responses (`POST /auth/forgot-password` 200 OK, `POST /auth/reset-password` 401 on invalid OTP, `POST /auth/refresh` 401 on invalid JWT, `POST /auth/logout` 401 on invalid JWT), and pre-push hook validation (`.githooks/pre-push` gate exit code 0). ✅

## Frontend Owner Escrow Reconciliation Review Screen & Provider Implementation

- **Implementation Detail**: Implemented Flutter frontend Owner Escrow Reconciliation Review screen and provider consuming backend endpoints `GET /users/jobs/reconciliation-queue` and `POST /users/jobs/reconciliation-resolve`. Created `ReconciliationJob` model (mapping `escrowFailureReason` to human-readable explanations like "Distance mismatch — under 70% of booked distance"), `ReconciliationProvider` (with queue fetching and resolution execution, surfacing 409 conflict and 429 rate-limit responses explicitly), and `OwnerReconciliationQueueScreen` (card list with detailed notes, locked escrow amounts, empty/loading states, and confirmation dialogs before fund movement). Wired provider in `main.dart` and added navigation entry points in `home_screen.dart` (AppBar icon & dashboard metric card).
- **Commit SHA**: ``cd94f15851ca13b561f05aad65b424e598461f22``
- **Verification**: Verified via `flutter analyze` (0 issues found), `flutter test test/reconciliation_queue_test.dart` (5/5 widget tests pass), `flutter test` (all pass), `make docs-check`, and `.githooks/pre-push` gate (exit code 0). ✅

## Admin/Owner Escrow Reconciliation Review Endpoints Implementation

- **Implementation Detail**: Implemented owner/admin escrow reconciliation queue review and resolution endpoints in `user-service`. Added `GET /users/jobs/reconciliation-queue` for tenant owners to list jobs in status `escrow_reconciliation_required` with full context (`ReconciliationNote`, `EscrowFailureReason`, `LockedEscrowAmount`). Added `POST /users/jobs/reconciliation-resolve` accepting resolution decisions (`release_to_employee` or `refund_to_customer`), executing fund release/refund via existing wallet/escrow methods, updating job status and reconciliation fields, and shipping security audit events (`ESCROW_RECONCILIATION_RESOLVED`). Enforced strict owner role gating (`resolveTokenWithRole`), tenant isolation IDOR protection, identity-based rate limiting (30 req/min), and status idempotency (409 Conflict on double resolution). Added `{owner_id, status}` index to MongoDB store (`GetReconciliationQueueByOwner`). Updated ADR-0007 tradeoffs to reflect completed Redis throttle migration.
- **Commit SHA**: ``cba5f6c82dcd85cd4192261f5c9d973b12faaf21``
- **Verification**: Verified via `go test ./services/user-service/internal/handlers -run "TestGetReconciliationQueue|TestResolveReconciliation"` (8/8 subtests pass), `go test ./services/user-service/internal/handlers/...` (all pass), `make docs-check`, `gofmt -l .`, and `.githooks/pre-push` gate (exit code 0). ✅

## ADR-0008 Live Employee Map Tracking Backend & End-to-End Verification

- **Implementation Detail**: Implemented backend support for ADR-0008 Live Employee Map Tracking across microservices. Extended `canAccessChannel` in `services/chat-service/internal/handlers/chat.go` to authorize `"fleet:<owner_id>"` channel subscriptions for users with the `"owner"` role. Wired `UpdateJobLocation` in `services/user-service/internal/handlers/handlers.go` to send background HTTP location broadcast POST requests to `chat-service` for BOTH `"job:<job.ID>"` and `"fleet:<job.OwnerID>"`. Added `active_only=true` query filtering to `GET /users/jobs/owner` for initial fleet hydration. Added `CurrentLocation` field to `OwnerJobResponse` DTO and `NewOwnerJobResponse` mapping. Built `TestADR0008_E2E_LiveEmployeeMapTracking` non-mocked integration test verifying real WebSockets connections, `"fleet:<owner_id>"` channel subscription authorization, and real-time location update broadcasts. Updated ADR-0008 status to Accepted.
- **Commit SHA**: ``17ebd52e1d88246c5141f793abfd08c5515cc133``
- **Verification**: Verified via `go test ./services/chat-service/...` (`TestCanAccessChannel` 11/11 subtests pass), `go test ./services/user-service/...` (`TestADR0008_E2E_LiveEmployeeMapTracking` passes cleanly), `gofmt -l .`, `make docs-check`, `flutter analyze` (0 issues), and `flutter test` (10/10 tests pass). ✅

## ADR-0008 Live Employee Map Tracking Frontend Implementation

- **Implementation Detail**: Implemented ADR-0008 Flutter frontend screens, provider, and models for live employee map tracking using `flutter_map` (v7.0.2) and OpenStreetMap raster tiles with required custom `User-Agent` header (`QuickDeliveryApp/1.0`) and configurable compile-time tile URL template (`MAP_TILE_URL`). Created `OwnerFleetMapScreen` for tenant owners (subscribing to `fleet:<owner_id>` WebSocket stream with initial state hydration via `GET /users/jobs/owner`) and `CustomerJobMapScreen` for customer active job tracking (subscribing to `job:<job_id>` WebSocket stream with initial state hydration via `GET /users/jobs/get`). Added `MapTrackingProvider` with initial HTTP hydration and WebSocket streaming, exponential backoff reconnection, and connection status banners.
- **Commit SHA**: ``7e3c3eb59faaab14f1d576ac217a50e221e3e116``
- **Verification**: Verified via `flutter analyze` (0 issues) and `flutter test` (6 new widget unit tests in `map_tracking_test.dart` passing cleanly). ✅

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

## Forgot Password & Reset Password Endpoints

- **Implementation Detail**: Implemented `POST /auth/forgot-password` and `POST /auth/reset-password` in `auth-service` reusing the existing AES-256-GCM encrypted OTP infrastructure (`SetOTP` / `VerifyOTP` in `mongodb.go`). `POST /auth/forgot-password` returns an anti-enumeration generic 200 OK response regardless of email existence, rate limits per IP and per email, generates/encrypts a 5-minute OTP code, and dispatches it via `a.dispatcher.Dispatch`. `POST /auth/reset-password` validates `email`, `otp`, and `new_password`, enforces IP/email rate-limiting lockouts, calls `store.VerifyOTP`, bcrypt-hashes the new password, updates the user password, and clears OTP fields (`otp_code`, `otp_verified`, `otp_expires_at`) to prevent replay attacks. Added unit test suite covering (a) identical anti-enumeration response for existing vs non-existent emails, (b) forgot-password rate limiting, (c) reset-password password update and old password failure, (d) invalid/expired OTP rejection with generic error & rate-limit recording, (e) missing password policy validation, and (f) OTP reuse prevention. Updated API map documentation via `make docs`.
- **Commit SHA**: ``ee443e39358b7f4c06fe7eb2f2a57b2f4e4c8d79``
- **Verification**: Verified via `go test -v ./internal/handlers -run "TestForgotPassword_|TestResetPassword_"` (6/6 pass) and `make docs`. ✅

## Job Completion Frontend Wiring

- **Implementation Detail**: Wired `POST /users/jobs/complete` into the Flutter frontend. Added `completeJob(String jobId)` method to `EmployeeJobsProvider` (`frontend/lib/providers/employee_jobs_provider.dart`) and rendered "Complete Job" action button in `EmployeeJobsScreen` (`frontend/lib/screens/employee_jobs_screen.dart`) exclusively for active/in-progress jobs. Features confirmation modal (`ConfirmActionDialog`), double-submission loading state, inline error banner via `friendlyErrorMessage`, and immediate job status update to COMPLETED. Added 4 widget tests (`frontend/test/employee_jobs_screen_test.dart`).
- **Commit SHA**: ``8f20aa6c78ec97ccf4adb605b57003743579880d``
- **Verification**: Verified via `flutter analyze` (0 issues) and `flutter test` (100% pass, 50/50 test cases). ✅

## Job Cancellation Frontend Wiring (POST /users/jobs/cancel)

- **Implementation Detail**: Wired `POST /users/jobs/cancel` into the Flutter frontend with strict role-specific and state-specific authorization logic. Added `cancelJob` method to `MarketplaceProvider` (`frontend/lib/providers/marketplace_provider.dart`) and `OwnerProvider` (`frontend/lib/providers/owner_provider.dart`). Created reusable `CancelJobDialog` (`frontend/lib/widgets/cancel_job_dialog.dart`) requiring a non-empty cancellation reason (confirm button disabled when empty). For tenant Owners: rendered "Cancel Job" buttons on `home_screen.dart` (Owner Dashboard) for pending and active jobs. For Customers: rendered "Cancel Job" button on `job_status_screen.dart` for pending jobs, and presented "Open a Complaint Ticket" affordance for active jobs with `// TODO` annotation referencing upcoming ticket endpoint wiring. Cancel buttons are completely omitted for completed and cancelled jobs. Added 6 widget tests in `frontend/test/job_cancellation_test.dart`.
- **Commit SHA**: ``c9e9c9cdbc8bdce1194098ccb5c4d67a4f457fa1``
- **Verification**: Verified via `flutter analyze` (0 issues) and `flutter test` (100% pass, 57/57 test cases). ✅

## Device GPS Location Permission Infrastructure (Part 1 of 2)

- **Implementation Detail**: Added `geolocator: ^12.0.0` dependency to `frontend/pubspec.yaml` (resolving cleanly without version conflicts against `web_socket_channel`). Configured foreground-only Android permission (`ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` in `AndroidManifest.xml`) and iOS permission (`NSLocationWhenInUseUsageDescription` in `Info.plist`). Created isolated `requestLocationPermission` helper utility (`frontend/lib/core/location_permission.dart`) returning unified `LocationPermissionResult` enum (`granted`, `denied`, `deniedForever`, `serviceDisabled`). Added unit test suite in `frontend/test/location_permission_test.dart` using `MockGeolocatorPlatform` with `MockPlatformInterfaceMixin` covering all permission result states.
- **Commit SHA**: ``0ee8e7858bcb87dd1e92bbcbc4c121155f673546``
- **Verification**: Verified via `flutter analyze` (0 issues) and `flutter test` (100% pass, 64/64 test cases). ✅







