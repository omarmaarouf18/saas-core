package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
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
)

func setupAuthReproTest(t *testing.T) (*Auth, *store.MongoDB, func()) {
	t.Helper()
	secret := "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2"
	os.Setenv("JWT_SECRET", secret)
	jwtutil.Init(secret)

	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://root:devpassword123@localhost:27017/?authSource=admin"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	cipher, err := otpcrypto.NewCipher("", "local")
	if err != nil {
		t.Fatalf("failed to create cipher: %v", err)
	}

	dbName := fmt.Sprintf("auth_repro_test_%d", time.Now().UnixNano())
	s, err := store.NewMongoDB(ctx, mongoURI, dbName, cipher)
	if err != nil {
		t.Skipf("Skipping auth repro tests: MongoDB not available: %v", err)
		return nil, nil, nil
	}

	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})

	cfg := &config.Config{
		AppEnv:               "local",
		GatewaySecret:        "test-gateway-secret",
		InternalServiceToken: "test-internal-token-123",
	}
	mockStorage, _ := storage.NewLocalStorage(t.TempDir(), "/api/v1", secret, "", "test")
	mockDispatcher := &mockOTPDispatcher{}

	a := NewAuth(s, mockDispatcher, cfg, rdb, mockStorage)

	cleanup := func() {
		_ = s.DropDatabase(context.Background())
		_ = s.Close(context.Background())
		_ = rdb.Close()
		mr.Close()
	}

	return a, s, cleanup
}

func TestRepro_Q20_Signup_InvalidEmailFormat(t *testing.T) {
	a, _, cleanup := setupAuthReproTest(t)
	if a == nil {
		return
	}
	defer cleanup()

	// Invalid email without '@' or domain
	reqBody, _ := json.Marshal(map[string]any{
		"email":    "completely-invalid-email",
		"password": "Password123!",
		"username": "validuser",
		"role":     "user",
	})

	req := httptest.NewRequest(http.MethodPost, "/auth/signup", bytes.NewReader(reqBody))
	rec := httptest.NewRecorder()

	a.Signup(rec, req)

	// Pre-fix: succeeds with 200 OK or 201 (accepts junk email)
	// Post-fix: must reject with 400 Bad Request
	if rec.Code == http.StatusOK || rec.Code == http.StatusCreated {
		t.Errorf("REPRO CONFIRMED Q20: Signup accepted invalid email 'completely-invalid-email' with status %d!", rec.Code)
	} else if rec.Code == http.StatusBadRequest {
		t.Logf("PASS: Signup rejected invalid email with 400 Bad Request")
	} else {
		t.Logf("Signup returned status %d: %s", rec.Code, rec.Body.String())
	}
}

func TestRepro_Q20_UpdateProfile_UsernameLengthBypass(t *testing.T) {
	a, s, cleanup := setupAuthReproTest(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	user := &models.User{
		ID:        "user-q20-uname",
		Email:     "userq20@test.com",
		Username:  "original",
		Role:      models.RoleUser,
		IsActive:  true,
		CreatedAt: time.Now().UTC(),
	}
	_ = s.CreateUser(ctx, user)

	token, _ := jwtutil.GenerateToken(user.ID, "user", "", user.Email)

	// Case 1: Username too short (2 chars, signup requires 3-30)
	reqBodyShort, _ := json.Marshal(map[string]any{
		"username": "ab",
	})
	reqShort := httptest.NewRequest(http.MethodPatch, "/auth/user", bytes.NewReader(reqBodyShort))
	reqShort.Header.Set("Authorization", "Bearer "+token)
	recShort := httptest.NewRecorder()

	a.UpdateProfile(recShort, reqShort)

	if recShort.Code == http.StatusOK {
		t.Errorf("REPRO CONFIRMED Q20: UpdateProfile accepted 2-character username 'ab' bypassing signup's 3-30 limit!")
	}

	// Case 2: Username too long (35 chars, signup requires 3-30)
	reqBodyLong, _ := json.Marshal(map[string]any{
		"username": strings.Repeat("u", 35),
	})
	reqLong := httptest.NewRequest(http.MethodPatch, "/auth/user", bytes.NewReader(reqBodyLong))
	reqLong.Header.Set("Authorization", "Bearer "+token)
	recLong := httptest.NewRecorder()

	a.UpdateProfile(recLong, reqLong)

	if recLong.Code == http.StatusOK {
		t.Errorf("REPRO CONFIRMED Q20: UpdateProfile accepted 35-character username bypassing signup's 3-30 limit!")
	}
}

func TestRepro_Q20_UpdateProfile_UnboundedFrequentAddress(t *testing.T) {
	a, s, cleanup := setupAuthReproTest(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	user := &models.User{
		ID:        "user-q20-addr",
		Email:     "addr@test.com",
		Username:  "addruser",
		Role:      models.RoleUser,
		IsActive:  true,
		CreatedAt: time.Now().UTC(),
	}
	_ = s.CreateUser(ctx, user)

	token, _ := jwtutil.GenerateToken(user.ID, "user", "", user.Email)

	// 10,000 character address string
	hugeAddr := strings.Repeat("Z", 10000)
	reqBody, _ := json.Marshal(map[string]any{
		"frequent_addresses": []string{hugeAddr},
	})
	req := httptest.NewRequest(http.MethodPatch, "/auth/user", bytes.NewReader(reqBody))
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()

	a.UpdateProfile(rec, req)

	if rec.Code == http.StatusOK {
		t.Errorf("REPRO CONFIRMED Q20: UpdateProfile accepted 10,000 character unbounded frequent address entry!")
	}
}

func TestRepro_Q20_AuditAction_UnboundedActionString(t *testing.T) {
	a, s, cleanup := setupAuthReproTest(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	owner := &models.User{
		ID:        "owner-q20-audit",
		Email:     "owner-audit@test.com",
		Username:  "owneraudit",
		Role:      models.RoleOwner,
		KYCStatus: models.KYCApproved,
		IsActive:  true,
	}
	_ = s.CreateUser(ctx, owner)

	emp := &models.User{
		ID:       "emp-q20-audit",
		Email:    "emp-audit@test.com",
		Username: "empaudit",
		Role:     models.RoleEmployee,
		OwnerID:  owner.ID,
		IsActive: true,
	}
	_ = s.CreateUser(ctx, emp)

	token, _ := jwtutil.GenerateToken(emp.ID, "employee", owner.ID, emp.Email)

	// 10,000 character action string
	hugeAction := strings.Repeat("ACT_", 2500)
	reqBody, _ := json.Marshal(map[string]any{
		"email":  emp.Email,
		"action": hugeAction,
	})
	req := httptest.NewRequest(http.MethodPost, "/auth/employee/audit", bytes.NewReader(reqBody))
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()

	a.SimulateEmployeeAction(rec, req)
	if rec.Code == http.StatusOK {
		t.Errorf("REPRO CONFIRMED Q20: SimulateEmployeeAction accepted 10,000 character unbounded action string with 200 OK!")
	}
}
