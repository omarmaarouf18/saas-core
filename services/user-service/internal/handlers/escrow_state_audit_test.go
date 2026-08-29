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

// Test1_FullLifecycleStateAudit walks a single negotiable transport job through its entire
// lifecycle (TrackJob -> RespondPrice accept -> CompleteJob) and directly inspects the underlying
// database state (MongoDB job document and wallet document) at every step to ensure 0 drift
// between recorded job escrow and actual wallet debits/releases.
func Test1_FullLifecycleStateAudit(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	dbName := fmt.Sprintf("saas_platform_audit_test_%d", time.Now().UnixNano())
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

	ownerID := "owner-audit-1"
	custID := "cust-audit-1"
	empID := "emp-audit-1"

	mockAuthServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		id := r.URL.Query().Get("id")
		if id == empID {
			json.NewEncoder(w).Encode(map[string]any{
				"id":        id,
				"role":      "employee",
				"is_active": true,
				"tenant_id": ownerID,
			})
			return
		}
		if id == custID {
			json.NewEncoder(w).Encode(map[string]any{
				"id":        id,
				"role":      "customer",
				"is_active": true,
				"tenant_id": ownerID,
			})
			return
		}
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

	tokenOwner, _ := jwtutil.GenerateToken(ownerID, "owner", ownerID, "owner@example.com")
	tokenCust, _ := jwtutil.GenerateToken(custID, "customer", ownerID, "cust@example.com")
	tokenEmp, _ := jwtutil.GenerateToken(empID, "employee", ownerID, "emp@example.com")

	svc := &models.Service{
		ID:               "svc-audit-trans-1",
		TenantID:         ownerID,
		Name:             "Audit Transport Service",
		Category:         "transport",
		TenantBasePrice:  100.0,
		TenantPricePerKM: 2.0,
		Latitude:         30.0,
		Longitude:        30.0,
	}
	s.CreateService(ctx, svc)

	_ = s.UpsertEmployeeLocation(ctx, &models.EmployeeLocation{
		TenantID:   ownerID,
		EmployeeID: empID,
		Latitude:   30.0,
		Longitude:  30.0,
		UpdatedAt:  time.Now().UTC(),
	})

	// Deposit initial funds into owner wallet
	initialDeposit := 500.0
	if err := s.Deposit(ctx, ownerID, initialDeposit); err != nil {
		t.Fatalf("Failed to deposit funds for owner: %v", err)
	}

	// Verify initial wallet state
	wallet0, err := s.GetOrCreateWallet(ctx, ownerID)
	if err != nil {
		t.Fatalf("Failed to fetch initial wallet: %v", err)
	}
	if wallet0.WithdrawableBalance != 500.0 || wallet0.EscrowBalance != 0.0 {
		t.Fatalf("Initial wallet state mismatch: balance=%.2f escrow=%.2f", wallet0.WithdrawableBalance, wallet0.EscrowBalance)
	}

	// ---------------------------------------------------------
	// Step 1: TrackJob (Booking with proposed price)
	// ---------------------------------------------------------
	trackReq := map[string]any{
		"owner_id":       tokenOwner,
		"service_id":     svc.ID,
		"user_id":        tokenCust,
		"employee_id":    tokenEmp,
		"payment_method": "wallet",
		"proposed_price": 120.0,
		"location": models.Location{
			Latitude:  30.0,
			Longitude: 30.0,
		},
	}
	tBody, _ := json.Marshal(trackReq)
	req1 := httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(tBody))
	req1.Header.Set("X-Real-IP", "192.168.10.1")
	rec1 := httptest.NewRecorder()
	u.TrackJob(rec1, req1)

	if rec1.Code != http.StatusCreated {
		t.Fatalf("Step 1 TrackJob failed: code=%d body=%s", rec1.Code, rec1.Body.String())
	}

	var trackResp map[string]any
	json.Unmarshal(rec1.Body.Bytes(), &trackResp)
	jobData, _ := trackResp["job"].(map[string]any)
	jobID, _ := jobData["id"].(string)

	// Directly inspect MongoDB job document after Step 1
	jobStep1 := s.GetJob(ctx, jobID)
	if jobStep1 == nil {
		t.Fatalf("Step 1: Job %s not found in MongoDB", jobID)
	}
	if jobStep1.Status != models.JobStatusAwaitingPriceResponse {
		t.Errorf("Step 1 DB check: expected status %s, got %s", models.JobStatusAwaitingPriceResponse, jobStep1.Status)
	}
	if jobStep1.LockedEscrowAmount != 0.0 {
		t.Errorf("Step 1 DB check: expected LockedEscrowAmount == 0.0 (not yet locked), got %.2f", jobStep1.LockedEscrowAmount)
	}

	// Directly inspect Owner Wallet document after Step 1
	walletStep1, _ := s.GetOrCreateWallet(ctx, ownerID)
	if walletStep1.WithdrawableBalance != 500.0 {
		t.Errorf("Step 1 Wallet check: expected WithdrawableBalance == 500.0, got %.2f", walletStep1.WithdrawableBalance)
	}
	if walletStep1.EscrowBalance != 0.0 {
		t.Errorf("Step 1 Wallet check: expected EscrowBalance == 0.0, got %.2f", walletStep1.EscrowBalance)
	}

	// ---------------------------------------------------------
	// Step 2: RespondPrice Accept (non-COD negotiable transport)
	// ---------------------------------------------------------
	respReq := map[string]any{
		"job_id":          jobID,
		"decision":        "accept",
		"requester_token": tokenEmp,
	}
	rBody, _ := json.Marshal(respReq)
	req2 := httptest.NewRequest("POST", "/users/jobs/respond-price", bytes.NewReader(rBody))
	req2.Header.Set("X-Real-IP", "192.168.10.2")
	rec2 := httptest.NewRecorder()
	u.RespondPrice(rec2, req2)

	if rec2.Code != http.StatusOK {
		t.Fatalf("Step 2 RespondPrice failed: code=%d body=%s", rec2.Code, rec2.Body.String())
	}

	// Directly inspect MongoDB job document after Step 2
	jobStep2 := s.GetJob(ctx, jobID)
	if jobStep2 == nil {
		t.Fatalf("Step 2: Job %s not found in MongoDB", jobID)
	}
	if jobStep2.Status != models.JobStatusActive {
		t.Errorf("Step 2 DB check: expected status active, got %s", jobStep2.Status)
	}
	if jobStep2.AgreedPrice == nil || *jobStep2.AgreedPrice != 120.0 {
		t.Errorf("Step 2 DB check: expected AgreedPrice == 120.0, got %v", jobStep2.AgreedPrice)
	}
	if jobStep2.LockedEscrowAmount != 120.0 {
		t.Errorf("Step 2 DB check: expected LockedEscrowAmount == 120.0, got %.2f", jobStep2.LockedEscrowAmount)
	}

	// Directly inspect Owner Wallet document after Step 2 (STATE VERIFICATION: WALLET DEBITED)
	walletStep2, _ := s.GetOrCreateWallet(ctx, ownerID)
	expectedAvailableBalance := initialDeposit - 120.0 // 380.0
	expectedEscrowBalance := 120.0

	if walletStep2.WithdrawableBalance != expectedAvailableBalance {
		t.Errorf("Step 2 Wallet check: expected available balance %.2f (debited by 120.0), got %.2f", expectedAvailableBalance, walletStep2.WithdrawableBalance)
	}
	if walletStep2.EscrowBalance != expectedEscrowBalance {
		t.Errorf("Step 2 Wallet check: expected escrow balance %.2f, got %.2f", expectedEscrowBalance, walletStep2.EscrowBalance)
	}

	// Confirm exact parity: job.LockedEscrowAmount matches wallet.EscrowBalance
	if jobStep2.LockedEscrowAmount != walletStep2.EscrowBalance {
		t.Errorf("Step 2 DRIFT DETECTED: job.LockedEscrowAmount (%.2f) != wallet.EscrowBalance (%.2f)", jobStep2.LockedEscrowAmount, walletStep2.EscrowBalance)
	}

	// ---------------------------------------------------------
	// Step 3: CompleteJob (Completion and Settlement)
	// ---------------------------------------------------------
	compReq := map[string]any{
		"job_id":          jobID,
		"requester_token": tokenEmp,
	}
	cBody, _ := json.Marshal(compReq)
	req3 := httptest.NewRequest("POST", "/users/jobs/complete", bytes.NewReader(cBody))
	req3.Header.Set("X-Real-IP", "192.168.10.3")
	rec3 := httptest.NewRecorder()
	u.CompleteJob(rec3, req3)

	if rec3.Code != http.StatusOK {
		t.Fatalf("Step 3 CompleteJob failed: code=%d body=%s", rec3.Code, rec3.Body.String())
	}

	var compResp map[string]any
	json.Unmarshal(rec3.Body.Bytes(), &compResp)
	totalAmount, _ := compResp["total_amount"].(float64)

	// Assert final released amount matches the locked amount (120.0)
	if totalAmount != 120.0 {
		t.Errorf("Step 3 CompleteJob check: expected total_amount == 120.0, got %.2f", totalAmount)
	}

	// Directly inspect MongoDB job document after Step 3
	jobStep3 := s.GetJob(ctx, jobID)
	if jobStep3.Status != models.JobStatusCompleted {
		t.Errorf("Step 3 DB check: expected status completed, got %s", jobStep3.Status)
	}
	// Assert LockedEscrowAmount is 0.0 after ReleaseEscrowWithSplit decrements locked escrow
	if jobStep3.LockedEscrowAmount != 0.0 {
		t.Errorf("Step 3 DB check: expected LockedEscrowAmount == 0.0 after release, got %.2f", jobStep3.LockedEscrowAmount)
	}

	// Directly inspect Owner Wallet document after Step 3
	walletStep3, _ := s.GetOrCreateWallet(ctx, ownerID)
	if walletStep3.EscrowBalance != 0.0 {
		t.Errorf("Step 3 Wallet check: expected EscrowBalance == 0.0 after release, got %.2f", walletStep3.EscrowBalance)
	}
	// Expected withdrawable balance = 380.0 + 120.0 (100% net payout per ADR-0017 0% platform fee) = 500.0
	expectedFinalWithdrawable := 380.0 + 120.0
	if walletStep3.WithdrawableBalance != expectedFinalWithdrawable {
		t.Errorf("Step 3 Wallet check: expected withdrawable balance %.2f (380 + 120 net), got %.2f", expectedFinalWithdrawable, walletStep3.WithdrawableBalance)
	}
}

// Test3_CrossFeatureInteraction_RespondPrice_And_ADR0007_SpeedCheck verifies that a transport job
// that undergoes RespondPrice accept escrow locking and subsequent ADR-0007 cumulative speed check
// validation maintains strict state integrity without cross-feature corruption.
func Test3_CrossFeatureInteraction_RespondPrice_And_ADR0007_SpeedCheck(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	dbName := fmt.Sprintf("saas_platform_interact_test_%d", time.Now().UnixNano())
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

	ownerID := "owner-interact-1"
	custID := "cust-interact-1"
	empID := "emp-interact-1"

	mockAuthServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		id := r.URL.Query().Get("id")
		if id == empID {
			json.NewEncoder(w).Encode(map[string]any{
				"id":        id,
				"role":      "employee",
				"is_active": true,
				"tenant_id": ownerID,
			})
			return
		}
		if id == custID {
			json.NewEncoder(w).Encode(map[string]any{
				"id":        id,
				"role":      "customer",
				"is_active": true,
				"tenant_id": ownerID,
			})
			return
		}
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

	tokenOwner, _ := jwtutil.GenerateToken(ownerID, "owner", ownerID, "owner@example.com")
	tokenCust, _ := jwtutil.GenerateToken(custID, "customer", ownerID, "cust@example.com")
	tokenEmp, _ := jwtutil.GenerateToken(empID, "employee", ownerID, "emp@example.com")

	svc := &models.Service{
		ID:               "svc-interact-trans-1",
		TenantID:         ownerID,
		Name:             "Interact Transport Service",
		Category:         "transport",
		TenantBasePrice:  120.0,
		TenantPricePerKM: 3.0,
		Latitude:         30.0,
		Longitude:        30.0,
	}
	s.CreateService(ctx, svc)
	_ = s.Deposit(ctx, ownerID, 600.0)
	_ = s.UpsertEmployeeLocation(ctx, &models.EmployeeLocation{
		TenantID:   ownerID,
		EmployeeID: empID,
		Latitude:   30.0,
		Longitude:  30.0,
		UpdatedAt:  time.Now().UTC(),
	})
	_ = s.UpsertSubscription(ctx, &models.Subscription{
		ID:        "sub-interact-1",
		TenantID:  ownerID,
		Tier:      models.PlanPaid,
		StartedAt: time.Now().Add(-1 * time.Hour),
		ExpiresAt: time.Now().Add(30 * 24 * time.Hour),
	})

	// 1. Create Job with TrackJob
	trackReq := map[string]any{
		"owner_id":       tokenOwner,
		"service_id":     svc.ID,
		"user_id":        tokenCust,
		"employee_id":    tokenEmp,
		"payment_method": "wallet",
		"proposed_price": 150.0,
		"location": models.Location{
			Latitude:  30.0,
			Longitude: 30.0,
		},
	}
	tBody, _ := json.Marshal(trackReq)
	req1 := httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(tBody))
	req1.Header.Set("X-Real-IP", "192.168.20.1")
	rec1 := httptest.NewRecorder()
	u.TrackJob(rec1, req1)

	var trackResp map[string]any
	json.Unmarshal(rec1.Body.Bytes(), &trackResp)
	jobData, _ := trackResp["job"].(map[string]any)
	jobID, _ := jobData["id"].(string)

	// 2. Execute RespondPrice Accept (Locks Escrow at 150.0)
	respReq := map[string]any{
		"job_id":          jobID,
		"decision":        "accept",
		"requester_token": tokenEmp,
	}
	rBody, _ := json.Marshal(respReq)
	req2 := httptest.NewRequest("POST", "/users/jobs/respond-price", bytes.NewReader(rBody))
	req2.Header.Set("X-Real-IP", "192.168.20.2")
	rec2 := httptest.NewRecorder()
	u.RespondPrice(rec2, req2)

	if rec2.Code != http.StatusOK {
		t.Fatalf("RespondPrice accept failed: %s", rec2.Body.String())
	}

	// Verify escrow locked state in DB and wallet
	jobAfterAccept := s.GetJob(ctx, jobID)
	if jobAfterAccept.Status != models.JobStatusActive || jobAfterAccept.LockedEscrowAmount != 150.0 {
		t.Fatalf("Job state mismatch after RespondPrice accept: status=%s locked=%.2f", jobAfterAccept.Status, jobAfterAccept.LockedEscrowAmount)
	}

	walletAfterAccept, _ := s.GetOrCreateWallet(ctx, ownerID)
	if walletAfterAccept.EscrowBalance != 150.0 {
		t.Fatalf("Wallet escrow balance mismatch after RespondPrice accept: %.2f", walletAfterAccept.EscrowBalance)
	}

	// 3. Send valid initial UpdateJobLocation at same coordinates (dist = 0.0 -> speed = 0.0)
	locReq1 := map[string]any{
		"job_id":          jobID,
		"requester_token": tokenEmp,
		"latitude":        30.0,
		"longitude":       30.0,
	}
	lBody1, _ := json.Marshal(locReq1)
	reqLoc1 := httptest.NewRequest("POST", "/users/jobs/location", bytes.NewReader(lBody1))
	reqLoc1.Header.Set("X-Real-IP", "192.168.20.3")
	recLoc1 := httptest.NewRecorder()
	u.UpdateJobLocation(recLoc1, reqLoc1)

	if recLoc1.Code != http.StatusOK {
		t.Fatalf("Valid location update failed: code=%d body=%s", recLoc1.Code, recLoc1.Body.String())
	}

	// Clear location throttle key so locReq2 passes 3s minimum interval rate limiter and hits speed check
	u.locationThrottleMu.Lock()
	delete(u.locationLastUpdate, jobID)
	u.locationThrottleMu.Unlock()
	if rdb != nil {
		_ = rdb.Del(ctx, "loc:lastupdate:"+jobID).Err()
	}

	// 4. Send speed-violation UpdateJobLocation (moving 550 km instantaneously -> > 150.0 km/h speed limit)
	locReq2 := map[string]any{
		"job_id":          jobID,
		"requester_token": tokenEmp,
		"latitude":        35.0, // ~550 km distance instantaneously
		"longitude":       30.0,
	}
	lBody2, _ := json.Marshal(locReq2)
	reqLoc2 := httptest.NewRequest("POST", "/users/jobs/location", bytes.NewReader(lBody2))
	reqLoc2.Header.Set("X-Real-IP", "192.168.20.4")
	recLoc2 := httptest.NewRecorder()
	u.UpdateJobLocation(recLoc2, reqLoc2)

	if recLoc2.Code != http.StatusBadRequest {
		t.Fatalf("Expected 400 Bad Request on speed check violation, got %d: %s", recLoc2.Code, recLoc2.Body.String())
	}

	// 5. Re-inspect state in MongoDB & Wallet after speed violation rejection
	jobAfterSpeedCheck := s.GetJob(ctx, jobID)
	if jobAfterSpeedCheck.Status != models.JobStatusActive {
		t.Errorf("Job status corrupted by speed check rejection: expected active, got %s", jobAfterSpeedCheck.Status)
	}
	if jobAfterSpeedCheck.LockedEscrowAmount != 150.0 {
		t.Errorf("LockedEscrowAmount corrupted by speed check rejection: expected 150.0, got %.2f", jobAfterSpeedCheck.LockedEscrowAmount)
	}
	if jobAfterSpeedCheck.AgreedPrice == nil || *jobAfterSpeedCheck.AgreedPrice != 150.0 {
		t.Errorf("AgreedPrice corrupted by speed check rejection: expected 150.0, got %v", jobAfterSpeedCheck.AgreedPrice)
	}

	walletAfterSpeedCheck, _ := s.GetOrCreateWallet(ctx, ownerID)
	if walletAfterSpeedCheck.EscrowBalance != 150.0 {
		t.Errorf("Wallet EscrowBalance corrupted by speed check rejection: expected 150.0, got %.2f", walletAfterSpeedCheck.EscrowBalance)
	}

	// 6. Execute CompleteJob and confirm smooth settlement
	compReq := map[string]any{
		"job_id":          jobID,
		"requester_token": tokenEmp,
	}
	cBody, _ := json.Marshal(compReq)
	reqComp := httptest.NewRequest("POST", "/users/jobs/complete", bytes.NewReader(cBody))
	reqComp.Header.Set("X-Real-IP", "192.168.20.5")
	recComp := httptest.NewRecorder()
	u.CompleteJob(recComp, reqComp)

	if recComp.Code != http.StatusOK {
		t.Fatalf("CompleteJob failed after speed check violation: code=%d body=%s", recComp.Code, recComp.Body.String())
	}

	jobFinal := s.GetJob(ctx, jobID)
	if jobFinal.Status != models.JobStatusCompleted {
		t.Errorf("Final job status expected completed, got %s", jobFinal.Status)
	}

	walletFinal, _ := s.GetOrCreateWallet(ctx, ownerID)
	if walletFinal.EscrowBalance != 0.0 {
		t.Errorf("Final wallet EscrowBalance expected 0.0, got %.2f", walletFinal.EscrowBalance)
	}
}
