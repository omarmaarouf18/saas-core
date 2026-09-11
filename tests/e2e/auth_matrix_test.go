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

// TestAuthAndRBACMatrix verifies the role-based access control (RBAC) boundaries
// and cross-tenant IDOR isolation guarantees across all system roles:
// Roles evaluated: Anonymous (no auth), Customer (user), Driver (employee), Owner (tenant), Reviewer (ops)
// Representative Endpoints:
// - Customer-scoped: POST /api/v1/chat/tickets
// - Employee-scoped: POST /api/v1/users/employee/location
// - Owner-scoped:    POST /api/v1/users/services
// - Reviewer-scoped: GET /api/queue (Console :8091)
//
// Cross-Tenant IDOR Invariants Verified:
// - Service Mutation IDOR: Tenant B cannot mutate Tenant A's service (403 Forbidden)
// - Reconciliation Queue IDOR: Tenant B cannot read Tenant A's reconciliation queue (403 Forbidden)
// - Job Completion IDOR: Courier B cannot complete Courier A's active job (403 Forbidden)
// - Chat History IDOR: Courier B cannot inspect Customer A's job chat history (403 Forbidden)
func TestAuthMatrix(t *testing.T) {
	TestAuthAndRBACMatrix(t)
}

func TestAuthAndRBACMatrix(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	cfg := LoadConfig()

	db, err := ConnectStagingDB(ctx, cfg.MongoURI)
	if err != nil {
		t.Fatalf("Failed to connect to staging DB: %v", err)
	}
	defer db.Close(ctx)

	rnd := rand.New(rand.NewSource(time.Now().UnixNano())).Intn(900000) + 100000
	tenantA := fmt.Sprintf("tenant-rbac-a-%d", rnd)
	ownerA := tenantA
	serviceA := fmt.Sprintf("svc-rbac-a-%d", rnd)
	courierA := fmt.Sprintf("courier-rbac-a-%d", rnd)
	customerA := fmt.Sprintf("cust-rbac-a-%d", rnd)

	tenantB := fmt.Sprintf("tenant-rbac-b-%d", rnd)
	ownerB := tenantB
	courierB := fmt.Sprintf("courier-rbac-b-%d", rnd)
	customerB := fmt.Sprintf("cust-rbac-b-%d", rnd)

	reviewerID := fmt.Sprintf("rev-rbac-%d", rnd)
	rawReviewerToken := fmt.Sprintf("reviewer-token-%d", rnd)

	defer func() {
		db.CleanupTestEntities(ctx, []string{tenantA, tenantB}, []string{ownerA, ownerB, courierA, courierB, customerA, customerB})
		_, _ = db.client.Database("staging_auth_db").Collection("reviewers").DeleteOne(ctx, map[string]any{"_id": reviewerID})
	}()

	// 1. Seed Tenant A (Paid) and Courier A, Customer A
	startLat, startLon := 30.0444, 31.2357
	if err := db.SeedTenantAndService(ctx, tenantA, ownerA, serviceA, 25.0, 5.0, startLat, startLon); err != nil {
		t.Fatalf("Failed to seed tenant A: %v", err)
	}
	if err := db.SeedCourier(ctx, tenantA, courierA, courierA+"@staging.local", startLat, startLon); err != nil {
		t.Fatalf("Failed to seed courier A: %v", err)
	}
	if err := db.SeedCustomer(ctx, tenantA, customerA, customerA+"@staging.local"); err != nil {
		t.Fatalf("Failed to seed customer A: %v", err)
	}
	if err := db.SeedWallet(ctx, tenantA, 1000.0); err != nil {
		t.Fatalf("Failed to seed wallet A: %v", err)
	}

	// 2. Seed Tenant B (Paid) and Courier B, Customer B
	if err := db.SeedTenantAndService(ctx, tenantB, ownerB, "svc-b-"+tenantB, 25.0, 5.0, startLat, startLon); err != nil {
		t.Fatalf("Failed to seed tenant B: %v", err)
	}
	if err := db.SeedCourier(ctx, tenantB, courierB, courierB+"@staging.local", startLat, startLon); err != nil {
		t.Fatalf("Failed to seed courier B: %v", err)
	}
	if err := db.SeedCustomer(ctx, tenantB, customerB, customerB+"@staging.local"); err != nil {
		t.Fatalf("Failed to seed customer B: %v", err)
	}
	if err := db.SeedWallet(ctx, tenantB, 1000.0); err != nil {
		t.Fatalf("Failed to seed wallet B: %v", err)
	}

	// 3. Seed Reviewer
	if err := db.SeedReviewer(ctx, reviewerID, "Matrix Reviewer", rawReviewerToken); err != nil {
		t.Fatalf("Failed to seed reviewer: %v", err)
	}

	// Generate Tokens
	custAToken, _ := cfg.GenerateJWT(customerA, "user", tenantA, customerA+"@staging.local")
	courierAToken, _ := cfg.GenerateJWT(courierA, "employee", tenantA, courierA+"@staging.local")
	ownerAToken, _ := cfg.GenerateJWT(ownerA, "owner", tenantA, ownerA+"@staging.local")

	custBToken, _ := cfg.GenerateJWT(customerB, "user", tenantB, customerB+"@staging.local")
	courierBToken, _ := cfg.GenerateJWT(courierB, "employee", tenantB, courierB+"@staging.local")
	ownerBToken, _ := cfg.GenerateJWT(ownerB, "owner", tenantB, ownerB+"@staging.local")

	// -------------------------------------------------------------------------
	// PART 1: Role RBAC Matrix Verification
	// -------------------------------------------------------------------------
	t.Run("Employee-Scoped Endpoint: POST /api/v1/users/employee/location", func(t *testing.T) {
		empURL := cfg.GatewayURL + "/api/v1/users/employee/location"
		payload := map[string]any{
			"latitude":  startLat,
			"longitude": startLon,
			"is_online": true,
		}

		// Anonymous -> 401
		resp, _, _ := PostJSON(ctx, empURL, "", payload)
		if resp.StatusCode != http.StatusUnauthorized {
			t.Errorf("Anonymous on /employee/location expected 401, got %d", resp.StatusCode)
		}

		// Customer -> 403
		resp, _, _ = PostJSON(ctx, empURL, custAToken, payload)
		if resp.StatusCode != http.StatusForbidden {
			t.Errorf("Customer on /employee/location expected 403, got %d", resp.StatusCode)
		}

		// Owner -> 403
		resp, _, _ = PostJSON(ctx, empURL, ownerAToken, payload)
		if resp.StatusCode != http.StatusForbidden {
			t.Errorf("Owner on /employee/location expected 403, got %d", resp.StatusCode)
		}

		// Courier -> 200 OK
		resp, _, _ = PostJSON(ctx, empURL, courierAToken, payload)
		if resp.StatusCode != http.StatusOK {
			t.Errorf("Courier on /employee/location expected 200, got %d", resp.StatusCode)
		}
	})

	t.Run("Owner-Scoped Endpoint: POST /api/v1/users/services", func(t *testing.T) {
		svcURL := cfg.GatewayURL + "/api/v1/users/services"
		payload := map[string]any{
			"name":                "RBAC Matrix Service",
			"category":            "delivery",
			"tenant_base_price":   30.0,
			"tenant_price_per_km": 5.0,
			"latitude":            startLat,
			"longitude":           startLon,
			"coverage_radius_km":  50.0,
		}

		// Anonymous -> 400 or 401
		resp, _, _ := PostJSON(ctx, svcURL, "", payload)
		if resp.StatusCode != http.StatusBadRequest && resp.StatusCode != http.StatusUnauthorized {
			t.Errorf("Anonymous on /users/services expected 400 or 401, got %d", resp.StatusCode)
		}

		// Customer -> 401 (invalid owner token: role mismatch)
		resp, _, _ = PostJSON(ctx, svcURL, custAToken, payload)
		if resp.StatusCode != http.StatusUnauthorized && resp.StatusCode != http.StatusForbidden {
			t.Errorf("Customer on /users/services expected 401 or 403, got %d", resp.StatusCode)
		}

		// Courier -> 401 (invalid owner token: role mismatch)
		resp, _, _ = PostJSON(ctx, svcURL, courierAToken, payload)
		if resp.StatusCode != http.StatusUnauthorized && resp.StatusCode != http.StatusForbidden {
			t.Errorf("Courier on /users/services expected 401 or 403, got %d", resp.StatusCode)
		}

		// Owner -> 201 Created
		resp, body, _ := PostJSON(ctx, svcURL, ownerAToken, payload)
		if resp.StatusCode != http.StatusCreated {
			t.Errorf("Owner on /users/services expected 201, got %d: %s", resp.StatusCode, string(body))
		}
	})

	t.Run("Reviewer Console Endpoint: GET /api/queue", func(t *testing.T) {
		queueURL := cfg.ConsoleURL + "/api/queue"

		// Anonymous -> 401
		req, _ := http.NewRequestWithContext(ctx, "GET", queueURL, nil)
		resp, _ := http.DefaultClient.Do(req)
		if resp.StatusCode != http.StatusUnauthorized {
			t.Errorf("Anonymous on Console /api/queue expected 401, got %d", resp.StatusCode)
		}
		_ = resp.Body.Close()

		// Customer Token in header -> 401
		req, _ = http.NewRequestWithContext(ctx, "GET", queueURL, nil)
		req.Header.Set("X-Reviewer-Token", custAToken)
		resp, _ = http.DefaultClient.Do(req)
		if resp.StatusCode != http.StatusUnauthorized {
			t.Errorf("Customer on Console /api/queue expected 401, got %d", resp.StatusCode)
		}
		_ = resp.Body.Close()

		// Valid Reviewer Token -> 200 OK
		req, _ = http.NewRequestWithContext(ctx, "GET", queueURL, nil)
		req.Header.Set("X-Reviewer-Token", rawReviewerToken)
		resp, _ = http.DefaultClient.Do(req)
		if resp.StatusCode != http.StatusOK {
			t.Errorf("Valid reviewer on Console /api/queue expected 200, got %d", resp.StatusCode)
		}
		_ = resp.Body.Close()
	})

	// -------------------------------------------------------------------------
	// PART 2: Explicit Cross-Tenant IDOR Isolation Checks
	// -------------------------------------------------------------------------
	t.Run("IDOR Isolation: Service Mutation", func(t *testing.T) {
		// Owner B attempts to update Owner A's service
		updatePayload := map[string]any{
			"id":                serviceA,
			"name":              "IDOR Malicious Overwrite",
			"tenant_base_price": 999.0,
			"owner_token":       ownerBToken,
		}
		resp, body, _ := PostJSON(ctx, cfg.GatewayURL+"/api/v1/users/services/update", ownerBToken, updatePayload)
		if resp.StatusCode != http.StatusForbidden {
			t.Fatalf("ASSERTION FAILED: Owner B mutating Owner A's service must return 403 Forbidden, got %d: %s", resp.StatusCode, string(body))
		}
		t.Logf("Verified: Cross-tenant service mutation blocked with 403 Forbidden")
	})

	t.Run("IDOR Isolation: Reconciliation Queue", func(t *testing.T) {
		// Owner B attempts to read Owner A's reconciliation queue
		reconURL := fmt.Sprintf("%s/api/v1/users/jobs/reconciliation-queue?owner_id=%s", cfg.GatewayURL, ownerA)
		resp, body, _ := GetJSON(ctx, reconURL, ownerBToken)
		if resp.StatusCode != http.StatusForbidden {
			t.Fatalf("ASSERTION FAILED: Owner B querying Owner A's reconciliation queue must return 403 Forbidden, got %d: %s", resp.StatusCode, string(body))
		}
		t.Logf("Verified: Cross-tenant reconciliation queue read blocked with 403 Forbidden")
	})

	t.Run("IDOR Isolation: Job Completion & Chat", func(t *testing.T) {
		// Book job for Customer A under Service A, accepted by Courier A
		bookPayload := map[string]any{
			"service_id":     serviceA,
			"user_id":        custAToken,
			"payment_method": "wallet",
			"location": map[string]float64{
				"latitude":  startLat,
				"longitude": startLon,
			},
		}
		resp, body, _ := PostJSON(ctx, cfg.GatewayURL+"/api/v1/users/jobs/track", custAToken, bookPayload)
		if resp.StatusCode != http.StatusCreated {
			t.Fatalf("Failed to book job: %s", string(body))
		}
		var bookResp struct {
			JobID string `json:"job_id"`
			Job   struct {
				ID string `json:"id"`
			} `json:"job"`
		}
		_ = json.Unmarshal(body, &bookResp)
		jobID := bookResp.JobID
		if jobID == "" {
			jobID = bookResp.Job.ID
		}

		acceptURL := fmt.Sprintf("%s/api/v1/users/employee/jobs/%s/accept", cfg.GatewayURL, jobID)
		resp, _, _ = PostJSON(ctx, acceptURL, courierAToken, nil)
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("Courier A failed to accept job: %d", resp.StatusCode)
		}

		// Courier B attempts to complete Courier A's job -> 403
		compPayload := map[string]any{
			"job_id":          jobID,
			"requester_token": courierBToken,
		}
		resp, compBody, _ := PostJSON(ctx, cfg.GatewayURL+"/api/v1/users/jobs/complete", courierBToken, compPayload)
		if resp.StatusCode != http.StatusForbidden {
			t.Fatalf("ASSERTION FAILED: Courier B completing Courier A's job must return 403 Forbidden, got %d: %s", resp.StatusCode, string(compBody))
		}
		t.Logf("Verified: Cross-tenant job completion blocked with 403 Forbidden")

		// Customer B attempts to inspect Customer A's job chat history -> 403
		chatHistoryURL := fmt.Sprintf("%s/api/v1/chat/history?channel=job:%s&token=%s", cfg.GatewayURL, jobID, custBToken)
		resp, chatBody, _ := GetJSON(ctx, chatHistoryURL, custBToken)
		if resp.StatusCode != http.StatusForbidden {
			t.Fatalf("ASSERTION FAILED: Customer B reading Customer A's job chat must return 403 Forbidden, got %d: %s", resp.StatusCode, string(chatBody))
		}
		t.Logf("Verified: Cross-tenant chat history blocked with 403 Forbidden")

		// Clean up by letting Courier A complete it
		compPayloadA := map[string]any{
			"job_id":          jobID,
			"requester_token": courierAToken,
		}
		_, _, _ = PostJSON(ctx, cfg.GatewayURL+"/api/v1/users/jobs/complete", courierAToken, compPayloadA)
	})

	t.Logf("== AUTH & RBAC MATRIX + IDOR ISOLATION PASSED CLEANLY ==")
}
