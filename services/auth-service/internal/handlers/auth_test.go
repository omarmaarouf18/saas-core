package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/project/auth-service/internal/config"
	"github.com/project/auth-service/internal/models"
	"github.com/project/auth-service/internal/otpcrypto"
	"github.com/project/auth-service/internal/storage"
	"github.com/project/auth-service/internal/store"
	"github.com/project/shared/infra/jwtutil"
	"github.com/redis/go-redis/v9"
	"golang.org/x/crypto/bcrypt"
)

// TestBcryptHashVerify checks the password hashing and verification flow
func TestBcryptHashVerify(t *testing.T) {
	password := "my-secret-password-123"
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		t.Fatalf("Failed to hash password: %v", err)
	}

	// Verify success case
	err = bcrypt.CompareHashAndPassword(hashedPassword, []byte(password))
	if err != nil {
		t.Errorf("Password verification failed: %v", err)
	}

	// Verify failure case
	err = bcrypt.CompareHashAndPassword(hashedPassword, []byte("wrong-password"))
	if err == nil {
		t.Errorf("Expected password verification to fail for wrong password")
	}
}

// TestRateLimiterLockout checks rate limit lockout counting and backoff
func TestRateLimiterLockout(t *testing.T) {
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	rl := NewRateLimiter(rdb)
	key := "test-client-ip"

	// Initial state: not locked
	locked, _ := rl.IsLocked(key)
	if locked {
		t.Errorf("Expected key to not be locked initially")
	}

	// Record 4 failures (lockout threshold is 5)
	for i := 0; i < 4; i++ {
		rl.RecordFailure(key)
		locked, _ = rl.IsLocked(key)
		if locked {
			t.Errorf("Expected key to not be locked after %d failures", i+1)
		}
	}

	// 5th failure should trigger lockout
	duration := rl.RecordFailure(key)
	if duration != 30*time.Second {
		t.Errorf("Expected lockout duration to be 30 seconds, got %v", duration)
	}

	locked, remaining := rl.IsLocked(key)
	if !locked {
		t.Errorf("Expected key to be locked after 5 failures")
	}
	if remaining <= 0 || remaining > 30*time.Second {
		t.Errorf("Expected remaining duration to be <= 30 seconds, got %v", remaining)
	}

	// Reset rate limiter key
	rl.Reset(key)
	locked, _ = rl.IsLocked(key)
	if locked {
		t.Errorf("Expected key to be unlocked after reset")
	}
}

// TestOTPExpiryRejection simulates OTP verification where expiration times are set
func TestOTPExpiryRejection(t *testing.T) {
	now := time.Now()
	expiresAtPast := now.Add(-1 * time.Minute)
	expiresAtFuture := now.Add(5 * time.Minute)

	tests := []struct {
		name      string
		expiresAt time.Time
		nowTime   time.Time
		expectErr bool
	}{
		{
			name:      "Expired OTP",
			expiresAt: expiresAtPast,
			nowTime:   now,
			expectErr: true,
		},
		{
			name:      "Valid OTP",
			expiresAt: expiresAtFuture,
			nowTime:   now,
			expectErr: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			hasExpired := !tt.expiresAt.IsZero() && tt.expiresAt.Before(tt.nowTime)
			if hasExpired != tt.expectErr {
				t.Errorf("Expected expiry rejection check to return %v, got %v", tt.expectErr, hasExpired)
			}
		})
	}
}

// TestGetAuditLogAccessControl verifies that requester_id is required and must match tenant_id
func TestGetAuditLogAccessControl(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	cfg := &config.Config{
		AppEnv:               "local",
		GatewaySecret:        "mock-gateway-secret",
		InternalServiceToken: "mock-internal-token",
	}
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	tempDir := t.TempDir()
	storeLoc, _ := storage.NewLocalStorage(tempDir, "/api/v1", os.Getenv("JWT_SECRET"))
	a := NewAuth(nil, nil, cfg, rdb, storeLoc)

	token1, _ := jwtutil.GenerateToken("tenant-1", "owner", "tenant-1", "t1@example.com")
	token2, _ := jwtutil.GenerateToken("tenant-2", "owner", "tenant-2", "t2@example.com")

	// A. Mismatched tenant_id and requester_id -> 403 Forbidden
	req := httptest.NewRequest("GET", "/auth/audit-log?tenant_id=tenant-1&requester_id="+token2, nil)
	rec := httptest.NewRecorder()
	a.GetAuditLog(rec, req)

	if rec.Code != http.StatusForbidden {
		t.Errorf("Expected 403 Forbidden for mismatched tenant_id, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// B. Missing tenant_id -> 400 Bad Request
	req = httptest.NewRequest("GET", "/auth/audit-log?requester_id="+token1, nil)
	rec = httptest.NewRecorder()
	a.GetAuditLog(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("Expected 400 Bad Request for missing tenant_id, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// C. Missing requester_id -> 400 Bad Request
	req = httptest.NewRequest("GET", "/auth/audit-log?tenant_id=tenant-1", nil)
	rec = httptest.NewRecorder()
	a.GetAuditLog(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("Expected 400 Bad Request for missing requester_id, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// D. Unverified raw/malformed requester_id -> 401 Unauthorized
	req = httptest.NewRequest("GET", "/auth/audit-log?tenant_id=tenant-1&requester_id=tenant-1", nil)
	rec = httptest.NewRecorder()
	a.GetAuditLog(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Errorf("Expected 401 Unauthorized for raw requester_id, got %d. Body: %s", rec.Code, rec.Body.String())
	}
}

func setupTestAuth(t *testing.T) (*Auth, *store.MongoDB, func()) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	jwtutil.Init("z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")

	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	dbName := fmt.Sprintf("saas_auth_test_%d", time.Now().UnixNano())
	cipher, err := otpcrypto.NewCipher("")
	if err != nil {
		t.Fatalf("failed to create cipher: %v", err)
	}

	s, err := store.NewMongoDB(ctx, mongoURI, dbName, cipher)
	if err != nil {
		t.Skipf("Skipping auth-service store integration tests: MongoDB not available at %s (%v)", mongoURI, err)
		return nil, nil, nil
	}

	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})

	cfg := &config.Config{
		AppEnv:               "local",
		GatewaySecret:        "mock-gateway-secret",
		InternalServiceToken: "mock-internal-token",
		JWTSecret:            "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2",
	}

	dispatcher := &mockOTPDispatcher{}

	tempDir := t.TempDir()
	storeLoc, _ := storage.NewLocalStorage(tempDir, "/api/v1", cfg.JWTSecret)
	a := NewAuth(s, dispatcher, cfg, rdb, storeLoc)
	cleanup := func() {
		if s != nil {
			_ = s.DropDatabase(context.Background())
			s.Close(context.Background())
		}
		mr.Close()
		rdb.Close()
	}
	return a, s, cleanup
}

type mockOTPDispatcher struct{}

func (m *mockOTPDispatcher) Dispatch(email, code string) error { return nil }
func (m *mockOTPDispatcher) Name() string                      { return "mock-otp-dispatcher" }

func TestAuthHandlers(t *testing.T) {
	a, s, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	// 1. Test Signup (Success path)
	signupBody := models.SignupRequest{
		Email:    "owner@example.com",
		Password: "password123",
		Role:     models.RoleOwner,
	}
	b, _ := json.Marshal(signupBody)
	req := httptest.NewRequest("POST", "/auth/signup", bytes.NewReader(b))
	rec := httptest.NewRecorder()
	a.Signup(rec, req)
	if rec.Code != http.StatusCreated {
		t.Errorf("Expected 201 Created for Signup, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	var signupResp map[string]any
	json.Unmarshal(rec.Body.Bytes(), &signupResp)
	signupOTP := signupResp["dev_otp"].(string)

	// Test Signup Duplicate (Validation error path)
	req = httptest.NewRequest("POST", "/auth/signup", bytes.NewReader(b))
	rec = httptest.NewRecorder()
	a.Signup(rec, req)
	if rec.Code != http.StatusConflict {
		t.Errorf("Expected 409 Conflict for duplicate Signup, got %d", rec.Code)
	}

	// 1b. Verify signup OTP to confirm account
	verifySignupBody := models.VerifyOTPRequest{
		Email: "owner@example.com",
		OTP:   signupOTP,
	}
	b4, _ := json.Marshal(verifySignupBody)
	req = httptest.NewRequest("POST", "/auth/verify-otp", bytes.NewReader(b4))
	rec = httptest.NewRecorder()
	a.VerifyOTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Errorf("Expected 200 OK for VerifyOTP (signup), got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// 2. Test Login (Success path / OTP dispatched)
	loginBody := models.LoginRequest{
		Email:    "owner@example.com",
		Password: "password123",
	}
	b2, _ := json.Marshal(loginBody)
	req = httptest.NewRequest("POST", "/auth/login", bytes.NewReader(b2))
	rec = httptest.NewRecorder()
	a.Login(rec, req)
	if rec.Code != http.StatusOK {
		t.Errorf("Expected 200 OK for Login, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// Decode dev_otp from login response
	var loginResp map[string]any
	json.Unmarshal(rec.Body.Bytes(), &loginResp)
	loginOTP := loginResp["dev_otp"].(string)

	// Test Login (Wrong Password / Failure path)
	wrongLoginBody := models.LoginRequest{
		Email:    "owner@example.com",
		Password: "wrongpassword",
	}
	b3, _ := json.Marshal(wrongLoginBody)
	req = httptest.NewRequest("POST", "/auth/login", bytes.NewReader(b3))
	rec = httptest.NewRecorder()
	a.Login(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Errorf("Expected 401 Unauthorized for wrong password, got %d", rec.Code)
	}

	// 3. Test VerifyOTP (Success path for Login 2FA)
	verifyLoginBody := models.VerifyOTPRequest{
		Email: "owner@example.com",
		OTP:   loginOTP,
	}
	b5, _ := json.Marshal(verifyLoginBody)
	req = httptest.NewRequest("POST", "/auth/verify-otp", bytes.NewReader(b5))
	rec = httptest.NewRecorder()
	a.VerifyOTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Errorf("Expected 200 OK for VerifyOTP (login), got %d. Body: %s", rec.Code, rec.Body.String())
	}

	var verifyResp map[string]any
	json.Unmarshal(rec.Body.Bytes(), &verifyResp)
	token := verifyResp["token"].(string)
	ownerID := verifyResp["user_id"].(string)

	// Approve KYC for Owner to allow toggling employees
	if err := s.UpdateKYCStatus(context.Background(), ownerID, models.KYCApproved); err != nil {
		t.Fatalf("failed to approve KYC: %v", err)
	}

	// Test VerifyOTP (Invalid Code / Failure path)
	wrongVerifyBody := models.VerifyOTPRequest{
		Email: "owner@example.com",
		OTP:   "9999",
	}
	b6, _ := json.Marshal(wrongVerifyBody)
	req = httptest.NewRequest("POST", "/auth/verify-otp", bytes.NewReader(b6))
	rec = httptest.NewRecorder()
	a.VerifyOTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Errorf("Expected 401 Unauthorized for wrong OTP, got %d", rec.Code)
	}

	// 4. Test ToggleEmployee (Success path)
	// Regression tests for owner-authenticated employee signup:
	// (a) employee signup with no token -> rejected (401)
	empSignupBody := models.SignupRequest{
		Email:    "employee@example.com",
		Password: "password123",
		Role:     models.RoleEmployee,
		OwnerID:  ownerID,
	}
	b6, _ = json.Marshal(empSignupBody)
	req = httptest.NewRequest("POST", "/auth/signup", bytes.NewReader(b6))
	rec = httptest.NewRecorder()
	a.Signup(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Errorf("Expected 401 Unauthorized for employee signup without token, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// (b) employee signup with a token belonging to a different user than owner_id -> rejected (403)
	diffUserToken, _ := jwtutil.GenerateToken("different-owner-id", string(models.RoleOwner), "different-owner-id", "diff@example.com")
	req = httptest.NewRequest("POST", "/auth/signup", bytes.NewReader(b6))
	req.Header.Set("Authorization", "Bearer "+diffUserToken)
	rec = httptest.NewRecorder()
	a.Signup(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Errorf("Expected 403 Forbidden for employee signup with mismatched owner token, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// (b2) employee signup with a non-owner token -> rejected (403)
	nonOwnerToken, _ := jwtutil.GenerateToken(ownerID, string(models.RoleUser), ownerID, "user@example.com")
	req = httptest.NewRequest("POST", "/auth/signup", bytes.NewReader(b6))
	req.Header.Set("Authorization", "Bearer "+nonOwnerToken)
	rec = httptest.NewRecorder()
	a.Signup(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Errorf("Expected 403 Forbidden for employee signup with non-owner token, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// (c) employee signup with a valid owner-matching token -> succeeds (201)
	validOwnerToken, _ := jwtutil.GenerateToken(ownerID, string(models.RoleOwner), ownerID, "owner@example.com")
	req = httptest.NewRequest("POST", "/auth/signup", bytes.NewReader(b6))
	req.Header.Set("Authorization", "Bearer "+validOwnerToken)
	rec = httptest.NewRecorder()
	a.Signup(rec, req)
	if rec.Code != http.StatusCreated {
		t.Errorf("Expected 201 Created for employee signup with valid owner token, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	var empSignupResp map[string]any
	json.Unmarshal(rec.Body.Bytes(), &empSignupResp)
	empUserID := empSignupResp["user_id"].(string)

	toggleBody := models.ToggleEmployeeRequest{
		EmployeeEmail: "employee@example.com",
		OwnerEmail:    "owner@example.com",
		OwnerPassword: "password123",
		SetActive:     false, // Freeze the employee (triggers mock user-service call)
	}
	b7, _ := json.Marshal(toggleBody)
	req = httptest.NewRequest("POST", "/auth/employee/toggle", bytes.NewReader(b7))
	rec = httptest.NewRecorder()
	a.ToggleEmployee(rec, req)
	if rec.Code != http.StatusOK {
		t.Errorf("Expected 200 OK for ToggleEmployee, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// 5. Test SimulateEmployeeAction (Success path)
	// Promote employee back to active first
	toggleBody.SetActive = true
	b8, _ := json.Marshal(toggleBody)
	req = httptest.NewRequest("POST", "/auth/employee/toggle", bytes.NewReader(b8))
	rec = httptest.NewRecorder()
	a.ToggleEmployee(rec, req)

	// Now simulate action with employee JWT
	empToken, _ := jwtutil.GenerateToken(empUserID, "employee", ownerID, "employee@example.com")
	actionBody := map[string]string{
		"email":  "employee@example.com",
		"action": "view-jobs",
	}
	b9, _ := json.Marshal(actionBody)
	req = httptest.NewRequest("POST", "/auth/employee/action", bytes.NewReader(b9))
	req.Header.Set("Authorization", "Bearer "+empToken)
	rec = httptest.NewRecorder()
	a.SimulateEmployeeAction(rec, req)
	if rec.Code != http.StatusOK {
		t.Errorf("Expected 200 OK for SimulateEmployeeAction, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// Test SimulateEmployeeAction (Unauthorized path)
	req = httptest.NewRequest("POST", "/auth/employee/action", bytes.NewReader(b9))
	rec = httptest.NewRecorder()
	a.SimulateEmployeeAction(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Errorf("Expected 401 Unauthorized for missing auth header in SimulateEmployeeAction, got %d", rec.Code)
	}

	// 6. Test GetUser (Success path via JWT token)
	req = httptest.NewRequest("GET", "/auth/user?id="+token, nil)
	rec = httptest.NewRecorder()
	a.GetUser(rec, req)
	if rec.Code != http.StatusOK {
		t.Errorf("Expected 200 OK for GetUser, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// Test GetUser (Success path via internal service token)
	req = httptest.NewRequest("GET", "/auth/user?id="+empUserID, nil)
	req.Header.Set("X-Internal-Token", "mock-internal-token")
	rec = httptest.NewRecorder()
	a.GetUser(rec, req)
	if rec.Code != http.StatusOK {
		t.Errorf("Expected 200 OK for GetUser via internal token, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// Test GetUser (Failure path)
	req = httptest.NewRequest("GET", "/auth/user?id=nonexistent-id", nil)
	req.Header.Set("X-Internal-Token", "mock-internal-token")
	rec = httptest.NewRecorder()
	a.GetUser(rec, req)
	if rec.Code != http.StatusNotFound {
		t.Errorf("Expected 404 Not Found for nonexistent GetUser, got %d", rec.Code)
	}

	// 7. Test Refresh (Success path)
	refreshBody := map[string]string{
		"token": token,
	}
	b10, _ := json.Marshal(refreshBody)
	req = httptest.NewRequest("POST", "/auth/refresh", bytes.NewReader(b10))
	rec = httptest.NewRecorder()
	a.Refresh(rec, req)
	if rec.Code != http.StatusOK {
		t.Errorf("Expected 200 OK for Refresh, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// Test Refresh (Failure path)
	refreshBody = map[string]string{
		"token": "invalid-token",
	}
	b11, _ := json.Marshal(refreshBody)
	req = httptest.NewRequest("POST", "/auth/refresh", bytes.NewReader(b11))
	rec = httptest.NewRecorder()
	a.Refresh(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Errorf("Expected 401 Unauthorized for invalid Refresh token, got %d", rec.Code)
	}
}

func createMultipartRequest(method, url, filename, contentType string, content []byte) (*http.Request, error) {
	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)
	part, err := writer.CreateFormFile("file", filename)
	if err != nil {
		return nil, err
	}
	if _, err := part.Write(content); err != nil {
		return nil, err
	}
	if err := writer.Close(); err != nil {
		return nil, err
	}
	req := httptest.NewRequest(method, url, body)
	req.Header.Set("Content-Type", writer.FormDataContentType())
	return req, nil
}

func TestKYBKYEUploadAndReview(t *testing.T) {
	a, s, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()

	// 1. Create owner and employee
	owner := &models.User{
		ID:          "owner-user",
		Email:       "owner@example.com",
		Password:    "password",
		Role:        models.RoleOwner,
		IsActive:    true,
		IsConfirmed: true,
	}
	s.CreateUser(ctx, owner)

	employee := &models.User{
		ID:          "employee-user",
		Email:       "employee@example.com",
		Password:    "password",
		Role:        models.RoleEmployee,
		IsActive:    true,
		IsConfirmed: true,
		OwnerID:     "owner-user",
	}
	s.CreateUser(ctx, employee)

	ownerToken, _ := jwtutil.GenerateToken(owner.ID, string(owner.Role), owner.ID, owner.Email)
	employeeToken, _ := jwtutil.GenerateToken(employee.ID, string(employee.Role), owner.ID, employee.Email)

	// 2. Test KYB upload authentication
	// Try uploading unsupported format
	req, _ := createMultipartRequest("POST", "/auth/kyb/upload?type=id_front", "test.txt", "text/plain", []byte("hello world"))
	req.Header.Set("Authorization", "Bearer "+ownerToken)
	rec := httptest.NewRecorder()
	a.UploadKYB(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("Expected 400 Bad Request for text file, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// Upload valid PNG for ID front
	pngData := []byte("\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\nIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01\r\n-\xb4\x00\x00\x00\x00IEND\xaeB`\x82")
	req, _ = createMultipartRequest("POST", "/auth/kyb/upload?type=id_front", "id_front.png", "image/png", pngData)
	req.Header.Set("Authorization", "Bearer "+ownerToken)
	rec = httptest.NewRecorder()
	a.UploadKYB(rec, req)
	if rec.Code != http.StatusOK {
		t.Errorf("Expected 200 OK, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// Status should still be KYCNone since not all 4 are uploaded
	u := s.GetByID(ctx, owner.ID)
	if u.KYCStatus != models.KYCNone {
		t.Errorf("Expected KYCStatus to be empty, got %s", u.KYCStatus)
	}

	// Upload ID back, selfie, and business proof (PDF)
	req, _ = createMultipartRequest("POST", "/auth/kyb/upload?type=id_back", "id_back.png", "image/png", pngData)
	req.Header.Set("Authorization", "Bearer "+ownerToken)
	rec = httptest.NewRecorder()
	a.UploadKYB(rec, req)

	req, _ = createMultipartRequest("POST", "/auth/kyb/upload?type=selfie", "selfie.png", "image/png", pngData)
	req.Header.Set("Authorization", "Bearer "+ownerToken)
	rec = httptest.NewRecorder()
	a.UploadKYB(rec, req)

	pdfData := []byte("%PDF-1.4 test pdf content")
	req, _ = createMultipartRequest("POST", "/auth/kyb/upload?type=business_proof", "proof.pdf", "application/pdf", pdfData)
	req.Header.Set("Authorization", "Bearer "+ownerToken)
	rec = httptest.NewRecorder()
	a.UploadKYB(rec, req)
	if rec.Code != http.StatusOK {
		t.Errorf("Expected 200 OK for PDF business proof, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// Now status should be KYCPendingApproval
	u = s.GetByID(ctx, owner.ID)
	if u.KYCStatus != models.KYCPendingApproval {
		t.Errorf("Expected KYCStatus to be pending, got %s", u.KYCStatus)
	}

	// Onboard a test reviewer
	reviewer := &models.Reviewer{
		ID:    "reviewer_test_123",
		Name:  "Test Reviewer",
		Token: "test-reviewer-token-abc",
	}
	if err := s.AddReviewer(ctx, reviewer); err != nil {
		t.Fatalf("failed to add test reviewer: %v", err)
	}

	// 3. Test reviewer pending submissions listing
	// Calling without X-Internal-Token -> 401
	req = httptest.NewRequest("GET", "/auth/kyb-kye/pending", nil)
	rec = httptest.NewRecorder()
	a.GetPendingKYBKYESubmissions(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Errorf("Expected 401 Unauthorized for pending list, got %d", rec.Code)
	}

	// Calling with X-Internal-Token but without X-Reviewer-Token -> 401
	req = httptest.NewRequest("GET", "/auth/kyb-kye/pending", nil)
	req.Header.Set("X-Internal-Token", a.internalServiceToken)
	rec = httptest.NewRecorder()
	a.GetPendingKYBKYESubmissions(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Errorf("Expected 401 Unauthorized for pending list without reviewer token, got %d", rec.Code)
	}

	// Calling with both X-Internal-Token and X-Reviewer-Token -> 200
	req = httptest.NewRequest("GET", "/auth/kyb-kye/pending", nil)
	req.Header.Set("X-Internal-Token", a.internalServiceToken)
	req.Header.Set("X-Reviewer-Token", reviewer.Token)
	rec = httptest.NewRecorder()
	a.GetPendingKYBKYESubmissions(rec, req)
	if rec.Code != http.StatusOK {
		t.Errorf("Expected 200 OK, got %d", rec.Code)
	}

	var pendingList []struct {
		UserID     string `json:"user_id"`
		IDFrontURL string `json:"id_front_url"`
	}
	if err := json.NewDecoder(rec.Body).Decode(&pendingList); err != nil {
		t.Fatalf("Failed to decode pending list: %v", err)
	}
	if len(pendingList) != 1 || pendingList[0].UserID != owner.ID {
		t.Errorf("Expected pending list to contain owner, got: %+v", pendingList)
	}

	// 4. Test document viewing
	docURL := pendingList[0].IDFrontURL
	uToken := docURL[strings.Index(docURL, "?token=")+7:]

	// View without tokens -> 401
	viewReq := httptest.NewRequest("GET", "/auth/documents/view?token="+uToken, nil)
	viewRec := httptest.NewRecorder()
	a.ViewDocument(viewRec, viewReq)
	if viewRec.Code != http.StatusUnauthorized {
		t.Errorf("Expected 401 Unauthorized for document view without tokens, got %d", viewRec.Code)
	}

	// View with valid tokens -> 200
	viewReq = httptest.NewRequest("GET", "/auth/documents/view?token="+uToken, nil)
	viewReq.Header.Set("X-Internal-Token", a.internalServiceToken)
	viewReq.Header.Set("X-Reviewer-Token", reviewer.Token)
	viewRec = httptest.NewRecorder()
	a.ViewDocument(viewRec, viewReq)
	if viewRec.Code != http.StatusOK {
		t.Errorf("Expected 200 OK for document view, got %d", viewRec.Code)
	}

	// View with invalid token -> 403
	viewReq = httptest.NewRequest("GET", "/auth/documents/view?token=invalid", nil)
	viewReq.Header.Set("X-Internal-Token", a.internalServiceToken)
	viewReq.Header.Set("X-Reviewer-Token", reviewer.Token)
	viewRec = httptest.NewRecorder()
	a.ViewDocument(viewRec, viewReq)
	if viewRec.Code != http.StatusForbidden {
		t.Errorf("Expected 403 Forbidden for invalid document view token, got %d", viewRec.Code)
	}

	// 5. Test Reviewing Submissions
	// Rejecting owner without tokens -> 401
	reviewReqBody := map[string]string{
		"user_id": owner.ID,
		"action":  "reject",
		"reason":  "blurry ID photo",
	}
	bReview, _ := json.Marshal(reviewReqBody)
	req = httptest.NewRequest("POST", "/auth/kyb-kye/review", bytes.NewReader(bReview))
	rec = httptest.NewRecorder()
	a.ReviewKYBKYESubmissions(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Errorf("Expected 401 Unauthorized for review, got %d", rec.Code)
	}

	// Rejecting owner with only X-Internal-Token -> 401
	req = httptest.NewRequest("POST", "/auth/kyb-kye/review", bytes.NewReader(bReview))
	req.Header.Set("X-Internal-Token", a.internalServiceToken)
	rec = httptest.NewRecorder()
	a.ReviewKYBKYESubmissions(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Errorf("Expected 401 Unauthorized for review without reviewer token, got %d", rec.Code)
	}

	// Rejecting owner with both X-Internal-Token and X-Reviewer-Token -> 200
	req = httptest.NewRequest("POST", "/auth/kyb-kye/review", bytes.NewReader(bReview))
	req.Header.Set("X-Internal-Token", a.internalServiceToken)
	req.Header.Set("X-Reviewer-Token", reviewer.Token)
	rec = httptest.NewRecorder()
	a.ReviewKYBKYESubmissions(rec, req)
	if rec.Code != http.StatusOK {
		t.Errorf("Expected 200 OK for review action, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// Verify status is KYCRejected in DB and reviewer_id is recorded
	u = s.GetByID(ctx, owner.ID)
	if u.KYCStatus != models.KYCRejected || u.RejectionReason != "blurry ID photo" {
		t.Errorf("Expected KYCStatus to be rejected with reason, got status: %s, reason: %s", u.KYCStatus, u.RejectionReason)
	}
	if u.ReviewerID != reviewer.ID {
		t.Errorf("Expected ReviewerID to be %s, got %s", reviewer.ID, u.ReviewerID)
	}

	// Check that owner can view their own rejection status and reason via GetUser
	req = httptest.NewRequest("GET", "/auth/user?id="+ownerToken, nil)
	rec = httptest.NewRecorder()
	a.GetUser(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK for GetUser, got %d", rec.Code)
	}
	var userDetails map[string]any
	json.NewDecoder(rec.Body).Decode(&userDetails)
	if userDetails["kyc_status"] != string(models.KYCRejected) || userDetails["rejection_reason"] != "blurry ID photo" {
		t.Errorf("Owner GetUser response missing rejection details: %+v", userDetails)
	}

	// Move owner back to pending by uploading id_front again
	req, _ = createMultipartRequest("POST", "/auth/kyb/upload?type=id_front", "id_front.png", "image/png", pngData)
	req.Header.Set("Authorization", "Bearer "+ownerToken)
	rec = httptest.NewRecorder()
	a.UploadKYB(rec, req)

	// Approve owner
	reviewReqBody["action"] = "approve"
	reviewReqBody["reason"] = ""
	bReviewApproved, _ := json.Marshal(reviewReqBody)
	req = httptest.NewRequest("POST", "/auth/kyb-kye/review", bytes.NewReader(bReviewApproved))
	req.Header.Set("X-Internal-Token", a.internalServiceToken)
	req.Header.Set("X-Reviewer-Token", reviewer.Token)
	rec = httptest.NewRecorder()
	a.ReviewKYBKYESubmissions(rec, req)
	if rec.Code != http.StatusOK {
		t.Errorf("Expected 200 OK for approve, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	u = s.GetByID(ctx, owner.ID)
	if u.KYCStatus != models.KYCApproved {
		t.Errorf("Expected KYCStatus to be approved, got %s", u.KYCStatus)
	}
	if u.ReviewerID != reviewer.ID {
		t.Errorf("Expected ReviewerID to be %s, got %s", reviewer.ID, u.ReviewerID)
	}

	// 6. Test Employee KYE Flow
	// Upload 3 docs for employee
	req, _ = createMultipartRequest("POST", "/auth/kye/upload?type=id_front", "id_front.png", "image/png", pngData)
	req.Header.Set("Authorization", "Bearer "+employeeToken)
	rec = httptest.NewRecorder()
	a.UploadKYE(rec, req)

	req, _ = createMultipartRequest("POST", "/auth/kye/upload?type=id_back", "id_back.png", "image/png", pngData)
	req.Header.Set("Authorization", "Bearer "+employeeToken)
	rec = httptest.NewRecorder()
	a.UploadKYE(rec, req)

	req, _ = createMultipartRequest("POST", "/auth/kye/upload?type=selfie", "selfie.png", "image/png", pngData)
	req.Header.Set("Authorization", "Bearer "+employeeToken)
	rec = httptest.NewRecorder()
	a.UploadKYE(rec, req)

	// Employee status should now be pending
	emp := s.GetByID(ctx, employee.ID)
	if emp.KYEStatus != models.KYCPendingApproval {
		t.Errorf("Expected KYEStatus to be pending, got %s", emp.KYEStatus)
	}

	// Approve employee
	employeeReviewBody := map[string]string{
		"user_id": employee.ID,
		"action":  "approve",
	}
	bEmpReview, _ := json.Marshal(employeeReviewBody)
	req = httptest.NewRequest("POST", "/auth/kyb-kye/review", bytes.NewReader(bEmpReview))
	req.Header.Set("X-Internal-Token", a.internalServiceToken)
	req.Header.Set("X-Reviewer-Token", reviewer.Token)
	rec = httptest.NewRecorder()
	a.ReviewKYBKYESubmissions(rec, req)
	if rec.Code != http.StatusOK {
		t.Errorf("Expected 200 OK for employee approve, got %d", rec.Code)
	}

	emp = s.GetByID(ctx, employee.ID)
	if emp.KYEStatus != models.KYCApproved {
		t.Errorf("Expected KYEStatus to be approved, got %s", emp.KYEStatus)
	}
	if emp.ReviewerID != reviewer.ID {
		t.Errorf("Expected ReviewerID to be %s, got %s", reviewer.ID, emp.ReviewerID)
	}
}
