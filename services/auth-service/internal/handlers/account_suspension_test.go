package handlers

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"golang.org/x/crypto/bcrypt"

	"github.com/project/auth-service/internal/models"
)

func TestLogin_SuspendedAccountBlocked(t *testing.T) {
	auth, s, cleanup := setupTestAuth(t)
	if auth == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	hash, _ := bcrypt.GenerateFromPassword([]byte("Password123!"), bcrypt.MinCost)

	// 1. Suspended owner
	owner := &models.User{
		ID:            "owner-suspended-1",
		Email:         "suspended_owner@example.com",
		Username:      "suspended_owner",
		Password:      string(hash),
		Role:          models.RoleOwner,
		IsActive:      false,
		AccountStatus: models.AccountStatusSuspended,
		CreatedAt:     time.Now().UTC(),
	}
	if err := s.CreateUser(ctx, owner); err != nil {
		t.Fatalf("failed to create owner: %v", err)
	}

	// 2. Suspended user
	normalUser := &models.User{
		ID:            "user-suspended-1",
		Email:         "suspended_user@example.com",
		Username:      "suspended_user",
		Password:      string(hash),
		Role:          models.RoleUser,
		IsActive:      false,
		AccountStatus: models.AccountStatusSuspended,
		CreatedAt:     time.Now().UTC(),
	}
	if err := s.CreateUser(ctx, normalUser); err != nil {
		t.Fatalf("failed to create user: %v", err)
	}

	// 3. Suspended employee
	employee := &models.User{
		ID:            "emp-suspended-1",
		Email:         "suspended_emp@example.com",
		Username:      "suspended_emp",
		Password:      string(hash),
		Role:          models.RoleEmployee,
		IsActive:      false,
		AccountStatus: models.AccountStatusSuspended,
		OwnerID:       "owner-1",
		CreatedAt:     time.Now().UTC(),
	}
	if err := s.CreateUser(ctx, employee); err != nil {
		t.Fatalf("failed to create employee: %v", err)
	}

	mux := http.NewServeMux()
	auth.RegisterRoutes(mux)

	tests := []struct {
		name       string
		email      string
		wantError  string
		statusCode int
	}{
		{
			name:       "Suspended Owner",
			email:      "suspended_owner@example.com",
			wantError:  "account is suspended",
			statusCode: http.StatusForbidden,
		},
		{
			name:       "Suspended Regular User",
			email:      "suspended_user@example.com",
			wantError:  "account is suspended",
			statusCode: http.StatusForbidden,
		},
		{
			name:       "Suspended Employee",
			email:      "suspended_emp@example.com",
			wantError:  "employee account is frozen/inactive",
			statusCode: http.StatusForbidden,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			body, _ := json.Marshal(models.LoginRequest{
				Email:    tc.email,
				Password: "Password123!",
			})
			req := httptest.NewRequest(http.MethodPost, "/auth/login", bytes.NewReader(body))
			req.Header.Set("Content-Type", "application/json")
			w := httptest.NewRecorder()

			mux.ServeHTTP(w, req)

			if w.Code != tc.statusCode {
				t.Fatalf("expected status %d, got %d. Body: %s", tc.statusCode, w.Code, w.Body.String())
			}

			var resp map[string]string
			_ = json.Unmarshal(w.Body.Bytes(), &resp)
			if !strings.Contains(resp["error"], tc.wantError) {
				t.Errorf("expected error containing %q, got %q", tc.wantError, resp["error"])
			}
		})
	}
}

func TestVerifyOTP_SuspendedAccountBlocked(t *testing.T) {
	auth, s, cleanup := setupTestAuth(t)
	if auth == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	hash, _ := bcrypt.GenerateFromPassword([]byte("Password123!"), bcrypt.MinCost)
	user := &models.User{
		ID:            "user-otp-suspended",
		Email:         "user_otp_susp@example.com",
		Username:      "user_otp_susp",
		Password:      string(hash),
		Role:          models.RoleUser,
		IsActive:      false,
		AccountStatus: models.AccountStatusSuspended,
		CreatedAt:     time.Now().UTC(),
	}
	if err := s.CreateUser(ctx, user); err != nil {
		t.Fatalf("failed to create user: %v", err)
	}

	_ = s.SetOTP(ctx, user.Email, "123456")

	mux := http.NewServeMux()
	auth.RegisterRoutes(mux)

	body, _ := json.Marshal(models.VerifyOTPRequest{
		Email: user.Email,
		OTP:   "123456",
	})
	req := httptest.NewRequest(http.MethodPost, "/auth/verify-otp", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	mux.ServeHTTP(w, req)

	if w.Code != http.StatusForbidden {
		t.Fatalf("expected 403 Forbidden on 2FA login for suspended account, got %d: %s", w.Code, w.Body.String())
	}
	var resp map[string]string
	_ = json.Unmarshal(w.Body.Bytes(), &resp)
	if resp["error"] != "account is suspended" {
		t.Errorf("expected 'account is suspended', got %q", resp["error"])
	}
}

func TestVerifyEmployeeAssignment_SuspendedChecks(t *testing.T) {
	auth, s, cleanup := setupTestAuth(t)
	if auth == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()

	// 1. Owner active & KYC approved
	owner := &models.User{
		ID:            "owner-good",
		Email:         "owner_good@example.com",
		Username:      "owner_good",
		Role:          models.RoleOwner,
		IsActive:      true,
		AccountStatus: models.AccountStatusActive,
		KYCStatus:     models.KYCApproved,
		CreatedAt:     time.Now().UTC(),
	}
	_ = s.CreateUser(ctx, owner)

	// 2. Suspended Employee under good owner
	empSuspended := &models.User{
		ID:            "emp-susp",
		Email:         "emp_susp@example.com",
		Username:      "emp_susp",
		Role:          models.RoleEmployee,
		OwnerID:       owner.ID,
		IsActive:      false,
		AccountStatus: models.AccountStatusSuspended,
		KYEStatus:     models.KYCApproved,
		CreatedAt:     time.Now().UTC(),
	}
	_ = s.CreateUser(ctx, empSuspended)

	// 3. Suspended Owner
	ownerSuspended := &models.User{
		ID:            "owner-susp",
		Email:         "owner_susp@example.com",
		Username:      "owner_susp",
		Role:          models.RoleOwner,
		IsActive:      false,
		AccountStatus: models.AccountStatusSuspended,
		KYCStatus:     models.KYCApproved,
		CreatedAt:     time.Now().UTC(),
	}
	_ = s.CreateUser(ctx, ownerSuspended)

	// 4. Active Employee under suspended owner
	empActiveUnderSusp := &models.User{
		ID:            "emp-under-susp",
		Email:         "emp_under_susp@example.com",
		Username:      "emp_under_susp",
		Role:          models.RoleEmployee,
		OwnerID:       ownerSuspended.ID,
		IsActive:      true,
		AccountStatus: models.AccountStatusActive,
		KYEStatus:     models.KYCApproved,
		CreatedAt:     time.Now().UTC(),
	}
	_ = s.CreateUser(ctx, empActiveUnderSusp)

	// Test 1: Suspended employee call
	body1, _ := json.Marshal(map[string]string{
		"email":  empSuspended.Email,
		"action": "delivery_action",
	})
	req1 := httptest.NewRequest(http.MethodPost, "/auth/employee/action", bytes.NewReader(body1))
	req1.Header.Set("Content-Type", "application/json")
	w1 := httptest.NewRecorder()
	auth.SimulateEmployeeAction(w1, req1)

	if w1.Code != http.StatusForbidden {
		t.Fatalf("expected 403 for suspended employee action, got %d", w1.Code)
	}

	// Test 2: Active employee under suspended owner call
	body2, _ := json.Marshal(map[string]string{
		"email":  empActiveUnderSusp.Email,
		"action": "delivery_action",
	})
	req2 := httptest.NewRequest(http.MethodPost, "/auth/employee/action", bytes.NewReader(body2))
	req2.Header.Set("Content-Type", "application/json")
	w2 := httptest.NewRecorder()
	auth.SimulateEmployeeAction(w2, req2)

	if w2.Code != http.StatusForbidden {
		t.Fatalf("expected 403 for employee under suspended owner, got %d", w2.Code)
	}
}

func TestGetAccounts_SecurityAndFilters(t *testing.T) {
	auth, s, cleanup := setupTestAuth(t)
	if auth == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()

	// Seed reviewer
	rawTok := "reviewer-token-abc"
	digest := sha256.Sum256([]byte(rawTok))
	hexDigest := hex.EncodeToString(digest[:])
	_ = s.AddReviewer(ctx, &models.Reviewer{
		ID:    "reviewer-1",
		Token: hexDigest,
		Name:  "Lead Reviewer",
	})

	setHeaders := func(req *http.Request) {
		req.Header.Set("X-Internal-Token", auth.internalServiceToken)
		req.Header.Set("X-Reviewer-Token", rawTok)
	}

	// Seed accounts
	users := []*models.User{
		{
			ID:            "acc-1",
			Email:         "alice_owner@example.com",
			Username:      "AliceOwner",
			Role:          models.RoleOwner,
			IsActive:      true,
			AccountStatus: models.AccountStatusActive,
			KYCStatus:     models.KYCApproved,
			CreatedAt:     time.Now().UTC().Add(-3 * time.Hour),
		},
		{
			ID:               "acc-2",
			Email:            "bob_driver@example.com",
			Username:         "BobDriver",
			Role:             models.RoleEmployee,
			IsActive:         false,
			AccountStatus:    models.AccountStatusSuspended,
			SuspensionReason: "Reckless driving reports",
			KYEStatus:        models.KYCApproved,
			CreatedAt:        time.Now().UTC().Add(-2 * time.Hour),
		},
		{
			ID:            "acc-3",
			Email:         "carol_customer@example.com",
			Username:      "CarolCustomer",
			Role:          models.RoleUser,
			IsActive:      true,
			AccountStatus: models.AccountStatusActive,
			CreatedAt:     time.Now().UTC().Add(-1 * time.Hour),
		},
	}
	for _, u := range users {
		_ = s.CreateUser(ctx, u)
	}

	mux := http.NewServeMux()
	auth.RegisterRoutes(mux)

	// 1. Unauthorized without reviewer tokens
	reqNoAuth := httptest.NewRequest(http.MethodGet, "/auth/accounts", nil)
	wNoAuth := httptest.NewRecorder()
	mux.ServeHTTP(wNoAuth, reqNoAuth)
	if wNoAuth.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 Unauthorized without reviewer tokens, got %d", wNoAuth.Code)
	}

	// 2. Fetch all with valid reviewer tokens
	reqAll := httptest.NewRequest(http.MethodGet, "/auth/accounts", nil)
	setHeaders(reqAll)
	wAll := httptest.NewRecorder()
	mux.ServeHTTP(wAll, reqAll)

	if wAll.Code != http.StatusOK {
		t.Fatalf("expected 200 OK, got %d: %s", wAll.Code, wAll.Body.String())
	}
	var respAll models.AccountDirectoryResponse
	if err := json.Unmarshal(wAll.Body.Bytes(), &respAll); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	if respAll.Total != 3 || len(respAll.Accounts) != 3 {
		t.Fatalf("expected 3 accounts, got total=%d len=%d", respAll.Total, len(respAll.Accounts))
	}

	// 3. Search by username substring ("bob")
	reqSearch := httptest.NewRequest(http.MethodGet, "/auth/accounts?search=bob", nil)
	setHeaders(reqSearch)
	wSearch := httptest.NewRecorder()
	mux.ServeHTTP(wSearch, reqSearch)
	var respSearch models.AccountDirectoryResponse
	_ = json.Unmarshal(wSearch.Body.Bytes(), &respSearch)
	if respSearch.Total != 1 || respSearch.Accounts[0].Username != "BobDriver" {
		t.Fatalf("expected 1 match for 'bob', got %d", respSearch.Total)
	}
	if respSearch.Accounts[0].SuspensionReason != "Reckless driving reports" {
		t.Errorf("expected suspension reason to be preserved, got %q", respSearch.Accounts[0].SuspensionReason)
	}

	// 4. Search by exact ID ("acc-1")
	reqID := httptest.NewRequest(http.MethodGet, "/auth/accounts?search=acc-1", nil)
	setHeaders(reqID)
	wID := httptest.NewRecorder()
	mux.ServeHTTP(wID, reqID)
	var respID models.AccountDirectoryResponse
	_ = json.Unmarshal(wID.Body.Bytes(), &respID)
	if respID.Total != 1 || respID.Accounts[0].ID != "acc-1" {
		t.Fatalf("expected 1 match for 'acc-1', got %d", respID.Total)
	}

	// 5. Filter by role ("owner")
	reqRole := httptest.NewRequest(http.MethodGet, "/auth/accounts?role=owner", nil)
	setHeaders(reqRole)
	wRole := httptest.NewRecorder()
	mux.ServeHTTP(wRole, reqRole)
	var respRole models.AccountDirectoryResponse
	_ = json.Unmarshal(wRole.Body.Bytes(), &respRole)
	if respRole.Total != 1 || respRole.Accounts[0].Role != models.RoleOwner {
		t.Fatalf("expected 1 owner match, got %d", respRole.Total)
	}

	// 6. Filter by status ("suspended")
	reqSusp := httptest.NewRequest(http.MethodGet, "/auth/accounts?status=suspended", nil)
	setHeaders(reqSusp)
	wSusp := httptest.NewRecorder()
	mux.ServeHTTP(wSusp, reqSusp)
	var respSusp models.AccountDirectoryResponse
	_ = json.Unmarshal(wSusp.Body.Bytes(), &respSusp)
	if respSusp.Total != 1 || respSusp.Accounts[0].Username != "BobDriver" {
		t.Fatalf("expected 1 suspended match, got %d", respSusp.Total)
	}

	// 7. Pagination test (limit=2, page=1 -> 2 items; page=2 -> 1 item)
	reqP1 := httptest.NewRequest(http.MethodGet, "/auth/accounts?limit=2&page=1", nil)
	setHeaders(reqP1)
	wP1 := httptest.NewRecorder()
	mux.ServeHTTP(wP1, reqP1)
	var respP1 models.AccountDirectoryResponse
	_ = json.Unmarshal(wP1.Body.Bytes(), &respP1)
	if len(respP1.Accounts) != 2 || respP1.Total != 3 {
		t.Fatalf("expected page 1 with 2 accounts out of 3, got len=%d total=%d", len(respP1.Accounts), respP1.Total)
	}

	reqP2 := httptest.NewRequest(http.MethodGet, "/auth/accounts?limit=2&page=2", nil)
	setHeaders(reqP2)
	wP2 := httptest.NewRecorder()
	mux.ServeHTTP(wP2, reqP2)
	var respP2 models.AccountDirectoryResponse
	_ = json.Unmarshal(wP2.Body.Bytes(), &respP2)
	if len(respP2.Accounts) != 1 || respP2.Total != 3 {
		t.Fatalf("expected page 2 with 1 account out of 3, got len=%d total=%d", len(respP2.Accounts), respP2.Total)
	}
}

func TestSuspendAndReactivateLifecycle(t *testing.T) {
	auth, s, cleanup := setupTestAuth(t)
	if auth == nil {
		return
	}
	defer cleanup()

	// Mock notification server
	type capturedRequest struct {
		internalToken string
		payload       map[string]any
	}
	var mu sync.Mutex
	var captured []capturedRequest
	notifSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/notifications/send" {
			http.NotFound(w, r)
			return
		}
		var payload map[string]any
		_ = json.NewDecoder(r.Body).Decode(&payload)
		mu.Lock()
		captured = append(captured, capturedRequest{
			internalToken: r.Header.Get("X-Internal-Token"),
			payload:       payload,
		})
		mu.Unlock()
		w.WriteHeader(http.StatusOK)
		_ = json.NewEncoder(w).Encode(map[string]any{"message": "ok"})
	}))
	defer notifSrv.Close()
	auth.notificationURL = notifSrv.URL

	ctx := context.Background()

	// Seed reviewer
	rawTok := "reviewer-token-abc"
	digest := sha256.Sum256([]byte(rawTok))
	hexDigest := hex.EncodeToString(digest[:])
	_ = s.AddReviewer(ctx, &models.Reviewer{
		ID:    "reviewer-1",
		Token: hexDigest,
		Name:  "Lead Reviewer",
	})

	setHeaders := func(req *http.Request) {
		req.Header.Set("X-Internal-Token", auth.internalServiceToken)
		req.Header.Set("X-Reviewer-Token", rawTok)
	}

	hash, _ := bcrypt.GenerateFromPassword([]byte("Password123!"), bcrypt.MinCost)
	user := &models.User{
		ID:            "target-user-lifecycle",
		Email:         "target_lifecycle@example.com",
		Username:      "target_lifecycle",
		Password:      string(hash),
		Role:          models.RoleOwner,
		IsActive:      true,
		AccountStatus: models.AccountStatusActive,
		KYCStatus:     models.KYCApproved,
		TenantID:      "target-user-lifecycle",
		CreatedAt:     time.Now().UTC(),
	}
	if err := s.CreateUser(ctx, user); err != nil {
		t.Fatalf("failed to create user: %v", err)
	}

	mux := http.NewServeMux()
	auth.RegisterRoutes(mux)

	// --- 1. Suspend validations ---
	// 1a. Missing reason
	bodyNoReason, _ := json.Marshal(models.SuspendAccountRequest{
		UserID: user.ID,
		Reason: "   ",
	})
	reqNoReason := httptest.NewRequest(http.MethodPost, "/auth/accounts/suspend", bytes.NewReader(bodyNoReason))
	setHeaders(reqNoReason)
	wNoReason := httptest.NewRecorder()
	mux.ServeHTTP(wNoReason, reqNoReason)
	if wNoReason.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 Bad Request for whitespace reason, got %d", wNoReason.Code)
	}

	// 1b. Oversized reason (> 1000 chars)
	bodyLongReason, _ := json.Marshal(models.SuspendAccountRequest{
		UserID: user.ID,
		Reason: strings.Repeat("x", 1001),
	})
	reqLongReason := httptest.NewRequest(http.MethodPost, "/auth/accounts/suspend", bytes.NewReader(bodyLongReason))
	setHeaders(reqLongReason)
	wLongReason := httptest.NewRecorder()
	mux.ServeHTTP(wLongReason, reqLongReason)
	if wLongReason.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 Bad Request for reason > 1000 chars, got %d", wLongReason.Code)
	}

	// 1c. Non-existent user
	bodyNonExistent, _ := json.Marshal(models.SuspendAccountRequest{
		UserID: "non-existent-user-id",
		Reason: "Suspension test",
	})
	reqNonExistent := httptest.NewRequest(http.MethodPost, "/auth/accounts/suspend", bytes.NewReader(bodyNonExistent))
	setHeaders(reqNonExistent)
	wNonExistent := httptest.NewRecorder()
	mux.ServeHTTP(wNonExistent, reqNonExistent)
	if wNonExistent.Code != http.StatusNotFound {
		t.Fatalf("expected 404 Not Found for non-existent user, got %d", wNonExistent.Code)
	}

	// --- 2. Successful Suspension ---
	bodyValidSuspend, _ := json.Marshal(models.SuspendAccountRequest{
		UserID: user.ID,
		Reason: "Fraudulent chargeback activity detected",
	})
	reqValidSuspend := httptest.NewRequest(http.MethodPost, "/auth/accounts/suspend", bytes.NewReader(bodyValidSuspend))
	setHeaders(reqValidSuspend)
	wValidSuspend := httptest.NewRecorder()
	mux.ServeHTTP(wValidSuspend, reqValidSuspend)

	if wValidSuspend.Code != http.StatusOK {
		t.Fatalf("expected 200 OK for valid suspend, got %d: %s", wValidSuspend.Code, wValidSuspend.Body.String())
	}

	// Verify database record
	updatedUser := s.GetByID(ctx, user.ID)
	if updatedUser.AccountStatus != models.AccountStatusSuspended || updatedUser.IsActive != false {
		t.Fatalf("expected account_status=suspended and is_active=false, got status=%s active=%v", updatedUser.AccountStatus, updatedUser.IsActive)
	}
	if updatedUser.SuspensionReason != "Fraudulent chargeback activity detected" {
		t.Errorf("unexpected suspension reason: %q", updatedUser.SuspensionReason)
	}
	if updatedUser.SuspendedAt == nil {
		t.Errorf("expected suspended_at timestamp to be set")
	}
	if updatedUser.KYCStatus != models.KYCApproved {
		t.Errorf("KYC status must be preserved intact upon suspension, got %q", updatedUser.KYCStatus)
	}

	// Verify notification dispatch
	time.Sleep(50 * time.Millisecond) // Allow async goroutine to execute
	mu.Lock()
	numCaptured := len(captured)
	var lastReq capturedRequest
	if numCaptured > 0 {
		lastReq = captured[numCaptured-1]
	}
	mu.Unlock()

	if numCaptured == 0 {
		t.Errorf("expected outcome notification to be sent to mock notification service")
	} else {
		if lastReq.payload["type"] != "account_suspended" || lastReq.payload["user_id"] != user.ID {
			t.Errorf("unexpected notification payload: %+v", lastReq.payload)
		}
	}

	// --- 3. Duplicate Suspension (CAS conflict) ---
	reqDup := httptest.NewRequest(http.MethodPost, "/auth/accounts/suspend", bytes.NewReader(bodyValidSuspend))
	setHeaders(reqDup)
	wDup := httptest.NewRecorder()
	mux.ServeHTTP(wDup, reqDup)
	if wDup.Code != http.StatusConflict {
		t.Fatalf("expected 409 Conflict when suspending already suspended account, got %d", wDup.Code)
	}

	// --- 4. Verify login is now blocked ---
	bodyLogin, _ := json.Marshal(models.LoginRequest{
		Email:    user.Email,
		Password: "Password123!",
	})
	reqLogin := httptest.NewRequest(http.MethodPost, "/auth/login", bytes.NewReader(bodyLogin))
	wLogin := httptest.NewRecorder()
	mux.ServeHTTP(wLogin, reqLogin)
	if wLogin.Code != http.StatusForbidden {
		t.Fatalf("expected 403 Forbidden on login for suspended account, got %d", wLogin.Code)
	}

	// --- 5. Reactivate Account (via path param /auth/accounts/{id}/reactivate) ---
	bodyReactivate, _ := json.Marshal(models.ReactivateAccountRequest{
		Reason: "Chargeback dispute resolved successfully",
	})
	reqReactivate := httptest.NewRequest(http.MethodPost, fmt.Sprintf("/auth/accounts/%s/reactivate", user.ID), bytes.NewReader(bodyReactivate))
	setHeaders(reqReactivate)
	wReactivate := httptest.NewRecorder()
	mux.ServeHTTP(wReactivate, reqReactivate)

	if wReactivate.Code != http.StatusOK {
		t.Fatalf("expected 200 OK on reactivation, got %d: %s", wReactivate.Code, wReactivate.Body.String())
	}

	// Verify database record restored
	reactivatedUser := s.GetByID(ctx, user.ID)
	if reactivatedUser.AccountStatus != models.AccountStatusActive || reactivatedUser.IsActive != true {
		t.Fatalf("expected account_status=active and is_active=true, got status=%s active=%v", reactivatedUser.AccountStatus, reactivatedUser.IsActive)
	}
	if reactivatedUser.SuspensionReason != "" {
		t.Errorf("expected suspension reason to be cleared, got %q", reactivatedUser.SuspensionReason)
	}
	if reactivatedUser.ReactivatedAt == nil {
		t.Errorf("expected reactivated_at timestamp to be set")
	}

	// --- 6. Duplicate Reactivate (CAS conflict) ---
	reqReactivateDup := httptest.NewRequest(http.MethodPost, fmt.Sprintf("/auth/accounts/%s/reactivate", user.ID), bytes.NewReader(bodyReactivate))
	setHeaders(reqReactivateDup)
	wReactivateDup := httptest.NewRecorder()
	mux.ServeHTTP(wReactivateDup, reqReactivateDup)
	if wReactivateDup.Code != http.StatusConflict {
		t.Fatalf("expected 409 Conflict when reactivating already active account, got %d", wReactivateDup.Code)
	}

	// --- 7. Verify login is now permitted ---
	reqLogin2 := httptest.NewRequest(http.MethodPost, "/auth/login", bytes.NewReader(bodyLogin))
	wLogin2 := httptest.NewRecorder()
	mux.ServeHTTP(wLogin2, reqLogin2)
	if wLogin2.Code != http.StatusOK {
		t.Fatalf("expected 200 OK on login after reactivation, got %d: %s", wLogin2.Code, wLogin2.Body.String())
	}

	// --- 8. Verify Audit Log Entries ---
	auditLogs := s.GetAuditLog(ctx, user.ID)
	var foundSusp, foundReact bool
	for _, entry := range auditLogs {
		if entry.Action == "ACCOUNT_SUSPENDED" {
			foundSusp = true
		}
		if entry.Action == "ACCOUNT_REACTIVATED" {
			foundReact = true
		}
	}
	if !foundSusp {
		t.Errorf("expected ACCOUNT_SUSPENDED audit entry to be recorded")
	}
	if !foundReact {
		t.Errorf("expected ACCOUNT_REACTIVATED audit entry to be recorded")
	}
}
