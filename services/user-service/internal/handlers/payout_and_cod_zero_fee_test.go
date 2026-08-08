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

	"github.com/alicebob/miniredis/v2"
	"github.com/project/shared/infra/jwtutil"
	"github.com/project/user-service/internal/config"
	"github.com/project/user-service/internal/models"
	"github.com/project/user-service/internal/store"
	"github.com/redis/go-redis/v9"
)

func TestCODZeroFeeCompletion(t *testing.T) {
	secret := "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2"
	os.Setenv("JWT_SECRET", secret)
	jwtutil.Init(secret)
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://root:devpassword123@localhost:27017/saas_platform?authSource=admin"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	dbName := fmt.Sprintf("saas_platform_test_cod_zero_fee_%d", time.Now().UnixNano())
	s, err := store.NewMongoDB(ctx, mongoURI, dbName)
	if err != nil {
		t.Skipf("Skipping test: MongoDB not available (%v)", err)
		return
	}
	defer func() {
		_ = s.DropDatabase(context.Background())
		s.Close(context.Background())
	}()

	mr, _ := miniredis.Run()
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
		InternalServiceToken:   "mock-token",
		AllowTestPaymentBypass: true,
		AppEnv:                 "test",
	}
	svcHandler := NewUserService(s, cfg, rdb)

	ownerID := "owner-cod-zero"
	jobID := "job-cod-zero-1"

	s.CreateService(ctx, &models.Service{
		ID:              "svc-cod",
		TenantID:        ownerID,
		Name:            "COD Service",
		Category:        "cleaning",
		TenantBasePrice: 100.0,
		Latitude:        30.0444,
		Longitude:       31.2357,
	})

	// Initial wallet balance = 0
	walletBefore, err := s.GetOrCreateWallet(ctx, ownerID)
	if err != nil {
		t.Fatalf("failed to create wallet: %v", err)
	}

	// Create active COD job
	if err := s.CreateJob(ctx, &models.Job{
		ID:            jobID,
		OwnerID:       ownerID,
		UserID:        "cust-cod",
		ServiceID:     "svc-cod",
		Status:        models.JobStatusActive,
		PaymentMethod: "cod",
		Location:      models.Location{Latitude: 30.0444, Longitude: 31.2357},
		CreatedAt:     time.Now().UTC(),
		UpdatedAt:     time.Now().UTC(),
	}); err != nil {
		t.Fatalf("failed to create COD job: %v", err)
	}

	ownerToken, _ := jwtutil.GenerateToken(ownerID, "owner", ownerID, "owner@cod.com")

	// Complete COD job
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

	if w.Code != http.StatusOK {
		t.Fatalf("CompleteJob failed with status %d: %s", w.Code, w.Body.String())
	}

	var res map[string]any
	json.Unmarshal(w.Body.Bytes(), &res)
	if res["platform_fee"] != 0.0 {
		t.Errorf("Expected platform_fee 0.0, got %v", res["platform_fee"])
	}

	// Verify wallet balance remained completely unchanged (0 mutation)
	walletAfter, _ := s.GetOrCreateWallet(ctx, ownerID)
	if walletAfter.TotalBalance != walletBefore.TotalBalance {
		t.Errorf("Expected TotalBalance to remain %.2f, got %.2f", walletBefore.TotalBalance, walletAfter.TotalBalance)
	}
	if walletAfter.WithdrawableBalance != walletBefore.WithdrawableBalance {
		t.Errorf("Expected WithdrawableBalance to remain %.2f, got %.2f", walletBefore.WithdrawableBalance, walletAfter.WithdrawableBalance)
	}

	// Verify job is marked Completed
	completedJob := s.GetJob(ctx, jobID)
	if completedJob.Status != models.JobStatusCompleted {
		t.Errorf("Expected job status Completed, got %s", completedJob.Status)
	}
}

func TestOwnerPayoutRequestFlow(t *testing.T) {
	secret := "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2"
	os.Setenv("JWT_SECRET", secret)
	jwtutil.Init(secret)
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://root:devpassword123@localhost:27017/saas_platform?authSource=admin"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	dbName := fmt.Sprintf("saas_platform_test_payout_%d", time.Now().UnixNano())
	s, err := store.NewMongoDB(ctx, mongoURI, dbName)
	if err != nil {
		t.Skipf("Skipping test: MongoDB not available (%v)", err)
		return
	}
	defer func() {
		_ = s.DropDatabase(context.Background())
		s.Close(context.Background())
	}()

	mr, _ := miniredis.Run()
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
		InternalServiceToken:   "mock-token",
		AllowTestPaymentBypass: true,
		AppEnv:                 "test",
	}
	svcHandler := NewUserService(s, cfg, rdb)

	ownerID := "owner-payout-1"
	ownerToken, _ := jwtutil.GenerateToken(ownerID, "owner", ownerID, "owner@payout.com")

	// Deposit 500 to owner wallet
	s.GetOrCreateWallet(ctx, ownerID)
	if err := s.Deposit(ctx, ownerID, 500.0); err != nil {
		t.Fatalf("failed to deposit: %v", err)
	}

	// 1. Attempt payout request exceeding balance (600 > 500) -> 400 Bad Request
	excessReq := models.CreatePayoutRequestInput{
		Amount:       600.0,
		PayoutMethod: "bank_transfer",
	}
	body, _ := json.Marshal(excessReq)
	req := httptest.NewRequest("POST", "/users/wallet/payout/request", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+ownerToken)
	w := httptest.NewRecorder()

	svcHandler.RequestPayout(w, req)
	if w.Code != http.StatusBadRequest {
		t.Errorf("Expected HTTP 400 for excessive payout request, got %d", w.Code)
	}

	// 2. Valid payout request (200 <= 500) -> 201 Created
	validReq := models.CreatePayoutRequestInput{
		Amount:         200.0,
		PayoutMethod:   "instapay",
		AccountDetails: "user@instapay",
	}
	body, _ = json.Marshal(validReq)
	req = httptest.NewRequest("POST", "/users/wallet/payout/request", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+ownerToken)
	w = httptest.NewRecorder()

	svcHandler.RequestPayout(w, req)
	if w.Code != http.StatusCreated {
		t.Fatalf("RequestPayout failed with HTTP %d: %s", w.Code, w.Body.String())
	}

	var payoutRes models.PayoutRequest
	json.Unmarshal(w.Body.Bytes(), &payoutRes)
	if payoutRes.Amount != 200.0 || payoutRes.Status != models.PayoutStatusRequested || payoutRes.PayoutMethod != "instapay" {
		t.Errorf("Unexpected payout response: %+v", payoutRes)
	}

	// Verify wallet balance decreased to 300 (500 - 200)
	wallet, _ := s.GetOrCreateWallet(ctx, ownerID)
	if wallet.WithdrawableBalance != 300.0 {
		t.Errorf("Expected withdrawable balance 300.0, got %.2f", wallet.WithdrawableBalance)
	}

	// 3. Retrieve payout history GET /users/wallet/payout/requests
	reqHist := httptest.NewRequest("GET", "/users/wallet/payout/requests", nil)
	reqHist.Header.Set("Authorization", "Bearer "+ownerToken)
	wHist := httptest.NewRecorder()

	svcHandler.GetPayoutRequests(wHist, reqHist)
	if wHist.Code != http.StatusOK {
		t.Fatalf("GetPayoutRequests failed with HTTP %d: %s", wHist.Code, wHist.Body.String())
	}

	var requests []*models.PayoutRequest
	json.Unmarshal(wHist.Body.Bytes(), &requests)
	if len(requests) != 1 || requests[0].ID != payoutRes.ID {
		t.Errorf("Expected 1 payout request matching ID %s, got %d items", payoutRes.ID, len(requests))
	}
}

func TestElectronicPaymentsFeatureFlag(t *testing.T) {
	secret := "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2"
	os.Setenv("JWT_SECRET", secret)
	jwtutil.Init(secret)

	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://root:devpassword123@localhost:27017/saas_platform?authSource=admin"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	dbName := fmt.Sprintf("saas_platform_test_flag_%d", time.Now().UnixNano())
	s, err := store.NewMongoDB(ctx, mongoURI, dbName)
	if err != nil {
		t.Skipf("Skipping test: MongoDB not available (%v)", err)
		return
	}
	defer func() {
		_ = s.DropDatabase(context.Background())
		s.Close(context.Background())
	}()

	mr, _ := miniredis.Run()
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

	// Config with ElectronicPaymentsEnabled = false and AllowTestPaymentBypass = false
	cfgDisabled := &config.Config{
		AuthServiceURL:            mockAuthServer.URL,
		InternalServiceToken:      "mock-token",
		AllowTestPaymentBypass:   false,
		ElectronicPaymentsEnabled: false,
		AppEnv:                    "production",
	}
	svcDisabled := NewUserService(s, cfgDisabled, rdb)

	ownerToken, _ := jwtutil.GenerateToken("owner-flag", "owner", "owner-flag", "owner@flag.com")
	custToken, _ := jwtutil.GenerateToken("cust-flag", "customer", "tenant-flag", "cust@flag.com")

	reqBody := map[string]any{
		"owner_id":       "owner-flag",
		"owner_token":    ownerToken,
		"user_id":        "cust-flag",
		"service_id":     "svc-flag",
		"payment_method": "wallet",
		"user_token":     custToken,
	}
	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+ownerToken)
	w := httptest.NewRecorder()

	svcDisabled.TrackJob(w, req)
	if w.Code != http.StatusBadRequest {
		t.Errorf("Expected HTTP 400 for electronic payment when flag disabled, got %d (body: %s)", w.Code, w.Body.String())
	}

	// Config with ElectronicPaymentsEnabled = true
	cfgEnabled := &config.Config{
		AuthServiceURL:            mockAuthServer.URL,
		InternalServiceToken:      "mock-token",
		AllowTestPaymentBypass:   false,
		ElectronicPaymentsEnabled: true,
		AppEnv:                    "production",
	}
	svcEnabled := NewUserService(s, cfgEnabled, rdb)

	s.CreateService(ctx, &models.Service{
		ID:              "svc-flag",
		TenantID:        "owner-flag",
		Name:            "Flag Service",
		Category:        "cleaning",
		TenantBasePrice: 100.0,
		Latitude:        30.0444,
		Longitude:       31.2357,
	})
	s.GetOrCreateWallet(ctx, "owner-flag")
	s.Deposit(ctx, "owner-flag", 200.0)

	req2 := httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(body))
	req2.Header.Set("Authorization", "Bearer "+ownerToken)
	w2 := httptest.NewRecorder()
	svcEnabled.TrackJob(w2, req2)

	if w2.Code == http.StatusBadRequest && strings.Contains(w2.Body.String(), "electronic payments are not currently enabled") {
		t.Errorf("TrackJob failed due to payment flag when flag was enabled: %s", w2.Body.String())
	}
}
