package e2e

// ADR-0028 §5 Task 2: end-to-end Job Model v2 walkthrough against the live
// staging stack (gateway -> user-service). Covers booking with the new v2
// booking fields, PickupJob CAS + cross-field phone-window open/close
// against the filled status_history.
import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strings"
	"testing"
	"time"

	"go.mongodb.org/mongo-driver/v2/bson"
)

// v2CourierPhone(ts) is derived per run so the auth-db unique phone index
// never collides with leftovers from earlier runs.
func v2CourierPhone(ts int64) string {
	return fmt.Sprintf("+2010999%06d", ts%1000000)
}

func TestE2E_JobModelV2_CODPickupAndPhoneWindow(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
	defer cancel()

	cfg := LoadConfig()
	db, err := ConnectStagingDB(ctx, cfg.MongoURI)
	if err != nil {
		t.Fatalf("Failed to connect to staging DB: %v", err)
	}
	defer db.Close(ctx)

	ts := time.Now().UnixNano()
	testTenantID := fmt.Sprintf("tenant_v2_%d", ts)
	// In Quick Delivery architecture, owner user ID is tenant ID
	testOwnerID := testTenantID
	testOwnerEmail := fmt.Sprintf("owner_%d@v2.test", ts)
	testServiceID := fmt.Sprintf("svc_v2_%d", ts)

	testCourierID := fmt.Sprintf("cour_v2_%d", ts)
	testCourierEmail := fmt.Sprintf("cour_%d@v2.test", ts)
	testCustID := fmt.Sprintf("cust_v2_%d", ts)
	testCustEmail := fmt.Sprintf("cust_%d@v2.test", ts)

	cleanupEntities := func() {
		if os.Getenv("E2E_NO_CLEANUP") != "" {
			return
		}
		db.CleanupTestEntities(ctx,
			[]string{testTenantID},
			[]string{testOwnerID, testCourierID, testCustID},
		)
		_ = FlushAllAuthRateLimits(ctx, cfg.RedisURI)
	}
	defer cleanupEntities()
	cleanupEntities()

	if err := db.SeedTenantAndService(ctx, testTenantID, testOwnerID, testServiceID, 25.0, 5.0, 30.0444, 31.2357); err != nil {
		t.Fatalf("Failed to seed tenant and service: %v", err)
	}
	if err := db.SeedCourier(ctx, testTenantID, testCourierID, testCourierEmail, 30.0450, 31.2360); err != nil {
		t.Fatalf("Failed to seed courier: %v", err)
	}
	// ADR-0028 §2.11: the courier-phone window is served through the
	// S2S auth lookup; SeedCourier does not populate the phone field.
	if _, err := db.client.Database("staging_auth_db").Collection("users").UpdateOne(
		ctx,
		bson.M{"_id": testCourierID},
		bson.M{"$set": bson.M{"phone": v2CourierPhone(ts)}},
	); err != nil {
		t.Fatalf("Failed to upsert courier phone: %v", err)
	}
	if err := db.SeedCustomer(ctx, testTenantID, testCustID, testCustEmail); err != nil {
		t.Fatalf("Failed to seed customer: %v", err)
	}

	custToken, err := cfg.GenerateJWT(testCustID, "user", testTenantID, testCustEmail)
	if err != nil {
		t.Fatalf("Failed to generate customer token: %v", err)
	}
	courierToken, err := cfg.GenerateJWT(testCourierID, "employee", testTenantID, testCourierEmail)
	if err != nil {
		t.Fatalf("Failed to generate courier token: %v", err)
	}
	ownerToken, err := cfg.GenerateJWT(testOwnerID, "owner", testTenantID, testOwnerEmail)
	if err != nil {
		t.Fatalf("Failed to generate owner token: %v", err)
	}

	// ---- 1. Book a COD delivery job with the v2 booking fields ----
	bookURL := fmt.Sprintf("%s/api/v1/users/jobs/track", cfg.GatewayURL)
	bookResp, bookBody, err := PostJSON(ctx, bookURL, custToken, map[string]any{
		"service_id":      testServiceID,
		"user_token":      custToken,
		"payment_method":  "cod",
		"location":        map[string]any{"latitude": 30.0444, "longitude": 31.2357, "address": "Giza, Dokki, Tahrir St"},
		"destination":     map[string]any{"latitude": 30.0500, "longitude": 31.2400, "address": "Giza, Mohandessin, A St"},
		"recipient":       map[string]any{"name": "Recipient Test", "phone": "+201000000000", "relationship_note": "neighbor"},
		"package_details": map[string]any{"notes": "fragile cupcake box"},
	})
	if err != nil {
		t.Fatalf("Booking request failed: %v", err)
	}
	if bookResp.StatusCode != http.StatusCreated {
		t.Fatalf("Expected 201 for v2 booking, got %d: %s", bookResp.StatusCode, string(bookBody))
	}

	var booked struct {
		Job struct {
			ID string `json:"id"`
		} `json:"job"`
	}
	if err := json.Unmarshal(bookBody, &booked); err != nil || booked.Job.ID == "" {
		t.Fatalf("Failed to parse booked job response: %v (%s)", err, string(bookBody))
	}
	jobID := booked.Job.ID

	getURL := func(token string) string {
		return fmt.Sprintf("%s/api/v1/users/jobs/get?id=%s&requester_token=%s", cfg.GatewayURL, jobID, token)
	}
	type v2Job struct {
		Status    string `json:"status"`
		Recipient struct {
			Name  string `json:"name"`
			Phone string `json:"phone"`
		} `json:"recipient"`
		Pkg struct {
			Notes string `json:"notes"`
		} `json:"package_details"`
		Location struct {
			Latitude  float64 `json:"latitude"`
			Longitude float64 `json:"longitude"`
			Address   string  `json:"address"`
		} `json:"location"`
		Destination struct {
			Latitude  float64 `json:"latitude"`
			Longitude float64 `json:"longitude"`
			Address   string  `json:"address"`
		} `json:"destination"`
		CourierPhone  string `json:"courier_phone"`
		StatusHistory []struct {
			Status    string `json:"status"`
			ActorRole string `json:"actor_role"`
			ActorID   string `json:"actor_id"`
			SubStatus string `json:"sub_status"`
		} `json:"status_history"`
	}
	var jobDoc v2Job
	getJob := func(t *testing.T, token string) v2Job {
		t.Helper()
		resp, body, err := GetJSON(ctx, getURL(token), token)
		if err != nil {
			t.Fatalf("GET /users/jobs/get failed: %v", err)
		}
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("GET /users/jobs/get expected 200, got %d: %s", resp.StatusCode, string(body))
		}
		if os.Getenv("E2E_DEBUG") != "" {
			t.Logf("GET body: %s", body)
		}
		// GetJob returns the DTO at the top level (no "job" envelope).
		var v v2Job
		if err := json.Unmarshal(body, &v); err != nil {
			t.Fatalf("Failed to parse job DTO: %v (%s)", err, string(body))
		}
		return v
	}

	// V2 fields round-tripped at booking time.
	jobDoc = getJob(t, custToken)
	if jobDoc.Recipient.Name != "Recipient Test" || jobDoc.Recipient.Phone != "+201000000000" {
		t.Fatalf("Recipient not round-tripped: %+v", jobDoc.Recipient)
	}
	if jobDoc.Pkg.Notes != "fragile cupcake box" {
		t.Fatalf("package_details.notes mismatch: %q", jobDoc.Pkg.Notes)
	}
	if jobDoc.Location.Address != "Giza, Dokki, Tahrir St" || jobDoc.Destination.Address != "Giza, Mohandessin, A St" {
		t.Fatalf("address snapshot mismatch: up=%q down=%q", jobDoc.Location.Address, jobDoc.Destination.Address)
	}
	// ADR-0028 §2.6: booking opens the history with a real customer event.
	if len(jobDoc.StatusHistory) == 0 {
		t.Fatalf("status_history missing at booking")
	}
	first := jobDoc.StatusHistory[0]
	if first.Status != "pending_dispatch" || first.ActorRole != "customer" {
		t.Fatalf("first history entry wrong: %+v", first)
	}
	if len(strings.TrimSpace(jobDoc.CourierPhone)) != 0 {
		t.Fatalf("courier_phone must be closed before any courier assignment")
	}

	// ---- 2. Assistant accept-equivalent: assign the courier (accept window) ----
	// Mirrors accept semantics (delivery flow) pending_dispatch -> active +
	// heading_to_pickup, the courier-phone window opens.
	if _, err := db.client.Database("staging_user_db").Collection("jobs").UpdateOne(
		ctx,
		bson.M{"_id": jobID},
		bson.M{"$set": bson.M{
			"employee_id":                testCourierID,
			"status":                     "active",
			"sub_status":                 "heading_to_pickup",
			"estimated_duration_minutes": 15,
		}},
	); err != nil {
		t.Fatalf("Failed to activate job: %v", err)
	}

	jobDoc = getJob(t, ownerToken)
	if jobDoc.Status != "active" {
		t.Fatalf("expected active after courier assignment, got %q", jobDoc.Status)
	}
	if len(jobDoc.StatusHistory) < 1 {
		t.Fatalf("status_history must survive activation")
	}
	if jobDoc.CourierPhone != v2CourierPhone(ts) {
		t.Fatalf("courier_phone window must open while active: %q", jobDoc.CourierPhone)
	}

	// ---- 3. POST /users/jobs/pickup: courier flips to picked_up atomically ----
	pickURL := fmt.Sprintf("%s/api/v1/users/jobs/pickup", cfg.GatewayURL)
	pickResp, pickBody, err := PostJSON(ctx, pickURL, courierToken, map[string]any{
		"job_id":          jobID,
		"requester_token": courierToken,
	})
	if err != nil {
		t.Fatalf("Pickup request failed: %v", err)
	}
	if pickResp.StatusCode != http.StatusOK {
		t.Fatalf("Expected 200 for pickup, got %d: %s", pickResp.StatusCode, string(pickBody))
	}

	// Double pickup: CAS must reject with recognised access-denied shape,
	// not 409.
	pickResp2, pickBody2, err := PostJSON(ctx, pickURL, courierToken, map[string]any{
		"job_id":          jobID,
		"requester_token": courierToken,
	})
	if err != nil {
		t.Fatalf("Second pickup request failed: %v", err)
	}
	if pickResp2.StatusCode != http.StatusConflict {
		t.Fatalf("Expected 409 for double pickup, got %d: %s", pickResp2.StatusCode, string(pickBody2))
	}

	// The pickup event is the new history tail and sub_status column.
	jobDoc = getJob(t, custToken)
	pickupIdx := -1
	for i, e := range jobDoc.StatusHistory {
		if e.SubStatus == "picked_up" {
			pickupIdx = i
		}
	}
	if pickupIdx < 0 {
		t.Fatalf("pickup event missing from status_history: %+v", jobDoc.StatusHistory)
	}
	pu := jobDoc.StatusHistory[pickupIdx]
	// ADR-0028: entries carry the top-level STATUS; the sub_status column
	// (and entry.sub_status) records the pickup phase.
	if pu.Status != "active" || pu.SubStatus != "picked_up" || pu.ActorRole != "employee" || pu.ActorID != testCourierID {
		t.Fatalf("pickup history entry wrong: %+v", pu)
	}
	if jobDoc.CourierPhone != v2CourierPhone(ts) {
		t.Fatalf("courier_phone window must remain open post-pickup")
	}

	// ---- 4. Completion closes the window and keeps the ledger ----
	if _, err := db.client.Database("staging_user_db").Collection("jobs").UpdateOne(
		ctx,
		bson.M{"_id": jobID},
		bson.M{"$set": bson.M{
			"status":             "completed",
			"sub_status":         "",
			"actual_cash_amount": 0.0,
		}},
	); err != nil {
		t.Fatalf("Failed to complete job: %v", err)
	}
	jobDoc = getJob(t, custToken)
	if jobDoc.Status != "completed" {
		t.Fatalf("expected completed, got %q", jobDoc.Status)
	}
	if len(jobDoc.StatusHistory) == 0 || jobDoc.StatusHistory[0].Status != "pending_dispatch" {
		t.Fatalf("history ledger must survive completion (ADR-0028 §2.6)")
	}
	if len(strings.TrimSpace(jobDoc.CourierPhone)) != 0 {
		t.Fatalf("courier_phone window must close on completion")
	}
}
