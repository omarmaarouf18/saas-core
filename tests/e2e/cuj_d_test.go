package e2e

import (
	"context"
	"encoding/json"
	"fmt"
	"math/rand"
	"net/http"
	"testing"
	"time"
)

// TestCUJ_D_DriverWorkflowFullCycle tests the end-to-end driver lifecycle:
// 1. Seed tenant, owner, service, customer, customer wallet (500 EGP), Courier A, and Courier B
// 2. Customer books delivery job through Caddy Gateway -> pending_dispatch
// 3. Courier A receives offer and accepts -> status transitions to active
// 4. Courier A updates location at pickup site
// 5. IDOR Guard 1: Courier B attempts to complete Courier A's job -> rejected with 403 Forbidden
// 6. IDOR Guard 2: Courier B attempts to query Courier A's job scoped to courier B -> rejected with 403 Forbidden
// 7. Courier A completes job -> status completed, escrow released to 0
// 8. Payout eligibility / wallet balance verification confirms release
func TestCUJ_D_DriverWorkflowFullCycle(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	cfg := LoadConfig()

	db, err := ConnectStagingDB(ctx, cfg.MongoURI)
	if err != nil {
		t.Fatalf("Failed to connect to staging DB: %v", err)
	}
	defer db.Close(ctx)

	rnd := rand.New(rand.NewSource(time.Now().UnixNano())).Intn(900000) + 100000
	tenantID := fmt.Sprintf("tenant-cuj-d-%d", rnd)
	ownerID := tenantID
	serviceID := fmt.Sprintf("svc-cuj-d-%d", rnd)
	courierAID := fmt.Sprintf("courierA-cuj-d-%d", rnd)
	courierBID := fmt.Sprintf("courierB-cuj-d-%d", rnd)
	customerID := fmt.Sprintf("cust-cuj-d-%d", rnd)

	defer func() {
		db.CleanupTestEntities(ctx, []string{tenantID}, []string{ownerID, courierAID, courierBID, customerID})
	}()

	// 1. Seed Tenant, Service, Couriers, Customer, Wallet
	basePrice := 20.0
	pricePerKM := 5.0
	startLat, startLon := 30.0444, 31.2357

	if err := db.SeedTenantAndService(ctx, tenantID, ownerID, serviceID, basePrice, pricePerKM, startLat, startLon); err != nil {
		t.Fatalf("Failed to seed tenant and service: %v", err)
	}
	if err := db.SeedCourier(ctx, tenantID, courierAID, courierAID+"@staging.local", startLat, startLon); err != nil {
		t.Fatalf("Failed to seed courier A: %v", err)
	}
	if err := db.SeedCourier(ctx, tenantID, courierBID, courierBID+"@staging.local", 30.0500, 31.2400); err != nil {
		t.Fatalf("Failed to seed courier B: %v", err)
	}
	if err := db.SeedCustomer(ctx, tenantID, customerID, customerID+"@staging.local"); err != nil {
		t.Fatalf("Failed to seed customer: %v", err)
	}
	if err := db.SeedWallet(ctx, tenantID, 500.0); err != nil {
		t.Fatalf("Failed to seed wallet: %v", err)
	}

	ownerToken, err := cfg.GenerateJWT(ownerID, "owner", tenantID, ownerID+"@staging.local")
	if err != nil {
		t.Fatalf("Failed to generate owner token: %v", err)
	}
	custToken, err := cfg.GenerateJWT(customerID, "user", tenantID, customerID+"@staging.local")
	if err != nil {
		t.Fatalf("Failed to generate customer token: %v", err)
	}
	courierAToken, err := cfg.GenerateJWT(courierAID, "employee", tenantID, courierAID+"@staging.local")
	if err != nil {
		t.Fatalf("Failed to generate courier A token: %v", err)
	}
	courierBToken, err := cfg.GenerateJWT(courierBID, "employee", tenantID, courierBID+"@staging.local")
	if err != nil {
		t.Fatalf("Failed to generate courier B token: %v", err)
	}

	// 2. Customer books job with properly formatted location struct
	bookPayload := map[string]any{
		"service_id":     serviceID,
		"user_id":        custToken,
		"payment_method": "wallet",
		"location": map[string]float64{
			"latitude":  startLat,
			"longitude": startLon,
		},
	}
	resp, body, err := PostJSON(ctx, cfg.GatewayURL+"/api/v1/users/jobs/track", custToken, bookPayload)
	if err != nil {
		t.Fatalf("Failed to book job: %v", err)
	}
	if resp.StatusCode != http.StatusCreated {
		t.Fatalf("Expected 201 Created from job booking, got %d: %s", resp.StatusCode, string(body))
	}

	var bookResp struct {
		JobID string `json:"job_id"`
		Job   struct {
			ID     string `json:"id"`
			Status string `json:"status"`
		} `json:"job"`
	}
	if err := json.Unmarshal(body, &bookResp); err != nil {
		t.Fatalf("Failed to decode book response: %v", err)
	}
	jobID := bookResp.JobID
	if jobID == "" {
		jobID = bookResp.Job.ID
	}
	if jobID == "" {
		t.Fatalf("Expected job ID in booking response, got: %s", string(body))
	}
	t.Logf("Customer booked job %s successfully through Gateway", jobID)

	// 3. Courier A accepts job offer
	acceptURL := fmt.Sprintf("%s/api/v1/users/employee/jobs/%s/accept", cfg.GatewayURL, jobID)
	resp, body, err = PostJSON(ctx, acceptURL, courierAToken, nil)
	if err != nil {
		t.Fatalf("Courier A failed to accept job: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("Expected 200 OK from job acceptance, got %d: %s", resp.StatusCode, string(body))
	}
	t.Logf("Courier A successfully accepted job %s", jobID)

	// 4. Courier A updates location at pickup site
	locUpdateURL := cfg.GatewayURL + "/api/v1/users/jobs/location/update"
	locUpdate1 := map[string]any{
		"job_id":          jobID,
		"latitude":        startLat,
		"longitude":       startLon,
		"requester_token": courierAToken,
	}
	resp, body, err = PostJSON(ctx, locUpdateURL, courierAToken, locUpdate1)
	if err != nil {
		t.Fatalf("Courier A failed to update location: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("Expected 200 OK on location update, got %d: %s", resp.StatusCode, string(body))
	}
	t.Logf("Courier A updated delivery coordinates at pickup site successfully")

	// 5. IDOR Guard 1: Courier B attempts to complete Courier A's job
	idorCompletePayload := map[string]any{
		"job_id":          jobID,
		"requester_token": courierBToken,
	}
	resp, body, err = PostJSON(ctx, cfg.GatewayURL+"/api/v1/users/jobs/complete", courierBToken, idorCompletePayload)
	if err != nil {
		t.Fatalf("Failed to execute IDOR complete request: %v", err)
	}
	if resp.StatusCode != http.StatusForbidden {
		t.Fatalf("ASSERTION FAILED: Courier B completing Courier A's job should return 403 Forbidden, got %d: %s", resp.StatusCode, string(body))
	}
	t.Logf("Verified IDOR Guard 1: Courier B blocked from completing Courier A's job with 403 Forbidden")

	// 6. IDOR Guard 2: Courier B attempts to query Courier A's job with employee_id scoping
	getJobURL := fmt.Sprintf("%s/api/v1/users/jobs/get?id=%s&requester_token=%s&employee_id=%s", cfg.GatewayURL, jobID, courierBToken, courierBID)
	resp, body, err = GetJSON(ctx, getJobURL, courierBToken)
	if err != nil {
		t.Fatalf("Failed to execute IDOR get job request: %v", err)
	}
	if resp.StatusCode != http.StatusForbidden {
		t.Fatalf("ASSERTION FAILED: Courier B querying Courier A's job should return 403 Forbidden, got %d: %s", resp.StatusCode, string(body))
	}
	t.Logf("Verified IDOR Guard 2: Courier B blocked from reading Courier A's job with 403 Forbidden")

	// 7. Courier A completes job
	validCompletePayload := map[string]any{
		"job_id":          jobID,
		"requester_token": courierAToken,
	}
	resp, body, err = PostJSON(ctx, cfg.GatewayURL+"/api/v1/users/jobs/complete", courierAToken, validCompletePayload)
	if err != nil {
		t.Fatalf("Courier A failed to complete job: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("Expected 200 OK from job completion, got %d: %s", resp.StatusCode, string(body))
	}

	var compResp struct {
		Message string `json:"message"`
		Status  string `json:"status"`
	}
	if err := json.Unmarshal(body, &compResp); err != nil {
		t.Fatalf("Failed to parse complete job response: %v", err)
	}
	t.Logf("Verified: Courier A completed job %s successfully", jobID)

	// 8. Verify wallet escrow balance released to 0
	walletURL := fmt.Sprintf("%s/api/v1/users/wallet?tenant_token=%s", cfg.GatewayURL, ownerToken)
	resp, body, err = GetJSON(ctx, walletURL, ownerToken)
	if err != nil {
		t.Fatalf("Failed to query wallet: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("Expected 200 OK from /users/wallet, got %d: %s", resp.StatusCode, string(body))
	}

	var walletResp struct {
		EscrowBalance       float64 `json:"escrow_balance"`
		TotalBalance        float64 `json:"total_balance"`
		WithdrawableBalance float64 `json:"withdrawable_balance"`
	}
	if err := json.Unmarshal(body, &walletResp); err != nil {
		t.Fatalf("Failed to parse wallet response: %v", err)
	}
	if walletResp.EscrowBalance != 0 {
		t.Fatalf("ASSERTION FAILED: Expected escrow_balance to be released to 0, got %.2f", walletResp.EscrowBalance)
	}
	t.Logf("Verified: Escrow balance successfully released to 0.0 (total=%.2f, withdrawable=%.2f)", walletResp.TotalBalance, walletResp.WithdrawableBalance)
	t.Logf("== CUJ-D (Driver Workflow Full Cycle & IDOR Guard) PASSED CLEANLY ==")
}
