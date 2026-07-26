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
	"github.com/project/shared/infra/jwtutil"
	"github.com/project/user-service/internal/config"
	"github.com/project/user-service/internal/store"
	"github.com/redis/go-redis/v9"
)

func setupTestUserService(t *testing.T) (*UserService, *store.MongoDB, func()) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	jwtutil.Init("z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")

	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	dbName := fmt.Sprintf("saas_user_handlers_test_%d", time.Now().UnixNano())
	s, err := store.NewMongoDB(ctx, mongoURI, dbName)
	if err != nil {
		t.Skipf("Skipping user-service handler tests: MongoDB not available at %s (%v)", mongoURI, err)
		return nil, nil, nil
	}

	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}

	mockAuthServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id := r.URL.Query().Get("id")
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]any{
			"id":         id,
			"role":       "owner",
			"kyc_status": "approved",
			"is_active":  true,
			"tenant_id":  id,
		})
	}))

	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	cfg := &config.Config{
		AppEnv:               "test",
		AuthServiceURL:       mockAuthServer.URL,
		ChatServiceURL:       "http://localhost:8082",
		InternalServiceToken: "test-internal-token",
	}

	svc := NewUserService(s, cfg, rdb)

	cleanup := func() {
		mockAuthServer.Close()
		rdb.Close()
		mr.Close()
		cleanupCtx, cCancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cCancel()
		_ = s.DropDatabase(cleanupCtx)
		_ = s.Close(cleanupCtx)
	}

	return svc, s, cleanup
}

func TestRegisterRoutes(t *testing.T) {
	svc, _, cleanup := setupTestUserService(t)
	if svc == nil {
		return
	}
	defer cleanup()

	mux := http.NewServeMux()
	svc.RegisterRoutes(mux)

	routes := []struct {
		method string
		path   string
	}{
		{"GET", "/users/services"},
		{"POST", "/users/services"},
		{"POST", "/users/jobs/track"},
		{"GET", "/users/jobs/get"},
		{"POST", "/users/jobs/complete"},
		{"POST", "/users/jobs/cancel"},
		{"GET", "/users/wallet"},
		{"POST", "/users/wallet/deposit"},
		{"GET", "/users/ledger"},
		{"GET", "/users/platform/config"},
		{"GET", "/users/subscription"},
		{"POST", "/users/subscription"},
		{"POST", "/users/jobs/rate"},
		{"GET", "/users/ratings"},
		{"POST", "/users/jobs/location/update"},
	}

	for _, r := range routes {
		req := httptest.NewRequest(r.method, r.path, nil)
		_, pattern := mux.Handler(req)
		if pattern == "" {
			t.Errorf("Expected pattern for %s %s, got empty", r.method, r.path)
		}
	}
}

func TestCreateService_ExtraEdgeCases(t *testing.T) {
	svc, _, cleanup := setupTestUserService(t)
	if svc == nil {
		return
	}
	defer cleanup()

	ownerToken, _ := jwtutil.GenerateToken("owner-1", "owner", "tenant-1", "owner@example.com")

	// 1. Malformed JSON -> 400 Bad Request
	req := httptest.NewRequest("POST", "/users/services", bytes.NewReader([]byte(`{"owner_id":`)))
	req.Header.Set("Authorization", "Bearer "+ownerToken)
	rec := httptest.NewRecorder()
	svc.CreateService(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("Expected 400 Bad Request for malformed JSON, got %d", rec.Code)
	}

	// 2. Missing required fields -> 400 Bad Request
	req = httptest.NewRequest("POST", "/users/services", bytes.NewReader([]byte(`{"owner_id":""}`)))
	req.Header.Set("Authorization", "Bearer "+ownerToken)
	rec = httptest.NewRecorder()
	svc.CreateService(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("Expected 400 Bad Request for missing required fields, got %d", rec.Code)
	}

	// 3. Invalid category -> 400 Bad Request
	body := fmt.Sprintf(`{"owner_id":%q,"name":"Test","category":"invalid_cat"}`, ownerToken)
	req = httptest.NewRequest("POST", "/users/services", bytes.NewReader([]byte(body)))
	req.Header.Set("Authorization", "Bearer "+ownerToken)
	rec = httptest.NewRecorder()
	svc.CreateService(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("Expected 400 Bad Request for invalid category, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// 4. Negative pricing -> 400 Bad Request
	body = fmt.Sprintf(`{"owner_id":%q,"name":"Test","category":"shipping","tenant_base_price":-10.0,"tenant_price_per_km":2.0}`, ownerToken)
	req = httptest.NewRequest("POST", "/users/services", bytes.NewReader([]byte(body)))
	req.Header.Set("Authorization", "Bearer "+ownerToken)
	rec = httptest.NewRecorder()
	svc.CreateService(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("Expected 400 Bad Request for negative base price, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	body = fmt.Sprintf(`{"owner_id":%q,"name":"Test","category":"shipping","tenant_base_price":10.0,"tenant_price_per_km":-2.0}`, ownerToken)
	req = httptest.NewRequest("POST", "/users/services", bytes.NewReader([]byte(body)))
	req.Header.Set("Authorization", "Bearer "+ownerToken)
	rec = httptest.NewRecorder()
	svc.CreateService(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("Expected 400 Bad Request for negative price per km, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// 5. Zero pricing (free service) -> Allowed (passes pricing validation)
	body = fmt.Sprintf(`{"owner_id":%q,"name":"Free Service","category":"shipping","tenant_base_price":0.0,"tenant_price_per_km":0.0}`, ownerToken)
	req = httptest.NewRequest("POST", "/users/services", bytes.NewReader([]byte(body)))
	req.Header.Set("Authorization", "Bearer "+ownerToken)
	rec = httptest.NewRecorder()
	svc.CreateService(rec, req)
	if rec.Code == http.StatusBadRequest && strings.Contains(rec.Body.String(), "invalid_pricing") {
		t.Errorf("Zero pricing should be allowed for free listings, got 400 invalid_pricing. Body: %s", rec.Body.String())
	}
}

func TestWalletDeposit_ExtraEdgeCases(t *testing.T) {
	svc, _, cleanup := setupTestUserService(t)
	if svc == nil {
		return
	}
	defer cleanup()

	ownerToken, _ := jwtutil.GenerateToken("owner-1", "owner", "t-1", "owner@example.com")

	// 1. Non-POST method -> 405 MethodNotAllowed
	req := httptest.NewRequest("GET", "/users/wallet/deposit", nil)
	rec := httptest.NewRecorder()
	svc.WalletDeposit(rec, req)
	if rec.Code != http.StatusMethodNotAllowed {
		t.Errorf("Expected 405 MethodNotAllowed, got %d", rec.Code)
	}

	// 2. Malformed JSON -> 400 Bad Request
	req = httptest.NewRequest("POST", "/users/wallet/deposit", bytes.NewReader([]byte(`{"tenant_id":`)))
	req.Header.Set("Authorization", "Bearer "+ownerToken)
	rec = httptest.NewRecorder()
	svc.WalletDeposit(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("Expected 400 Bad Request, got %d", rec.Code)
	}

	// 3. Negative / Zero deposit amount -> 400 Bad Request
	req = httptest.NewRequest("POST", "/users/wallet/deposit", bytes.NewReader([]byte(`{"tenant_id":"t-1","amount":0}`)))
	req.Header.Set("Authorization", "Bearer "+ownerToken)
	rec = httptest.NewRecorder()
	svc.WalletDeposit(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("Expected 400 Bad Request for 0 deposit amount, got %d", rec.Code)
	}

	// 4. Deposit blocked in production environment (400 Bad Request: payment gateway not yet integrated)
	svcProduction, _, pCleanup := setupTestUserService(t)
	if svcProduction != nil {
		defer pCleanup()
		svcProduction.appEnv = "production"

		prodOwnerToken, _ := jwtutil.GenerateToken("owner-prod", "owner", "t-prod", "owner@example.com")
		body := `{"tenant_id":"t-prod","amount":100}`
		req = httptest.NewRequest("POST", "/users/wallet/deposit", bytes.NewReader([]byte(body)))
		req.Header.Set("Authorization", "Bearer "+prodOwnerToken)
		rec = httptest.NewRecorder()
		svcProduction.WalletDeposit(rec, req)

		if rec.Code != http.StatusBadRequest {
			t.Errorf("Expected 400 Bad Request for deposit in production environment, got %d. Body: %s", rec.Code, rec.Body.String())
		}
	}
}

func TestSubscription_ExtraEdgeCases(t *testing.T) {
	svc, _, cleanup := setupTestUserService(t)
	if svc == nil {
		return
	}
	defer cleanup()

	ownerToken, _ := jwtutil.GenerateToken("owner-sub-1", "owner", "t-sub-1", "owner@example.com")

	// 1. GET non-existent subscription -> returns default Free tier
	req := httptest.NewRequest("GET", "/users/subscription?tenant_id=t-sub-1&tenant_token="+ownerToken, nil)
	req.Header.Set("Authorization", "Bearer "+ownerToken)
	rec := httptest.NewRecorder()
	svc.Subscription(rec, req)
	if rec.Code != http.StatusOK {
		t.Errorf("Expected 200 OK for subscription GET, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// 2. POST invalid tier -> 400 Bad Request
	body := `{"tenant_id":"t-sub-1","tier":"invalid_tier_xyz"}`
	req = httptest.NewRequest("POST", "/users/subscription", strings.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+ownerToken)
	rec = httptest.NewRecorder()
	svc.Subscription(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("Expected 400 Bad Request for invalid tier, got %d. Body: %s", rec.Code, rec.Body.String())
	}
}

func TestRateJob_ExtraEdgeCases(t *testing.T) {
	svc, _, cleanup := setupTestUserService(t)
	if svc == nil {
		return
	}
	defer cleanup()

	userToken, _ := jwtutil.GenerateToken("user-rate-1", "user", "tenant-1", "user@example.com")

	// 1. Non-POST method -> 405 MethodNotAllowed
	req := httptest.NewRequest("GET", "/users/jobs/rate", nil)
	rec := httptest.NewRecorder()
	svc.RateJob(rec, req)
	if rec.Code != http.StatusMethodNotAllowed {
		t.Errorf("Expected 405 MethodNotAllowed, got %d", rec.Code)
	}

	// 2. Invalid stars (0 or 6) -> 400 Bad Request
	body := `{"job_id":"j-1","stars":6}`
	req = httptest.NewRequest("POST", "/users/jobs/rate", strings.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+userToken)
	rec = httptest.NewRecorder()
	svc.RateJob(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("Expected 400 Bad Request for stars=6, got %d", rec.Code)
	}
}
