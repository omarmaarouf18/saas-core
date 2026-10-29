package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"
	"time"

	"github.com/project/auth-service/internal/models"
)

func TestAuth_GetInternalOverviewStats(t *testing.T) {
	a, s, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	now := time.Now().UTC()

	// Seed users:
	// 1. Pending KYB owner
	s.CreateUser(ctx, &models.User{
		ID:        "user-pending-kyb",
		Email:     "kyb@example.com",
		Username:  "kyb_user",
		Role:      models.RoleOwner,
		KYCStatus: models.KYCPendingApproval,
		IsActive:  true,
		CreatedAt: now,
	})
	// 2. Pending KYE employee
	s.CreateUser(ctx, &models.User{
		ID:        "user-pending-kye",
		Email:     "kye@example.com",
		Username:  "kye_user",
		Role:      models.RoleEmployee,
		KYEStatus: models.KYCPendingApproval,
		IsActive:  true,
		CreatedAt: now,
	})
	// 3. Suspended user
	s.CreateUser(ctx, &models.User{
		ID:            "user-suspended",
		Email:         "susp@example.com",
		Username:      "susp_user",
		Role:          models.RoleUser,
		AccountStatus: models.AccountStatusSuspended,
		IsActive:      false,
		CreatedAt:     now.AddDate(0, 0, -2),
	})
	// 4. Old active user (10 days ago)
	s.CreateUser(ctx, &models.User{
		ID:            "user-old",
		Email:         "old@example.com",
		Username:      "old_user",
		Role:          models.RoleUser,
		AccountStatus: models.AccountStatusActive,
		IsActive:      true,
		CreatedAt:     now.AddDate(0, 0, -10),
	})

	// Test 1: Unauthorized without internal token
	reqNoAuth := httptest.NewRequest(http.MethodGet, "/auth/internal/overview-stats", nil)
	recNoAuth := httptest.NewRecorder()
	a.GetInternalOverviewStats(recNoAuth, reqNoAuth)
	if recNoAuth.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 Unauthorized, got %d", recNoAuth.Code)
	}

	// Test 2: Method not allowed
	reqPost := httptest.NewRequest(http.MethodPost, "/auth/internal/overview-stats", nil)
	reqPost.Header.Set("X-Internal-Token", a.internalServiceToken)
	recPost := httptest.NewRecorder()
	a.GetInternalOverviewStats(recPost, reqPost)
	if recPost.Code != http.StatusMethodNotAllowed {
		t.Fatalf("expected 405 Method Not Allowed, got %d", recPost.Code)
	}

	// Test 3: Success with internal token
	req := httptest.NewRequest(http.MethodGet, "/auth/internal/overview-stats", nil)
	req.Header.Set("X-Internal-Token", a.internalServiceToken)
	rec := httptest.NewRecorder()
	a.GetInternalOverviewStats(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK, got %d: %s", rec.Code, rec.Body.String())
	}

	var stats map[string]int64
	if err := json.Unmarshal(rec.Body.Bytes(), &stats); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}

	if stats["pending_kyb_kye"] < 2 {
		t.Errorf("expected at least 2 pending_kyb_kye, got %d", stats["pending_kyb_kye"])
	}
	if stats["new_accounts_today"] < 2 {
		t.Errorf("expected at least 2 new_accounts_today, got %d", stats["new_accounts_today"])
	}
	if stats["new_accounts_7d"] < 3 {
		t.Errorf("expected at least 3 new_accounts_7d, got %d", stats["new_accounts_7d"])
	}
	if stats["suspended_accounts"] < 1 {
		t.Errorf("expected at least 1 suspended_accounts, got %d", stats["suspended_accounts"])
	}
}

func TestAuth_GetUserByPhone(t *testing.T) {
	a, s, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	phone := "+201012345678"
	s.CreateUser(ctx, &models.User{
		ID:        "user-phone-test",
		Email:     "phone@example.com",
		Username:  "phone_user",
		Phone:     phone,
		Role:      models.RoleUser,
		IsActive:  true,
		CreatedAt: time.Now().UTC(),
	})

	// 1. Missing / invalid internal token -> 401
	reqNoAuth := httptest.NewRequest(http.MethodGet, "/auth/internal/user-by-phone?phone="+phone, nil)
	recNoAuth := httptest.NewRecorder()
	a.GetUserByPhone(recNoAuth, reqNoAuth)
	if recNoAuth.Code != http.StatusUnauthorized {
		t.Errorf("expected 401, got %d", recNoAuth.Code)
	}

	// 2. Missing phone parameter -> 400
	reqNoPhone := httptest.NewRequest(http.MethodGet, "/auth/internal/user-by-phone", nil)
	reqNoPhone.Header.Set("X-Internal-Token", a.internalServiceToken)
	recNoPhone := httptest.NewRecorder()
	a.GetUserByPhone(recNoPhone, reqNoPhone)
	if recNoPhone.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", recNoPhone.Code)
	}

	// 3. User not found -> 404
	reqNotFound := httptest.NewRequest(http.MethodGet, "/auth/internal/user-by-phone?phone="+url.QueryEscape("+201999999999"), nil)
	reqNotFound.Header.Set("X-Internal-Token", a.internalServiceToken)
	recNotFound := httptest.NewRecorder()
	a.GetUserByPhone(recNotFound, reqNotFound)
	if recNotFound.Code != http.StatusNotFound {
		t.Errorf("expected 404, got %d", recNotFound.Code)
	}

	// 4. Found -> 200
	reqFound := httptest.NewRequest(http.MethodGet, "/auth/internal/user-by-phone?phone="+url.QueryEscape(phone), nil)
	reqFound.Header.Set("X-Internal-Token", a.internalServiceToken)
	recFound := httptest.NewRecorder()
	a.GetUserByPhone(recFound, reqFound)
	if recFound.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", recFound.Code, recFound.Body.String())
	}

	var u struct {
		ID    string `json:"id"`
		Phone string `json:"phone"`
	}
	if err := json.Unmarshal(recFound.Body.Bytes(), &u); err != nil {
		t.Fatalf("decode err: %v", err)
	}
	if u.ID != "user-phone-test" || u.Phone != phone {
		t.Errorf("expected user-phone-test and %s, got %s and %s", phone, u.ID, u.Phone)
	}
}
