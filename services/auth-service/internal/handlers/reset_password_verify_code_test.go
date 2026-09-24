package handlers

// Security regression tests for POST /auth/reset-password/verify-code
// (ADR-0026 phase 1). Each requirement below is a distinct, separately-named
// test case: a generic "tests pass" summary must never be the only evidence
// that this brute-forceable endpoint carries the same protections as
// ResetPassword.

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/project/auth-service/internal/models"
	"github.com/project/auth-service/internal/store"
	"go.mongodb.org/mongo-driver/v2/bson"
	"golang.org/x/crypto/bcrypt"
)

func createVerifyCodeUser(t *testing.T, ctx context.Context, mongoStore *store.MongoDB, email, userID, otp string) {
	t.Helper()
	hashed, _ := bcrypt.GenerateFromPassword([]byte("OldPassword123"), bcrypt.DefaultCost)
	user := &models.User{
		ID:        userID,
		Email:     email,
		Username:  userID, // unique per test user (username has a unique index)
		Password:  string(hashed),
		Role:      models.RoleUser,
		IsActive:  true,
		CreatedAt: time.Now().UTC(),
	}
	if err := mongoStore.CreateUser(ctx, user); err != nil {
		t.Fatalf("Failed to create test user: %v", err)
	}
	if err := mongoStore.SetOTP(ctx, email, otp); err != nil {
		t.Fatalf("Failed to set OTP: %v", err)
	}
}

func postVerifyCode(a *Auth, email, otp, remoteAddr string) *httptest.ResponseRecorder {
	body := fmt.Sprintf(`{"email":%q,"otp":%q}`, email, otp)
	req := httptest.NewRequest("POST", "/auth/reset-password/verify-code", strings.NewReader(body))
	if remoteAddr != "" {
		req.RemoteAddr = remoteAddr
	}
	rec := httptest.NewRecorder()
	a.VerifyResetCode(rec, req)
	return rec
}

// TestVerifyResetCode_SixthConsecutiveWrongAttemptLockedOut proves the 6th
// consecutive wrong guess from the same IP+email gets 429, not 401.
func TestVerifyResetCode_SixthConsecutiveWrongAttemptLockedOut(t *testing.T) {
	a, mongoStore, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	email := "vclockout@example.com"
	createVerifyCodeUser(t, ctx, mongoStore, email, "user-vc-lockout", "123456")

	ip := "10.9.9.1:12345"
	for i := 0; i < 5; i++ {
		rec := postVerifyCode(a, email, "000000", ip)
		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("Attempt %d: expected 401 Unauthorized, got %d. Body: %s", i+1, rec.Code, rec.Body.String())
		}
	}
	rec := postVerifyCode(a, email, "000000", ip)
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("6th consecutive wrong attempt: expected 429 Too Many Requests, got %d. Body: %s", rec.Code, rec.Body.String())
	}
}

// TestVerifyResetCode_WrongAttemptDoesNotConsumeCode proves a wrong guess
// leaves the real code intact: the SAME code still verifies afterward. The
// rate limiter — not consumption — is the brute-force defense.
func TestVerifyResetCode_WrongAttemptDoesNotConsumeCode(t *testing.T) {
	a, mongoStore, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	email := "vcnconsume@example.com"
	createVerifyCodeUser(t, ctx, mongoStore, email, "user-vc-nconsume", "654321")

	ip := "10.9.9.2:12345"
	wrong := postVerifyCode(a, email, "000000", ip)
	if wrong.Code != http.StatusUnauthorized {
		t.Fatalf("Expected 401 for wrong code, got %d. Body: %s", wrong.Code, wrong.Body.String())
	}
	right := postVerifyCode(a, email, "654321", ip)
	if right.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK for the same code after a wrong guess, got %d. Body: %s", right.Code, right.Body.String())
	}
}

// TestVerifyResetCode_SuccessResetsBothCounters proves a correct verify
// resets the IP and email failure counters: 4 failures, success on the 5th,
// then 5 fresh failures are tolerated again before lockout.
func TestVerifyResetCode_SuccessResetsBothCounters(t *testing.T) {
	a, mongoStore, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	email := "vcreset@example.com"
	createVerifyCodeUser(t, ctx, mongoStore, email, "user-vc-reset", "777888")

	ip := "10.9.9.3:12345"
	for i := 0; i < 4; i++ {
		if rec := postVerifyCode(a, email, "000000", ip); rec.Code != http.StatusUnauthorized {
			t.Fatalf("Pre-success failure %d: expected 401, got %d", i+1, rec.Code)
		}
	}
	if rec := postVerifyCode(a, email, "777888", ip); rec.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK for correct code on 5th attempt, got %d. Body: %s", rec.Code, rec.Body.String())
	}
	// Counters were reset: 5 more failures must yield 401s, lockout only after.
	for i := 0; i < 5; i++ {
		if rec := postVerifyCode(a, email, "000000", ip); rec.Code != http.StatusUnauthorized {
			t.Fatalf("Post-reset failure %d: expected 401 (counters were reset), got %d. Body: %s", i+1, rec.Code, rec.Body.String())
		}
	}
	if rec := postVerifyCode(a, email, "000000", ip); rec.Code != http.StatusTooManyRequests {
		t.Fatalf("Expected 429 only after 5 fresh post-reset failures, got %d. Body: %s", rec.Code, rec.Body.String())
	}
}

// TestVerifyResetCode_IPLockoutCheckedBeforeComparison proves a locked-out IP
// is rejected even with the CORRECT code — i.e. the lockout check runs
// before any OTP comparison — and that the code is left unconsumed.
func TestVerifyResetCode_IPLockoutCheckedBeforeComparison(t *testing.T) {
	a, mongoStore, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	email := "vciplock@example.com"
	createVerifyCodeUser(t, ctx, mongoStore, email, "user-vc-iplock", "112233")

	lockedIP := "10.9.9.4:12345"
	// getClientIP strips the port before keying the limiter, so pre-lock the
	// stripped key exactly as the handler will check it.
	for i := 0; i < 5; i++ {
		a.limiter.RecordFailure("10.9.9.4")
	}
	rec := postVerifyCode(a, email, "112233", lockedIP)
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("Expected 429 for locked IP even with correct code, got %d. Body: %s", rec.Code, rec.Body.String())
	}
	// The correct code must be untouched: a fresh IP verifies it fine.
	fresh := postVerifyCode(a, email, "112233", "10.9.9.5:12345")
	if fresh.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK from fresh IP (code unconsumed by locked attempt), got %d. Body: %s", fresh.Code, fresh.Body.String())
	}
}

// TestVerifyResetCode_EmailLockoutRejects mirrors the existing ResetPassword
// rate-limit test shape: a pre-locked email gets 429.
func TestVerifyResetCode_EmailLockoutRejects(t *testing.T) {
	a, _, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	email := "vcemaillock@example.com"
	for i := 0; i < 5; i++ {
		a.limiter.RecordFailure(email)
	}
	rec := postVerifyCode(a, email, "123456", "10.9.9.6:12345")
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("Expected 429 Too Many Requests for rate limited email, got %d. Body: %s", rec.Code, rec.Body.String())
	}
}

// TestVerifyResetCode_UniformErrorResponses proves user-not-found, wrong
// code, and expired code produce byte-identical status + body (no oracle).
func TestVerifyResetCode_UniformErrorResponses(t *testing.T) {
	a, mongoStore, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	ip := "10.9.9.7:12345"

	// Case 1: unknown email.
	unknownRec := postVerifyCode(a, "nosuchuser@example.com", "123456", ip)

	// Case 2: wrong code for a real user.
	wrongEmail := "vcwrong@example.com"
	createVerifyCodeUser(t, ctx, mongoStore, wrongEmail, "user-vc-wrong", "123456")
	wrongRec := postVerifyCode(a, wrongEmail, "000000", "10.9.9.8:12345")

	// Case 3: correct code but force-expired deadline.
	expEmail := "vcexpired@example.com"
	createVerifyCodeUser(t, ctx, mongoStore, expEmail, "user-vc-exp", "123456")
	expUser := mongoStore.GetByEmail(ctx, expEmail)
	if expUser == nil {
		t.Fatalf("Failed to fetch user for expiry manipulation")
	}
	past := time.Now().Add(-1 * time.Hour)
	if err := mongoStore.UpdateUser(ctx, expUser.ID, bson.M{"$set": bson.M{"otp_expires_at": past}}); err != nil {
		t.Fatalf("Failed to backdate otp_expires_at: %v", err)
	}
	expRec := postVerifyCode(a, expEmail, "123456", "10.9.9.9:12345")

	for name, rec := range map[string]*httptest.ResponseRecorder{
		"unknown-email": unknownRec,
		"wrong-code":    wrongRec,
		"expired-code":  expRec,
	} {
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("%s: expected 401 Unauthorized, got %d. Body: %s", name, rec.Code, rec.Body.String())
		}
	}
	if unknownRec.Body.String() != wrongRec.Body.String() ||
		wrongRec.Body.String() != expRec.Body.String() {
		t.Errorf("Error responses differ across failure causes (enumeration oracle):\nunknown=%q\nwrong=%q\nexpired=%q",
			unknownRec.Body.String(), wrongRec.Body.String(), expRec.Body.String())
	}
	var decoded map[string]string
	_ = json.Unmarshal(unknownRec.Body.Bytes(), &decoded)
	if decoded["error"] != "invalid or expired OTP code" {
		t.Errorf("Expected uniform 'invalid or expired OTP code' message, got %q", decoded["error"])
	}
}

// TestVerifyResetCode_SuccessCarriesOnlyResetToken proves the success body
// carries the single-use reset token and ONLY the token: still no
// password/session/user object. (Renamed from SuccessCarriesNoToken: the
// bare-indicator contract was the pre-token design.)
func TestVerifyResetCode_SuccessCarriesOnlyResetToken(t *testing.T) {
	a, mongoStore, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	email := "vcnotoken@example.com"
	createVerifyCodeUser(t, ctx, mongoStore, email, "user-vc-notoken", "445566")

	rec := postVerifyCode(a, email, "445566", "10.9.9.10:12345")
	if rec.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK, got %d. Body: %s", rec.Code, rec.Body.String())
	}
	raw := rec.Body.String()
	var decoded map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &decoded); err != nil {
		t.Fatalf("Success body is not JSON: %v", err)
	}
	// Exactly {status, message, reset_token} — the token is the only
	// credential-shaped value the endpoint may return.
	if len(decoded) != 3 {
		t.Errorf("Expected exactly {status,message,reset_token} keys, got %v", decoded)
	}
	token, _ := decoded["reset_token"].(string)
	if len(token) != 43 {
		t.Errorf("Expected 43-char base64url token (32 bytes entropy), got %q (%d chars)", token, len(token))
	}
	if _, err := base64.RawURLEncoding.DecodeString(token); err != nil {
		t.Errorf("reset_token is not valid base64url: %v", err)
	}
	lowered := strings.ToLower(raw)
	for _, marker := range []string{"jwt", "bearer", "session", "user_id", "username", "password"} {
		if strings.Contains(lowered, marker) {
			t.Errorf("Success body must not contain %q: %s", marker, raw)
		}
	}
}

// TestVerifyResetCode_ReplayFails proves verify-code consumes the code: a
// second call with the same code fails like a wrong code.
func TestVerifyResetCode_ReplayFails(t *testing.T) {
	a, mongoStore, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	email := "vcreplay@example.com"
	createVerifyCodeUser(t, ctx, mongoStore, email, "user-vc-replay", "998877")

	ip := "10.9.9.11:12345"
	first := postVerifyCode(a, email, "998877", ip)
	if first.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK for first verify, got %d. Body: %s", first.Code, first.Body.String())
	}
	second := postVerifyCode(a, email, "998877", ip)
	if second.Code != http.StatusUnauthorized {
		t.Fatalf("Expected 401 Unauthorized for replayed code, got %d. Body: %s", second.Code, second.Body.String())
	}
	// The replayed-code error must be byte-identical to the generic error.
	wrong := postVerifyCode(a, "other@example.com", "000000", "10.9.9.12:12345")
	if second.Body.String() != wrong.Body.String() {
		t.Errorf("Replayed-code error differs from generic error: %q vs %q", second.Body.String(), wrong.Body.String())
	}
}

// TestResetPassword_TwoPhaseGate proves phase 2 enforces the stored flag and
// deadline: success when verified+fresh, generic 401 when never verified or
// verified too long ago (stalled on the new-password screen).
func TestResetPassword_TwoPhaseGate(t *testing.T) {
	newUser := func(t *testing.T, ctx context.Context, mongoStore *store.MongoDB, email, userID string) {
		t.Helper()
		hashed, _ := bcrypt.GenerateFromPassword([]byte("OldPassword123"), bcrypt.DefaultCost)
		user := &models.User{
			ID:        userID,
			Email:     email,
			Username:  "gateuser",
			Password:  string(hashed),
			Role:      models.RoleUser,
			IsActive:  true,
			CreatedAt: time.Now().UTC(),
		}
		if err := mongoStore.CreateUser(ctx, user); err != nil {
			t.Fatalf("Failed to create test user: %v", err)
		}
		if err := mongoStore.SetOTP(ctx, email, "246810"); err != nil {
			t.Fatalf("Failed to set OTP: %v", err)
		}
	}
	postReset := func(a *Auth, email, token string) *httptest.ResponseRecorder {
		body := fmt.Sprintf(`{"email":%q,"reset_token":%q,"new_password":"BrandNewPass1"}`, email, token)
		req := httptest.NewRequest("POST", "/auth/reset-password", strings.NewReader(body))
		rec := httptest.NewRecorder()
		a.ResetPassword(rec, req)
		return rec
	}

	// captureToken runs phase 1 and returns the raw reset token.
	captureToken := func(t *testing.T, a *Auth, email string) string {
		t.Helper()
		body := fmt.Sprintf(`{"email":%q,"otp":"246810"}`, email)
		req := httptest.NewRequest("POST", "/auth/reset-password/verify-code", strings.NewReader(body))
		rec := httptest.NewRecorder()
		a.VerifyResetCode(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK for verify-code, got %d. Body: %s", rec.Code, rec.Body.String())
		}
		var resp map[string]any
		if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
			t.Fatalf("Failed to decode verify-code response: %v", err)
		}
		token, _ := resp["reset_token"].(string)
		if token == "" {
			t.Fatalf("Expected reset_token in verify-code response, got %s", rec.Body.String())
		}
		return token
	}

	t.Run("UnverifiedRejected", func(t *testing.T) {
		a, mongoStore, cleanup := setupTestAuth(t)
		if a == nil {
			return
		}
		defer cleanup()
		ctx := context.Background()
		newUser(t, ctx, mongoStore, "gate-unverified@example.com", "user-gate-unv")
		rec := postReset(a, "gate-unverified@example.com", "")
		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("Expected 401 for never-verified reset, got %d. Body: %s", rec.Code, rec.Body.String())
		}
		var resp map[string]string
		_ = json.Unmarshal(rec.Body.Bytes(), &resp)
		if resp["error"] != "invalid or expired reset verification" {
			t.Errorf("Expected generic non-enumerating error, got %q", resp["error"])
		}
	})

	t.Run("VerifiedFreshSucceeds", func(t *testing.T) {
		a, mongoStore, cleanup := setupTestAuth(t)
		if a == nil {
			return
		}
		defer cleanup()
		ctx := context.Background()
		email := "gate-fresh@example.com"
		newUser(t, ctx, mongoStore, email, "user-gate-fresh")
		token := captureToken(t, a, email)
		if rec := postReset(a, email, token); rec.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK for token-bound reset, got %d. Body: %s", rec.Code, rec.Body.String())
		}
	})

	t.Run("VerifiedButExpiredRejected", func(t *testing.T) {
		a, mongoStore, cleanup := setupTestAuth(t)
		if a == nil {
			return
		}
		defer cleanup()
		ctx := context.Background()
		email := "gate-stale@example.com"
		newUser(t, ctx, mongoStore, email, "user-gate-stale")
		token := captureToken(t, a, email)
		// Simulate stalling on the new-password screen past the TOKEN
		// deadline (the token's own 10-minute clock, not the OTP send time).
		stalled := mongoStore.GetByEmail(ctx, email)
		if stalled == nil {
			t.Fatalf("Failed to fetch user for expiry manipulation")
		}
		if err := mongoStore.UpdateUser(ctx, stalled.ID, bson.M{"$set": bson.M{"reset_token_expires_at": time.Now().Add(-1 * time.Hour)}}); err != nil {
			t.Fatalf("Failed to backdate reset_token_expires_at: %v", err)
		}
		rec := postReset(a, email, token)
		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("Expected 401 for stale token, got %d. Body: %s", rec.Code, rec.Body.String())
		}
		var resp map[string]string
		_ = json.Unmarshal(rec.Body.Bytes(), &resp)
		if resp["error"] != "invalid or expired reset verification" {
			t.Errorf("Expected generic non-enumerating error, got %q", resp["error"])
		}
	})
}
