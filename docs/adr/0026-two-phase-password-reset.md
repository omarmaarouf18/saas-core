# ADR-0026: Two-Phase Password Reset (Verify-Code, Then Set-Password)

- **Status**: Accepted
- **Date**: 2026-09-24
- **Related**: None (first change to the password-reset flow since the consolidated single-screen flow, see `docs/frontend/STATUS.md` Phase 14)
- **Implementation**: backend verify-code endpoint + `ResetPassword` rework land as the step-2 commit; the three-screen frontend split lands as the step-3 commit (see `docs/changelog/new-features.md` and `docs/changelog/security-fixes.md`).

## Context

`POST /auth/reset-password` currently takes `{email, otp, new_password}` and does everything in one call: it checks the raw 6-digit code via `store.VerifyOTP` and, on success, immediately sets the new password. The Flutter client mirrors this with a single screen (`ForgotPasswordScreen`) showing email + OTP + new-password fields all at once.

This single-shot shape has two problems:

1. **No separation between "prove you own the inbox" and "choose a secret".** The raw code and the new password travel together, and any client that wants a stepped UX (enter code → then choose password) cannot stage the flow: there is no server-side record of "this email proved its code" independent of the password change itself.
2. **The code is consumed exactly once, at password-set time.** A user who mistypes the new password (or whose request fails after a correct code) burns the code and must start over from the email step, because `VerifyOTP` clears `otp_code` on success.

The store already persists everything a two-phase flow needs: `SetOTP` writes `otp_code` (AES-256-GCM ciphertext) + `otp_verified=false` + `otp_expires_at`, and the existing `store.VerifyOTP` (`services/auth-service/internal/store/mongodb.go:487`) atomically consumes the code on success and sets `otp_verified=true`, with race-safe semantics documented in its own comments (ciphertext-as-one-time-handle: a concurrent resend or a racing verifier makes the compare-and-clear miss, so one code can never yield two successes). That method is correct and must NOT be modified.

## Decision

### 1. New verify-code endpoint (phase 1 of 2)

`POST /auth/reset-password/verify-code`, accepting `{email, otp}`, calling the EXISTING `store.VerifyOTP` unchanged. The name extends the existing `/auth/forgot-password` → `/auth/reset-password` naming chain with a sub-resource for the code step.

Explicit non-reuse rule: do NOT reuse the existing handler `a.VerifyOTP` (`auth.go:611`). That handler serves the login/signup 2FA flow and has different side effects (account activation, pending-signup consumption, JWT issuance). The new endpoint must NOT issue any token/session/user object on success — only a success indicator (`{"status":"success","message":...}`). Code verification and session issuance stay in separate handlers by design, so a password-reset code can never be mistaken for (or upgraded into) an authentication grant.

Security wiring (mandatory, each covered by its own test):

- **Rate limiting FIRST, before any OTP comparison**: `a.limiter.IsLocked(clientIP)` then `a.limiter.IsLocked(req.Email)` as the very first checks, mirroring `ResetPassword`'s existing order (`auth.go:2925-2941`), rejecting with 429 + generic "too many attempts" before touching `store.VerifyOTP` or revealing whether the email exists. Same `a.limiter` instance (`AuthRateLimiter`: 5 failures → lockout, exponential backoff 30s/60s/120s/240s capped at 300s, dual-keyed on IP + email, 24h count TTL — `shared/infra/ratelimit/ratelimit.go:175-201`). No separate limiter instance.
- **Failure accounting**: wrong/expired code → `RecordFailure` on BOTH `clientIP` and `req.Email` (mirrors `auth.go:2947-2948`).
- **Success accounting**: correct code → `Reset` on both keys (mirrors `auth.go:2956-2957`).
- **Uniform errors**: user-not-found, wrong code, and expired code all return the SAME generic body (mirrors `ResetPassword`'s single "invalid or expired OTP code" message, `auth.go:2949-2951`) — no oracle distinguishing the three.

Brute-force analysis (why this is safe): the rate limiter, not code consumption, is the actual brute-force defense. A 6-digit code under a 5-failure dual-keyed lockout with exponential backoff cannot be swept: 6 consecutive wrong guesses from one IP+email lock out on the 6th (429), and rotating IPs still trips the per-email key. Consumption-on-success additionally guarantees one code yields at most one verified flag (replay of a consumed code fails like a wrong code — same generic 401).

### 2. ResetPassword drops the raw code (phase 2 of 2)

`ResetPasswordRequest` loses the `otp` field; `ResetPassword` (`auth.go:2902`) no longer accepts or re-checks a raw code. Before hashing and setting the new password it verifies, from the stored user record:

- (a) `otp_verified == true` — the email completed phase 1;
- (b) `otp_expires_at` has not passed — the verification is still fresh.

Failure of either check returns a clear but generic, non-enumerating error (same "invalid or expired" family — it must not reveal whether the email exists, was never verified, or verified too long ago). On success the handler keeps its existing behavior exactly: set password, clear `otp_code`/`otp_verified`/`otp_expires_at` (so the flag cannot be reused for a second reset), revoke all user tokens, return success-only.

**Explicit reuse note (for future readers):** `otp_expires_at` is reused as-is as the phase-2 deadline — no new expiry field is added. That timestamp is set when the code is ISSUED (`SetOTP`), not when it is verified, so the window for completing step 3 (choosing the new password) is inherited from the original send time. A user who verifies quickly but then sits on the new-password screen past the deadline must restart from the email step. This is deliberate: one deadline, one field, no second clock to keep in sync.

### 3. Direct contract change, no versioning

Removing a required field from `ResetPassword`'s request contract is a breaking change in the abstract — but this is a same-repo frontend+backend change with no external API consumers (the only caller is this repo's Flutter client, updated in the step-3 commit). Change it directly rather than versioning (`/v2`, deprecation headers, dual-accept windows) — versioning machinery for a single first-party caller would be pure overhead. Stated here explicitly so the absence of a migration path is a recorded decision, not an oversight.

### 4. Non-goals

- No change to code issuance: `ForgotPassword` (`auth.go:2815`) stays as-is (same anti-enumeration response, same `dev_otp` local behavior).
- No change to `otp_expires_at`'s duration.
- No change to 6-digit code generation.
- No change to `store.VerifyOTP` itself (race-safe consumption already correct).

## Consequences

- The reset flow becomes three client steps (email → code → new password) against two backend calls (verify-code, then reset-password with no code). The Flutter split is specified in the step-3 task; the backend accepts no raw code at password-set time, so the code never needs to be carried forward past screen 2.
- A verified-but-stalled user (past `otp_expires_at`) gets a "restart from the email step" error — the client must route them back to screen 1, not retry.
- `APPLICATION_MAP.md` gains the new endpoint via the normal `make docs` regeneration (auto-generated from `RegisterRoutes`).
- Residual risk accepted: the phase-1 verified flag + phase-2 deadline both live server-side on the user record, so there is no client-held "verified token" to steal — but also no way to distinguish "never verified" from "verified too long ago" without reading the record, which is why both map to the same generic error.
