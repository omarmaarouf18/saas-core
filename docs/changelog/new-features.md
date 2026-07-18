# New Features Changelog

This file tracks historical entries for the primary category: **New Features Changelog**.

---

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

## Username Propagation & Chat Point-in-Time Snapshot

- **Implementation Detail**: Updated `GET /auth/user` response to return `username`. Updated `GET /auth/kyb-kye/pending` (`GetPendingKYBKYESubmissions`) response to return `username` per submission. Updated `chat-service` to cache usernames upon WebSocket handshake (refreshed at connection init time or every 60 seconds on cache expiry), attach it to WebSocket clients, and embed `sender_username` inside real-time messages and the persisted database schema as a point-in-time snapshot captured at send-time (historical messages preserve the username active when sent). Support agents are assigned a fallback display name matching `Agent <agent_id>` because they are system operators who do not have a standard `models.User` record.
  On the frontend: added a username input field to the signup and employee registration forms with rune-aware length check and dynamic RTL text direction detection for Arabic script input. Updated `UserProfile` and `ChatMessage` Dart models to parse `username` and `sender_username` respectively. Propagated the username display to the chat screen (with agent/legacy user fallbacks), home dashboard banners, profile detail tables, and employee dashboard screen.
- **Commit SHA**: `0c7930212a897a3f31daa42dab802597089fd0f5` (backend), `[UNVERIFIED - PENDING COMMIT]` (frontend)
- **Verification**: Verified via backend integration tests in `auth-service` and `chat-service`, and Flutter widget tests in `widget_test.dart` asserting signup validation logic and chat sender name rendering. ✅


