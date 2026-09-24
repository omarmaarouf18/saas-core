package handlers

// Possession-token binding tests for POST /auth/reset-password (phase 2).
// ADR-0026 shipped phase 2 authorized on email + stored otp_verified +
// otp_expires_at — nothing proving the caller is the party that supplied
// the correct OTP in phase 1. These tests pin the fix: phase 2 requires a
// server-minted, single-use, short-lived reset token returned by phase 1.

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/project/auth-service/internal/models"
	"github.com/project/auth-service/internal/store"
	"golang.org/x/crypto/bcrypt"
)

func createTokenTestUser(t *testing.T, ctx context.Context, mongoStore *store.MongoDB, email, userID, otp string) {
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

// verifyAndCaptureToken runs phase 1 and returns the raw reset token.
func verifyAndCaptureToken(t *testing.T, a *Auth, email, otp string) string {
	t.Helper()
	body := fmt.Sprintf(`{"email":%q,"otp":%q}`, email, otp)
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
		t.Fatalf("Expected non-empty reset_token in verify-code response, got body %s", rec.Body.String())
	}
	return token
}

func postResetWithToken(a *Auth, email, token, newPassword string) *httptest.ResponseRecorder {
	body := fmt.Sprintf(`{"email":%q,"reset_token":%q,"new_password":%q}`, email, token, newPassword)
	req := httptest.NewRequest("POST", "/auth/reset-password", strings.NewReader(body))
	rec := httptest.NewRecorder()
	a.ResetPassword(rec, req)
	return rec
}

// TestResetPassword_RejectsEmailAloneWithoutToken is the gap test that
// should have existed from the start: a caller who knows ONLY the email
// (never the code) must not complete a reset during the verified window.
func TestResetPassword_RejectsEmailAloneWithoutToken(t *testing.T) {
	a, mongoStore, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	email := "gap-email-alone@example.com"
	createTokenTestUser(t, ctx, mongoStore, email, "user-gap-alone", "135790")

	// Legitimate user completes phase 1 (opens the verified window).
	verifyAndCaptureToken(t, a, email, "135790")

	// Attacker knows only the email: phase 2 with no token at all.
	body := fmt.Sprintf(`{"email":%q,"new_password":"AttackerSet9"}`, email)
	req := httptest.NewRequest("POST", "/auth/reset-password", strings.NewReader(body))
	rec := httptest.NewRecorder()
	a.ResetPassword(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("GAP: email-alone phase 2 must fail, got %d. Body: %s", rec.Code, rec.Body.String())
	}
	var resp map[string]string
	_ = json.Unmarshal(rec.Body.Bytes(), &resp)
	if resp["error"] != "invalid or expired reset verification" {
		t.Errorf("Expected generic 'invalid or expired reset verification', got %q", resp["error"])
	}
}

// TestResetPassword_WrongTokenForCorrectEmailFails proves a guessed token
// for a verified email fails with the byte-identical generic error (no
// oracle distinguishing it from an unknown email).
func TestResetPassword_WrongTokenForCorrectEmailFails(t *testing.T) {
	a, mongoStore, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	email := "gap-wrong-token@example.com"
	createTokenTestUser(t, ctx, mongoStore, email, "user-gap-wrong", "135790")
	verifyAndCaptureToken(t, a, email, "135790")

	guessed := "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
	rec := postResetWithToken(a, email, guessed, "AttackerSet9")
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("Expected 401 for guessed token, got %d. Body: %s", rec.Code, rec.Body.String())
	}
	unknownBody := fmt.Sprintf(`{"email":%q,"reset_token":%q,"new_password":"AttackerSet9"}`, "nobody-here@example.com", guessed)
	unknownReq := httptest.NewRequest("POST", "/auth/reset-password", strings.NewReader(unknownBody))
	unknownRec := httptest.NewRecorder()
	a.ResetPassword(unknownRec, unknownReq)
	if unknownRec.Code != http.StatusUnauthorized {
		t.Fatalf("Expected 401 for unknown email, got %d. Body: %s", unknownRec.Code, unknownRec.Body.String())
	}
	if rec.Body.String() != unknownRec.Body.String() {
		t.Errorf("Token errors differ across causes (oracle):\nwrong=%q\nunknown=%q",
			rec.Body.String(), unknownRec.Body.String())
	}
}

// TestResetPassword_TokenIsSingleUse proves a token dies with its reset: a
// second phase-2 call with the same token and email must fail (mirror of
// the TestVerifyResetCode_ReplayFails pattern, one layer up).
func TestResetPassword_TokenIsSingleUse(t *testing.T) {
	a, mongoStore, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	email := "gap-single-use@example.com"
	createTokenTestUser(t, ctx, mongoStore, email, "user-gap-single", "135790")
	token := verifyAndCaptureToken(t, a, email, "135790")

	first := postResetWithToken(a, email, token, "BrandNewPass1")
	if first.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK for first token use, got %d. Body: %s", first.Code, first.Body.String())
	}
	second := postResetWithToken(a, email, token, "AnotherPass2")
	if second.Code != http.StatusUnauthorized {
		t.Fatalf("Expected 401 for reused token, got %d. Body: %s", second.Code, second.Body.String())
	}
	var resp map[string]string
	_ = json.Unmarshal(second.Body.Bytes(), &resp)
	if resp["error"] != "invalid or expired reset verification" {
		t.Errorf("Expected generic 'invalid or expired reset verification', got %q", resp["error"])
	}
}

// TestVerifyResetCode_ReVerificationRotatesToken proves a fresh verify
// invalidates the previously issued token: token A dies the moment token B
// is minted (resend + re-verify), so at most one live token exists.
func TestVerifyResetCode_ReVerificationRotatesToken(t *testing.T) {
	a, mongoStore, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	email := "gap-rotate@example.com"
	createTokenTestUser(t, ctx, mongoStore, email, "user-gap-rotate", "111111")
	tokenA := verifyAndCaptureToken(t, a, email, "111111")

	// Resend a fresh code (also asserts SetOTP-time rotation scaffolding
	// holds) and verify again.
	if err := mongoStore.SetOTP(ctx, email, "222222"); err != nil {
		t.Fatalf("Failed to resend OTP: %v", err)
	}
	tokenB := verifyAndCaptureToken(t, a, email, "222222")
	if tokenA == tokenB {
		t.Fatalf("Re-verification must mint a distinct token")
	}

	stale := postResetWithToken(a, email, tokenA, "StalePass1")
	if stale.Code != http.StatusUnauthorized {
		t.Fatalf("Expected 401 for rotated-out token A, got %d. Body: %s", stale.Code, stale.Body.String())
	}
	fresh := postResetWithToken(a, email, tokenB, "FreshPass2")
	if fresh.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK for current token B, got %d. Body: %s", fresh.Code, fresh.Body.String())
	}
}

// TestResetPassword_ResendKillsLiveToken proves the rotation invariant from
// the other side: requesting a new code alone (no second verify yet)
// already kills the previously issued token.
func TestResetPassword_ResendKillsLiveToken(t *testing.T) {
	a, mongoStore, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	email := "gap-resend-kill@example.com"
	createTokenTestUser(t, ctx, mongoStore, email, "user-gap-resend", "111111")
	token := verifyAndCaptureToken(t, a, email, "111111")

	if err := mongoStore.SetOTP(ctx, email, "222222"); err != nil {
		t.Fatalf("Failed to resend OTP: %v", err)
	}
	rec := postResetWithToken(a, email, token, "StalePass1")
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("Expected 401 for token killed by resend, got %d. Body: %s", rec.Code, rec.Body.String())
	}
	// Sanity: the stored hash itself is gone, not just shadowed.
	stored := mongoStore.GetByEmail(ctx, email)
	if stored == nil {
		t.Fatalf("Failed to fetch user after resend")
	}
	if stored.ResetTokenHash != "" {
		t.Errorf("Expected resend to clear the stored token hash")
	}
}
