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
- **Commit SHA**: ``current``
- **Verification**: Verified via user-service integration tests. ✅

## Live Location Tracking

- **Implementation Detail**: Broadcast real-time employee locations via WebSockets to owner and client.
- **Commit SHA**: ``current``
- **Verification**: Verified via integration tests and E2E simulation. ✅

## Redis Rate Limiting Stage 1: Wrapper & Config

- **Implementation Detail**: Created shared ratelimit package wrapping Redis client with atomic Lua scripts, and updated all 5 config packages to load REDIS_URI.
- **Commit SHA**: ``current``
- **Verification**: Verified via compilation and unit tests. ✅

## Redis Rate Limiting Stage 2: api-gateway

- **Implementation Detail**: Migrated the api-gateway edge rate limiter to use the Redis-backed wrapper.
- **Commit SHA**: ``current``
- **Verification**: Verified via compilation. ✅

## Redis Rate Limiting Stage 3: auth-service

- **Implementation Detail**: Migrated the auth-service dual-key (IP + email) rate limiter to use Redis.
- **Commit SHA**: ``current``
- **Verification**: Verified via compilation and test execution. ✅

## Redis Rate Limiting Stage 4: chat, user & notification services

- **Implementation Detail**: Migrated rate limiters in chat, user, and notification services to use Redis-backed wrapper.
- **Commit SHA**: ``current``
- **Verification**: Verified via compilation and test execution. ✅

## Redis Rate Limiting Stage 6: Verification & Concurrency Tests

- **Implementation Detail**: Created concurrency and cross-instance rate limit tests, and ran full test suite verification.
- **Commit SHA**: ``current``
- **Verification**: Verified via integration and concurrency tests. ✅

## Resilience Stage 1: Wrapper Client

- **Implementation Detail**: Created shared resilience package implementing retry-with-backoff + jitter and circuit-breaker wrapper around http.Client.
- **Commit SHA**: ``current``
- **Verification**: Verified via compilation. ✅

## Resilience Stage 2 & 3: Wiring & Fail-Closed Errors

- **Implementation Detail**: Wired separate circuit breaker and retry instances into internal HTTP clients and proxies, returning 503 Service Unavailable and failing closed on timeouts.
- **Commit SHA**: ``current``
- **Verification**: Verified via compilation and test execution. ✅

## Resilience Stage 4: Observability & Health Integration

- **Implementation Detail**: Configured structured logs for circuit breaker transitions and exposed dependency breaker status on /health endpoints.
- **Commit SHA**: ``current``
- **Verification**: Verified via compilation and test execution. ✅

## Resilience Stage 5: Resilience Tests & Verification

- **Implementation Detail**: Created unit and integration tests verifying retry limit capping, circuit breaker trip/recovery transitions, and fail-closed security properties.
- **Commit SHA**: ``current``
- **Verification**: Verified via integration tests. ✅

## Complaint Routing Stage 1: Data Model

- **Implementation Detail**: Added database collections, Go model structs, and indexes for support agents and complaint tickets in chat-service store.
- **Commit SHA**: ``current``
- **Verification**: Verified via compilation. ✅

## Complaint Routing Stage 3, 4, 5: WebSocket & HTTP Wiring

- **Implementation Detail**: Wired complaint ticket channel/access checks into chat WebSocket/Hub, added structured security audit logging, and applied Redis rate limiter.
- **Commit SHA**: ``current``
- **Verification**: Verified via compilation. ✅

## Complaint Routing Stage 6: Concurrency & Access Tests

- **Implementation Detail**: Added unit and concurrency tests proving atomic support agent assignment, queueing, and IDOR mitigation for ticket access.
- **Commit SHA**: ``current``
- **Verification**: Verified via test execution. ✅

## KYB/KYE Data Model

- **Implementation Detail**: Extended auth-service User model to support IDFrontDoc, IDBackDoc, SelfieDoc, BusinessProofDoc, and review metadata.
- **Commit SHA**: ``current``
- **Verification**: Verified via compilation. ✅

## KYB/KYE Local Storage

- **Implementation Detail**: Created local-disk storage implementation (securing document files on disk and generating short-lived signed token URLs).
- **Commit SHA**: ``current``
- **Verification**: Verified via compilation. ✅

## KYB/KYE Uploads & Reviews

- **Implementation Detail**: Implemented file validation, multipart uploads, pending submissions list, review gating, signed document views, and audit logging.
- **Commit SHA**: ``current``
- **Verification**: Verified via integration tests. ✅

## Reviewers Collection

- **Implementation Detail**: Added reviewers collection, unique token indexing, and query/insert methods in auth-service store.
- **Commit SHA**: ``current``
- **Verification**: Verified via compilation. ✅

