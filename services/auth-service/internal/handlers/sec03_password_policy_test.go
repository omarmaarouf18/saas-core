package handlers

// SEC-03 regression tests: every entry point that sets a password must
// enforce the shared passwordpolicy (min 8 runes, max 72 bytes, embedded
// common-password blocklist).

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/project/auth-service/internal/models"
)

// sec03StrongPassword is a policy-compliant password for test payloads that
// only need a value the SEC-03 policy accepts (>= 8 runes, not blocklisted).
const sec03StrongPassword = "Str0ng!P@ssword"

func postSignup(t *testing.T, a *Auth, req models.SignupRequest) *httptest.ResponseRecorder {
	t.Helper()
	b, _ := json.Marshal(req)
	rec := httptest.NewRecorder()
	a.Signup(rec, httptest.NewRequest("POST", "/auth/signup", bytes.NewReader(b)))
	return rec
}

func TestSignup_RejectsWeakPasswords(t *testing.T) {
	a, _, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	cases := []struct {
		name     string
		password string
		wantErr  string
	}{
		{"TooShort", "short1", "password must be at least 8 characters"},
		{"TooLong", strings.Repeat("a", 73), "password must be at most 72 bytes"},
		{"TooCommon", "password123", "password is too common"},
	}
	for i, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			rec := postSignup(t, a, models.SignupRequest{
				Email:    fmt.Sprintf("sec03-weak-%d@example.com", i),
				Username: fmt.Sprintf("sec03_weak_%d", i),
				Password: tc.password,
				Role:     models.RoleUser,
			})
			if rec.Code != http.StatusBadRequest {
				t.Fatalf("expected 400 Bad Request for weak password, got %d. Body: %s", rec.Code, rec.Body.String())
			}
			if !strings.Contains(rec.Body.String(), tc.wantErr) {
				t.Errorf("expected body to contain %q, got: %s", tc.wantErr, rec.Body.String())
			}
		})
	}

	// Employee signup goes through the same handler: the policy must apply
	// before any provisioning/auth checks, including without an owner token.
	t.Run("EmployeeRole", func(t *testing.T) {
		rec := postSignup(t, a, models.SignupRequest{
			Email:    "sec03-weak-emp@example.com",
			Username: "sec03_weak_emp",
			Password: "password123",
			Role:     models.RoleEmployee,
		})
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("expected 400 Bad Request for weak employee password, got %d. Body: %s", rec.Code, rec.Body.String())
		}
		if !strings.Contains(rec.Body.String(), "password is too common") {
			t.Errorf("expected common-password error, got: %s", rec.Body.String())
		}
	})
}

func TestSignup_AcceptsStrongPassword(t *testing.T) {
	a, _, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	rec := postSignup(t, a, models.SignupRequest{
		Email:    "sec03-strong@example.com",
		Username: "sec03_strong",
		Password: "Str0ng!P@ssword",
		Role:     models.RoleUser,
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201 Created for strong password, got %d. Body: %s", rec.Code, rec.Body.String())
	}
}

func TestResetPassword_RejectsWeakPasswordAndKeepsToken(t *testing.T) {
	a, mongoStore, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	email := "sec03-reset@example.com"
	createTokenTestUser(t, ctx, mongoStore, email, "user-sec03-reset", "246810")
	token := verifyAndCaptureToken(t, a, email, "246810")

	rec := postResetWithToken(a, email, token, "password123")
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 Bad Request for weak reset password, got %d. Body: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "password is too common") {
		t.Errorf("expected common-password error, got: %s", rec.Body.String())
	}

	// A rejected attempt must not consume the single-use token: the holder
	// must be able to retry with a policy-compliant password.
	rec = postResetWithToken(a, email, token, "BrandNewPass1")
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK for strong reset password after weak attempt, got %d. Body: %s", rec.Code, rec.Body.String())
	}
}
