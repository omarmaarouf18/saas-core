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
	"github.com/project/shared/infra/jwtutil"
	"github.com/project/user-service/internal/config"
	"github.com/project/user-service/internal/models"
	"github.com/project/user-service/internal/store"
	"github.com/redis/go-redis/v9"
)

// TestOwnerConfigurationSave_ReproLiveError reproduces the exact HTTP request
// sent by the Flutter client's owner_configuration_screen.dart (_submitForm -> updateOwnerServiceConfig).
func TestOwnerConfigurationSave_ReproLiveError(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	dbName := fmt.Sprintf("saas_platform_test_%d", time.Now().UnixNano())
	s, err := store.NewMongoDB(ctx, mongoURI, dbName)
	if err != nil {
		t.Skipf("Skipping integration test: MongoDB not available at %s (%v)", mongoURI, err)
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

	mockAuthServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		id := r.URL.Query().Get("id")
		w.WriteHeader(http.StatusOK)
		_ = json.NewEncoder(w).Encode(map[string]any{
			"id":         id,
			"role":       "owner",
			"kyc_status": "approved",
			"is_active":  true,
			"tenant_id":  id,
		})
	}))
	defer mockAuthServer.Close()

	cfg := &config.Config{
		AuthServiceURL: mockAuthServer.URL,
		ChatServiceURL: mockAuthServer.URL,
		AppEnv:         "local",
	}
	u := NewUserService(s, cfg, rdb)

	ownerID := "owner-config-123"
	ownerToken, _ := jwtutil.GenerateToken(ownerID, "owner", ownerID, "owner@example.com")

	// Seed existing service in DB
	svc := &models.Service{
		ID:               "svc-config-777",
		TenantID:         ownerID,
		Name:             "Initial Service Name",
		Category:         "delivery",
		BasePrice:        10.0,
		TenantBasePrice:  10.0,
		TenantPricePerKM: 1.0,
		Latitude:         30.0444,
		Longitude:        31.2357,
	}
	s.CreateService(ctx, svc)

	// Build the exact payload that ownerProvider.updateOwnerServiceConfig sends:
	// Notice that the Flutter frontend passes user.id (the raw ID "owner-config-123") in owner_id,
	// and ApiClient sends the JWT in Authorization: Bearer <ownerToken> header.
	payload := map[string]any{
		"service_id":          "svc-config-777",
		"owner_id":            ownerID, // raw user.id
		"name":                "Updated Business Name",
		"category":            "delivery",
		"tenant_base_price":   15.0,
		"tenant_price_per_km": 2.0,
		"photo_url":           "https://example.com/photo.png",
		"address":             "123 Street",
		"working_hours":       "9am-5pm",
		"coverage_radius_km":  25.0,
		"latitude":            30.0444,
		"longitude":           31.2357,
	}

	bodyBytes, _ := json.Marshal(payload)
	req := httptest.NewRequest(http.MethodPut, "/users/services", bytes.NewReader(bodyBytes))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+ownerToken)

	rec := httptest.NewRecorder()
	u.UpdateService(rec, req)

	t.Logf("REPRO CAPTURE (UpdateService) -> Status Code: %d", rec.Code)
	t.Logf("REPRO CAPTURE (UpdateService) -> Response Body: %s", rec.Body.String())
	if rec.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK for UpdateService, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// Now also test CreateService path (when _existingService is null)
	createPayload := map[string]any{
		"owner_id":            ownerID, // raw user.id
		"name":                "New Business Name",
		"category":            "delivery",
		"tenant_base_price":   10.0,
		"tenant_price_per_km": 1.5,
		"latitude":            30.0444,
		"longitude":           31.2357,
	}
	createBytes, _ := json.Marshal(createPayload)
	createReq := httptest.NewRequest(http.MethodPost, "/users/services", bytes.NewReader(createBytes))
	createReq.Header.Set("Content-Type", "application/json")
	createReq.Header.Set("Authorization", "Bearer "+ownerToken)

	createRec := httptest.NewRecorder()
	u.CreateService(createRec, createReq)

	t.Logf("REPRO CAPTURE (CreateService) -> Status Code: %d", createRec.Code)
	t.Logf("REPRO CAPTURE (CreateService) -> Response Body: %s", createRec.Body.String())
	if createRec.Code != http.StatusCreated {
		t.Fatalf("Expected 201 Created for CreateService, got %d. Body: %s", createRec.Code, createRec.Body.String())
	}
}
