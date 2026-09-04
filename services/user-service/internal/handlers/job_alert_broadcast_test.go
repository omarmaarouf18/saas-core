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
	"sync"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"

	"github.com/project/shared/infra/jwtutil"
	"github.com/project/user-service/internal/config"
	"github.com/project/user-service/internal/models"
	"github.com/project/user-service/internal/store"
)

func TestJobAlertBroadcast_EndToEnd(t *testing.T) {
	os.Setenv("JWT_SECRET", "test-jwt-secret-12345678901234567890123456789012")

	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://root:devpassword123@localhost:27017/saas_platform?authSource=admin"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	dbName := fmt.Sprintf("saas_platform_test_jobalert_%d", time.Now().UnixNano())
	testStore, err := store.NewMongoDB(ctx, mongoURI, dbName)
	if err != nil {
		t.Skipf("Skipping TestJobAlertBroadcast_EndToEnd: MongoDB not available at %s (%v)", mongoURI, err)
		return
	}
	defer func() {
		_ = testStore.DropDatabase(context.Background())
		testStore.Close(context.Background())
	}()

	ownerID := "owner-tenant-101"
	empID := "employee-worker-99"
	custID := "customer-user-1"

	ownerToken, _ := jwtutil.GenerateToken(ownerID, "owner", ownerID, "owner@example.com")
	empToken, _ := jwtutil.GenerateToken(empID, "employee", ownerID, "emp@example.com")
	custToken, _ := jwtutil.GenerateToken(custID, "customer", ownerID, "cust@example.com")

	// Mock Auth Service for token validation and KYC check
	mockAuthServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.Contains(r.URL.Path, "/auth/validate-token") {
			w.WriteHeader(http.StatusOK)
			_ = json.NewEncoder(w).Encode(map[string]any{
				"valid": true,
				"claims": map[string]any{
					"user_id":   ownerID,
					"tenant_id": ownerID,
					"email":     "owner@example.com",
					"role":      "owner",
				},
			})
			return
		}
		if strings.Contains(r.URL.Path, "/auth/kyc-status") {
			w.WriteHeader(http.StatusOK)
			_ = json.NewEncoder(w).Encode(map[string]any{
				"kyc_status": "approved",
			})
			return
		}
		if strings.Contains(r.URL.Path, "/auth/user") {
			id := r.URL.Query().Get("id")
			if id == empID {
				w.WriteHeader(http.StatusOK)
				_ = json.NewEncoder(w).Encode(map[string]any{
					"role":      "employee",
					"tenant_id": ownerID,
					"is_active": true,
				})
				return
			}
			w.WriteHeader(http.StatusOK)
			_ = json.NewEncoder(w).Encode(map[string]any{
				"role":           "owner",
				"kyc_status":     "approved",
				"is_active":      true,
				"account_status": "active",
			})
			return
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer mockAuthServer.Close()

	var notifMu sync.Mutex
	var receivedPayload map[string]any
	var receivedToken string
	var callCount int

	// Mock Notification Service
	mockNotifServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/notifications/broadcast/job-alert" && r.Method == http.MethodPost {
			notifMu.Lock()
			callCount++
			receivedToken = r.Header.Get("X-Internal-Token")
			_ = json.NewDecoder(r.Body).Decode(&receivedPayload)
			notifMu.Unlock()

			w.WriteHeader(http.StatusOK)
			_ = json.NewEncoder(w).Encode(map[string]string{"message": "broadcast sent"})
			return
		}
		w.WriteHeader(http.StatusNotFound)
	}))
	defer mockNotifServer.Close()

	svcID := "service-cleaning-1"
	testStore.CreateService(context.Background(), &models.Service{
		ID:               svcID,
		TenantID:         ownerID,
		Name:             "Home Cleaning",
		Category:         "cleaning",
		TenantBasePrice:  100.0,
		TenantPricePerKM: 0.0,
		Latitude:         30.0444,
		Longitude:        31.2357,
	})

	_ = testStore.UpsertEmployeeLocation(context.Background(), &models.EmployeeLocation{
		TenantID:   ownerID,
		EmployeeID: empID,
		Latitude:   30.0444,
		Longitude:  31.2357,
		UpdatedAt:  time.Now().UTC(),
	})

	cfg := &config.Config{
		AppEnv:                 "test",
		JWTSecret:              "test-jwt-secret-12345678901234567890123456789012",
		InternalServiceToken:   "internal-secret-token-123",
		AuthServiceURL:         mockAuthServer.URL,
		NotificationServiceURL: mockNotifServer.URL,
	}

	u := NewUserService(testStore, cfg, rdb)

	t.Run("Job creation with assigned employee triggers job_alert broadcast with correct payload", func(t *testing.T) {
		reqBody := map[string]any{
			"owner_id":       ownerToken,
			"employee_id":    empToken,
			"user_id":        custToken,
			"service_id":     svcID,
			"payment_method": "cod",
			"location": map[string]any{
				"latitude":  30.0444,
				"longitude": 31.2357,
			},
		}

		b, _ := json.Marshal(reqBody)
		req := httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(b))
		rec := httptest.NewRecorder()

		u.TrackJob(rec, req)

		if rec.Code != http.StatusCreated {
			t.Fatalf("Expected status 201 Created, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		// Wait briefly for asynchronous background goroutine to execute
		time.Sleep(150 * time.Millisecond)

		notifMu.Lock()
		defer notifMu.Unlock()

		if callCount != 1 {
			t.Fatalf("Expected 1 notification service call, got %d", callCount)
		}
		if receivedToken != "internal-secret-token-123" {
			t.Errorf("Expected X-Internal-Token 'internal-secret-token-123', got %q", receivedToken)
		}
		if receivedPayload["tenant_id"] != ownerID {
			t.Errorf("Expected tenant_id %q, got %v", ownerID, receivedPayload["tenant_id"])
		}
		if receivedPayload["employee_id"] != empID {
			t.Errorf("Expected employee_id %q, got %v", empID, receivedPayload["employee_id"])
		}
		if receivedPayload["service_name"] != "Home Cleaning" {
			t.Errorf("Expected service_name 'Home Cleaning', got %v", receivedPayload["service_name"])
		}
		if !strings.Contains(fmt.Sprintf("%v", receivedPayload["description"]), "cleaning") {
			t.Errorf("Expected description to contain category 'cleaning', got %v", receivedPayload["description"])
		}
	})

	t.Run("Notification service failure (500 Internal Error) does NOT block or fail job creation", func(t *testing.T) {
		// Create mock failing notification server
		failingNotifServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusInternalServerError)
		}))
		defer failingNotifServer.Close()

		cfgFailing := &config.Config{
			AppEnv:                 "test",
			JWTSecret:              "test-jwt-secret-12345678901234567890123456789012",
			InternalServiceToken:   "internal-secret-token-123",
			AuthServiceURL:         mockAuthServer.URL,
			NotificationServiceURL: failingNotifServer.URL,
		}

		uFailing := NewUserService(testStore, cfgFailing, rdb)

		reqBody := map[string]any{
			"owner_id":       ownerToken,
			"employee_id":    empToken,
			"user_id":        custToken,
			"service_id":     svcID,
			"payment_method": "cod",
			"location": map[string]any{
				"latitude":  30.0444,
				"longitude": 31.2357,
			},
		}

		b, _ := json.Marshal(reqBody)
		req := httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(b))
		rec := httptest.NewRecorder()

		uFailing.TrackJob(rec, req)

		// Assert parent job creation request succeeds cleanly despite notification service failure
		if rec.Code != http.StatusCreated {
			t.Fatalf("Expected status 201 Created despite notification failure, got %d. Body: %s", rec.Code, rec.Body.String())
		}
	})
}
