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
	"golang.org/x/crypto/bcrypt"
)

func TestResendOTP_PendingLoginChallenge_And_PendingSignup(t *testing.T) {
	a, s, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()

	// ---------------------------------------------------------
	// Path 1: Resend for a pending signup
	// ---------------------------------------------------------
	t.Run("Resend_PendingSignup_DispatchesNewCode", func(t *testing.T) {
		signupEmail := "pending_signup@example.com"
		initialCode := "111222"
		pending := &models.PendingSignup{
			Email:     signupEmail,
			Username:  "pending_user",
			Password:  "$2a$10$dummyhashedpasswordvalue123456",
			Role:      models.RoleUser,
			CreatedAt: time.Now(),
		}
		if err := s.SetPendingSignup(ctx, signupEmail, pending, initialCode); err != nil {
			t.Fatalf("set pending signup: %v", err)
		}

		// Call resend
		resendPayload, _ := json.Marshal(map[string]string{"email": signupEmail})
		req := httptest.NewRequest(http.MethodPost, "/auth/resend-otp", bytes.NewReader(resendPayload))
		req.Header.Set("Content-Type", "application/json")
		rec := httptest.NewRecorder()
		a.ResendOTP(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 OK for pending signup resend, got %d: %s", rec.Code, rec.Body.String())
		}

		var resp map[string]any
		if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
			t.Fatalf("unmarshal: %v", err)
		}
		newCode, ok := resp["dev_otp"].(string)
		if !ok || len(newCode) != 6 {
			t.Fatalf("expected 6-digit dev_otp, got %v", resp["dev_otp"])
		}
		if newCode == initialCode {
			t.Errorf("expected fresh OTP code, got identical to initial: %s", newCode)
		}

		// Verify old code fails, new code succeeds in VerifyOTP
		verifyWrong, _ := json.Marshal(map[string]string{"email": signupEmail, "otp": initialCode})
		reqWrong := httptest.NewRequest(http.MethodPost, "/auth/verify-otp", bytes.NewReader(verifyWrong))
		recWrong := httptest.NewRecorder()
		a.VerifyOTP(recWrong, reqWrong)
		if recWrong.Code != http.StatusUnauthorized {
			t.Errorf("expected 401 for superseded code, got %d", recWrong.Code)
		}

		verifyNew, _ := json.Marshal(map[string]string{"email": signupEmail, "otp": newCode})
		reqNew := httptest.NewRequest(http.MethodPost, "/auth/verify-otp", bytes.NewReader(verifyNew))
		recNew := httptest.NewRecorder()
		a.VerifyOTP(recNew, reqNew)
		if recNew.Code != http.StatusCreated && recNew.Code != http.StatusOK {
			t.Errorf("expected 200/201 for fresh code, got %d: %s", recNew.Code, recNew.Body.String())
		}
	})

	// ---------------------------------------------------------
	// Path 2: Resend for a pending login challenge on existing user
	// ---------------------------------------------------------
	t.Run("Resend_PendingLoginChallenge_DispatchesNewCode", func(t *testing.T) {
		loginEmail := "login_challenge@example.com"
		rawPassword := "SecurePassword123!"
		hashed, _ := bcrypt.GenerateFromPassword([]byte(rawPassword), bcrypt.DefaultCost)
		user := &models.User{
			ID:        "usr-login-resend-test",
			Email:     loginEmail,
			Username:  "login_resend_user",
			Password:  string(hashed),
			Role:      models.RoleOwner,
			IsActive:  true,
			CreatedAt: time.Now(),
		}
		if err := s.CreateUser(ctx, user); err != nil {
			t.Fatalf("seed user: %v", err)
		}

		// Step 1: Initiate Login -> triggers 2FA
		loginPayload, _ := json.Marshal(map[string]string{
			"email":    loginEmail,
			"password": rawPassword,
		})
		loginReq := httptest.NewRequest(http.MethodPost, "/auth/login", bytes.NewReader(loginPayload))
		loginReq.Header.Set("Content-Type", "application/json")
		loginRec := httptest.NewRecorder()
		a.Login(loginRec, loginReq)

		if loginRec.Code != http.StatusOK {
			t.Fatalf("login expected 200, got %d: %s", loginRec.Code, loginRec.Body.String())
		}
		var loginResp map[string]any
		_ = json.Unmarshal(loginRec.Body.Bytes(), &loginResp)
		initialLoginCode, ok := loginResp["dev_otp"].(string)
		if !ok || len(initialLoginCode) != 6 {
			t.Fatalf("expected 6-digit dev_otp from login, got %v", loginResp["dev_otp"])
		}

		// Step 2: Resend OTP for the pending login challenge
		resendPayload, _ := json.Marshal(map[string]string{"email": loginEmail})
		resendReq := httptest.NewRequest(http.MethodPost, "/auth/resend-otp", bytes.NewReader(resendPayload))
		resendReq.Header.Set("Content-Type", "application/json")
		resendRec := httptest.NewRecorder()
		a.ResendOTP(resendRec, resendReq)

		if resendRec.Code != http.StatusOK {
			t.Fatalf("resend expected 200, got %d: %s", resendRec.Code, resendRec.Body.String())
		}

		var resendResp map[string]any
		if err := json.Unmarshal(resendRec.Body.Bytes(), &resendResp); err != nil {
			t.Fatalf("unmarshal resendResp: %v", err)
		}
		newLoginCode, ok := resendResp["dev_otp"].(string)
		if !ok || len(newLoginCode) != 6 {
			t.Fatalf("expected 6-digit dev_otp from resend-otp, got %v", resendResp["dev_otp"])
		}
		if newLoginCode == initialLoginCode {
			t.Errorf("resend OTP should generate a new distinct code, got identical: %s", newLoginCode)
		}

		// Step 3: Old code should fail verification
		verifyOldPayload, _ := json.Marshal(map[string]string{"email": loginEmail, "otp": initialLoginCode})
		reqOld := httptest.NewRequest(http.MethodPost, "/auth/verify-otp", bytes.NewReader(verifyOldPayload))
		reqOld.Header.Set("Content-Type", "application/json")
		recOld := httptest.NewRecorder()
		a.VerifyOTP(recOld, reqOld)

		if recOld.Code != http.StatusUnauthorized {
			t.Errorf("superseded login code expected 401, got %d: %s", recOld.Code, recOld.Body.String())
		}

		// Step 4: New code should succeed in 2FA login verification
		verifyNewPayload, _ := json.Marshal(map[string]string{"email": loginEmail, "otp": newLoginCode})
		reqNew := httptest.NewRequest(http.MethodPost, "/auth/verify-otp", bytes.NewReader(verifyNewPayload))
		reqNew.Header.Set("Content-Type", "application/json")
		recNew := httptest.NewRecorder()
		a.VerifyOTP(recNew, reqNew)

		if recNew.Code != http.StatusOK {
			t.Fatalf("fresh login code expected 200, got %d: %s", recNew.Code, recNew.Body.String())
		}

		var finalResp map[string]any
		_ = json.Unmarshal(recNew.Body.Bytes(), &finalResp)
		if finalResp["token"] == nil || finalResp["token"] == "" {
			t.Errorf("expected JWT token upon successful 2FA verification")
		}

		// Step 5: After verification, user has NO pending challenge. Resend returns generic response without dev_otp.
		resendAfterVerifPayload, _ := json.Marshal(map[string]string{"email": loginEmail})
		resendAfterReq := httptest.NewRequest(http.MethodPost, "/auth/resend-otp", bytes.NewReader(resendAfterVerifPayload))
		resendAfterRec := httptest.NewRecorder()
		a.ResendOTP(resendAfterRec, resendAfterReq)

		if resendAfterRec.Code != http.StatusOK {
			t.Fatalf("resend after verif expected 200, got %d", resendAfterRec.Code)
		}
		var afterResp map[string]any
		_ = json.Unmarshal(resendAfterRec.Body.Bytes(), &afterResp)
		if afterResp["dev_otp"] != nil {
			t.Errorf("expected no dev_otp when user has no pending login challenge, got %v", afterResp["dev_otp"])
		}
	})
}
