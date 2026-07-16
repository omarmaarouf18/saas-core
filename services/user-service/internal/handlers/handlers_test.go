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
			AppEnv:               "test",
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
			ID:                 "job-coords-validation",
			OwnerID:            "kyc-approved-owner",
			UserID:             "client-user-123",
			EmployeeID:         "active-employee",
			ServiceID:          "svc-coords-validation",
			Status:             models.JobStatusActive,
			PaymentMethod:      "cod",
			Location:           models.Location{Latitude: 0.0, Longitude: 0.0},
			CreatedAt:          time.Now().Add(-1 * time.Hour),
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
					"latitude":    tc.lat,
					"longitude":   tc.lon,
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
