package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/project/auth-service/internal/models"
	"github.com/project/auth-service/internal/store"
	"github.com/project/shared/infra/jwtutil"
	"github.com/redis/go-redis/v9"
	"go.mongodb.org/mongo-driver/v2/bson"
	"golang.org/x/crypto/bcrypt"
)

const revokeKeyPrefix = "jwt:invalidated_before:"

// revokeFailHook makes the Redis SET behind jwtutil.RevokeAllUserTokens fail
// for every user ID that failFor reports true, while every other command
// (including ValidateToken's GET of the same key) goes through untouched.
type revokeFailHook struct {
	failFor func(userID string) bool
}

func (h revokeFailHook) DialHook(next redis.DialHook) redis.DialHook { return next }

func (h revokeFailHook) ProcessHook(next redis.ProcessHook) redis.ProcessHook {
	return func(ctx context.Context, cmd redis.Cmder) error {
		args := cmd.Args()
		if strings.EqualFold(cmd.Name(), "set") && len(args) >= 2 {
			if key, ok := args[1].(string); ok && strings.HasPrefix(key, revokeKeyPrefix) && h.failFor(strings.TrimPrefix(key, revokeKeyPrefix)) {
				err := errors.New("forced revocation failure")
				cmd.SetErr(err)
				return err
			}
		}
		return next(ctx, cmd)
	}
}

func (h revokeFailHook) ProcessPipelineHook(next redis.ProcessPipelineHook) redis.ProcessPipelineHook {
	return next
}

// useJWTRedis points jwtutil at a fresh miniredis whose revocation writes fail
// for the user IDs selected by failFor (nil = never fail). Restored on cleanup.
func useJWTRedis(t *testing.T, failFor func(userID string) bool) {
	t.Helper()
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	if failFor != nil {
		rdb.AddHook(revokeFailHook{failFor: failFor})
	}
	jwtutil.SetRedisClient(rdb)
	t.Cleanup(func() {
		jwtutil.SetRedisClient(nil)
		_ = rdb.Close()
		mr.Close()
	})
}

type capturedSecurityEvent struct {
	eventType, actorID, tenantID, detail string
}

// captureSecurityEvents swaps the shipSecurityEvent seam for a recorder.
func captureSecurityEvents(t *testing.T) func() []capturedSecurityEvent {
	t.Helper()
	var mu sync.Mutex
	var events []capturedSecurityEvent
	prev := shipSecurityEvent
	shipSecurityEvent = func(_ context.Context, eventType, _, actorID, tenantID, detail, _ string) {
		mu.Lock()
		defer mu.Unlock()
		events = append(events, capturedSecurityEvent{eventType, actorID, tenantID, detail})
	}
	t.Cleanup(func() { shipSecurityEvent = prev })
	return func() []capturedSecurityEvent {
		mu.Lock()
		defer mu.Unlock()
		return append([]capturedSecurityEvent(nil), events...)
	}
}

func hasSecurityEvent(events []capturedSecurityEvent, eventType string) bool {
	for _, e := range events {
		if e.eventType == eventType {
			return true
		}
	}
	return false
}

func assertSafeErrorCode(t *testing.T, rec *httptest.ResponseRecorder, wantStatus int, wantCode string) {
	t.Helper()
	if rec.Code != wantStatus {
		t.Fatalf("expected %d, got %d. Body: %s", wantStatus, rec.Code, rec.Body.String())
	}
	var resp struct {
		Code string `json:"code"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to decode error response: %v", err)
	}
	if resp.Code != wantCode {
		t.Errorf("expected stable error code %q, got %q", wantCode, resp.Code)
	}
}

// ---------------------------------------------------------------------------
// Password reset
// ---------------------------------------------------------------------------

const sec07bOldPassword = "OldPassword1!"

// seedResetUser creates a user with a known password and runs phase 1 of the
// reset flow, returning the user and the phase-2 reset token.
func seedResetUser(t *testing.T, a *Auth, mongoStore *store.MongoDB) (*models.User, string) {
	t.Helper()
	ctx := context.Background()
	hashed, err := bcrypt.GenerateFromPassword([]byte(sec07bOldPassword), bcrypt.DefaultCost)
	if err != nil {
		t.Fatalf("failed to hash password: %v", err)
	}
	user := &models.User{
		ID:        "user-sec07b-reset",
		Email:     "reset-sec07b@example.com",
		Username:  "reset_sec07b",
		Password:  string(hashed),
		Role:      models.RoleUser,
		IsActive:  true,
		CreatedAt: time.Now().UTC(),
	}
	if err := mongoStore.CreateUser(ctx, user); err != nil {
		t.Fatalf("failed to create user: %v", err)
	}
	otpCode := "246810"
	if err := mongoStore.SetOTP(ctx, user.Email, otpCode); err != nil {
		t.Fatalf("failed to set OTP: %v", err)
	}
	req := httptest.NewRequest("POST", "/auth/reset-password/verify-code", strings.NewReader(fmt.Sprintf(`{"email":%q,"otp":%q}`, user.Email, otpCode)))
	rec := httptest.NewRecorder()
	a.VerifyResetCode(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("verify-code failed: got %d. Body: %s", rec.Code, rec.Body.String())
	}
	var resp map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to decode verify-code response: %v", err)
	}
	resetToken, _ := resp["reset_token"].(string)
	if resetToken == "" {
		t.Fatalf("expected reset_token, got: %s", rec.Body.String())
	}
	return user, resetToken
}

func doResetPassword(a *Auth, email, resetToken, newPassword string) *httptest.ResponseRecorder {
	body := fmt.Sprintf(`{"email":%q,"reset_token":%q,"new_password":%q}`, email, resetToken, newPassword)
	req := httptest.NewRequest("POST", "/auth/reset-password", strings.NewReader(body))
	rec := httptest.NewRecorder()
	a.ResetPassword(rec, req)
	return rec
}

// TestResetPassword_RevokeFailure_FailsClosed: SEC-07b — if session revocation
// fails, the reset returns 503, the password is NOT changed, the reset token
// is NOT consumed (a retry succeeds), the old session stays the only session
// (no new password with old sessions alive), and a security event is emitted.
func TestResetPassword_RevokeFailure_FailsClosed(t *testing.T) {
	a, mongoStore, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	user, resetToken := seedResetUser(t, a, mongoStore)
	newPassword := "NewPassword2@"

	failing := true
	var mu sync.Mutex
	useJWTRedis(t, func(string) bool { mu.Lock(); defer mu.Unlock(); return failing })
	events := captureSecurityEvents(t)

	oldToken, err := jwtutil.GenerateToken(user.ID, string(user.Role), user.ID, user.Email)
	if err != nil {
		t.Fatalf("failed to generate token: %v", err)
	}

	rec := doResetPassword(a, user.Email, resetToken, newPassword)
	assertSafeErrorCode(t, rec, http.StatusServiceUnavailable, "service_unavailable")

	stored := mongoStore.GetByEmail(ctx, user.Email)
	if stored == nil {
		t.Fatal("user disappeared from store")
	}
	if bcrypt.CompareHashAndPassword([]byte(stored.Password), []byte(sec07bOldPassword)) != nil {
		t.Fatal("password must be unchanged when revocation fails")
	}
	if stored.ResetTokenHash == "" {
		t.Fatal("reset token must not be consumed when revocation fails")
	}
	if !hasSecurityEvent(events(), "PASSWORD_RESET_REVOKE_FAILED") {
		t.Fatalf("expected PASSWORD_RESET_REVOKE_FAILED security event, got %+v", events())
	}

	// Redis recovers: the same reset token works and the old session dies.
	mu.Lock()
	failing = false
	mu.Unlock()
	rec = doResetPassword(a, user.Email, resetToken, newPassword)
	if rec.Code != http.StatusOK {
		t.Fatalf("retry after recovery: expected 200, got %d. Body: %s", rec.Code, rec.Body.String())
	}
	if _, err := jwtutil.ValidateToken(oldToken); err == nil || err.Error() != "jwtutil: token has been revoked" {
		t.Fatalf("expected pre-reset token to be revoked after successful retry, got: %v", err)
	}
}

// ---------------------------------------------------------------------------
// Account suspension
// ---------------------------------------------------------------------------

const sec07bReviewerToken = "sec07b-reviewer-token-0123456789abcdef"

func seedReviewer(t *testing.T, mongoStore *store.MongoDB) *models.Reviewer {
	t.Helper()
	rev := &models.Reviewer{ID: "rev-sec07b", Name: "SEC-07b Reviewer", Token: sec07bReviewerToken}
	if err := mongoStore.AddReviewer(context.Background(), rev); err != nil {
		t.Fatalf("AddReviewer failed: %v", err)
	}
	return rev
}

func doSuspend(a *Auth, userID string) *httptest.ResponseRecorder {
	body, _ := json.Marshal(models.SuspendAccountRequest{UserID: userID, Reason: "SEC-07b test suspension"})
	req := httptest.NewRequest(http.MethodPost, "/auth/accounts/suspend", bytes.NewReader(body))
	req.Header.Set("X-Internal-Token", a.internalServiceToken)
	req.Header.Set("X-Reviewer-Token", sec07bReviewerToken)
	rec := httptest.NewRecorder()
	a.SuspendAccount(rec, req)
	return rec
}

func assertNotSuspended(t *testing.T, mongoStore *store.MongoDB, userID string) {
	t.Helper()
	u := mongoStore.GetByID(context.Background(), userID)
	if u == nil {
		t.Fatalf("user %s disappeared from store", userID)
	}
	if u.EffectiveAccountStatus() == models.AccountStatusSuspended || !u.IsActive {
		t.Fatalf("user %s must NOT be suspended when revocation fails (status=%q active=%v)", userID, u.EffectiveAccountStatus(), u.IsActive)
	}
}

// TestSuspendAccount_RevokesSessions: SEC-07b happy path — suspending an owner
// revokes the owner's and the employees' existing tokens and persists the
// suspension.
func TestSuspendAccount_RevokesSessions(t *testing.T) {
	a, mongoStore, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	seedReviewer(t, mongoStore)
	owner, emp, _, _ := seedOwnerAndEmployee(t, mongoStore)
	useJWTRedis(t, nil)

	ownerToken, _ := jwtutil.GenerateToken(owner.ID, string(owner.Role), owner.ID, owner.Email)
	empToken, _ := jwtutil.GenerateToken(emp.ID, string(emp.Role), owner.ID, emp.Email)

	rec := doSuspend(a, owner.ID)
	if rec.Code != http.StatusOK {
		t.Fatalf("suspend failed: got %d. Body: %s", rec.Code, rec.Body.String())
	}
	for name, tok := range map[string]string{"owner": ownerToken, "employee": empToken} {
		if _, err := jwtutil.ValidateToken(tok); err == nil || err.Error() != "jwtutil: token has been revoked" {
			t.Errorf("expected %s token to be revoked after suspension, got: %v", name, err)
		}
	}
	u := mongoStore.GetByID(context.Background(), owner.ID)
	if u == nil || u.EffectiveAccountStatus() != models.AccountStatusSuspended {
		t.Fatalf("expected owner to be suspended, got %+v", u)
	}
}

// TestSuspendAccount_RevokeFailure_FailsClosed: SEC-07b — if revoking the
// target's sessions fails, the suspension returns 503, is NOT persisted, and
// a security event is emitted.
func TestSuspendAccount_RevokeFailure_FailsClosed(t *testing.T) {
	a, mongoStore, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	seedReviewer(t, mongoStore)
	_, emp, _, _ := seedOwnerAndEmployee(t, mongoStore)
	useJWTRedis(t, func(string) bool { return true })
	events := captureSecurityEvents(t)

	rec := doSuspend(a, emp.ID)
	assertSafeErrorCode(t, rec, http.StatusServiceUnavailable, "service_unavailable")
	assertNotSuspended(t, mongoStore, emp.ID)
	if !hasSecurityEvent(events(), "ACCOUNT_SUSPEND_REVOKE_FAILED") {
		t.Fatalf("expected ACCOUNT_SUSPEND_REVOKE_FAILED security event, got %+v", events())
	}
}

// TestSuspendAccount_OwnerCascadePartialFailure_AbortsAll: SEC-07b — when the
// owner's own revocation succeeds but an employee's fails, the whole
// suspension aborts: 503, owner NOT suspended, security event emitted.
func TestSuspendAccount_OwnerCascadePartialFailure_AbortsAll(t *testing.T) {
	a, mongoStore, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	seedReviewer(t, mongoStore)
	owner, emp, _, _ := seedOwnerAndEmployee(t, mongoStore)
	useJWTRedis(t, func(userID string) bool { return userID == emp.ID })
	events := captureSecurityEvents(t)

	rec := doSuspend(a, owner.ID)
	assertSafeErrorCode(t, rec, http.StatusServiceUnavailable, "service_unavailable")
	assertNotSuspended(t, mongoStore, owner.ID)
	evs := events()
	if !hasSecurityEvent(evs, "ACCOUNT_SUSPEND_REVOKE_FAILED") {
		t.Fatalf("expected ACCOUNT_SUSPEND_REVOKE_FAILED security event, got %+v", evs)
	}
	for _, e := range evs {
		if e.eventType == "ACCOUNT_SUSPEND_REVOKE_FAILED" && !strings.Contains(e.detail, emp.ID) {
			t.Errorf("security event should name the employee whose revocation failed, got detail %q", e.detail)
		}
	}
}

// insertCorruptEmployee adds an employee of ownerID whose is_active field
// cannot be decoded, so store.GetEmployeesByOwner returns an error.
func insertCorruptEmployee(t *testing.T, mongoStore *store.MongoDB, ownerID string) {
	t.Helper()
	if _, err := mongoStore.DatabaseForTesting().Collection("users").InsertOne(context.Background(), bson.M{
		"_id": "emp-sec07b-corrupt", "email": "corrupt-sec07b@example.com", "role": models.RoleEmployee,
		"owner_id": ownerID, "is_active": "corrupt",
	}); err != nil {
		t.Fatalf("failed to insert corrupt employee: %v", err)
	}
}

// TestSuspendAccount_EmployeeLookupFailure_FailsClosed: SEC-07b — if the
// owner's employee lookup fails, the suspension aborts (503, owner NOT
// suspended, security event) instead of treating it as "no employees".
func TestSuspendAccount_EmployeeLookupFailure_FailsClosed(t *testing.T) {
	a, mongoStore, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	seedReviewer(t, mongoStore)
	owner, _, _, _ := seedOwnerAndEmployee(t, mongoStore)
	insertCorruptEmployee(t, mongoStore, owner.ID)
	useJWTRedis(t, nil)
	events := captureSecurityEvents(t)

	rec := doSuspend(a, owner.ID)
	assertSafeErrorCode(t, rec, http.StatusServiceUnavailable, "service_unavailable")
	assertNotSuspended(t, mongoStore, owner.ID)
	if !hasSecurityEvent(events(), "ACCOUNT_SUSPEND_REVOKE_FAILED") {
		t.Fatalf("expected ACCOUNT_SUSPEND_REVOKE_FAILED security event, got %+v", events())
	}
}

// TestGetEmployees_LookupFailure_ReturnsError: SEC-07b — GET /auth/employees
// returns an error instead of an empty list when the lookup fails.
func TestGetEmployees_LookupFailure_ReturnsError(t *testing.T) {
	a, mongoStore, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	owner, _, _, _ := seedOwnerAndEmployee(t, mongoStore)
	insertCorruptEmployee(t, mongoStore, owner.ID)
	token, err := jwtutil.GenerateToken(owner.ID, string(owner.Role), owner.ID, owner.Email)
	if err != nil {
		t.Fatalf("failed to generate owner token: %v", err)
	}

	req := httptest.NewRequest(http.MethodGet, "/auth/employees", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	a.GetEmployees(rec, req)
	assertSafeErrorCode(t, rec, http.StatusInternalServerError, "internal_error")
}
