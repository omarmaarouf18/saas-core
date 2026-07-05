package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/project/user-service/internal/store"
)

func TestUserServiceHandlers(t *testing.T) {
	// Initialize MongoDB store. Fallback or skip if not running.
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}
	
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	
	s, err := store.NewMongoDB(ctx, mongoURI, "saas_platform_test")
	if err != nil {
		t.Skipf("Skipping user-service integration tests: MongoDB not available at %s (%v)", mongoURI, err)
		return
	}
	defer func() {
		s.Close(context.Background())
	}()

	// Start a mock Auth Service
	mockAuthServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		id := r.URL.Query().Get("id")
		
		if id == "kyc-approved-owner" {
			w.WriteHeader(http.StatusOK)
			json.NewEncoder(w).Encode(map[string]any{
				"id":         "kyc-approved-owner",
				"role":       "owner",
				"kyc_status": "approved",
			})
			return
		}
		
		if id == "kyc-pending-owner" {
			w.WriteHeader(http.StatusOK)
			json.NewEncoder(w).Encode(map[string]any{
				"id":         "kyc-pending-owner",
				"role":       "owner",
				"kyc_status": "pending_super_admin_approval",
			})
			return
		}
		
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(map[string]string{"error": "user not found"})
	}))
	defer mockAuthServer.Close()

	u := NewUserService(s, mockAuthServer.URL)

	// Test 1: KYC gating blocks CreateService for non-approved owners
	t.Run("CreateService KYC Gating", func(t *testing.T) {
		reqBody := map[string]any{
			"owner_id":          "kyc-pending-owner",
			"name":              "Test Transport",
			"category":          "transport",
			"tenant_base_price": 5.0,
		}
		body, _ := json.Marshal(reqBody)
		req := httptest.NewRequest("POST", "/users/services", bytes.NewReader(body))
		rec := httptest.NewRecorder()

		u.CreateService(rec, req)

		if rec.Code != http.StatusForbidden {
			t.Errorf("Expected 403 Forbidden, got %d. Body: %s", rec.Code, rec.Body.String())
		}
		if !strings.Contains(rec.Body.String(), "owner KYC approval is pending") {
			t.Errorf("Expected error about KYC pending, got: %s", rec.Body.String())
		}
	})

	// Test 2: KYC gating blocks TrackJob for non-approved owners
	t.Run("TrackJob KYC Gating", func(t *testing.T) {
		reqBody := map[string]any{
			"owner_id":       "kyc-pending-owner",
			"service_id":     "some-service-id",
			"payment_method": "cod",
		}
		body, _ := json.Marshal(reqBody)
		req := httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(body))
		rec := httptest.NewRecorder()

		u.TrackJob(rec, req)

		if rec.Code != http.StatusForbidden {
			t.Errorf("Expected 403 Forbidden, got %d. Body: %s", rec.Code, rec.Body.String())
		}
	})

	// Test 3: COD payment method rejection for non-cod values
	t.Run("TrackJob COD payment_method verification", func(t *testing.T) {
		reqBody := map[string]any{
			"owner_id":       "kyc-approved-owner",
			"service_id":     "some-service-id",
			"payment_method": "wallet", // non-cod payment
		}
		body, _ := json.Marshal(reqBody)
		req := httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(body))
		rec := httptest.NewRecorder()

		u.TrackJob(rec, req)

		if rec.Code != http.StatusBadRequest {
			t.Errorf("Expected 400 Bad Request, got %d. Body: %s", rec.Code, rec.Body.String())
		}
		if !strings.Contains(rec.Body.String(), "only 'cod' is currently supported") {
			t.Errorf("Expected error about cod support only, got: %s", rec.Body.String())
		}
	})

	// Test 4: Subscription requester_id and tenant_id mismatch rejection
	t.Run("Subscription mismatch requester_id", func(t *testing.T) {
		// Mock auth lookup to return 200 OK for tenant ID
		mockAuthServer2 := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusOK)
			json.NewEncoder(w).Encode(map[string]any{"id": "tenant-id"})
		}))
		defer mockAuthServer2.Close()
		
		u2 := NewUserService(s, mockAuthServer2.URL)

		reqBody := map[string]any{
			"tenant_id":    "tenant-id",
			"tier":         "paid",
			"requester_id": "mismatch-id", // Mismatch
		}
		body, _ := json.Marshal(reqBody)
		req := httptest.NewRequest("POST", "/users/subscription", bytes.NewReader(body))
		rec := httptest.NewRecorder()

		u2.Subscription(rec, req)

		if rec.Code != http.StatusForbidden {
			t.Errorf("Expected 403 Forbidden, got %d. Body: %s", rec.Code, rec.Body.String())
		}
		if !strings.Contains(rec.Body.String(), "requester_id must match tenant_id") {
			t.Errorf("Expected mismatch error, got: %s", rec.Body.String())
		}
	})
}
