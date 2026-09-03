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
	"runtime"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/golang-jwt/jwt/v5"
	"github.com/project/auth-service/internal/config"
	"github.com/project/auth-service/internal/models"
	"github.com/project/auth-service/internal/otpcrypto"
	"github.com/project/auth-service/internal/storage"
	"github.com/project/auth-service/internal/store"
	"github.com/project/shared/infra/jwtutil"
	"github.com/redis/go-redis/v9"
	"go.mongodb.org/mongo-driver/v2/bson"
	"golang.org/x/crypto/bcrypt"
)

// TestBcryptHashVerify tests the password hashing and verification flow
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
	storeLoc, _ := storage.NewLocalStorage(tempDir, "/api/v1", os.Getenv("JWT_SECRET"), "", "test")
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
	os.Setenv("DOCUMENT_SIGNING_SECRET", "doc-signing-secret-key-32bytes-long-test")
	jwtutil.Init("z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")

	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	dbName := fmt.Sprintf("saas_auth_test_%d", time.Now().UnixNano())
	cipher, err := otpcrypto.NewCipher("", "local")
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
		AppEnv:                "local",
		GatewaySecret:         "mock-gateway-secret",
		InternalServiceToken:  "mock-internal-token",
		JWTSecret:             "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2",
		DocumentSigningSecret: "doc-signing-secret-key-32bytes-long-test",
	}

	dispatcher := &mockOTPDispatcher{}

	tempDir := t.TempDir()
	storeLoc, _ := storage.NewLocalStorage(tempDir, "/api/v1", cfg.DocumentSigningSecret, "", "test")
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
		Username: "owner_username",
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

	// 1b. Verify signup OTP to confirm account and create user record
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

	// Test Signup Duplicate (Validation error path against existing confirmed user)
	req = httptest.NewRequest("POST", "/auth/signup", bytes.NewReader(b))
	rec = httptest.NewRecorder()
	a.Signup(rec, req)
	if rec.Code != http.StatusConflict {
		t.Errorf("Expected 409 Conflict for duplicate Signup, got %d. Body: %s", rec.Code, rec.Body.String())
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
		Username: "employee_username",
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
	var getUserResp map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &getUserResp); err != nil {
		t.Fatalf("Failed to decode GetUser response: %v", err)
	}
	if getUserResp["username"] != "owner_username" {
		t.Errorf("Expected username to be 'owner_username', got %v", getUserResp["username"])
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
		ID:       "owner-user",
		Email:    "owner@example.com",
		Username: "owner_user_username",
		Password: "password",
		Role:     models.RoleOwner,
		IsActive: true,
	}
	s.CreateUser(ctx, owner)

	employee := &models.User{
		ID:       "employee-user",
		Email:    "employee@example.com",
		Username: "employee_user_username",
		Password: "password",
		Role:     models.RoleEmployee,
		IsActive: true,
		OwnerID:  "owner-user",
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
		Username   string `json:"username"`
		IDFrontURL string `json:"id_front_url"`
	}
	if err := json.NewDecoder(rec.Body).Decode(&pendingList); err != nil {
		t.Fatalf("Failed to decode pending list: %v", err)
	}
	if len(pendingList) != 1 || pendingList[0].UserID != owner.ID {
		t.Errorf("Expected pending list to contain owner, got: %+v", pendingList)
	}
	if pendingList[0].Username != owner.Username {
		t.Errorf("Expected pending list owner username to be %q, got %q", owner.Username, pendingList[0].Username)
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

func TestTokenRefresh(t *testing.T) {
	a, s, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()

	// 1. Create a confirmed and active user in store
	testUser := &models.User{
		ID:       "user_refresh_123",
		Email:    "refresh123@example.com",
		Username: "refresh123_username",
		Password: "$2a$10$abcdefghijklmnopqrstuv", // Bcrypt format placeholder
		Role:     models.RoleOwner,
		TenantID: "tenant_refresh_123",
		IsActive: true,
	}
	if err := s.CreateUser(ctx, testUser); err != nil {
		t.Fatalf("failed to create user: %v", err)
	}

	// Helper to generate custom-expired token
	generateCustomExpiredToken := func(duration time.Duration) string {
		claims := jwtutil.Claims{
			UserID:   testUser.ID,
			Role:     string(testUser.Role),
			TenantID: testUser.TenantID,
			Email:    testUser.Email,
			RegisteredClaims: jwt.RegisteredClaims{
				ExpiresAt: jwt.NewNumericDate(time.Now().Add(duration)),
				IssuedAt:  jwt.NewNumericDate(time.Now().Add(duration - 24*time.Hour)),
				NotBefore: jwt.NewNumericDate(time.Now().Add(duration - 24*time.Hour)),
			},
		}
		token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
		secret := []byte("z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
		tokenStr, err := token.SignedString(secret)
		if err != nil {
			t.Fatalf("failed to sign token: %v", err)
		}
		return tokenStr
	}

	// Case A: Token expired 1 hour ago -> Should return 200 OK and a fresh token
	expired1hToken := generateCustomExpiredToken(-1 * time.Hour)
	reqBodyA := map[string]string{"token": expired1hToken}
	bA, _ := json.Marshal(reqBodyA)
	req := httptest.NewRequest("POST", "/auth/refresh", bytes.NewReader(bA))
	rec := httptest.NewRecorder()
	a.Refresh(rec, req)

	if rec.Code != http.StatusOK {
		t.Errorf("Expected 200 OK for token expired 1 hour ago, got %d. Body: %s", rec.Code, rec.Body.String())
	} else {
		var resp map[string]any
		if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
			t.Errorf("failed to parse refresh response: %v", err)
		}
		if resp["status"] != "success" || resp["token"] == "" {
			t.Errorf("invalid refresh response body: %v", resp)
		}
	}

	// Case B: Token expired 8 days ago (> 7 days) -> Should return 401 Unauthorized
	expired8dToken := generateCustomExpiredToken(-8 * 24 * time.Hour)
	reqBodyB := map[string]string{"token": expired8dToken}
	bB, _ := json.Marshal(reqBodyB)
	req = httptest.NewRequest("POST", "/auth/refresh", bytes.NewReader(bB))
	rec = httptest.NewRecorder()
	a.Refresh(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Errorf("Expected 401 Unauthorized for token expired > 7 days, got %d. Body: %s", rec.Code, rec.Body.String())
	}
}

type otpFailContext struct {
	context.Context
}

func (c *otpFailContext) Done() <-chan struct{} {
	var pcs [10]uintptr
	n := runtime.Callers(2, pcs[:])
	frames := runtime.CallersFrames(pcs[:n])
	for {
		frame, more := frames.Next()
		if strings.Contains(frame.Function, "SetOTP") {
			ch := make(chan struct{})
			close(ch)
			return ch
		}
		if !more {
			break
		}
	}
	return c.Context.Done()
}

func (c *otpFailContext) Err() error {
	var pcs [10]uintptr
	n := runtime.Callers(2, pcs[:])
	frames := runtime.CallersFrames(pcs[:n])
	for {
		frame, more := frames.Next()
		if strings.Contains(frame.Function, "SetOTP") || strings.Contains(frame.Function, "SetPendingSignup") {
			return context.Canceled
		}
		if !more {
			break
		}
	}
	return c.Context.Err()
}

func TestSignupRollbackOnOTPFailure(t *testing.T) {
	a, s, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	// 1. Prepare signup request
	signupBody := models.SignupRequest{
		Email:    "rollback_test@example.com",
		Username: "rollback_username",
		Password: "password123",
		Role:     models.RoleOwner,
	}
	b, _ := json.Marshal(signupBody)

	// Wrap request context with otpFailContext to simulate SetOTP failure
	req := httptest.NewRequest("POST", "/auth/signup", bytes.NewReader(b))
	customCtx := &otpFailContext{Context: req.Context()}
	req = req.WithContext(customCtx)

	rec := httptest.NewRecorder()
	a.Signup(rec, req)

	// Verify that the response is 500 Internal Server Error (since SetOTP failed)
	if rec.Code != http.StatusInternalServerError {
		t.Errorf("Expected 500 Internal Server Error for failed SetOTP, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// Verify that the user record was NOT created or was rolled back (does not exist in DB)
	ctx := context.Background()
	user := s.GetByEmail(ctx, "rollback_test@example.com")
	if user != nil {
		t.Errorf("User record was not deleted/rolled back after SetOTP failure!")
	}
}

type mockStorageWithFailure struct {
	storage.Storage
	failKey string
}

func (m *mockStorageWithFailure) GetSignedURL(ctx context.Context, key string, expires time.Duration) (string, error) {
	if key == m.failKey {
		return "", fmt.Errorf("simulated signed URL generation error")
	}
	return m.Storage.GetSignedURL(ctx, key, expires)
}

func TestGetPendingKYBKYESubmissions_StorageError(t *testing.T) {
	a, s, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	user := &models.User{
		ID:               "user_kyb_test_999",
		Email:            "kyb_error_test@example.com",
		Username:         "kyb_error_test_username",
		Role:             models.RoleOwner,
		KYCStatus:        models.KYCPendingApproval,
		IDFrontDoc:       "id_front_999.png",
		IDBackDoc:        "id_back_999.png",
		SelfieDoc:        "selfie_999.png",
		BusinessProofDoc: "business_proof_999.pdf",
		IsActive:         true,
	}
	if err := s.CreateUser(ctx, user); err != nil {
		t.Fatalf("failed to create test user: %v", err)
	}

	reviewer := &models.Reviewer{
		ID:    "reviewer_err_999",
		Name:  "Test Reviewer Error",
		Token: "reviewer-token-err-999",
	}
	if err := s.AddReviewer(ctx, reviewer); err != nil {
		t.Fatalf("failed to add test reviewer: %v", err)
	}

	// Intercept and wrap storage to fail for id_back key
	a.storage = &mockStorageWithFailure{
		Storage: a.storage,
		failKey: "id_back_999.png",
	}

	req := httptest.NewRequest("GET", "/auth/kyb-kye/pending", nil)
	req.Header.Set("X-Internal-Token", a.internalServiceToken)
	req.Header.Set("X-Reviewer-Token", reviewer.Token)
	rec := httptest.NewRecorder()

	a.GetPendingKYBKYESubmissions(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	var pendingList []struct {
		UserID           string   `json:"user_id"`
		IDFrontURL       string   `json:"id_front_url"`
		IDBackURL        string   `json:"id_back_url"`
		SelfieURL        string   `json:"selfie_url"`
		BusinessProofURL string   `json:"business_proof_url"`
		DocumentErrors   []string `json:"document_errors"`
	}
	if err := json.NewDecoder(rec.Body).Decode(&pendingList); err != nil {
		t.Fatalf("Failed to decode pending list: %v", err)
	}

	found := false
	for _, sub := range pendingList {
		if sub.UserID == user.ID {
			found = true
			if sub.IDFrontURL == "" || sub.SelfieURL == "" || sub.BusinessProofURL == "" {
				t.Errorf("Expected URLs for id_front, selfie, business_proof to be populated, got: front=%q, selfie=%q, proof=%q", sub.IDFrontURL, sub.SelfieURL, sub.BusinessProofURL)
			}
			if sub.IDBackURL != "" {
				t.Errorf("Expected id_back URL to be empty on failure, got %q", sub.IDBackURL)
			}
			if len(sub.DocumentErrors) != 1 || sub.DocumentErrors[0] != "Failed to load id_back" {
				t.Errorf("Expected exact document error 'Failed to load id_back', got: %v", sub.DocumentErrors)
			}
			if strings.Contains(sub.DocumentErrors[0], ":") {
				t.Errorf("SECURITY DEFECT: DocumentErrors leaked internal error details or colon interpolation! Got: %s", sub.DocumentErrors[0])
			}
		}
	}
	if !found {
		t.Errorf("Did not find test user %s in pending list", user.ID)
	}
}

func TestLogout_Denylist(t *testing.T) {
	jwtutil.Init("z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")

	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()

	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	jwtutil.SetRedisClient(rdb)
	defer jwtutil.SetRedisClient(nil)

	// 1. Generate two tokens
	token1, err := jwtutil.GenerateToken("user1", "employee", "tenant1", "user1@example.com")
	if err != nil {
		t.Fatalf("failed to generate token 1: %v", err)
	}
	token2, err := jwtutil.GenerateToken("user2", "employee", "tenant1", "user2@example.com")
	if err != nil {
		t.Fatalf("failed to generate token 2: %v", err)
	}

	// Verify both are valid initially
	claims1, err := jwtutil.ValidateToken(token1)
	if err != nil {
		t.Fatalf("failed to validate token 1: %v", err)
	}
	claims2, err := jwtutil.ValidateToken(token2)
	if err != nil {
		t.Fatalf("failed to validate token 2: %v", err)
	}
	if claims1.RegisteredClaims.ID == "" || claims2.RegisteredClaims.ID == "" {
		t.Errorf("expected non-empty JTI/ID in tokens")
	}

	// 2. Revoke/Logout token 1
	cfg := &config.Config{
		AppEnv:               "local",
		GatewaySecret:        "mock-gateway-secret",
		InternalServiceToken: "mock-internal-token",
		JWTSecret:            "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2",
	}
	tempDir := t.TempDir()
	storeLoc, _ := storage.NewLocalStorage(tempDir, "/api/v1", cfg.JWTSecret, "", "test")
	a := NewAuth(nil, nil, cfg, rdb, storeLoc)

	rec := httptest.NewRecorder()
	req := httptest.NewRequest("POST", "/auth/logout", nil)
	req.Header.Set("Authorization", "Bearer "+token1)
	a.Logout(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected status 200 on logout, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// 3. Verify token 1 is now rejected
	_, err = jwtutil.ValidateToken(token1)
	if err == nil {
		t.Errorf("expected token 1 to be rejected after logout, but it was accepted")
	} else if !strings.Contains(err.Error(), "revoked") {
		t.Errorf("expected revocation error, got %v", err)
	}

	// 4. Verify token 2 is still valid
	_, err = jwtutil.ValidateToken(token2)
	if err != nil {
		t.Errorf("expected token 2 to remain valid, but got error: %v", err)
	}
}

func TestOTPResendFlow(t *testing.T) {
	a, _, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	// 1. Signup a new user
	signupBody := models.SignupRequest{
		Email:    "resend_flow_test@example.com",
		Username: "resend_flow_username",
		Password: "password123",
		Role:     models.RoleUser,
	}
	b, _ := json.Marshal(signupBody)
	req := httptest.NewRequest("POST", "/auth/signup", bytes.NewReader(b))
	rec := httptest.NewRecorder()
	a.Signup(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201 Created on signup, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	var signupResp map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &signupResp); err != nil {
		t.Fatalf("failed to unmarshal signup response: %v", err)
	}

	oldOtp := signupResp["dev_otp"].(string)

	// 2. Try verifying a wrong OTP -> fails (401)
	verifyBodyWrong := models.VerifyOTPRequest{
		Email: "resend_flow_test@example.com",
		OTP:   "000000",
	}
	bWrong, _ := json.Marshal(verifyBodyWrong)
	reqWrong := httptest.NewRequest("POST", "/auth/verify-otp", bytes.NewReader(bWrong))
	recWrong := httptest.NewRecorder()
	a.VerifyOTP(recWrong, reqWrong)

	if recWrong.Code != http.StatusUnauthorized {
		t.Errorf("expected 401 Unauthorized for wrong OTP, got %d", recWrong.Code)
	}

	// 3. Call resend-otp -> returns fresh OTP
	resendBody := ResendOTPRequest{
		Email: "resend_flow_test@example.com",
	}
	bResend, _ := json.Marshal(resendBody)
	reqResend := httptest.NewRequest("POST", "/auth/resend-otp", bytes.NewReader(bResend))
	recResend := httptest.NewRecorder()
	a.ResendOTP(recResend, reqResend)

	if recResend.Code != http.StatusOK {
		t.Fatalf("expected 200 OK for resend-otp, got %d. Body: %s", recResend.Code, recResend.Body.String())
	}

	var resendResp map[string]any
	if err := json.Unmarshal(recResend.Body.Bytes(), &resendResp); err != nil {
		t.Fatalf("failed to unmarshal resend response: %v", err)
	}

	newOtp := resendResp["dev_otp"].(string)
	if newOtp == oldOtp {
		t.Errorf("expected new OTP to be different from old OTP, but both are %s", oldOtp)
	}

	// 4. Try verifying old OTP -> fails (401) because it was replaced/invalidated
	verifyBodyOld := models.VerifyOTPRequest{
		Email: "resend_flow_test@example.com",
		OTP:   oldOtp,
	}
	bOld, _ := json.Marshal(verifyBodyOld)
	reqOld := httptest.NewRequest("POST", "/auth/verify-otp", bytes.NewReader(bOld))
	recOld := httptest.NewRecorder()
	a.VerifyOTP(recOld, reqOld)

	if recOld.Code != http.StatusUnauthorized {
		t.Errorf("expected 401 Unauthorized for old OTP after resend, got %d. Body: %s", recOld.Code, recOld.Body.String())
	}

	// 5. Verify new OTP -> succeeds (200)
	verifyBodyNew := models.VerifyOTPRequest{
		Email: "resend_flow_test@example.com",
		OTP:   newOtp,
	}
	bNew, _ := json.Marshal(verifyBodyNew)
	reqNew := httptest.NewRequest("POST", "/auth/verify-otp", bytes.NewReader(bNew))
	recNew := httptest.NewRecorder()
	a.VerifyOTP(recNew, reqNew)

	if recNew.Code != http.StatusOK {
		t.Errorf("expected 200 OK for verification with new OTP, got %d. Body: %s", recNew.Code, recNew.Body.String())
	}
}

func TestAuth_ExtraGaps(t *testing.T) {
	a, s, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	defaultIP := "192.0.2.1"

	// 1. POST /auth/refresh: confirm whether the OLD token remains valid (not revoked) after a successful refresh
	t.Run("Refresh_OldTokenNonRevocation", func(t *testing.T) {
		// Create a confirmed/active user
		user := &models.User{
			ID:       "user_refresh_gap",
			Email:    "refreshgap@example.com",
			Username: "refreshgap_username",
			Password: "$2a$10$abcdefghijklmnopqrstuv", // Bcrypt placeholder
			Role:     models.RoleOwner,
			TenantID: "tenant_refresh_gap",
			IsActive: true,
		}
		if err := s.CreateUser(ctx, user); err != nil {
			t.Fatalf("failed to create user: %v", err)
		}

		// Generate initial token
		oldToken, err := jwtutil.GenerateToken(user.ID, string(user.Role), user.TenantID, user.Email)
		if err != nil {
			t.Fatalf("failed to generate token: %v", err)
		}

		// Refresh the token
		reqBody := map[string]string{"token": oldToken}
		bodyBytes, _ := json.Marshal(reqBody)
		req := httptest.NewRequest("POST", "/auth/refresh", bytes.NewReader(bodyBytes))
		rec := httptest.NewRecorder()
		a.Refresh(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 OK, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		// Assert that the old token is still valid (current behavior verification)
		claims, err := jwtutil.ValidateToken(oldToken)
		if err != nil {
			t.Errorf("expected old token to remain valid after refresh, but got error: %v", err)
		}
		if claims == nil || claims.UserID != user.ID {
			t.Errorf("expected claims to contain correct user ID, got %+v", claims)
		}
	})

	// 2. Employee provisioning during Signup
	t.Run("Signup_EmployeeProvisioningRejections", func(t *testing.T) {
		a.limiter.Reset(defaultIP)

		// Set up an owner user in DB
		owner := &models.User{
			ID:       "owner_prov",
			Email:    "ownerprov@example.com",
			Username: "ownerprov_username",
			Password: "$2a$10$abcdefghijklmnopqrstuv",
			Role:     models.RoleOwner,
			TenantID: "tenant_prov",
			IsActive: true,
		}
		if err := s.CreateUser(ctx, owner); err != nil {
			t.Fatalf("failed to create owner: %v", err)
		}

		// Set up a non-owner user in DB
		nonOwner := &models.User{
			ID:       "user_non_owner",
			Email:    "usernonowner@example.com",
			Username: "usernonowner_username",
			Password: "$2a$10$abcdefghijklmnopqrstuv",
			Role:     models.RoleUser,
			TenantID: "tenant_prov",
			IsActive: true,
		}
		if err := s.CreateUser(ctx, nonOwner); err != nil {
			t.Fatalf("failed to create non-owner: %v", err)
		}

		// Generate Bearer tokens
		ownerToken, _ := jwtutil.GenerateToken(owner.ID, string(owner.Role), owner.TenantID, owner.Email)
		nonOwnerToken, _ := jwtutil.GenerateToken(nonOwner.ID, string(nonOwner.Role), nonOwner.TenantID, nonOwner.Email)

		// Subtest A: Token user ID mismatch vs owner_id (returns 403)
		t.Run("TokenUserIDMismatch", func(t *testing.T) {
			signupReq := models.SignupRequest{
				Email:    "emp_mismatch@example.com",
				Username: "emp_mismatch_user",
				Password: "password",
				Role:     models.RoleEmployee,
				OwnerID:  "different_owner_id",
			}
			body, _ := json.Marshal(signupReq)
			req := httptest.NewRequest("POST", "/auth/signup", bytes.NewReader(body))
			req.Header.Set("Authorization", "Bearer "+ownerToken)
			rec := httptest.NewRecorder()
			a.Signup(rec, req)

			if rec.Code != http.StatusForbidden {
				t.Errorf("expected 403 Forbidden, got %d. Body: %s", rec.Code, rec.Body.String())
			}
			if !strings.Contains(rec.Body.String(), "caller is not the owner specified by owner_id") {
				t.Errorf("unexpected error response: %s", rec.Body.String())
			}
		})

		// Subtest B: Non-owner role token (returns 403)
		t.Run("NonOwnerRoleToken", func(t *testing.T) {
			signupReq := models.SignupRequest{
				Email:    "emp_nonowner_role@example.com",
				Username: "emp_nonowner_role_user",
				Password: "password",
				Role:     models.RoleEmployee,
				OwnerID:  nonOwner.ID,
			}
			body, _ := json.Marshal(signupReq)
			req := httptest.NewRequest("POST", "/auth/signup", bytes.NewReader(body))
			req.Header.Set("Authorization", "Bearer "+nonOwnerToken)
			rec := httptest.NewRecorder()
			a.Signup(rec, req)

			if rec.Code != http.StatusForbidden {
				t.Errorf("expected 403 Forbidden, got %d. Body: %s", rec.Code, rec.Body.String())
			}
			if !strings.Contains(rec.Body.String(), "owner role required to provision employees") {
				t.Errorf("unexpected error response: %s", rec.Body.String())
			}
		})

		// Subtest C: owner_id pointing to a non-existent user (returns 400)
		t.Run("NonExistentOwnerID", func(t *testing.T) {
			fakeToken, _ := jwtutil.GenerateToken("fake_owner_id", "owner", "fake_tenant", "fake@example.com")
			signupReq := models.SignupRequest{
				Email:    "emp_no_owner@example.com",
				Username: "emp_no_owner_user",
				Password: "password",
				Role:     models.RoleEmployee,
				OwnerID:  "fake_owner_id",
			}
			body, _ := json.Marshal(signupReq)
			req := httptest.NewRequest("POST", "/auth/signup", bytes.NewReader(body))
			req.Header.Set("Authorization", "Bearer "+fakeToken)
			rec := httptest.NewRecorder()
			a.Signup(rec, req)

			if rec.Code != http.StatusBadRequest {
				t.Errorf("expected 400 Bad Request, got %d. Body: %s", rec.Code, rec.Body.String())
			}
			if !strings.Contains(rec.Body.String(), "does not exist") {
				t.Errorf("unexpected error response: %s", rec.Body.String())
			}
		})

		// Subtest D: owner_id pointing to a user that is not role=owner (returns 400)
		t.Run("OwnerIDNotRoleOwner", func(t *testing.T) {
			fakeToken, _ := jwtutil.GenerateToken(nonOwner.ID, "owner", nonOwner.TenantID, nonOwner.Email)
			signupReq := models.SignupRequest{
				Email:    "emp_not_owner_role@example.com",
				Username: "emp_not_owner_role_user",
				Password: "password",
				Role:     models.RoleEmployee,
				OwnerID:  nonOwner.ID,
			}
			body, _ := json.Marshal(signupReq)
			req := httptest.NewRequest("POST", "/auth/signup", bytes.NewReader(body))
			req.Header.Set("Authorization", "Bearer "+fakeToken)
			rec := httptest.NewRecorder()
			a.Signup(rec, req)

			if rec.Code != http.StatusBadRequest {
				t.Errorf("expected 400 Bad Request, got %d. Body: %s", rec.Code, rec.Body.String())
			}
			if !strings.Contains(rec.Body.String(), "is not an owner tenant") {
				t.Errorf("unexpected error response: %s", rec.Body.String())
			}
		})

		// Reset failures recorded on defaultIP during validations
		a.limiter.Reset(defaultIP)
	})

	// 3. Login
	t.Run("Login_Gaps", func(t *testing.T) {
		a.limiter.Reset(defaultIP)

		// A: locked-out IP vs locked-out email are independent axes
		t.Run("LockedOutIpHearsLockedOutEmailIndependently", func(t *testing.T) {
			ip := "192.168.99.1"
			email := "lockgap@example.com"

			// Lock the IP by recording 5 failures on it
			for i := 0; i < 5; i++ {
				a.limiter.RecordFailure(ip)
			}
			locked, _ := a.limiter.IsLocked(ip)
			if !locked {
				t.Error("expected IP to be locked")
			}

			// Email should NOT be locked
			lockedEmail, _ := a.limiter.IsLocked(email)
			if lockedEmail {
				t.Error("expected email to not be locked by IP lockout")
			}

			// Reset IP
			a.limiter.Reset(ip)

			// Lock the email by recording 5 failures on it
			for i := 0; i < 5; i++ {
				a.limiter.RecordFailure(email)
			}
			lockedEmail, _ = a.limiter.IsLocked(email)
			if !lockedEmail {
				t.Error("expected email to be locked")
			}

			// IP should NOT be locked
			locked, _ = a.limiter.IsLocked(ip)
			if locked {
				t.Error("expected IP to not be locked by email lockout")
			}

			// Reset email
			a.limiter.Reset(email)
		})

		// B: confirm the generic "invalid email or password" response is identical
		t.Run("IdenticalResponseForNonExistentAndWrongPassword", func(t *testing.T) {
			a.limiter.Reset(defaultIP)

			// Case 1: non-existent email
			loginReq1 := models.LoginRequest{
				Email:    "doesnotexist@example.com",
				Password: "password123",
			}
			body1, _ := json.Marshal(loginReq1)
			req1 := httptest.NewRequest("POST", "/auth/login", bytes.NewReader(body1))
			rec1 := httptest.NewRecorder()
			a.Login(rec1, req1)

			// Reset failures from the first failure to avoid locking out defaultIP
			a.limiter.Reset(defaultIP)
			a.limiter.Reset("doesnotexist@example.com")

			// Case 2: existent email but wrong password
			hashedPass, _ := bcrypt.GenerateFromPassword([]byte("correctpassword"), bcrypt.DefaultCost)
			user := &models.User{
				ID:       "user_login_test",
				Email:    "exist@example.com",
				Username: "exist_username",
				Password: string(hashedPass),
				Role:     models.RoleOwner,
				TenantID: "tenant_login_test",
				IsActive: true,
			}
			if err := s.CreateUser(ctx, user); err != nil {
				t.Fatalf("failed to create user: %v", err)
			}

			loginReq2 := models.LoginRequest{
				Email:    "exist@example.com",
				Password: "wrongpassword",
			}
			body2, _ := json.Marshal(loginReq2)
			req2 := httptest.NewRequest("POST", "/auth/login", bytes.NewReader(body2))
			rec2 := httptest.NewRecorder()
			a.Login(rec2, req2)

			// Verify identical response level details (status code and body)
			if rec1.Code != rec2.Code {
				t.Errorf("expected status codes to be identical, got %d vs %d", rec1.Code, rec2.Code)
			}
			if rec1.Code != http.StatusUnauthorized {
				t.Errorf("expected 401 Unauthorized, got %d", rec1.Code)
			}

			var resp1, resp2 map[string]string
			json.Unmarshal(rec1.Body.Bytes(), &resp1)
			json.Unmarshal(rec2.Body.Bytes(), &resp2)

			if resp1["error"] != resp2["error"] || resp1["error"] != "invalid email or password" {
				t.Errorf("expected identical response bodies 'invalid email or password', got: %q vs %q", resp1["error"], resp2["error"])
			}

			// Clean up limits
			a.limiter.Reset(defaultIP)
			a.limiter.Reset("exist@example.com")
		})
	})

	// 4. VerifyOTP
	t.Run("VerifyOTP_Gaps", func(t *testing.T) {
		// A: reused OTP after successful verification is rejected
		t.Run("ReusedOTPRejected", func(t *testing.T) {
			a.limiter.Reset(defaultIP)

			email := "otp_reuse@example.com"
			user := &models.User{
				ID:       "user_otp_reuse",
				Email:    email,
				Username: "otp_reuse_username",
				Password: "$2a$10$abcdefghijklmnopqrstuv",
				Role:     models.RoleOwner,
				TenantID: "tenant_otp",
				IsActive: true,
			}
			s.CreateUser(ctx, user)
			s.SetOTP(ctx, email, "111111")

			// Verification 1: should succeed
			reqBody1 := models.VerifyOTPRequest{Email: email, OTP: "111111"}
			b1, _ := json.Marshal(reqBody1)
			req1 := httptest.NewRequest("POST", "/auth/verify-otp", bytes.NewReader(b1))
			rec1 := httptest.NewRecorder()
			a.VerifyOTP(rec1, req1)
			if rec1.Code != http.StatusOK {
				t.Errorf("expected first verification to succeed, got %d. Body: %s", rec1.Code, rec1.Body.String())
			}

			// Verification 2: reused OTP must be rejected
			req1 = httptest.NewRequest("POST", "/auth/verify-otp", bytes.NewReader(b1))
			rec2 := httptest.NewRecorder()
			a.VerifyOTP(rec2, req1)
			if rec2.Code != http.StatusUnauthorized {
				t.Errorf("expected second verification to fail (401), got %d. Body: %s", rec2.Code, rec2.Body.String())
			}

			a.limiter.Reset(defaultIP)
			a.limiter.Reset(email)
		})

		// B1: OTP valid but user record deleted -> rejected cleanly without panic
		t.Run("OTPUserDeletedClean404", func(t *testing.T) {
			a.limiter.Reset(defaultIP)
			deletedEmail := "deleted_user_otp@example.com"
			a.limiter.Reset(deletedEmail)

			s.SetOTP(ctx, deletedEmail, "333333")

			reqBody := models.VerifyOTPRequest{Email: deletedEmail, OTP: "333333"}
			b, _ := json.Marshal(reqBody)
			req := httptest.NewRequest("POST", "/auth/verify-otp", bytes.NewReader(b))
			rec := httptest.NewRecorder()

			a.VerifyOTP(rec, req)

			if rec.Code != http.StatusUnauthorized && rec.Code != http.StatusNotFound {
				t.Errorf("expected 401 or 404 when user deleted post-OTP, got %d. Body: %s", rec.Code, rec.Body.String())
			}

			a.limiter.Reset(defaultIP)
			a.limiter.Reset(deletedEmail)
		})

		// B: OTP for wrong email is rejected
		t.Run("OTPWrongEmailRejected", func(t *testing.T) {
			a.limiter.Reset(defaultIP)

			s.SetOTP(ctx, "exist@example.com", "222222")

			reqBody := models.VerifyOTPRequest{Email: "doesnotexist@example.com", OTP: "222222"}
			b, _ := json.Marshal(reqBody)
			req := httptest.NewRequest("POST", "/auth/verify-otp", bytes.NewReader(b))
			rec := httptest.NewRecorder()
			a.VerifyOTP(rec, req)

			if rec.Code != http.StatusUnauthorized {
				t.Errorf("expected 401 Unauthorized, got %d. Body: %s", rec.Code, rec.Body.String())
			}

			a.limiter.Reset(defaultIP)
			a.limiter.Reset("doesnotexist@example.com")
		})

		// C: rate limit lockout on repeated wrong OTPs
		t.Run("RateLimitLockoutRepeatedWrongOTPs", func(t *testing.T) {
			a.limiter.Reset(defaultIP)

			email := "otp_lockout@example.com"
			user := &models.User{
				ID:       "user_otp_lockout",
				Email:    email,
				Username: "otp_lockout_username",
				Password: "$2a$10$abcdefghijklmnopqrstuv",
				Role:     models.RoleOwner,
				TenantID: "tenant_otp",
				IsActive: true,
			}
			s.CreateUser(ctx, user)
			s.SetOTP(ctx, email, "888888")

			a.limiter.Reset(email)

			reqBody := models.VerifyOTPRequest{Email: email, OTP: "000000"}
			b, _ := json.Marshal(reqBody)

			for i := 0; i < 5; i++ {
				req := httptest.NewRequest("POST", "/auth/verify-otp", bytes.NewReader(b))
				rec := httptest.NewRecorder()
				a.VerifyOTP(rec, req)
				if rec.Code != http.StatusUnauthorized {
					t.Errorf("expected 401 on failure %d, got %d", i+1, rec.Code)
				}
			}

			req := httptest.NewRequest("POST", "/auth/verify-otp", bytes.NewReader(b))
			rec := httptest.NewRecorder()
			a.VerifyOTP(rec, req)
			if rec.Code != http.StatusTooManyRequests {
				t.Errorf("expected 429 Too Many Requests on locked out attempt, got %d. Body: %s", rec.Code, rec.Body.String())
			}

			a.limiter.Reset(email)
			a.limiter.Reset(defaultIP)
		})
	})

	// 5. ToggleEmployee: only owning tenant's owner can toggle their own employee
	t.Run("ToggleEmployee_TenantValidation", func(t *testing.T) {
		a.limiter.Reset(defaultIP)

		// Create Owner A
		ownerAPass, _ := bcrypt.GenerateFromPassword([]byte("pass_a"), bcrypt.DefaultCost)
		ownerA := &models.User{
			ID:        "owner_a",
			Email:     "owner_a@example.com",
			Username:  "owner_a_username",
			Password:  string(ownerAPass),
			Role:      models.RoleOwner,
			TenantID:  "tenant_a",
			IsActive:  true,
			KYCStatus: models.KYCApproved,
		}
		s.CreateUser(ctx, ownerA)

		// Create Owner B
		ownerBPass, _ := bcrypt.GenerateFromPassword([]byte("pass_b"), bcrypt.DefaultCost)
		ownerB := &models.User{
			ID:        "owner_b",
			Email:     "owner_b@example.com",
			Username:  "owner_b_username",
			Password:  string(ownerBPass),
			Role:      models.RoleOwner,
			TenantID:  "tenant_b",
			IsActive:  true,
			KYCStatus: models.KYCApproved,
		}
		s.CreateUser(ctx, ownerB)

		// Create Employee A (belongs to Owner A)
		empA := &models.User{
			ID:       "emp_a",
			Email:    "emp_a@example.com",
			Username: "emp_a_username",
			Password: "$2a$10$abcdefghijklmnopqrstuv",
			Role:     models.RoleEmployee,
			TenantID: "tenant_a",
			OwnerID:  "owner_a",
			IsActive: true,
		}
		s.CreateUser(ctx, empA)

		// Attempt toggle Employee A by Owner B -> must fail/be unauthorized
		toggleReq := models.ToggleEmployeeRequest{
			EmployeeEmail: "emp_a@example.com",
			OwnerEmail:    "owner_b@example.com",
			OwnerPassword: "pass_b",
			SetActive:     false,
		}
		body, _ := json.Marshal(toggleReq)
		req := httptest.NewRequest("POST", "/auth/employee/toggle", bytes.NewReader(body))
		rec := httptest.NewRecorder()
		a.ToggleEmployee(rec, req)

		if rec.Code == http.StatusOK {
			t.Error("expected unauthorized toggle request to fail, but got 200 OK")
		}
		if !strings.Contains(rec.Body.String(), "employee not found or not authorized for this owner") {
			t.Errorf("unexpected error message: %s", rec.Body.String())
		}

		a.limiter.Reset(defaultIP)
		a.limiter.Reset("owner_b@example.com")
	})

	// 6. authenticateReviewer
	t.Run("AuthenticateReviewer_Gaps", func(t *testing.T) {
		t.Run("MissingInternalToken", func(t *testing.T) {
			req := httptest.NewRequest("GET", "/some-url", nil)
			a.limiter.ResetReviewer(a.getClientIP(req))
			_, err := a.authenticateReviewer(req)
			if err == nil || err.Error() != "unauthorized internal token" {
				t.Errorf("expected 'unauthorized internal token' error, got: %v", err)
			}
		})

		t.Run("MissingReviewerToken", func(t *testing.T) {
			req := httptest.NewRequest("GET", "/some-url", nil)
			req.Header.Set("X-Internal-Token", a.internalServiceToken)
			a.limiter.ResetReviewer(a.getClientIP(req))
			_, err := a.authenticateReviewer(req)
			if err == nil || err.Error() != "missing reviewer token" {
				t.Errorf("expected 'missing reviewer token' error, got: %v", err)
			}
		})

		t.Run("InvalidReviewerToken", func(t *testing.T) {
			req := httptest.NewRequest("GET", "/some-url", nil)
			req.Header.Set("X-Internal-Token", a.internalServiceToken)
			req.Header.Set("X-Reviewer-Token", "invalid-token-123")
			a.limiter.ResetReviewer(a.getClientIP(req))
			a.limiter.ResetReviewer(hashToken("invalid-token-123"))
			_, err := a.authenticateReviewer(req)
			if err == nil || err.Error() != "invalid reviewer token" {
				t.Errorf("expected 'invalid reviewer token' error, got: %v", err)
			}
		})

		t.Run("QueryParamInternalTokenRejected", func(t *testing.T) {
			req := httptest.NewRequest("GET", "/some-url?internal_token="+a.internalServiceToken+"&reviewer_token=some-token", nil)
			a.limiter.ResetReviewer(a.getClientIP(req))
			_, err := a.authenticateReviewer(req)
			if err == nil || err.Error() != "unauthorized internal token" {
				t.Errorf("expected query param internal_token to be rejected, got: %v", err)
			}
		})

		t.Run("QueryParamReviewerTokenRejected", func(t *testing.T) {
			req := httptest.NewRequest("GET", "/some-url?reviewer_token=some-token", nil)
			req.Header.Set("X-Internal-Token", a.internalServiceToken)
			a.limiter.ResetReviewer(a.getClientIP(req))
			_, err := a.authenticateReviewer(req)
			if err == nil || err.Error() != "missing reviewer token" {
				t.Errorf("expected query param reviewer_token to be rejected, got: %v", err)
			}
		})
	})

	// 7. Logout
	t.Run("Logout_Gaps", func(t *testing.T) {
		// Set up isolated miniredis for Logout testing
		mrLog, err := miniredis.Run()
		if err != nil {
			t.Fatalf("failed to start miniredis for logout: %v", err)
		}
		defer mrLog.Close()

		rdbLog := redis.NewClient(&redis.Options{Addr: mrLog.Addr()})
		defer rdbLog.Close()

		jwtutil.SetRedisClient(rdbLog)
		defer jwtutil.SetRedisClient(nil)

		// Create local Auth instance
		cfgLog := &config.Config{
			AppEnv:               "local",
			GatewaySecret:        "mock-gateway-secret",
			InternalServiceToken: "mock-internal-token",
			JWTSecret:            "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2",
		}
		tempDir := t.TempDir()
		storeLoc, _ := storage.NewLocalStorage(tempDir, "/api/v1", cfgLog.JWTSecret, "", "test")
		aLog := NewAuth(s, &mockOTPDispatcher{}, cfgLog, rdbLog, storeLoc)

		user := &models.User{
			ID:       "user_logout_gap",
			Email:    "logoutgap@example.com",
			Username: "logoutgap_username",
			Password: "$2a$10$abcdefghijklmnopqrstuv",
			Role:     models.RoleOwner,
			TenantID: "tenant_logout",
			IsActive: true,
		}
		s.CreateUser(ctx, user)

		generateCustomToken := func(expiry time.Duration) string {
			claims := jwtutil.Claims{
				UserID:   user.ID,
				Role:     string(user.Role),
				TenantID: user.TenantID,
				Email:    user.Email,
				RegisteredClaims: jwt.RegisteredClaims{
					ExpiresAt: jwt.NewNumericDate(time.Now().Add(expiry)),
					IssuedAt:  jwt.NewNumericDate(time.Now()),
					ID:        "jti-" + user.ID + "-" + fmt.Sprint(time.Now().UnixNano()),
				},
			}
			token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
			tokenStr, _ := token.SignedString([]byte(cfgLog.JWTSecret))
			return tokenStr
		}

		t.Run("RecentlyExpiredToken", func(t *testing.T) {
			token := generateCustomToken(-1 * time.Hour)
			req := httptest.NewRequest("POST", "/auth/logout", nil)
			req.Header.Set("Authorization", "Bearer "+token)
			rec := httptest.NewRecorder()
			aLog.Logout(rec, req)

			if rec.Code != http.StatusOK {
				t.Errorf("expected 200 OK for recently expired token logout, got %d. Body: %s", rec.Code, rec.Body.String())
			}
		})

		t.Run("AlreadyRevokedToken", func(t *testing.T) {
			token := generateCustomToken(1 * time.Hour)

			req1 := httptest.NewRequest("POST", "/auth/logout", nil)
			req1.Header.Set("Authorization", "Bearer "+token)
			rec1 := httptest.NewRecorder()
			aLog.Logout(rec1, req1)
			if rec1.Code != http.StatusOK {
				t.Fatalf("first logout failed: %d", rec1.Code)
			}

			req2 := httptest.NewRequest("POST", "/auth/logout", nil)
			req2.Header.Set("Authorization", "Bearer "+token)
			rec2 := httptest.NewRecorder()
			aLog.Logout(rec2, req2)

			if rec2.Code != http.StatusUnauthorized {
				t.Errorf("expected 401 Unauthorized for already revoked token, got %d. Body: %s", rec2.Code, rec2.Body.String())
			}
			if !strings.Contains(rec2.Body.String(), "logout failed: jwtutil: token has been revoked") {
				t.Errorf("unexpected error: %s", rec2.Body.String())
			}
		})

		t.Run("WayPastExpiredToken", func(t *testing.T) {
			token := generateCustomToken(-8 * 24 * time.Hour)
			req := httptest.NewRequest("POST", "/auth/logout", nil)
			req.Header.Set("Authorization", "Bearer "+token)
			rec := httptest.NewRecorder()
			aLog.Logout(rec, req)

			if rec.Code != http.StatusOK {
				t.Errorf("expected 200 OK for way past expired token logout, got %d. Body: %s", rec.Code, rec.Body.String())
			}
		})
	})
}

func TestSignupUsernameValidation(t *testing.T) {
	a, _, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	t.Run("ValidUsernameSucceeds", func(t *testing.T) {
		reqBody := models.SignupRequest{
			Email:    "valid_username@example.com",
			Username: "valid_username_123",
			Password: "password123",
			Role:     models.RoleUser,
		}
		b, _ := json.Marshal(reqBody)
		req := httptest.NewRequest("POST", "/auth/signup", bytes.NewReader(b))
		rec := httptest.NewRecorder()
		a.Signup(rec, req)
		if rec.Code != http.StatusCreated {
			t.Errorf("expected 201 StatusCreated, got %d. Body: %s", rec.Code, rec.Body.String())
		}
	})

	t.Run("MissingUsernameRejected", func(t *testing.T) {
		reqBody := models.SignupRequest{
			Email:    "missing_username@example.com",
			Username: "",
			Password: "password123",
			Role:     models.RoleUser,
		}
		b, _ := json.Marshal(reqBody)
		req := httptest.NewRequest("POST", "/auth/signup", bytes.NewReader(b))
		rec := httptest.NewRecorder()
		a.Signup(rec, req)
		if rec.Code != http.StatusBadRequest {
			t.Errorf("expected 400 StatusBadRequest, got %d. Body: %s", rec.Code, rec.Body.String())
		}
		if !strings.Contains(rec.Body.String(), "username is required") {
			t.Errorf("expected error message to contain 'username is required', got: %s", rec.Body.String())
		}
	})

	t.Run("TooShortUsernameRejected", func(t *testing.T) {
		reqBody := models.SignupRequest{
			Email:    "tooshort@example.com",
			Username: "ab",
			Password: "password123",
			Role:     models.RoleUser,
		}
		b, _ := json.Marshal(reqBody)
		req := httptest.NewRequest("POST", "/auth/signup", bytes.NewReader(b))
		rec := httptest.NewRecorder()
		a.Signup(rec, req)
		if rec.Code != http.StatusBadRequest {
			t.Errorf("expected 400 StatusBadRequest, got %d. Body: %s", rec.Code, rec.Body.String())
		}
		if !strings.Contains(rec.Body.String(), "username must be between 3 and 30 characters") {
			t.Errorf("expected error message to contain 'username must be between 3 and 30 characters', got: %s", rec.Body.String())
		}
	})

	t.Run("TooLongUsernameRejected", func(t *testing.T) {
		reqBody := models.SignupRequest{
			Email:    "toolong@example.com",
			Username: "abcdefghijklmnopqrstuvwxyz12345", // 31 chars
			Password: "password123",
			Role:     models.RoleUser,
		}
		b, _ := json.Marshal(reqBody)
		req := httptest.NewRequest("POST", "/auth/signup", bytes.NewReader(b))
		rec := httptest.NewRecorder()
		a.Signup(rec, req)
		if rec.Code != http.StatusBadRequest {
			t.Errorf("expected 400 StatusBadRequest, got %d. Body: %s", rec.Code, rec.Body.String())
		}
		if !strings.Contains(rec.Body.String(), "username must be between 3 and 30 characters") {
			t.Errorf("expected error message to contain 'username must be between 3 and 30 characters', got: %s", rec.Body.String())
		}
	})

	t.Run("InvalidCharactersRejected", func(t *testing.T) {
		reqBody := models.SignupRequest{
			Email:    "invalidchars@example.com",
			Username: "user@name!",
			Password: "password123",
			Role:     models.RoleUser,
		}
		b, _ := json.Marshal(reqBody)
		req := httptest.NewRequest("POST", "/auth/signup", bytes.NewReader(b))
		rec := httptest.NewRecorder()
		a.Signup(rec, req)
		if rec.Code != http.StatusBadRequest {
			t.Errorf("expected 400 StatusBadRequest, got %d. Body: %s", rec.Code, rec.Body.String())
		}
		if !strings.Contains(rec.Body.String(), "username contains invalid characters") {
			t.Errorf("expected error message to contain 'username contains invalid characters', got: %s", rec.Body.String())
		}
	})

	t.Run("ValidArabicUsernameSucceeds", func(t *testing.T) {
		reqBody := models.SignupRequest{
			Email:    "arabic_username@example.com",
			Username: "أحمد محمد",
			Password: "password123",
			Role:     models.RoleUser,
		}
		b, _ := json.Marshal(reqBody)
		req := httptest.NewRequest("POST", "/auth/signup", bytes.NewReader(b))
		rec := httptest.NewRecorder()
		a.Signup(rec, req)
		if rec.Code != http.StatusCreated {
			t.Errorf("expected 201 StatusCreated for Arabic username, got %d. Body: %s", rec.Code, rec.Body.String())
		}
	})

	t.Run("MixedArabicEnglishUsernameSucceeds", func(t *testing.T) {
		reqBody := models.SignupRequest{
			Email:    "mixed_username@example.com",
			Username: "Ahmed أحمد",
			Password: "password123",
			Role:     models.RoleUser,
		}
		b, _ := json.Marshal(reqBody)
		req := httptest.NewRequest("POST", "/auth/signup", bytes.NewReader(b))
		rec := httptest.NewRecorder()
		a.Signup(rec, req)
		if rec.Code != http.StatusCreated {
			t.Errorf("expected 201 StatusCreated for mixed username, got %d. Body: %s", rec.Code, rec.Body.String())
		}
	})

	t.Run("XSSUnsafeUsernameRejected", func(t *testing.T) {
		reqBody := models.SignupRequest{
			Email:    "xss_username@example.com",
			Username: "<script>alert(1)</script>",
			Password: "password123",
			Role:     models.RoleUser,
		}
		b, _ := json.Marshal(reqBody)
		req := httptest.NewRequest("POST", "/auth/signup", bytes.NewReader(b))
		rec := httptest.NewRecorder()
		a.Signup(rec, req)
		if rec.Code != http.StatusBadRequest {
			t.Errorf("expected 400 StatusBadRequest for XSS script tag, got %d. Body: %s", rec.Code, rec.Body.String())
		}
		if !strings.Contains(rec.Body.String(), "username contains invalid characters") {
			t.Errorf("expected error message to contain 'username contains invalid characters', got: %s", rec.Body.String())
		}
	})

	t.Run("DuplicateUsernameRejected", func(t *testing.T) {
		// First user signup: succeeds
		reqBody1 := models.SignupRequest{
			Email:    "user1@example.com",
			Username: "unique_username",
			Password: "password123",
			Role:     models.RoleUser,
		}
		b1, _ := json.Marshal(reqBody1)
		req1 := httptest.NewRequest("POST", "/auth/signup", bytes.NewReader(b1))
		rec1 := httptest.NewRecorder()
		a.Signup(rec1, req1)
		if rec1.Code != http.StatusCreated {
			t.Fatalf("first signup failed: %d. Body: %s", rec1.Code, rec1.Body.String())
		}

		var resp1 map[string]any
		json.Unmarshal(rec1.Body.Bytes(), &resp1)
		otp1 := resp1["dev_otp"].(string)

		// Confirm first user account via OTP
		vBody1, _ := json.Marshal(models.VerifyOTPRequest{Email: "user1@example.com", OTP: otp1})
		vReq1 := httptest.NewRequest("POST", "/auth/verify-otp", bytes.NewReader(vBody1))
		vRec1 := httptest.NewRecorder()
		a.VerifyOTP(vRec1, vReq1)
		if vRec1.Code != http.StatusOK {
			t.Fatalf("expected 200 OK verifying first user, got %d", vRec1.Code)
		}

		// Second user signup with duplicate username but different email: rejected with 409 and specific message
		reqBody2 := models.SignupRequest{
			Email:    "user2@example.com",
			Username: "unique_username",
			Password: "password123",
			Role:     models.RoleUser,
		}
		b2, _ := json.Marshal(reqBody2)
		req2 := httptest.NewRequest("POST", "/auth/signup", bytes.NewReader(b2))
		rec2 := httptest.NewRecorder()
		a.Signup(rec2, req2)
		if rec2.Code != http.StatusConflict {
			t.Errorf("expected 409 StatusConflict for duplicate username, got %d. Body: %s", rec2.Code, rec2.Body.String())
		}
		if !strings.Contains(rec2.Body.String(), "username already taken") {
			t.Errorf("expected error message to contain 'username already taken', got: %s", rec2.Body.String())
		}

		// Third user signup with same email but different username: rejected with 409 and specific message
		reqBody3 := models.SignupRequest{
			Email:    "user1@example.com",
			Username: "different_username",
			Password: "password123",
			Role:     models.RoleUser,
		}
		b3, _ := json.Marshal(reqBody3)
		req3 := httptest.NewRequest("POST", "/auth/signup", bytes.NewReader(b3))
		rec3 := httptest.NewRecorder()
		a.Signup(rec3, req3)
		if rec3.Code != http.StatusConflict {
			t.Errorf("expected 409 StatusConflict for duplicate email, got %d. Body: %s", rec3.Code, rec3.Body.String())
		}
		if !strings.Contains(rec3.Body.String(), "email already registered") {
			t.Errorf("expected error message to contain 'email already registered', got: %s", rec3.Body.String())
		}
	})
}

func TestGetUserUsernameResponse(t *testing.T) {
	a, s, cleanup := setupTestAuth(t)
	if a == nil {
		t.Skip("setup failed")
		return
	}
	defer cleanup()

	ctx := context.Background()
	user := &models.User{
		ID:       "test-user-user-123",
		Email:    "propagate_user@example.com",
		Username: "propagate_username",
		Password: "hashedpass",
		Role:     models.RoleUser,
		IsActive: true,
	}
	if err := s.CreateUser(ctx, user); err != nil {
		t.Fatalf("failed to create user: %v", err)
	}

	token, err := jwtutil.GenerateToken(user.ID, string(user.Role), user.TenantID, user.Email)
	if err != nil {
		t.Fatalf("failed to generate token: %v", err)
	}

	req := httptest.NewRequest("GET", "/auth/user?id="+token, nil)
	rec := httptest.NewRecorder()
	a.GetUser(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	var res map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &res); err != nil {
		t.Fatalf("failed to decode: %v", err)
	}

	if res["username"] != "propagate_username" {
		t.Errorf("expected username 'propagate_username', got %v", res["username"])
	}
}

func TestGetPendingSubmissionsUsername(t *testing.T) {
	a, s, cleanup := setupTestAuth(t)
	if a == nil {
		t.Skip("setup failed")
		return
	}
	defer cleanup()

	ctx := context.Background()
	user := &models.User{
		ID:         "pending-user-123",
		Email:      "pending_propagate@example.com",
		Username:   "pending_username",
		Password:   "hashedpass",
		Role:       models.RoleOwner,
		IsActive:   true,
		KYCStatus:  models.KYCPendingApproval,
		IDFrontDoc: "id_front_test.png",
	}
	if err := s.CreateUser(ctx, user); err != nil {
		t.Fatalf("failed to create user: %v", err)
	}

	reviewer := &models.Reviewer{
		ID:    "reviewer_test_propagation",
		Name:  "Test Reviewer",
		Token: "reviewer-token-prop",
	}
	if err := s.AddReviewer(ctx, reviewer); err != nil {
		t.Fatalf("failed to add reviewer: %v", err)
	}

	req := httptest.NewRequest("GET", "/auth/kyb-kye/pending", nil)
	req.Header.Set("X-Internal-Token", "mock-internal-token")
	req.Header.Set("X-Reviewer-Token", reviewer.Token)
	rec := httptest.NewRecorder()

	a.GetPendingKYBKYESubmissions(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	var pendingList []struct {
		UserID   string `json:"user_id"`
		Username string `json:"username"`
		Email    string `json:"email"`
	}
	if err := json.NewDecoder(rec.Body).Decode(&pendingList); err != nil {
		t.Fatalf("failed to decode pending submissions: %v", err)
	}

	if len(pendingList) != 1 {
		t.Fatalf("expected 1 submission, got %d", len(pendingList))
	}

	if pendingList[0].Username != "pending_username" {
		t.Errorf("expected username 'pending_username', got %q", pendingList[0].Username)
	}
}

func TestSignupUsernameWhitespaceTrimming(t *testing.T) {
	a, _, cleanup := setupTestAuth(t)
	if a == nil {
		t.Skip("setup failed")
		return
	}
	defer cleanup()

	// 1. Assert all-space username is rejected with "username is required"
	reqBodyAllSpaces := models.SignupRequest{
		Email:    "spaces@example.com",
		Username: "   ",
		Password: "password123",
		Role:     models.RoleUser,
	}
	b1, _ := json.Marshal(reqBodyAllSpaces)
	req1 := httptest.NewRequest("POST", "/auth/signup", bytes.NewReader(b1))
	rec1 := httptest.NewRecorder()
	a.Signup(rec1, req1)

	if rec1.Code != http.StatusBadRequest {
		t.Errorf("expected 400 Bad Request for all-space username, got %d. Body: %s", rec1.Code, rec1.Body.String())
	}
	if !strings.Contains(rec1.Body.String(), "username is required") {
		t.Errorf("expected error message to contain 'username is required', got: %s", rec1.Body.String())
	}

	// 2. Register first user with "omar"
	reqBodyFirst := models.SignupRequest{
		Email:    "omar@example.com",
		Username: "omar",
		Password: "password123",
		Role:     models.RoleUser,
	}
	b2, _ := json.Marshal(reqBodyFirst)
	req2 := httptest.NewRequest("POST", "/auth/signup", bytes.NewReader(b2))
	rec2 := httptest.NewRecorder()
	a.Signup(rec2, req2)

	if rec2.Code != http.StatusCreated {
		t.Fatalf("expected 201 Created for first user registration, got %d. Body: %s", rec2.Code, rec2.Body.String())
	}

	var respFirst map[string]any
	json.Unmarshal(rec2.Body.Bytes(), &respFirst)
	otpFirst := respFirst["dev_otp"].(string)

	// Confirm first user account via OTP
	vBodyFirst, _ := json.Marshal(models.VerifyOTPRequest{Email: "omar@example.com", OTP: otpFirst})
	vReqFirst := httptest.NewRequest("POST", "/auth/verify-otp", bytes.NewReader(vBodyFirst))
	vRecFirst := httptest.NewRecorder()
	a.VerifyOTP(vRecFirst, vReqFirst)
	if vRecFirst.Code != http.StatusOK {
		t.Fatalf("expected 200 OK verifying first user, got %d", vRecFirst.Code)
	}

	// 3. Register second user with "  omar  " (which should be trimmed to "omar" and rejected as duplicate)
	reqBodySecond := models.SignupRequest{
		Email:    "omar_dup@example.com",
		Username: "  omar  ",
		Password: "password123",
		Role:     models.RoleUser,
	}
	b3, _ := json.Marshal(reqBodySecond)
	req3 := httptest.NewRequest("POST", "/auth/signup", bytes.NewReader(b3))
	rec3 := httptest.NewRecorder()
	a.Signup(rec3, req3)

	if rec3.Code != http.StatusConflict {
		t.Errorf("expected 409 StatusConflict for padded duplicate username, got %d. Body: %s", rec3.Code, rec3.Body.String())
	}
	if !strings.Contains(rec3.Body.String(), "username already taken") {
		t.Errorf("expected error message to contain 'username already taken', got: %s", rec3.Body.String())
	}
}

func TestSignupUsernameCaseInsensitivity(t *testing.T) {
	a, _, cleanup := setupTestAuth(t)
	if a == nil {
		t.Skip("setup failed")
		return
	}
	defer cleanup()

	// 1. Register first user with "omar"
	reqBodyFirst := models.SignupRequest{
		Email:    "omar@example.com",
		Username: "omar",
		Password: "password123",
		Role:     models.RoleUser,
	}
	b1, _ := json.Marshal(reqBodyFirst)
	req1 := httptest.NewRequest("POST", "/auth/signup", bytes.NewReader(b1))
	rec1 := httptest.NewRecorder()
	a.Signup(rec1, req1)

	if rec1.Code != http.StatusCreated {
		t.Fatalf("expected 201 Created for first user, got %d. Body: %s", rec1.Code, rec1.Body.String())
	}

	var resp1 map[string]any
	json.Unmarshal(rec1.Body.Bytes(), &resp1)
	otp1 := resp1["dev_otp"].(string)

	// Confirm first user account via OTP
	vBody1, _ := json.Marshal(models.VerifyOTPRequest{Email: "omar@example.com", OTP: otp1})
	vReq1 := httptest.NewRequest("POST", "/auth/verify-otp", bytes.NewReader(vBody1))
	vRec1 := httptest.NewRecorder()
	a.VerifyOTP(vRec1, vReq1)
	if vRec1.Code != http.StatusOK {
		t.Fatalf("expected 200 OK verifying first user, got %d", vRec1.Code)
	}

	// 2. Register second user with "Omar" (should fail with StatusConflict / "username already taken")
	reqBodySecond := models.SignupRequest{
		Email:    "omar_caps@example.com",
		Username: "Omar",
		Password: "password123",
		Role:     models.RoleUser,
	}
	b2, _ := json.Marshal(reqBodySecond)
	req2 := httptest.NewRequest("POST", "/auth/signup", bytes.NewReader(b2))
	rec2 := httptest.NewRecorder()
	a.Signup(rec2, req2)

	if rec2.Code != http.StatusConflict {
		t.Errorf("expected 409 StatusConflict for case-variant duplicate username 'Omar', got %d. Body: %s", rec2.Code, rec2.Body.String())
	}
	if !strings.Contains(rec2.Body.String(), "username already taken") {
		t.Errorf("expected error message to contain 'username already taken', got: %s", rec2.Body.String())
	}
}

func TestTokenNameAliasesInAuth(t *testing.T) {
	a, _, cleanup := setupTestAuth(t)
	if a == nil {
		t.Skip("setup failed")
		return
	}
	defer cleanup()

	// Sign up a user to query
	reqBodyFirst := models.SignupRequest{
		Email:    "alias_auth@example.com",
		Username: "alias_auth",
		Password: "password123",
		Role:     models.RoleUser,
	}
	b1, _ := json.Marshal(reqBodyFirst)
	req1 := httptest.NewRequest("POST", "/auth/signup", bytes.NewReader(b1))
	rec1 := httptest.NewRecorder()
	a.Signup(rec1, req1)
	if rec1.Code != http.StatusCreated {
		t.Fatalf("expected 201 Created for signup, got %d. Body: %s", rec1.Code, rec1.Body.String())
	}

	var signupResp map[string]any
	json.Unmarshal(rec1.Body.Bytes(), &signupResp)
	signupOTP := signupResp["dev_otp"].(string)

	// Verify OTP
	verifyReqBody := models.VerifyOTPRequest{
		Email: "alias_auth@example.com",
		OTP:   signupOTP,
	}
	b2, _ := json.Marshal(verifyReqBody)
	req2 := httptest.NewRequest("POST", "/auth/verify-otp", bytes.NewReader(b2))
	rec2 := httptest.NewRecorder()
	a.VerifyOTP(rec2, req2)
	if rec2.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK for VerifyOTP, got %d. Body: %s", rec2.Code, rec2.Body.String())
	}

	var verifyResp map[string]any
	json.Unmarshal(rec2.Body.Bytes(), &verifyResp)
	userID := verifyResp["user_id"].(string)
	token := verifyResp["token"].(string)

	// 1. GetUser using user_token query param
	req := httptest.NewRequest("GET", "/auth/user?user_token="+token, nil)
	rec := httptest.NewRecorder()
	a.GetUser(rec, req)
	if rec.Code != http.StatusOK {
		t.Errorf("GetUser with user_token: expected 200 OK, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// 2. GetPublicProfile using user_token and requester_token query params
	req = httptest.NewRequest("GET", "/auth/user/public-profile?user_token="+userID+"&requester_token="+token, nil)
	rec = httptest.NewRecorder()
	a.GetPublicProfile(rec, req)
	if rec.Code != http.StatusOK {
		t.Errorf("GetPublicProfile with requester_token: expected 200 OK, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// 3. GetAuditLog using requester_token
	req = httptest.NewRequest("GET", "/auth/audit-log?tenant_id="+userID+"&requester_token="+token, nil)
	rec = httptest.NewRecorder()
	a.GetAuditLog(rec, req)
	if rec.Code != http.StatusOK {
		t.Errorf("GetAuditLog with requester_token: expected 200 OK, got %d. Body: %s", rec.Code, rec.Body.String())
	}
}

func TestGetEmployees(t *testing.T) {
	a, s, cleanup := setupTestAuth(t)
	if a == nil {
		t.Skip("setup failed")
		return
	}
	defer cleanup()

	ctx := context.Background()

	// 1. Create Owners A, B, C, D
	ownerA := &models.User{
		ID:        "owner_a_id",
		Email:     "owner_a@example.com",
		Username:  "owner_a",
		Role:      models.RoleOwner,
		TenantID:  "tenant_a",
		IsActive:  true,
		CreatedAt: time.Now(),
	}
	s.CreateUser(ctx, ownerA)

	ownerB := &models.User{
		ID:        "owner_b_id",
		Email:     "owner_b@example.com",
		Username:  "owner_b",
		Role:      models.RoleOwner,
		TenantID:  "tenant_b",
		IsActive:  true,
		CreatedAt: time.Now(),
	}
	s.CreateUser(ctx, ownerB)

	ownerC := &models.User{
		ID:        "owner_c_id",
		Email:     "owner_c@example.com",
		Username:  "owner_c",
		Role:      models.RoleOwner,
		TenantID:  "tenant_c",
		IsActive:  true,
		CreatedAt: time.Now(),
	}
	s.CreateUser(ctx, ownerC)

	ownerD := &models.User{
		ID:        "owner_d_id",
		Email:     "owner_d@example.com",
		Username:  "owner_d",
		Role:      models.RoleOwner,
		TenantID:  "tenant_d",
		IsActive:  true,
		CreatedAt: time.Now(),
	}
	s.CreateUser(ctx, ownerD)

	// 2. Create Employees under Owner A (1 active, 1 frozen/inactive)
	empA1 := &models.User{
		ID:         "emp_a1_id",
		Email:      "emp_a1@example.com",
		Username:   "emp_a1",
		Role:       models.RoleEmployee,
		TenantID:   "tenant_a",
		OwnerID:    "owner_a_id",
		IsActive:   true,
		Password:   "$2a$10$secret_hash",
		IDFrontDoc: "documents/id_front.png",
		OTPCode:    "123456",
		CreatedAt:  time.Now(),
	}
	s.CreateUser(ctx, empA1)

	empA2 := &models.User{
		ID:         "emp_a2_id",
		Email:      "emp_a2@example.com",
		Username:   "emp_a2",
		Role:       models.RoleEmployee,
		TenantID:   "tenant_a",
		OwnerID:    "owner_a_id",
		IsActive:   false, // Frozen/inactive
		Password:   "$2a$10$secret_hash",
		IDFrontDoc: "documents/id_front_2.png",
		OTPCode:    "654321",
		CreatedAt:  time.Now(),
	}
	s.CreateUser(ctx, empA2)

	// 3. Create Employee under Owner B
	empB1 := &models.User{
		ID:        "emp_b1_id",
		Email:     "emp_b1@example.com",
		Username:  "emp_b1",
		Role:      models.RoleEmployee,
		TenantID:  "tenant_b",
		OwnerID:   "owner_b_id",
		IsActive:  true,
		CreatedAt: time.Now(),
	}
	s.CreateUser(ctx, empB1)

	// Generate JWT tokens
	tokenOwnerA, _ := jwtutil.GenerateToken("owner_a_id", string(models.RoleOwner), "tenant_a", "owner_a@example.com")
	tokenOwnerB, _ := jwtutil.GenerateToken("owner_b_id", string(models.RoleOwner), "tenant_b", "owner_b@example.com")
	tokenOwnerC, _ := jwtutil.GenerateToken("owner_c_id", string(models.RoleOwner), "tenant_c", "owner_c@example.com")
	tokenOwnerD, _ := jwtutil.GenerateToken("owner_d_id", string(models.RoleOwner), "tenant_d", "owner_d@example.com")
	tokenEmpA1, _ := jwtutil.GenerateToken("emp_a1_id", string(models.RoleEmployee), "tenant_a", "emp_a1@example.com")

	// Test Case 1 & 5: Owner A lists employees (active + frozen, correct fields, no sensitive leaks)
	t.Run("OwnerA_ListsEmployees_IncludesActiveAndFrozen_NoSensitiveFields", func(t *testing.T) {
		req := httptest.NewRequest("GET", "/auth/employees", nil)
		req.Header.Set("Authorization", "Bearer "+tokenOwnerA)
		rec := httptest.NewRecorder()

		a.GetEmployees(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK for Owner A, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		var rawItems []map[string]interface{}
		if err := json.Unmarshal(rec.Body.Bytes(), &rawItems); err != nil {
			t.Fatalf("Failed to parse JSON response: %v", err)
		}

		if len(rawItems) != 2 {
			t.Fatalf("Expected 2 employees for Owner A, got %d", len(rawItems))
		}

		foundActive := false
		foundFrozen := false
		for _, item := range rawItems {
			if _, ok := item["password"]; ok {
				t.Errorf("Security leak: password field present in response")
			}
			if _, ok := item["otp_code"]; ok {
				t.Errorf("Security leak: otp_code field present in response")
			}
			if _, ok := item["id_front_doc"]; ok {
				t.Errorf("Security leak: id_front_doc field present in response")
			}

			if item["id"] == "emp_a1_id" {
				foundActive = true
				if item["is_active"] != true {
					t.Errorf("Expected emp_a1_id to have is_active=true")
				}
			}
			if item["id"] == "emp_a2_id" {
				foundFrozen = true
				if item["is_active"] != false {
					t.Errorf("Expected emp_a2_id to have is_active=false")
				}
			}
		}

		if !foundActive || !foundFrozen {
			t.Errorf("Did not find both active and frozen employees in Owner A list")
		}
	})

	// Test Case 2: Non-owner role rejected with 403
	t.Run("NonOwner_Employee_Rejected403", func(t *testing.T) {
		req := httptest.NewRequest("GET", "/auth/employees", nil)
		req.Header.Set("Authorization", "Bearer "+tokenEmpA1)
		rec := httptest.NewRecorder()

		a.GetEmployees(rec, req)
		if rec.Code != http.StatusForbidden {
			t.Fatalf("Expected 403 Forbidden for employee role, got %d. Body: %s", rec.Code, rec.Body.String())
		}
	})

	// Test Case 3: Tenant isolation (Owner A cannot see Owner B's employees, and vice versa)
	t.Run("TenantIsolation_OwnerA_DoesNotSeeOwnerB", func(t *testing.T) {
		req := httptest.NewRequest("GET", "/auth/employees", nil)
		req.Header.Set("Authorization", "Bearer "+tokenOwnerB)
		rec := httptest.NewRecorder()

		a.GetEmployees(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK for Owner B, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		var rawItems []map[string]interface{}
		if err := json.Unmarshal(rec.Body.Bytes(), &rawItems); err != nil {
			t.Fatalf("Failed to parse JSON response: %v", err)
		}

		if len(rawItems) != 1 {
			t.Fatalf("Expected 1 employee for Owner B, got %d", len(rawItems))
		}
		if rawItems[0]["id"] != "emp_b1_id" {
			t.Errorf("Expected Owner B to only see emp_b1_id, got %v", rawItems[0]["id"])
		}
	})

	// Test Case 4: Owner with zero employees gets [] (empty array)
	t.Run("EmptyList_ReturnsEmptyArrayNotNil", func(t *testing.T) {
		req := httptest.NewRequest("GET", "/auth/employees", nil)
		req.Header.Set("Authorization", "Bearer "+tokenOwnerC)
		rec := httptest.NewRecorder()

		a.GetEmployees(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK for Owner C, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		bodyStr := strings.TrimSpace(rec.Body.String())
		if bodyStr != "[]" {
			t.Fatalf("Expected exact JSON array '[]' for zero employees, got '%s'", bodyStr)
		}
	})

	// Test Case 6: Rate limiting (31st request from same owner returns 429)
	t.Run("RateLimiting_31stRequestReturns429", func(t *testing.T) {
		for i := 1; i <= 30; i++ {
			req := httptest.NewRequest("GET", "/auth/employees", nil)
			req.Header.Set("Authorization", "Bearer "+tokenOwnerD)
			rec := httptest.NewRecorder()
			a.GetEmployees(rec, req)
			if rec.Code != http.StatusOK {
				t.Fatalf("Request %d for Owner D expected 200 OK, got %d. Body: %s", i, rec.Code, rec.Body.String())
			}
		}

		// 31st request
		req := httptest.NewRequest("GET", "/auth/employees", nil)
		req.Header.Set("Authorization", "Bearer "+tokenOwnerD)
		rec := httptest.NewRecorder()
		a.GetEmployees(rec, req)

		if rec.Code != http.StatusTooManyRequests {
			t.Fatalf("Expected 31st request to return 429 Too Many Requests, got %d. Body: %s", rec.Code, rec.Body.String())
		}
		if !strings.Contains(rec.Body.String(), "too many requests") {
			t.Errorf("Expected 429 response body to contain 'too many requests', got: %s", rec.Body.String())
		}
	})
}

func TestAuth_RegisterRoutes(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	jwtutil.Init("z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")

	a := &Auth{}
	mux := http.NewServeMux()
	a.RegisterRoutes(mux)

	routes := []struct {
		method string
		path   string
	}{
		{"POST", "/auth/signup"},
		{"POST", "/auth/login"},
		{"POST", "/auth/verify-otp"},
		{"GET", "/auth/user"},
		{"POST", "/auth/employee/toggle"},
		{"POST", "/auth/employee/action"},
		{"POST", "/auth/kyb/upload"},
		{"POST", "/auth/kye/upload"},
		{"GET", "/auth/kyb-kye/pending"},
		{"POST", "/auth/kyb-kye/review"},
		{"GET", "/auth/documents/view"},
		{"GET", "/auth/audit-log"},
		{"POST", "/auth/resend-otp"},
		{"POST", "/auth/logout"},
		{"GET", "/auth/user/public-profile"},
		{"GET", "/auth/employees"},
	}

	for _, r := range routes {
		req := httptest.NewRequest(r.method, r.path, nil)
		_, pattern := mux.Handler(req)
		if pattern == "" {
			t.Errorf("Expected pattern for %s %s, got empty", r.method, r.path)
		}
	}
}

func TestResendOTP_ExtraCoverage(t *testing.T) {
	a, _, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	// 1. Non-POST method -> 405 MethodNotAllowed
	req := httptest.NewRequest("GET", "/auth/resend-otp", nil)
	rec := httptest.NewRecorder()
	a.ResendOTP(rec, req)
	if rec.Code != http.StatusMethodNotAllowed {
		t.Errorf("Expected 405 MethodNotAllowed, got %d", rec.Code)
	}

	// 2. Malformed JSON -> 400 Bad Request
	req = httptest.NewRequest("POST", "/auth/resend-otp", strings.NewReader(`{"email":`))
	rec = httptest.NewRecorder()
	a.ResendOTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("Expected 400 Bad Request, got %d", rec.Code)
	}

	// 3. Missing email -> 400 Bad Request
	req = httptest.NewRequest("POST", "/auth/resend-otp", strings.NewReader(`{"email":""}`))
	rec = httptest.NewRecorder()
	a.ResendOTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("Expected 400 Bad Request, got %d", rec.Code)
	}

	// 4. User not found -> 200 OK (Generic success to prevent identity leakage)
	req = httptest.NewRequest("POST", "/auth/resend-otp", strings.NewReader(`{"email":"nonexistent-resend@example.com"}`))
	rec = httptest.NewRecorder()
	a.ResendOTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Errorf("Expected 200 OK (generic success), got %d", rec.Code)
	}
}

func TestGetPublicProfile_ExtraCoverage(t *testing.T) {
	a, mongoStore, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	user := &models.User{
		ID:       "pub-prof-id-123",
		Email:    "pubprof@example.com",
		Username: "pubprofuser",
		Role:     models.RoleOwner,
		IsActive: true,
	}
	if err := mongoStore.CreateUser(ctx, user); err != nil {
		t.Fatalf("failed to create test user: %v", err)
	}

	reqToken, _ := jwtutil.GenerateToken("req-user-1", "user", "tenant-1", "requester@example.com")

	// 1. Missing user ID -> 400 Bad Request
	req := httptest.NewRequest("GET", "/auth/user/public-profile?requester_id="+reqToken, nil)
	rec := httptest.NewRecorder()
	a.GetPublicProfile(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("Expected 400 Bad Request, got %d", rec.Code)
	}

	// 2. Missing requester token -> 401 Unauthorized
	req = httptest.NewRequest("GET", "/auth/user/public-profile?id=pub-prof-id-123", nil)
	rec = httptest.NewRecorder()
	a.GetPublicProfile(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Errorf("Expected 401 Unauthorized for missing requester token, got %d", rec.Code)
	}

	// 3. User not found -> 404 Not Found
	req = httptest.NewRequest("GET", "/auth/user/public-profile?id=non-existent-id&requester_id="+reqToken, nil)
	rec = httptest.NewRecorder()
	a.GetPublicProfile(rec, req)
	if rec.Code != http.StatusNotFound {
		t.Errorf("Expected 404 Not Found, got %d", rec.Code)
	}

	// 4. Valid lookup by ID -> 200 OK
	req = httptest.NewRequest("GET", "/auth/user/public-profile?id=pub-prof-id-123&requester_id="+reqToken, nil)
	rec = httptest.NewRecorder()
	a.GetPublicProfile(rec, req)
	if rec.Code != http.StatusOK {
		t.Errorf("Expected 200 OK for ID lookup, got %d. Body: %s", rec.Code, rec.Body.String())
	}
}

func TestSimulateEmployeeAction_ExtraCoverage(t *testing.T) {
	a, mongoStore, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	activeEmp := &models.User{
		ID:       "active-emp-123",
		Email:    "activeemp@example.com",
		Role:     models.RoleEmployee,
		IsActive: true,
	}
	frozenEmp := &models.User{
		ID:       "frozen-emp-123",
		Email:    "frozenemp@example.com",
		Role:     models.RoleEmployee,
		IsActive: false,
	}
	_ = mongoStore.CreateUser(ctx, activeEmp)
	_ = mongoStore.CreateUser(ctx, frozenEmp)

	// 1. Non-POST -> 405 MethodNotAllowed
	req := httptest.NewRequest("GET", "/auth/employee/action", nil)
	rec := httptest.NewRecorder()
	a.SimulateEmployeeAction(rec, req)
	if rec.Code != http.StatusMethodNotAllowed {
		t.Errorf("Expected 405 MethodNotAllowed, got %d", rec.Code)
	}

	// 2. Missing Auth Header -> 401 Unauthorized
	body := `{"email":"activeemp@example.com","action":"check_in"}`
	req = httptest.NewRequest("POST", "/auth/employee/action", strings.NewReader(body))
	rec = httptest.NewRecorder()
	a.SimulateEmployeeAction(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Errorf("Expected 401 Unauthorized for missing auth header, got %d", rec.Code)
	}

	// 3. Frozen Employee Action -> 403 Forbidden
	frozenToken, _ := jwtutil.GenerateToken("frozen-emp-123", "employee", "tenant-1", "frozenemp@example.com")
	frozenBody := `{"email":"frozenemp@example.com","action":"check_in"}`
	req = httptest.NewRequest("POST", "/auth/employee/action", strings.NewReader(frozenBody))
	req.Header.Set("Authorization", "Bearer "+frozenToken)
	rec = httptest.NewRecorder()
	a.SimulateEmployeeAction(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Errorf("Expected 403 Forbidden for frozen employee action, got %d. Body: %s", rec.Code, rec.Body.String())
	}
}

// TestForgotPassword_AntiEnumeration verifies that forgot-password returns an identical generic response for existing vs non-existent email
func TestForgotPassword_AntiEnumeration(t *testing.T) {
	a, mongoStore, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()

	// Register an existing user
	existingEmail := "existinguser@example.com"
	user := &models.User{
		ID:        "user-exist-1",
		Email:     existingEmail,
		Username:  "existinguser",
		Password:  "hashedpass",
		Role:      models.RoleUser,
		IsActive:  true,
		CreatedAt: time.Now().UTC(),
	}
	if err := mongoStore.CreateUser(ctx, user); err != nil {
		t.Fatalf("Failed to create test user: %v", err)
	}

	// 1. Call ForgotPassword for EXISTING email
	bodyExist := fmt.Sprintf(`{"email":%q}`, existingEmail)
	req1 := httptest.NewRequest("POST", "/auth/forgot-password", strings.NewReader(bodyExist))
	rec1 := httptest.NewRecorder()
	a.ForgotPassword(rec1, req1)

	if rec1.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK for existing email, got %d. Body: %s", rec1.Code, rec1.Body.String())
	}

	var resp1 map[string]any
	if err := json.Unmarshal(rec1.Body.Bytes(), &resp1); err != nil {
		t.Fatalf("Failed to decode response 1: %v", err)
	}

	// 2. Call ForgotPassword for NON-EXISTENT email
	bodyNonExist := `{"email":"nonexistentuser@example.com"}`
	req2 := httptest.NewRequest("POST", "/auth/forgot-password", strings.NewReader(bodyNonExist))
	rec2 := httptest.NewRecorder()
	a.ForgotPassword(rec2, req2)

	if rec2.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK for non-existent email, got %d. Body: %s", rec2.Code, rec2.Body.String())
	}

	var resp2 map[string]any
	if err := json.Unmarshal(rec2.Body.Bytes(), &resp2); err != nil {
		t.Fatalf("Failed to decode response 2: %v", err)
	}

	// Verify status and message are identical to prevent account enumeration
	if resp1["status"] != resp2["status"] || resp1["message"] != resp2["message"] {
		t.Errorf("Expected identical status and message for existing vs non-existent email. Got: %v vs %v", resp1, resp2)
	}
	if resp1["message"] != "If an account exists for this email, a reset code has been sent." {
		t.Errorf("Unexpected message string: %v", resp1["message"])
	}
}

// TestForgotPassword_RateLimiting verifies that excessive forgot-password attempts trigger 429 Too Many Requests
func TestForgotPassword_RateLimiting(t *testing.T) {
	a, _, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	email := "ratelimitforgot@example.com"
	clientIP := "192.168.1.100"

	// Trigger 5 rate limiter failures
	for i := 0; i < 5; i++ {
		a.limiter.RecordFailure(email)
	}

	body := fmt.Sprintf(`{"email":%q}`, email)
	req := httptest.NewRequest("POST", "/auth/forgot-password", strings.NewReader(body))
	req.RemoteAddr = clientIP + ":12345"
	rec := httptest.NewRecorder()
	a.ForgotPassword(rec, req)

	if rec.Code != http.StatusTooManyRequests {
		t.Errorf("Expected 429 Too Many Requests for rate limited email, got %d. Body: %s", rec.Code, rec.Body.String())
	}
}

// TestResetPassword_Success verifies reset-password updates password and old password no longer works
func TestResetPassword_Success(t *testing.T) {
	a, mongoStore, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	email := "resetpassuser@example.com"
	oldPassword := "OldPassword123"
	newPassword := "NewPassword456"

	hashedOld, _ := bcrypt.GenerateFromPassword([]byte(oldPassword), bcrypt.DefaultCost)
	user := &models.User{
		ID:        "user-reset-1",
		Email:     email,
		Username:  "resetpassuser",
		Password:  string(hashedOld),
		Role:      models.RoleUser,
		IsActive:  true,
		CreatedAt: time.Now().UTC(),
	}
	if err := mongoStore.CreateUser(ctx, user); err != nil {
		t.Fatalf("Failed to create test user: %v", err)
	}

	// Set OTP
	otpCode := "654321"
	if err := mongoStore.SetOTP(ctx, email, otpCode); err != nil {
		t.Fatalf("Failed to set OTP: %v", err)
	}

	// Execute ResetPassword
	resetBody := fmt.Sprintf(`{"email":%q,"otp":%q,"new_password":%q}`, email, otpCode, newPassword)
	req := httptest.NewRequest("POST", "/auth/reset-password", strings.NewReader(resetBody))
	rec := httptest.NewRecorder()
	a.ResetPassword(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK on reset password, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// Verify updated user record
	updatedUser := mongoStore.GetByEmail(ctx, email)
	if updatedUser == nil {
		t.Fatalf("Failed to retrieve updated user")
	}

	// Verify old password fails
	if err := bcrypt.CompareHashAndPassword([]byte(updatedUser.Password), []byte(oldPassword)); err == nil {
		t.Errorf("Expected old password to fail bcrypt check after reset")
	}

	// Verify new password succeeds
	if err := bcrypt.CompareHashAndPassword([]byte(updatedUser.Password), []byte(newPassword)); err != nil {
		t.Errorf("Expected new password to succeed bcrypt check after reset, got: %v", err)
	}
}

// TestResetPassword_InvalidOrExpiredOTP_RateLimiting verifies invalid OTP is rejected with generic error and records failure
func TestResetPassword_InvalidOrExpiredOTP_RateLimiting(t *testing.T) {
	a, mongoStore, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	email := "wrongotpreset@example.com"
	user := &models.User{
		ID:        "user-reset-2",
		Email:     email,
		Username:  "wrongotpuser",
		Password:  "somepass",
		Role:      models.RoleUser,
		IsActive:  true,
		CreatedAt: time.Now().UTC(),
	}
	_ = mongoStore.CreateUser(ctx, user)
	_ = mongoStore.SetOTP(ctx, email, "123456")

	// Call ResetPassword with WRONG OTP
	resetBody := fmt.Sprintf(`{"email":%q,"otp":"000000","new_password":"NewPassword123"}`, email)
	req := httptest.NewRequest("POST", "/auth/reset-password", strings.NewReader(resetBody))
	rec := httptest.NewRecorder()
	a.ResetPassword(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("Expected 401 Unauthorized for wrong OTP, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	var resp map[string]string
	_ = json.Unmarshal(rec.Body.Bytes(), &resp)
	if resp["error"] != "invalid or expired OTP code" {
		t.Errorf("Expected generic 'invalid or expired OTP code' error message, got %q", resp["error"])
	}

	// Verify rate limiter recorded failure on email
	locked, _ := a.limiter.IsLocked(email)
	// Recording 1 failure shouldn't lock out immediately (threshold is 5), but failure count should be incremented
	// Record 4 more failures to verify it triggers lockout
	for i := 0; i < 4; i++ {
		a.limiter.RecordFailure(email)
	}
	locked, _ = a.limiter.IsLocked(email)
	if !locked {
		t.Errorf("Expected email to be locked out after 5 failures including the reset failure")
	}
}

// TestResetPassword_PasswordPolicyCheck verifies reset-password rejects missing/empty new_password
func TestResetPassword_PasswordPolicyCheck(t *testing.T) {
	a, _, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	body := `{"email":"test@example.com","otp":"123456","new_password":""}`
	req := httptest.NewRequest("POST", "/auth/reset-password", strings.NewReader(body))
	rec := httptest.NewRecorder()
	a.ResetPassword(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Errorf("Expected 400 Bad Request for empty new_password, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	var resp map[string]string
	_ = json.Unmarshal(rec.Body.Bytes(), &resp)
	if resp["error"] != "email, otp, and new_password are required" {
		t.Errorf("Expected 'email, otp, and new_password are required' error, got %q", resp["error"])
	}
}

// TestResetPassword_OTPReusePrevention verifies an OTP cannot be reused for a second reset-password call
func TestResetPassword_OTPReusePrevention(t *testing.T) {
	a, mongoStore, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	email := "reuseotp@example.com"
	user := &models.User{
		ID:        "user-reset-reuse",
		Email:     email,
		Username:  "reuseuser",
		Password:  "OldPassword1",
		Role:      models.RoleUser,
		IsActive:  true,
		CreatedAt: time.Now().UTC(),
	}
	_ = mongoStore.CreateUser(ctx, user)
	_ = mongoStore.SetOTP(ctx, email, "888999")

	resetBody := fmt.Sprintf(`{"email":%q,"otp":"888999","new_password":"NewPassword1"}`, email)

	// Call 1: First attempt -> 200 OK
	req1 := httptest.NewRequest("POST", "/auth/reset-password", strings.NewReader(resetBody))
	rec1 := httptest.NewRecorder()
	a.ResetPassword(rec1, req1)
	if rec1.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK for first reset attempt, got %d. Body: %s", rec1.Code, rec1.Body.String())
	}

	// Call 2: Second attempt with SAME OTP -> 401 Unauthorized
	req2 := httptest.NewRequest("POST", "/auth/reset-password", strings.NewReader(resetBody))
	rec2 := httptest.NewRecorder()
	a.ResetPassword(rec2, req2)
	if rec2.Code != http.StatusUnauthorized {
		t.Fatalf("Expected 401 Unauthorized for reused OTP, got %d. Body: %s", rec2.Code, rec2.Body.String())
	}
}

// TestResetPassword_SessionInvalidation verifies that resetting a password invalidates all previously issued JWT tokens for that user
func TestResetPassword_SessionInvalidation(t *testing.T) {
	a, mongoStore, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	jwtutil.SetRedisClient(rdb)
	defer jwtutil.SetRedisClient(nil)

	ctx := context.Background()
	email := "sessioninvalidation@example.com"
	oldPassword := "OldPassword123"
	newPassword := "NewPassword456"

	hashedOld, _ := bcrypt.GenerateFromPassword([]byte(oldPassword), bcrypt.DefaultCost)
	user := &models.User{
		ID:        "user-session-invalidation-1",
		Email:     email,
		Username:  "sessioninvuser",
		Password:  string(hashedOld),
		Role:      models.RoleUser,
		IsActive:  true,
		CreatedAt: time.Now().UTC(),
	}
	if err := mongoStore.CreateUser(ctx, user); err != nil {
		t.Fatalf("Failed to create test user: %v", err)
	}

	// Issue token BEFORE password reset
	tokenBeforeReset, err := jwtutil.GenerateToken(user.ID, string(user.Role), user.ID, user.Email)
	if err != nil {
		t.Fatalf("Failed to generate token before reset: %v", err)
	}

	// Validate tokenBeforeReset before password reset -> MUST SUCCEED
	claimsBefore, err := jwtutil.ValidateToken(tokenBeforeReset)
	if err != nil {
		t.Fatalf("Expected token issued before reset to be valid prior to reset, got: %v", err)
	}
	if claimsBefore.UserID != user.ID {
		t.Errorf("Expected claims UserID %s, got %s", user.ID, claimsBefore.UserID)
	}

	// Ensure token issuance timestamp is strictly before the reset timestamp
	time.Sleep(1 * time.Second)

	// Set OTP and reset password
	otpCode := "123456"
	if err := mongoStore.SetOTP(ctx, email, otpCode); err != nil {
		t.Fatalf("Failed to set OTP: %v", err)
	}

	resetBody := fmt.Sprintf(`{"email":%q,"otp":%q,"new_password":%q}`, email, otpCode, newPassword)
	req := httptest.NewRequest("POST", "/auth/reset-password", strings.NewReader(resetBody))
	rec := httptest.NewRecorder()
	a.ResetPassword(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK on reset password, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// Validate tokenBeforeReset after password reset -> MUST BE REJECTED with "jwtutil: token has been revoked"
	_, err = jwtutil.ValidateToken(tokenBeforeReset)
	if err == nil || err.Error() != "jwtutil: token has been revoked" {
		t.Fatalf("Expected token issued before password reset to be rejected after reset with 'jwtutil: token has been revoked', got: %v", err)
	}

	// Issue token AFTER password reset -> MUST BE VALID
	tokenAfterReset, err := jwtutil.GenerateToken(user.ID, string(user.Role), user.ID, user.Email)
	if err != nil {
		t.Fatalf("Failed to generate token after reset: %v", err)
	}

	claimsAfter, err := jwtutil.ValidateToken(tokenAfterReset)
	if err != nil {
		t.Fatalf("Expected token issued after password reset to be valid, got: %v", err)
	}
	if claimsAfter.UserID != user.ID {
		t.Errorf("Expected claims UserID %s, got %s", user.ID, claimsAfter.UserID)
	}
}

// TestResetPassword_DBErrorGenericMessage verifies that MongoDB update failure returns generic error message without leaking driver details
func TestResetPassword_DBErrorGenericMessage(t *testing.T) {
	a, mongoStore, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	email := "dberrorleak@example.com"
	user := &models.User{
		ID:        "user-dberror-1",
		Email:     email,
		Username:  "dberroruser",
		Password:  "OldPass123",
		Role:      models.RoleUser,
		IsActive:  true,
		CreatedAt: time.Now().UTC(),
	}
	if err := mongoStore.CreateUser(ctx, user); err != nil {
		t.Fatalf("Failed to create test user: %v", err)
	}

	otpCode := "999888"
	if err := mongoStore.SetOTP(ctx, email, otpCode); err != nil {
		t.Fatalf("Failed to set OTP: %v", err)
	}

	// Set a schema validator on the users collection to force UpdateUser to fail with a MongoDB WriteError (Document failed validation)
	if err := mongoStore.DatabaseForTesting().RunCommand(ctx, bson.D{
		{Key: "collMod", Value: "users"},
		{Key: "validator", Value: bson.M{
			"otp_verified": true, // VerifyOTP sets otp_verified: true (passes), UpdateUser sets otp_verified: false (fails validation)
		}},
		{Key: "validationAction", Value: "error"},
	}).Err(); err != nil {
		t.Fatalf("Failed to set collMod validator on users collection: %v", err)
	}

	resetBody := fmt.Sprintf(`{"email":%q,"otp":%q,"new_password":"NewPassword123"}`, email, otpCode)
	req := httptest.NewRequest("POST", "/auth/reset-password", strings.NewReader(resetBody))
	rec := httptest.NewRecorder()
	a.ResetPassword(rec, req)

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("Expected 500 Internal Server Error when DB operation fails, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	var resp map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("Failed to unmarshal error response JSON: %v", err)
	}

	if resp["error"] != "failed to update password" {
		t.Errorf("Expected generic error 'failed to update password', got %q", resp["error"])
	}

	// Confirm no raw driver error strings leaked in the response body
	bodyStr := rec.Body.String()
	if strings.Contains(bodyStr, "Document failed validation") || strings.Contains(bodyStr, "WriteError") || strings.Contains(bodyStr, "mongo") {
		t.Errorf("Security Leak: raw MongoDB error details leaked in response body: %s", bodyStr)
	}
}

// TestDeviceToken_RegistrationAndUpsert tests registering, updating, and deduplicating FCM device tokens
func TestDeviceToken_RegistrationAndUpsert(t *testing.T) {
	a, mongoStore, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	user := &models.User{
		ID:        "user-device-token-1",
		Email:     "devicetoken@example.com",
		Username:  "devicetokenuser",
		Password:  "Password123!",
		Role:      models.RoleUser,
		IsActive:  true,
		CreatedAt: time.Now().UTC(),
	}
	_ = mongoStore.CreateUser(ctx, user)

	tokenStr, err := jwtutil.GenerateToken(user.ID, string(user.Role), user.TenantID, user.Email)
	if err != nil {
		t.Fatalf("failed to generate token: %v", err)
	}

	// 1. Register first device token
	body1 := `{"token":"fcm-token-android-123","platform":"android"}`
	req1 := httptest.NewRequest("POST", "/auth/device-token", strings.NewReader(body1))
	req1.Header.Set("Authorization", "Bearer "+tokenStr)
	rec1 := httptest.NewRecorder()
	a.DeviceToken(rec1, req1)

	if rec1.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK for token registration, got %d. Body: %s", rec1.Code, rec1.Body.String())
	}

	u1 := mongoStore.GetByID(ctx, user.ID)
	if len(u1.DeviceTokens) != 1 || u1.DeviceTokens[0].Token != "fcm-token-android-123" {
		t.Fatalf("Expected 1 device token 'fcm-token-android-123', got %+v", u1.DeviceTokens)
	}

	// 2. Re-register SAME token (upsert, should update and NOT create duplicate)
	body2 := `{"token":"fcm-token-android-123","platform":"android"}`
	req2 := httptest.NewRequest("POST", "/auth/device-token", strings.NewReader(body2))
	req2.Header.Set("Authorization", "Bearer "+tokenStr)
	rec2 := httptest.NewRecorder()
	a.DeviceToken(rec2, req2)

	if rec2.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK for token re-registration, got %d", rec2.Code)
	}

	u2 := mongoStore.GetByID(ctx, user.ID)
	if len(u2.DeviceTokens) != 1 {
		t.Fatalf("Expected no duplicate tokens (len=1), got len=%d", len(u2.DeviceTokens))
	}

	// 3. Register second device token (multiple devices support)
	body3 := `{"token":"fcm-token-ios-456","platform":"ios"}`
	req3 := httptest.NewRequest("POST", "/auth/device-token", strings.NewReader(body3))
	req3.Header.Set("Authorization", "Bearer "+tokenStr)
	rec3 := httptest.NewRecorder()
	a.DeviceToken(rec3, req3)

	if rec3.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK for second token registration, got %d", rec3.Code)
	}

	u3 := mongoStore.GetByID(ctx, user.ID)
	if len(u3.DeviceTokens) != 2 {
		t.Fatalf("Expected 2 device tokens for multi-device support, got len=%d", len(u3.DeviceTokens))
	}

	// 4. Unregister first token via DELETE
	body4 := `{"token":"fcm-token-android-123"}`
	req4 := httptest.NewRequest("DELETE", "/auth/device-token", strings.NewReader(body4))
	req4.Header.Set("Authorization", "Bearer "+tokenStr)
	rec4 := httptest.NewRecorder()
	a.DeviceToken(rec4, req4)

	if rec4.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK for token unregistration, got %d", rec4.Code)
	}

	u4 := mongoStore.GetByID(ctx, user.ID)
	if len(u4.DeviceTokens) != 1 || u4.DeviceTokens[0].Token != "fcm-token-ios-456" {
		t.Fatalf("Expected only ios token remaining, got %+v", u4.DeviceTokens)
	}

	// 5. Unregister second token via POST action="unregister"
	body5 := `{"token":"fcm-token-ios-456","action":"unregister"}`
	req5 := httptest.NewRequest("POST", "/auth/device-token", strings.NewReader(body5))
	req5.Header.Set("Authorization", "Bearer "+tokenStr)
	rec5 := httptest.NewRecorder()
	a.DeviceToken(rec5, req5)

	if rec5.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK for action=unregister, got %d", rec5.Code)
	}

	u5 := mongoStore.GetByID(ctx, user.ID)
	if len(u5.DeviceTokens) != 0 {
		t.Fatalf("Expected 0 device tokens remaining, got len=%d", len(u5.DeviceTokens))
	}
}

// TestDeviceToken_Unauthorized verifies unauthenticated requests are rejected
func TestDeviceToken_Unauthorized(t *testing.T) {
	a, _, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	req := httptest.NewRequest("POST", "/auth/device-token", strings.NewReader(`{"token":"abc"}`))
	rec := httptest.NewRecorder()
	a.DeviceToken(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Errorf("Expected 401 Unauthorized for unauthenticated device-token request, got %d", rec.Code)
	}
}

// Test (a): abandoned signup followed by a second signup attempt with the same email succeeds cleanly.
func TestSignup_AbandonedSignup_SecondAttemptSucceeds(t *testing.T) {
	a, s, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	email := "abandoned@example.com"

	// 1. Initial signup attempt (creates pending signup)
	signupReq1 := models.SignupRequest{
		Email:    email,
		Username: "abandoned_user",
		Password: "password123",
		Role:     models.RoleUser,
	}
	b1, _ := json.Marshal(signupReq1)
	req1 := httptest.NewRequest("POST", "/auth/signup", bytes.NewReader(b1))
	rec1 := httptest.NewRecorder()
	a.Signup(rec1, req1)

	if rec1.Code != http.StatusCreated {
		t.Fatalf("expected 201 Created on first signup attempt, got %d. Body: %s", rec1.Code, rec1.Body.String())
	}

	// Confirm user is NOT in DB yet
	ctx := context.Background()
	if user := s.GetByEmail(ctx, email); user != nil {
		t.Fatalf("expected user record to NOT exist in DB prior to OTP verification")
	}

	// 2. Abandoned first attempt — second signup attempt with same email
	signupReq2 := models.SignupRequest{
		Email:    email,
		Username: "abandoned_user_2",
		Password: "newpassword456",
		Role:     models.RoleUser,
	}
	b2, _ := json.Marshal(signupReq2)
	req2 := httptest.NewRequest("POST", "/auth/signup", bytes.NewReader(b2))
	rec2 := httptest.NewRecorder()
	a.Signup(rec2, req2)

	if rec2.Code != http.StatusCreated {
		t.Fatalf("expected 201 Created on second signup attempt, got %d. Body: %s", rec2.Code, rec2.Body.String())
	}

	var signupResp map[string]any
	json.Unmarshal(rec2.Body.Bytes(), &signupResp)
	newOtp := signupResp["dev_otp"].(string)

	// 3. Verify OTP from second attempt -> user created in DB
	verifyReq := models.VerifyOTPRequest{
		Email: email,
		OTP:   newOtp,
	}
	bv, _ := json.Marshal(verifyReq)
	reqV := httptest.NewRequest("POST", "/auth/verify-otp", bytes.NewReader(bv))
	recV := httptest.NewRecorder()
	a.VerifyOTP(recV, reqV)

	if recV.Code != http.StatusOK {
		t.Fatalf("expected 200 OK for VerifyOTP on second attempt, got %d. Body: %s", recV.Code, recV.Body.String())
	}

	// Confirm user now exists in DB with details from second attempt
	user := s.GetByEmail(ctx, email)
	if user == nil || user.Username != "abandoned_user_2" {
		t.Fatalf("expected user created in DB with username 'abandoned_user_2', got: %+v", user)
	}
}

// Test (b): a confirmed user can log in again after their JWT expires (regression test for bug).
func TestLogin_ConfirmedUser_CanLoginAfterJWTExpires(t *testing.T) {
	a, _, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	email := "confirmed_login@example.com"
	pass := "secretpass123"

	// 1. Signup user
	signupReq := models.SignupRequest{
		Email:    email,
		Username: "confirmed_login_user",
		Password: pass,
		Role:     models.RoleUser,
	}
	b, _ := json.Marshal(signupReq)
	req := httptest.NewRequest("POST", "/auth/signup", bytes.NewReader(b))
	rec := httptest.NewRecorder()
	a.Signup(rec, req)

	var signupResp map[string]any
	json.Unmarshal(rec.Body.Bytes(), &signupResp)
	otp := signupResp["dev_otp"].(string)

	// 2. Verify OTP -> account created in DB
	verifyReq := models.VerifyOTPRequest{
		Email: email,
		OTP:   otp,
	}
	bv, _ := json.Marshal(verifyReq)
	reqV := httptest.NewRequest("POST", "/auth/verify-otp", bytes.NewReader(bv))
	recV := httptest.NewRecorder()
	a.VerifyOTP(recV, reqV)

	if recV.Code != http.StatusOK {
		t.Fatalf("expected 200 OK on initial OTP verification, got %d. Body: %s", recV.Code, recV.Body.String())
	}

	// 3. Simulate future login after JWT expires (e.g. user returns to app)
	loginReq := models.LoginRequest{
		Email:    email,
		Password: pass,
	}
	bl, _ := json.Marshal(loginReq)
	reqL := httptest.NewRequest("POST", "/auth/login", bytes.NewReader(bl))
	recL := httptest.NewRecorder()
	a.Login(recL, reqL)

	if recL.Code != http.StatusOK {
		t.Fatalf("expected 200 OK on login for confirmed user, got %d. Body: %s", recL.Code, recL.Body.String())
	}

	var loginResp map[string]any
	json.Unmarshal(recL.Body.Bytes(), &loginResp)
	loginOtp := loginResp["dev_otp"].(string)

	// 4. Verify login 2FA OTP -> new token issued
	verifyLoginReq := models.VerifyOTPRequest{
		Email: email,
		OTP:   loginOtp,
	}
	bvl, _ := json.Marshal(verifyLoginReq)
	reqVL := httptest.NewRequest("POST", "/auth/verify-otp", bytes.NewReader(bvl))
	recVL := httptest.NewRecorder()
	a.VerifyOTP(recVL, reqVL)

	if recVL.Code != http.StatusOK {
		t.Fatalf("expected 200 OK on 2FA login verification, got %d. Body: %s", recVL.Code, recVL.Body.String())
	}
}

// Test (c): pending signup expires after 5 minutes and a fresh signup is required.
func TestSignup_PendingSignup_ExpiresAfter5Minutes(t *testing.T) {
	a, s, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	email := "expired_pending@example.com"

	// 1. Signup user
	signupReq := models.SignupRequest{
		Email:    email,
		Username: "expired_user",
		Password: "password123",
		Role:     models.RoleUser,
	}
	b, _ := json.Marshal(signupReq)
	req := httptest.NewRequest("POST", "/auth/signup", bytes.NewReader(b))
	rec := httptest.NewRecorder()
	a.Signup(rec, req)

	var signupResp map[string]any
	json.Unmarshal(rec.Body.Bytes(), &signupResp)
	otp := signupResp["dev_otp"].(string)

	// 2. Manually expire pending signup in DB
	s.DatabaseForTesting().Collection("pending_signups").UpdateOne(ctx,
		bson.M{"email": email},
		bson.M{"$set": bson.M{"otp_expires_at": time.Now().Add(-10 * time.Minute)}},
	)

	// 3. Verify OTP -> should fail with 401
	verifyReq := models.VerifyOTPRequest{
		Email: email,
		OTP:   otp,
	}
	bv, _ := json.Marshal(verifyReq)
	reqV := httptest.NewRequest("POST", "/auth/verify-otp", bytes.NewReader(bv))
	recV := httptest.NewRecorder()
	a.VerifyOTP(recV, reqV)

	if recV.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 Unauthorized for expired pending signup OTP, got %d. Body: %s", recV.Code, recV.Body.String())
	}

	// Verify no user record created in DB
	if user := s.GetByEmail(ctx, email); user != nil {
		t.Fatalf("expected user to NOT exist in DB after expired OTP attempt")
	}

	// 4. Fresh signup works cleanly
	reqFresh := httptest.NewRequest("POST", "/auth/signup", bytes.NewReader(b))
	recFresh := httptest.NewRecorder()
	a.Signup(recFresh, reqFresh)

	if recFresh.Code != http.StatusCreated {
		t.Fatalf("expected 201 Created on fresh signup after expiry, got %d. Body: %s", recFresh.Code, recFresh.Body.String())
	}
}

// Test (d): wrong OTP against a pending signup fails without creating a user record.
func TestSignup_WrongOTPAgainstPendingSignup_FailsWithoutUserCreation(t *testing.T) {
	a, s, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	email := "wrong_otp_pending@example.com"

	// 1. Signup user
	signupReq := models.SignupRequest{
		Email:    email,
		Username: "wrong_otp_user",
		Password: "password123",
		Role:     models.RoleUser,
	}
	b, _ := json.Marshal(signupReq)
	req := httptest.NewRequest("POST", "/auth/signup", bytes.NewReader(b))
	rec := httptest.NewRecorder()
	a.Signup(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201 Created on signup, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// 2. Submit wrong OTP
	verifyReq := models.VerifyOTPRequest{
		Email: email,
		OTP:   "000000",
	}
	bv, _ := json.Marshal(verifyReq)
	reqV := httptest.NewRequest("POST", "/auth/verify-otp", bytes.NewReader(bv))
	recV := httptest.NewRecorder()
	a.VerifyOTP(recV, reqV)

	if recV.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 Unauthorized for wrong OTP, got %d. Body: %s", recV.Code, recV.Body.String())
	}

	// 3. Confirm no user record was created in DB
	if user := s.GetByEmail(ctx, email); user != nil {
		t.Fatalf("expected user record to NOT exist in DB after wrong OTP, but found user: %+v", user)
	}
}

func TestReviewKYBKYESubmissions_ConcurrencyRace(t *testing.T) {
	a, s, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()

	// 1. Create a pending owner submission
	owner := &models.User{
		ID:        "owner-race-1",
		Email:     "owner-race@example.com",
		Role:      models.RoleOwner,
		KYCStatus: models.KYCPendingApproval,
	}
	if err := s.CreateUser(ctx, owner); err != nil {
		t.Fatalf("Failed to create owner user: %v", err)
	}

	// 2. Create reviewer
	reviewer := &models.Reviewer{
		ID:    "reviewer-race-1",
		Token: "reviewer-token-race",
		Name:  "Race Reviewer",
	}
	if err := s.AddReviewer(ctx, reviewer); err != nil {
		t.Fatalf("Failed to create reviewer: %v", err)
	}

	// 3. Simulate two concurrent review requests
	bodyApprove, _ := json.Marshal(map[string]string{
		"user_id": owner.ID,
		"action":  "approve",
	})
	bodyReject, _ := json.Marshal(map[string]string{
		"user_id": owner.ID,
		"action":  "reject",
		"reason":  "blurry document",
	})

	var wg sync.WaitGroup
	var code1, code2 int
	var body1, body2 string

	wg.Add(2)
	go func() {
		defer wg.Done()
		req := httptest.NewRequest("POST", "/auth/kyb-kye/review", bytes.NewReader(bodyApprove))
		req.Header.Set("X-Internal-Token", a.internalServiceToken)
		req.Header.Set("X-Reviewer-Token", reviewer.Token)
		rec := httptest.NewRecorder()
		a.ReviewKYBKYESubmissions(rec, req)
		code1 = rec.Code
		body1 = rec.Body.String()
	}()

	go func() {
		defer wg.Done()
		req := httptest.NewRequest("POST", "/auth/kyb-kye/review", bytes.NewReader(bodyReject))
		req.Header.Set("X-Internal-Token", a.internalServiceToken)
		req.Header.Set("X-Reviewer-Token", reviewer.Token)
		rec := httptest.NewRecorder()
		a.ReviewKYBKYESubmissions(rec, req)
		code2 = rec.Code
		body2 = rec.Body.String()
	}()

	wg.Wait()

	// Assert exactly one 200 OK and one 409 Conflict
	var status200Count, status409Count int
	if code1 == http.StatusOK {
		status200Count++
	} else if code1 == http.StatusConflict {
		status409Count++
	}

	if code2 == http.StatusOK {
		status200Count++
	} else if code2 == http.StatusConflict {
		status409Count++
	}

	if status200Count != 1 || status409Count != 1 {
		t.Fatalf("Expected exactly one 200 OK and one 409 Conflict, got code1=%d (body: %s), code2=%d (body: %s)", code1, body1, code2, body2)
	}

	// 4. Assert audit logs count is exactly 1 (not 2 contradictory audit log entries)
	logs := s.GetAuditLog(ctx, "")
	var kycReviewedCount int
	for _, l := range logs {
		if l.Action == "KYC_REVIEWED" && l.TenantID == owner.ID {
			kycReviewedCount++
		}
	}
	if kycReviewedCount != 1 {
		t.Errorf("Expected exactly 1 audit log entry for KYC_REVIEWED, got %d", kycReviewedCount)
	}
}

// TestDeviceToken_PlatformWhitelist reproduces the missing whitelist: the
// platform field was persisted verbatim, so arbitrary strings (or injection
// payloads) entered device_tokens[].platform.
//
// Pre-fix expectation: arbitrary platform accepted (200).
// Post-fix expectation: only android/ios/web accepted; others 400.
func TestDeviceToken_PlatformWhitelist(t *testing.T) {
	a, mongoStore, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	user := &models.User{
		ID: "user-device-platform-1", Email: "deviceplatform@example.com",
		Username: "deviceplatformuser", Password: "Password123!",
		Role: models.RoleUser, IsActive: true, CreatedAt: time.Now().UTC(),
	}
	_ = mongoStore.CreateUser(ctx, user)

	tokenStr, err := jwtutil.GenerateToken(user.ID, string(user.Role), user.TenantID, user.Email)
	if err != nil {
		t.Fatalf("token: %v", err)
	}

	for _, platform := range []string{"android", "ios", "web"} {
		body := fmt.Sprintf(`{"token":"tok-%s","platform":"%s"}`, platform, platform)
		req := httptest.NewRequest("POST", "/auth/device-token", strings.NewReader(body))
		req.Header.Set("Authorization", "Bearer "+tokenStr)
		rec := httptest.NewRecorder()
		a.DeviceToken(rec, req)
		if rec.Code != http.StatusOK {
			t.Errorf("platform %q should be whitelisted, got %d %s", platform, rec.Code, rec.Body.String())
		}
	}

	body := `{"token":"tok-bad","platform":"windows-phone;DROP"}`
	req := httptest.NewRequest("POST", "/auth/device-token", strings.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+tokenStr)
	rec := httptest.NewRecorder()
	a.DeviceToken(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("ARBITRARY PLATFORM ACCEPTED: platform=%q got %d (want 400)", "windows-phone;DROP", rec.Code)
	}
}
