package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"sync"
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
)

func TestEmailChange_FullLifecycleAndSecurity(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	cipher, err := otpcrypto.NewCipher("", "local")
	if err != nil {
		t.Fatalf("failed to create cipher: %v", err)
	}

	dbName := fmt.Sprintf("saas_platform_email_change_test_%d", time.Now().UnixNano())
	s, err := store.NewMongoDB(ctx, mongoURI, dbName, cipher)
	if err != nil {
		t.Skipf("Skipping auth-service email change integration tests: MongoDB not available at %s (%v)", mongoURI, err)
		return
	}
	defer func() {
		_ = s.DropDatabase(context.Background())
		s.Close(context.Background())
	}()

	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	cfg := &config.Config{AppEnv: "local", GatewaySecret: "test-gateway-secret", InternalServiceToken: "test-internal-token-123"}
	mockStorage, _ := storage.NewLocalStorage(t.TempDir(), "/api/v1", os.Getenv("JWT_SECRET"))
	a := NewAuth(s, &mockOTPDispatcher{}, cfg, rdb, mockStorage)

	// Seed User A (user to change email) and User B (existing email clash)
	userA := &models.User{
		ID:        "user_a_123",
		Email:     "user_a@example.com",
		Username:  "user_a",
		Role:      models.RoleUser,
		TenantID:  "tenant_a",
		IsActive:  true,
		CreatedAt: time.Now().UTC(),
	}
	userB := &models.User{
		ID:        "user_b_456",
		Email:     "user_b@example.com",
		Username:  "user_b",
		Role:      models.RoleUser,
		TenantID:  "tenant_b",
		IsActive:  true,
		CreatedAt: time.Now().UTC(),
	}

	if err := s.CreateUser(ctx, userA); err != nil {
		t.Fatalf("failed to create user A: %v", err)
	}
	if err := s.CreateUser(ctx, userB); err != nil {
		t.Fatalf("failed to create user B: %v", err)
	}

	tokenA, err := jwtutil.GenerateToken(userA.ID, string(userA.Role), userA.TenantID, userA.Email)
	if err != nil {
		t.Fatalf("failed to generate token A: %v", err)
	}

	// 1. Unauthenticated request should fail (401)
	reqUnauth := httptest.NewRequest(http.MethodPost, "/auth/email-change/request", bytes.NewBufferString(`{"new_email":"new@example.com"}`))
	reqUnauth.Header.Set("Content-Type", "application/json")
	recUnauth := httptest.NewRecorder()
	a.RequestEmailChange(recUnauth, reqUnauth)
	if recUnauth.Code != http.StatusUnauthorized {
		t.Errorf("expected 401 for unauthenticated request, got %d", recUnauth.Code)
	}

	// 2. Request change to current email should fail (400)
	reqSame := httptest.NewRequest(http.MethodPost, "/auth/email-change/request", bytes.NewBufferString(`{"new_email":"user_a@example.com"}`))
	reqSame.Header.Set("Content-Type", "application/json")
	reqSame.Header.Set("Authorization", "Bearer "+tokenA)
	recSame := httptest.NewRecorder()
	a.RequestEmailChange(recSame, reqSame)
	if recSame.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for requesting same email, got %d", recSame.Code)
	}

	// 3. Request change to an already registered email (User B) should fail (409 Conflict)
	reqClash := httptest.NewRequest(http.MethodPost, "/auth/email-change/request", bytes.NewBufferString(`{"new_email":"user_b@example.com"}`))
	reqClash.Header.Set("Content-Type", "application/json")
	reqClash.Header.Set("Authorization", "Bearer "+tokenA)
	recClash := httptest.NewRecorder()
	a.RequestEmailChange(recClash, reqClash)
	if recClash.Code != http.StatusConflict {
		t.Errorf("expected 409 for duplicate email, got %d", recClash.Code)
	}

	// 4. Request change to valid new email (Happy Path Request)
	newEmail := "user_a_new@example.com"
	reqBody, _ := json.Marshal(models.EmailChangeRequest{NewEmail: newEmail})
	reqValid := httptest.NewRequest(http.MethodPost, "/auth/email-change/request", bytes.NewReader(reqBody))
	reqValid.Header.Set("Content-Type", "application/json")
	reqValid.Header.Set("Authorization", "Bearer "+tokenA)
	recValid := httptest.NewRecorder()
	a.RequestEmailChange(recValid, reqValid)

	if recValid.Code != http.StatusOK {
		t.Fatalf("expected 200 for valid email change request, got %d: %s", recValid.Code, recValid.Body.String())
	}

	var reqResp map[string]any
	if err := json.Unmarshal(recValid.Body.Bytes(), &reqResp); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	devOTP, ok := reqResp["dev_otp"].(string)
	if !ok || devOTP == "" {
		t.Fatalf("expected dev_otp in local response, got %v", reqResp)
	}

	// 5. Confirm with wrong OTP should fail (401) and consume the single-use record
	confirmWrongBody, _ := json.Marshal(models.EmailChangeConfirmRequest{OTP: "000000"})
	reqWrong := httptest.NewRequest(http.MethodPost, "/auth/email-change/confirm", bytes.NewReader(confirmWrongBody))
	reqWrong.Header.Set("Content-Type", "application/json")
	reqWrong.Header.Set("Authorization", "Bearer "+tokenA)
	recWrong := httptest.NewRecorder()
	a.ConfirmEmailChange(recWrong, reqWrong)
	if recWrong.Code != http.StatusUnauthorized {
		t.Errorf("expected 401 for wrong OTP, got %d", recWrong.Code)
	}

	// Request fresh OTP after single-use consumption
	reqFresh := httptest.NewRequest(http.MethodPost, "/auth/email-change/request", bytes.NewReader(reqBody))
	reqFresh.Header.Set("Content-Type", "application/json")
	reqFresh.Header.Set("Authorization", "Bearer "+tokenA)
	recFresh := httptest.NewRecorder()
	a.RequestEmailChange(recFresh, reqFresh)

	if recFresh.Code != http.StatusOK {
		t.Fatalf("expected 200 for fresh email change request, got %d: %s", recFresh.Code, recFresh.Body.String())
	}

	var freshResp map[string]any
	json.Unmarshal(recFresh.Body.Bytes(), &freshResp)
	freshOTP := freshResp["dev_otp"].(string)

	// 6. Confirm with valid OTP (Happy Path Confirm)
	confirmValidBody, _ := json.Marshal(models.EmailChangeConfirmRequest{OTP: freshOTP})
	reqConfirm := httptest.NewRequest(http.MethodPost, "/auth/email-change/confirm", bytes.NewReader(confirmValidBody))
	reqConfirm.Header.Set("Content-Type", "application/json")
	reqConfirm.Header.Set("Authorization", "Bearer "+tokenA)
	recConfirm := httptest.NewRecorder()
	a.ConfirmEmailChange(recConfirm, reqConfirm)

	if recConfirm.Code != http.StatusOK {
		t.Fatalf("expected 200 for valid OTP confirm, got %d: %s", recConfirm.Code, recConfirm.Body.String())
	}

	var confirmResp map[string]any
	if err := json.Unmarshal(recConfirm.Body.Bytes(), &confirmResp); err != nil {
		t.Fatalf("failed to decode confirm response: %v", err)
	}

	newToken, ok := confirmResp["token"].(string)
	if !ok || newToken == "" {
		t.Errorf("expected fresh token in confirm response, got %v", confirmResp)
	}

	// Verify database state updated
	dbUser := s.GetByID(ctx, userA.ID)
	if dbUser.Email != newEmail {
		t.Errorf("expected user email in DB to be %s, got %s", newEmail, dbUser.Email)
	}

	// 7. Verify pending email change record consumed
	pendingAfter := s.GetPendingEmailChange(ctx, userA.ID)
	if pendingAfter != nil {
		t.Errorf("expected pending email change record to be consumed, but it still exists")
	}

	// 8. Test Rate Limiting on Email Change Request
	// Trigger failures to lock rate limiter
	for i := 0; i < 6; i++ {
		a.limiter.RecordFailure(userA.ID)
	}
	reqRateLimited := httptest.NewRequest(http.MethodPost, "/auth/email-change/request", bytes.NewBufferString(`{"new_email":"another@example.com"}`))
	reqRateLimited.Header.Set("Content-Type", "application/json")
	reqRateLimited.Header.Set("Authorization", "Bearer "+tokenA)
	recRateLimited := httptest.NewRecorder()
	a.RequestEmailChange(recRateLimited, reqRateLimited)
	if recRateLimited.Code != http.StatusTooManyRequests {
		t.Errorf("expected 429 Too Many Requests for rate limited user, got %d", recRateLimited.Code)
	}
}

func TestEmailChange_ExpiredOTP(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	cipher, err := otpcrypto.NewCipher("", "local")
	if err != nil {
		t.Fatalf("failed to create cipher: %v", err)
	}

	dbName := fmt.Sprintf("saas_platform_email_change_exp_test_%d", time.Now().UnixNano())
	s, err := store.NewMongoDB(ctx, mongoURI, dbName, cipher)
	if err != nil {
		t.Skipf("Skipping auth-service integration test: MongoDB not available (%v)", err)
		return
	}
	defer func() {
		_ = s.DropDatabase(context.Background())
		s.Close(context.Background())
	}()

	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	cfg := &config.Config{AppEnv: "local", GatewaySecret: "test-gateway-secret", InternalServiceToken: "test-internal-token-123"}
	mockStorage, _ := storage.NewLocalStorage(t.TempDir(), "/api/v1", os.Getenv("JWT_SECRET"))
	a := NewAuth(s, &mockOTPDispatcher{}, cfg, rdb, mockStorage)

	user := &models.User{
		ID:        "user_exp_123",
		Email:     "userexp@example.com",
		Username:  "userexp",
		Role:      models.RoleUser,
		IsActive:  true,
		CreatedAt: time.Now().UTC(),
	}
	if err := s.CreateUser(ctx, user); err != nil {
		t.Fatalf("failed to create user: %v", err)
	}

	token, _ := jwtutil.GenerateToken(user.ID, string(user.Role), user.TenantID, user.Email)

	// Create an expired pending record directly in store
	pending := &models.PendingEmailChange{
		UserID:       user.ID,
		OldEmail:     user.Email,
		NewEmail:     "newexp@example.com",
		OTPExpiresAt: time.Now().Add(-10 * time.Minute), // expired
	}
	if err := s.SetPendingEmailChange(ctx, user.ID, pending, "123456"); err != nil {
		t.Fatalf("failed to set pending email change: %v", err)
	}

	// Try confirming expired OTP
	confirmBody, _ := json.Marshal(models.EmailChangeConfirmRequest{OTP: "123456"})
	req := httptest.NewRequest(http.MethodPost, "/auth/email-change/confirm", bytes.NewReader(confirmBody))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	a.ConfirmEmailChange(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Errorf("expected 401 for expired OTP, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestEmailChange_ConcurrentConfirmRace(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://root:devpassword123@localhost:27017/saas_platform?authSource=admin"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	cipher, err := otpcrypto.NewCipher("", "local")
	if err != nil {
		t.Fatalf("failed to create cipher: %v", err)
	}

	dbName := fmt.Sprintf("saas_platform_email_change_race_test_%d", time.Now().UnixNano())
	s, err := store.NewMongoDB(ctx, mongoURI, dbName, cipher)
	if err != nil {
		t.Skipf("Skipping auth-service integration test: MongoDB not available (%v)", err)
		return
	}
	defer func() {
		_ = s.DropDatabase(context.Background())
		s.Close(context.Background())
	}()

	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	cfg := &config.Config{AppEnv: "local", GatewaySecret: "test-gateway-secret", InternalServiceToken: "test-internal-token-123"}
	mockStorage, _ := storage.NewLocalStorage(t.TempDir(), "/api/v1", os.Getenv("JWT_SECRET"))
	a := NewAuth(s, &mockOTPDispatcher{}, cfg, rdb, mockStorage)

	user := &models.User{
		ID:        "user_race_123",
		Email:     "user_race@example.com",
		Username:  "user_race",
		Role:      models.RoleUser,
		IsActive:  true,
		CreatedAt: time.Now().UTC(),
	}
	if err := s.CreateUser(ctx, user); err != nil {
		t.Fatalf("failed to create user: %v", err)
	}

	token, _ := jwtutil.GenerateToken(user.ID, string(user.Role), user.TenantID, user.Email)

	// Step 1: Request email change to obtain dev_otp
	newEmail := "user_race_new@example.com"
	reqBody, _ := json.Marshal(models.EmailChangeRequest{NewEmail: newEmail})
	req := httptest.NewRequest(http.MethodPost, "/auth/email-change/request", bytes.NewReader(reqBody))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	a.RequestEmailChange(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 for email change request, got %d: %s", rec.Code, rec.Body.String())
	}

	var reqResp map[string]any
	json.Unmarshal(rec.Body.Bytes(), &reqResp)
	otp := reqResp["dev_otp"].(string)

	// Step 2: Fire two concurrent confirm requests with the exact same valid OTP
	var wg sync.WaitGroup
	start := make(chan struct{})
	codes := make([]int, 2)

	for i := 0; i < 2; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			confirmBody, _ := json.Marshal(models.EmailChangeConfirmRequest{OTP: otp})
			reqConfirm := httptest.NewRequest(http.MethodPost, "/auth/email-change/confirm", bytes.NewReader(confirmBody))
			reqConfirm.Header.Set("Content-Type", "application/json")
			reqConfirm.Header.Set("Authorization", "Bearer "+token)
			reqConfirm.RemoteAddr = fmt.Sprintf("192.168.1.%d:12345", idx+1)
			recConfirm := httptest.NewRecorder()

			<-start
			a.ConfirmEmailChange(recConfirm, reqConfirm)
			codes[idx] = recConfirm.Code
		}(i)
	}

	close(start)
	wg.Wait()

	// Assert exactly one request succeeded (200 OK) and the other failed (401 Unauthorized / not found)
	successCount := 0
	for _, code := range codes {
		if code == http.StatusOK {
			successCount++
		}
	}

	if successCount != 1 {
		t.Errorf("expected exactly 1 successful confirm request, got %d (codes: %v)", successCount, codes)
	}

	// Verify database updated to new email
	dbUser := s.GetByID(ctx, user.ID)
	if dbUser.Email != newEmail {
		t.Errorf("expected user email to be %s, got %s", newEmail, dbUser.Email)
	}
}
