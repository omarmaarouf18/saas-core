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
	"github.com/project/shared/infra/jwtutil"
	"github.com/project/user-service/internal/config"
	"github.com/project/user-service/internal/models"
	"github.com/project/user-service/internal/store"
	"github.com/redis/go-redis/v9"
)

// TestRespondPrice_ConcurrencyRace_DoubleEscrowPrevention verifies that concurrent accept calls
// on the same job_id result in exactly one successful escrow lock and one job_state_changed rejection.
func TestRespondPrice_ConcurrencyRace_DoubleEscrowPrevention(t *testing.T) {
	jwtSecret := "NrrYbDqT4bRD/ADvJ5U2VKmLqXr8nk21IRVAbrzVI1mqEhuMhII3IO26PPa4qJtR"
	os.Setenv("JWT_SECRET", jwtSecret)
	jwtutil.Init(jwtSecret)

	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	dbName := fmt.Sprintf("saas_platform_race_test_%d", time.Now().UnixNano())
	s, err := store.NewMongoDB(ctx, mongoURI, dbName)
	if err != nil {
		t.Skipf("Skipping race condition test: MongoDB not available at %s (%v)", mongoURI, err)
		return
	}
	defer func() {
		_ = s.DropDatabase(context.Background())
		s.Close(context.Background())
	}()

	ownerID := "owner-race-1"
	empID := "emp-race-1"
	custID := "cust-race-1"
	svcID := "svc-transport-race-1"

	mockAuthServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		id := r.URL.Query().Get("id")

		if id == ownerID {
			json.NewEncoder(w).Encode(map[string]any{
				"id":         id,
				"role":       "owner",
				"kyc_status": "approved",
				"is_active":  true,
				"tenant_id":  id,
			})
			return
		}
		if id == empID {
			json.NewEncoder(w).Encode(map[string]any{
				"id":        id,
				"role":      "employee",
				"owner_id":  ownerID,
				"tenant_id": ownerID,
				"is_active": true,
			})
			return
		}
		if id == custID {
			json.NewEncoder(w).Encode(map[string]any{
				"id":        id,
				"role":      "customer",
				"tenant_id": ownerID,
				"is_active": true,
			})
			return
		}
		w.WriteHeader(http.StatusNotFound)
	}))
	defer mockAuthServer.Close()

	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	cfg := &config.Config{
		AuthServiceURL: mockAuthServer.URL,
	}

	u := NewUserService(s, cfg, rdb)

	// 1. Create Transport Service
	svc := &models.Service{
		ID:               svcID,
		TenantID:         ownerID,
		Name:             "Express Ride",
		Category:         "transport",
		BasePrice:        50.0,
		TenantBasePrice:  50.0,
		TenantPricePerKM: 10.0,
	}
	s.CreateService(ctx, svc)

	// 2. Fund Owner Wallet (500.0 — enough for multiple locks if not protected)
	if err := s.Deposit(ctx, ownerID, 500.0); err != nil {
		t.Fatalf("Failed to fund wallet: %v", err)
	}

	// 3. Create Negotiable Transport Job awaiting price response
	jobID := "job-race-escrow-1"
	job := &models.Job{
		ID:             jobID,
		OwnerID:        ownerID,
		EmployeeID:     empID,
		UserID:         custID,
		ServiceID:      svcID,
		Status:         models.JobStatusAwaitingPriceResponse,
		PaymentMethod:  "card",
		SuggestedPrice: 100.0,
		CreatedAt:      time.Now().UTC(),
		UpdatedAt:      time.Now().UTC(),
	}
	if err := s.CreateJob(ctx, job); err != nil {
		t.Fatalf("Failed to create job: %v", err)
	}

	empToken, _ := jwtutil.GenerateToken(empID, "employee", ownerID, "emp@example.com")

	// 4. Concurrent execution barrier
	var wg sync.WaitGroup
	start := make(chan struct{})
	type result struct {
		code int
		body string
	}
	results := make([]result, 2)

	for i := 0; i < 2; i++ {
		wg.Add(1)
		idx := i
		go func() {
			defer wg.Done()
			<-start

			reqBody := fmt.Sprintf(`{"job_id":%q,"decision":"accept"}`, jobID)
			req := httptest.NewRequest("POST", "/users/jobs/respond-price", bytes.NewBufferString(reqBody))
			req.Header.Set("Authorization", "Bearer "+empToken)
			rec := httptest.NewRecorder()

			u.RespondPrice(rec, req)

			results[idx] = result{
				code: rec.Code,
				body: rec.Body.String(),
			}
		}()
	}

	// Release both goroutines simultaneously
	close(start)
	wg.Wait()

	// 5. Assert concurrency guarantees
	successCount := 0
	conflictCount := 0

	for i, res := range results {
		t.Logf("Goroutine %d: code=%d body=%s", i+1, res.code, res.body)
		if res.code == http.StatusOK {
			successCount++
		} else if res.code == http.StatusConflict && (bytes.Contains([]byte(res.body), []byte("job_state_changed"))) {
			conflictCount++
		}
	}

	if successCount != 1 || conflictCount != 1 {
		t.Fatalf("Expected exactly 1 success (200 OK) and 1 conflict (409 job_state_changed). Got: success=%d, conflict=%d", successCount, conflictCount)
	}

	// 6. Inspect underlying wallet state: EscrowBalance must be exactly 100.0 (locked ONCE, not 200.0)
	wallet := s.GetWallet(ctx, ownerID)
	if wallet == nil {
		t.Fatalf("Failed to fetch owner wallet")
	}

	expectedEscrow := 100.0
	if wallet.EscrowBalance != expectedEscrow {
		t.Errorf("Escrow balance mismatch after race condition test. Expected %.2f (single lock), got %.2f", expectedEscrow, wallet.EscrowBalance)
	}

	expectedBalance := 400.0 // 500 - 100
	if wallet.WithdrawableBalance != expectedBalance {
		t.Errorf("Wallet withdrawable balance mismatch. Expected %.2f, got %.2f", expectedBalance, wallet.WithdrawableBalance)
	}

	// 7. Inspect updated job state
	updatedJob := s.GetJob(ctx, jobID)
	if updatedJob.Status != models.JobStatusActive {
		t.Errorf("Expected job status to be active, got %s", updatedJob.Status)
	}
	if updatedJob.LockedEscrowAmount != 100.0 {
		t.Errorf("Expected locked escrow amount on job to be 100.0, got %.2f", updatedJob.LockedEscrowAmount)
	}
}

// TestProposePrice_ConcurrencyRace_OverwrittenProposalPrevention verifies that concurrent proposals
// on the same job_id result in exactly one successful proposal and one job_state_changed rejection.
func TestProposePrice_ConcurrencyRace_OverwrittenProposalPrevention(t *testing.T) {
	jwtSecret := "NrrYbDqT4bRD/ADvJ5U2VKmLqXr8nk21IRVAbrzVI1mqEhuMhII3IO26PPa4qJtR"
	os.Setenv("JWT_SECRET", jwtSecret)
	jwtutil.Init(jwtSecret)

	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	dbName := fmt.Sprintf("saas_platform_race_propose_%d", time.Now().UnixNano())
	s, err := store.NewMongoDB(ctx, mongoURI, dbName)
	if err != nil {
		t.Skipf("Skipping proposal race test: MongoDB not available at %s (%v)", mongoURI, err)
		return
	}
	defer func() {
		_ = s.DropDatabase(context.Background())
		s.Close(context.Background())
	}()

	ownerID := "owner-race-propose"
	empID := "emp-race-propose"
	custID := "cust-race-propose"
	svcID := "svc-transport-race-propose"

	mockAuthServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		id := r.URL.Query().Get("id")

		if id == ownerID {
			json.NewEncoder(w).Encode(map[string]any{"id": id, "role": "owner", "kyc_status": "approved", "is_active": true, "tenant_id": id})
			return
		}
		if id == empID {
			json.NewEncoder(w).Encode(map[string]any{"id": id, "role": "employee", "owner_id": ownerID, "tenant_id": ownerID, "is_active": true})
			return
		}
		if id == custID {
			json.NewEncoder(w).Encode(map[string]any{"id": id, "role": "customer", "tenant_id": ownerID, "is_active": true})
			return
		}
		w.WriteHeader(http.StatusNotFound)
	}))
	defer mockAuthServer.Close()

	mr2, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr2.Close()
	rdb2 := redis.NewClient(&redis.Options{Addr: mr2.Addr()})
	defer rdb2.Close()

	cfg := &config.Config{AuthServiceURL: mockAuthServer.URL}
	u := NewUserService(s, cfg, rdb2)

	svc := &models.Service{ID: svcID, TenantID: ownerID, Name: "Ride", Category: "transport", BasePrice: 50.0}
	s.CreateService(ctx, svc)

	jobID := "job-race-propose-1"
	job := &models.Job{
		ID:             jobID,
		OwnerID:        ownerID,
		EmployeeID:     empID,
		UserID:         custID,
		ServiceID:      svcID,
		Status:         models.JobStatusAwaitingPriceResponse,
		SuggestedPrice: 100.0,
		ProposedPrice:  nil,
		CreatedAt:      time.Now().UTC(),
		UpdatedAt:      time.Now().UTC(),
	}
	_ = s.CreateJob(ctx, job)

	custToken, _ := jwtutil.GenerateToken(custID, "customer", ownerID, "cust@example.com")

	var wg sync.WaitGroup
	start := make(chan struct{})
	type result struct {
		code int
		body string
	}
	results := make([]result, 2)
	prices := []float64{110.0, 120.0}

	for i := 0; i < 2; i++ {
		wg.Add(1)
		idx := i
		p := prices[i]
		go func() {
			defer wg.Done()
			<-start

			reqBody := fmt.Sprintf(`{"job_id":%q,"proposed_price":%.1f}`, jobID, p)
			req := httptest.NewRequest("POST", "/users/jobs/propose-price", bytes.NewBufferString(reqBody))
			req.Header.Set("Authorization", "Bearer "+custToken)
			rec := httptest.NewRecorder()

			u.ProposePrice(rec, req)

			results[idx] = result{code: rec.Code, body: rec.Body.String()}
		}()
	}

	close(start)
	wg.Wait()

	successCount := 0
	rejectedCount := 0

	for i, res := range results {
		t.Logf("Propose Goroutine %d: code=%d body=%s", i+1, res.code, res.body)
		if res.code == http.StatusOK {
			successCount++
		} else if (res.code == http.StatusConflict && bytes.Contains([]byte(res.body), []byte("job_state_changed"))) ||
			(res.code == http.StatusBadRequest && bytes.Contains([]byte(res.body), []byte("proposal_already_submitted"))) {
			rejectedCount++
		}
	}

	if successCount != 1 || rejectedCount != 1 {
		t.Fatalf("Expected exactly 1 success (200 OK) and 1 rejection (400 proposal_already_submitted or 409 job_state_changed). Got: success=%d, rejected=%d", successCount, rejectedCount)
	}

	updatedJob := s.GetJob(ctx, jobID)
	if updatedJob.ProposedPrice == nil {
		t.Fatalf("Expected ProposedPrice to be set on job")
	}
}

// TestRespondPrice_JobStateChanged_RollbackFailure_ReconciliationFallback verifies that when
// UpdateJobAgreedPrice fails with job_state_changed after escrow lock and RollbackEscrow fails twice,
// the job is marked as escrow_reconciliation_required with reconciliation notes, and HTTP 409 is returned.
func TestRespondPrice_JobStateChanged_RollbackFailure_ReconciliationFallback(t *testing.T) {
	jwtSecret := "NrrYbDqT4bRD/ADvJ5U2VKmLqXr8nk21IRVAbrzVI1mqEhuMhII3IO26PPa4qJtR"
	os.Setenv("JWT_SECRET", jwtSecret)
	jwtutil.Init(jwtSecret)

	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	dbName := fmt.Sprintf("saas_platform_rollback_fail_%d", time.Now().UnixNano())
	s, err := store.NewMongoDB(ctx, mongoURI, dbName)
	if err != nil {
		t.Skipf("Skipping rollback failure test: MongoDB not available at %s (%v)", mongoURI, err)
		return
	}
	defer func() {
		_ = s.DropDatabase(context.Background())
		s.Close(context.Background())
	}()

	ownerID := "owner-rollback-fail"
	empID := "emp-rollback-fail"
	custID := "cust-rollback-fail"
	svcID := "svc-rollback-fail"

	mockAuthServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		id := r.URL.Query().Get("id")

		if id == ownerID {
			json.NewEncoder(w).Encode(map[string]any{"id": id, "role": "owner", "kyc_status": "approved", "is_active": true, "tenant_id": id})
			return
		}
		if id == empID {
			json.NewEncoder(w).Encode(map[string]any{"id": id, "role": "employee", "owner_id": ownerID, "tenant_id": ownerID, "is_active": true})
			return
		}
		if id == custID {
			json.NewEncoder(w).Encode(map[string]any{"id": id, "role": "customer", "tenant_id": ownerID, "is_active": true})
			return
		}
		w.WriteHeader(http.StatusNotFound)
	}))
	defer mockAuthServer.Close()

	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	cfg := &config.Config{AuthServiceURL: mockAuthServer.URL}
	u := NewUserService(s, cfg, rdb)

	svc := &models.Service{ID: svcID, TenantID: ownerID, Name: "Ride", Category: "transport", BasePrice: 50.0}
	s.CreateService(ctx, svc)
	_ = s.Deposit(ctx, ownerID, 500.0)

	jobID := "job-rollback-fail-1"
	job := &models.Job{
		ID:             jobID,
		OwnerID:        ownerID,
		EmployeeID:     empID,
		UserID:         custID,
		ServiceID:      svcID,
		Status:         models.JobStatusAwaitingPriceResponse,
		PaymentMethod:  "card",
		SuggestedPrice: 100.0,
		CreatedAt:      time.Now().UTC(),
		UpdatedAt:      time.Now().UTC(),
	}
	_ = s.CreateJob(ctx, job)

	empToken, _ := jwtutil.GenerateToken(empID, "employee", ownerID, "emp@example.com")

	// Hook 1: Right before UpdateJobAgreedPrice write, simulate concurrent status change in DB
	u.updateJobAgreedPriceBeforeWriteHook = func(ctx context.Context) {
		_ = s.UpdateJobCancellation(ctx, jobID, models.JobStatusCancelled, "concurrent_cancel_race")
	}
	defer func() { u.updateJobAgreedPriceBeforeWriteHook = nil }()

	// Hook 2: Force RollbackEscrow to fail twice
	rollbackCallCount := 0
	u.rollbackEscrowHook = func(ctx context.Context, tenantID string, amount float64) error {
		rollbackCallCount++
		return fmt.Errorf("simulated rollback failure on attempt %d", rollbackCallCount)
	}
	defer func() { u.rollbackEscrowHook = nil }()

	reqBody := fmt.Sprintf(`{"job_id":%q,"decision":"accept"}`, jobID)
	req := httptest.NewRequest("POST", "/users/jobs/respond-price", bytes.NewBufferString(reqBody))
	req.Header.Set("Authorization", "Bearer "+empToken)
	rec := httptest.NewRecorder()

	u.RespondPrice(rec, req)

	// 1. Client receives HTTP 409 Conflict with error "job_state_changed"
	if rec.Code != http.StatusConflict {
		t.Fatalf("Expected 409 Conflict, got %d: %s", rec.Code, rec.Body.String())
	}
	if !bytes.Contains(rec.Body.Bytes(), []byte("job_state_changed")) {
		t.Errorf("Expected response body to contain job_state_changed, got %s", rec.Body.String())
	}

	// 2. Rollback was attempted twice (initial + 1 retry)
	if rollbackCallCount != 2 {
		t.Errorf("Expected RollbackEscrow to be called twice, got %d", rollbackCallCount)
	}

	// 3. Database job status updated to escrow_reconciliation_required
	updatedJob := s.GetJob(ctx, jobID)
	if updatedJob.Status != models.JobStatusEscrowReconciliationRequired {
		t.Errorf("Expected job status to be %s, got %s", models.JobStatusEscrowReconciliationRequired, updatedJob.Status)
	}
	if !strings.Contains(updatedJob.ReconciliationNote, "Job state changed concurrently during RespondPrice accept") {
		t.Errorf("Expected ReconciliationNote to describe race + rollback failure, got %q", updatedJob.ReconciliationNote)
	}
	if !strings.Contains(updatedJob.EscrowFailureReason, "simulated rollback failure") {
		t.Errorf("Expected EscrowFailureReason to be set, got %q", updatedJob.EscrowFailureReason)
	}
	if updatedJob.LockedEscrowAmount != 100.0 {
		t.Errorf("Expected LockedEscrowAmount to be 100.0, got %.2f", updatedJob.LockedEscrowAmount)
	}
}
