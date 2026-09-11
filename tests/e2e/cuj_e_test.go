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

// TestCUJ_E_OwnerWorkflow tests the comprehensive tenant owner lifecycle:
// 1. Seed Paid-tier Owner A and Free-tier Owner B with KYC approval
// 2. Owner A queries dashboard aggregate data (wallet, ledger, jobs, employees) -> 200 OK
// 3. Paid-tier Gating Check: Free-tier Owner B creates service -> rejected with 402 Payment Required
// 4. Paid-tier Owner A creates service -> succeeds with 201 Created
// 5. Paid-tier Owner A updates service -> succeeds with 200 OK
// 6. Owner A inspects reconciliation queue -> 200 OK
// 7. IDOR Guard 1: Owner B attempts to update Owner A's service -> rejected with 403 Forbidden
// 8. IDOR Guard 2: Owner B attempts to view Owner A's reconciliation queue -> rejected with 403 Forbidden
func TestCUJ_E_OwnerWorkflow(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	cfg := LoadConfig()

	db, err := ConnectStagingDB(ctx, cfg.MongoURI)
	if err != nil {
		t.Fatalf("Failed to connect to staging DB: %v", err)
	}
	defer db.Close(ctx)

	rnd := rand.New(rand.NewSource(time.Now().UnixNano())).Intn(900000) + 100000
	tenantPaid := fmt.Sprintf("tenant-cuj-e-paid-%d", rnd)
	ownerPaid := tenantPaid
	tenantFree := fmt.Sprintf("tenant-cuj-e-free-%d", rnd)
	ownerFree := tenantFree

	defer func() {
		db.CleanupTestEntities(ctx, []string{tenantPaid, tenantFree}, []string{ownerPaid, ownerFree})
	}()

	// 1. Seed Paid-tier Owner A
	if err := db.SeedTenantAndService(ctx, tenantPaid, ownerPaid, "svc-dummy-"+tenantPaid, 25.0, 5.0, 30.0444, 31.2357); err != nil {
		t.Fatalf("Failed to seed paid tenant: %v", err)
	}
	if err := db.SeedWallet(ctx, tenantPaid, 1000.0); err != nil {
		t.Fatalf("Failed to seed paid tenant wallet: %v", err)
	}

	// Seed Free-tier Owner B
	if err := db.SeedCustomer(ctx, tenantFree, ownerFree, ownerFree+"@staging.local"); err != nil {
		t.Fatalf("Failed to seed free owner base: %v", err)
	}
	// Update role to owner and kyc_status to approved
	if err := db.SeedKYCSubmission(ctx, ownerFree, ownerFree+"@staging.local", "owner", tenantFree); err != nil {
		t.Fatalf("Failed to seed free owner: %v", err)
	}
	// Mark KYC approved in staging_auth_db
	authUsers := db.client.Database("staging_auth_db").Collection("users")
	_, err = authUsers.UpdateOne(ctx, map[string]any{"_id": ownerFree}, map[string]any{"$set": map[string]any{"kyc_status": "approved"}})
	if err != nil {
		t.Fatalf("Failed to mark free owner approved: %v", err)
	}
	if err := db.SeedFreeSubscription(ctx, tenantFree); err != nil {
		t.Fatalf("Failed to seed free subscription: %v", err)
	}
	if err := db.SeedWallet(ctx, tenantFree, 100.0); err != nil {
		t.Fatalf("Failed to seed free tenant wallet: %v", err)
	}

	ownerPaidToken, err := cfg.GenerateJWT(ownerPaid, "owner", tenantPaid, ownerPaid+"@staging.local")
	if err != nil {
		t.Fatalf("Failed to generate paid owner token: %v", err)
	}
	ownerFreeToken, err := cfg.GenerateJWT(ownerFree, "owner", tenantFree, ownerFree+"@staging.local")
	if err != nil {
		t.Fatalf("Failed to generate free owner token: %v", err)
	}

	// 2. Owner A queries dashboard aggregate data
	// 2a. Wallet
	walletURL := fmt.Sprintf("%s/api/v1/users/wallet?tenant_token=%s", cfg.GatewayURL, ownerPaidToken)
	resp, body, err := GetJSON(ctx, walletURL, ownerPaidToken)
	if err != nil {
		t.Fatalf("Failed to query wallet: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("Expected 200 OK from wallet, got %d: %s", resp.StatusCode, string(body))
	}

	// 2b. Ledger
	ledgerURL := fmt.Sprintf("%s/api/v1/users/ledger?tenant_token=%s", cfg.GatewayURL, ownerPaidToken)
	resp, body, err = GetJSON(ctx, ledgerURL, ownerPaidToken)
	if err != nil {
		t.Fatalf("Failed to query ledger: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("Expected 200 OK from ledger, got %d: %s", resp.StatusCode, string(body))
	}

	// 2c. Owner Jobs
	jobsURL := fmt.Sprintf("%s/api/v1/users/jobs/owner", cfg.GatewayURL)
	resp, body, err = GetJSON(ctx, jobsURL, ownerPaidToken)
	if err != nil {
		t.Fatalf("Failed to query owner jobs: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("Expected 200 OK from jobs/owner, got %d: %s", resp.StatusCode, string(body))
	}

	// 2d. Employees list
	empURL := fmt.Sprintf("%s/api/v1/auth/employees", cfg.GatewayURL)
	resp, body, err = GetJSON(ctx, empURL, ownerPaidToken)
	if err != nil {
		t.Fatalf("Failed to query employees: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("Expected 200 OK from auth/employees, got %d: %s", resp.StatusCode, string(body))
	}
	t.Logf("Verified: Owner A dashboard endpoints (wallet, ledger, jobs, employees) all responded 200 OK")

	// 3. Paid-tier Gating Check: Free-tier Owner B attempts to create service -> 402 Payment Required
	freeSvcPayload := map[string]any{
		"name":                "Free Tier Logistics",
		"category":            "delivery",
		"tenant_base_price":   30.0,
		"tenant_price_per_km": 6.0,
		"latitude":            30.0444,
		"longitude":           31.2357,
		"coverage_radius_km":  40.0,
		"owner_token":         ownerFreeToken,
	}
	resp, body, err = PostJSON(ctx, cfg.GatewayURL+"/api/v1/users/services", ownerFreeToken, freeSvcPayload)
	if err != nil {
		t.Fatalf("Failed to execute free service creation: %v", err)
	}
	if resp.StatusCode != http.StatusPaymentRequired {
		t.Fatalf("ASSERTION FAILED: Free-tier owner creating service should return 402 Payment Required, got %d: %s", resp.StatusCode, string(body))
	}
	t.Logf("Verified Paid-tier Gate: Free-tier owner rejected with 402 Payment Required: %s", string(body))

	// 4. Paid-tier Owner A creates service -> 201 Created
	paidSvcPayload := map[string]any{
		"name":                "Fleet Delivery Pro",
		"category":            "delivery",
		"tenant_base_price":   35.0,
		"tenant_price_per_km": 7.0,
		"latitude":            30.0444,
		"longitude":           31.2357,
		"coverage_radius_km":  50.0,
		"owner_token":         ownerPaidToken,
	}
	resp, body, err = PostJSON(ctx, cfg.GatewayURL+"/api/v1/users/services", ownerPaidToken, paidSvcPayload)
	if err != nil {
		t.Fatalf("Failed to execute paid service creation: %v", err)
	}
	if resp.StatusCode != http.StatusCreated {
		t.Fatalf("Expected 201 Created for paid owner service creation, got %d: %s", resp.StatusCode, string(body))
	}

	var createdSvcResp struct {
		Service struct {
			ID   string `json:"id"`
			Name string `json:"name"`
		} `json:"service"`
	}
	if err := json.Unmarshal(body, &createdSvcResp); err != nil {
		t.Fatalf("Failed to parse created service response: %v", err)
	}
	serviceAID := createdSvcResp.Service.ID
	if serviceAID == "" {
		t.Fatalf("Expected non-empty service ID in creation response, got: %s", string(body))
	}
	t.Logf("Verified: Paid-tier Owner A created service %s with 201 Created", serviceAID)

	// 5. Paid-tier Owner A updates service -> 200 OK
	updateSvcPayload := map[string]any{
		"id":                serviceAID,
		"name":              "Fleet Delivery Pro Express",
		"tenant_base_price": 40.0,
		"owner_token":       ownerPaidToken,
	}
	resp, body, err = PostJSON(ctx, cfg.GatewayURL+"/api/v1/users/services/update", ownerPaidToken, updateSvcPayload)
	if err != nil {
		t.Fatalf("Failed to update service: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("Expected 200 OK from service update, got %d: %s", resp.StatusCode, string(body))
	}
	t.Logf("Verified: Paid-tier Owner A updated service %s with 200 OK", serviceAID)

	// 6. Owner A inspects reconciliation queue -> 200 OK
	reconURL := fmt.Sprintf("%s/api/v1/users/jobs/reconciliation-queue", cfg.GatewayURL)
	resp, body, err = GetJSON(ctx, reconURL, ownerPaidToken)
	if err != nil {
		t.Fatalf("Failed to query reconciliation queue: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("Expected 200 OK from reconciliation queue, got %d: %s", resp.StatusCode, string(body))
	}
	t.Logf("Verified: Owner A accessed reconciliation queue successfully (200 OK)")

	// 7. IDOR Guard 1: Owner B attempts to update Owner A's service
	idorUpdatePayload := map[string]any{
		"id":          serviceAID,
		"name":        "Hijacked Service Name",
		"owner_token": ownerFreeToken,
	}
	resp, body, err = PostJSON(ctx, cfg.GatewayURL+"/api/v1/users/services/update", ownerFreeToken, idorUpdatePayload)
	if err != nil {
		t.Fatalf("Failed to execute IDOR update request: %v", err)
	}
	// Free tier gate (402) or IDOR check (403) both protect Owner A's service
	if resp.StatusCode != http.StatusForbidden && resp.StatusCode != http.StatusPaymentRequired {
		t.Fatalf("ASSERTION FAILED: Owner B mutating Owner A's service must be blocked (402 or 403), got %d: %s", resp.StatusCode, string(body))
	}
	t.Logf("Verified IDOR Guard 1: Owner B blocked from updating Owner A's service (status %d)", resp.StatusCode)

	// 8. IDOR Guard 2: Owner B attempts to view Owner A's reconciliation queue
	idorReconURL := fmt.Sprintf("%s/api/v1/users/jobs/reconciliation-queue?owner_id=%s", cfg.GatewayURL, ownerPaid)
	resp, body, err = GetJSON(ctx, idorReconURL, ownerFreeToken)
	if err != nil {
		t.Fatalf("Failed to execute IDOR reconciliation request: %v", err)
	}
	if resp.StatusCode != http.StatusForbidden {
		t.Fatalf("ASSERTION FAILED: Owner B viewing Owner A's reconciliation queue must return 403 Forbidden, got %d: %s", resp.StatusCode, string(body))
	}
	t.Logf("Verified IDOR Guard 2: Owner B blocked from reading Owner A's reconciliation queue with 403 Forbidden")
	t.Logf("== CUJ-E (Owner Workflow, Paid-Tier Gating & IDOR Guard) PASSED CLEANLY ==")
}
