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

func TestGetReconciliationQueue(t *testing.T) {
	jwtSecret := "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2"
	os.Setenv("JWT_SECRET", jwtSecret)

	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	dbName := fmt.Sprintf("saas_platform_test_recon_queue_%d", time.Now().UnixNano())
	s, err := store.NewMongoDB(ctx, mongoURI, dbName)
	if err != nil {
		t.Skipf("Skipping TestGetReconciliationQueue: MongoDB not available (%v)", err)
		return
	}
	defer func() {
		_ = s.DropDatabase(context.Background())
		s.Close(context.Background())
	}()

	ownerA := "owner-recon-queue-A"
	ownerB := "owner-recon-queue-B"
	custID := "cust-recon-queue"
	empID := "emp-recon-queue"

	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	userCfg := &config.Config{
		InternalServiceToken: "test-internal-token",
	}
	u := NewUserService(s, userCfg, rdb)

	// Seed jobs
	// Job 1 (Owner A, flagged for reconciliation)
	job1 := &models.Job{
		ID:                  "job-recon-1",
		OwnerID:             ownerA,
		UserID:              custID,
		EmployeeID:          empID,
		ServiceID:           "service-1",
		Status:              models.JobStatusEscrowReconciliationRequired,
		ReconciliationNote:  "tracked_distance_mismatch: actual 2.00 km vs booked 10.00 km",
		EscrowFailureReason: "under_distance_mismatch",
		LockedEscrowAmount:  50.0,
		CreatedAt:           time.Now().Add(-1 * time.Hour),
		UpdatedAt:           time.Now(),
	}
	// Job 2 (Owner A, active, not flagged)
	job2 := &models.Job{
		ID:         "job-recon-2",
		OwnerID:    ownerA,
		UserID:     custID,
		EmployeeID: empID,
		ServiceID:  "service-1",
		Status:     models.JobStatusActive,
		CreatedAt:  time.Now(),
		UpdatedAt:  time.Now(),
	}
	// Job 3 (Owner B, flagged for reconciliation)
	job3 := &models.Job{
		ID:                  "job-recon-3",
		OwnerID:             ownerB,
		UserID:              custID,
		EmployeeID:          empID,
		ServiceID:           "service-1",
		Status:              models.JobStatusEscrowReconciliationRequired,
		ReconciliationNote:  "under_distance_mismatch",
		EscrowFailureReason: "under_distance_mismatch",
		LockedEscrowAmount:  30.0,
		CreatedAt:           time.Now(),
		UpdatedAt:           time.Now(),
	}

	_ = s.CreateJob(ctx, job1)
	_ = s.CreateJob(ctx, job2)
	_ = s.CreateJob(ctx, job3)

	ownerAToken, _ := jwtutil.GenerateToken(ownerA, "owner", ownerA, "ownerA@example.com")
	ownerBToken, _ := jwtutil.GenerateToken(ownerB, "owner", ownerB, "ownerB@example.com")
	custToken, _ := jwtutil.GenerateToken(custID, "user", custID, "cust@example.com")

	// 1. Owner A queries reconciliation queue
	t.Run("Owner A Queue Scoping", func(t *testing.T) {
		req := httptest.NewRequest("GET", "/users/jobs/reconciliation-queue", nil)
		req.Header.Set("Authorization", "Bearer "+ownerAToken)
		rec := httptest.NewRecorder()

		u.GetReconciliationQueue(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK, got status %d, body: %s", rec.Code, rec.Body.String())
		}

		var queue []models.OwnerJobResponse
		if err := json.NewDecoder(rec.Body).Decode(&queue); err != nil {
			t.Fatalf("Failed to decode response: %v", err)
		}

		if len(queue) != 1 {
			t.Fatalf("Expected 1 reconciliation job for Owner A, got %d", len(queue))
		}
		if queue[0].ID != "job-recon-1" {
			t.Fatalf("Expected job ID job-recon-1, got %s", queue[0].ID)
		}
		if queue[0].ReconciliationNote == "" {
			t.Fatalf("Expected non-empty ReconciliationNote")
		}
		if queue[0].LockedEscrowAmount != 50.0 {
			t.Fatalf("Expected LockedEscrowAmount 50.0, got %f", queue[0].LockedEscrowAmount)
		}
	})

	// 2. IDOR Protection check: Owner B passing owner_id=ownerA in query
	t.Run("IDOR Rejection", func(t *testing.T) {
		req := httptest.NewRequest("GET", "/users/jobs/reconciliation-queue?owner_id="+ownerA, nil)
		req.Header.Set("Authorization", "Bearer "+ownerBToken)
		rec := httptest.NewRecorder()

		u.GetReconciliationQueue(rec, req)

		if rec.Code != http.StatusForbidden {
			t.Fatalf("Expected 403 Forbidden for IDOR attempt, got %d: %s", rec.Code, rec.Body.String())
		}
	})

	// 3. Non-owner role rejection
	t.Run("Customer Role Rejection", func(t *testing.T) {
		req := httptest.NewRequest("GET", "/users/jobs/reconciliation-queue", nil)
		req.Header.Set("Authorization", "Bearer "+custToken)
		rec := httptest.NewRecorder()

		u.GetReconciliationQueue(rec, req)

		if rec.Code != http.StatusForbidden {
			t.Fatalf("Expected 403 Forbidden for customer role, got %d: %s", rec.Code, rec.Body.String())
		}
	})

	// 4. Rate limiting enforcement (30 req/min limit)
	t.Run("Rate Limiting Enforcement", func(t *testing.T) {
		ownerRateToken, _ := jwtutil.GenerateToken("owner-rate-test", "owner", "owner-rate-test", "rate@example.com")
		var lastStatus int
		for i := 0; i < 35; i++ {
			req := httptest.NewRequest("GET", "/users/jobs/reconciliation-queue", nil)
			req.Header.Set("Authorization", "Bearer "+ownerRateToken)
			rec := httptest.NewRecorder()
			u.GetReconciliationQueue(rec, req)
			lastStatus = rec.Code
		}
		if lastStatus != http.StatusTooManyRequests {
			t.Fatalf("Expected 429 Too Many Requests after 30 requests, got status %d", lastStatus)
		}
	})
}

func TestResolveReconciliation(t *testing.T) {
	jwtSecret := "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2"
	os.Setenv("JWT_SECRET", jwtSecret)

	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	dbName := fmt.Sprintf("saas_platform_test_recon_resolve_%d", time.Now().UnixNano())
	s, err := store.NewMongoDB(ctx, mongoURI, dbName)
	if err != nil {
		t.Skipf("Skipping TestResolveReconciliation: MongoDB not available (%v)", err)
		return
	}
	defer func() {
		_ = s.DropDatabase(context.Background())
		s.Close(context.Background())
	}()

	ownerA := "owner-resolve-A"
	ownerB := "owner-resolve-B"
	custID := "cust-resolve"
	empID := "emp-resolve"

	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	userCfg := &config.Config{
		InternalServiceToken: "test-internal-token",
	}
	u := NewUserService(s, userCfg, rdb)

	// Setup wallet and lock escrow for Customer and Owner A
	// Deposit 100 into Customer wallet, lock 50 for Job 1
	_ = s.Deposit(ctx, ownerA, 100.0)
	_ = s.LockEscrow(ctx, ownerA, "job-resolve-1", 50.0)

	// Job 1: Flagged for reconciliation, 50 locked escrow
	job1 := &models.Job{
		ID:                  "job-resolve-1",
		OwnerID:             ownerA,
		UserID:              custID,
		EmployeeID:          empID,
		ServiceID:           "service-1",
		PaymentMethod:       "escrow",
		Status:              models.JobStatusEscrowReconciliationRequired,
		ReconciliationNote:  "under_distance_mismatch",
		EscrowFailureReason: "under_distance_mismatch",
		LockedEscrowAmount:  50.0,
		CreatedAt:           time.Now().Add(-1 * time.Hour),
		UpdatedAt:           time.Now(),
	}
	_ = s.CreateJob(ctx, job1)

	// Setup Job 2: Customer deposit 100, lock 40 for Job 2
	_ = s.Deposit(ctx, ownerA, 100.0)
	_ = s.LockEscrow(ctx, ownerA, "job-resolve-2", 40.0)

	job2 := &models.Job{
		ID:                  "job-resolve-2",
		OwnerID:             ownerA,
		UserID:              custID,
		EmployeeID:          empID,
		ServiceID:           "service-1",
		PaymentMethod:       "escrow",
		Status:              models.JobStatusEscrowReconciliationRequired,
		ReconciliationNote:  "under_distance_mismatch",
		EscrowFailureReason: "under_distance_mismatch",
		LockedEscrowAmount:  40.0,
		CreatedAt:           time.Now().Add(-1 * time.Hour),
		UpdatedAt:           time.Now(),
	}
	_ = s.CreateJob(ctx, job2)

	ownerAToken, _ := jwtutil.GenerateToken(ownerA, "owner", ownerA, "ownerA@example.com")
	ownerBToken, _ := jwtutil.GenerateToken(ownerB, "owner", ownerB, "ownerB@example.com")

	// 1. Resolve release_to_employee
	t.Run("Resolve Release to Employee", func(t *testing.T) {
		body := map[string]string{
			"job_id":   "job-resolve-1",
			"decision": "release_to_employee",
		}
		b, _ := json.Marshal(body)

		req := httptest.NewRequest("POST", "/users/jobs/reconciliation-resolve", bytes.NewReader(b))
		req.Header.Set("Authorization", "Bearer "+ownerAToken)
		rec := httptest.NewRecorder()

		u.ResolveReconciliation(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK, got status %d: %s", rec.Code, rec.Body.String())
		}

		// Verify job status updated to Completed
		updatedJob := s.GetJob(ctx, "job-resolve-1")
		if updatedJob == nil || updatedJob.Status != models.JobStatusCompleted {
			t.Fatalf("Expected job status Completed, got %v", updatedJob)
		}

		// Verify owner wallet received net funds
		ownerWallet, _ := s.GetOrCreateWallet(ctx, ownerA)
		if ownerWallet.TotalBalance <= 0 {
			t.Fatalf("Expected positive owner wallet balance after release, got %f", ownerWallet.TotalBalance)
		}
	})

	// 2. Idempotency Check: Resolving Job 1 again returns 409 Conflict
	t.Run("Idempotency Re-resolution Rejection", func(t *testing.T) {
		body := map[string]string{
			"job_id":   "job-resolve-1",
			"decision": "release_to_employee",
		}
		b, _ := json.Marshal(body)

		req := httptest.NewRequest("POST", "/users/jobs/reconciliation-resolve", bytes.NewReader(b))
		req.Header.Set("Authorization", "Bearer "+ownerAToken)
		rec := httptest.NewRecorder()

		u.ResolveReconciliation(rec, req)

		if rec.Code != http.StatusConflict {
			t.Fatalf("Expected 409 Conflict on double resolution, got status %d: %s", rec.Code, rec.Body.String())
		}
	})

	// 3. Resolve refund_to_customer
	t.Run("Resolve Refund to Customer", func(t *testing.T) {
		body := map[string]string{
			"job_id":   "job-resolve-2",
			"decision": "refund_to_customer",
		}
		b, _ := json.Marshal(body)

		req := httptest.NewRequest("POST", "/users/jobs/reconciliation-resolve", bytes.NewReader(b))
		req.Header.Set("Authorization", "Bearer "+ownerAToken)
		rec := httptest.NewRecorder()

		u.ResolveReconciliation(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK, got status %d: %s", rec.Code, rec.Body.String())
		}

		// Verify job status updated to Cancelled
		updatedJob := s.GetJob(ctx, "job-resolve-2")
		if updatedJob == nil || updatedJob.Status != models.JobStatusCancelled {
			t.Fatalf("Expected job status Cancelled, got %v", updatedJob)
		}

		// Verify owner withdrawable balance restored
		ownerWallet, _ := s.GetOrCreateWallet(ctx, ownerA)
		if ownerWallet.WithdrawableBalance < 40.0 {
			t.Fatalf("Expected restored owner withdrawable balance >= 40, got %f", ownerWallet.WithdrawableBalance)
		}
	})

	// 4. Wrong owner tenant isolation check
	t.Run("Wrong Owner Rejection", func(t *testing.T) {
		// Create Job 3 for Owner A
		job3 := &models.Job{
			ID:                 "job-resolve-3",
			OwnerID:            ownerA,
			UserID:             custID,
			EmployeeID:         empID,
			ServiceID:          "service-1",
			Status:             models.JobStatusEscrowReconciliationRequired,
			LockedEscrowAmount: 20.0,
			CreatedAt:          time.Now(),
			UpdatedAt:          time.Now(),
		}
		_ = s.CreateJob(ctx, job3)

		body := map[string]string{
			"job_id":   "job-resolve-3",
			"decision": "refund_to_customer",
		}
		b, _ := json.Marshal(body)

		req := httptest.NewRequest("POST", "/users/jobs/reconciliation-resolve", bytes.NewReader(b))
		req.Header.Set("Authorization", "Bearer "+ownerBToken)
		rec := httptest.NewRecorder()

		u.ResolveReconciliation(rec, req)

		if rec.Code != http.StatusForbidden {
			t.Fatalf("Expected 403 Forbidden for wrong owner resolution attempt, got status %d: %s", rec.Code, rec.Body.String())
		}
	})
}
