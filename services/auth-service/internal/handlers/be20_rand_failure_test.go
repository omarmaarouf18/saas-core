package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/project/auth-service/internal/models"
)

// injectFailingRand replaces the package entropy source with a deterministic
// failing reader for the duration of the test.
func injectFailingRand(t *testing.T) {
	t.Helper()
	orig := cryptoRandRead
	cryptoRandRead = func(b []byte) (int, error) {
		return 0, errors.New("injected rand failure")
	}
	t.Cleanup(func() { cryptoRandRead = orig })
}

// TestGenerateHelpers_ReturnErrorOnRandFailure: BE-20 — the generators must
// surface entropy failures as errors instead of terminating the process.
func TestGenerateHelpers_ReturnErrorOnRandFailure(t *testing.T) {
	injectFailingRand(t)

	if _, err := generateID(); err == nil {
		t.Error("generateID: expected error on rand failure, got nil")
	}
	if _, err := generate6DigitOTP(); err == nil {
		t.Error("generate6DigitOTP: expected error on rand failure, got nil")
	}
}

// TestSignup_RandFailure_Returns500NotExit: BE-20 — a failing entropy source
// during signup must produce a sanitized 500, never a process exit.
func TestSignup_RandFailure_Returns500NotExit(t *testing.T) {
	a, _, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	injectFailingRand(t)

	body, _ := json.Marshal(models.SignupRequest{
		Email:    "randfail@example.com",
		Username: "randfailuser",
		Password: "password123",
		Role:     models.RoleOwner,
	})
	req := httptest.NewRequest("POST", "/auth/signup", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	a.Signup(rec, req)

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500 on rand failure, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	var resp struct {
		Code string `json:"code"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to decode response body %q: %v", rec.Body.String(), err)
	}
	if resp.Code != "internal_error" {
		t.Errorf("expected stable error code internal_error, got %q", resp.Code)
	}
}

// TestVerifyOTP_PendingSignup_RandFailure_Returns500NotExit: BE-20 — the
// generateID call on pending-signup completion must also fail safe.
func TestVerifyOTP_PendingSignup_RandFailure_Returns500NotExit(t *testing.T) {
	a, mongoStore, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	pending := &models.PendingSignup{
		Email:        "randfailpending@example.com",
		Username:     "randfailpending",
		Password:     "hashed",
		Role:         models.RoleUser,
		OTPExpiresAt: time.Now().Add(5 * time.Minute),
	}
	if err := mongoStore.SetPendingSignup(ctx, pending.Email, pending, "445566"); err != nil {
		t.Fatalf("failed to seed pending signup: %v", err)
	}

	injectFailingRand(t)

	body := `{"email":"randfailpending@example.com","otp":"445566"}`
	req := httptest.NewRequest("POST", "/auth/verify-otp", bytes.NewReader([]byte(body)))
	rec := httptest.NewRecorder()
	a.VerifyOTP(rec, req)

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500 on rand failure, got %d. Body: %s", rec.Code, rec.Body.String())
	}
}
