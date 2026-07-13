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
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatchlogs"
	"github.com/project/shared/infra/handlerutil"
	"github.com/project/shared/infra/jwtutil"
	"github.com/project/user-service/internal/config"
	"github.com/project/user-service/internal/models"
	"github.com/project/user-service/internal/store"
	"github.com/redis/go-redis/v9"
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

	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

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
				"is_active":  true,
			})
			return
		}

		if id == "kyc-pending-owner" {
			w.WriteHeader(http.StatusOK)
			json.NewEncoder(w).Encode(map[string]any{
				"id":         "kyc-pending-owner",
				"role":       "owner",
				"kyc_status": "pending_super_admin_approval",
				"is_active":  true,
			})
			return
		}

		if strings.Contains(id, "employee") {
			isActive := !strings.Contains(id, "deactivated")
			w.WriteHeader(http.StatusOK)
			json.NewEncoder(w).Encode(map[string]any{
				"id":        id,
				"role":      "employee",
				"is_active": isActive,
			})
			return
		}

		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(map[string]string{"error": "user not found"})
	}))
	defer mockAuthServer.Close()

	cfg := &config.Config{
		AuthServiceURL:       mockAuthServer.URL,
		InternalServiceToken: "mock-internal-token",
	}
	u := NewUserService(s, cfg, rdb)

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

		cfg2 := &config.Config{
			AuthServiceURL:       mockAuthServer2.URL,
			InternalServiceToken: "mock-internal-token",
		}
		u2 := NewUserService(s, cfg2, rdb)

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
		req = httptest.NewRequest("GET", "/users/jobs/get?id=test-job-999&requester_id="+tokenMismatchedUser, nil)
		rec = httptest.NewRecorder()
		u.GetJob(rec, req)
		if rec.Code != http.StatusForbidden {
			t.Errorf("Expected 403 Forbidden for mismatched requester, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		// C. Matching requester_id (Owner) -> 200 OK
		req = httptest.NewRequest("GET", "/users/jobs/get?id=test-job-999&requester_id="+tokenJobOwner, nil)
		rec = httptest.NewRecorder()
		u.GetJob(rec, req)
		if rec.Code != http.StatusOK {
			t.Errorf("Expected 200 OK for owner, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		// D. Matching requester_id (User/Client) -> 200 OK
		req = httptest.NewRequest("GET", "/users/jobs/get?id=test-job-999&requester_id="+tokenJobClient, nil)
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
			"job_id":         "test-job-888",
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
			"job_id":         "test-job-888",
			"cash_collected": true,
			"requester_id":   tokenMismatchedUser,
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
			"job_id":         "test-job-888",
			"cash_collected": true,
			"requester_id":   tokenJobOwner,
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

		cfg3 := &config.Config{
			AuthServiceURL:       mockAuthServer3.URL,
			InternalServiceToken: "mock-internal-token",
		}
		u3 := NewUserService(s, cfg3, rdb)

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

		// C. Non-local environment: APP_ENV=production -> 400 Bad Request
		t.Setenv("APP_ENV", "production")
		reqBody = map[string]any{
			"tenant_id": tokenTenant,
			"amount":    500.0,
		}
		body, _ = json.Marshal(reqBody)
		req = httptest.NewRequest("POST", "/users/wallet/deposit", bytes.NewReader(body))
		rec = httptest.NewRecorder()
		u3.WalletDeposit(rec, req)
		if rec.Code != http.StatusBadRequest {
			t.Errorf("Expected 400 Bad Request for production env deposit, got %d. Body: %s", rec.Code, rec.Body.String())
		}
		if !strings.Contains(rec.Body.String(), "payment gateway not yet integrated") {
			t.Errorf("Expected gateway integration error message, got: %s", rec.Body.String())
		}
	})

	// Test 8: UpdateJobLocation Gating and Verification
	t.Run("UpdateJobLocation Gating and Verification", func(t *testing.T) {
		ctx := context.Background()
		_ = s.UpsertSubscription(ctx, &models.Subscription{
			ID:        "sub-owner-777",
			TenantID:  "owner-777",
			Tier:      models.PlanPaid,
			StartedAt: time.Now(),
		})
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

	// Test 9: Live Location Tracking Subscription Gating
	t.Run("UpdateJobLocation Subscription Gating", func(t *testing.T) {
		ctx := context.Background()

		// Setup 3 owners with different subscription tiers
		tokenEmployee, _ := jwtutil.GenerateToken("emp-777", "employee", "paid-owner", "emp@example.com")

		_ = s.UpsertSubscription(ctx, &models.Subscription{
			ID:        "sub-pending",
			TenantID:  "pending-owner",
			Tier:      models.PlanPendingPayment,
			StartedAt: time.Now(),
		})
		_ = s.UpsertSubscription(ctx, &models.Subscription{
			ID:        "sub-paid",
			TenantID:  "paid-owner",
			Tier:      models.PlanPaid,
			StartedAt: time.Now(),
		})

		// Active jobs
		jobFree := &models.Job{
			ID: "job-free", OwnerID: "free-owner", EmployeeID: "emp-777", UserID: "client-1",
			Status: models.JobStatusActive, PaymentMethod: "cod",
		}
		jobPending := &models.Job{
			ID: "job-pending", OwnerID: "pending-owner", EmployeeID: "emp-777", UserID: "client-2",
			Status: models.JobStatusActive, PaymentMethod: "cod",
		}
		jobPaid := &models.Job{
			ID: "job-paid", OwnerID: "paid-owner", EmployeeID: "emp-777", UserID: "client-3",
			Status: models.JobStatusActive, PaymentMethod: "cod",
		}
		_ = s.CreateJob(ctx, jobFree)
		_ = s.CreateJob(ctx, jobPending)
		_ = s.CreateJob(ctx, jobPaid)

		// 1. Free tenant → HTTP 402 Upgrade Required
		reqBody := map[string]any{
			"job_id":       "job-free",
			"requester_id": tokenEmployee,
			"latitude":     12.34,
			"longitude":    56.78,
			"tier":         "paid", // Injected bypass attempt
		}
		body, _ := json.Marshal(reqBody)
		req := httptest.NewRequest("POST", "/users/jobs/location/update", bytes.NewReader(body))
		rec := httptest.NewRecorder()
		u.UpdateJobLocation(rec, req)
		if rec.Code != http.StatusPaymentRequired {
			t.Errorf("Expected 402 Payment Required for Free, got %d. Body: %s", rec.Code, rec.Body.String())
		}
		if !strings.Contains(rec.Body.String(), "upgrade_required") {
			t.Errorf("Expected upgrade_required error payload, got: %s", rec.Body.String())
		}

		// 2. Pending Payment tenant → HTTP 402 Upgrade Required
		reqBody["job_id"] = "job-pending"
		body, _ = json.Marshal(reqBody)
		req = httptest.NewRequest("POST", "/users/jobs/location/update", bytes.NewReader(body))
		rec = httptest.NewRecorder()
		u.UpdateJobLocation(rec, req)
		if rec.Code != http.StatusPaymentRequired {
			t.Errorf("Expected 402 Payment Required for Pending Payment, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		// 3. Paid tenant → HTTP 200 OK
		reqBody["job_id"] = "job-paid"
		body, _ = json.Marshal(reqBody)
		req = httptest.NewRequest("POST", "/users/jobs/location/update", bytes.NewReader(body))
		rec = httptest.NewRecorder()
		u.UpdateJobLocation(rec, req)
		if rec.Code != http.StatusOK {
			t.Errorf("Expected 200 OK for Paid, got %d. Body: %s", rec.Code, rec.Body.String())
		}
	})

	// Test 10: Location Throttle Gating
	t.Run("UpdateJobLocation Minimum Interval Throttling", func(t *testing.T) {
		ctx := context.Background()
		tokenEmployee, _ := jwtutil.GenerateToken("emp-888", "employee", "paid-owner", "emp@example.com")

		// Create two active jobs under the same paid owner
		jobA := &models.Job{
			ID: "job-throttle-A", OwnerID: "paid-owner", EmployeeID: "emp-888", UserID: "client-a",
			Status: models.JobStatusActive, PaymentMethod: "cod",
		}
		jobB := &models.Job{
			ID: "job-throttle-B", OwnerID: "paid-owner", EmployeeID: "emp-888", UserID: "client-b",
			Status: models.JobStatusActive, PaymentMethod: "cod",
		}
		_ = s.CreateJob(ctx, jobA)
		_ = s.CreateJob(ctx, jobB)

		// 1. Initial push for Job A → succeeds (200 OK)
		reqBody := map[string]any{
			"job_id":       "job-throttle-A",
			"requester_id": tokenEmployee,
			"latitude":     12.34,
			"longitude":    56.78,
		}
		body, _ := json.Marshal(reqBody)
		req := httptest.NewRequest("POST", "/users/jobs/location/update", bytes.NewReader(body))
		rec := httptest.NewRecorder()
		u.UpdateJobLocation(rec, req)
		if rec.Code != http.StatusOK {
			t.Errorf("Expected first push to succeed, got status %d. Body: %s", rec.Code, rec.Body.String())
		}

		// 2. Rapid second push for Job A (within 1 second) → fails (429 Too Many Requests)
		req = httptest.NewRequest("POST", "/users/jobs/location/update", bytes.NewReader(body))
		rec = httptest.NewRecorder()
		u.UpdateJobLocation(rec, req)
		if rec.Code != http.StatusTooManyRequests {
			t.Errorf("Expected 429 Too Many Requests, got status %d. Body: %s", rec.Code, rec.Body.String())
		}

		// 3. Parallel push for Job B → succeeds (200 OK, not blocked by Job A's throttle)
		reqBody["job_id"] = "job-throttle-B"
		body, _ = json.Marshal(reqBody)
		req = httptest.NewRequest("POST", "/users/jobs/location/update", bytes.NewReader(body))
		rec = httptest.NewRecorder()
		u.UpdateJobLocation(rec, req)
		if rec.Code != http.StatusOK {
			t.Errorf("Expected parallel job B push to succeed, got status %d. Body: %s", rec.Code, rec.Body.String())
		}

		// 4. Assert SSRF-safe design: u.chatServiceURL is used, verify it's configured in handlers
		if u.chatServiceURL == "" {
			t.Errorf("SSRF validation error: chatServiceURL is empty in handler configuration")
		}
	})

	// Test 11: Location Throttle Error Rollback and Race Handling
	t.Run("UpdateJobLocation Throttle Error Rollback", func(t *testing.T) {
		// Clean up throttle state first
		u.locationThrottleMu.Lock()
		delete(u.locationLastUpdate, "active-job-777")
		delete(u.locationInFlight, "active-job-777")
		u.locationThrottleMu.Unlock()

		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()

		tokenEmployee, _ := jwtutil.GenerateToken("employee-777", "employee", "owner-777", "employee@example.com")

		reqBody := map[string]any{
			"job_id":       "active-job-777",
			"requester_id": tokenEmployee,
			"latitude":     12.34,
			"longitude":    56.78,
		}
		body, _ := json.Marshal(reqBody)
		req := httptest.NewRequest("POST", "/users/jobs/location/update", bytes.NewReader(body))
		req = req.WithContext(ctx)

		// Goroutine that polls to detect when the request enters the in-flight state, then cancels the context
		go func() {
			for {
				u.locationThrottleMu.Lock()
				inFlight := u.locationInFlight["active-job-777"]
				u.locationThrottleMu.Unlock()
				if inFlight {
					cancel()
					break
				}
				time.Sleep(10 * time.Microsecond)
			}
		}()

		// 1. Call UpdateJobLocation with the canceling context → expect 500 internal_error (context cancelled)
		rec := httptest.NewRecorder()
		u.UpdateJobLocation(rec, req)
		if rec.Code != http.StatusInternalServerError {
			t.Errorf("Expected 500 Internal Server Error, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		// 2. Immediate retry with a fresh/valid context → expect 200 OK (rollback worked!)
		req2 := httptest.NewRequest("POST", "/users/jobs/location/update", bytes.NewReader(body))
		rec2 := httptest.NewRecorder()
		u.UpdateJobLocation(rec2, req2)
		if rec2.Code != http.StatusOK {
			t.Errorf("Expected retry to succeed with 200 OK, got %d. Body: %s", rec2.Code, rec2.Body.String())
		}
	})

	t.Run("UpdateJobLocation Throttle Concurrent Race Handling", func(t *testing.T) {
		// Clean up throttle state first
		u.locationThrottleMu.Lock()
		delete(u.locationLastUpdate, "active-job-777")
		delete(u.locationInFlight, "active-job-777")
		u.locationThrottleMu.Unlock()

		tokenEmployee, _ := jwtutil.GenerateToken("employee-777", "employee", "owner-777", "employee@example.com")

		reqBody := map[string]any{
			"job_id":       "active-job-777",
			"requester_id": tokenEmployee,
			"latitude":     12.34,
			"longitude":    56.78,
		}
		body, _ := json.Marshal(reqBody)

		var wg sync.WaitGroup
		var codesMu sync.Mutex
		var codes []int

		// Launch two concurrent requests for the same job
		for i := 0; i < 2; i++ {
			wg.Add(1)
			go func() {
				defer wg.Done()
				req := httptest.NewRequest("POST", "/users/jobs/location/update", bytes.NewReader(body))
				rec := httptest.NewRecorder()
				u.UpdateJobLocation(rec, req)
				codesMu.Lock()
				codes = append(codes, rec.Code)
				codesMu.Unlock()
			}()
		}
		wg.Wait()

		// Verify that exactly one request succeeded (200) and one was rejected (429)
		var count200, count429 int
		for _, code := range codes {
			if code == http.StatusOK {
				count200++
			} else if code == http.StatusTooManyRequests {
				count429++
			}
		}

		if count200 != 1 || count429 != 1 {
			t.Errorf("Expected exactly one 200 OK and one 429 Too Many Requests, got codes: %v", codes)
		}
	})

	// Test 13: Live Location Tracking Gated Rejection with Enabled CloudWatch Event Shipping
	t.Run("UpdateJobLocation Gated Rejection with CloudWatch Shipping", func(t *testing.T) {
		// Clean up throttle state first
		u.locationThrottleMu.Lock()
		delete(u.locationLastUpdate, "job-free")
		delete(u.locationInFlight, "job-free")
		u.locationThrottleMu.Unlock()

		// Enable shipping with invalid/unreachable config
		handlerutil.CwLogGroup = "test-group"
		handlerutil.CwEnabled = true
		handlerutil.CwClient = cloudwatchlogs.NewFromConfig(aws.Config{})

		tokenEmployee, _ := jwtutil.GenerateToken("emp-777", "employee", "paid-owner", "emp@example.com")

		reqBody := map[string]any{
			"job_id":       "job-free", // free owner -> will trigger upgrade_required
			"requester_id": tokenEmployee,
			"latitude":     12.34,
			"longitude":    56.78,
		}
		body, _ := json.Marshal(reqBody)
		req := httptest.NewRequest("POST", "/users/jobs/location/update", bytes.NewReader(body))
		rec := httptest.NewRecorder()

		start := time.Now()
		u.UpdateJobLocation(rec, req)
		duration := time.Since(start)

		// 1. Must return 402 Payment Required
		if rec.Code != http.StatusPaymentRequired {
			t.Errorf("Expected 402 Payment Required, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		// 2. Must not block (should be near instant)
		if duration > 100*time.Millisecond {
			t.Errorf("UpdateJobLocation blocked for %v when log shipping, expected it to return instantly", duration)
		}
	})

	// Test 14: Prevent Duplicate Ratings
	t.Run("Prevent Duplicate Ratings", func(t *testing.T) {
		// Seed a completed job
		jobID := "rate-job-123"
		testJob := &models.Job{
			ID:         jobID,
			OwnerID:    "rate-owner-123",
			EmployeeID: "rate-employee-123",
			Status:     models.JobStatusCompleted,
		}
		_ = s.CreateJob(ctx, testJob)

		// Create mock tokens for owner and employee
		tokenOwner, _ := jwtutil.GenerateToken("rate-owner-123", "owner", "rate-owner-123", "owner@example.com")
		tokenEmployee, _ := jwtutil.GenerateToken("rate-employee-123", "employee", "rate-employee-123", "emp@example.com")

		// First rating: Owner rating Employee -> Should succeed (201 Created)
		req1Body := map[string]any{
			"job_id":     jobID,
			"rated_by":   tokenOwner,
			"rated_user": tokenEmployee,
			"stars":      5,
			"comment":    "Great job!",
		}
		body1, _ := json.Marshal(req1Body)
		req1 := httptest.NewRequest("POST", "/users/jobs/rate", bytes.NewReader(body1))
		rec1 := httptest.NewRecorder()
		u.RateJob(rec1, req1)
		if rec1.Code != http.StatusCreated {
			t.Errorf("Expected 201 Created for first rating, got %d. Body: %s", rec1.Code, rec1.Body.String())
		}

		// Second rating: Owner rating Employee again -> Should fail with 409 Conflict
		req2 := httptest.NewRequest("POST", "/users/jobs/rate", bytes.NewReader(body1))
		rec2 := httptest.NewRecorder()
		u.RateJob(rec2, req2)
		if rec2.Code != http.StatusConflict {
			t.Errorf("Expected 409 Conflict for duplicate rating, got %d. Body: %s", rec2.Code, rec2.Body.String())
		}

		// Third rating: Employee rating Owner -> Should succeed (201 Created) since rated_by is different
		req3Body := map[string]any{
			"job_id":     jobID,
			"rated_by":   tokenEmployee,
			"rated_user": tokenOwner,
			"stars":      4,
			"comment":    "Good client.",
		}
		body3, _ := json.Marshal(req3Body)
		req3 := httptest.NewRequest("POST", "/users/jobs/rate", bytes.NewReader(body3))
		rec3 := httptest.NewRecorder()
		u.RateJob(rec3, req3)
		if rec3.Code != http.StatusCreated {
			t.Errorf("Expected 201 Created for employee rating owner, got %d. Body: %s", rec3.Code, rec3.Body.String())
		}
	})

	// Test: ListServices
	t.Run("ListServices", func(t *testing.T) {
		// Happy path (public endpoint, no token required)
		req := httptest.NewRequest("GET", "/users/services", nil)
		rec := httptest.NewRecorder()
		u.ListServices(rec, req)
		if rec.Code != http.StatusOK {
			t.Errorf("Expected 200 OK for ListServices, got %d. Body: %s", rec.Code, rec.Body.String())
		}
	})

	// Test: GetWallet
	t.Run("GetWallet", func(t *testing.T) {
		// Happy path
		req := httptest.NewRequest("GET", "/users/wallet?tenant_id="+tokenApprovedOwner, nil)
		rec := httptest.NewRecorder()
		u.GetWallet(rec, req)
		if rec.Code != http.StatusOK {
			t.Errorf("Expected 200 OK for GetWallet, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		// Missing tenant_id -> 400 Bad Request
		req = httptest.NewRequest("GET", "/users/wallet", nil)
		rec = httptest.NewRecorder()
		u.GetWallet(rec, req)
		if rec.Code != http.StatusBadRequest {
			t.Errorf("Expected 400 Bad Request for missing tenant_id, got %d", rec.Code)
		}

		// Invalid token -> 401 Unauthorized
		req = httptest.NewRequest("GET", "/users/wallet?tenant_id=invalid-token", nil)
		rec = httptest.NewRecorder()
		u.GetWallet(rec, req)
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("Expected 401 Unauthorized for invalid token, got %d", rec.Code)
		}
	})

	// Test: GetLedger
	t.Run("GetLedger", func(t *testing.T) {
		// Happy path
		req := httptest.NewRequest("GET", "/users/ledger?tenant_id="+tokenApprovedOwner, nil)
		rec := httptest.NewRecorder()
		u.GetLedger(rec, req)
		if rec.Code != http.StatusOK {
			t.Errorf("Expected 200 OK for GetLedger, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		// Missing tenant_id -> 400 Bad Request
		req = httptest.NewRequest("GET", "/users/ledger", nil)
		rec = httptest.NewRecorder()
		u.GetLedger(rec, req)
		if rec.Code != http.StatusBadRequest {
			t.Errorf("Expected 400 Bad Request for missing tenant_id, got %d", rec.Code)
		}

		// Invalid token -> 401 Unauthorized
		req = httptest.NewRequest("GET", "/users/ledger?tenant_id=invalid-token", nil)
		rec = httptest.NewRecorder()
		u.GetLedger(rec, req)
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("Expected 401 Unauthorized for invalid token, got %d", rec.Code)
		}
	})

	// Test: GetPlatformConfig
	t.Run("GetPlatformConfig", func(t *testing.T) {
		// Happy path (public endpoint, no token required)
		req := httptest.NewRequest("GET", "/users/platform-config", nil)
		rec := httptest.NewRecorder()
		u.GetPlatformConfig(rec, req)
		if rec.Code != http.StatusOK {
			t.Errorf("Expected 200 OK for GetPlatformConfig, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		// Wrong Method -> 405 Method Not Allowed
		req = httptest.NewRequest("POST", "/users/platform-config", nil)
		rec = httptest.NewRecorder()
		u.GetPlatformConfig(rec, req)
		if rec.Code != http.StatusMethodNotAllowed {
			t.Errorf("Expected 405 Method Not Allowed, got %d", rec.Code)
		}
	})

	// Test: GetRatings
	t.Run("GetRatings", func(t *testing.T) {
		// Happy path (user_id parameter holds the token)
		req := httptest.NewRequest("GET", "/users/ratings?user_id="+tokenApprovedOwner, nil)
		rec := httptest.NewRecorder()
		u.GetRatings(rec, req)
		if rec.Code != http.StatusOK {
			t.Errorf("Expected 200 OK for GetRatings, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		// Validation failure (missing user_id)
		req = httptest.NewRequest("GET", "/users/ratings", nil)
		rec = httptest.NewRecorder()
		u.GetRatings(rec, req)
		if rec.Code != http.StatusBadRequest {
			t.Errorf("Expected 400 Bad Request for missing user_id in GetRatings, got %d", rec.Code)
		}

		// Invalid token -> 401 Unauthorized
		req = httptest.NewRequest("GET", "/users/ratings?user_id=invalid-token", nil)
		rec = httptest.NewRecorder()
		u.GetRatings(rec, req)
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("Expected 401 Unauthorized for invalid token, got %d", rec.Code)
		}
	})

	// Test: Job Cancellation
	t.Run("Job Cancellation", func(t *testing.T) {
		ctx := context.Background()
		rdb.FlushAll(ctx)

		// Setup owners, employees, customers tokens
		tokenOwner, _ := jwtutil.GenerateToken("kyc-approved-owner", "owner", "kyc-approved-owner", "owner@example.com")
		tokenCustomer, _ := jwtutil.GenerateToken("canceller-customer", "user", "canceller-customer", "customer@example.com")

		// 1. Pending Job Cancellation by Owner -> Success
		jobPending1 := &models.Job{
			ID:            "job-pending-1",
			OwnerID:       "kyc-approved-owner",
			UserID:        "canceller-customer",
			Status:        models.JobStatusPending,
			PaymentMethod: "cod",
		}
		_ = s.CreateJob(ctx, jobPending1)

		reqBody := map[string]any{
			"job_id":       "job-pending-1",
			"requester_id": tokenOwner,
			"reason":       "Owner cancel pending",
		}
		body, _ := json.Marshal(reqBody)
		rdb.FlushAll(ctx)
		req := httptest.NewRequest("POST", "/users/jobs/cancel", bytes.NewReader(body))
		rec := httptest.NewRecorder()
		u.CancelJob(rec, req)
		if rec.Code != http.StatusOK {
			t.Errorf("Expected 200 OK for owner cancelling pending job, got %d. Body: %s", rec.Code, rec.Body.String())
		}
		// Verify in DB
		updatedJob := s.GetJob(ctx, "job-pending-1")
		if updatedJob.Status != models.JobStatusCancelled || updatedJob.CancellationReason != "Owner cancel pending" {
			t.Errorf("Expected job status cancelled with reason, got: %s (reason: %s)", updatedJob.Status, updatedJob.CancellationReason)
		}

		// 2. Pending Job Cancellation by Customer -> Success
		jobPending2 := &models.Job{
			ID:            "job-pending-2",
			OwnerID:       "kyc-approved-owner",
			UserID:        "canceller-customer",
			Status:        models.JobStatusPending,
			PaymentMethod: "cod",
		}
		_ = s.CreateJob(ctx, jobPending2)

		reqBody = map[string]any{
			"job_id":       "job-pending-2",
			"requester_id": tokenCustomer,
			"reason":       "Customer cancel pending",
		}
		body, _ = json.Marshal(reqBody)
		rdb.FlushAll(ctx)
		req = httptest.NewRequest("POST", "/users/jobs/cancel", bytes.NewReader(body))
		rec = httptest.NewRecorder()
		u.CancelJob(rec, req)
		if rec.Code != http.StatusOK {
			t.Errorf("Expected 200 OK for customer cancelling pending job, got %d. Body: %s", rec.Code, rec.Body.String())
		}
		updatedJob = s.GetJob(ctx, "job-pending-2")
		if updatedJob.Status != models.JobStatusCancelled {
			t.Errorf("Expected job status cancelled, got: %s", updatedJob.Status)
		}

		// 3. Active Job Cancellation by Customer -> Forbidden (403)
		jobActive1 := &models.Job{
			ID:            "job-active-1",
			OwnerID:       "kyc-approved-owner",
			UserID:        "canceller-customer",
			Status:        models.JobStatusActive,
			PaymentMethod: "cod",
		}
		_ = s.CreateJob(ctx, jobActive1)

		reqBody = map[string]any{
			"job_id":       "job-active-1",
			"requester_id": tokenCustomer,
			"reason":       "Customer tries to cancel active job",
		}
		body, _ = json.Marshal(reqBody)
		rdb.FlushAll(ctx)
		req = httptest.NewRequest("POST", "/users/jobs/cancel", bytes.NewReader(body))
		rec = httptest.NewRecorder()
		u.CancelJob(rec, req)
		if rec.Code != http.StatusForbidden {
			t.Errorf("Expected 403 Forbidden for customer cancelling active job, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		// 4. Active Job Cancellation by Owner -> Success
		reqBody = map[string]any{
			"job_id":       "job-active-1",
			"requester_id": tokenOwner,
			"reason":       "Owner cancels active job",
		}
		body, _ = json.Marshal(reqBody)
		rdb.FlushAll(ctx)
		req = httptest.NewRequest("POST", "/users/jobs/cancel", bytes.NewReader(body))
		rec = httptest.NewRecorder()
		u.CancelJob(rec, req)
		if rec.Code != http.StatusOK {
			t.Errorf("Expected 200 OK for owner cancelling active job, got %d. Body: %s", rec.Code, rec.Body.String())
		}
		updatedJob = s.GetJob(ctx, "job-active-1")
		if updatedJob.Status != models.JobStatusCancelled {
			t.Errorf("Expected job status cancelled, got: %s", updatedJob.Status)
		}

		// 5. Completed Job Cancellation -> Rejected with 409 Conflict
		jobCompleted1 := &models.Job{
			ID:            "job-completed-1",
			OwnerID:       "kyc-approved-owner",
			UserID:        "canceller-customer",
			Status:        models.JobStatusCompleted,
			PaymentMethod: "cod",
		}
		_ = s.CreateJob(ctx, jobCompleted1)

		reqBody = map[string]any{
			"job_id":       "job-completed-1",
			"requester_id": tokenOwner,
			"reason":       "Try to cancel completed job",
		}
		body, _ = json.Marshal(reqBody)
		rdb.FlushAll(ctx)
		req = httptest.NewRequest("POST", "/users/jobs/cancel", bytes.NewReader(body))
		rec = httptest.NewRecorder()
		u.CancelJob(rec, req)
		if rec.Code != http.StatusConflict {
			t.Errorf("Expected 409 Conflict for cancelled completed job, got %d", rec.Code)
		}

		// 6. Already Cancelled Job Cancellation -> Rejected with 409 Conflict
		reqBody = map[string]any{
			"job_id":       "job-pending-1", // already cancelled in step 1
			"requester_id": tokenOwner,
			"reason":       "Try to cancel already cancelled job",
		}
		body, _ = json.Marshal(reqBody)
		rdb.FlushAll(ctx)
		req = httptest.NewRequest("POST", "/users/jobs/cancel", bytes.NewReader(body))
		rec = httptest.NewRecorder()
		u.CancelJob(rec, req)
		if rec.Code != http.StatusConflict {
			t.Errorf("Expected 409 Conflict for already cancelled job, got %d", rec.Code)
		}

		// 7. Complete Cancelled Job -> Rejected with 409 Conflict
		reqCompleteBody := map[string]any{
			"job_id":         "job-pending-1",
			"requester_id":   tokenOwner,
			"cash_collected": true,
		}
		body, _ = json.Marshal(reqCompleteBody)
		rdb.FlushAll(ctx)
		req = httptest.NewRequest("POST", "/users/jobs/complete", bytes.NewReader(body))
		rec = httptest.NewRecorder()
		u.CompleteJob(rec, req)
		if rec.Code != http.StatusConflict {
			t.Errorf("Expected 409 Conflict when completing a cancelled job, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		// 8. Test Escrow Refund on Cancellation for Non-COD Job
		// Setup wallet deposit for non-COD refund testing
		_ = s.Deposit(ctx, "kyc-approved-owner", 500.0)

		// Create a test service
		testSvc := &models.Service{
			ID:               "svc-canceller-999",
			TenantID:         "kyc-approved-owner",
			Name:             "Canceller Service",
			Category:         "transport",
			TenantBasePrice:  10.0,
			TenantPricePerKM: 1.0,
			Latitude:         30.0,
			Longitude:        30.0,
		}
		s.CreateService(ctx, testSvc)

		wBefore, _ := s.GetOrCreateWallet(ctx, "kyc-approved-owner")

		jobNonCOD := &models.Job{
			ID:            "job-non-cod-1",
			OwnerID:       "kyc-approved-owner",
			UserID:        "canceller-customer",
			ServiceID:     "svc-canceller-999",
			Status:        models.JobStatusActive,
			PaymentMethod: "wallet", // non-cod
			Location:      models.Location{Latitude: 30.0, Longitude: 30.0},
		}
		_ = s.CreateJob(ctx, jobNonCOD)

		// Calculate escrow amount (dist = 0, base price = 10.0)
		escrowAmount := 10.0
		// Lock the escrow manually
		err := s.LockEscrow(ctx, "kyc-approved-owner", "job-non-cod-1", escrowAmount)
		if err != nil {
			t.Fatalf("Failed to lock escrow: %v", err)
		}

		// Verify escrow locked
		wLocked, _ := s.GetOrCreateWallet(ctx, "kyc-approved-owner")
		if wLocked.EscrowBalance != escrowAmount {
			t.Errorf("Expected escrow balance to be %.2f, got %.2f", escrowAmount, wLocked.EscrowBalance)
		}

		// Cancel the non-COD job via endpoint
		reqBody = map[string]any{
			"job_id":       "job-non-cod-1",
			"requester_id": tokenOwner,
			"reason":       "Cancel non-COD job to test refund",
		}
		body, _ = json.Marshal(reqBody)
		rdb.FlushAll(ctx)
		req = httptest.NewRequest("POST", "/users/jobs/cancel", bytes.NewReader(body))
		rec = httptest.NewRecorder()
		u.CancelJob(rec, req)
		if rec.Code != http.StatusOK {
			t.Errorf("Expected 200 OK for cancelling non-COD job, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		// Verify escrow refunded
		wRefunded, _ := s.GetOrCreateWallet(ctx, "kyc-approved-owner")
		if wRefunded.EscrowBalance != 0.0 {
			t.Errorf("Expected escrow balance to be 0 after refund, got %.2f", wRefunded.EscrowBalance)
		}
		if wRefunded.WithdrawableBalance != wBefore.WithdrawableBalance {
			t.Errorf("Expected withdrawable balance to return to %.2f, got %.2f", wBefore.WithdrawableBalance, wRefunded.WithdrawableBalance)
		}
	})

	// Test: CompleteJob Deactivated Employee Check
	t.Run("CompleteJob Deactivated Employee", func(t *testing.T) {
		ctx := context.Background()

		// Setup tokens
		tokenActiveEmp, _ := jwtutil.GenerateToken("active-employee", "employee", "kyc-approved-owner", "active@example.com")
		tokenDeactEmp, _ := jwtutil.GenerateToken("deactivated-employee", "employee", "kyc-approved-owner", "deactivated@example.com")

		// Create a service
		testSvc := &models.Service{
			ID:               "svc-deact-999",
			TenantID:         "kyc-approved-owner",
			Name:             "Deact Svc",
			Category:         "transport",
			TenantBasePrice:  10.0,
			TenantPricePerKM: 1.0,
			Latitude:         30.0,
			Longitude:        30.0,
		}
		s.CreateService(ctx, testSvc)

		// 1. Success case: Active employee completing job
		jobActiveEmp := &models.Job{
			ID:            "job-active-emp",
			OwnerID:       "kyc-approved-owner",
			UserID:        "customer-123",
			EmployeeID:    "active-employee",
			ServiceID:     "svc-deact-999",
			Status:        models.JobStatusActive,
			PaymentMethod: "cod",
		}
		_ = s.CreateJob(ctx, jobActiveEmp)

		reqBody := map[string]any{
			"job_id":         "job-active-emp",
			"requester_id":   tokenActiveEmp,
			"cash_collected": true,
		}
		body, _ := json.Marshal(reqBody)
		rdb.FlushAll(ctx)
		req := httptest.NewRequest("POST", "/users/jobs/complete", bytes.NewReader(body))
		rec := httptest.NewRecorder()
		u.CompleteJob(rec, req)
		if rec.Code != http.StatusOK {
			t.Errorf("Expected 200 OK for active employee completing job, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		// 2. Success case: Deactivated employee completing job (allowed under graceful deactivation)
		jobDeactEmp := &models.Job{
			ID:            "job-deact-emp",
			OwnerID:       "kyc-approved-owner",
			UserID:        "customer-123",
			EmployeeID:    "deactivated-employee",
			ServiceID:     "svc-deact-999",
			Status:        models.JobStatusActive,
			PaymentMethod: "cod",
		}
		_ = s.CreateJob(ctx, jobDeactEmp)

		reqBody = map[string]any{
			"job_id":         "job-deact-emp",
			"requester_id":   tokenDeactEmp,
			"cash_collected": true,
		}
		body, _ = json.Marshal(reqBody)
		rdb.FlushAll(ctx)
		req = httptest.NewRequest("POST", "/users/jobs/complete", bytes.NewReader(body))
		rec = httptest.NewRecorder()
		u.CompleteJob(rec, req)
		if rec.Code != http.StatusOK {
			t.Errorf("Expected 200 OK for deactivated employee completing job, got %d. Body: %s", rec.Code, rec.Body.String())
		}
	})

	// Test: TrackJob Deactivated Employee Gating
	t.Run("TrackJob Deactivated Employee Gating", func(t *testing.T) {
		ctx := context.Background()
		tokenOwner, _ := jwtutil.GenerateToken("kyc-approved-owner", "owner", "kyc-approved-owner", "owner@example.com")
		tokenDeactEmp, _ := jwtutil.GenerateToken("deactivated-employee", "employee", "kyc-approved-owner", "deactivated@example.com")
		tokenUser, _ := jwtutil.GenerateToken("client-user-123", "user", "client-user-123", "client@example.com")

		// TrackJob request with deactivated employee
		reqBody := map[string]any{
			"owner_id":       tokenOwner,
			"service_id":     "svc-deact-999",
			"user_id":        tokenUser,
			"employee_id":    tokenDeactEmp,
			"payment_method": "cod",
		}
		body, _ := json.Marshal(reqBody)
		rdb.FlushAll(ctx)
		req := httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(body))
		rec := httptest.NewRecorder()
		u.TrackJob(rec, req)
		if rec.Code != http.StatusBadRequest {
			t.Errorf("Expected 400 Bad Request for assigning deactivated employee in TrackJob, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		// TrackJob request with active employee
		tokenActiveEmp, _ := jwtutil.GenerateToken("active-employee", "employee", "kyc-approved-owner", "active@example.com")
		reqBody["employee_id"] = tokenActiveEmp
		body, _ = json.Marshal(reqBody)
		rdb.FlushAll(ctx)
		req = httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(body))
		rec = httptest.NewRecorder()
		u.TrackJob(rec, req)
		if rec.Code != http.StatusCreated {
			t.Errorf("Expected 201 Created for assigning active employee in TrackJob, got %d. Body: %s", rec.Code, rec.Body.String())
		}
	})
}
