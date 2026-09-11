package e2e

import (
	"context"
	"encoding/json"
	"fmt"
	"math/rand"
	"net/http"
	"strings"
	"testing"
	"time"
)

// TestCUJ_C_CustomerRegistration tests the end-to-end customer registration journey
// through the production gateway reverse proxy chain:
// 1. Negative: weak password (< 6 chars) rejected with 400 Bad Request
// 2. Negative: invalid email format rejected with 400 Bad Request
// 3. Signup with valid details succeeds with 201 Created and dispatches OTP
// 4. Negative: invalid OTP code rejected with 401 Unauthorized
// 5. Valid OTP verification completes registration and creates user
// 6. Negative: duplicate email registration for existing user rejected with 409 Conflict
// 7. Login with valid credentials triggers 2FA challenge
// 8. 2FA verification completes login and returns authenticated session token
// 9. Fetch authenticated user profile through gateway verifies active state
func TestCUJ_C_CustomerRegistration(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	cfg := LoadConfig()

	db, err := ConnectStagingDB(ctx, cfg.MongoURI)
	if err != nil {
		t.Fatalf("Failed to connect to staging DB: %v", err)
	}
	defer db.Close(ctx)

	rnd := rand.New(rand.NewSource(time.Now().UnixNano())).Intn(900000) + 100000
	email := fmt.Sprintf("cust-cujc-%d@staging.local", rnd)
	username := fmt.Sprintf("cust_cujc_%d", rnd)
	password := "SecretPass123!"

	var registeredUserID string
	defer func() {
		db.CleanupTestEntities(ctx, nil, []string{email, registeredUserID})
	}()

	// -------------------------------------------------------------------------
	// 1. NEGATIVE: Weak password (< 6 chars)
	// -------------------------------------------------------------------------
	weakReq := map[string]string{
		"email":    email,
		"password": "123",
		"username": username,
		"role":     "user",
	}
	resp, body, err := PostJSON(ctx, cfg.GatewayURL+"/api/v1/auth/signup", "", weakReq)
	if err != nil {
		t.Fatalf("Failed to execute weak password request: %v", err)
	}
	if resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("Expected 400 Bad Request for weak password, got %d: %s", resp.StatusCode, string(body))
	}
	if !strings.Contains(string(body), "password must be at least 6 characters") {
		t.Fatalf("Expected 'password must be at least 6 characters' in body, got: %s", string(body))
	}
	t.Logf("Verified: Weak password rejected with 400 Bad Request: %s", string(body))

	// -------------------------------------------------------------------------
	// 2. NEGATIVE: Invalid email format
	// -------------------------------------------------------------------------
	invalidEmailReq := map[string]string{
		"email":    "not-a-valid-email",
		"password": password,
		"username": username,
		"role":     "user",
	}
	resp, body, err = PostJSON(ctx, cfg.GatewayURL+"/api/v1/auth/signup", "", invalidEmailReq)
	if err != nil {
		t.Fatalf("Failed to execute invalid email request: %v", err)
	}
	if resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("Expected 400 Bad Request for invalid email, got %d: %s", resp.StatusCode, string(body))
	}
	t.Logf("Verified: Invalid email rejected with 400 Bad Request: %s", string(body))

	// -------------------------------------------------------------------------
	// 3. HAPPY PATH: Valid Signup
	// -------------------------------------------------------------------------
	validSignupReq := map[string]string{
		"email":    email,
		"password": password,
		"username": username,
		"role":     "user",
	}
	resp, body, err = PostJSON(ctx, cfg.GatewayURL+"/api/v1/auth/signup", "", validSignupReq)
	if err != nil {
		t.Fatalf("Failed to execute valid signup request: %v", err)
	}
	if resp.StatusCode != http.StatusCreated {
		t.Fatalf("Expected 201 Created for valid signup, got %d: %s", resp.StatusCode, string(body))
	}

	var signupResp struct {
		Status  string `json:"status"`
		Message string `json:"message"`
		DevOTP  string `json:"dev_otp"`
	}
	if err := json.Unmarshal(body, &signupResp); err != nil {
		t.Fatalf("Failed to parse signup response: %v", err)
	}
	if signupResp.DevOTP == "" {
		t.Fatalf("Expected dev_otp in signup response, got body: %s", string(body))
	}
	t.Logf("Verified: Signup successful with 201 Created, dev_otp=%s", signupResp.DevOTP)

	// -------------------------------------------------------------------------
	// 4. NEGATIVE: Invalid OTP code
	// -------------------------------------------------------------------------
	invalidOTPReq := map[string]string{
		"email": email,
		"otp":   "000000",
	}
	resp, body, err = PostJSON(ctx, cfg.GatewayURL+"/api/v1/auth/verify-otp", "", invalidOTPReq)
	if err != nil {
		t.Fatalf("Failed to execute invalid OTP request: %v", err)
	}
	if resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("Expected 401 Unauthorized for invalid OTP, got %d: %s", resp.StatusCode, string(body))
	}
	t.Logf("Verified: Invalid OTP rejected with 401 Unauthorized: %s", string(body))

	// -------------------------------------------------------------------------
	// 5. HAPPY PATH: Valid OTP verification completes registration
	// -------------------------------------------------------------------------
	verifyReq := map[string]string{
		"email": email,
		"otp":   signupResp.DevOTP,
	}
	resp, body, err = PostJSON(ctx, cfg.GatewayURL+"/api/v1/auth/verify-otp", "", verifyReq)
	if err != nil {
		t.Fatalf("Failed to execute valid OTP verification: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("Expected 200 OK for valid OTP verification, got %d: %s", resp.StatusCode, string(body))
	}

	var verifyResp struct {
		Status   string `json:"status"`
		UserID   string `json:"user_id"`
		Role     string `json:"role"`
		Username string `json:"username"`
		Token    string `json:"token"`
	}
	if err := json.Unmarshal(body, &verifyResp); err != nil {
		t.Fatalf("Failed to parse OTP verification response: %v", err)
	}
	if verifyResp.UserID == "" || verifyResp.Token == "" {
		t.Fatalf("Expected user_id and token in verification response, got: %s", string(body))
	}
	registeredUserID = verifyResp.UserID
	t.Logf("Verified: Customer registered successfully, userID=%s, role=%s", registeredUserID, verifyResp.Role)

	// -------------------------------------------------------------------------
	// 6. NEGATIVE: Duplicate email signup for existing registered user
	// -------------------------------------------------------------------------
	resp, body, err = PostJSON(ctx, cfg.GatewayURL+"/api/v1/auth/signup", "", validSignupReq)
	if err != nil {
		t.Fatalf("Failed to execute duplicate signup request: %v", err)
	}
	if resp.StatusCode != http.StatusConflict {
		t.Fatalf("Expected 409 Conflict for duplicate email signup, got %d: %s", resp.StatusCode, string(body))
	}
	if !strings.Contains(string(body), "already registered") {
		t.Fatalf("Expected 'already registered' in conflict response, got: %s", string(body))
	}
	t.Logf("Verified: Duplicate signup rejected with 409 Conflict: %s", string(body))

	// -------------------------------------------------------------------------
	// 7. HAPPY PATH: Login flow (Password verification -> 2FA challenge)
	// -------------------------------------------------------------------------
	loginReq := map[string]string{
		"email":    email,
		"password": password,
	}
	resp, body, err = PostJSON(ctx, cfg.GatewayURL+"/api/v1/auth/login", "", loginReq)
	if err != nil {
		t.Fatalf("Failed to execute login request: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("Expected 200 OK for login, got %d: %s", resp.StatusCode, string(body))
	}

	var loginResp struct {
		Status  string `json:"status"`
		Message string `json:"message"`
		DevOTP  string `json:"dev_otp"`
	}
	if err := json.Unmarshal(body, &loginResp); err != nil {
		t.Fatalf("Failed to parse login response: %v", err)
	}
	if loginResp.DevOTP == "" {
		t.Fatalf("Expected 2FA dev_otp in login response, got: %s", string(body))
	}
	t.Logf("Verified: Login credentials validated, 2FA challenge triggered with dev_otp=%s", loginResp.DevOTP)

	// -------------------------------------------------------------------------
	// 8. 2FA Verification: Issue authenticated session JWT
	// -------------------------------------------------------------------------
	twoFactorReq := map[string]string{
		"email": email,
		"otp":   loginResp.DevOTP,
	}
	resp, body, err = PostJSON(ctx, cfg.GatewayURL+"/api/v1/auth/verify-otp", "", twoFactorReq)
	if err != nil {
		t.Fatalf("Failed to verify 2FA OTP: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("Expected 200 OK for 2FA OTP verification, got %d: %s", resp.StatusCode, string(body))
	}

	var twoFactorResp struct {
		Token    string `json:"token"`
		UserID   string `json:"user_id"`
		Role     string `json:"role"`
		Username string `json:"username"`
	}
	if err := json.Unmarshal(body, &twoFactorResp); err != nil {
		t.Fatalf("Failed to parse 2FA response: %v", err)
	}
	if twoFactorResp.Token == "" || twoFactorResp.UserID != registeredUserID {
		t.Fatalf("2FA verification mismatch, expected userID %s, got: %s", registeredUserID, string(body))
	}
	t.Logf("Verified: 2FA verification successful, session token acquired")

	// -------------------------------------------------------------------------
	// 9. Authenticated App State: Query profile via GET /api/v1/auth/user
	// -------------------------------------------------------------------------
	profileURL := fmt.Sprintf("%s/api/v1/auth/user?user_token=%s", cfg.GatewayURL, twoFactorResp.Token)
	resp, body, err = GetJSON(ctx, profileURL, twoFactorResp.Token)
	if err != nil {
		t.Fatalf("Failed to fetch user profile: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("Expected 200 OK from /auth/user, got %d: %s", resp.StatusCode, string(body))
	}

	var profileResp struct {
		ID       string `json:"id"`
		Email    string `json:"email"`
		Role     string `json:"role"`
		Username string `json:"username"`
	}
	if err := json.Unmarshal(body, &profileResp); err != nil {
		t.Fatalf("Failed to parse user profile response: %v", err)
	}
	if profileResp.ID != registeredUserID || profileResp.Email != email || profileResp.Username != username {
		t.Fatalf("Profile data mismatch, expected ID=%s, Email=%s, Username=%s, got %+v", registeredUserID, email, username, profileResp)
	}
	t.Logf("Verified: Authenticated user profile loaded cleanly through Gateway: %+v", profileResp)
	t.Logf("== CUJ-C (Customer Registration & Authentication Flow) PASSED CLEANLY ==")
}
