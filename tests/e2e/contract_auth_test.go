package e2e

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"testing"
	"time"

	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo/options"
)

// postMultipartHelper uploads a file via multipart/form-data with optional Bearer token
func postMultipartHelper(ctx context.Context, targetURL, token, fieldName, fileName string, fileBytes []byte) (*http.Response, []byte, error) {
	var body bytes.Buffer
	writer := multipart.NewWriter(&body)

	part, err := writer.CreateFormFile(fieldName, fileName)
	if err != nil {
		return nil, nil, err
	}
	if _, err := part.Write(fileBytes); err != nil {
		return nil, nil, err
	}
	if err := writer.Close(); err != nil {
		return nil, nil, err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, targetURL, &body)
	if err != nil {
		return nil, nil, err
	}
	req.Header.Set("Content-Type", writer.FormDataContentType())
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, nil, err
	}
	defer resp.Body.Close()

	respBytes, err := io.ReadAll(resp.Body)
	return resp, respBytes, err
}

// TestContract_AuthService covers all 27 canonical auth-service endpoints:
//
// 1.  POST   /auth/signup
// 2.  POST   /auth/verify-otp
// 3.  POST   /auth/resend-otp
// 4.  POST   /auth/login
// 5.  POST   /auth/refresh
// 6.  POST   /auth/forgot-password
// 7.  POST   /auth/reset-password
// 8.  POST   /auth/logout
// 9.  GET    /auth/user
// 10. PATCH  /auth/user
// 11. GET    /auth/user/public-profile
// 12. DELETE /auth/device-token
// 13. POST   /auth/email-change/request
// 14. POST   /auth/email-change/confirm
// 15. GET    /auth/employees
// 16. POST   /auth/employee/toggle
// 17. POST   /auth/employee/action
// 18. GET    /auth/audit-log
// 19. POST   /auth/kyb/upload
// 20. POST   /auth/kye/upload
// 21. GET    /auth/reviewer/verify
// 22. GET    /auth/kyb-kye/pending
// 23. POST   /auth/kyb-kye/review
// 24. GET    /auth/documents/view
// 25. GET    /auth/accounts
// 26. POST   /auth/accounts/suspend (and /auth/accounts/{id}/suspend)
// 27. POST   /auth/accounts/reactivate (and /auth/accounts/{id}/reactivate)
func TestContract_AuthService(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()

	cfg := LoadConfig()
	db, err := ConnectStagingDB(ctx, cfg.MongoURI)
	if err != nil {
		t.Fatalf("Failed to connect to staging mongo: %v", err)
	}
	defer db.Close(ctx)

	rnd := time.Now().UnixNano()
	ownerID := fmt.Sprintf("owner-auth-contract-%d", rnd)
	courierID := fmt.Sprintf("courier-auth-contract-%d", rnd)
	customerID := fmt.Sprintf("customer-auth-contract-%d", rnd)
	kycSubUserID := fmt.Sprintf("kyc-sub-auth-%d", rnd)
	reviewerID := fmt.Sprintf("reviewer-auth-contract-%d", rnd)
	rawReviewerToken := fmt.Sprintf("reviewer-token-%d", rnd)

	ownerEmail := fmt.Sprintf("owner_%d@staging.contract", rnd)
	courierEmail := fmt.Sprintf("courier_%d@staging.contract", rnd)
	customerEmail := fmt.Sprintf("customer_%d@staging.contract", rnd)
	kycSubEmail := fmt.Sprintf("kyc_sub_%d@staging.contract", rnd)

	// Clean up any test entities
	defer func() {
		db.CleanupTestEntities(ctx, []string{ownerID, kycSubUserID}, []string{ownerID, courierID, customerID, kycSubUserID, reviewerID})
		_, _ = db.client.Database("staging_auth_db").Collection("reviewers").DeleteOne(ctx, bson.M{"_id": reviewerID})
		_ = FlushReviewerRateLimits(ctx, cfg.RedisURI)
	}()

	// Seed reviewer
	if err := db.SeedReviewer(ctx, reviewerID, "Auth Contract Reviewer", rawReviewerToken); err != nil {
		t.Fatalf("Failed to seed reviewer: %v", err)
	}

	// Seed Owner in auth_db
	authUsers := db.client.Database("staging_auth_db").Collection("users")
	_, err = authUsers.UpdateOne(
		ctx,
		bson.M{"_id": ownerID},
		bson.M{
			"$set": bson.M{
				"_id":            ownerID,
				"username":       "owner_" + ownerID,
				"email":          ownerEmail,
				"role":           "owner",
				"tenant_id":      ownerID,
				"is_active":      true,
				"kyc_status":     "approved",
				"account_status": "active",
				"updated_at":     time.Now().UTC(),
			},
			"$setOnInsert": bson.M{"created_at": time.Now().UTC()},
		},
		options.UpdateOne().SetUpsert(true),
	)
	if err != nil {
		t.Fatalf("Failed to seed owner: %v", err)
	}

	// Seed paid subscription for owner
	userSubs := db.client.Database("staging_user_db").Collection("subscriptions")
	_, err = userSubs.UpdateOne(
		ctx,
		bson.M{"_id": ownerID},
		bson.M{
			"$set": bson.M{
				"_id":        ownerID,
				"tenant_id":  ownerID,
				"tier":       "paid",
				"plan":       "paid",
				"status":     "active",
				"expires_at": time.Now().UTC().Add(365 * 24 * time.Hour),
				"updated_at": time.Now().UTC(),
			},
			"$setOnInsert": bson.M{"created_at": time.Now().UTC()},
		},
		options.UpdateOne().SetUpsert(true),
	)
	if err != nil {
		t.Fatalf("Failed to seed subscription: %v", err)
	}

	// Seed courier (employee)
	_, err = authUsers.UpdateOne(
		ctx,
		bson.M{"_id": courierID},
		bson.M{
			"$set": bson.M{
				"_id":            courierID,
				"username":       "courier_" + courierID,
				"email":          courierEmail,
				"role":           "employee",
				"tenant_id":      ownerID,
				"owner_id":       ownerID,
				"is_active":      true,
				"kyc_status":     "approved",
				"account_status": "active",
				"updated_at":     time.Now().UTC(),
			},
			"$setOnInsert": bson.M{"created_at": time.Now().UTC()},
		},
		options.UpdateOne().SetUpsert(true),
	)
	if err != nil {
		t.Fatalf("Failed to seed courier: %v", err)
	}

	// Seed customer
	_, err = authUsers.UpdateOne(
		ctx,
		bson.M{"_id": customerID},
		bson.M{
			"$set": bson.M{
				"_id":            customerID,
				"username":       "customer_" + customerID,
				"email":          customerEmail,
				"role":           "user",
				"is_active":      true,
				"kyc_status":     "approved",
				"account_status": "active",
				"updated_at":     time.Now().UTC(),
			},
			"$setOnInsert": bson.M{"created_at": time.Now().UTC()},
		},
		options.UpdateOne().SetUpsert(true),
	)
	if err != nil {
		t.Fatalf("Failed to seed customer: %v", err)
	}

	// Seed KYC Submission for reviewer tests
	if err := db.SeedKYCSubmission(ctx, kycSubUserID, kycSubEmail, "owner", kycSubUserID); err != nil {
		t.Fatalf("Failed to seed KYC submission: %v", err)
	}

	ownerToken, _ := cfg.GenerateJWT(ownerID, "owner", ownerID, ownerEmail)
	courierToken, _ := cfg.GenerateJWT(courierID, "employee", ownerID, courierEmail)
	customerToken, _ := cfg.GenerateJWT(customerID, "user", "", customerEmail)

	// Minimal valid JPEG binary for KYB/KYE file upload tests
	validJpegBytes := []byte("\xFF\xD8\xFF\xE0\x00\x10JFIF\x00\x01\x01\x01\x00`\x00`\x00\x00\xFF\xDB\x00C\x00\x08\x06\x06\x07\x06\x05\x08\x07\x07\x07\t\t\x08\n\x0c\x14\r\x0c\x0b\x0b\x0c\x19\x12\x13\x0f\x14\x1d\x1a\x1f\x1e\x1d\x1a\x1c\x1c $.' \",#\x1c\x1c(7),01444\x1f'9=82<.342\xFF\xC0\x00\x0b\x08\x00\x01\x00\x01\x01\x01\x11\x00\xFF\xC4\x00\x1f\x00\x00\x01\x05\x01\x01\x01\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x01\x02\x03\x04\x05\x06\x07\x08\t\n\x0b\xFF\xDA\x00\x08\x01\x01\x00\x00?\x00\xbf\x00\xFF\xD9")

	// -------------------------------------------------------------------------
	// 1. POST /auth/signup & 2. POST /auth/verify-otp & 3. POST /auth/resend-otp
	// -------------------------------------------------------------------------
	signupEmail := fmt.Sprintf("signup_%d@staging.test", rnd)
	var devOTP string

	t.Run("POST_Auth_Signup", func(t *testing.T) {
		signupURL := fmt.Sprintf("%s/api/v1/auth/signup", cfg.GatewayURL)

		// Negative: Missing credentials -> 400
		resp, _, err := PostJSON(ctx, signupURL, "", map[string]string{"role": "user"})
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if resp.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for missing credentials, got %d", resp.StatusCode)
		}

		// Negative: Malformed JSON -> 400
		respBad, _, err := DoRequestWithHeaders(ctx, http.MethodPost, signupURL, map[string]string{"Content-Type": "application/json"}, []byte("invalid-json{"))
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respBad.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for malformed JSON, got %d", respBad.StatusCode)
		}

		// Happy Path: Valid signup -> 201 Created
		signupBody := map[string]string{
			"email":    signupEmail,
			"password": "Password123!",
			"role":     "user",
			"username": fmt.Sprintf("user_%d", rnd),
		}
		respGood, body, err := PostJSON(ctx, signupURL, "", signupBody)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusCreated {
			t.Fatalf("Expected 201 Created, got %d: %s", respGood.StatusCode, string(body))
		}

		var parsed struct {
			Status  string `json:"status"`
			Message string `json:"message"`
			DevOTP  string `json:"dev_otp"`
		}
		if err := json.Unmarshal(body, &parsed); err != nil {
			t.Fatalf("Failed to parse response: %v", err)
		}
		devOTP = parsed.DevOTP

		// Propagate the verified bcrypt hash of "Password123!" from pending_signups to our seeded owner
		var pendingDoc struct {
			Password string `bson:"password"`
		}
		err = db.client.Database("staging_auth_db").Collection("pending_signups").FindOne(ctx, bson.M{"email": signupEmail}).Decode(&pendingDoc)
		if err == nil && pendingDoc.Password != "" {
			_, _ = authUsers.UpdateOne(ctx, bson.M{"_id": ownerID}, bson.M{"$set": bson.M{"password": pendingDoc.Password}})
		}
	})

	t.Run("POST_Auth_Resend_OTP", func(t *testing.T) {
		resendURL := fmt.Sprintf("%s/api/v1/auth/resend-otp", cfg.GatewayURL)

		// Negative: Missing email -> 400
		resp, _, err := PostJSON(ctx, resendURL, "", map[string]string{})
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if resp.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for missing email, got %d", resp.StatusCode)
		}

		// Happy Path: Valid resend -> 200 OK
		respGood, body, err := PostJSON(ctx, resendURL, "", map[string]string{"email": signupEmail})
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK, got %d: %s", respGood.StatusCode, string(body))
		}

		var parsed struct {
			Status string `json:"status"`
			DevOTP string `json:"dev_otp"`
		}
		if err := json.Unmarshal(body, &parsed); err == nil && parsed.DevOTP != "" {
			devOTP = parsed.DevOTP
		}
	})

	var userJWT string
	t.Run("POST_Auth_Verify_OTP", func(t *testing.T) {
		_ = FlushAllAuthRateLimits(ctx, cfg.RedisURI)
		verifyURL := fmt.Sprintf("%s/api/v1/auth/verify-otp", cfg.GatewayURL)

		// Negative: Invalid OTP -> 401 Unauthorized
		respBad, _, err := PostJSON(ctx, verifyURL, "", map[string]string{
			"email": signupEmail,
			"otp":   "000000",
		})
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respBad.StatusCode != http.StatusUnauthorized {
			t.Errorf("Expected 401 for wrong OTP, got %d", respBad.StatusCode)
		}

		// Flush limits before valid OTP
		_ = FlushAllAuthRateLimits(ctx, cfg.RedisURI)

		// Happy Path: Valid OTP -> 200 OK
		respGood, body, err := PostJSON(ctx, verifyURL, "", map[string]string{
			"email": signupEmail,
			"otp":   devOTP,
		})
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK, got %d: %s", respGood.StatusCode, string(body))
		}

		var parsed struct {
			Status       string `json:"status"`
			Token        string `json:"token"`
			RefreshToken string `json:"refresh_token"`
			UserID       string `json:"user_id"`
			Role         string `json:"role"`
		}
		if err := json.Unmarshal(body, &parsed); err != nil {
			t.Fatalf("Failed to parse verify response: %v", err)
		}
		if parsed.Token == "" {
			t.Errorf("Expected non-empty token in verify response")
		}
		userJWT = parsed.Token
	})

	// -------------------------------------------------------------------------
	// 4. POST /auth/login
	// -------------------------------------------------------------------------
	t.Run("POST_Auth_Login", func(t *testing.T) {
		_ = FlushAllAuthRateLimits(ctx, cfg.RedisURI)
		loginURL := fmt.Sprintf("%s/api/v1/auth/login", cfg.GatewayURL)

		// Negative: Wrong credentials -> 401 Unauthorized
		respBad, _, err := PostJSON(ctx, loginURL, "", map[string]string{
			"email":    signupEmail,
			"password": "WrongPassword999!",
		})
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respBad.StatusCode != http.StatusUnauthorized {
			t.Errorf("Expected 401 for wrong password, got %d", respBad.StatusCode)
		}

		_ = FlushAllAuthRateLimits(ctx, cfg.RedisURI)

		// Happy Path: Correct credentials -> 200 OK
		respGood, body, err := PostJSON(ctx, loginURL, "", map[string]string{
			"email":    signupEmail,
			"password": "Password123!",
		})
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK, got %d: %s", respGood.StatusCode, string(body))
		}

		var parsed struct {
			Status  string `json:"status"`
			Message string `json:"message"`
		}
		if err := json.Unmarshal(body, &parsed); err != nil || parsed.Status != "success" {
			t.Errorf("Failed to parse login response: %v", err)
		}
	})

	// -------------------------------------------------------------------------
	// 5. POST /auth/refresh
	// -------------------------------------------------------------------------
	t.Run("POST_Auth_Refresh", func(t *testing.T) {
		_ = FlushAllAuthRateLimits(ctx, cfg.RedisURI)
		refreshURL := fmt.Sprintf("%s/api/v1/auth/refresh", cfg.GatewayURL)

		// Negative: Missing refresh token -> 400
		respBad, _, err := PostJSON(ctx, refreshURL, "", map[string]string{})
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respBad.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for missing token, got %d", respBad.StatusCode)
		}

		// Happy Path: Valid refresh token -> 200 OK
		respGood, body, err := PostJSON(ctx, refreshURL, "", map[string]string{
			"token": userJWT,
		})
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK, got %d: %s", respGood.StatusCode, string(body))
		}

		var parsed struct {
			Token string `json:"token"`
		}
		if err := json.Unmarshal(body, &parsed); err != nil || parsed.Token == "" {
			t.Errorf("Failed to parse refreshed token: %v", err)
		}
	})

	// -------------------------------------------------------------------------
	// 6. POST /auth/forgot-password & 7. POST /auth/reset-password
	// -------------------------------------------------------------------------
	var resetOTP string
	t.Run("POST_Auth_Forgot_Password", func(t *testing.T) {
		_ = FlushAllAuthRateLimits(ctx, cfg.RedisURI)
		forgotURL := fmt.Sprintf("%s/api/v1/auth/forgot-password", cfg.GatewayURL)

		// Negative: Missing email -> 400
		respBad, _, err := PostJSON(ctx, forgotURL, "", map[string]string{"email": ""})
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respBad.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for empty email, got %d", respBad.StatusCode)
		}

		_ = FlushAllAuthRateLimits(ctx, cfg.RedisURI)

		// Happy Path: Valid registered email -> 200 OK
		respGood, body, err := PostJSON(ctx, forgotURL, "", map[string]string{"email": signupEmail})
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK, got %d: %s", respGood.StatusCode, string(body))
		}

		var parsed struct {
			Status string `json:"status"`
			DevOTP string `json:"dev_otp"`
		}
		if err := json.Unmarshal(body, &parsed); err == nil {
			resetOTP = parsed.DevOTP
		}
	})

	t.Run("POST_Auth_Reset_Password", func(t *testing.T) {
		_ = FlushAllAuthRateLimits(ctx, cfg.RedisURI)
		verifyURL := fmt.Sprintf("%s/api/v1/auth/reset-password/verify-code", cfg.GatewayURL)
		resetURL := fmt.Sprintf("%s/api/v1/auth/reset-password", cfg.GatewayURL)

		// Negative: missing fields on verify-code -> 400
		respMissing, _, err := PostJSON(ctx, verifyURL, "", map[string]string{
			"email": signupEmail,
		})
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respMissing.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for missing fields on verify-code, got %d", respMissing.StatusCode)
		}

		// Negative: wrong OTP on verify-code -> 401, no reset_token issued
		respBadOTP, _, err := PostJSON(ctx, verifyURL, "", map[string]string{
			"email": signupEmail,
			"otp":   "999999",
		})
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respBadOTP.StatusCode != http.StatusUnauthorized {
			t.Errorf("Expected 401 for wrong reset OTP on verify-code, got %d", respBadOTP.StatusCode)
		}

		_ = FlushAllAuthRateLimits(ctx, cfg.RedisURI)

		// Phase 1 happy path: correct OTP -> 200 + reset_token
		respVerify, verifyBody, err := PostJSON(ctx, verifyURL, "", map[string]string{
			"email": signupEmail,
			"otp":   resetOTP,
		})
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respVerify.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK from verify-code, got %d: %s", respVerify.StatusCode, string(verifyBody))
		}
		var verifyResp struct {
			ResetToken string `json:"reset_token"`
		}
		if err := json.Unmarshal(verifyBody, &verifyResp); err != nil {
			t.Fatalf("Failed to parse verify-code response: %v", err)
		}
		if verifyResp.ResetToken == "" {
			t.Fatalf("Expected non-empty reset_token from verify-code, got empty")
		}

		// Negative: phase 2 with the RAW OTP instead of the possession token -> 401
		// (this is exactly the shape the old stale test used to send — keep this
		// as an explicit regression guard so the old contract can never silently
		// become accepted again)
		respRawOTP, _, err := PostJSON(ctx, resetURL, "", map[string]string{
			"email":        signupEmail,
			"otp":          resetOTP,
			"new_password": "NewPassword123!",
		})
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respRawOTP.StatusCode != http.StatusUnauthorized {
			t.Errorf("Expected 401 when phase 2 is called with the raw OTP instead of reset_token, got %d", respRawOTP.StatusCode)
		}

		// Phase 2 happy path: correct reset_token -> 200 OK
		respGood, body, err := PostJSON(ctx, resetURL, "", map[string]string{
			"email":        signupEmail,
			"reset_token":  verifyResp.ResetToken,
			"new_password": "NewPassword123!",
		})
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK, got %d: %s", respGood.StatusCode, string(body))
		}

		// Negative: reusing the same reset_token a second time -> must fail
		// (single-use token — confirms the possession-token binding fix from
		// commit 213210b actually holds)
		respReuse, _, err := PostJSON(ctx, resetURL, "", map[string]string{
			"email":        signupEmail,
			"reset_token":  verifyResp.ResetToken,
			"new_password": "AnotherPassword456!",
		})
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respReuse.StatusCode == http.StatusOK {
			t.Errorf("Expected reset_token reuse to be rejected, but got 200 OK — token is not single-use")
		}
	})

	// -------------------------------------------------------------------------
	// 8. POST /auth/logout
	// -------------------------------------------------------------------------
	t.Run("POST_Auth_Logout", func(t *testing.T) {
		_ = FlushAllAuthRateLimits(ctx, cfg.RedisURI)
		logoutURL := fmt.Sprintf("%s/api/v1/auth/logout", cfg.GatewayURL)

		// Negative: Missing Authorization header -> 400
		respBad, _, err := PostJSON(ctx, logoutURL, "", nil)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respBad.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for missing header, got %d", respBad.StatusCode)
		}

		// Happy Path: Valid token -> 200 OK
		logoutToken, _ := cfg.GenerateJWT(customerID, "user", "", customerEmail)
		respGood, body, err := PostJSON(ctx, logoutURL, logoutToken, nil)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK for logout, got %d: %s", respGood.StatusCode, string(body))
		}
	})

	// -------------------------------------------------------------------------
	// 9. GET /auth/user & 10. PATCH /auth/user
	// -------------------------------------------------------------------------
	t.Run("GET_Auth_User", func(t *testing.T) {
		userURL := fmt.Sprintf("%s/api/v1/auth/user", cfg.GatewayURL)

		// Negative: Missing user token parameter -> 400
		respMissing, _, err := GetJSON(ctx, userURL, "")
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respMissing.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 without id/token param, got %d", respMissing.StatusCode)
		}

		// Negative: Invalid token parameter -> 401 Unauthorized
		respUnauth, _, err := GetJSON(ctx, userURL+"?user_token=invalid.jwt.token", "")
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respUnauth.StatusCode != http.StatusUnauthorized {
			t.Errorf("Expected 401 for invalid user_token, got %d", respUnauth.StatusCode)
		}

		// Happy Path: Authenticated customer query -> 200 OK
		respGood, body, err := GetJSON(ctx, userURL+"?user_token="+customerToken, "")
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK for GET /auth/user, got %d: %s", respGood.StatusCode, string(body))
		}

		var userProfile struct {
			ID    string `json:"id"`
			Email string `json:"email"`
			Role  string `json:"role"`
		}
		if err := json.Unmarshal(body, &userProfile); err != nil || userProfile.ID != customerID {
			t.Errorf("Unexpected user profile response: %s", string(body))
		}
	})

	t.Run("PATCH_Auth_User", func(t *testing.T) {
		userURL := fmt.Sprintf("%s/api/v1/auth/user", cfg.GatewayURL)

		// Negative: Malformed JSON -> 400
		respBad, _, err := DoRequestWithHeaders(ctx, http.MethodPatch, userURL, map[string]string{
			"Authorization": "Bearer " + customerToken,
			"Content-Type":  "application/json",
		}, []byte("not-json"))
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respBad.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for bad JSON, got %d", respBad.StatusCode)
		}

		// Happy Path: Update profile -> 200 OK
		patchBody := map[string]string{
			"full_name": "Updated Customer Name",
			"phone":     "+201012345678",
		}
		respGood, body, err := PatchJSON(ctx, userURL, customerToken, patchBody)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK for PATCH /auth/user, got %d: %s", respGood.StatusCode, string(body))
		}
	})

	// -------------------------------------------------------------------------
	// 11. GET /auth/user/public-profile
	// -------------------------------------------------------------------------
	t.Run("GET_Auth_User_Public_Profile", func(t *testing.T) {
		pubURL := fmt.Sprintf("%s/api/v1/auth/user/public-profile", cfg.GatewayURL)

		// Negative: Missing ID query param -> 400
		respBad, _, err := GetJSON(ctx, pubURL, customerToken)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respBad.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for missing id, got %d", respBad.StatusCode)
		}

		// Negative: Missing auth header -> 401
		respNoAuth, _, err := GetJSON(ctx, pubURL+"?id="+customerID, "")
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respNoAuth.StatusCode != http.StatusUnauthorized {
			t.Errorf("Expected 401 for unauthenticated public profile read, got %d", respNoAuth.StatusCode)
		}

		// Negative: Non-existent user -> 404
		resp404, _, err := GetJSON(ctx, pubURL+"?id=non-existent-user-id-999", customerToken)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if resp404.StatusCode != http.StatusNotFound {
			t.Errorf("Expected 404 for non-existent user, got %d", resp404.StatusCode)
		}

		// Happy Path: Valid user -> 200 OK
		respGood, body, err := GetJSON(ctx, pubURL+"?id="+customerID, customerToken)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK, got %d: %s", respGood.StatusCode, string(body))
		}

		var pubProfile struct {
			ID   string `json:"id"`
			Role string `json:"role"`
		}
		if err := json.Unmarshal(body, &pubProfile); err != nil || pubProfile.ID != customerID {
			t.Errorf("Unexpected public profile response: %s", string(body))
		}
	})

	// -------------------------------------------------------------------------
	// 12. DELETE /auth/device-token
	// -------------------------------------------------------------------------
	t.Run("DELETE_Auth_Device_Token", func(t *testing.T) {
		devTokenURL := fmt.Sprintf("%s/api/v1/auth/device-token", cfg.GatewayURL)

		// Negative: Missing auth -> 401
		respUnauth, _, err := DeleteJSON(ctx, devTokenURL, "")
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respUnauth.StatusCode != http.StatusUnauthorized {
			t.Errorf("Expected 401 without auth, got %d", respUnauth.StatusCode)
		}

		// Happy Path: Authorized delete -> 200 OK
		respGood, body, err := DeleteJSON(ctx, devTokenURL+"?token=fcm-test-token", customerToken)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK, got %d: %s", respGood.StatusCode, string(body))
		}
	})

	// -------------------------------------------------------------------------
	// 13. POST /auth/email-change/request & 14. POST /auth/email-change/confirm
	// -------------------------------------------------------------------------
	newCustomerEmail := fmt.Sprintf("newcust_%d@staging.test", rnd)

	t.Run("POST_Auth_Email_Change_Request", func(t *testing.T) {
		_ = FlushAllAuthRateLimits(ctx, cfg.RedisURI)
		reqURL := fmt.Sprintf("%s/api/v1/auth/email-change/request", cfg.GatewayURL)

		// Negative: Same email -> 400
		respSame, _, err := PostJSON(ctx, reqURL, customerToken, map[string]string{"new_email": customerEmail})
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respSame.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 when changing to current email, got %d", respSame.StatusCode)
		}

		_ = FlushAllAuthRateLimits(ctx, cfg.RedisURI)

		// Happy Path: New email request -> 200 OK
		respGood, body, err := PostJSON(ctx, reqURL, customerToken, map[string]string{"new_email": newCustomerEmail})
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK, got %d: %s", respGood.StatusCode, string(body))
		}

		var parsed struct {
			Status string `json:"status"`
			DevOTP string `json:"dev_otp"`
		}
		_ = json.Unmarshal(body, &parsed)
	})

	t.Run("POST_Auth_Email_Change_Confirm", func(t *testing.T) {
		_ = FlushAllAuthRateLimits(ctx, cfg.RedisURI)
		confirmURL := fmt.Sprintf("%s/api/v1/auth/email-change/confirm", cfg.GatewayURL)

		// Negative: Missing OTP -> 400
		respMissing, _, err := PostJSON(ctx, confirmURL, customerToken, map[string]string{"otp": ""})
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respMissing.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for empty OTP, got %d", respMissing.StatusCode)
		}

		// Negative: Invalid OTP -> 401
		respBad, _, err := PostJSON(ctx, confirmURL, customerToken, map[string]string{"otp": "000000"})
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respBad.StatusCode != http.StatusUnauthorized {
			t.Errorf("Expected 401 for wrong OTP, got %d", respBad.StatusCode)
		}

		_ = FlushAllAuthRateLimits(ctx, cfg.RedisURI)

		// Re-request valid OTP since FindOneAndDelete consumed the previous pending request
		reqURL := fmt.Sprintf("%s/api/v1/auth/email-change/request", cfg.GatewayURL)
		respReq, reqBody, err := PostJSON(ctx, reqURL, customerToken, map[string]string{"new_email": newCustomerEmail})
		if err != nil || respReq.StatusCode != http.StatusOK {
			t.Fatalf("Failed to re-request email change OTP: %v (status %d)", err, respReq.StatusCode)
		}
		var parsedReq struct {
			DevOTP string `json:"dev_otp"`
		}
		_ = json.Unmarshal(reqBody, &parsedReq)

		_ = FlushAllAuthRateLimits(ctx, cfg.RedisURI)

		// Happy Path: Valid OTP -> 200 OK
		respGood, body, err := PostJSON(ctx, confirmURL, customerToken, map[string]string{"otp": parsedReq.DevOTP})
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK, got %d: %s", respGood.StatusCode, string(body))
		}
	})

	// -------------------------------------------------------------------------
	// 15. GET /auth/employees & 16. POST /auth/employee/toggle & 17. POST /auth/employee/action
	// -------------------------------------------------------------------------
	t.Run("GET_Auth_Employees", func(t *testing.T) {
		empURL := fmt.Sprintf("%s/api/v1/auth/employees", cfg.GatewayURL)

		// Negative: Forbidden for customer role -> 403
		respCust, _, err := GetJSON(ctx, empURL, customerToken)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respCust.StatusCode != http.StatusForbidden {
			t.Errorf("Expected 403 Forbidden for customer, got %d", respCust.StatusCode)
		}

		// Happy Path: Owner reading employee list -> 200 OK
		respGood, body, err := GetJSON(ctx, empURL+"?page=1&limit=10", ownerToken)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK, got %d: %s", respGood.StatusCode, string(body))
		}

		var employees []any
		if err := json.Unmarshal(body, &employees); err != nil {
			t.Errorf("Failed to parse employee list: %v", err)
		}
		if len(employees) == 0 {
			t.Errorf("Expected at least 1 employee in owner's employee list")
		}
	})

	t.Run("POST_Auth_Employee_Toggle", func(t *testing.T) {
		_ = FlushAllAuthRateLimits(ctx, cfg.RedisURI)
		toggleURL := fmt.Sprintf("%s/api/v1/auth/employee/toggle", cfg.GatewayURL)

		// Negative: Missing fields -> 400
		respBadReq, _, err := PostJSON(ctx, toggleURL, ownerToken, map[string]any{
			"owner_email": ownerEmail,
		})
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respBadReq.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for missing fields, got %d", respBadReq.StatusCode)
		}

		// Negative: Wrong owner password -> 403
		respBadPass, _, err := PostJSON(ctx, toggleURL, ownerToken, map[string]any{
			"owner_email":    ownerEmail,
			"owner_password": "WrongPassword999!",
			"employee_email": courierEmail,
			"set_active":     false,
		})
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respBadPass.StatusCode != http.StatusForbidden {
			t.Errorf("Expected 403 for wrong owner password, got %d", respBadPass.StatusCode)
		}

		_ = FlushAllAuthRateLimits(ctx, cfg.RedisURI)

		// Happy Path: Owner toggles employee active state -> 200 OK
		respGood, body, err := PostJSON(ctx, toggleURL, ownerToken, map[string]any{
			"owner_email":    ownerEmail,
			"owner_password": "Password123!",
			"employee_email": courierEmail,
			"set_active":     true,
		})
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK, got %d: %s", respGood.StatusCode, string(body))
		}
	})

	t.Run("POST_Auth_Employee_Action", func(t *testing.T) {
		actionURL := fmt.Sprintf("%s/api/v1/auth/employee/action", cfg.GatewayURL)

		// Negative: Identity mismatch (customer trying to simulate courier action) -> 403/401
		respBad, _, err := PostJSON(ctx, actionURL, customerToken, map[string]string{
			"email":  courierEmail,
			"action": "delivery_completed",
		})
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respBad.StatusCode != http.StatusForbidden && respBad.StatusCode != http.StatusUnauthorized {
			t.Errorf("Expected 403/401 for identity mismatch, got %d", respBad.StatusCode)
		}

		// Happy Path: Courier executes action -> 200 OK
		respGood, body, err := PostJSON(ctx, actionURL, courierToken, map[string]string{
			"email":  courierEmail,
			"action": "clock_in",
		})
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK, got %d: %s", respGood.StatusCode, string(body))
		}
	})

	// -------------------------------------------------------------------------
	// 18. GET /auth/audit-log
	// -------------------------------------------------------------------------
	t.Run("GET_Auth_Audit_Log", func(t *testing.T) {
		auditURL := fmt.Sprintf("%s/api/v1/auth/audit-log", cfg.GatewayURL)

		// Negative: Missing tenant_id parameter -> 400
		respMissing, _, err := GetJSON(ctx, auditURL, ownerToken)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respMissing.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for missing tenant_id, got %d", respMissing.StatusCode)
		}

		// Negative: Customer attempting to read owner's audit log -> 403
		respCust, _, err := GetJSON(ctx, fmt.Sprintf("%s?tenant_id=%s&requester_token=%s", auditURL, ownerID, customerToken), customerToken)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respCust.StatusCode != http.StatusForbidden {
			t.Errorf("Expected 403 for non-owner audit read, got %d", respCust.StatusCode)
		}

		// Happy Path: Owner reading audit log -> 200 OK
		respGood, body, err := GetJSON(ctx, fmt.Sprintf("%s?tenant_id=%s&requester_token=%s&page=1&limit=10", auditURL, ownerID, ownerToken), ownerToken)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK, got %d: %s", respGood.StatusCode, string(body))
		}

		var parsed struct {
			Count   int   `json:"count"`
			Entries []any `json:"entries"`
		}
		if err := json.Unmarshal(body, &parsed); err != nil {
			t.Errorf("Failed to parse audit log response: %v", err)
		}
	})

	// -------------------------------------------------------------------------
	// 19. POST /auth/kyb/upload & 20. POST /auth/kye/upload
	// -------------------------------------------------------------------------
	t.Run("POST_Auth_KYB_Upload", func(t *testing.T) {
		uploadURL := fmt.Sprintf("%s/api/v1/auth/kyb/upload?type=id_front", cfg.GatewayURL)

		// Negative: Customer role forbidden -> 403
		respCust, _, err := postMultipartHelper(ctx, uploadURL, customerToken, "file", "id.jpg", validJpegBytes)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respCust.StatusCode != http.StatusForbidden {
			t.Errorf("Expected 403 for customer KYB upload, got %d", respCust.StatusCode)
		}

		// Negative: Invalid doc type query param -> 400
		badTypeURL := fmt.Sprintf("%s/api/v1/auth/kyb/upload?type=invalid_doc", cfg.GatewayURL)
		respBadType, _, err := postMultipartHelper(ctx, badTypeURL, ownerToken, "file", "id.jpg", validJpegBytes)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respBadType.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for invalid doc type, got %d", respBadType.StatusCode)
		}

		// Happy Path: Owner uploading valid JPEG -> 200 OK
		respGood, body, err := postMultipartHelper(ctx, uploadURL, ownerToken, "file", "id.jpg", validJpegBytes)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK, got %d: %s", respGood.StatusCode, string(body))
		}
	})

	t.Run("POST_Auth_KYE_Upload", func(t *testing.T) {
		uploadURL := fmt.Sprintf("%s/api/v1/auth/kye/upload?type=id_front", cfg.GatewayURL)

		// Negative: Customer forbidden -> 403
		respCust, _, err := postMultipartHelper(ctx, uploadURL, customerToken, "file", "id.jpg", validJpegBytes)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respCust.StatusCode != http.StatusForbidden {
			t.Errorf("Expected 403 for customer KYE upload, got %d", respCust.StatusCode)
		}

		// Happy Path: Employee uploading valid JPEG -> 200 OK
		respGood, body, err := postMultipartHelper(ctx, uploadURL, courierToken, "file", "id.jpg", validJpegBytes)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK, got %d: %s", respGood.StatusCode, string(body))
		}
	})

	// -------------------------------------------------------------------------
	// 21. GET /auth/reviewer/verify
	// -------------------------------------------------------------------------
	t.Run("GET_Auth_Reviewer_Verify", func(t *testing.T) {
		meURL := fmt.Sprintf("%s/api/me", cfg.ConsoleURL)

		// Negative: Missing reviewer token -> 401
		respBad, _, err := DoRequestWithHeaders(ctx, http.MethodGet, meURL, nil, nil)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respBad.StatusCode != http.StatusUnauthorized {
			t.Errorf("Expected 401 for missing reviewer token, got %d", respBad.StatusCode)
		}

		// Happy Path: Valid reviewer -> 200 OK
		headers := map[string]string{"X-Reviewer-Token": rawReviewerToken}
		respGood, body, err := DoRequestWithHeaders(ctx, http.MethodGet, meURL, headers, nil)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK for reviewer verify, got %d: %s", respGood.StatusCode, string(body))
		}

		var parsed struct {
			ID   string `json:"id"`
			Name string `json:"name"`
		}
		if err := json.Unmarshal(body, &parsed); err != nil || parsed.ID != reviewerID {
			t.Errorf("Unexpected reviewer verify response: %s", string(body))
		}
	})

	// -------------------------------------------------------------------------
	// 22. GET /auth/kyb-kye/pending & 23. POST /auth/kyb-kye/review & 24. GET /auth/documents/view
	// -------------------------------------------------------------------------
	t.Run("GET_Auth_KYB_KYE_Pending", func(t *testing.T) {
		queueURL := fmt.Sprintf("%s/api/queue", cfg.ConsoleURL)

		// Negative: Missing reviewer token -> 401
		respBad, _, err := DoRequestWithHeaders(ctx, http.MethodGet, queueURL, nil, nil)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respBad.StatusCode != http.StatusUnauthorized {
			t.Errorf("Expected 401 for queue without token, got %d", respBad.StatusCode)
		}

		// Happy Path: Valid reviewer -> 200 OK
		headers := map[string]string{"X-Reviewer-Token": rawReviewerToken}
		respGood, body, err := DoRequestWithHeaders(ctx, http.MethodGet, queueURL, headers, nil)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK for pending queue, got %d: %s", respGood.StatusCode, string(body))
		}
	})

	t.Run("POST_Auth_KYB_KYE_Review", func(t *testing.T) {
		reviewURL := fmt.Sprintf("%s/api/review", cfg.ConsoleURL)
		headers := map[string]string{
			"X-Reviewer-Token": rawReviewerToken,
			"Content-Type":     "application/json",
		}

		// Negative: Missing rejection reason when rejecting -> 400
		badReq := map[string]string{
			"user_id": kycSubUserID,
			"action":  "reject",
			"reason":  "",
		}
		badBytes, _ := json.Marshal(badReq)
		respBad, _, err := DoRequestWithHeaders(ctx, http.MethodPost, reviewURL, headers, badBytes)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respBad.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for reject without reason, got %d", respBad.StatusCode)
		}

		// Happy Path: Approve submission -> 200 OK
		approveReq := map[string]string{
			"user_id": kycSubUserID,
			"action":  "approve",
		}
		appBytes, _ := json.Marshal(approveReq)
		respGood, body, err := DoRequestWithHeaders(ctx, http.MethodPost, reviewURL, headers, appBytes)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK for review action, got %d: %s", respGood.StatusCode, string(body))
		}

		// CAS Conflict Check: Attempting to review an already-approved application -> 409 Conflict
		respConflict, _, err := DoRequestWithHeaders(ctx, http.MethodPost, reviewURL, headers, appBytes)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respConflict.StatusCode != http.StatusConflict {
			t.Errorf("Expected 409 Conflict when reviewing already-approved submission, got %d", respConflict.StatusCode)
		}
	})

	t.Run("GET_Auth_Documents_View", func(t *testing.T) {
		docURL := fmt.Sprintf("%s/api/documents/view", cfg.ConsoleURL)
		headers := map[string]string{"X-Reviewer-Token": rawReviewerToken}

		// Negative: Missing token query parameter -> 400
		respBad, _, err := DoRequestWithHeaders(ctx, http.MethodGet, docURL, headers, nil)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respBad.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for missing token, got %d", respBad.StatusCode)
		}
	})

	// -------------------------------------------------------------------------
	// 25. GET /auth/accounts
	// -------------------------------------------------------------------------
	t.Run("GET_Auth_Accounts", func(t *testing.T) {
		accountsURL := fmt.Sprintf("%s/api/accounts", cfg.ConsoleURL)
		headers := map[string]string{"X-Reviewer-Token": rawReviewerToken}

		// Negative: Missing token -> 401
		respBad, _, err := DoRequestWithHeaders(ctx, http.MethodGet, accountsURL, nil, nil)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respBad.StatusCode != http.StatusUnauthorized {
			t.Errorf("Expected 401 without reviewer token, got %d", respBad.StatusCode)
		}

		// Happy Path: List accounts -> 200 OK
		respGood, body, err := DoRequestWithHeaders(ctx, http.MethodGet, accountsURL+"?page=1&limit=10", headers, nil)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK, got %d: %s", respGood.StatusCode, string(body))
		}

		var parsed struct {
			Accounts []any `json:"accounts"`
		}
		if err := json.Unmarshal(body, &parsed); err != nil {
			t.Errorf("Failed to parse accounts response: %v", err)
		}
	})

	// -------------------------------------------------------------------------
	// 26. POST /auth/accounts/suspend & 27. POST /auth/accounts/reactivate
	// (including companion routes /auth/accounts/{id}/suspend and reactivate)
	// -------------------------------------------------------------------------
	t.Run("POST_Auth_Accounts_Suspend", func(t *testing.T) {
		suspendURL := fmt.Sprintf("%s/api/accounts/suspend", cfg.ConsoleURL)
		headers := map[string]string{
			"X-Reviewer-Token": rawReviewerToken,
			"Content-Type":     "application/json",
		}

		// Negative: Missing reason -> 400
		badReq := map[string]string{"user_id": customerID, "reason": ""}
		badBytes, _ := json.Marshal(badReq)
		respBad, _, err := DoRequestWithHeaders(ctx, http.MethodPost, suspendURL, headers, badBytes)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respBad.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for suspend without reason, got %d", respBad.StatusCode)
		}

		// Happy Path: Suspend active account -> 200 OK
		goodReq := map[string]string{"user_id": customerID, "reason": "Suspicious activity detected"}
		goodBytes, _ := json.Marshal(goodReq)
		respGood, body, err := DoRequestWithHeaders(ctx, http.MethodPost, suspendURL, headers, goodBytes)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK for suspend, got %d: %s", respGood.StatusCode, string(body))
		}

		// Conflict: Suspending already suspended account -> 409 Conflict
		respConflict, _, err := DoRequestWithHeaders(ctx, http.MethodPost, suspendURL, headers, goodBytes)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respConflict.StatusCode != http.StatusConflict {
			t.Errorf("Expected 409 Conflict when suspending already-suspended account, got %d", respConflict.StatusCode)
		}
	})

	t.Run("POST_Auth_Accounts_Reactivate", func(t *testing.T) {
		reactivateURL := fmt.Sprintf("%s/api/accounts/reactivate", cfg.ConsoleURL)
		headers := map[string]string{
			"X-Reviewer-Token": rawReviewerToken,
			"Content-Type":     "application/json",
		}

		// Negative: Missing user_id -> 400
		badReq := map[string]string{"user_id": "", "reason": "No user specified"}
		badBytes, _ := json.Marshal(badReq)
		respBad, _, err := DoRequestWithHeaders(ctx, http.MethodPost, reactivateURL, headers, badBytes)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respBad.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for reactivate without user_id, got %d", respBad.StatusCode)
		}

		// Happy Path: Reactivate suspended account -> 200 OK
		goodReq := map[string]string{"user_id": customerID, "reason": "Identity verified"}
		goodBytes, _ := json.Marshal(goodReq)
		respGood, body, err := DoRequestWithHeaders(ctx, http.MethodPost, reactivateURL, headers, goodBytes)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK for reactivate, got %d: %s", respGood.StatusCode, string(body))
		}

		// Conflict: Reactivating already active account -> 409 Conflict
		respConflict, _, err := DoRequestWithHeaders(ctx, http.MethodPost, reactivateURL, headers, goodBytes)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respConflict.StatusCode != http.StatusConflict {
			t.Errorf("Expected 409 Conflict when reactivating already-active account, got %d", respConflict.StatusCode)
		}
	})
}
