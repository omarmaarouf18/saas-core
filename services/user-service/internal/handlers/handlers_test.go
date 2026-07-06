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

	"github.com/project/user-service/internal/jwtutil"
	"github.com/project/user-service/internal/models"
	"github.com/project/user-service/internal/store"
)

func TestUserServiceHandlers(t *testing.T) {
	// Initialize MongoDB store. Fallback or skip if not running.
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
		t.Skipf("Skipping user-service integration tests: MongoDB not available at %s (%v)", mongoURI, err)
		return
	}
	defer func() {
		_ = s.DropDatabase(context.Background())
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

	u := NewUserService(s, mockAuthServer.URL, "mock-internal-token")

	// Generate tokens for tests
	tokenPendingOwner, _ := jwtutil.GenerateToken("kyc-pending-owner", "owner", "kyc-pending-owner", "pending@example.com")
	tokenApprovedOwner, _ := jwtutil.GenerateToken("kyc-approved-owner", "owner", "kyc-approved-owner", "approved@example.com")
	tokenMismatch, _ := jwtutil.GenerateToken("mismatch-id", "owner", "mismatch-id", "mismatch@example.com")
	tokenTenant, _ := jwtutil.GenerateToken("tenant-id", "owner", "tenant-id", "tenant@example.com")
	tokenClientUser, _ := jwtutil.GenerateToken("client-user-123", "user", "client-user-123", "client@example.com")

	// Test 1: KYC gating blocks CreateService for non-approved owners
	t.Run("CreateService KYC Gating", func(t *testing.T) {
		reqBody := map[string]any{
			"owner_id":          tokenPendingOwner,
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
			"owner_id":       tokenPendingOwner,
			"user_id":        tokenClientUser,
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
			"owner_id":       tokenApprovedOwner,
			"user_id":        tokenClientUser,
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
		
		u2 := NewUserService(s, mockAuthServer2.URL, "mock-internal-token")

		reqBody := map[string]any{
			"tenant_id":    tokenTenant,
			"tier":         "paid",
			"requester_id": tokenMismatch, // Mismatch
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

	// Test 5: GetJob Access Control
	t.Run("GetJob Access Control", func(t *testing.T) {
		ctx := context.Background()
		testJob := &models.Job{
			ID:         "test-job-999",
			OwnerID:    "job-owner-999",
			EmployeeID: "job-employee-999",
			UserID:     "client-user-999",
			Status:     "pending",
		}
		_ = s.CreateJob(ctx, testJob)

		tokenMismatchedUser, _ := jwtutil.GenerateToken("mismatched-user", "user", "mismatched-user", "mismatch@example.com")
		tokenJobOwner, _ := jwtutil.GenerateToken("job-owner-999", "owner", "job-owner-999", "owner@example.com")
		tokenJobClient, _ := jwtutil.GenerateToken("client-user-999", "user", "client-user-999", "client@example.com")

		// A. Valid internal token -> 200 OK
		req := httptest.NewRequest("GET", "/users/jobs/get?id=test-job-999", nil)
		req.Header.Set("X-Internal-Token", "mock-internal-token")
		rec := httptest.NewRecorder()
		u.GetJob(rec, req)
		if rec.Code != http.StatusOK {
			t.Errorf("Expected 200 OK for internal token, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		// B. Mismatched requester_id -> 403 Forbidden
		req = httptest.NewRequest("GET", "/users/jobs/get?id=test-job-999&requester_id=" + tokenMismatchedUser, nil)
		rec = httptest.NewRecorder()
		u.GetJob(rec, req)
		if rec.Code != http.StatusForbidden {
			t.Errorf("Expected 403 Forbidden for mismatched requester, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		// C. Matching requester_id (Owner) -> 200 OK
		req = httptest.NewRequest("GET", "/users/jobs/get?id=test-job-999&requester_id=" + tokenJobOwner, nil)
		rec = httptest.NewRecorder()
		u.GetJob(rec, req)
		if rec.Code != http.StatusOK {
			t.Errorf("Expected 200 OK for owner, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		// D. Matching requester_id (User/Client) -> 200 OK
		req = httptest.NewRequest("GET", "/users/jobs/get?id=test-job-999&requester_id=" + tokenJobClient, nil)
		rec = httptest.NewRecorder()
		u.GetJob(rec, req)
		if rec.Code != http.StatusOK {
			t.Errorf("Expected 200 OK for client, got %d. Body: %s", rec.Code, rec.Body.String())
		}
	})

	// Test 6: CompleteJob Access Control
	t.Run("CompleteJob Access Control", func(t *testing.T) {
		ctx := context.Background()
		testJob := &models.Job{
			ID:            "test-job-888",
			OwnerID:       "job-owner-888",
			EmployeeID:    "job-employee-888",
			UserID:        "client-user-888",
			ServiceID:     "svc-001",
			Status:        models.JobStatusActive,
			PaymentMethod: "cod",
		}
		_ = s.CreateJob(ctx, testJob)

		tokenMismatchedUser, _ := jwtutil.GenerateToken("mismatched-user-888", "user", "mismatched-user-888", "mismatch@example.com")
		tokenJobOwner, _ := jwtutil.GenerateToken("job-owner-888", "owner", "job-owner-888", "owner@example.com")

		// A. Valid internal token -> 200 OK
		reqBody := map[string]any{
			"job_id": "test-job-888",
			"cash_collected": true,
		}
		body, _ := json.Marshal(reqBody)
		req := httptest.NewRequest("POST", "/users/jobs/complete", bytes.NewReader(body))
		req.Header.Set("X-Internal-Token", "mock-internal-token")
		rec := httptest.NewRecorder()
		u.CompleteJob(rec, req)
		if rec.Code != http.StatusOK {
			t.Errorf("Expected 200 OK for internal token, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		// Reset job status to active for subsequent tests
		_ = s.UpdateJobStatus(ctx, "test-job-888", models.JobStatusActive)

		// B. Mismatched requester_id -> 403 Forbidden
		reqBody = map[string]any{
			"job_id": "test-job-888",
			"cash_collected": true,
			"requester_id": tokenMismatchedUser,
		}
		body, _ = json.Marshal(reqBody)
		req = httptest.NewRequest("POST", "/users/jobs/complete", bytes.NewReader(body))
		rec = httptest.NewRecorder()
		u.CompleteJob(rec, req)
		if rec.Code != http.StatusForbidden {
			t.Errorf("Expected 403 Forbidden for mismatched requester, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		// C. Matching requester_id (Owner) -> 200 OK
		reqBody = map[string]any{
			"job_id": "test-job-888",
			"cash_collected": true,
			"requester_id": tokenJobOwner,
		}
		body, _ = json.Marshal(reqBody)
		req = httptest.NewRequest("POST", "/users/jobs/complete", bytes.NewReader(body))
		rec = httptest.NewRecorder()
		u.CompleteJob(rec, req)
		if rec.Code != http.StatusOK {
			t.Errorf("Expected 200 OK for owner, got %d. Body: %s", rec.Code, rec.Body.String())
		}
	})

	// Test 7: WalletDeposit Max Amount Gating
	t.Run("WalletDeposit Max Amount Gating", func(t *testing.T) {
		// Mock auth lookup to return 200 OK for tenant ID with approved KYC status
		mockAuthServer3 := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusOK)
			json.NewEncoder(w).Encode(map[string]any{
				"id":         "tenant-id",
				"kyc_status": "approved",
				"role":       "owner",
				"is_active":  true,
			})
		}))
		defer mockAuthServer3.Close()
		
		u3 := NewUserService(s, mockAuthServer3.URL, "mock-internal-token")

		// A. Valid deposit limit: 500,000 -> 200 OK
		reqBody := map[string]any{
			"tenant_id": tokenTenant,
			"amount":    500000.0,
		}
		body, _ := json.Marshal(reqBody)
		req := httptest.NewRequest("POST", "/users/wallet/deposit", bytes.NewReader(body))
		rec := httptest.NewRecorder()
		u3.WalletDeposit(rec, req)
		if rec.Code != http.StatusOK {
			t.Errorf("Expected 200 OK for valid deposit, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		// B. Exceeded deposit limit: 2,000,000 -> 400 Bad Request
		reqBody = map[string]any{
			"tenant_id": tokenTenant,
			"amount":    2000000.0,
		}
		body, _ = json.Marshal(reqBody)
		req = httptest.NewRequest("POST", "/users/wallet/deposit", bytes.NewReader(body))
		rec = httptest.NewRecorder()
		u3.WalletDeposit(rec, req)
		if rec.Code != http.StatusBadRequest {
			t.Errorf("Expected 400 Bad Request for exceeded deposit, got %d. Body: %s", rec.Code, rec.Body.String())
		}
		if !strings.Contains(rec.Body.String(), "amount up to 1000000 required") {
			t.Errorf("Expected limit error message, got: %s", rec.Body.String())
		}
	})

	// Test 8: UpdateJobLocation Gating and Verification
	t.Run("UpdateJobLocation Gating and Verification", func(t *testing.T) {
		ctx := context.Background()
		activeJob := &models.Job{
			ID:            "active-job-777",
			OwnerID:       "owner-777",
			EmployeeID:    "employee-777",
			UserID:        "client-777",
			Status:        models.JobStatusActive,
			PaymentMethod: "cod",
		}
		_ = s.CreateJob(ctx, activeJob)

		pendingJob := &models.Job{
			ID:            "pending-job-777",
			OwnerID:       "owner-777",
			EmployeeID:    "employee-777",
			UserID:        "client-777",
			Status:        models.JobStatusPending,
			PaymentMethod: "cod",
		}
		_ = s.CreateJob(ctx, pendingJob)

		tokenEmployee, _ := jwtutil.GenerateToken("employee-777", "employee", "owner-777", "employee@example.com")
		tokenMismatched, _ := jwtutil.GenerateToken("mismatched-user", "user", "mismatched-user", "mismatch@example.com")

		// A. Requester is not the assigned employee -> 403 Forbidden
		reqBody := map[string]any{
			"job_id":       "active-job-777",
			"requester_id": tokenMismatched,
			"latitude":     12.34,
			"longitude":    56.78,
		}
		body, _ := json.Marshal(reqBody)
		req := httptest.NewRequest("POST", "/users/jobs/location/update", bytes.NewReader(body))
		rec := httptest.NewRecorder()
		u.UpdateJobLocation(rec, req)
		if rec.Code != http.StatusForbidden {
			t.Errorf("Expected 403 Forbidden for mismatched employee, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		// B. Job is not active (pending) -> 403 Forbidden
		reqBody = map[string]any{
			"job_id":       "pending-job-777",
			"requester_id": tokenEmployee,
			"latitude":     12.34,
			"longitude":    56.78,
		}
		body, _ = json.Marshal(reqBody)
		req = httptest.NewRequest("POST", "/users/jobs/location/update", bytes.NewReader(body))
		rec = httptest.NewRecorder()
		u.UpdateJobLocation(rec, req)
		if rec.Code != http.StatusForbidden {
			t.Errorf("Expected 403 Forbidden for non-active job status, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		// C. Success update -> 200 OK
		reqBody = map[string]any{
			"job_id":       "active-job-777",
			"requester_id": tokenEmployee,
			"latitude":     12.34,
			"longitude":    56.78,
		}
		body, _ = json.Marshal(reqBody)
		req = httptest.NewRequest("POST", "/users/jobs/location/update", bytes.NewReader(body))
		rec = httptest.NewRecorder()
		u.UpdateJobLocation(rec, req)
		if rec.Code != http.StatusOK {
			t.Errorf("Expected 200 OK, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		// Verify in database
		updatedJob := s.GetJob(ctx, "active-job-777")
		if updatedJob == nil || updatedJob.CurrentLocation == nil || updatedJob.CurrentLocation.Latitude != 12.34 {
			t.Errorf("Location not updated in store: %+v", updatedJob)
		}
	})
}
