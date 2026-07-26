package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"runtime"
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
	// Initialize MongoDB store for integration testing. Fallback or skip if not running.
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

		if id == "kyc-pending-owner" {
			w.WriteHeader(http.StatusOK)
			json.NewEncoder(w).Encode(map[string]any{
				"id":         "kyc-pending-owner",
				"role":       "owner",
				"kyc_status": "pending_super_admin_approval",
				"is_active":  true,
				"tenant_id":  "kyc-pending-owner",
			})
			return
		}

		if strings.Contains(id, "employee") {
			isActive := !strings.Contains(id, "deactivated")
			tenantID := "kyc-approved-owner"
			if strings.Contains(id, "-under-") {
				parts := strings.Split(id, "-under-")
				if len(parts) > 1 {
					tenantID = parts[1]
				}
			}
			w.WriteHeader(http.StatusOK)
			json.NewEncoder(w).Encode(map[string]any{
				"id":        id,
				"role":      "employee",
				"is_active": isActive,
				"tenant_id": tenantID,
			})
			return
		}

		if strings.Contains(id, "user") {
			w.WriteHeader(http.StatusOK)
			json.NewEncoder(w).Encode(map[string]any{
				"id":        id,
				"role":      "user",
				"is_active": true,
				"tenant_id": "client-user-123",
			})
			return
		}

		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(map[string]string{"error": "user not found"})
	}))
	defer mockAuthServer.Close()

	cfg := &config.Config{
		AuthServiceURL:         mockAuthServer.URL,
		InternalServiceToken:   "mock-internal-token",
		AllowTestPaymentBypass: true,
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

		// E. Empty id query param with valid employee requester_id -> 200 OK with list of jobs
		tokenJobEmployee, _ := jwtutil.GenerateToken("job-employee-999", "employee", "job-employee-999", "employee@example.com")
		req = httptest.NewRequest("GET", "/users/jobs/get?requester_id="+tokenJobEmployee, nil)
		rec = httptest.NewRecorder()
		u.GetJob(rec, req)
		if rec.Code != http.StatusOK {
			t.Errorf("Expected 200 OK for employee listing, got %d. Body: %s", rec.Code, rec.Body.String())
		}
		var jobs []*models.Job
		if err := json.Unmarshal(rec.Body.Bytes(), &jobs); err != nil {
			t.Fatalf("Failed to parse jobs list response: %v", err)
		}
		if len(jobs) == 0 {
			t.Errorf("Expected at least 1 job, got 0")
		}
		found := false
		for _, j := range jobs {
			if j.ID == "test-job-999" {
				found = true
				break
			}
		}
		if !found {
			t.Errorf("Expected to find test-job-999 in employee jobs list")
		}

		// F. IDOR check - query param employee_id does not match the token resolved user -> 403 Forbidden
		req = httptest.NewRequest("GET", "/users/jobs/get?employee_id=different-employee&requester_id="+tokenJobEmployee, nil)
		rec = httptest.NewRecorder()
		u.GetJob(rec, req)
		if rec.Code != http.StatusForbidden {
			t.Errorf("Expected 403 Forbidden for mismatched employee_id query parameter, got %d. Body: %s", rec.Code, rec.Body.String())
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
		rdb.FlushAll(context.Background())
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
			AppEnv:                 "test",
			AuthServiceURL:         mockAuthServer3.URL,
			InternalServiceToken:   "mock-internal-token",
			AllowTestPaymentBypass: true,
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
		rdb.FlushAll(context.Background())
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

		// C. Non-local environment: AppEnv=production -> 400 Bad Request
		rdb.FlushAll(context.Background())
		cfgProd := &config.Config{
			AppEnv:               "production",
			AuthServiceURL:       mockAuthServer3.URL,
			InternalServiceToken: "mock-internal-token",
		}
		uProd := NewUserService(s, cfgProd, rdb)
		reqBody = map[string]any{
			"tenant_id": tokenTenant,
			"amount":    500.0,
		}
		body, _ = json.Marshal(reqBody)
		req = httptest.NewRequest("POST", "/users/wallet/deposit", bytes.NewReader(body))
		rec = httptest.NewRecorder()
		uProd.WalletDeposit(rec, req)
		if rec.Code != http.StatusBadRequest {
			t.Errorf("Expected 400 Bad Request for production env deposit, got %d. Body: %s", rec.Code, rec.Body.String())
		}
		if !strings.Contains(rec.Body.String(), "payment gateway not yet integrated") {
			t.Errorf("Expected gateway integration error message, got: %s", rec.Body.String())
		}

		// D. Unset/Empty environment: AppEnv="" -> 400 Bad Request
		rdb.FlushAll(context.Background())
		cfgUnset := &config.Config{
			AppEnv:               "",
			AuthServiceURL:       mockAuthServer3.URL,
			InternalServiceToken: "mock-internal-token",
		}
		uUnset := NewUserService(s, cfgUnset, rdb)
		req = httptest.NewRequest("POST", "/users/wallet/deposit", bytes.NewReader(body))
		rec = httptest.NewRecorder()
		uUnset.WalletDeposit(rec, req)
		if rec.Code != http.StatusBadRequest {
			t.Errorf("Expected 400 Bad Request for unset env deposit, got %d. Body: %s", rec.Code, rec.Body.String())
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

		// Seed required data to make the subtest self-contained
		_ = s.UpsertSubscription(ctx, &models.Subscription{
			ID:        "sub-owner-777",
			TenantID:  "owner-777",
			Tier:      models.PlanPaid,
			StartedAt: time.Now(),
		})
		_ = s.CreateJob(ctx, &models.Job{
			ID:            "active-job-777",
			OwnerID:       "owner-777",
			EmployeeID:    "employee-777",
			UserID:        "client-777",
			Status:        models.JobStatusActive,
			PaymentMethod: "cod",
		})

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

		// Setup deterministic synchronization using the test hook
		writeStartCh := make(chan struct{})
		writeProceedCh := make(chan struct{})

		u.updateJobLocationBeforeWriteHook = func(hookCtx context.Context) {
			close(writeStartCh)
			<-writeProceedCh
		}
		defer func() {
			u.updateJobLocationBeforeWriteHook = nil
		}()

		// 1. Call UpdateJobLocation with the canceling context in a separate goroutine
		rec := httptest.NewRecorder()
		doneCh := make(chan struct{})
		go func() {
			u.UpdateJobLocation(rec, req)
			close(doneCh)
		}()

		// Wait until handler is about to write to the store (in-flight is set, ready to write)
		<-writeStartCh

		// Cancel the context now, guaranteed to cancel context BEFORE store write finishes (or even starts)
		cancel()

		// Allow the write call to proceed (which will immediately fail due to cancelled context)
		close(writeProceedCh)

		// Wait for the handler call to return
		<-doneCh

		// Disable the hook so that the subsequent retry call is not affected by it
		u.updateJobLocationBeforeWriteHook = nil

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
		// Happy path (requester passes auth header, user_id specifies target user)
		req := httptest.NewRequest("GET", "/users/ratings?user_id=emp-101", nil)
		req.Header.Set("Authorization", "Bearer "+tokenApprovedOwner)
		rec := httptest.NewRecorder()
		u.GetRatings(rec, req)
		if rec.Code != http.StatusOK {
			t.Errorf("Expected 200 OK for GetRatings, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		// Validation failure (missing user_id)
		req = httptest.NewRequest("GET", "/users/ratings", nil)
		req.Header.Set("Authorization", "Bearer "+tokenApprovedOwner)
		rec = httptest.NewRecorder()
		u.GetRatings(rec, req)
		if rec.Code != http.StatusBadRequest {
			t.Errorf("Expected 400 Bad Request for missing user_id in GetRatings, got %d", rec.Code)
		}

		// Invalid requester token -> 401 Unauthorized
		req = httptest.NewRequest("GET", "/users/ratings?user_id=emp-101", nil)
		req.Header.Set("Authorization", "Bearer invalid-token")
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
			ID:                 "job-non-cod-1",
			OwnerID:            "kyc-approved-owner",
			UserID:             "canceller-customer",
			ServiceID:          "svc-canceller-999",
			Status:             models.JobStatusActive,
			PaymentMethod:      "wallet", // non-cod
			LockedEscrowAmount: 10.0,
			Location:           models.Location{Latitude: 30.0, Longitude: 30.0},
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

	// Test: TrackJob Employee Assignment Gating
	t.Run("TrackJob Employee Assignment Gating", func(t *testing.T) {
		ctx := context.Background()
		tokenOwner, _ := jwtutil.GenerateToken("kyc-approved-owner", "owner", "kyc-approved-owner", "owner@example.com")
		tokenDeactEmp, _ := jwtutil.GenerateToken("deactivated-employee", "employee", "kyc-approved-owner", "deactivated@example.com")
		tokenUser, _ := jwtutil.GenerateToken("client-user-123", "user", "client-user-123", "client@example.com")

		// Create a mock service to allow TrackJob to pass initial checks
		testSvc := &models.Service{
			ID:               "svc-deact-999",
			TenantID:         "kyc-approved-owner",
			Name:             "Deact Svc",
			Category:         "transport",
			TenantBasePrice:  10.0,
			TenantPricePerKM: 10.0,
			Latitude:         30.0,
			Longitude:        30.0,
		}
		s.CreateService(ctx, testSvc)

		// 1. TrackJob request with deactivated employee -> rejected
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
		if !strings.Contains(rec.Body.String(), "employee is not active") {
			t.Errorf("Expected error about employee not active, got: %s", rec.Body.String())
		}

		// 2. Assigning another owner's account as employee_id -> rejected
		tokenOtherOwner, _ := jwtutil.GenerateToken("kyc-approved-owner-other", "owner", "kyc-approved-owner-other", "other@example.com")
		reqBody["employee_id"] = tokenOtherOwner
		body, _ = json.Marshal(reqBody)
		rdb.FlushAll(ctx)
		req = httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(body))
		rec = httptest.NewRecorder()
		u.TrackJob(rec, req)
		if rec.Code != http.StatusBadRequest {
			t.Errorf("Expected 400 Bad Request for assigning owner as employee, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		// 3. Assigning a "user" role account as employee_id -> rejected
		reqBody["employee_id"] = tokenUser
		body, _ = json.Marshal(reqBody)
		rdb.FlushAll(ctx)
		req = httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(body))
		rec = httptest.NewRecorder()
		u.TrackJob(rec, req)
		if rec.Code != http.StatusBadRequest {
			t.Errorf("Expected 400 Bad Request for assigning plain user as employee, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		// 4. Assigning an employee belonging to a DIFFERENT owner -> rejected
		tokenDiffOwnerEmp, _ := jwtutil.GenerateToken("employee-under-kyc-approved-owner-other", "employee", "kyc-approved-owner-other", "diffowneremp@example.com")
		reqBody["employee_id"] = tokenDiffOwnerEmp
		body, _ = json.Marshal(reqBody)
		rdb.FlushAll(ctx)
		req = httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(body))
		rec = httptest.NewRecorder()
		u.TrackJob(rec, req)
		if rec.Code != http.StatusBadRequest {
			t.Errorf("Expected 400 Bad Request for assigning employee of different owner, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		// 5. Assigning a valid, active employee belonging to the correct owner -> succeeds
		tokenActiveEmp, _ := jwtutil.GenerateToken("active-employee-under-kyc-approved-owner", "employee", "kyc-approved-owner", "active@example.com")
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

	// Test: TrackJob Customer-Initiated Employee Assignment Gating
	t.Run("TrackJob Customer-Initiated Employee Assignment Gating", func(t *testing.T) {
		ctx := context.Background()
		tokenDeactEmp, _ := jwtutil.GenerateToken("deactivated-employee", "employee", "kyc-approved-owner", "deactivated@example.com")
		tokenUser, _ := jwtutil.GenerateToken("client-user-123", "user", "client-user-123", "client@example.com")

		// Create a mock service to allow TrackJob to pass initial checks
		testSvc := &models.Service{
			ID:               "svc-cust-emp-999",
			TenantID:         "kyc-approved-owner",
			Name:             "Cust Emp Svc",
			Category:         "transport",
			TenantBasePrice:  10.0,
			TenantPricePerKM: 10.0,
			Latitude:         30.0,
			Longitude:        30.0,
		}
		s.CreateService(ctx, testSvc)

		// 1. TrackJob request with deactivated employee -> rejected
		reqBody := map[string]any{
			"service_id":     "svc-cust-emp-999",
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
			t.Errorf("Expected 400 Bad Request for assigning deactivated employee in customer TrackJob, got %d. Body: %s", rec.Code, rec.Body.String())
		}
		if !strings.Contains(rec.Body.String(), "employee is not active") {
			t.Errorf("Expected error about employee not active, got: %s", rec.Body.String())
		}

		// 2. Assigning another owner's account as employee_id -> rejected
		tokenOtherOwner, _ := jwtutil.GenerateToken("kyc-approved-owner-other", "owner", "kyc-approved-owner-other", "other@example.com")
		reqBody["employee_id"] = tokenOtherOwner
		body, _ = json.Marshal(reqBody)
		rdb.FlushAll(ctx)
		req = httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(body))
		rec = httptest.NewRecorder()
		u.TrackJob(rec, req)
		if rec.Code != http.StatusBadRequest {
			t.Errorf("Expected 400 Bad Request for assigning owner as employee in customer TrackJob, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		// 3. Assigning a "user" role account as employee_id -> rejected
		reqBody["employee_id"] = tokenUser
		body, _ = json.Marshal(reqBody)
		rdb.FlushAll(ctx)
		req = httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(body))
		rec = httptest.NewRecorder()
		u.TrackJob(rec, req)
		if rec.Code != http.StatusBadRequest {
			t.Errorf("Expected 400 Bad Request for assigning plain user as employee in customer TrackJob, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		// 4. Assigning an employee belonging to a DIFFERENT owner -> rejected
		tokenDiffOwnerEmp, _ := jwtutil.GenerateToken("employee-under-kyc-approved-owner-other", "employee", "kyc-approved-owner-other", "diffowneremp@example.com")
		reqBody["employee_id"] = tokenDiffOwnerEmp
		body, _ = json.Marshal(reqBody)
		rdb.FlushAll(ctx)
		req = httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(body))
		rec = httptest.NewRecorder()
		u.TrackJob(rec, req)
		if rec.Code != http.StatusBadRequest {
			t.Errorf("Expected 400 Bad Request for assigning employee of different owner in customer TrackJob, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		// 5. Assigning a valid, active employee belonging to the correct owner -> succeeds
		tokenActiveEmp, _ := jwtutil.GenerateToken("active-employee-under-kyc-approved-owner", "employee", "kyc-approved-owner", "active@example.com")
		reqBody["employee_id"] = tokenActiveEmp
		body, _ = json.Marshal(reqBody)
		rdb.FlushAll(ctx)
		req = httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(body))
		rec = httptest.NewRecorder()
		u.TrackJob(rec, req)
		if rec.Code != http.StatusCreated {
			t.Errorf("Expected 201 Created for assigning active employee in customer TrackJob, got %d. Body: %s", rec.Code, rec.Body.String())
		}
	})

	// Test: Escrow Integrity and Speed Validation
	t.Run("Escrow Integrity and Speed Validation", func(t *testing.T) {
		u.appEnv = "test"
		defer func() { u.appEnv = "" }()
		ctx := context.Background()
		tokenEmp, _ := jwtutil.GenerateToken("active-employee", "employee", "kyc-approved-owner-integrity", "employee@example.com")

		// 1. Setup service
		testSvc := &models.Service{
			ID:               "svc-escrow-integrity-999",
			TenantID:         "kyc-approved-owner-integrity",
			Name:             "Integrity Svc",
			Category:         "transport",
			TenantBasePrice:  10.0,
			TenantPricePerKM: 10.0,
			Latitude:         30.0,
			Longitude:        30.0,
		}
		s.CreateService(ctx, testSvc)

		// 2. Setup subscription and wallet for owner using public store APIs
		_ = s.UpsertSubscription(ctx, &models.Subscription{
			ID:        "sub-integrity-owner",
			TenantID:  "kyc-approved-owner-integrity",
			Tier:      models.PlanPaid,
			StartedAt: time.Now(),
		})
		_ = s.Deposit(ctx, "kyc-approved-owner-integrity", 150.0)
		_ = s.LockEscrow(ctx, "kyc-approved-owner-integrity", "job-integrity-A", 100.0)
		_ = s.LockEscrow(ctx, "kyc-approved-owner-integrity", "job-integrity-B", 50.0)

		// 3. Setup two jobs for the same owner
		jobA := &models.Job{
			ID:                 "job-integrity-A",
			OwnerID:            "kyc-approved-owner-integrity",
			UserID:             "customer-123",
			EmployeeID:         "active-employee",
			ServiceID:          "svc-escrow-integrity-999",
			Status:             models.JobStatusActive,
			PaymentMethod:      "wallet",
			LockedEscrowAmount: 100.0,
			Location: models.Location{
				Latitude:  30.1, // dist approx 15.6 km -> cost approx 166.0
				Longitude: 30.1,
			},
			CreatedAt: time.Now().Add(-1 * time.Hour),
		}

		jobB := &models.Job{
			ID:                 "job-integrity-B",
			OwnerID:            "kyc-approved-owner-integrity",
			UserID:             "customer-123",
			EmployeeID:         "active-employee",
			ServiceID:          "svc-escrow-integrity-999",
			Status:             models.JobStatusActive,
			PaymentMethod:      "wallet",
			LockedEscrowAmount: 50.0,
			Location: models.Location{
				Latitude:  31.0, // dist approx 150 km -> cost approx 1510.0
				Longitude: 31.0,
			},
			CreatedAt: time.Now().Add(-1 * time.Hour),
		}

		_ = s.CreateJob(ctx, jobA)
		_ = s.CreateJob(ctx, jobB)

		// (a) Regression Test: CompleteJob capped at LockedEscrowAmount
		reqBody := map[string]any{
			"job_id":       "job-integrity-B",
			"requester_id": tokenEmp,
		}
		body, _ := json.Marshal(reqBody)
		req := httptest.NewRequest("POST", "/users/jobs/complete", bytes.NewReader(body))
		rec := httptest.NewRecorder()
		u.CompleteJob(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK for capped CompleteJob, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		var resp map[string]any
		_ = json.Unmarshal(rec.Body.Bytes(), &resp)
		totalAmt, _ := resp["total_amount"].(float64)
		if totalAmt != 50.0 {
			t.Errorf("Expected completion payout to be capped at Job B's LockedEscrowAmount (50.0), got %.2f", totalAmt)
		}

		// Verify jobB is completed and has locked escrow zeroed/decremented in DB
		updatedJobB := s.GetJob(ctx, "job-integrity-B")
		if updatedJobB.Status != models.JobStatusCompleted {
			t.Errorf("Expected job B status to be Completed, got %s", updatedJobB.Status)
		}
		if updatedJobB.LockedEscrowAmount != 0.0 {
			t.Errorf("Expected job B locked escrow amount to be 0.0 after completion, got %.2f", updatedJobB.LockedEscrowAmount)
		}

		// (b) Regression Test: Job A's locked escrow was not drawn down by Job B
		updatedJobA := s.GetJob(ctx, "job-integrity-A")
		if updatedJobA.LockedEscrowAmount != 100.0 {
			t.Errorf("Expected job A locked escrow to remain 100.0, got %.2f", updatedJobA.LockedEscrowAmount)
		}

		wallet, _ := s.GetOrCreateWallet(ctx, "kyc-approved-owner-integrity")
		// Payout for Job B was 50.0. platform fee = 15% of 50.0 = 7.5. net = 42.5.
		// Wallet escrow should go from 150.0 to 100.0 (still locking job A's 100.0 escrow).
		if wallet.EscrowBalance != 100.0 {
			t.Errorf("Expected wallet escrow balance to be exactly 100.0, got %.2f", wallet.EscrowBalance)
		}

		// Direct call to ReleaseEscrowWithSplit for Job B again (or for more than locked) should fail
		err := s.ReleaseEscrowWithSplit(ctx, "kyc-approved-owner-integrity", "job-integrity-B", 10.0)
		if err == nil {
			t.Error("Expected ReleaseEscrowWithSplit to fail for already completed/fully-released job")
		}

		// (c) Regression Test: UpdateJobLocation rejects implausible-speed jump
		jobC := &models.Job{
			ID:                 "job-integrity-C",
			OwnerID:            "kyc-approved-owner-integrity",
			UserID:             "customer-123",
			EmployeeID:         "active-employee",
			ServiceID:          "svc-escrow-integrity-999",
			Status:             models.JobStatusActive,
			PaymentMethod:      "wallet",
			LockedEscrowAmount: 50.0,
			Location: models.Location{
				Latitude:  30.0,
				Longitude: 30.0,
			},
			CreatedAt: time.Now().Add(-1 * time.Hour),
		}
		_ = s.CreateJob(ctx, jobC)

		// Set last update time to 1 hour ago
		u.locationThrottleMu.Lock()
		u.locationLastUpdate[jobC.ID] = time.Now().Add(-1 * time.Hour)
		u.locationThrottleMu.Unlock()

		// Attempt to update location 500 km away (implausible speed for 1 hour)
		locReqBody := map[string]any{
			"job_id":       "job-integrity-C",
			"requester_id": tokenEmp,
			"latitude":     35.0, // approx 500+ km away
			"longitude":    30.0,
		}
		locBody, _ := json.Marshal(locReqBody)
		locReq := httptest.NewRequest("POST", "/users/jobs/location/update", bytes.NewReader(locBody))
		locRec := httptest.NewRecorder()
		u.UpdateJobLocation(locRec, locReq)

		if locRec.Code != http.StatusBadRequest {
			t.Errorf("Expected 400 Bad Request for implausible speed, got %d. Body: %s", locRec.Code, locRec.Body.String())
		}
		var locResp map[string]any
		_ = json.Unmarshal(locRec.Body.Bytes(), &locResp)
		if locResp["error"] != "implausible_speed" {
			t.Errorf("Expected error to be 'implausible_speed', got %v", locResp["error"])
		}
	})

	// Test: Zero-Value Escrow and TrackJob Rollback
	t.Run("Zero-Value Escrow and TrackJob Rollback", func(t *testing.T) {
		u.appEnv = "test"
		defer func() { u.appEnv = "" }()
		ctx := context.Background()
		tokenEmp, _ := jwtutil.GenerateToken("active-employee-under-kyc-approved-owner-zeroval", "employee", "kyc-approved-owner-zeroval", "employee@example.com")
		tokenOwner, _ := jwtutil.GenerateToken("kyc-approved-owner-zeroval", "owner", "kyc-approved-owner-zeroval", "owner@example.com")

		// 1. Setup service
		testSvc := &models.Service{
			ID:               "svc-zeroval-999",
			TenantID:         "kyc-approved-owner-zeroval",
			Name:             "Zeroval Svc",
			Category:         "transport",
			TenantBasePrice:  10.0,
			TenantPricePerKM: 10.0,
			Latitude:         30.0,
			Longitude:        30.0,
		}
		s.CreateService(ctx, testSvc)

		// 2. Setup wallet for owner
		_ = s.Deposit(ctx, "kyc-approved-owner-zeroval", 100.0)

		// (a) Test: CompleteJob/CancelJob with LockedEscrowAmount == 0 fails closed
		jobZero := &models.Job{
			ID:                 "job-zeroval-zero",
			OwnerID:            "kyc-approved-owner-zeroval",
			UserID:             "customer-123",
			EmployeeID:         "active-employee-under-kyc-approved-owner-zeroval",
			ServiceID:          "svc-zeroval-999",
			Status:             models.JobStatusActive,
			PaymentMethod:      "wallet",
			LockedEscrowAmount: 0.0, // Explicitly zero
			Location: models.Location{
				Latitude:  30.1,
				Longitude: 30.1,
			},
			CreatedAt: time.Now().Add(-1 * time.Hour),
		}
		_ = s.CreateJob(ctx, jobZero)
		_ = s.LockEscrow(ctx, "kyc-approved-owner-zeroval", "job-zeroval-zero", 50.0) // lock some wallet escrow but job record has 0

		// Attempt CompleteJob
		reqBody := map[string]any{
			"job_id":       "job-zeroval-zero",
			"requester_id": tokenEmp,
		}
		body, _ := json.Marshal(reqBody)
		req := httptest.NewRequest("POST", "/users/jobs/complete", bytes.NewReader(body))
		rec := httptest.NewRecorder()
		u.CompleteJob(rec, req)

		if rec.Code != http.StatusBadRequest {
			t.Errorf("Expected 400 Bad Request for zero LockedEscrowAmount CompleteJob, got %d. Body: %s", rec.Code, rec.Body.String())
		}
		var resp map[string]any
		_ = json.Unmarshal(rec.Body.Bytes(), &resp)
		if resp["error"] != "escrow_amount_unrecorded" {
			t.Errorf("Expected error 'escrow_amount_unrecorded', got %v", resp["error"])
		}

		// Attempt CancelJob
		cancelReqBody := map[string]any{
			"job_id":       "job-zeroval-zero",
			"requester_id": tokenOwner,
			"reason":       "testing zero value",
		}
		cancelBody, _ := json.Marshal(cancelReqBody)
		cancelReq := httptest.NewRequest("POST", "/users/jobs/cancel", bytes.NewReader(cancelBody))
		cancelRec := httptest.NewRecorder()
		u.CancelJob(cancelRec, cancelReq)

		if cancelRec.Code != http.StatusBadRequest {
			t.Errorf("Expected 400 Bad Request for zero LockedEscrowAmount CancelJob, got %d. Body: %s", cancelRec.Code, cancelRec.Body.String())
		}
		var cancelResp map[string]any
		_ = json.Unmarshal(cancelRec.Body.Bytes(), &cancelResp)
		if cancelResp["error"] != "escrow_amount_unrecorded" {
			t.Errorf("Expected error 'escrow_amount_unrecorded', got %v", cancelResp["error"])
		}

		// (b) Test: TrackJob fails cleanly and rolls back wallet/deletes job if UpdateJobLockedEscrow fails
		mockCtx := &contextMock{
			Context: context.Background(),
		}

		// Deposit funds for the track job
		_ = s.Deposit(ctx, "kyc-approved-owner-zeroval", 500.0)

		tokenUser, _ := jwtutil.GenerateToken("customer-123", "user", "kyc-approved-owner-zeroval", "customer@example.com")
		trackReqBody := map[string]any{
			"owner_id":       tokenOwner,
			"service_id":     "svc-zeroval-999",
			"user_id":        tokenUser,
			"employee_id":    tokenEmp,
			"payment_method": "wallet",
			"location": models.Location{
				Latitude:  30.1,
				Longitude: 30.1,
			},
		}
		trackBody, _ := json.Marshal(trackReqBody)
		trackReq := httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(trackBody))
		trackReq = trackReq.WithContext(mockCtx)
		trackRec := httptest.NewRecorder()

		u.TrackJob(trackRec, trackReq)

		if trackRec.Code != http.StatusInternalServerError {
			t.Errorf("Expected 500 Internal Server Error when DB update fails, got %d. Body: %s", trackRec.Code, trackRec.Body.String())
		}

		// Verify wallet escrow balance was rolled back (should go back to 50.0 from jobZero)
		finalWallet, _ := s.GetOrCreateWallet(ctx, "kyc-approved-owner-zeroval")
		if finalWallet.EscrowBalance != 50.0 {
			t.Errorf("Expected wallet escrow balance to roll back to 50.0, got %.2f", finalWallet.EscrowBalance)
		}

		// Verify job record was deleted
		count, err := s.CountJobsByOwner(ctx, "kyc-approved-owner-zeroval")
		if err != nil {
			t.Errorf("failed to count jobs: %v", err)
		}
		if count != 1 {
			t.Errorf("Expected only 1 job to exist in DB for owner, got %d", count)
		}

		retrievedJob := s.GetJob(ctx, "job-zeroval-zero")
		if retrievedJob == nil || retrievedJob.ID != "job-zeroval-zero" {
			t.Error("Expected job-zeroval-zero to exist in DB")
		}
	})

	// Test: Concurrency Race-Condition Verification
	t.Run("Concurrency Race-Condition Verification", func(t *testing.T) {
		u.appEnv = "test"
		defer func() { u.appEnv = "" }()
		ctx := context.Background()
		tokenEmp, _ := jwtutil.GenerateToken("active-employee", "employee", "kyc-approved-owner-concurrency", "employee@example.com")
		tokenOwner, _ := jwtutil.GenerateToken("kyc-approved-owner-concurrency", "owner", "kyc-approved-owner-concurrency", "owner@example.com")

		// 1. Setup service
		testSvc := &models.Service{
			ID:               "svc-concurrency-999",
			TenantID:         "kyc-approved-owner-concurrency",
			Name:             "Concurrency Svc",
			Category:         "transport",
			TenantBasePrice:  10.0,
			TenantPricePerKM: 10.0,
			Latitude:         30.0,
			Longitude:        30.0,
		}
		s.CreateService(ctx, testSvc)

		// 2. Setup wallet for owner
		_ = s.Deposit(ctx, "kyc-approved-owner-concurrency", 500.0)

		// (a) Test: Concurrent CompleteJob vs CancelJob
		job := &models.Job{
			ID:                 "job-concurrency-AB",
			OwnerID:            "kyc-approved-owner-concurrency",
			UserID:             "customer-123",
			EmployeeID:         "active-employee",
			ServiceID:          "svc-concurrency-999",
			Status:             models.JobStatusActive,
			PaymentMethod:      "wallet",
			LockedEscrowAmount: 100.0,
			Location: models.Location{
				Latitude:  30.1, // dist approx 15.6 km -> cost approx 166.0 (capped at 100.0)
				Longitude: 30.1,
			},
			CreatedAt: time.Now().Add(-1 * time.Hour),
		}
		_ = s.CreateJob(ctx, job)
		_ = s.LockEscrow(ctx, "kyc-approved-owner-concurrency", "job-concurrency-AB", 100.0)

		var wg sync.WaitGroup
		wg.Add(2)

		recComplete := httptest.NewRecorder()
		recCancel := httptest.NewRecorder()

		reqCompleteBody := map[string]any{
			"job_id":       "job-concurrency-AB",
			"requester_id": tokenEmp,
		}
		compBody, _ := json.Marshal(reqCompleteBody)
		reqComplete := httptest.NewRequest("POST", "/users/jobs/complete", bytes.NewReader(compBody))

		reqCancelBody := map[string]any{
			"job_id":       "job-concurrency-AB",
			"requester_id": tokenOwner,
			"reason":       "cancel concurrent test",
		}
		cancelBody, _ := json.Marshal(reqCancelBody)
		reqCancel := httptest.NewRequest("POST", "/users/jobs/cancel", bytes.NewReader(cancelBody))

		go func() {
			defer wg.Done()
			u.CompleteJob(recComplete, reqComplete)
		}()

		go func() {
			defer wg.Done()
			u.CancelJob(recCancel, reqCancel)
		}()

		wg.Wait()

		// Verify: Exactly one succeeded (200), and the other got a conflict/error
		successCount := 0
		failCount := 0
		if recComplete.Code == http.StatusOK {
			successCount++
		} else {
			failCount++
		}
		if recCancel.Code == http.StatusOK {
			successCount++
		} else {
			failCount++
		}

		if successCount != 1 || failCount != 1 {
			t.Errorf("Complete vs Cancel: Expected exactly 1 success and 1 failure, got success=%d, fail=%d. Complete code: %d, Cancel code: %d", successCount, failCount, recComplete.Code, recCancel.Code)
		}

		// Verify the wallet/ledger has either released escrow or refunded escrow, but not both.
		wallet, _ := s.GetOrCreateWallet(ctx, "kyc-approved-owner-concurrency")
		if wallet.EscrowBalance != 0.0 {
			t.Errorf("Expected wallet escrow balance to be 0, got %.2f", wallet.EscrowBalance)
		}
		// Complete won: total=485 (500 - 15 fee). Cancel won: total=500.
		if wallet.TotalBalance != 485.0 && wallet.TotalBalance != 500.0 {
			t.Errorf("Expected wallet total balance to be either 485.0 (complete won) or 500.0 (cancel won), got %.2f", wallet.TotalBalance)
		}

		// (b) Test: Concurrent CompleteJob vs CompleteJob
		jobC := &models.Job{
			ID:                 "job-concurrency-CC",
			OwnerID:            "kyc-approved-owner-concurrency",
			UserID:             "customer-123",
			EmployeeID:         "active-employee",
			ServiceID:          "svc-concurrency-999",
			Status:             models.JobStatusActive,
			PaymentMethod:      "wallet",
			LockedEscrowAmount: 100.0,
			Location: models.Location{
				Latitude:  30.1,
				Longitude: 30.1,
			},
			CreatedAt: time.Now().Add(-1 * time.Hour),
		}
		_ = s.CreateJob(ctx, jobC)
		// Deposit and Lock Escrow
		_ = s.Deposit(ctx, "kyc-approved-owner-concurrency", 100.0)
		_ = s.LockEscrow(ctx, "kyc-approved-owner-concurrency", "job-concurrency-CC", 100.0)

		wg.Add(2)
		recComp1 := httptest.NewRecorder()
		recComp2 := httptest.NewRecorder()

		reqCompBodyC := map[string]any{
			"job_id":       "job-concurrency-CC",
			"requester_id": tokenEmp,
		}
		compBodyC, _ := json.Marshal(reqCompBodyC)
		reqComp1 := httptest.NewRequest("POST", "/users/jobs/complete", bytes.NewReader(compBodyC))
		reqComp2 := httptest.NewRequest("POST", "/users/jobs/complete", bytes.NewReader(compBodyC))

		go func() {
			defer wg.Done()
			u.CompleteJob(recComp1, reqComp1)
		}()

		go func() {
			defer wg.Done()
			u.CompleteJob(recComp2, reqComp2)
		}()

		wg.Wait()

		successCount = 0
		failCount = 0
		if recComp1.Code == http.StatusOK {
			successCount++
		} else {
			failCount++
		}
		if recComp2.Code == http.StatusOK {
			successCount++
		} else {
			failCount++
		}

		if successCount != 1 || failCount != 1 {
			t.Errorf("Complete vs Complete: Expected exactly 1 success and 1 failure, got success=%d, fail=%d. Comp1 code: %d, Comp2 code: %d", successCount, failCount, recComp1.Code, recComp2.Code)
		}

		// (c) Test: Concurrent CancelJob vs CancelJob
		jobX := &models.Job{
			ID:                 "job-concurrency-XX",
			OwnerID:            "kyc-approved-owner-concurrency",
			UserID:             "customer-123",
			EmployeeID:         "active-employee",
			ServiceID:          "svc-concurrency-999",
			Status:             models.JobStatusActive,
			PaymentMethod:      "wallet",
			LockedEscrowAmount: 100.0,
			Location: models.Location{
				Latitude:  30.1,
				Longitude: 30.1,
			},
			CreatedAt: time.Now().Add(-1 * time.Hour),
		}
		_ = s.CreateJob(ctx, jobX)
		// Deposit and Lock Escrow
		_ = s.Deposit(ctx, "kyc-approved-owner-concurrency", 100.0)
		_ = s.LockEscrow(ctx, "kyc-approved-owner-concurrency", "job-concurrency-XX", 100.0)

		wg.Add(2)
		recCancel1 := httptest.NewRecorder()
		recCancel2 := httptest.NewRecorder()

		reqCancelBodyX := map[string]any{
			"job_id":       "job-concurrency-XX",
			"requester_id": tokenOwner,
			"reason":       "cancel concurrent test",
		}
		cancelBodyX, _ := json.Marshal(reqCancelBodyX)
		reqCancel1 := httptest.NewRequest("POST", "/users/jobs/cancel", bytes.NewReader(cancelBodyX))
		reqCancel2 := httptest.NewRequest("POST", "/users/jobs/cancel", bytes.NewReader(cancelBodyX))

		go func() {
			defer wg.Done()
			u.CancelJob(recCancel1, reqCancel1)
		}()

		go func() {
			defer wg.Done()
			u.CancelJob(recCancel2, reqCancel2)
		}()

		wg.Wait()

		successCount = 0
		failCount = 0
		if recCancel1.Code == http.StatusOK {
			successCount++
		} else {
			failCount++
		}
		if recCancel2.Code == http.StatusOK {
			successCount++
		} else {
			failCount++
		}

		if successCount != 1 || failCount != 1 {
			t.Errorf("Cancel vs Cancel: Expected exactly 1 success and 1 failure, got success=%d, fail=%d. Cancel1 code: %d, Cancel2 code: %d", successCount, failCount, recCancel1.Code, recCancel2.Code)
		}

		// (d) Test: Concurrent COD CompleteJob vs CompleteJob (COD path)
		jobCOD := &models.Job{
			ID:                 "job-concurrency-COD",
			OwnerID:            "kyc-approved-owner-concurrency",
			UserID:             "customer-123",
			EmployeeID:         "active-employee",
			ServiceID:          "svc-concurrency-999",
			Status:             models.JobStatusActive,
			PaymentMethod:      "cod",
			LockedEscrowAmount: 0.0,
			Location: models.Location{
				Latitude:  30.1,
				Longitude: 30.1,
			},
			CreatedAt: time.Now().Add(-1 * time.Hour),
		}
		_ = s.CreateJob(ctx, jobCOD)

		// Record initial platform and owner wallet balances
		wBefore, _ := s.GetOrCreateWallet(ctx, "kyc-approved-owner-concurrency")
		wPlatBefore, _ := s.GetOrCreateWallet(ctx, "platform")

		wg.Add(2)
		recCompCOD1 := httptest.NewRecorder()
		recCompCOD2 := httptest.NewRecorder()

		reqCompCODBody := map[string]any{
			"job_id":         "job-concurrency-COD",
			"requester_id":   tokenEmp,
			"cash_collected": true,
		}
		compCODBody, _ := json.Marshal(reqCompCODBody)
		reqCompCOD1 := httptest.NewRequest("POST", "/users/jobs/complete", bytes.NewReader(compCODBody))
		reqCompCOD2 := httptest.NewRequest("POST", "/users/jobs/complete", bytes.NewReader(compCODBody))

		go func() {
			defer wg.Done()
			u.CompleteJob(recCompCOD1, reqCompCOD1)
		}()

		go func() {
			defer wg.Done()
			u.CompleteJob(recCompCOD2, reqCompCOD2)
		}()

		wg.Wait()

		successCount = 0
		failCount = 0
		if recCompCOD1.Code == http.StatusOK {
			successCount++
		} else {
			failCount++
		}
		if recCompCOD2.Code == http.StatusOK {
			successCount++
		} else {
			failCount++
		}

		if successCount != 1 || failCount != 1 {
			t.Errorf("COD Complete vs Complete: Expected exactly 1 success and 1 failure, got success=%d, fail=%d. Comp1 code: %d, Comp2 code: %d", successCount, failCount, recCompCOD1.Code, recCompCOD2.Code)
		}

		// Verify exactly one fee deduction on the owner wallet, and one fee credit to platform wallet
		wAfter, _ := s.GetOrCreateWallet(ctx, "kyc-approved-owner-concurrency")
		wPlatAfter, _ := s.GetOrCreateWallet(ctx, "platform")

		expectedFeeDeduction := wBefore.TotalBalance - wAfter.TotalBalance
		if expectedFeeDeduction <= 0.0 {
			t.Errorf("Expected positive fee deduction from owner's wallet, got balance difference: %.2f -> %.2f", wBefore.TotalBalance, wAfter.TotalBalance)
		}

		platFeeCredit := wPlatAfter.TotalBalance - wPlatBefore.TotalBalance
		if platFeeCredit <= 0.0 {
			t.Errorf("Expected positive platform fee credit, got balance difference: %.2f -> %.2f", wPlatBefore.TotalBalance, wPlatAfter.TotalBalance)
		}

		// Verify that exactly one ledger entry exists for this job in the ledger
		entries := s.GetLedger(ctx, "kyc-approved-owner-concurrency")
		codLedgerCount := 0
		for _, entry := range entries {
			if entry.JobID == "job-concurrency-COD" {
				codLedgerCount++
			}
		}
		if codLedgerCount != 1 {
			t.Errorf("Expected exactly 1 ledger entry for job-concurrency-COD, got %d", codLedgerCount)
		}
	})

	// Test: Geographic Coordinate Bounds Validation
	t.Run("Geographic Coordinate Bounds Validation", func(t *testing.T) {
		u.appEnv = "test"
		defer func() { u.appEnv = "" }()

		// Setup a mock service, subscription, and job for UpdateJobLocation
		ctx := context.Background()
		testSvc := &models.Service{
			ID:               "svc-coords-validation",
			TenantID:         "kyc-approved-owner",
			Name:             "Coords Validation Svc",
			Category:         "transport",
			TenantBasePrice:  10.0,
			TenantPricePerKM: 10.0,
			Latitude:         0.0,
			Longitude:        0.0,
		}
		s.CreateService(ctx, testSvc)

		_ = s.UpsertSubscription(ctx, &models.Subscription{
			ID:        "sub-coords-validation",
			TenantID:  "kyc-approved-owner",
			Tier:      models.PlanPaid,
			StartedAt: time.Now(),
		})

		activeJob := &models.Job{
			ID:            "job-coords-validation",
			OwnerID:       "kyc-approved-owner",
			UserID:        "client-user-123",
			EmployeeID:    "active-employee",
			ServiceID:     "svc-coords-validation",
			Status:        models.JobStatusActive,
			PaymentMethod: "cod",
			Location:      models.Location{Latitude: 0.0, Longitude: 0.0},
			CreatedAt:     time.Now().Add(-1 * time.Hour),
		}
		s.CreateJob(ctx, activeJob)

		tokenEmp, _ := jwtutil.GenerateToken("active-employee", "employee", "kyc-approved-owner", "employee@example.com")

		// 1. TrackJob Coordinate Checks
		trackJobCases := []struct {
			name           string
			lat, lon       float64
			expectedStatus int
			expectedError  string
		}{
			{"Valid coords pass", 45.0, 90.0, http.StatusCreated, ""},
			{"Boundary lat max", 90.0, 180.0, http.StatusCreated, ""},
			{"Boundary lat min", -90.0, -180.0, http.StatusCreated, ""},
			{"Lat too high", 90.1, 0.0, http.StatusBadRequest, "invalid_coordinates"},
			{"Lat too low", -90.1, 0.0, http.StatusBadRequest, "invalid_coordinates"},
			{"Lon too high", 0.0, 180.1, http.StatusBadRequest, "invalid_coordinates"},
			{"Lon too low", 0.0, -180.1, http.StatusBadRequest, "invalid_coordinates"},
		}

		for i, tc := range trackJobCases {
			t.Run("TrackJob - "+tc.name, func(t *testing.T) {
				reqBody := map[string]any{
					"owner_id":       tokenApprovedOwner,
					"user_id":        tokenClientUser,
					"service_id":     "svc-coords-validation",
					"payment_method": "cod",
					"location": map[string]float64{
						"latitude":  tc.lat,
						"longitude": tc.lon,
					},
				}
				body, _ := json.Marshal(reqBody)
				req := httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(body))
				req.Header.Set("X-Real-IP", fmt.Sprintf("192.168.2.%d", i+1))
				rec := httptest.NewRecorder()

				u.TrackJob(rec, req)

				if rec.Code != tc.expectedStatus {
					t.Errorf("expected status %d, got %d. Body: %s", tc.expectedStatus, rec.Code, rec.Body.String())
				}

				if tc.expectedError != "" {
					var resp map[string]string
					json.Unmarshal(rec.Body.Bytes(), &resp)
					if resp["error"] != tc.expectedError {
						t.Errorf("expected error %q, got %q", tc.expectedError, resp["error"])
					}
				}
			})
		}

		// 2. UpdateJobLocation Coordinate Checks
		updateLocCases := []struct {
			name           string
			lat, lon       float64
			expectedStatus int
			expectedError  string
		}{
			{"Valid coords pass", 0.1, 0.1, http.StatusOK, ""}, // near prev location to avoid speed trigger
			{"Lat too high", 90.1, 0.0, http.StatusBadRequest, "invalid_coordinates"},
			{"Lat too low", -90.1, 0.0, http.StatusBadRequest, "invalid_coordinates"},
			{"Lon too high", 0.0, 180.1, http.StatusBadRequest, "invalid_coordinates"},
			{"Lon too low", 0.0, -180.1, http.StatusBadRequest, "invalid_coordinates"},
		}

		for i, tc := range updateLocCases {
			t.Run("UpdateLoc - "+tc.name, func(t *testing.T) {
				// Clear location throttle and inflight state for each run
				u.locationThrottleMu.Lock()
				delete(u.locationInFlight, "job-coords-validation")
				delete(u.locationLastUpdate, "job-coords-validation")
				u.locationThrottleMu.Unlock()

				reqBody := map[string]any{
					"job_id":       "job-coords-validation",
					"requester_id": tokenEmp,
					"latitude":     tc.lat,
					"longitude":    tc.lon,
				}
				body, _ := json.Marshal(reqBody)
				req := httptest.NewRequest("POST", "/users/jobs/location/update", bytes.NewReader(body))
				req.Header.Set("X-Real-IP", fmt.Sprintf("192.168.3.%d", i+1))
				rec := httptest.NewRecorder()

				u.UpdateJobLocation(rec, req)

				if rec.Code != tc.expectedStatus {
					t.Errorf("expected status %d, got %d. Body: %s", tc.expectedStatus, rec.Code, rec.Body.String())
				}

				if tc.expectedError != "" {
					var resp map[string]string
					json.Unmarshal(rec.Body.Bytes(), &resp)
					if resp["error"] != tc.expectedError {
						t.Errorf("expected error %q, got %q", tc.expectedError, resp["error"])
					}
				}
			})
		}
	})

	// Test: TrackJob Security - Owner ID server-side resolution and spoofing prevention
	t.Run("TrackJob Security - Owner ID server-side resolution", func(t *testing.T) {
		// Create a mock service belonging to "kyc-approved-owner"
		svcID := "secure-service-123"
		mockSvc := &models.Service{
			ID:               svcID,
			TenantID:         "kyc-approved-owner",
			Name:             "Secure Ride Service",
			Category:         "transport",
			TenantBasePrice:  10.0,
			TenantPricePerKM: 2.0,
			Latitude:         30.0,
			Longitude:        31.0,
		}
		s.CreateService(context.Background(), mockSvc)

		// Let's verify: a customer booking a job with service_id resolves owner ID server-side.
		// (a) Customer books WITHOUT supplying owner_id in request body
		reqBody := map[string]any{
			"user_id":        tokenClientUser,
			"service_id":     svcID,
			"payment_method": "cod",
			"location": map[string]any{
				"latitude":  30.0,
				"longitude": 31.0,
			},
		}
		body, _ := json.Marshal(reqBody)
		req := httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(body))
		req.Header.Set("X-Real-IP", "192.168.99.1")
		rec := httptest.NewRecorder()

		u.TrackJob(rec, req)

		if rec.Code != http.StatusCreated {
			t.Fatalf("Expected 201 Created for customer booking, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		var resp map[string]any
		json.Unmarshal(rec.Body.Bytes(), &resp)
		jobData, ok := resp["job"].(map[string]any)
		if !ok {
			t.Fatalf("Response does not contain job data")
		}

		// Verify resolved owner_id matches service TenantID ("kyc-approved-owner")
		if jobData["owner_id"] != "kyc-approved-owner" {
			t.Errorf("Expected owner_id to be resolved to 'kyc-approved-owner', got %v", jobData["owner_id"])
		}

		// (b) Customer books with an arbitrary/spoofed owner_id (raw ID format) -> rejected
		reqBodySpoofRaw := map[string]any{
			"owner_id":       "kyc-approved-owner", // raw ID bypass attempt
			"user_id":        tokenClientUser,
			"service_id":     svcID,
			"payment_method": "cod",
			"location": map[string]any{
				"latitude":  30.0,
				"longitude": 31.0,
			},
		}
		bodySpoofRaw, _ := json.Marshal(reqBodySpoofRaw)
		reqSpoofRaw := httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(bodySpoofRaw))
		reqSpoofRaw.Header.Set("X-Real-IP", "192.168.99.2")
		recSpoofRaw := httptest.NewRecorder()

		u.TrackJob(recSpoofRaw, reqSpoofRaw)

		if recSpoofRaw.Code != http.StatusUnauthorized {
			t.Errorf("Expected 401 Unauthorized for raw owner_id bypass attempt, got %d. Body: %s", recSpoofRaw.Code, recSpoofRaw.Body.String())
		}

		// (c) Customer books with a mismatched owner token -> rejected
		tokenOtherOwner, _ := jwtutil.GenerateToken("other-owner", "owner", "other-owner", "other@example.com")
		reqBodySpoofToken := map[string]any{
			"owner_id":       tokenOtherOwner, // valid token but for a different owner!
			"user_id":        tokenClientUser,
			"service_id":     svcID,
			"payment_method": "cod",
			"location": map[string]any{
				"latitude":  30.0,
				"longitude": 31.0,
			},
		}
		bodySpoofToken, _ := json.Marshal(reqBodySpoofToken)
		reqSpoofToken := httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(bodySpoofToken))
		reqSpoofToken.Header.Set("X-Real-IP", "192.168.99.3")
		recSpoofToken := httptest.NewRecorder()

		u.TrackJob(recSpoofToken, reqSpoofToken)

		if recSpoofToken.Code != http.StatusForbidden {
			t.Errorf("Expected 403 Forbidden for mismatched owner token spoofing, got %d. Body: %s", recSpoofToken.Code, recSpoofToken.Body.String())
		}
	})

	// Test: TrackJob Pricing/Escrow Client-Controlled-Distance
	t.Run("TrackJob Pricing Client-Controlled-Distance", func(t *testing.T) {
		u.appEnv = "test"
		defer func() { u.appEnv = "" }()
		ctx := context.Background()

		// 1. Create a service
		svcCoords := &models.Service{
			ID:               "svc-pricing-coords-1",
			TenantID:         "kyc-approved-owner-pricing",
			Name:             "Pricing Coords Svc",
			Category:         "transport",
			TenantBasePrice:  25.0,
			TenantPricePerKM: 5.0,
			Latitude:         30.0,
			Longitude:        30.0,
		}
		s.CreateService(ctx, svcCoords)

		// 2. Setup subscription and deposit enough funds in owner wallet
		_ = s.UpsertSubscription(ctx, &models.Subscription{
			ID:        "sub-pricing-owner",
			TenantID:  "kyc-approved-owner-pricing",
			Tier:      models.PlanPaid,
			StartedAt: time.Now(),
		})
		_ = s.Deposit(ctx, "kyc-approved-owner-pricing", 100.0)

		tokenApprovedOwnerPricing, _ := jwtutil.GenerateToken("kyc-approved-owner-pricing", "owner", "kyc-approved-owner-pricing", "pricing@example.com")

		// 3. Request coordinates identical or very close to service coordinates
		reqBody := map[string]any{
			"owner_id":       tokenApprovedOwnerPricing,
			"user_id":        tokenClientUser,
			"service_id":     "svc-pricing-coords-1",
			"payment_method": "wallet",
			"location": map[string]float64{
				"latitude":  30.0, // Identical to service coords
				"longitude": 30.0,
			},
		}
		body, _ := json.Marshal(reqBody)
		req := httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(body))
		req.Header.Set("X-Real-IP", "192.168.100.1")
		rec := httptest.NewRecorder()

		u.TrackJob(rec, req)

		if rec.Code != http.StatusCreated {
			t.Fatalf("Expected 201 Created for TrackJob, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		var resp map[string]any
		json.Unmarshal(rec.Body.Bytes(), &resp)
		escrowAmount, ok := resp["escrow_locked"].(float64)
		if !ok {
			t.Fatalf("Response does not contain escrow_locked as float64: %v", resp)
		}

		// Assert that escrowAmount is exactly TenantBasePrice (25.0), confirming the client-controlled distance risk
		if escrowAmount != 25.0 {
			t.Errorf("Expected escrow_locked to be 25.0 (base price), got %.2f", escrowAmount)
		}
	})

	// Test: UpdateJobLocation speed check cumulative evasion
	t.Run("UpdateJobLocation Speed Check Cumulative Evasion", func(t *testing.T) {
		u.appEnv = "test"
		defer func() { u.appEnv = "" }()
		ctx := context.Background()

		// 1. Setup subscription and active job
		_ = s.UpsertSubscription(ctx, &models.Subscription{
			ID:        "sub-speed-check-owner",
			TenantID:  "kyc-approved-owner-speed",
			Tier:      models.PlanPaid,
			StartedAt: time.Now(),
		})
		activeJob := &models.Job{
			ID:            "job-speed-check-cumulative",
			OwnerID:       "kyc-approved-owner-speed",
			EmployeeID:    "employee-123-speed",
			UserID:        "client-user-123",
			Status:        models.JobStatusActive,
			PaymentMethod: "cod",
			Location:      models.Location{Latitude: 30.0, Longitude: 30.0},
		}
		_ = s.CreateJob(ctx, activeJob)

		tokenEmployeeSpeed, _ := jwtutil.GenerateToken("employee-123-speed", "employee", "kyc-approved-owner-speed", "emp@example.com")

		// 2. Perform 3 consecutive updates spaced by MinLocationUpdateInterval (3 seconds) + a small delta
		// Each step travels 120 meters (approx 0.001 deg lat), yielding ~139 km/h per step (under the 150 km/h limit).
		// Cumulatively they cover 360 meters in 9.3 seconds, which is ~139 km/h.
		steps := []struct {
			lat float64
			lon float64
		}{
			{30.001, 30.0},
			{30.002, 30.0},
			{30.003, 30.0},
		}

		u.locationThrottleMu.Lock()
		delete(u.locationInFlight, activeJob.ID)
		delete(u.locationLastUpdate, activeJob.ID)
		u.locationThrottleMu.Unlock()

		for i, step := range steps {
			reqBody := map[string]any{
				"job_id":       activeJob.ID,
				"requester_id": tokenEmployeeSpeed,
				"latitude":     step.lat,
				"longitude":    step.lon,
			}
			body, _ := json.Marshal(reqBody)
			req := httptest.NewRequest("POST", "/users/jobs/location/update", bytes.NewReader(body))
			req.Header.Set("X-Real-IP", fmt.Sprintf("192.168.100.%d", 10+i))
			rec := httptest.NewRecorder()

			// Manually mock locationLastUpdate to simulate the exact passage of 3.1 seconds
			if i > 0 {
				u.locationThrottleMu.Lock()
				u.locationLastUpdate[activeJob.ID] = time.Now().Add(-3100 * time.Millisecond)
				u.locationThrottleMu.Unlock()
			}

			u.UpdateJobLocation(rec, req)

			if rec.Code != http.StatusOK {
				t.Errorf("Step %d: Expected 200 OK, got %d. Body: %s", i+1, rec.Code, rec.Body.String())
			}
		}

		// Verify the final location was successfully updated in DB, confirming the per-step speed check did not reject this evasion
		jobFromDB := s.GetJob(ctx, activeJob.ID)
		if jobFromDB.CurrentLocation == nil || jobFromDB.CurrentLocation.Latitude != 30.003 {
			t.Errorf("Expected current location to be (30.003, 30.0), got %+v", jobFromDB.CurrentLocation)
		}
	})

	// Test: UpdateJobLocation Throttling State Sharing check
	t.Run("UpdateJobLocation Throttling State Sharing check", func(t *testing.T) {
		u.appEnv = "test"
		defer func() { u.appEnv = "" }()
		ctx := context.Background()

		// 1. Create a second UserService instance (replicating a separate server instance)
		u2 := NewUserService(s, cfg, rdb)
		u2.appEnv = "test"

		// 2. Setup subscription and job
		_ = s.UpsertSubscription(ctx, &models.Subscription{
			ID:        "sub-throttle-owner",
			TenantID:  "kyc-approved-owner-throttle",
			Tier:      models.PlanPaid,
			StartedAt: time.Now(),
		})
		activeJob := &models.Job{
			ID:            "job-throttle-sharing",
			OwnerID:       "kyc-approved-owner-throttle",
			EmployeeID:    "employee-123-throttle",
			UserID:        "client-user-123",
			Status:        models.JobStatusActive,
			PaymentMethod: "cod",
			Location:      models.Location{Latitude: 30.0, Longitude: 30.0},
		}
		_ = s.CreateJob(ctx, activeJob)
		tokenEmployeeThrottle, _ := jwtutil.GenerateToken("employee-123-throttle", "employee", "kyc-approved-owner-throttle", "emp@example.com")

		// 3. Make an update on u1 -> succeeds
		reqBody := map[string]any{
			"job_id":       activeJob.ID,
			"requester_id": tokenEmployeeThrottle,
			"latitude":     30.0001,
			"longitude":    30.0,
		}
		body, _ := json.Marshal(reqBody)
		req1 := httptest.NewRequest("POST", "/users/jobs/location/update", bytes.NewReader(body))
		req1.Header.Set("X-Real-IP", "192.168.100.20")
		rec1 := httptest.NewRecorder()
		u.UpdateJobLocation(rec1, req1)

		if rec1.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK on u1, got %d. Body: %s", rec1.Code, rec1.Body.String())
		}

		// 4. Immediately make next update on u1 -> throttled (429)
		req2 := httptest.NewRequest("POST", "/users/jobs/location/update", bytes.NewReader(body))
		req2.Header.Set("X-Real-IP", "192.168.100.21")
		rec2 := httptest.NewRecorder()
		u.UpdateJobLocation(rec2, req2)
		if rec2.Code != http.StatusTooManyRequests {
			t.Errorf("Expected 429 Too Many Requests on u1 retry, got %d", rec2.Code)
		}

		// 5. Immediately make next update on u2 -> succeeds (200 OK), confirming state is not shared between instances
		req3 := httptest.NewRequest("POST", "/users/jobs/location/update", bytes.NewReader(body))
		req3.Header.Set("X-Real-IP", "192.168.100.22")
		rec3 := httptest.NewRecorder()
		u2.UpdateJobLocation(rec3, req3)
		if rec3.Code != http.StatusOK {
			t.Errorf("Expected 200 OK on u2 instance, got %d. Body: %s", rec3.Code, rec3.Body.String())
		}
	})

	// Test: CompleteJob original coordinates usage validation
	t.Run("CompleteJob Location Recalculation original coordinates check", func(t *testing.T) {
		u.appEnv = "test"
		defer func() { u.appEnv = "" }()
		ctx := context.Background()

		// 1. Create service
		testSvc := &models.Service{
			ID:               "svc-complete-coords-1",
			TenantID:         "kyc-approved-owner-complete",
			Name:             "Complete Coords Svc",
			Category:         "transport",
			TenantBasePrice:  10.0,
			TenantPricePerKM: 10.0,
			Latitude:         30.0,
			Longitude:        30.0,
		}
		s.CreateService(ctx, testSvc)

		// 2. Setup subscription and deposit enough funds in owner wallet
		_ = s.UpsertSubscription(ctx, &models.Subscription{
			ID:        "sub-complete-coords-owner",
			TenantID:  "kyc-approved-owner-complete",
			Tier:      models.PlanPaid,
			StartedAt: time.Now(),
		})

		tokenEmployeeComplete, _ := jwtutil.GenerateToken("employee-123-complete", "employee", "kyc-approved-owner-complete", "emp@example.com")

		// Case A: COD Payment Path
		t.Run("COD Path", func(t *testing.T) {
			_ = s.Deposit(ctx, "kyc-approved-owner-complete", 200.0)

			job := &models.Job{
				ID:            "job-complete-coords-cod",
				OwnerID:       "kyc-approved-owner-complete",
				EmployeeID:    "employee-123-complete",
				UserID:        "client-user-123",
				ServiceID:     "svc-complete-coords-1",
				Status:        models.JobStatusActive,
				PaymentMethod: "cod",
				Location:      models.Location{Latitude: 30.0, Longitude: 30.0}, // Original: dist = 0, price = 10.0
			}
			_ = s.CreateJob(ctx, job)

			// Live location update to somewhere far away (dist = 111 km, which would increase cost significantly)
			_ = s.UpdateJobLocation(ctx, job.ID, 31.0, 30.0)

			reqBody := map[string]any{
				"job_id":         job.ID,
				"requester_id":   tokenEmployeeComplete,
				"cash_collected": true,
			}
			body, _ := json.Marshal(reqBody)
			req := httptest.NewRequest("POST", "/users/jobs/complete", bytes.NewReader(body))
			req.Header.Set("X-Real-IP", "192.168.100.30")
			rec := httptest.NewRecorder()

			u.CompleteJob(rec, req)

			if rec.Code != http.StatusOK {
				t.Fatalf("Expected 200 OK, got %d. Body: %s", rec.Code, rec.Body.String())
			}

			var resp map[string]any
			json.Unmarshal(rec.Body.Bytes(), &resp)
			totalAmt, _ := resp["total_amount"].(float64)

			// Assert amount is exactly base price of 10.0, not recalculated using 31.0, 30.0
			if totalAmt != 10.0 {
				t.Errorf("Expected COD total_amount to be 10.0, got %.2f", totalAmt)
			}
		})

		// Case B: Escrow Payment Path
		t.Run("Escrow Path", func(t *testing.T) {
			_ = s.Deposit(ctx, "kyc-approved-owner-complete", 200.0)

			job := &models.Job{
				ID:                 "job-complete-coords-escrow",
				OwnerID:            "kyc-approved-owner-complete",
				EmployeeID:         "employee-123-complete",
				UserID:             "client-user-123",
				ServiceID:          "svc-complete-coords-1",
				Status:             models.JobStatusActive,
				PaymentMethod:      "wallet",
				LockedEscrowAmount: 100.0,
				Location:           models.Location{Latitude: 30.0, Longitude: 30.0}, // Original: dist = 0, price = 10.0
			}
			_ = s.CreateJob(ctx, job)
			_ = s.LockEscrow(ctx, "kyc-approved-owner-complete", job.ID, 100.0)

			// Live location update to somewhere far away
			_ = s.UpdateJobLocation(ctx, job.ID, 31.0, 30.0)

			reqBody := map[string]any{
				"job_id":       job.ID,
				"requester_id": tokenEmployeeComplete,
			}
			body, _ := json.Marshal(reqBody)
			req := httptest.NewRequest("POST", "/users/jobs/complete", bytes.NewReader(body))
			req.Header.Set("X-Real-IP", "192.168.100.31")
			rec := httptest.NewRecorder()

			u.CompleteJob(rec, req)

			if rec.Code != http.StatusOK {
				t.Fatalf("Expected 200 OK, got %d. Body: %s", rec.Code, rec.Body.String())
			}

			var resp map[string]any
			json.Unmarshal(rec.Body.Bytes(), &resp)
			totalAmt, _ := resp["total_amount"].(float64)

			// Assert amount is exactly base price of 10.0, not recalculated using 31.0, 30.0
			if totalAmt != 10.0 {
				t.Errorf("Expected Escrow total_amount to be 10.0, got %.2f", totalAmt)
			}
		})
	})

	// Test: CancelJob and CompleteJob Unauthorized Parties rejections
	t.Run("CancelJob and CompleteJob Unauthorized Parties", func(t *testing.T) {
		u.appEnv = "test"
		defer func() { u.appEnv = "" }()
		ctx := context.Background()

		// Setup tokens
		tokenEmployeeUnauth, _ := jwtutil.GenerateToken("employee-123-unauth", "employee", "kyc-approved-owner-unauth", "emp@example.com")
		tokenCustomerUnauth, _ := jwtutil.GenerateToken("client-user-123-unauth", "user", "client-user-123-unauth", "client@example.com")
		tokenOtherUserUnauth, _ := jwtutil.GenerateToken("other-user-456-unauth", "user", "other-user-456-unauth", "other@example.com")

		// Create active job
		job := &models.Job{
			ID:            "job-unauth-parties",
			OwnerID:       "kyc-approved-owner-unauth",
			EmployeeID:    "employee-123-unauth",
			UserID:        "client-user-123-unauth",
			ServiceID:     "svc-complete-coords-1",
			Status:        models.JobStatusActive,
			PaymentMethod: "cod",
			Location:      models.Location{Latitude: 30.0, Longitude: 30.0},
		}
		_ = s.CreateJob(ctx, job)

		// Subtest A: Employee of the job attempts to cancel the job -> rejected with 403 Forbidden
		t.Run("EmployeeAttemptsCancel", func(t *testing.T) {
			reqBody := map[string]any{
				"job_id":       job.ID,
				"requester_id": tokenEmployeeUnauth,
				"reason":       "Employee tries to cancel",
			}
			body, _ := json.Marshal(reqBody)
			req := httptest.NewRequest("POST", "/users/jobs/cancel", bytes.NewReader(body))
			req.Header.Set("X-Real-IP", "192.168.100.40")
			rec := httptest.NewRecorder()

			u.CancelJob(rec, req)

			if rec.Code != http.StatusForbidden {
				t.Errorf("Expected 403 Forbidden, got %d. Body: %s", rec.Code, rec.Body.String())
			}
		})

		// Subtest B: Customer (user) of the job attempts to complete the job -> rejected with 403 Forbidden
		t.Run("CustomerAttemptsComplete", func(t *testing.T) {
			reqBody := map[string]any{
				"job_id":         job.ID,
				"requester_id":   tokenCustomerUnauth,
				"cash_collected": true,
			}
			body, _ := json.Marshal(reqBody)
			req := httptest.NewRequest("POST", "/users/jobs/complete", bytes.NewReader(body))
			req.Header.Set("X-Real-IP", "192.168.100.41")
			rec := httptest.NewRecorder()

			u.CompleteJob(rec, req)

			if rec.Code != http.StatusForbidden {
				t.Errorf("Expected 403 Forbidden, got %d. Body: %s", rec.Code, rec.Body.String())
			}
		})

		// Subtest C: Third party attempts to cancel the job -> rejected with 403 Forbidden
		t.Run("ThirdPartyAttemptsCancel", func(t *testing.T) {
			reqBody := map[string]any{
				"job_id":       job.ID,
				"requester_id": tokenOtherUserUnauth,
				"reason":       "Third party tries to cancel",
			}
			body, _ := json.Marshal(reqBody)
			req := httptest.NewRequest("POST", "/users/jobs/cancel", bytes.NewReader(body))
			req.Header.Set("X-Real-IP", "192.168.100.42")
			rec := httptest.NewRecorder()

			u.CancelJob(rec, req)

			if rec.Code != http.StatusForbidden {
				t.Errorf("Expected 403 Forbidden, got %d. Body: %s", rec.Code, rec.Body.String())
			}
		})

		// Subtest D: Third party attempts to complete the job -> rejected with 403 Forbidden
		t.Run("ThirdPartyAttemptsComplete", func(t *testing.T) {
			reqBody := map[string]any{
				"job_id":         job.ID,
				"requester_id":   tokenOtherUserUnauth,
				"cash_collected": true,
			}
			body, _ := json.Marshal(reqBody)
			req := httptest.NewRequest("POST", "/users/jobs/complete", bytes.NewReader(body))
			req.Header.Set("X-Real-IP", "192.168.100.43")
			rec := httptest.NewRecorder()

			u.CompleteJob(rec, req)

			if rec.Code != http.StatusForbidden {
				t.Errorf("Expected 403 Forbidden, got %d. Body: %s", rec.Code, rec.Body.String())
			}
		})
	})

	// Test: GetJob / GetWallet / GetLedger tenant boundary verification
	t.Run("GetJob GetWallet GetLedger Tenant Boundaries", func(t *testing.T) {
		ctx := context.Background()

		// Setup Tenant A and Tenant B
		tokenTenantB, _ := jwtutil.GenerateToken("tenant-b-owner", "owner", "tenant-b", "ownerB@example.com")

		// Create Wallet for Tenant A
		_ = s.Deposit(ctx, "tenant-a-owner", 50.0)
		// Create Ledger for Tenant A
		_ = s.LockEscrow(ctx, "tenant-a-owner", "job-tenant-a", 10.0)

		// 1. GetJob access check
		jobA := &models.Job{
			ID:            "job-tenant-a",
			OwnerID:       "tenant-a-owner",
			UserID:        "customer-a",
			Status:        models.JobStatusActive,
			PaymentMethod: "cod",
			Location:      models.Location{Latitude: 30.0, Longitude: 30.0},
		}
		_ = s.CreateJob(ctx, jobA)

		t.Run("GetJob Tenant Mismatch", func(t *testing.T) {
			req := httptest.NewRequest("GET", "/users/jobs/get?id=job-tenant-a&requester_id="+tokenTenantB, nil)
			req.Header.Set("X-Real-IP", "192.168.100.50")
			rec := httptest.NewRecorder()
			u.GetJob(rec, req)

			if rec.Code != http.StatusForbidden {
				t.Errorf("Expected 403 Forbidden, got %d. Body: %s", rec.Code, rec.Body.String())
			}
		})

		// 2. GetWallet access check
		t.Run("GetWallet Tenant Isolation", func(t *testing.T) {
			// Query with Tenant B's token
			req := httptest.NewRequest("GET", "/users/wallet?tenant_id="+tokenTenantB, nil)
			req.Header.Set("X-Real-IP", "192.168.100.51")
			rec := httptest.NewRecorder()
			u.GetWallet(rec, req)

			if rec.Code != http.StatusOK {
				t.Fatalf("Expected 200 OK, got %d. Body: %s", rec.Code, rec.Body.String())
			}

			// Confirm it returns Tenant B's wallet (balance 0), NOT Tenant A's wallet (balance 50)
			var wallet models.Wallet
			json.Unmarshal(rec.Body.Bytes(), &wallet)
			if wallet.TenantID != "tenant-b-owner" {
				t.Errorf("Expected resolved wallet TenantID to be 'tenant-b-owner', got %s", wallet.TenantID)
			}
			if wallet.TotalBalance != 0.0 {
				t.Errorf("Expected Tenant B's balance to be 0.0, got %.2f", wallet.TotalBalance)
			}
		})

		// 3. GetLedger access check
		t.Run("GetLedger Tenant Isolation", func(t *testing.T) {
			// Query with Tenant B's token
			req := httptest.NewRequest("GET", "/users/ledger?tenant_id="+tokenTenantB, nil)
			req.Header.Set("X-Real-IP", "192.168.100.52")
			rec := httptest.NewRecorder()
			u.GetLedger(rec, req)

			if rec.Code != http.StatusOK {
				t.Fatalf("Expected 200 OK, got %d. Body: %s", rec.Code, rec.Body.String())
			}

			// Confirm it returns Tenant B's ledger (0 entries), NOT Tenant A's ledger
			var resp map[string]any
			json.Unmarshal(rec.Body.Bytes(), &resp)
			count, _ := resp["count"].(float64)
			if count != 0 {
				t.Errorf("Expected Tenant B's ledger count to be 0, got %.0f", count)
			}
		})

		// 4. Token parameter aliases check
		t.Run("Token Parameter Aliases Compatibility", func(t *testing.T) {
			tokenOwner, _ := jwtutil.GenerateToken("kyc-approved-owner-alias", "owner", "kyc-approved-owner-alias", "ownerAlias@example.com")
			tokenCustomer, _ := jwtutil.GenerateToken("customer-alias", "user", "", "customerAlias@example.com")
			tokenEmployee, _ := jwtutil.GenerateToken("employee-under-kyc-approved-owner-alias", "employee", "kyc-approved-owner-alias", "employeeAlias@example.com")

			// A. CreateService using owner_token
			reqBody := map[string]any{
				"owner_token":         tokenOwner,
				"name":                "Alias Test Service",
				"category":            "delivery",
				"tenant_base_price":   5.0,
				"tenant_price_per_km": 1.0,
				"latitude":            30.0,
				"longitude":           31.0,
			}
			body, _ := json.Marshal(reqBody)
			req := httptest.NewRequest("POST", "/users/services", bytes.NewReader(body))
			req.Header.Set("X-Real-IP", "192.168.200.1")
			rec := httptest.NewRecorder()
			u.CreateService(rec, req)
			if rec.Code != http.StatusCreated {
				t.Fatalf("CreateService: Expected 201 Created with owner_token, got %d. Body: %s", rec.Code, rec.Body.String())
			}

			var svcResp map[string]any
			json.Unmarshal(rec.Body.Bytes(), &svcResp)
			svcData := svcResp["service"].(map[string]any)
			serviceID := svcData["id"].(string)

			// B. TrackJob using owner_token, user_token, and employee_token
			reqBodyJob := map[string]any{
				"service_id":     serviceID,
				"owner_token":    tokenOwner,
				"user_token":     tokenCustomer,
				"employee_token": tokenEmployee,
				"payment_method": "cod",
				"location": map[string]any{
					"latitude":  30.0,
					"longitude": 31.0,
				},
			}
			bodyJob, _ := json.Marshal(reqBodyJob)
			req = httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(bodyJob))
			req.Header.Set("X-Real-IP", "192.168.200.2")
			rec = httptest.NewRecorder()
			u.TrackJob(rec, req)
			if rec.Code != http.StatusCreated {
				t.Fatalf("TrackJob: Expected 201 Created with owner_token/user_token, got %d. Body: %s", rec.Code, rec.Body.String())
			}

			var jobResp map[string]any
			json.Unmarshal(rec.Body.Bytes(), &jobResp)
			jobData := jobResp["job"].(map[string]any)
			jobID := jobData["id"].(string)

			// C. GetJob using requester_token
			req = httptest.NewRequest("GET", "/users/jobs/get?id="+jobID+"&requester_token="+tokenOwner, nil)
			req.Header.Set("X-Real-IP", "192.168.200.3")
			rec = httptest.NewRecorder()
			u.GetJob(rec, req)
			if rec.Code != http.StatusOK {
				t.Errorf("GetJob: Expected 200 OK with requester_token, got %d. Body: %s", rec.Code, rec.Body.String())
			}

			// D. GetWallet using tenant_token
			req = httptest.NewRequest("GET", "/users/wallet?tenant_token="+tokenOwner, nil)
			req.Header.Set("X-Real-IP", "192.168.200.4")
			rec = httptest.NewRecorder()
			u.GetWallet(rec, req)
			if rec.Code != http.StatusOK {
				t.Errorf("GetWallet: Expected 200 OK with tenant_token, got %d. Body: %s", rec.Code, rec.Body.String())
			}

			// E. GetLedger using tenant_token
			req = httptest.NewRequest("GET", "/users/ledger?tenant_token="+tokenOwner, nil)
			req.Header.Set("X-Real-IP", "192.168.200.5")
			rec = httptest.NewRecorder()
			u.GetLedger(rec, req)
			if rec.Code != http.StatusOK {
				t.Errorf("GetLedger: Expected 200 OK with tenant_token, got %d. Body: %s", rec.Code, rec.Body.String())
			}

			// F. WalletDeposit using tenant_token (with AppEnv override)
			oldEnv := u.appEnv
			u.appEnv = "local"
			defer func() { u.appEnv = oldEnv }()

			reqBodyDeposit := map[string]any{
				"tenant_token": tokenOwner,
				"amount":       20.0,
			}
			bodyDep, _ := json.Marshal(reqBodyDeposit)
			req = httptest.NewRequest("POST", "/users/wallet/deposit", bytes.NewReader(bodyDep))
			req.Header.Set("X-Real-IP", "192.168.200.6")
			rec = httptest.NewRecorder()
			u.WalletDeposit(rec, req)
			if rec.Code != http.StatusOK {
				t.Errorf("WalletDeposit: Expected 200 OK with tenant_token, got %d. Body: %s", rec.Code, rec.Body.String())
			}

			// G. UpdateJobLocation using requester_token
			s.UpsertSubscription(context.Background(), &models.Subscription{
				ID:        "sub-alias-kyc-approved-owner-alias",
				TenantID:  "kyc-approved-owner-alias",
				Tier:      models.PlanPaid,
				StartedAt: time.Now().UTC(),
			})

			reqBodyLoc := map[string]any{
				"job_id":          jobID,
				"requester_token": tokenEmployee,
				"latitude":        30.0,
				"longitude":       31.0,
			}
			bodyLoc, _ := json.Marshal(reqBodyLoc)
			req = httptest.NewRequest("POST", "/users/jobs/location/update", bytes.NewReader(bodyLoc))
			req.Header.Set("X-Real-IP", "192.168.200.7")
			rec = httptest.NewRecorder()
			u.UpdateJobLocation(rec, req)
			if rec.Code != http.StatusOK {
				t.Errorf("UpdateJobLocation: Expected 200 OK with requester_token, got %d. Body: %s", rec.Code, rec.Body.String())
			}

			// H. CompleteJob using requester_token
			reqBodyComp := map[string]any{
				"job_id":          jobID,
				"requester_token": tokenOwner,
				"cash_collected":  true,
			}
			bodyComp, _ := json.Marshal(reqBodyComp)
			req = httptest.NewRequest("POST", "/users/jobs/complete", bytes.NewReader(bodyComp))
			req.Header.Set("X-Real-IP", "192.168.200.8")
			rec = httptest.NewRecorder()
			u.CompleteJob(rec, req)
			if rec.Code != http.StatusOK {
				t.Errorf("CompleteJob: Expected 200 OK with requester_token, got %d. Body: %s", rec.Code, rec.Body.String())
			}

			// I. RateJob using rated_by_token & rated_user_token
			reqBodyRate := map[string]any{
				"job_id":           jobID,
				"rated_by_token":   tokenOwner,
				"rated_user_token": tokenEmployee,
				"stars":            4,
				"comment":          "Good job!",
			}
			bodyRate, _ := json.Marshal(reqBodyRate)
			req = httptest.NewRequest("POST", "/users/jobs/rate", bytes.NewReader(bodyRate))
			req.Header.Set("X-Real-IP", "192.168.200.9")
			rec = httptest.NewRecorder()
			u.RateJob(rec, req)
			if rec.Code != http.StatusCreated {
				t.Errorf("RateJob: Expected 201 Created with rated_by_token/rated_user_token, got %d. Body: %s", rec.Code, rec.Body.String())
			}

			// J. GetRatings using user_token
			req = httptest.NewRequest("GET", "/users/ratings?user_token="+tokenEmployee, nil)
			req.Header.Set("X-Real-IP", "192.168.200.10")
			rec = httptest.NewRecorder()
			u.GetRatings(rec, req)
			if rec.Code != http.StatusOK {
				t.Errorf("GetRatings: Expected 200 OK with user_token, got %d. Body: %s", rec.Code, rec.Body.String())
			}

			// K. IDOR Regression Tests: GetOwnerJobs, GetCustomerJobs, GetJob
			// (a) Legitimate caller with no extra param -> 200 OK
			req = httptest.NewRequest("GET", "/users/jobs/owner", nil)
			req.Header.Set("Authorization", "Bearer "+tokenApprovedOwner)
			rec = httptest.NewRecorder()
			u.GetOwnerJobs(rec, req)
			if rec.Code != http.StatusOK {
				t.Errorf("GetOwnerJobs (no param): expected 200 OK, got %d. Body: %s", rec.Code, rec.Body.String())
			}

			// (b) Legitimate owner passing owner_token / owner_id back -> 200 OK (no false positive IDOR)
			req = httptest.NewRequest("GET", "/users/jobs/owner?owner_token="+tokenApprovedOwner, nil)
			rec = httptest.NewRecorder()
			u.GetOwnerJobs(rec, req)
			if rec.Code != http.StatusOK {
				t.Errorf("GetOwnerJobs (owner_token): expected 200 OK, got %d. Body: %s", rec.Code, rec.Body.String())
			}

			req = httptest.NewRequest("GET", "/users/jobs/owner?owner_id=kyc-approved-owner", nil)
			req.Header.Set("Authorization", "Bearer "+tokenApprovedOwner)
			rec = httptest.NewRecorder()
			u.GetOwnerJobs(rec, req)
			if rec.Code != http.StatusOK {
				t.Errorf("GetOwnerJobs (own owner_id): expected 200 OK, got %d. Body: %s", rec.Code, rec.Body.String())
			}

			// (c) Owner passing different owner_id -> 403 Forbidden (genuine IDOR)
			req = httptest.NewRequest("GET", "/users/jobs/owner?owner_id=different-owner", nil)
			req.Header.Set("Authorization", "Bearer "+tokenApprovedOwner)
			rec = httptest.NewRecorder()
			u.GetOwnerJobs(rec, req)
			if rec.Code != http.StatusForbidden {
				t.Errorf("GetOwnerJobs (mismatched owner_id): expected 403 Forbidden, got %d. Body: %s", rec.Code, rec.Body.String())
			}

			// Customer Jobs Regression:
			req = httptest.NewRequest("GET", "/users/jobs/mine", nil)
			req.Header.Set("Authorization", "Bearer "+tokenClientUser)
			rec = httptest.NewRecorder()
			u.GetCustomerJobs(rec, req)
			if rec.Code != http.StatusOK {
				t.Errorf("GetCustomerJobs (no param): expected 200 OK, got %d. Body: %s", rec.Code, rec.Body.String())
			}

			req = httptest.NewRequest("GET", "/users/jobs/mine?customer_token="+tokenClientUser, nil)
			rec = httptest.NewRecorder()
			u.GetCustomerJobs(rec, req)
			if rec.Code != http.StatusOK {
				t.Errorf("GetCustomerJobs (customer_token): expected 200 OK, got %d. Body: %s", rec.Code, rec.Body.String())
			}

			req = httptest.NewRequest("GET", "/users/jobs/mine?user_id=client-user-123", nil)
			req.Header.Set("Authorization", "Bearer "+tokenClientUser)
			rec = httptest.NewRecorder()
			u.GetCustomerJobs(rec, req)
			if rec.Code != http.StatusOK {
				t.Errorf("GetCustomerJobs (own user_id): expected 200 OK, got %d. Body: %s", rec.Code, rec.Body.String())
			}

			req = httptest.NewRequest("GET", "/users/jobs/mine?user_id=different-user", nil)
			req.Header.Set("Authorization", "Bearer "+tokenClientUser)
			rec = httptest.NewRecorder()
			u.GetCustomerJobs(rec, req)
			if rec.Code != http.StatusForbidden {
				t.Errorf("GetCustomerJobs (mismatched user_id): expected 403 Forbidden, got %d. Body: %s", rec.Code, rec.Body.String())
			}
		})
	})
}

func TestGetJobsByOwner(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	dbName := fmt.Sprintf("saas_platform_test_owner_jobs_%d", time.Now().UnixNano())
	s, err := store.NewMongoDB(ctx, mongoURI, dbName)
	if err != nil {
		t.Skipf("Skipping TestGetJobsByOwner integration test: MongoDB not available (%v)", err)
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

	cfg := &config.Config{
		InternalServiceToken: "mock-internal-token",
	}
	u := NewUserService(s, cfg, rdb)

	ownerID1 := "owner-tenant-100"
	ownerID2 := "owner-tenant-200"

	job1 := &models.Job{
		ID:         "job-owner-101",
		OwnerID:    ownerID1,
		EmployeeID: "emp-100",
		UserID:     "cust-100",
		ServiceID:  "svc-100",
		Status:     models.JobStatusPending,
		CreatedAt:  time.Now(),
		UpdatedAt:  time.Now(),
	}
	job2 := &models.Job{
		ID:         "job-owner-201",
		OwnerID:    ownerID2,
		EmployeeID: "emp-200",
		UserID:     "cust-200",
		ServiceID:  "svc-200",
		Status:     models.JobStatusActive,
		CreatedAt:  time.Now(),
		UpdatedAt:  time.Now(),
	}
	if err := s.CreateJob(ctx, job1); err != nil {
		t.Fatalf("failed to create job1: %v", err)
	}
	if err := s.CreateJob(ctx, job2); err != nil {
		t.Fatalf("failed to create job2: %v", err)
	}

	tokenOwner1, _ := jwtutil.GenerateToken(ownerID1, "owner", ownerID1, "owner1@example.com")
	tokenOwner2, _ := jwtutil.GenerateToken(ownerID2, "owner", ownerID2, "owner2@example.com")
	tokenNonOwner, _ := jwtutil.GenerateToken("employee-999", "employee", "employee-999", "emp@example.com")

	// 1. Tenant Isolation: Owner 1 receives only Job 1
	t.Run("Tenant Isolation", func(t *testing.T) {
		req := httptest.NewRequest("GET", "/users/jobs/owner", nil)
		req.Header.Set("Authorization", "Bearer "+tokenOwner1)
		rec := httptest.NewRecorder()
		u.GetOwnerJobs(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK, got %d. Body: %s", rec.Code, rec.Body.String())
		}
		var jobs []models.OwnerJobResponse
		if err := json.Unmarshal(rec.Body.Bytes(), &jobs); err != nil {
			t.Fatalf("Failed to parse response: %v", err)
		}
		if len(jobs) != 1 {
			t.Fatalf("Expected 1 job for owner1, got %d", len(jobs))
		}
		if jobs[0].ID != "job-owner-101" {
			t.Errorf("Expected job ID job-owner-101, got %s", jobs[0].ID)
		}

		// Verify Owner 2 receives only Job 2
		req2 := httptest.NewRequest("GET", "/users/jobs/owner", nil)
		req2.Header.Set("Authorization", "Bearer "+tokenOwner2)
		rec2 := httptest.NewRecorder()
		u.GetOwnerJobs(rec2, req2)
		if rec2.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK for owner2, got %d. Body: %s", rec2.Code, rec2.Body.String())
		}
		var jobs2 []models.OwnerJobResponse
		if err := json.Unmarshal(rec2.Body.Bytes(), &jobs2); err != nil {
			t.Fatalf("Failed to parse owner2 response: %v", err)
		}
		if len(jobs2) != 1 || jobs2[0].ID != "job-owner-201" {
			t.Errorf("Expected 1 job (job-owner-201) for owner2, got %v", jobs2)
		}
	})

	// 2. IDOR Verification: own owner_id matches, mismatched owner_id returns 403
	t.Run("IDOR Verification", func(t *testing.T) {
		reqMatch := httptest.NewRequest("GET", "/users/jobs/owner?owner_id="+ownerID1, nil)
		reqMatch.Header.Set("Authorization", "Bearer "+tokenOwner1)
		recMatch := httptest.NewRecorder()
		u.GetOwnerJobs(recMatch, reqMatch)
		if recMatch.Code != http.StatusOK {
			t.Errorf("Expected 200 OK for matching owner_id, got %d. Body: %s", recMatch.Code, recMatch.Body.String())
		}

		reqMismatch := httptest.NewRequest("GET", "/users/jobs/owner?owner_id="+ownerID2, nil)
		reqMismatch.Header.Set("Authorization", "Bearer "+tokenOwner1)
		recMismatch := httptest.NewRecorder()
		u.GetOwnerJobs(recMismatch, reqMismatch)
		if recMismatch.Code != http.StatusForbidden {
			t.Errorf("Expected 403 Forbidden for mismatched owner_id, got %d. Body: %s", recMismatch.Code, recMismatch.Body.String())
		}
	})

	// 3. Role Enforcement: non-owner or empty role returns 403
	t.Run("Role Enforcement", func(t *testing.T) {
		req := httptest.NewRequest("GET", "/users/jobs/owner", nil)
		req.Header.Set("Authorization", "Bearer "+tokenNonOwner)
		rec := httptest.NewRecorder()
		u.GetOwnerJobs(rec, req)

		if rec.Code != http.StatusForbidden {
			t.Errorf("Expected 403 Forbidden for employee role, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		// Empty-role token test
		tokenEmptyRole, _ := jwtutil.GenerateToken(ownerID1, "", ownerID1, "empty@example.com")
		reqEmpty := httptest.NewRequest("GET", "/users/jobs/owner", nil)
		reqEmpty.Header.Set("Authorization", "Bearer "+tokenEmptyRole)
		recEmpty := httptest.NewRecorder()
		u.GetOwnerJobs(recEmpty, reqEmpty)

		if recEmpty.Code != http.StatusForbidden {
			t.Errorf("Expected 403 Forbidden for empty role token, got %d. Body: %s", recEmpty.Code, recEmpty.Body.String())
		}
	})

	// 4. Rate Limiting: 31st request receives 429
	t.Run("Rate Limiting", func(t *testing.T) {
		rateLimitOwnerID := "owner-ratelimit-300"
		tokenRateLimit, _ := jwtutil.GenerateToken(rateLimitOwnerID, "owner", rateLimitOwnerID, "rate@example.com")

		for i := 0; i < 5; i++ {
			req := httptest.NewRequest("GET", "/users/jobs/owner", nil)
			req.Header.Set("Authorization", "Bearer "+tokenRateLimit)
			rec := httptest.NewRecorder()
			u.GetOwnerJobs(rec, req)
			if rec.Code != http.StatusOK {
				t.Fatalf("Request %d failed unexpectedly with status %d: %s", i+1, rec.Code, rec.Body.String())
			}
		}

		// 6th request must trigger 429
		reqLimit := httptest.NewRequest("GET", "/users/jobs/owner", nil)
		reqLimit.Header.Set("Authorization", "Bearer "+tokenRateLimit)
		recLimit := httptest.NewRecorder()
		u.GetOwnerJobs(recLimit, reqLimit)

		if recLimit.Code != http.StatusTooManyRequests {
			t.Fatalf("Expected 429 Too Many Requests on 6th call, got %d. Body: %s", recLimit.Code, recLimit.Body.String())
		}
		if !strings.Contains(recLimit.Body.String(), "too many requests") {
			t.Errorf("Expected rate limit error message in body, got %s", recLimit.Body.String())
		}
	})
}

func TestGetJobsByCustomer(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	dbName := fmt.Sprintf("saas_platform_test_customer_jobs_%d", time.Now().UnixNano())
	s, err := store.NewMongoDB(ctx, mongoURI, dbName)
	if err != nil {
		t.Skipf("Skipping TestGetJobsByCustomer integration test: MongoDB not available (%v)", err)
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

	cfg := &config.Config{
		InternalServiceToken: "mock-internal-token",
	}
	u := NewUserService(s, cfg, rdb)

	custID1 := "cust-user-100"
	custID2 := "cust-user-200"

	job1 := &models.Job{
		ID:         "job-cust-101",
		OwnerID:    "owner-100",
		EmployeeID: "emp-100",
		UserID:     custID1,
		ServiceID:  "svc-100",
		Status:     models.JobStatusPending,
		CreatedAt:  time.Now(),
		UpdatedAt:  time.Now(),
	}
	job2 := &models.Job{
		ID:         "job-cust-201",
		OwnerID:    "owner-200",
		EmployeeID: "emp-200",
		UserID:     custID2,
		ServiceID:  "svc-200",
		Status:     models.JobStatusActive,
		CreatedAt:  time.Now(),
		UpdatedAt:  time.Now(),
	}
	if err := s.CreateJob(ctx, job1); err != nil {
		t.Fatalf("failed to create job1: %v", err)
	}
	if err := s.CreateJob(ctx, job2); err != nil {
		t.Fatalf("failed to create job2: %v", err)
	}

	tokenCust1, _ := jwtutil.GenerateToken(custID1, "user", custID1, "cust1@example.com")
	tokenCust2, _ := jwtutil.GenerateToken(custID2, "user", custID2, "cust2@example.com")

	// 1. Tenant Isolation: Customer 1 receives only Customer 1's jobs
	t.Run("Tenant Isolation", func(t *testing.T) {
		req := httptest.NewRequest("GET", "/users/jobs/mine", nil)
		req.Header.Set("Authorization", "Bearer "+tokenCust1)
		rec := httptest.NewRecorder()
		u.GetCustomerJobs(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK, got %d. Body: %s", rec.Code, rec.Body.String())
		}
		var jobs []models.CustomerJobResponse
		if err := json.Unmarshal(rec.Body.Bytes(), &jobs); err != nil {
			t.Fatalf("Failed to parse response: %v", err)
		}
		if len(jobs) != 1 {
			t.Fatalf("Expected 1 job for customer 1, got %d", len(jobs))
		}
		if jobs[0].ID != "job-cust-101" {
			t.Errorf("Expected job ID job-cust-101, got %s", jobs[0].ID)
		}

		// Verify Customer 2 receives only Job 2
		req2 := httptest.NewRequest("GET", "/users/jobs/mine", nil)
		req2.Header.Set("Authorization", "Bearer "+tokenCust2)
		rec2 := httptest.NewRecorder()
		u.GetCustomerJobs(rec2, req2)
		if rec2.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK for customer2, got %d. Body: %s", rec2.Code, rec2.Body.String())
		}
		var jobs2 []models.CustomerJobResponse
		if err := json.Unmarshal(rec2.Body.Bytes(), &jobs2); err != nil {
			t.Fatalf("Failed to parse customer2 response: %v", err)
		}
		if len(jobs2) != 1 || jobs2[0].ID != "job-cust-201" {
			t.Errorf("Expected 1 job (job-cust-201) for customer2, got %v", jobs2)
		}
	})

	// 2. IDOR Verification: matching user_id succeeds, mismatch fails with 403
	t.Run("IDOR Verification", func(t *testing.T) {
		reqMatch := httptest.NewRequest("GET", "/users/jobs/mine?user_id="+custID1, nil)
		reqMatch.Header.Set("Authorization", "Bearer "+tokenCust1)
		recMatch := httptest.NewRecorder()
		u.GetCustomerJobs(recMatch, reqMatch)
		if recMatch.Code != http.StatusOK {
			t.Errorf("Expected 200 OK for matching user_id, got %d. Body: %s", recMatch.Code, recMatch.Body.String())
		}

		reqMismatch := httptest.NewRequest("GET", "/users/jobs/mine?user_id="+custID2, nil)
		reqMismatch.Header.Set("Authorization", "Bearer "+tokenCust1)
		recMismatch := httptest.NewRecorder()
		u.GetCustomerJobs(recMismatch, reqMismatch)
		if recMismatch.Code != http.StatusForbidden {
			t.Errorf("Expected 403 Forbidden for mismatched user_id, got %d. Body: %s", recMismatch.Code, recMismatch.Body.String())
		}
	})

	// 3. Role Enforcement: non-user or empty role returns 403
	t.Run("Role Enforcement", func(t *testing.T) {
		tokenOwnerRole, _ := jwtutil.GenerateToken(custID1, "owner", custID1, "owner@example.com")
		reqOwner := httptest.NewRequest("GET", "/users/jobs/mine", nil)
		reqOwner.Header.Set("Authorization", "Bearer "+tokenOwnerRole)
		recOwner := httptest.NewRecorder()
		u.GetCustomerJobs(recOwner, reqOwner)

		if recOwner.Code != http.StatusForbidden {
			t.Errorf("Expected 403 Forbidden for owner role on customer jobs, got %d. Body: %s", recOwner.Code, recOwner.Body.String())
		}

		// Empty-role token test
		tokenEmptyRole, _ := jwtutil.GenerateToken(custID1, "", custID1, "emptycust@example.com")
		reqEmpty := httptest.NewRequest("GET", "/users/jobs/mine", nil)
		reqEmpty.Header.Set("Authorization", "Bearer "+tokenEmptyRole)
		recEmpty := httptest.NewRecorder()
		u.GetCustomerJobs(recEmpty, reqEmpty)

		if recEmpty.Code != http.StatusForbidden {
			t.Errorf("Expected 403 Forbidden for empty role token on customer jobs, got %d. Body: %s", recEmpty.Code, recEmpty.Body.String())
		}
	})
	t.Run("Rate Limiting", func(t *testing.T) {
		rateLimitCustID := "cust-ratelimit-300"
		tokenRateLimit, _ := jwtutil.GenerateToken(rateLimitCustID, "user", rateLimitCustID, "custrate@example.com")

		for i := 0; i < 5; i++ {
			req := httptest.NewRequest("GET", "/users/jobs/mine", nil)
			req.Header.Set("Authorization", "Bearer "+tokenRateLimit)
			rec := httptest.NewRecorder()
			u.GetCustomerJobs(rec, req)
			if rec.Code != http.StatusOK {
				t.Fatalf("Request %d failed unexpectedly with status %d: %s", i+1, rec.Code, rec.Body.String())
			}
		}

		// 6th request must trigger 429
		reqLimit := httptest.NewRequest("GET", "/users/jobs/mine", nil)
		reqLimit.Header.Set("Authorization", "Bearer "+tokenRateLimit)
		recLimit := httptest.NewRecorder()
		u.GetCustomerJobs(recLimit, reqLimit)

		if recLimit.Code != http.StatusTooManyRequests {
			t.Fatalf("Expected 429 Too Many Requests on 6th call, got %d. Body: %s", recLimit.Code, recLimit.Body.String())
		}
		if !strings.Contains(recLimit.Body.String(), "too many requests") {
			t.Errorf("Expected rate limit error message in body, got %s", recLimit.Body.String())
		}
	})
}

type contextMock struct {
	context.Context
}

func (c *contextMock) Done() <-chan struct{} {
	var pcs [10]uintptr
	n := runtime.Callers(2, pcs[:])
	frames := runtime.CallersFrames(pcs[:n])
	for {
		frame, more := frames.Next()
		if strings.Contains(frame.Function, "UpdateJobLockedEscrow") {
			ch := make(chan struct{})
			close(ch)
			return ch
		}
		if !more {
			break
		}
	}
	return c.Context.Done()
}

func (c *contextMock) Err() error {
	var pcs [10]uintptr
	n := runtime.Callers(2, pcs[:])
	frames := runtime.CallersFrames(pcs[:n])
	for {
		frame, more := frames.Next()
		if strings.Contains(frame.Function, "UpdateJobLockedEscrow") {
			return context.Canceled
		}
		if !more {
			break
		}
	}
	return c.Context.Err()
}

func TestTrackJob_EscrowRollbackFailure_ReconciliationRequired(t *testing.T) {
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
		json.NewEncoder(w).Encode(map[string]any{
			"id":         id,
			"role":       "owner",
			"kyc_status": "approved",
			"is_active":  true,
			"tenant_id":  id,
		})
	}))
	defer mockAuthServer.Close()

	cfg := &config.Config{
		AuthServiceURL:         mockAuthServer.URL,
		InternalServiceToken:   "mock-internal-token",
		AppEnv:                 "test",
		AllowTestPaymentBypass: true,
	}

	u := NewUserService(s, cfg, rdb)

	ownerID := "rec-owner-1"
	userID := "rec-user-1"
	serviceID := "svc-rec-1"

	mockSvc := &models.Service{
		ID:               serviceID,
		TenantID:         ownerID,
		Name:             "Reconciliation Service",
		Category:         "delivery",
		TenantBasePrice:  50.0,
		TenantPricePerKM: 2.0,
		Latitude:         30.0,
		Longitude:        30.0,
	}
	s.CreateService(ctx, mockSvc)

	if err := s.Deposit(ctx, ownerID, 500.0); err != nil {
		t.Fatalf("Failed to deposit funds: %v", err)
	}

	// Stub RollbackEscrow to fail
	u.rollbackEscrowHook = func(ctx context.Context, tenantID string, amount float64) error {
		return fmt.Errorf("simulated rollback error")
	}
	defer func() { u.rollbackEscrowHook = nil }()

	// Stub UpdateJobLockedEscrow to fail using contextMock
	mockCtx := &contextMock{Context: context.Background()}

	tokenOwner, _ := jwtutil.GenerateToken(ownerID, "owner", ownerID, "owner@example.com")
	tokenUser, _ := jwtutil.GenerateToken(userID, "user", ownerID, "user@example.com")

	trackReqBody := map[string]any{
		"owner_id":       tokenOwner,
		"service_id":     serviceID,
		"user_id":        tokenUser,
		"payment_method": "wallet",
		"location": models.Location{
			Latitude:  30.0,
			Longitude: 30.0,
		},
	}
	trackBody, _ := json.Marshal(trackReqBody)
	req := httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(trackBody))
	req = req.WithContext(mockCtx)
	rec := httptest.NewRecorder()

	u.TrackJob(rec, req)

	// Assert (c): Appropriate error response returned to client
	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("Expected status 500, got %d. Body: %s", rec.Code, rec.Body.String())
	}
	var resp map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("Failed to parse response body: %v", err)
	}
	if !strings.Contains(resp["error"], "reconciliation") {
		t.Errorf("Expected error message to mention reconciliation, got: %s", resp["error"])
	}

	// Fetch job from store
	jobs, err := s.GetJobsByOwner(context.Background(), ownerID)
	if err != nil {
		t.Fatalf("Failed to get jobs by owner: %v", err)
	}

	// Assert (a): Job is NOT deleted
	if len(jobs) != 1 {
		t.Fatalf("Expected 1 job preserved in DB, got %d", len(jobs))
	}

	stuckJob := jobs[0]
	if stuckJob == nil {
		t.Fatal("Expected non-nil job record in DB")
	}

	// Assert (b): Job's status and fields reflect reconciliation-needed state
	if stuckJob.Status != models.JobStatusEscrowReconciliationRequired {
		t.Errorf("Expected job status %q, got %q", models.JobStatusEscrowReconciliationRequired, stuckJob.Status)
	}
	if stuckJob.ReconciliationNote == "" {
		t.Error("Expected non-empty ReconciliationNote")
	}
	if stuckJob.EscrowFailureReason == "" {
		t.Error("Expected non-empty EscrowFailureReason")
	}
}

func TestTrackJob_IdempotencyKey(t *testing.T) {
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
		json.NewEncoder(w).Encode(map[string]any{
			"id":         id,
			"role":       "owner",
			"kyc_status": "approved",
			"is_active":  true,
			"tenant_id":  id,
		})
	}))
	defer mockAuthServer.Close()

	cfg := &config.Config{
		AuthServiceURL:         mockAuthServer.URL,
		InternalServiceToken:   "mock-internal-token",
		AppEnv:                 "test",
		AllowTestPaymentBypass: true,
	}

	u := NewUserService(s, cfg, rdb)

	ownerID := "idem-owner-1"
	userID := "idem-user-1"
	serviceID := "svc-idem-1"

	mockSvc := &models.Service{
		ID:               serviceID,
		TenantID:         ownerID,
		Name:             "Idempotency Service",
		Category:         "delivery",
		TenantBasePrice:  50.0,
		TenantPricePerKM: 2.0,
		Latitude:         30.0,
		Longitude:        30.0,
	}
	s.CreateService(ctx, mockSvc)

	if err := s.Deposit(ctx, ownerID, 500.0); err != nil {
		t.Fatalf("Failed to deposit funds: %v", err)
	}

	tokenOwner, _ := jwtutil.GenerateToken(ownerID, "owner", ownerID, "owner@example.com")
	tokenUser, _ := jwtutil.GenerateToken(userID, "user", ownerID, "user@example.com")

	idempotencyKey := "req-key-abc-123"

	trackReqBody := map[string]any{
		"owner_id":        tokenOwner,
		"service_id":      serviceID,
		"user_id":         tokenUser,
		"payment_method":  "wallet",
		"idempotency_key": idempotencyKey,
		"location": models.Location{
			Latitude:  30.0,
			Longitude: 30.0,
		},
	}
	trackBody, _ := json.Marshal(trackReqBody)

	// First request: should create job (201 Created)
	req1 := httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(trackBody))
	req1.Header.Set("Idempotency-Key", idempotencyKey)
	rec1 := httptest.NewRecorder()

	u.TrackJob(rec1, req1)

	if rec1.Code != http.StatusCreated {
		t.Fatalf("Expected status 201 Created on first request, got %d. Body: %s", rec1.Code, rec1.Body.String())
	}

	var resp1 map[string]any
	json.Unmarshal(rec1.Body.Bytes(), &resp1)
	jobObj1, _ := resp1["job"].(map[string]any)
	jobID1, _ := jobObj1["id"].(string)

	if jobID1 == "" {
		t.Fatal("Expected job ID in response 1")
	}

	// Second request with SAME idempotency key: should return existing job (200 OK)
	req2 := httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(trackBody))
	req2.Header.Set("Idempotency-Key", idempotencyKey)
	rec2 := httptest.NewRecorder()

	u.TrackJob(rec2, req2)

	if rec2.Code != http.StatusOK {
		t.Fatalf("Expected status 200 OK on duplicate request, got %d. Body: %s", rec2.Code, rec2.Body.String())
	}

	var resp2 map[string]any
	json.Unmarshal(rec2.Body.Bytes(), &resp2)
	jobObj2, _ := resp2["job"].(map[string]any)
	jobID2, _ := jobObj2["id"].(string)

	if jobID2 != jobID1 {
		t.Fatalf("Expected duplicate request to return original job ID %q, got %q", jobID1, jobID2)
	}

	// Assert exactly 1 job exists for owner
	jobs, err := s.GetJobsByOwner(ctx, ownerID)
	if err != nil {
		t.Fatalf("Failed to query jobs by owner: %v", err)
	}
	if len(jobs) != 1 {
		t.Fatalf("Expected exactly 1 job in DB, got %d", len(jobs))
	}
}

func TestRateJobAndGetRatings_RateLimiting(t *testing.T) {
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

	cfg := &config.Config{AppEnv: "test", AllowTestPaymentBypass: true}
	u := NewUserService(s, cfg, rdb)

	tok, _ := jwtutil.GenerateToken("usr-1", "user", "owner-1", "u@example.com")

	// Rate limit is 5 requests per minute per IP
	for i := 0; i < 5; i++ {
		req := httptest.NewRequest("GET", "/users/ratings?user_id=usr-1", nil)
		req.Header.Set("Authorization", "Bearer "+tok)
		req.RemoteAddr = "192.168.1.100:12345"
		rec := httptest.NewRecorder()
		u.GetRatings(rec, req)
	}

	// 6th request should be rate-limited (429 Too Many Requests)
	req6 := httptest.NewRequest("GET", "/users/ratings?user_id=usr-1", nil)
	req6.Header.Set("Authorization", "Bearer "+tok)
	req6.RemoteAddr = "192.168.1.100:12345"
	rec6 := httptest.NewRecorder()
	u.GetRatings(rec6, req6)

	if rec6.Code != http.StatusTooManyRequests {
		t.Fatalf("Expected status 429 Too Many Requests for GetRatings rate limit, got %d. Body: %s", rec6.Code, rec6.Body.String())
	}

	// RateJob test for rate limiting
	for i := 0; i < 5; i++ {
		req := httptest.NewRequest("POST", "/users/jobs/rate", strings.NewReader(`{"job_id":"job-1","stars":5}`))
		req.RemoteAddr = "192.168.1.200:12345"
		rec := httptest.NewRecorder()
		u.RateJob(rec, req)
	}

	reqRateLimited := httptest.NewRequest("POST", "/users/jobs/rate", strings.NewReader(`{"job_id":"job-1","stars":5}`))
	reqRateLimited.RemoteAddr = "192.168.1.200:12345"
	recRateLimited := httptest.NewRecorder()
	u.RateJob(recRateLimited, reqRateLimited)

	if recRateLimited.Code != http.StatusTooManyRequests {
		t.Fatalf("Expected status 429 Too Many Requests for RateJob rate limit, got %d. Body: %s", recRateLimited.Code, recRateLimited.Body.String())
	}
}

func TestResolveTokenWithRole(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")

	ownerToken, _ := jwtutil.GenerateToken("user-owner-1", "owner", "owner-1", "owner@example.com")
	employeeToken, _ := jwtutil.GenerateToken("user-emp-1", "employee", "owner-1", "emp@example.com")

	// Matching role should succeed
	id, err := resolveTokenWithRole(ownerToken, "owner")
	if err != nil || id != "user-owner-1" {
		t.Fatalf("Expected success resolving owner token, got id %q, err %v", id, err)
	}

	// Multiple allowed roles including match should succeed
	id, err = resolveTokenWithRole(employeeToken, "owner", "employee")
	if err != nil || id != "user-emp-1" {
		t.Fatalf("Expected success resolving employee token with allowed roles, got id %q, err %v", id, err)
	}

	// Mismatching role should fail
	_, err = resolveTokenWithRole(employeeToken, "owner")
	if err == nil || !strings.Contains(err.Error(), "role mismatch") {
		t.Fatalf("Expected role mismatch error when passing employee token for owner role, got err: %v", err)
	}
}

func TestGetLedger_RateLimiting(t *testing.T) {
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

	cfg := &config.Config{AppEnv: "test"}
	u := NewUserService(s, cfg, rdb)

	ownerToken, _ := jwtutil.GenerateToken("ledger-owner-1", "owner", "ledger-owner-1", "owner@example.com")

	// Rate limit is 5 requests per minute per IP
	for i := 0; i < 5; i++ {
		req := httptest.NewRequest("GET", "/users/ledger?tenant_token="+ownerToken, nil)
		req.RemoteAddr = "192.168.2.100:12345"
		rec := httptest.NewRecorder()
		u.GetLedger(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK on request %d, got %d. Body: %s", i+1, rec.Code, rec.Body.String())
		}
	}

	// 6th request from same IP should be rate-limited (429 Too Many Requests)
	req6 := httptest.NewRequest("GET", "/users/ledger?tenant_token="+ownerToken, nil)
	req6.RemoteAddr = "192.168.2.100:12345"
	rec6 := httptest.NewRecorder()
	u.GetLedger(rec6, req6)

	if rec6.Code != http.StatusTooManyRequests {
		t.Fatalf("Expected status 429 Too Many Requests for GetLedger rate limit, got %d. Body: %s", rec6.Code, rec6.Body.String())
	}
}

func TestTestPaymentBypass_Gating(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")

	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	// Config with AllowTestPaymentBypass: false
	cfgDisabled := &config.Config{
		AppEnv:                 "test",
		AllowTestPaymentBypass: false,
	}
	uDisabled := NewUserService(nil, cfgDisabled, rdb)

	// WalletDeposit without AllowTestPaymentBypass MUST be rejected (400 Bad Request)
	reqDeposit := httptest.NewRequest("POST", "/users/wallet/deposit", strings.NewReader(`{"tenant_id":"t1","amount":100}`))
	recDeposit := httptest.NewRecorder()
	uDisabled.WalletDeposit(recDeposit, reqDeposit)

	if recDeposit.Code != http.StatusBadRequest {
		t.Fatalf("Expected 400 Bad Request for WalletDeposit when AllowTestPaymentBypass is false, got %d", recDeposit.Code)
	}

	userToken, _ := jwtutil.GenerateToken("u1", "user", "u1", "user@example.com")
	ownerToken, _ := jwtutil.GenerateToken("o1", "owner", "o1", "owner@example.com")

	// TrackJob non-COD without AllowTestPaymentBypass MUST be rejected (400 Bad Request)
	trackBody := strings.NewReader(fmt.Sprintf(`{"owner_id":%q,"service_id":"s1","user_id":%q,"payment_method":"wallet","location":{"latitude":30.0,"longitude":30.0}}`, ownerToken, userToken))
	reqTrack := httptest.NewRequest("POST", "/users/jobs/track", trackBody)
	recTrack := httptest.NewRecorder()
	uDisabled.TrackJob(recTrack, reqTrack)

	if recTrack.Code != http.StatusBadRequest {
		t.Fatalf("Expected 400 Bad Request for non-COD TrackJob when AllowTestPaymentBypass is false, got %d. Body: %s", recTrack.Code, recTrack.Body.String())
	}
}
