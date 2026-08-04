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
	"github.com/project/user-service/internal/models"
	"github.com/project/user-service/internal/store"
	"github.com/redis/go-redis/v9"
)

func TestService_OwnerConfigurationAndUpdates(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	dbName := fmt.Sprintf("saas_platform_owner_config_test_%d", time.Now().UnixNano())
	s, err := store.NewMongoDB(ctx, mongoURI, dbName)
	if err != nil {
		t.Skipf("Skipping user-service integration tests: MongoDB not available at %s (%v)", mongoURI, err)
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

		if strings.HasPrefix(id, "kyc-approved-owner") {
			w.WriteHeader(http.StatusOK)
			json.NewEncoder(w).Encode(map[string]any{
				"id":         id,
				"role":       "owner",
				"kyc_status": "approved",
				"is_active":  true,
				"tenant_id":  id,
			})
			return
		}

		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]any{
			"id":         id,
			"role":       "user",
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

	ownerID1 := "kyc-approved-owner-config-1"
	ownerToken1, err := jwtutil.GenerateToken(ownerID1, "owner", ownerID1, "owner1@example.com")
	if err != nil {
		t.Fatalf("failed to generate owner token: %v", err)
	}

	ownerID2 := "kyc-approved-owner-config-2"
	ownerToken2, err := jwtutil.GenerateToken(ownerID2, "owner", ownerID2, "owner2@example.com")
	if err != nil {
		t.Fatalf("failed to generate second owner token: %v", err)
	}

	// 1. CreateService with new Owner Configuration fields
	t.Run("CreateService with Owner Configuration fields", func(t *testing.T) {
		reqBody := models.CreateServiceRequest{
			OwnerToken:       ownerToken1,
			Name:             "Premium Express Logistics",
			Category:         "delivery",
			TenantBasePrice:  50.0,
			TenantPricePerKM: 3.5,
			Latitude:         30.0444,
			Longitude:        31.2357,
			PhotoURL:         "https://cdn.example.com/services/express.jpg",
			Address:          "123 Commerce St, Cairo, Egypt",
			WorkingHours:     "8:00 AM - 8:00 PM",
			CoverageRadiusKM: 25.0,
		}

		bodyBytes, _ := json.Marshal(reqBody)
		req := httptest.NewRequest(http.MethodPost, "/users/services", bytes.NewReader(bodyBytes))
		rec := httptest.NewRecorder()

		u.CreateService(rec, req)

		if rec.Code != http.StatusCreated {
			t.Fatalf("Expected 201 Created, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		var resp map[string]any
		_ = json.Unmarshal(rec.Body.Bytes(), &resp)

		svcMap, ok := resp["service"].(map[string]any)
		if !ok {
			t.Fatalf("Expected service object in response, got %v", resp)
		}

		if svcMap["photo_url"] != "https://cdn.example.com/services/express.jpg" {
			t.Errorf("Expected photo_url 'https://cdn.example.com/services/express.jpg', got %v", svcMap["photo_url"])
		}
		if svcMap["address"] != "123 Commerce St, Cairo, Egypt" {
			t.Errorf("Expected address '123 Commerce St, Cairo, Egypt', got %v", svcMap["address"])
		}
		if svcMap["working_hours"] != "8:00 AM - 8:00 PM" {
			t.Errorf("Expected working_hours '8:00 AM - 8:00 PM', got %v", svcMap["working_hours"])
		}
		if svcMap["coverage_radius_km"] != 25.0 {
			t.Errorf("Expected coverage_radius_km 25.0, got %v", svcMap["coverage_radius_km"])
		}
	})

	// 2. CreateService Backward Compatibility (omitting new fields)
	t.Run("CreateService Backward Compatibility (omitting new fields)", func(t *testing.T) {
		reqBody := models.CreateServiceRequest{
			OwnerToken:       ownerToken1,
			Name:             "Standard Transport",
			Category:         "transport",
			TenantBasePrice:  30.0,
			TenantPricePerKM: 2.0,
			Latitude:         30.0500,
			Longitude:        31.2400,
		}

		bodyBytes, _ := json.Marshal(reqBody)
		req := httptest.NewRequest(http.MethodPost, "/users/services", bytes.NewReader(bodyBytes))
		rec := httptest.NewRecorder()

		u.CreateService(rec, req)

		if rec.Code != http.StatusCreated {
			t.Fatalf("Expected 201 Created, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		var resp map[string]any
		_ = json.Unmarshal(rec.Body.Bytes(), &resp)

		svcMap, ok := resp["service"].(map[string]any)
		if !ok {
			t.Fatalf("Expected service object in response, got %v", resp)
		}

		if svcMap["photo_url"] != nil && svcMap["photo_url"] != "" {
			t.Errorf("Expected empty/nil photo_url for legacy creation, got %v", svcMap["photo_url"])
		}
		if svcMap["address"] != nil && svcMap["address"] != "" {
			t.Errorf("Expected empty/nil address for legacy creation, got %v", svcMap["address"])
		}
	})

	// 3. UpdateService existing service's fields
	t.Run("UpdateService existing service's fields", func(t *testing.T) {
		// First create a service
		createReq := models.CreateServiceRequest{
			OwnerToken:       ownerToken1,
			Name:             "Original Service Name",
			Category:         "shipping",
			TenantBasePrice:  40.0,
			TenantPricePerKM: 3.0,
			Latitude:         30.0,
			Longitude:        31.0,
		}
		bodyBytes, _ := json.Marshal(createReq)
		reqC := httptest.NewRequest(http.MethodPost, "/users/services", bytes.NewReader(bodyBytes))
		recC := httptest.NewRecorder()
		u.CreateService(recC, reqC)

		var respC map[string]any
		_ = json.Unmarshal(recC.Body.Bytes(), &respC)
		svcC := respC["service"].(map[string]any)
		serviceID := svcC["id"].(string)

		// Update via PUT /users/services
		newPhoto := "https://cdn.example.com/services/updated.png"
		newAddress := "456 Industrial Zone, Giza, Egypt"
		newHours := "10:00 AM - 6:00 PM"
		newRadius := 30.0
		newBasePrice := 55.0

		updateReq := models.UpdateServiceRequest{
			ID:               serviceID,
			OwnerToken:       ownerToken1,
			Name:             "Updated Logistics Service",
			TenantBasePrice:  &newBasePrice,
			PhotoURL:         &newPhoto,
			Address:          &newAddress,
			WorkingHours:     &newHours,
			CoverageRadiusKM: &newRadius,
		}

		updateBytes, _ := json.Marshal(updateReq)
		reqU := httptest.NewRequest(http.MethodPut, "/users/services", bytes.NewReader(updateBytes))
		recU := httptest.NewRecorder()

		u.UpdateService(recU, reqU)

		if recU.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK for UpdateService, got %d. Body: %s", recU.Code, recU.Body.String())
		}

		// Verify database state directly
		fetched := s.GetServiceByID(context.Background(), serviceID)
		if fetched == nil {
			t.Fatalf("Failed to fetch updated service %s from database", serviceID)
		}
		if fetched.Name != "Updated Logistics Service" {
			t.Errorf("Expected updated name 'Updated Logistics Service', got '%s'", fetched.Name)
		}
		if fetched.TenantBasePrice != 55.0 {
			t.Errorf("Expected updated base price 55.0, got %f", fetched.TenantBasePrice)
		}
		if fetched.PhotoURL != newPhoto {
			t.Errorf("Expected photo URL '%s', got '%s'", newPhoto, fetched.PhotoURL)
		}
		if fetched.Address != newAddress {
			t.Errorf("Expected address '%s', got '%s'", newAddress, fetched.Address)
		}
		if fetched.WorkingHours != newHours {
			t.Errorf("Expected working hours '%s', got '%s'", newHours, fetched.WorkingHours)
		}
		if fetched.CoverageRadiusKM != 30.0 {
			t.Errorf("Expected coverage radius 30.0, got %f", fetched.CoverageRadiusKM)
		}
	})

	// 4. UpdateService IDOR & Authorization Gating
	t.Run("UpdateService IDOR & Authorization Gating", func(t *testing.T) {
		// Create service under Owner 1
		createReq := models.CreateServiceRequest{
			OwnerToken:       ownerToken1,
			Name:             "Owner 1 Protected Service",
			Category:         "delivery",
			TenantBasePrice:  20.0,
			TenantPricePerKM: 1.5,
			Latitude:         30.0,
			Longitude:        31.0,
		}
		bodyBytes, _ := json.Marshal(createReq)
		reqC := httptest.NewRequest(http.MethodPost, "/users/services", bytes.NewReader(bodyBytes))
		recC := httptest.NewRecorder()
		u.CreateService(recC, reqC)

		var respC map[string]any
		_ = json.Unmarshal(recC.Body.Bytes(), &respC)
		svcC := respC["service"].(map[string]any)
		serviceID := svcC["id"].(string)

		// Owner 2 attempts to modify Owner 1's service -> IDOR block (430 / 403 Forbidden)
		updateName := "Hacked Service Name"
		updateReq := models.UpdateServiceRequest{
			ID:         serviceID,
			OwnerToken: ownerToken2,
			Name:       updateName,
		}
		updateBytes, _ := json.Marshal(updateReq)
		reqU := httptest.NewRequest(http.MethodPut, "/users/services", bytes.NewReader(updateBytes))
		recU := httptest.NewRecorder()

		u.UpdateService(recU, reqU)

		if recU.Code != http.StatusForbidden {
			t.Errorf("Expected 403 Forbidden on IDOR update attempt, got %d. Body: %s", recU.Code, recU.Body.String())
		}

		// Verify service was NOT modified in database
		fetched := s.GetServiceByID(context.Background(), serviceID)
		if fetched.Name == updateName {
			t.Errorf("SECURITY DEFECT: IDOR update succeeded in mutating service name!")
		}

		// Non-existent service ID -> 404 Not Found
		updateReqNotFound := models.UpdateServiceRequest{
			ID:         "non-existent-service-id",
			OwnerToken: ownerToken1,
			Name:       "New Name",
		}
		notFoundBytes, _ := json.Marshal(updateReqNotFound)
		reqNF := httptest.NewRequest(http.MethodPut, "/users/services", bytes.NewReader(notFoundBytes))
		recNF := httptest.NewRecorder()

		u.UpdateService(recNF, reqNF)

		if recNF.Code != http.StatusNotFound {
			t.Errorf("Expected 404 Not Found for non-existent service ID, got %d", recNF.Code)
		}
	})
}
