package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/project/auth-service/internal/models"
	"github.com/project/shared/infra/jwtutil"
	"golang.org/x/crypto/bcrypt"
)

func TestTwoFactor_DisablePasswordVerification(t *testing.T) {
	a, s, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	plainPassword := "Correct-Horse-Battery-99"
	hash, err := bcrypt.GenerateFromPassword([]byte(plainPassword), bcrypt.DefaultCost)
	if err != nil {
		t.Fatalf("failed to hash password: %v", err)
	}

	trueVal := true
	user := &models.User{
		ID:               "usr-2fa-pwd-test",
		Email:            "twofa-pwd@example.com",
		Username:         "twofa_user",
		Password:         string(hash),
		Role:             models.RoleUser,
		IsActive:         true,
		KYCStatus:        models.KYCNone,
		TwoFactorEnabled: &trueVal,
		CreatedAt:        time.Now(),
	}
	if err := s.CreateUser(ctx, user); err != nil {
		t.Fatalf("failed to seed test user: %v", err)
	}

	token, err := jwtutil.GenerateToken(user.ID, string(user.Role), user.ID, user.Email)
	if err != nil {
		t.Fatalf("failed to generate token: %v", err)
	}

	// 1. Missing password on disable: returns 400 and keeps 2FA enabled
	t.Run("Missing password on disable returns 400 and keeps 2FA enabled", func(t *testing.T) {
		payload := map[string]any{
			"two_factor_enabled": false,
		}
		bodyBytes, _ := json.Marshal(payload)
		req := httptest.NewRequest(http.MethodPatch, "/auth/user", bytes.NewReader(bodyBytes))
		req.Header.Set("Authorization", "Bearer "+token)
		rec := httptest.NewRecorder()

		a.UpdateProfile(rec, req)

		if rec.Code != http.StatusBadRequest {
			t.Fatalf("Expected 400 Bad Request, got %d. Body: %s", rec.Code, rec.Body.String())
		}
		if !bytes.Contains(rec.Body.Bytes(), []byte("current password is required to disable two-factor authentication")) {
			t.Errorf("Expected 'current password is required' error, got: %s", rec.Body.String())
		}

		// Verify DB unchanged
		dbUser := s.GetByID(ctx, user.ID)
		if !dbUser.Is2FAEnabled() {
			t.Errorf("Expected 2FA to remain enabled in DB on missing password")
		}
	})

	// 2. Wrong password on disable: returns 401 and keeps 2FA enabled
	t.Run("Wrong password on disable returns 401 and keeps 2FA enabled", func(t *testing.T) {
		payload := map[string]any{
			"two_factor_enabled": false,
			"password":           "wrong-password-guess",
		}
		bodyBytes, _ := json.Marshal(payload)
		req := httptest.NewRequest(http.MethodPatch, "/auth/user", bytes.NewReader(bodyBytes))
		req.Header.Set("Authorization", "Bearer "+token)
		rec := httptest.NewRecorder()

		a.UpdateProfile(rec, req)

		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("Expected 401 Unauthorized, got %d. Body: %s", rec.Code, rec.Body.String())
		}
		if !bytes.Contains(rec.Body.Bytes(), []byte("invalid password")) {
			t.Errorf("Expected 'invalid password' error, got: %s", rec.Body.String())
		}

		// Verify DB unchanged
		dbUser := s.GetByID(ctx, user.ID)
		if !dbUser.Is2FAEnabled() {
			t.Errorf("Expected 2FA to remain enabled in DB on wrong password")
		}
	})

	// 3. Correct password on disable: returns 200 and sets 2FA to false
	t.Run("Correct password on disable returns 200 and sets 2FA to false", func(t *testing.T) {
		payload := map[string]any{
			"two_factor_enabled": false,
			"password":           plainPassword,
		}
		bodyBytes, _ := json.Marshal(payload)
		req := httptest.NewRequest(http.MethodPatch, "/auth/user", bytes.NewReader(bodyBytes))
		req.Header.Set("Authorization", "Bearer "+token)
		rec := httptest.NewRecorder()

		a.UpdateProfile(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		// Verify DB updated
		dbUser := s.GetByID(ctx, user.ID)
		if dbUser.Is2FAEnabled() {
			t.Errorf("Expected 2FA to be disabled in DB on correct password")
		}
	})

	// 4. Enabling 2FA without password: returns 200 and sets 2FA to true
	t.Run("Enabling 2FA without password returns 200 and sets 2FA to true", func(t *testing.T) {
		payload := map[string]any{
			"two_factor_enabled": true,
		}
		bodyBytes, _ := json.Marshal(payload)
		req := httptest.NewRequest(http.MethodPatch, "/auth/user", bytes.NewReader(bodyBytes))
		req.Header.Set("Authorization", "Bearer "+token)
		rec := httptest.NewRecorder()

		a.UpdateProfile(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		// Verify DB updated
		dbUser := s.GetByID(ctx, user.ID)
		if !dbUser.Is2FAEnabled() {
			t.Errorf("Expected 2FA to be enabled in DB without password")
		}
	})
}

func TestTwoFactor_DisableTimingParityForUserWithoutPassword(t *testing.T) {
	a, s, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	trueVal := true
	userNoPwd := &models.User{
		ID:               "usr-2fa-no-pwd-test",
		Email:            "nopwd@example.com",
		Username:         "nopwd_user",
		Password:         "", // User account has no password set
		Role:             models.RoleUser,
		IsActive:         true,
		KYCStatus:        models.KYCNone,
		TwoFactorEnabled: &trueVal,
		CreatedAt:        time.Now(),
	}
	if err := s.CreateUser(ctx, userNoPwd); err != nil {
		t.Fatalf("failed to seed test user without password: %v", err)
	}

	token, err := jwtutil.GenerateToken(userNoPwd.ID, string(userNoPwd.Role), userNoPwd.ID, userNoPwd.Email)
	if err != nil {
		t.Fatalf("failed to generate token: %v", err)
	}

	payload := map[string]any{
		"two_factor_enabled": false,
		"password":           "any-attempt-password",
	}
	bodyBytes, _ := json.Marshal(payload)
	req := httptest.NewRequest(http.MethodPatch, "/auth/user", bytes.NewReader(bodyBytes))
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()

	start := time.Now()
	a.UpdateProfile(rec, req)
	elapsed := time.Since(start)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("Expected 401 Unauthorized for user without password, got %d. Body: %s", rec.Code, rec.Body.String())
	}
	if !bytes.Contains(rec.Body.Bytes(), []byte("invalid password")) {
		t.Errorf("Expected 'invalid password' error, got: %s", rec.Body.String())
	}
	// Verify timing: dummy bcrypt hash comparison should take >= 20ms
	if elapsed < 20*time.Millisecond {
		t.Errorf("Expected dummy bcrypt hash comparison to take >= 20ms, elapsed was %v", elapsed)
	}
	t.Logf("Dummy bcrypt comparison elapsed: %v", elapsed)

	// Verify DB state remains 2FA enabled
	dbUser := s.GetByID(ctx, userNoPwd.ID)
	if !dbUser.Is2FAEnabled() {
		t.Errorf("Expected 2FA to remain enabled in DB")
	}
}

func TestTwoFactor_DisableRateLimitingLockout(t *testing.T) {
	a, s, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	plainPassword := "Correct-Password-Lockout-99"
	hash, err := bcrypt.GenerateFromPassword([]byte(plainPassword), bcrypt.DefaultCost)
	if err != nil {
		t.Fatalf("failed to hash password: %v", err)
	}

	trueVal := true
	user := &models.User{
		ID:               "usr-2fa-lockout-test",
		Email:            "twofa-lockout@example.com",
		Username:         "twofa_lockout_user",
		Password:         string(hash),
		Role:             models.RoleUser,
		IsActive:         true,
		KYCStatus:        models.KYCNone,
		TwoFactorEnabled: &trueVal,
		CreatedAt:        time.Now(),
	}
	if err := s.CreateUser(ctx, user); err != nil {
		t.Fatalf("failed to seed test user: %v", err)
	}

	token, err := jwtutil.GenerateToken(user.ID, string(user.Role), user.ID, user.Email)
	if err != nil {
		t.Fatalf("failed to generate token: %v", err)
	}

	// Lockout threshold in auth-service is 5 failures.
	// Submit 5 wrong-password attempts.
	for i := 0; i < 5; i++ {
		payload := map[string]any{
			"two_factor_enabled": false,
			"password":           "wrong-guess-password",
		}
		bodyBytes, _ := json.Marshal(payload)
		req := httptest.NewRequest(http.MethodPatch, "/auth/user", bytes.NewReader(bodyBytes))
		req.Header.Set("Authorization", "Bearer "+token)
		rec := httptest.NewRecorder()

		a.UpdateProfile(rec, req)

		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("Attempt %d: expected 401 Unauthorized, got %d. Body: %s", i+1, rec.Code, rec.Body.String())
		}
	}

	// 6th attempt: submit the CORRECT password.
	// Because account/IP is locked out, it MUST return 429 Too Many Requests, not 200 OK.
	payload := map[string]any{
		"two_factor_enabled": false,
		"password":           plainPassword,
	}
	bodyBytes, _ := json.Marshal(payload)
	req := httptest.NewRequest(http.MethodPatch, "/auth/user", bytes.NewReader(bodyBytes))
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()

	a.UpdateProfile(rec, req)

	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("Expected 429 Too Many Requests when locked out (even with correct password), got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// Verify DB state remains 2FA enabled
	dbUser := s.GetByID(ctx, user.ID)
	if !dbUser.Is2FAEnabled() {
		t.Errorf("Expected 2FA to remain enabled in DB after locked-out attempt")
	}
}
