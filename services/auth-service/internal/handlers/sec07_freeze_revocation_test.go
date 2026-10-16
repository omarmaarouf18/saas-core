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
	"github.com/project/auth-service/internal/store"
	"github.com/project/shared/infra/jwtutil"
	"github.com/redis/go-redis/v9"
	"golang.org/x/crypto/bcrypt"
)

// seedOwnerAndEmployee creates an approved owner and one active employee of
// that owner, both with bcrypt-hashed passwords.
func seedOwnerAndEmployee(t *testing.T, mongoStore *store.MongoDB) (*models.User, *models.User, string, string) {
	t.Helper()
	ctx := context.Background()

	ownerPassword := "OwnerPassword1"
	empPassword := "EmployeePassword1"
	hashedOwner, err := bcrypt.GenerateFromPassword([]byte(ownerPassword), bcrypt.DefaultCost)
	if err != nil {
		t.Fatalf("failed to hash owner password: %v", err)
	}
	hashedEmp, err := bcrypt.GenerateFromPassword([]byte(empPassword), bcrypt.DefaultCost)
	if err != nil {
		t.Fatalf("failed to hash employee password: %v", err)
	}

	owner := &models.User{
		ID:        "owner-sec07",
		Email:     "owner-sec07@example.com",
		Username:  "owner_sec07",
		Password:  string(hashedOwner),
		Role:      models.RoleOwner,
		KYCStatus: models.KYCApproved,
		IsActive:  true,
		CreatedAt: time.Now().UTC(),
	}
	emp := &models.User{
		ID:        "emp-sec07",
		Email:     "emp-sec07@example.com",
		Username:  "emp_sec07",
		Password:  string(hashedEmp),
		Role:      models.RoleEmployee,
		OwnerID:   owner.ID,
		TenantID:  owner.ID,
		IsActive:  true,
		CreatedAt: time.Now().UTC(),
	}
	if err := mongoStore.CreateUser(ctx, owner); err != nil {
		t.Fatalf("failed to create owner: %v", err)
	}
	if err := mongoStore.CreateUser(ctx, emp); err != nil {
		t.Fatalf("failed to create employee: %v", err)
	}
	return owner, emp, ownerPassword, empPassword
}

// loginEmployee authenticates the employee (no 2FA for employees) and returns
// the issued JWT.
func loginEmployee(t *testing.T, a *Auth, email, password string) string {
	t.Helper()
	body, _ := json.Marshal(models.LoginRequest{Email: email, Password: password})
	req := httptest.NewRequest("POST", "/auth/login", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	a.Login(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("employee login failed: got %d. Body: %s", rec.Code, rec.Body.String())
	}
	var resp map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to decode login response: %v", err)
	}
	token, _ := resp["token"].(string)
	if token == "" {
		t.Fatalf("expected token in login response, got: %s", rec.Body.String())
	}
	return token
}

// TestToggleEmployee_FreezeRevokesSessions: SEC-07 — freezing an employee must
// revoke their sessions, and the employee's still-valid token must be rejected
// by jwtutil.ValidateToken immediately. The login and the freeze run in the
// same wall-clock second, covering the same-second revocation edge case.
func TestToggleEmployee_FreezeRevokesSessions(t *testing.T) {
	a, mongoStore, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	owner, emp, ownerPassword, empPassword := seedOwnerAndEmployee(t, mongoStore)

	token := loginEmployee(t, a, emp.Email, empPassword)
	if _, err := jwtutil.ValidateToken(token); err != nil {
		t.Fatalf("employee token must be valid before freeze, got: %v", err)
	}

	body, _ := json.Marshal(models.ToggleEmployeeRequest{
		EmployeeEmail: emp.Email,
		OwnerEmail:    owner.Email,
		OwnerPassword: ownerPassword,
		SetActive:     false,
	})
	req := httptest.NewRequest("POST", "/auth/employee/toggle", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	a.ToggleEmployee(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("freeze failed: got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// The pre-freeze token must be rejected immediately (same second included).
	if _, err := jwtutil.ValidateToken(token); err == nil || err.Error() != "jwtutil: token has been revoked" {
		t.Fatalf("expected employee token to be revoked right after freeze, got: %v", err)
	}

	// The employee must actually be inactive in the store.
	updated := mongoStore.GetByEmail(ctx, emp.Email)
	if updated == nil {
		t.Fatal("employee disappeared from store")
	}
	if updated.IsActive {
		t.Fatal("expected employee to be inactive after freeze")
	}
}

// TestToggleEmployee_FreezeRevokeFailure_FailsClosed: SEC-07 — if session
// revocation fails (Redis unreachable), the toggle must fail and the employee
// must NOT be left inactive-but-unrevoked.
func TestToggleEmployee_FreezeRevokeFailure_FailsClosed(t *testing.T) {
	a, mongoStore, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	owner, emp, ownerPassword, empPassword := seedOwnerAndEmployee(t, mongoStore)

	token := loginEmployee(t, a, emp.Email, empPassword)
	if _, err := jwtutil.ValidateToken(token); err != nil {
		t.Fatalf("employee token must be valid before the failed freeze, got: %v", err)
	}

	// Point jwtutil at an unreachable Redis so RevokeAllUserTokens fails fast.
	deadClient := redis.NewClient(&redis.Options{Addr: "127.0.0.1:1"})
	defer deadClient.Close()
	jwtutil.SetRedisClient(deadClient)
	defer jwtutil.SetRedisClient(nil)

	body, _ := json.Marshal(models.ToggleEmployeeRequest{
		EmployeeEmail: emp.Email,
		OwnerEmail:    owner.Email,
		OwnerPassword: ownerPassword,
		SetActive:     false,
	})
	req := httptest.NewRequest("POST", "/auth/employee/toggle", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	a.ToggleEmployee(rec, req)

	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected 503 when revocation fails, got %d. Body: %s", rec.Code, rec.Body.String())
	}
	var resp struct {
		Code string `json:"code"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to decode error response: %v", err)
	}
	if resp.Code != "service_unavailable" {
		t.Errorf("expected stable error code service_unavailable, got %q", resp.Code)
	}

	// Fail closed AND consistent: the employee must still be active (the
	// freeze was rejected), never inactive with live tokens.
	updated := mongoStore.GetByEmail(ctx, emp.Email)
	if updated == nil {
		t.Fatal("employee disappeared from store")
	}
	if !updated.IsActive {
		t.Fatal("employee must remain active when revocation fails (no inactive-but-unrevoked state)")
	}
}
