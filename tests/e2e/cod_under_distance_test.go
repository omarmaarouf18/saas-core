package e2e

import (
	"context"
	"encoding/json"
	"fmt"
	"math/rand"
	"net/http"
	"testing"
	"time"

	"go.mongodb.org/mongo-driver/v2/bson"
)

// TestCOD_UnderDistanceCompletion (FIX-COD-RECON) verifies through the
// gateway that a COD delivery whose tracked GPS trail is under 70 % of the
// booked distance still completes:
//  1. Seed tenant, delivery service, courier, customer and an active COD job
//     booked at ~100 km whose recorded trail is ~5 km.
//  2. Courier completes with cash_collected + actual_cash_amount -> 200,
//     cash recorded, distance_review in the response.
//  3. Owner GET /users/jobs/get -> status completed, actual_cash_amount and
//     distance_review present.
//  4. Owner GET /users/jobs/reconciliation-queue -> the job is NOT listed.
func TestCOD_UnderDistanceCompletion(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	cfg := LoadConfig()
	db, err := ConnectStagingDB(ctx, cfg.MongoURI)
	if err != nil {
		t.Fatalf("Failed to connect to staging DB: %v", err)
	}
	defer db.Close(ctx)

	rnd := rand.New(rand.NewSource(time.Now().UnixNano())).Intn(900000) + 100000
	tenantID := fmt.Sprintf("tenant-cod-recon-%d", rnd)
	ownerID := tenantID
	serviceID := fmt.Sprintf("svc-cod-recon-%d", rnd)
	courierID := fmt.Sprintf("courier-cod-recon-%d", rnd)
	customerID := fmt.Sprintf("cust-cod-recon-%d", rnd)
	jobID := fmt.Sprintf("job-cod-recon-%d", rnd)
	defer db.CleanupTestEntities(ctx, []string{tenantID}, []string{ownerID, courierID, customerID})

	// 1. Seed
	startLat, startLon := 30.0, 31.0
	if err := db.SeedTenantAndService(ctx, tenantID, ownerID, serviceID, 10.0, 2.0, startLat, startLon); err != nil {
		t.Fatalf("Failed to seed tenant and service: %v", err)
	}
	if err := db.SeedCourier(ctx, tenantID, courierID, courierID+"@staging.local", startLat, startLon); err != nil {
		t.Fatalf("Failed to seed courier: %v", err)
	}
	if err := db.SeedCustomer(ctx, tenantID, customerID, customerID+"@staging.local"); err != nil {
		t.Fatalf("Failed to seed customer: %v", err)
	}
	now := time.Now().UTC()
	if err := db.SeedJob(ctx, bson.M{
		"_id": jobID, "owner_id": ownerID, "employee_id": courierID, "user_id": customerID,
		"service_id": serviceID, "status": "active", "payment_method": "cod",
		"location":        bson.M{"latitude": startLat, "longitude": startLon},
		"destination":     bson.M{"latitude": startLat + 0.9, "longitude": startLon},
		"booked_distance": 100.0,
		"waypoints":       bson.A{bson.M{"latitude": startLat + 0.045, "longitude": startLon}},
		"created_at":      now.Add(-30 * time.Minute), "updated_at": now,
	}); err != nil {
		t.Fatalf("Failed to seed job: %v", err)
	}

	ownerToken, err := cfg.GenerateJWT(ownerID, "owner", tenantID, ownerID+"@staging.local")
	if err != nil {
		t.Fatalf("Failed to generate owner token: %v", err)
	}
	courierToken, err := cfg.GenerateJWT(courierID, "employee", tenantID, courierID+"@staging.local")
	if err != nil {
		t.Fatalf("Failed to generate courier token: %v", err)
	}

	// 2. Courier completes with cash collected
	resp, body, err := PostJSON(ctx, cfg.GatewayURL+"/api/v1/users/jobs/complete", courierToken, map[string]any{
		"job_id": jobID, "cash_collected": true, "actual_cash_amount": 150.0,
	})
	if err != nil {
		t.Fatalf("CompleteJob request failed: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("Expected 200 from COD completion, got %d: %s", resp.StatusCode, string(body))
	}
	var comp map[string]any
	if err := json.Unmarshal(body, &comp); err != nil {
		t.Fatalf("Failed to parse completion response: %v (%s)", err, string(body))
	}
	if comp["cash_amount_recorded"] != 150.0 {
		t.Errorf("ASSERTION FAILED: cash_amount_recorded = %v, want 150 (body %s)", comp["cash_amount_recorded"], string(body))
	}
	if _, ok := comp["distance_review"].(map[string]any); !ok {
		t.Errorf("ASSERTION FAILED: completion response lacks distance_review: %s", string(body))
	}

	// 3. Owner sees the completed job with cash and the review flag
	resp, body, err = GetJSON(ctx, fmt.Sprintf("%s/api/v1/users/jobs/get?id=%s", cfg.GatewayURL, jobID), ownerToken)
	if err != nil {
		t.Fatalf("GetJob request failed: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("Expected 200 from owner GetJob, got %d: %s", resp.StatusCode, string(body))
	}
	var job map[string]any
	if err := json.Unmarshal(body, &job); err != nil {
		t.Fatalf("Failed to parse job: %v (%s)", err, string(body))
	}
	if job["status"] != "completed" || job["actual_cash_amount"] != 150.0 {
		t.Errorf("ASSERTION FAILED: owner view status=%v actual_cash_amount=%v, want completed / 150", job["status"], job["actual_cash_amount"])
	}
	review, ok := job["distance_review"].(map[string]any)
	if !ok || review["booked_km"] != 100.0 {
		t.Errorf("ASSERTION FAILED: owner view distance_review = %v, want booked_km 100", job["distance_review"])
	}

	// 4. The job is not in the owner's escrow reconciliation queue
	resp, body, err = GetJSON(ctx, cfg.GatewayURL+"/api/v1/users/jobs/reconciliation-queue", ownerToken)
	if err != nil {
		t.Fatalf("Reconciliation queue request failed: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("Expected 200 from reconciliation queue, got %d: %s", resp.StatusCode, string(body))
	}
	var queue []map[string]any
	if err := json.Unmarshal(body, &queue); err != nil {
		t.Fatalf("Failed to parse reconciliation queue: %v (%s)", err, string(body))
	}
	for _, q := range queue {
		if q["id"] == jobID {
			t.Errorf("ASSERTION FAILED: COD job %s must not be in the escrow reconciliation queue", jobID)
		}
	}
}
