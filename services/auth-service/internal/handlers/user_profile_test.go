package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
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

func TestUpdateProfile_SelfServiceAndSecurity(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	cipher, err := otpcrypto.NewCipher("", "local")
	if err != nil {
		t.Fatalf("failed to create cipher: %v", err)
	}

	dbName := fmt.Sprintf("saas_platform_user_profile_test_%d", time.Now().UnixNano())
	s, err := store.NewMongoDB(ctx, mongoURI, dbName, cipher)
	if err != nil {
		t.Skipf("Skipping auth-service user profile integration tests: MongoDB not available at %s (%v)", mongoURI, err)
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
	mockDispatcher := &mockOTPDispatcher{}

	a := NewAuth(s, mockDispatcher, cfg, rdb, mockStorage)

	userA := &models.User{
		ID:        "usr-profile-a",
		Email:     "userA@example.com",
		Username:  "user_a_orig",
		Role:      models.RoleUser,
		IsActive:  true,
		KYCStatus: models.KYCNone,
		CreatedAt: time.Now(),
	}
	if err := s.CreateUser(ctx, userA); err != nil {
		t.Fatalf("failed to seed userA: %v", err)
	}

	userB := &models.User{
		ID:        "usr-profile-b",
		Email:     "userB@example.com",
		Username:  "user_b_orig",
		Role:      models.RoleUser,
		IsActive:  true,
		KYCStatus: models.KYCNone,
		CreatedAt: time.Now(),
	}
	if err := s.CreateUser(ctx, userB); err != nil {
		t.Fatalf("failed to seed userB: %v", err)
	}

	tokenA, err := jwtutil.GenerateToken(userA.ID, string(userA.Role), userA.ID, userA.Email)
	if err != nil {
		t.Fatalf("failed to generate tokenA: %v", err)
	}

	tokenB, err := jwtutil.GenerateToken(userB.ID, string(userB.Role), userB.ID, userB.Email)
	if err != nil {
		t.Fatalf("failed to generate tokenB: %v", err)
	}

	// 1. Successful Profile Update (username, phone, frequent_addresses)
	t.Run("Successful Profile Update", func(t *testing.T) {
		reqPayload := map[string]any{
			"username": "user_a_updated",
			"phone":    "+201012345678",
			"frequent_addresses": []string{
				"123 Nile St, Cairo",
				"456 Pyramids Rd, Giza",
			},
		}
		bodyBytes, _ := json.Marshal(reqPayload)
		req := httptest.NewRequest(http.MethodPatch, "/auth/user", bytes.NewReader(bodyBytes))
		req.Header.Set("Authorization", "Bearer "+tokenA)
		rec := httptest.NewRecorder()

		a.UpdateProfile(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK for profile update, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		// Verify database state directly
		fetched := s.GetByID(ctx, userA.ID)
		if fetched == nil {
			t.Fatalf("User A missing from database after update")
		}
		if fetched.Username != "user_a_updated" {
			t.Errorf("Expected updated username 'user_a_updated', got '%s'", fetched.Username)
		}
		if fetched.Phone != "+201012345678" {
			t.Errorf("Expected updated phone '+201012345678', got '%s'", fetched.Phone)
		}
		if len(fetched.FrequentAddresses) != 2 || fetched.FrequentAddresses[0] != "123 Nile St, Cairo" {
			t.Errorf("Expected frequent_addresses ['123 Nile St, Cairo', '456 Pyramids Rd, Giza'], got %v", fetched.FrequentAddresses)
		}

		// Also verify GET /auth/user returns the new fields
		reqGet := httptest.NewRequest(http.MethodGet, "/auth/user?user_token="+tokenA, nil)
		recGet := httptest.NewRecorder()
		a.GetUser(recGet, reqGet)
		if recGet.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK for GET /auth/user, got %d. Body: %s", recGet.Code, recGet.Body.String())
		}
		var getResp map[string]any
		_ = json.Unmarshal(recGet.Body.Bytes(), &getResp)
		if getResp["phone"] != "+201012345678" {
			t.Errorf("Expected GET /auth/user to include phone '+201012345678', got %v", getResp["phone"])
		}
	})

	// 2. IDOR Protection Test: Attempting to update User B's profile using User A's token MUST fail with 403
	t.Run("IDOR Protection: Mismatched User ID in Body Fails with 403", func(t *testing.T) {
		reqPayload := map[string]any{
			"user_id":  userB.ID, // Mismatched target user
			"username": "hacked_user_b",
		}
		bodyBytes, _ := json.Marshal(reqPayload)
		req := httptest.NewRequest(http.MethodPatch, "/auth/user", bytes.NewReader(bodyBytes))
		req.Header.Set("Authorization", "Bearer "+tokenA) // User A token
		rec := httptest.NewRecorder()

		a.UpdateProfile(rec, req)

		if rec.Code != http.StatusForbidden {
			t.Fatalf("IDOR SECURITY DEFECT: Expected 403 Forbidden when User A attempts to update User B via user_id in body, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		// Confirm User B's profile was NOT modified
		fetchedB := s.GetByID(ctx, userB.ID)
		if fetchedB.Username == "hacked_user_b" {
			t.Fatalf("IDOR CRITICAL VULNERABILITY: User B's username was mutated by User A!")
		}

		// Test mismatched user_token in body
		reqPayload2 := map[string]any{
			"user_token": tokenB, // User B token in body while header is User A
			"username":   "hacked_user_b_v2",
		}
		bodyBytes2, _ := json.Marshal(reqPayload2)
		req2 := httptest.NewRequest(http.MethodPatch, "/auth/user", bytes.NewReader(bodyBytes2))
		req2.Header.Set("Authorization", "Bearer "+tokenA)
		rec2 := httptest.NewRecorder()

		a.UpdateProfile(rec2, req2)

		if rec2.Code != http.StatusForbidden {
			t.Fatalf("IDOR SECURITY DEFECT: Expected 403 Forbidden when passing mismatched user_token in body, got %d", rec2.Code)
		}
	})

	// 3. Sensitive Field Smuggling: Attempting to update email/password/role/kyc_status MUST be ignored
	t.Run("Sensitive Field Smuggling Attempts Ignored", func(t *testing.T) {
		reqPayload := map[string]any{
			"email":      "hacked_email@example.com",
			"password":   "hacked_password123",
			"role":       "owner",
			"kyc_status": "approved",
			"is_active":  false,
			"username":   "user_a_legit_update",
		}
		bodyBytes, _ := json.Marshal(reqPayload)
		req := httptest.NewRequest(http.MethodPatch, "/auth/user", bytes.NewReader(bodyBytes))
		req.Header.Set("Authorization", "Bearer "+tokenA)
		rec := httptest.NewRecorder()

		a.UpdateProfile(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK for partial profile update with ignored sensitive fields, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		// Verify that sensitive fields were NOT changed
		fetched := s.GetByID(ctx, userA.ID)
		if fetched.Email != "userA@example.com" {
			t.Errorf("SECURITY DEFECT: User email was mutated via PATCH payload! Expected userA@example.com, got %s", fetched.Email)
		}
		if fetched.Role != models.RoleUser {
			t.Errorf("SECURITY DEFECT: User role was escalated via PATCH payload! Expected user, got %s", fetched.Role)
		}
		if fetched.KYCStatus != models.KYCNone {
			t.Errorf("SECURITY DEFECT: User kyc_status was escalated via PATCH payload! Got %s", fetched.KYCStatus)
		}
		if !fetched.IsActive {
			t.Errorf("SECURITY DEFECT: User is_active was mutated via PATCH payload!")
		}
		if fetched.Username != "user_a_legit_update" {
			t.Errorf("Expected legitimate username update to 'user_a_legit_update', got '%s'", fetched.Username)
		}
	})

	// 4. Frequent Addresses Length Validation (> 10 entries fails with 400)
	t.Run("Frequent Addresses Exceeding 10 Entries Fails", func(t *testing.T) {
		tooManyAddresses := make([]string, 11)
		for i := 0; i < 11; i++ {
			tooManyAddresses[i] = fmt.Sprintf("Address #%d", i+1)
		}

		reqPayload := map[string]any{
			"frequent_addresses": tooManyAddresses,
		}
		bodyBytes, _ := json.Marshal(reqPayload)
		req := httptest.NewRequest(http.MethodPatch, "/auth/user", bytes.NewReader(bodyBytes))
		req.Header.Set("Authorization", "Bearer "+tokenA)
		rec := httptest.NewRecorder()

		a.UpdateProfile(rec, req)

		if rec.Code != http.StatusBadRequest {
			t.Fatalf("Expected 400 Bad Request when frequent_addresses exceeds 10 entries, got %d. Body: %s", rec.Code, rec.Body.String())
		}
	})
}
