package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
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

// TestFinding1_CODCancelCompleteRaceCondition verifies that concurrent CompleteJob and CancelJob
// requests on the exact same active COD job cannot both succeed, eliminating the race condition.
func TestFinding1_CODCancelCompleteRaceCondition(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://root:devpassword123@localhost:27017/saas_platform?authSource=admin"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	dbName := fmt.Sprintf("saas_platform_test_finding1_%d", time.Now().UnixNano())
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

	// Mock Auth Server
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
		AllowTestPaymentBypass: true,
		AppEnv:                 "test",
	}
	svcHandler := NewUserService(s, cfg, rdb)

	ownerID := "owner-finding1"
	jobID := "job-cod-race-1"

	// Seed service and active COD job
	testService := &models.Service{
		ID:              "svc-finding1",
		TenantID:        ownerID,
		Name:            "Delivery Test",
		Category:        "delivery",
		TenantBasePrice: 50.0,
		Latitude:        30.0444,
		Longitude:       31.2357,
	}
	s.CreateService(ctx, testService)

	activeJob := &models.Job{
		ID:            jobID,
		OwnerID:       ownerID,
		UserID:        "cust-finding1",
		ServiceID:     "svc-finding1",
		Status:        models.JobStatusActive,
		PaymentMethod: "cod",
		Location:      models.Location{Latitude: 30.0444, Longitude: 31.2357},
		CreatedAt:     time.Now().UTC(),
		UpdatedAt:     time.Now().UTC(),
	}
	if err := s.CreateJob(ctx, activeJob); err != nil {
		t.Fatalf("failed to create active COD job: %v", err)
	}

	ownerToken, err := jwtutil.GenerateToken(ownerID, "owner", ownerID, "owner@finding1.com")
	if err != nil {
		t.Fatalf("failed to generate owner token: %v", err)
	}

	var wg sync.WaitGroup
	wg.Add(2)

	completeStatus := 0
	cancelStatus := 0

	// Goroutine 1: CompleteJob
	go func() {
		defer wg.Done()
		completeReq := models.CompleteJobRequest{
			JobID:         jobID,
			CashCollected: true,
			RequesterID:   ownerToken,
		}
		body, _ := json.Marshal(completeReq)
		req := httptest.NewRequest("POST", "/users/jobs/complete", bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Authorization", "Bearer "+ownerToken)
		w := httptest.NewRecorder()

		svcHandler.CompleteJob(w, req)
		completeStatus = w.Code
	}()

	// Goroutine 2: CancelJob
	go func() {
		defer wg.Done()
		cancelReq := map[string]string{
			"job_id":       jobID,
			"reason":       "customer requested cancellation",
			"requester_id": ownerToken,
		}
		body, _ := json.Marshal(cancelReq)
		req := httptest.NewRequest("POST", "/users/jobs/cancel", bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Authorization", "Bearer "+ownerToken)
		w := httptest.NewRecorder()

		svcHandler.CancelJob(w, req)
		cancelStatus = w.Code
	}()

	wg.Wait()

	// Assert that exactly one request returns HTTP 200 (OK) and the other returns HTTP 409 (Conflict).
	t.Logf("Race result: CompleteJob status=%d, CancelJob status=%d", completeStatus, cancelStatus)

	successCount := 0
	conflictCount := 0

	if completeStatus == http.StatusOK {
		successCount++
	} else if completeStatus == http.StatusConflict {
		conflictCount++
	}

	if cancelStatus == http.StatusOK {
		successCount++
	} else if cancelStatus == http.StatusConflict {
		conflictCount++
	}

	if successCount != 1 {
		t.Errorf("Expected exactly 1 successful request, got %d (complete=%d, cancel=%d)", successCount, completeStatus, cancelStatus)
	}
	if conflictCount != 1 {
		t.Errorf("Expected exactly 1 conflict request, got %d (complete=%d, cancel=%d)", conflictCount, completeStatus, cancelStatus)
	}

	// Verify database state is consistent
	updatedJob := s.GetJob(ctx, jobID)
	if updatedJob == nil {
		t.Fatalf("job %s lost after race execution", jobID)
	}
	t.Logf("Final job status after concurrent race: %s", updatedJob.Status)
	if updatedJob.Status != models.JobStatusCompleted && updatedJob.Status != models.JobStatusCancelled {
		t.Errorf("Expected final job status to be completed or cancelled, got %s", updatedJob.Status)
	}
}

// TestFinding2_CancelJob_NegotiatedTransport_AgreedPriceRefund verifies that CancelJob uses AgreedPrice
// when refunding escrow for transport-category negotiated jobs, leaving 0 stranded locked escrow.
func TestFinding2_CancelJob_NegotiatedTransport_AgreedPriceRefund(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://root:devpassword123@localhost:27017/saas_platform?authSource=admin"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	dbName := fmt.Sprintf("saas_platform_test_finding2_%d", time.Now().UnixNano())
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
		AllowTestPaymentBypass: true,
		AppEnv:                 "test",
	}
	svcHandler := NewUserService(s, cfg, rdb)

	ownerID := "owner-finding2"
	jobID := "job-negotiated-transport-1"
	basePrice := 100.0
	agreedPrice := 150.0

	// Seed service
	testService := &models.Service{
		ID:               "svc-finding2",
		TenantID:         ownerID,
		Name:             "Transport Test",
		Category:         "transport",
		TenantBasePrice:  basePrice,
		TenantPricePerKM: 0.0,
		Latitude:         30.0444,
		Longitude:        31.2357,
	}
	s.CreateService(ctx, testService)

	// Create owner wallet and deposit initial withdrawable balance ($200)
	if _, err := s.GetOrCreateWallet(ctx, ownerID); err != nil {
		t.Fatalf("failed to create wallet: %v", err)
	}
	// Deposit initial funds ($200) into owner wallet
	if err := s.Deposit(ctx, ownerID, 200.0); err != nil {
		t.Fatalf("failed to deposit funds: %v", err)
	}

	// Lock escrow for the agreed price ($150)
	if err := s.LockEscrow(ctx, ownerID, jobID, agreedPrice); err != nil {
		t.Fatalf("failed to lock escrow: %v", err)
	}

	// Create active job with AgreedPrice = 150 and LockedEscrowAmount = 150
	activeJob := &models.Job{
		ID:                 jobID,
		OwnerID:            ownerID,
		UserID:             "cust-finding2",
		ServiceID:          "svc-finding2",
		Status:             models.JobStatusActive,
		PaymentMethod:      "wallet",
		Location:           models.Location{Latitude: 30.0444, Longitude: 31.2357},
		LockedEscrowAmount: agreedPrice,
		AgreedPrice:        &agreedPrice,
		CreatedAt:          time.Now().UTC(),
		UpdatedAt:          time.Now().UTC(),
	}
	if err := s.CreateJob(ctx, activeJob); err != nil {
		t.Fatalf("failed to create negotiated transport job: %v", err)
	}

	ownerToken, err := jwtutil.GenerateToken(ownerID, "owner", ownerID, "owner@finding2.com")
	if err != nil {
		t.Fatalf("failed to generate owner token: %v", err)
	}

	// Execute CancelJob request
	cancelReq := map[string]string{
		"job_id":       jobID,
		"reason":       "negotiated transport cancelled",
		"requester_id": ownerToken,
	}
	body, _ := json.Marshal(cancelReq)
	req := httptest.NewRequest("POST", "/users/jobs/cancel", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+ownerToken)
	w := httptest.NewRecorder()

	svcHandler.CancelJob(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("CancelJob failed with HTTP %d: %s", w.Code, w.Body.String())
	}

	// Verify wallet balances after cancellation
	wallet, err := s.GetOrCreateWallet(ctx, ownerID)
	if err != nil {
		t.Fatalf("failed to fetch wallet: %v", err)
	}

	// Deposited 200, locked 150 (withdrawable became 50, escrow 150). On cancel, full 150 refunded to withdrawable (back to 200).
	if wallet.EscrowBalance != 0.0 {
		t.Errorf("Expected EscrowBalance to be 0.0 after full refund, got %.2f (fund leakage!)", wallet.EscrowBalance)
	}
	if wallet.WithdrawableBalance != 200.0 {
		t.Errorf("Expected WithdrawableBalance to be 200.0 after full refund, got %.2f", wallet.WithdrawableBalance)
	}

	// Verify job document locked escrow amount is 0
	updatedJob := s.GetJob(ctx, jobID)
	if updatedJob.LockedEscrowAmount != 0.0 {
		t.Errorf("Expected Job LockedEscrowAmount to be 0.0, got %.2f", updatedJob.LockedEscrowAmount)
	}
}
