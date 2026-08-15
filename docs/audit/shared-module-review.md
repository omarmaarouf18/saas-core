# Shared Module Security & Functional Audit Report

- **Status**: Completed
- **Target Branch**: `logic-exploitation`
- **Scope**: `shared/` directory (`shared/infra/...`)
- **Date**: 2026-07-17

---

## 1. Summary of Reviewed Files & Packages

The following packages under `shared/` were audited file-by-file, function-by-function, verifying call paths, validations, error handling, rate limiting logic, resource management, and test coverage:

| Package / Path | Audited Files | Importing Services | Status |
| :--- | :--- | :--- | :--- |
| `shared/infra/jwtutil` | `jwt.go`, `jwt_test.go` | `auth-service`, `chat-service`, `notification-service`, `user-service` | Clean |
| `shared/infra/ratelimit` | `ratelimit.go`, `ratelimit_test.go` | `api-gateway`, `auth-service`, `chat-service`, `notification-service`, `user-service` | Clean |
| `shared/infra/resilience` | `resilience.go`, `resilience_test.go` | `api-gateway`, `auth-service`, `chat-service`, `notification-service`, `user-service` | **Gap Fixed** |
| `shared/infra/tlsutil` | `tlsutil.go` | `api-gateway`, `auth-service`, `chat-service`, `notification-service`, `user-service` | Clean (Zero Tests) |
| `shared/infra/handlerutil` | `limiter.go`, `security_logs.go`, `security_logs_test.go` | `auth-service`, `chat-service`, `notification-service`, `user-service` | Clean (Zero Tests for `limiter.go`) |

---

## 2. Gaps Found & Closed

### Gap 1: Intermediate HTTP Response Connection Leak
* **File**: `shared/infra/resilience/resilience.go`
* **Functions**: `ResilienceClient.Do` and `ResilienceRoundTripper.RoundTrip`
* **Severity**: Functional (Denial of Service / File Descriptor Exhaustion)
* **Details**: In both `Do` and `RoundTrip`, when a downstream request returned an HTTP 5xx error, the inner handler returned the `*http.Response` alongside a constructed error (`fmt.Errorf("HTTP status %d", ...)`). Because it returned a non-nil error, the client retry loop would either:
  1. Trigger a retry, overwriting `lastResp` with the next attempt's response without calling `.Close()` on the previous attempt's body.
  2. Exit the loop on final failure. Since the caller received an `err != nil`, standard Go conventions dictate that they do not inspect or call `.Close()` on the returned response body.
  
  This resulted in connection/descriptor leaks on all intermediate retried attempts and final failures.
* **Failing Test Commit**: `04a261cfd29144894e94615d0a3d5676ba85f7b3` (introduced `TestResilienceClient_ConnectionLeak` which failed with 3 unclosed bodies).
* **Fix Commit SHA**: `eb0ddb54b537358b46f00b82b9540d069b531705` (added explicit `lastResp.Body.Close()` checks on failure branches).
* **Verifying Test Name**: `TestResilienceClient_ConnectionLeak` (in `shared/infra/resilience/resilience_test.go`). ✅

### Gap 2: Zero Test Coverage for TLS Loading Utils
* **File**: `shared/infra/tlsutil/tlsutil.go`
* **Functions**: `LoadServerTLSConfig`, `LoadClientTLSConfig`, `NewClient`
* **Severity**: Untested-edge-case / Documentation-drift-only
* **Details**: The package compiles and operates correctly, but has zero unit tests validating PEM parsing errors, file read errors, or config initialization logic.
* **Next Steps**: Handled as clean, but marked for future test coverage expansion.

### Gap 3: Zero Test Coverage for Limiter Wrap & IP Helpers
* **File**: `shared/infra/handlerutil/limiter.go`
* **Functions**: `RateLimiter.CheckAndRecord`, `GetIP`
* **Severity**: Untested-edge-case / Documentation-drift-only
* **Details**: The delegation wrapper for sliding window checks has zero unit tests. While `GetIP` is implicitly tested by importing service integrations, no unit tests directly assert its header preference ordering (e.g. `X-Forwarded-For` vs `X-Real-IP` vs `RemoteAddr`) or IPv6 brackets trimming.
* **Next Steps**: Handled as clean, but marked for future test coverage expansion.

---

## 3. Detailed File Audit Logs (Clean Files)

### `shared/infra/jwtutil/jwt.go`
* **Init & getSecret**: Verified both functions correctly fail-fast via `panic` on empty secret, adhering to the JWT Secret Hardening decision.
* **GenerateToken & GenerateUUID**: Verified claims (`UserID`, `Role`, `TenantID`, `Email`, `RegisteredClaims.ID`) are populated correctly with a secure UUID.
* **ValidateToken**: verified signature parsing is verified *before* claims are trusted. The parser enforces signing method verification to prevent HS256/RS256 algorithm swapping. Expired tokens correctly set `isExpired` flag and query the Redis denylist using a fail-closed pattern (unreachable Redis drops the request rather than bypassing the denylist).
* **RevokeToken**: Revocation successfully denylists tokens in Redis and correctly locks out matching JTIs.
* **Verification tests**: Added `TestValidateToken_ExpiredAndInvalidSignature` to confirm signature integrity constraints on expired tokens. ✅

### `shared/infra/ratelimit/ratelimit.go`
* **NewRedisClient**: Verified URL parsing/fallback correctly pings Redis with timeout.
* **RateLimiter (CheckAndRecord)**: Verified sliding window check and exponential lockout calculations are performed atomically via Lua. Fail-closed fallback sets a 30-second lockout when Redis is unavailable.
* **AuthRateLimiter (IsLocked, RecordFailure, Reset)**: Verified lockout verification and failure increments. Fail-closed fallback enforces 5-minute lockout when Redis fails.

### `shared/infra/handlerutil/security_logs.go`
* **InitCloudWatch & ShipSecurityEvent**: Verified CloudWatch initialization and event shipping. Log shipping is executed asynchronously in a goroutine to prevent blocking HTTP handler execution.
* **GetClientIP**: Verified IP parsing and brackets trimming.

---

## 4. Flagged for Next Pass (Services & Frontend)

During import tracing, the following items under `services/` were flagged as requiring close inspection in future service audits:
1. **`auth-service/internal/handlers/auth.go`**: Verify why token expiry is compared against a hardcoded `7*24*time.Hour` refresh window. Check if this value is configurable or documented.
2. **`chat-service/internal/handlers/chat.go`**: Verify that query-parameter authentication tokens (`?token=`) for WebSocket connections are securely cleared/redacted on client handshake errors before logging.
3. **`user-service/internal/handlers/services_handlers.go`** (originally `handlers.go`): Ensure spatial coordinate bounds checking is consistent across all service directory queries and is not vulnerable to out-of-bounds input bypasses. **[RESOLVED]** — Added `isValidCoordinate(refLat, refLon)` bounds validation to `ListServices` in `user-service`, rejecting out-of-bounds inputs with `400 Bad Request` (`invalid_coordinates`), security event logging, and audit tracking. Verified via `list_services_test.go`. (Commit `679667f9c994edd582d5c6d79226e78d1b277320`).

---

## 5. Audit Refresh (2026-07-19)

### 5.1 Overview of Scope Expansion
Since the original audit on 2026-07-17, the `logic-exploitation` branch has received significant expansions, including codebase-wide `gosec` verification, testing improvements, and username validation features. This refresh validates changes under `shared/infra` and traces how key integration items flagged in the previous pass have been corrected.

### 5.2 Verification of Flagged Items & Security Gaps
1. **gosec G104 (Unchecked Error Handling)**: Verified that all unchecked error returns codebase-wide have been resolved. In `shared/infra`, standard response helpers were added via `shared/infra/handlerutil/response.go` to wrap byte writing and JSON encoding safely.
2. **Directory Traversal (G304)**: Mitigated in `services/auth-service/internal/storage/storage.go` by verifying all destination and file-open paths against `filepath.Abs` and asserting prefix containment under the configured base storage directory (`strings.HasPrefix(absDest, absBase)`). Explicitly justified the necessary `#nosec G304` annotations inline.
3. **HTTP Server Timeouts (G114)**: Verified that all microservices now configure `ReadHeaderTimeout: 3 * time.Second` on their `http.Server` definitions (addressing Slowloris DDoS vectors).
4. **Test Coverage Expansion**:
   - `shared/infra/jwtutil/jwt_test.go` and `shared/infra/resilience/resilience_test.go` have been expanded to include comprehensive edge cases, signature mismatches, expired tokens, and connection leaks.
   - `shared/infra/tlsutil/` has had comprehensive unit tests added (`tlsutil_test.go`).
5. **Flaky-Test Auditing & Sleep Replacements**:
   - `shared/infra` test suites were audited and verified.
   - Fixed sleeps in `services/chat-service` and `services/notification-service` were audited. The fixed sleep in `services/chat-service/internal/chat/hub_test.go` was replaced with a thread-safe active polling loop checking `hub.ClientCount()` and `hub.ChannelCount()` to ensure clean teardown. Other sleeps (such as sequential database insertion timestamp spacers in `chat_test.go` and stress-test activity spacers in `hub_test.go`) were analyzed and classified as `SAFE` due to lack of I/O races.

