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

func TestServiceCreate_SavesAndReturnsEveryField(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://root:devpassword123@localhost:27017/saas_platform?authSource=admin"
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	dbName := fmt.Sprintf("saas_user_create_fields_%d", time.Now().UnixNano())
	s, err := store.NewMongoDB(ctx, mongoURI, dbName)
	if err != nil {
		t.Skipf("Skipping: MongoDB not available (%v)", err)
	}
	t.Cleanup(func() {
		_ = s.DropDatabase(context.Background())
		_ = s.Close(context.Background())
	})

	ownerID := "create-fields-owner"
	if err := s.UpsertSubscription(ctx, &models.Subscription{
		TenantID:  ownerID,
		Tier:      models.PlanPaid,
		ExpiresAt: time.Now().Add(24 * time.Hour),
	}); err != nil {
		t.Fatalf("seed subscription: %v", err)
	}

	auth := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{
			"id":         ownerID,
			"role":       "owner",
			"kyc_status": "approved",
			"is_active":  true,
			"tenant_id":  ownerID,
		})
	}))
	t.Cleanup(auth.Close)

	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	t.Cleanup(func() { _ = rdb.Close() })

	cfg := &config.Config{
		AuthServiceURL:       auth.URL,
		InternalServiceToken: "mock-internal-token",
		AppEnv:               "test",
		JWTSecret:            os.Getenv("JWT_SECRET"),
	}
	u := NewUserService(s, cfg, rdb)
	ownerToken, _ := jwtutil.GenerateToken(ownerID, "owner", ownerID, "owner@example.com")

	mux := http.NewServeMux()
	u.RegisterRoutes(mux)

	// 1. Create service with same_daily schedule and all fields
	createPayload := map[string]any{
		"owner_token":         ownerToken,
		"name":                "Super Delivery Express",
		"category":            "delivery",
		"tenant_base_price":   30.0,
		"tenant_price_per_km": 3.0,
		"latitude":            30.0444,
		"longitude":           31.2357,
		"photo_url":           "services/owner1/store.jpg",
		"address":             "456 Tahrir Square, Downtown, Cairo",
		"working_hours":       "Daily 8am-10pm",
		"coverage_radius_km":  25.5,
		"schedule_mode":       "same_daily",
		"open_time":           "08:00",
		"close_time":          "22:00",
		"timezone":            "Africa/Cairo",
	}

	bodyBytes, _ := json.Marshal(createPayload)
	req := httptest.NewRequest("POST", "/users/services", bytes.NewReader(bodyBytes))
	req.Header.Set("Authorization", "Bearer "+ownerToken)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201 Created, got %d: %s", rec.Code, rec.Body.String())
	}

	var createResp struct {
		Message string         `json:"message"`
		Service models.Service `json:"service"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &createResp); err != nil {
		t.Fatalf("unmarshal create response: %v", err)
	}

	svc := createResp.Service
	if svc.ID == "" {
		t.Fatalf("expected service ID to be generated")
	}
	if svc.Address != "456 Tahrir Square, Downtown, Cairo" {
		t.Errorf("create resp address = %q, want '456 Tahrir Square, Downtown, Cairo'", svc.Address)
	}
	if svc.CoverageRadiusKM != 25.5 {
		t.Errorf("create resp coverage_radius_km = %v, want 25.5", svc.CoverageRadiusKM)
	}
	if svc.WorkingHours != "Daily 8am-10pm" {
		t.Errorf("create resp working_hours = %q, want 'Daily 8am-10pm'", svc.WorkingHours)
	}
	if svc.ScheduleMode != "same_daily" {
		t.Errorf("create resp schedule_mode = %q, want 'same_daily'", svc.ScheduleMode)
	}
	if svc.OpenTime != "08:00" || svc.CloseTime != "22:00" {
		t.Errorf("create resp open/close time = %s-%s, want 08:00-22:00", svc.OpenTime, svc.CloseTime)
	}
	if svc.PhotoURL != "services/owner1/store.jpg" {
		t.Errorf("create resp photo_url = %q, want 'services/owner1/store.jpg'", svc.PhotoURL)
	}
	if svc.Timezone != "Africa/Cairo" {
		t.Errorf("create resp timezone = %q, want 'Africa/Cairo'", svc.Timezone)
	}

	// 2. GET by ID via ?id=<id>
	getReq := httptest.NewRequest("GET", "/users/services?id="+svc.ID, nil)
	getRec := httptest.NewRecorder()
	mux.ServeHTTP(getRec, getReq)

	if getRec.Code != http.StatusOK {
		t.Fatalf("GET /users/services?id= expected 200, got %d: %s", getRec.Code, getRec.Body.String())
	}

	var getResp struct {
		Service models.Service `json:"service"`
	}
	if err := json.Unmarshal(getRec.Body.Bytes(), &getResp); err != nil {
		t.Fatalf("unmarshal GET response: %v", err)
	}

	retrieved := getResp.Service
	if retrieved.ID != svc.ID {
		t.Errorf("retrieved ID = %q, want %q", retrieved.ID, svc.ID)
	}
	if retrieved.Address != "456 Tahrir Square, Downtown, Cairo" {
		t.Errorf("retrieved address = %q, want '456 Tahrir Square, Downtown, Cairo'", retrieved.Address)
	}
	if retrieved.CoverageRadiusKM != 25.5 {
		t.Errorf("retrieved coverage_radius_km = %v, want 25.5", retrieved.CoverageRadiusKM)
	}
	if retrieved.WorkingHours != "Daily 8am-10pm" {
		t.Errorf("retrieved working_hours = %q, want 'Daily 8am-10pm'", retrieved.WorkingHours)
	}
	if retrieved.ScheduleMode != "same_daily" {
		t.Errorf("retrieved schedule_mode = %q, want 'same_daily'", retrieved.ScheduleMode)
	}
	if retrieved.OpenTime != "08:00" || retrieved.CloseTime != "22:00" {
		t.Errorf("retrieved open/close time = %s-%s, want 08:00-22:00", retrieved.OpenTime, retrieved.CloseTime)
	}
	if retrieved.PhotoURL != "services/owner1/store.jpg" {
		t.Errorf("retrieved photo_url = %q, want 'services/owner1/store.jpg'", retrieved.PhotoURL)
	}
	if retrieved.Timezone != "Africa/Cairo" {
		t.Errorf("retrieved timezone = %q, want 'Africa/Cairo'", retrieved.Timezone)
	}

	// 3. GET by path: /users/services/{id}
	getPathReq := httptest.NewRequest("GET", "/users/services/"+svc.ID, nil)
	getPathRec := httptest.NewRecorder()
	mux.ServeHTTP(getPathRec, getPathReq)

	if getPathRec.Code != http.StatusOK {
		t.Fatalf("GET /users/services/{id} expected 200, got %d: %s", getPathRec.Code, getPathRec.Body.String())
	}

	// 4. Test aliases: "photo" and "coverage_radius"
	aliasPayload := map[string]any{
		"owner_token":         ownerToken,
		"name":                "Alias Fields Service",
		"category":            "shipping",
		"tenant_base_price":   40.0,
		"tenant_price_per_km": 4.0,
		"latitude":            30.0444,
		"longitude":           31.2357,
		"photo":               "services/owner1/alias_store.jpg",
		"coverage_radius":     18.0,
		"address":             "789 Pyramids Rd, Giza",
	}
	aliasBytes, _ := json.Marshal(aliasPayload)
	aliasReq := httptest.NewRequest("POST", "/users/services", bytes.NewReader(aliasBytes))
	aliasReq.Header.Set("Authorization", "Bearer "+ownerToken)
	aliasRec := httptest.NewRecorder()
	mux.ServeHTTP(aliasRec, aliasReq)

	if aliasRec.Code != http.StatusCreated {
		t.Fatalf("alias create expected 201, got %d: %s", aliasRec.Code, aliasRec.Body.String())
	}
	var aliasResp struct {
		Service models.Service `json:"service"`
	}
	_ = json.Unmarshal(aliasRec.Body.Bytes(), &aliasResp)
	if aliasResp.Service.PhotoURL != "services/owner1/alias_store.jpg" {
		t.Errorf("alias photo = %q, want 'services/owner1/alias_store.jpg'", aliasResp.Service.PhotoURL)
	}
	if aliasResp.Service.CoverageRadiusKM != 18.0 {
		t.Errorf("alias coverage_radius = %v, want 18.0", aliasResp.Service.CoverageRadiusKM)
	}
}
