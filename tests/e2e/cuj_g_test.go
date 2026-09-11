package e2e

import (
	"context"
	"encoding/json"
	"fmt"
	"math/rand"
	"net/http"
	"strings"
	"testing"
	"time"
)

// TestCUJ_G_Rating tests the end-to-end rating lifecycle:
// 1. Seed tenant, owner, service, customer, and courier
// 2. Customer books job (job active/pending, not completed)
// 3. Negative 1: Rating uncompleted job rejected with 400 Bad Request
// 4. Negative 2: Rating with out-of-range stars (6 stars) rejected with 400 Bad Request
// 5. Negative 3: Rating with out-of-range stars (0 stars) rejected with 400 Bad Request
// 6. Negative 4: Non-participant rating rejected with 403 Forbidden
// 7. Complete job delivery through normal lifecycle
// 8. Submit double-blind rating (Owner rates Courier 5 stars) -> 201 Created
// 9. Negative 5: Duplicate rating submission rejected with 409 Conflict
// 10. Query aggregate ratings for courier -> total=1, average=5.0
func TestCUJ_G_Rating(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	cfg := LoadConfig()

	db, err := ConnectStagingDB(ctx, cfg.MongoURI)
	if err != nil {
		t.Fatalf("Failed to connect to staging DB: %v", err)
	}
	defer db.Close(ctx)

	rnd := rand.New(rand.NewSource(time.Now().UnixNano())).Intn(900000) + 100000
	tenantID := fmt.Sprintf("tenant-cuj-g-%d", rnd)
	ownerID := tenantID
	serviceID := fmt.Sprintf("svc-cuj-g-%d", rnd)
	courierID := fmt.Sprintf("courier-cuj-g-%d", rnd)
	unrelatedUserID := fmt.Sprintf("unrelated-cuj-g-%d", rnd)
	customerID := fmt.Sprintf("cust-cuj-g-%d", rnd)

	defer func() {
		db.CleanupTestEntities(ctx, []string{tenantID}, []string{ownerID, courierID, customerID, unrelatedUserID})
	}()

	startLat, startLon := 30.0444, 31.2357
	if err := db.SeedTenantAndService(ctx, tenantID, ownerID, serviceID, 20.0, 5.0, startLat, startLon); err != nil {
		t.Fatalf("Failed to seed tenant and service: %v", err)
	}
	if err := db.SeedCourier(ctx, tenantID, courierID, courierID+"@staging.local", startLat, startLon); err != nil {
		t.Fatalf("Failed to seed courier: %v", err)
	}
	if err := db.SeedCustomer(ctx, tenantID, customerID, customerID+"@staging.local"); err != nil {
		t.Fatalf("Failed to seed customer: %v", err)
	}
	if err := db.SeedCustomer(ctx, tenantID, unrelatedUserID, unrelatedUserID+"@staging.local"); err != nil {
		t.Fatalf("Failed to seed unrelated user: %v", err)
	}
	if err := db.SeedWallet(ctx, tenantID, 500.0); err != nil {
		t.Fatalf("Failed to seed wallet: %v", err)
	}

	ownerToken, err := cfg.GenerateJWT(ownerID, "owner", tenantID, ownerID+"@staging.local")
	if err != nil {
		t.Fatalf("Failed to generate owner token: %v", err)
	}
	courierToken, err := cfg.GenerateJWT(courierID, "employee", tenantID, courierID+"@staging.local")
	if err != nil {
		t.Fatalf("Failed to generate courier token: %v", err)
	}
	custToken, err := cfg.GenerateJWT(customerID, "user", tenantID, customerID+"@staging.local")
	if err != nil {
		t.Fatalf("Failed to generate customer token: %v", err)
	}
	unrelatedToken, err := cfg.GenerateJWT(unrelatedUserID, "user", tenantID, unrelatedUserID+"@staging.local")
	if err != nil {
		t.Fatalf("Failed to generate unrelated user token: %v", err)
	}

	// 2. Book job
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
	if err != nil || resp.StatusCode != http.StatusCreated {
		t.Fatalf("Failed to book job: %v, body: %s", err, string(body))
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

	// Accept job so employee is assigned
	acceptURL := fmt.Sprintf("%s/api/v1/users/employee/jobs/%s/accept", cfg.GatewayURL, jobID)
	resp, body, err = PostJSON(ctx, acceptURL, courierToken, nil)
	if err != nil || resp.StatusCode != http.StatusOK {
		t.Fatalf("Failed to accept job: %v, body: %s", err, string(body))
	}

	rateURL := cfg.GatewayURL + "/api/v1/users/jobs/rate"

	// 3. NEGATIVE: Rate uncompleted job -> 400 Bad Request
	uncompletedRatePayload := map[string]any{
		"job_id":         jobID,
		"rated_by_token": ownerToken,
		"rated_user":     courierID,
		"stars":          5,
		"comment":        "Great courier",
	}
	resp, body, err = PostJSON(ctx, rateURL, ownerToken, uncompletedRatePayload)
	if err != nil {
		t.Fatalf("Failed to send uncompleted rate request: %v", err)
	}
	if resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("Expected 400 Bad Request for uncompleted job rating, got %d: %s", resp.StatusCode, string(body))
	}
	if !strings.Contains(string(body), "cannot rate a job that is not completed") {
		t.Fatalf("Expected 'cannot rate a job that is not completed' in error, got: %s", string(body))
	}
	t.Logf("Verified Negative 1: Rating uncompleted job rejected with 400 Bad Request: %s", string(body))

	// 4. NEGATIVE: Out-of-range stars (6 stars)
	sixStarPayload := map[string]any{
		"job_id":         jobID,
		"rated_by_token": ownerToken,
		"rated_user":     courierID,
		"stars":          6,
	}
	resp, body, err = PostJSON(ctx, rateURL, ownerToken, sixStarPayload)
	if err != nil {
		t.Fatalf("Failed to send 6-star rate request: %v", err)
	}
	if resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("Expected 400 Bad Request for 6 stars, got %d: %s", resp.StatusCode, string(body))
	}
	t.Logf("Verified Negative 2: 6 stars rejected with 400 Bad Request: %s", string(body))

	// 5. NEGATIVE: Out-of-range stars (0 stars)
	zeroStarPayload := map[string]any{
		"job_id":         jobID,
		"rated_by_token": ownerToken,
		"rated_user":     courierID,
		"stars":          0,
	}
	resp, body, err = PostJSON(ctx, rateURL, ownerToken, zeroStarPayload)
	if err != nil {
		t.Fatalf("Failed to send 0-star rate request: %v", err)
	}
	if resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("Expected 400 Bad Request for 0 stars, got %d: %s", resp.StatusCode, string(body))
	}
	t.Logf("Verified Negative 3: 0 stars rejected with 400 Bad Request: %s", string(body))

	// 6. Complete job delivery
	locUpdateURL := cfg.GatewayURL + "/api/v1/users/jobs/location/update"
	locUpdate := map[string]any{
		"job_id":          jobID,
		"latitude":        startLat,
		"longitude":       startLon,
		"requester_token": courierToken,
	}
	_, _, _ = PostJSON(ctx, locUpdateURL, courierToken, locUpdate)

	completePayload := map[string]any{
		"job_id":          jobID,
		"requester_token": courierToken,
	}
	resp, body, err = PostJSON(ctx, cfg.GatewayURL+"/api/v1/users/jobs/complete", courierToken, completePayload)
	if err != nil || resp.StatusCode != http.StatusOK {
		t.Fatalf("Courier failed to complete job: %v, body: %s", err, string(body))
	}
	t.Logf("Job %s completed successfully", jobID)

	// 7. NEGATIVE: Non-participant rating -> 403 Forbidden
	nonParticipantPayload := map[string]any{
		"job_id":         jobID,
		"rated_by_token": unrelatedToken,
		"rated_user":     courierID,
		"stars":          5,
	}
	resp, body, err = PostJSON(ctx, rateURL, unrelatedToken, nonParticipantPayload)
	if err != nil {
		t.Fatalf("Failed to send non-participant rate request: %v", err)
	}
	if resp.StatusCode != http.StatusForbidden {
		t.Fatalf("Expected 403 Forbidden for non-participant rating, got %d: %s", resp.StatusCode, string(body))
	}
	t.Logf("Verified Negative 4: Non-participant rating rejected with 403 Forbidden: %s", string(body))

	// 8. HAPPY PATH: Double-blind rating (Owner rates Courier 5 stars)
	validRatingPayload := map[string]any{
		"job_id":         jobID,
		"rated_by_token": ownerToken,
		"rated_user":     courierID,
		"stars":          5,
		"comment":        "Excellent delivery speed and handling",
	}
	resp, body, err = PostJSON(ctx, rateURL, ownerToken, validRatingPayload)
	if err != nil {
		t.Fatalf("Failed to submit valid rating: %v", err)
	}
	if resp.StatusCode != http.StatusCreated {
		t.Fatalf("Expected 201 Created from valid rating, got %d: %s", resp.StatusCode, string(body))
	}
	t.Logf("Verified: Owner successfully submitted 5-star rating for Courier")

	// 9. NEGATIVE: Duplicate rating submission -> 409 Conflict
	resp, body, err = PostJSON(ctx, rateURL, ownerToken, validRatingPayload)
	if err != nil {
		t.Fatalf("Failed to submit duplicate rating: %v", err)
	}
	if resp.StatusCode != http.StatusConflict {
		t.Fatalf("Expected 409 Conflict for duplicate rating, got %d: %s", resp.StatusCode, string(body))
	}
	t.Logf("Verified Negative 5: Duplicate rating rejected with 409 Conflict: %s", string(body))

	// 10. Query aggregate ratings
	ratingsURL := fmt.Sprintf("%s/api/v1/users/ratings?user_id=%s", cfg.GatewayURL, courierID)
	resp, body, err = GetJSON(ctx, ratingsURL, ownerToken)
	if err != nil {
		t.Fatalf("Failed to query ratings: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("Expected 200 OK from /users/ratings, got %d: %s", resp.StatusCode, string(body))
	}

	var ratingsResp struct {
		UserID        string  `json:"user_id"`
		AverageRating float64 `json:"average_rating"`
		Count         int     `json:"count"`
	}
	if err := json.Unmarshal(body, &ratingsResp); err != nil {
		t.Fatalf("Failed to parse ratings response: %v", err)
	}
	if ratingsResp.Count != 1 || ratingsResp.AverageRating != 5.0 {
		t.Fatalf("ASSERTION FAILED: Expected total=1, avg=5.0, got total=%d, avg=%.2f", ratingsResp.Count, ratingsResp.AverageRating)
	}
	t.Logf("Verified: Aggregate ratings updated correctly: total=%d, avg=%.2f", ratingsResp.Count, ratingsResp.AverageRating)
	t.Logf("== CUJ-G (Double-Blind Rating, Validations & Aggregate Metrics) PASSED CLEANLY ==")
}
