package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"github.com/project/auth-service/internal/models"
	"github.com/project/auth-service/internal/store"
	"github.com/project/shared/infra/jwtutil"
)

const sec07cOTP = "135790"

// seedEmailChangeUser creates a user with a pending email change whose OTP is
// sec07cOTP, and returns the user plus a session token minted before it.
func seedEmailChangeUser(t *testing.T, mongoStore *store.MongoDB) (*models.User, string, string) {
	t.Helper()
	ctx := context.Background()
	user := &models.User{
		ID:        "user-sec07c-email",
		Email:     "old-sec07c@example.com",
		Username:  "sec07c_email",
		Role:      models.RoleUser,
		TenantID:  "tenant-sec07c",
		IsActive:  true,
		CreatedAt: time.Now().UTC(),
	}
	if err := mongoStore.CreateUser(ctx, user); err != nil {
		t.Fatalf("failed to create user: %v", err)
	}
	newEmail := "new-sec07c@example.com"
	pending := &models.PendingEmailChange{
		OldEmail:     user.Email,
		NewEmail:     newEmail,
		OTPExpiresAt: time.Now().Add(5 * time.Minute),
	}
	if err := mongoStore.SetPendingEmailChange(ctx, user.ID, pending, sec07cOTP); err != nil {
		t.Fatalf("failed to set pending email change: %v", err)
	}
	oldToken, err := jwtutil.GenerateToken(user.ID, string(user.Role), user.TenantID, user.Email)
	if err != nil {
		t.Fatalf("failed to generate token: %v", err)
	}
	return user, newEmail, oldToken
}

func doConfirmEmailChange(a *Auth, token, otp string) *httptest.ResponseRecorder {
	body, _ := json.Marshal(models.EmailChangeConfirmRequest{OTP: otp})
	req := httptest.NewRequest(http.MethodPost, "/auth/email-change/confirm", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	a.ConfirmEmailChange(rec, req)
	return rec
}

// TestConfirmEmailChange_RevokesOldSessions: SEC-07c — confirming an email
// change revokes every session that existed before it, while the fresh token
// in the response is accepted (not caught by the same-second `<=` rule).
func TestConfirmEmailChange_RevokesOldSessions(t *testing.T) {
	a, mongoStore, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()
	useJWTRedis(t, nil)

	user, newEmail, oldToken := seedEmailChangeUser(t, mongoStore)
	// A second pre-existing session (e.g. an attacker's), minted separately.
	otherToken, err := jwtutil.GenerateToken(user.ID, string(user.Role), user.TenantID, user.Email)
	if err != nil {
		t.Fatalf("failed to generate token: %v", err)
	}

	rec := doConfirmEmailChange(a, oldToken, sec07cOTP)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d. Body: %s", rec.Code, rec.Body.String())
	}
	var resp struct {
		Token string `json:"token"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil || resp.Token == "" {
		t.Fatalf("expected a fresh token, got %s (%v)", rec.Body.String(), err)
	}

	for name, tok := range map[string]string{"confirming session": oldToken, "other session": otherToken} {
		if _, err := jwtutil.ValidateToken(tok); err == nil {
			t.Errorf("expected pre-change %s token to be rejected after email change, got: <nil>", name)
		}
	}
	claims, err := jwtutil.ValidateToken(resp.Token)
	if err != nil {
		t.Fatalf("expected fresh token to be accepted, got: %v", err)
	}
	if claims.Email != newEmail {
		t.Errorf("expected fresh token email %q, got %q", newEmail, claims.Email)
	}
	if got := mongoStore.GetByID(context.Background(), user.ID); got == nil || got.Email != newEmail {
		t.Errorf("expected email %q in DB, got %+v", newEmail, got)
	}
}

// TestConfirmEmailChange_RevokeFailure_FailsClosed: SEC-07c — if revocation
// fails, the confirm returns 503 service_unavailable with a security event,
// the email is NOT changed, and the pending change is restored so the same
// code succeeds once Redis is back.
func TestConfirmEmailChange_RevokeFailure_FailsClosed(t *testing.T) {
	a, mongoStore, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	failing := true
	var mu sync.Mutex
	useJWTRedis(t, func(string) bool { mu.Lock(); defer mu.Unlock(); return failing })
	events := captureSecurityEvents(t)

	user, newEmail, oldToken := seedEmailChangeUser(t, mongoStore)
	ctx := context.Background()

	rec := doConfirmEmailChange(a, oldToken, sec07cOTP)
	assertSafeErrorCode(t, rec, http.StatusServiceUnavailable, "service_unavailable")
	if !hasSecurityEvent(events(), "EMAIL_CHANGE_REVOKE_FAILED") {
		t.Errorf("expected EMAIL_CHANGE_REVOKE_FAILED security event, got %+v", events())
	}
	if got := mongoStore.GetByID(ctx, user.ID); got == nil || got.Email != user.Email {
		t.Fatalf("expected email to stay %q after revoke failure, got %+v", user.Email, got)
	}
	if mongoStore.GetPendingEmailChange(ctx, user.ID) == nil {
		t.Fatalf("expected pending email change to be restored after revoke failure")
	}

	mu.Lock()
	failing = false
	mu.Unlock()

	retry := doConfirmEmailChange(a, oldToken, sec07cOTP)
	if retry.Code != http.StatusOK {
		t.Fatalf("expected retry to succeed with 200, got %d. Body: %s", retry.Code, retry.Body.String())
	}
	if got := mongoStore.GetByID(ctx, user.ID); got == nil || got.Email != newEmail {
		t.Errorf("expected email %q after retry, got %+v", newEmail, got)
	}
	if _, err := jwtutil.ValidateToken(oldToken); err == nil {
		t.Errorf("expected old token to be rejected after successful retry, got: <nil>")
	}
}
