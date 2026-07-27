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

	"github.com/project/shared/infra/jwtutil"

	"github.com/project/user-service/internal/config"
	"github.com/project/user-service/internal/models"
	"github.com/project/user-service/internal/store"
	"github.com/redis/go-redis/v9"
)

func TestADR0007_E2E_DeliveryGPSReconciliation(t *testing.T) {
	jwtSecret := "NrrYbDqT4bRD/ADvJ5U2VKmLqXr8nk21IRVAbrzVI1mqEhuMhII3IO26PPa4qJtR"
	os.Setenv("JWT_SECRET", jwtSecret)

	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	dbName := fmt.Sprintf("saas_platform_e2e_adr0007_%d", time.Now().UnixNano())
	s, err := store.NewMongoDB(ctx, mongoURI, dbName)
	if err != nil {
		t.Skipf("Skipping E2E test: MongoDB not available at %s (%v)", mongoURI, err)
		return
	}
	defer func() {
		_ = s.DropDatabase(context.Background())
		s.Close(context.Background())
	}()

	ownerID := "owner-e2e-adr0007"
	empID := "emp-e2e-adr0007"
	custID := "cust-e2e-adr0007"

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
				"is_active": true,
				"tenant_id": ownerID,
			})
			return
		}
		json.NewEncoder(w).Encode(map[string]any{
			"id":        id,
			"role":      "customer",
			"is_active": true,
			"tenant_id": id,
		})
	}))
	defer mockAuthServer.Close()

	redisURI := os.Getenv("REDIS_URI")
	var rdbOpts *redis.Options
	if redisURI != "" {
		if opts, err := redis.ParseURL(redisURI); err == nil {
			rdbOpts = opts
		}
	}
	if rdbOpts == nil {
		redisAddr := os.Getenv("REDIS_ADDR")
		if redisAddr == "" {
			redisAddr = "localhost:6379"
		}
		rdbOpts = &redis.Options{Addr: redisAddr}
	}
	rdb := redis.NewClient(rdbOpts)
	defer rdb.Close()

	pingCtx, pingCancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer pingCancel()
	if err := rdb.Ping(pingCtx).Err(); err != nil {
		t.Skipf("Skipping E2E test: Redis not reachable at %s (%v)", rdbOpts.Addr, err)
		return
	}

	cfg := &config.Config{
		AuthServiceURL:         mockAuthServer.URL,
		InternalServiceToken:   "test-internal-token",
		AppEnv:                 "test",
		AllowTestPaymentBypass: true,
	}
	u := NewUserService(s, cfg, rdb)

	tokenOwner, _ := jwtutil.GenerateToken(ownerID, "owner", ownerID, "owner@example.com")
	tokenEmp, _ := jwtutil.GenerateToken(empID, "employee", ownerID, "emp@example.com")
	tokenCust, _ := jwtutil.GenerateToken(custID, "customer", ownerID, "cust@example.com")

	// Seed active subscription for owner
	_ = s.UpsertSubscription(ctx, &models.Subscription{
		ID:        "sub-e2e-adr0007",
		TenantID:  ownerID,
		Tier:      models.PlanPaid,
		StartedAt: time.Now().UTC(),
		ExpiresAt: time.Now().UTC().Add(30 * 24 * time.Hour),
	})

	// Long Delivery Service: Base=$10, Rate=$2/km, Pickup at (30.9, 30.0) -> Booked distance ~100 km ($209.80)
	svcLongDelivery := &models.Service{
		ID:               "svc-e2e-deliv-long",
		TenantID:         ownerID,
		Name:             "Long Range Delivery",
		Category:         "delivery",
		TenantBasePrice:  10.0,
		TenantPricePerKM: 2.0,
		Latitude:         30.9,
		Longitude:        30.0,
	}
	s.CreateService(ctx, svcLongDelivery)

	// Standard Delivery Service: Base=$10, Rate=$2/km, Pickup at (30.1, 30.0) -> Booked distance ~11.1 km ($32.22)
	svcStdDelivery := &models.Service{
		ID:               "svc-e2e-deliv-std",
		TenantID:         ownerID,
		Name:             "Standard Delivery",
		Category:         "delivery",
		TenantBasePrice:  10.0,
		TenantPricePerKM: 2.0,
		Latitude:         30.1,
		Longitude:        30.0,
	}
	s.CreateService(ctx, svcStdDelivery)

	var reqCounter int
	nextIP := func() string {
		reqCounter++
		return fmt.Sprintf("192.168.210.%d", reqCounter)
	}

	// -------------------------------------------------------------------------
	// STEP 3: UNDER-DISTANCE RECONCILIATION REVIEW FLAG
	// -------------------------------------------------------------------------
	t.Run("E2E Step 3: Under-distance tracked waypoints (< 70% of booked) flags job for manual review", func(t *testing.T) {
		trackReq := map[string]any{
			"owner_id":       tokenOwner,
			"service_id":     svcLongDelivery.ID,
			"user_id":        tokenCust,
			"employee_id":    tokenEmp,
			"payment_method": "cod",
			"location":       models.Location{Latitude: 30.0, Longitude: 30.0},
		}
		body, _ := json.Marshal(trackReq)
		req := httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(body))
		req.Header.Set("X-Real-IP", nextIP())
		rec := httptest.NewRecorder()
		u.TrackJob(rec, req)

		if rec.Code != http.StatusCreated {
			t.Fatalf("Expected 201 Created on TrackJob Step 3, got %d: %s", rec.Code, rec.Body.String())
		}
		var trackResp map[string]any
		json.Unmarshal(rec.Body.Bytes(), &trackResp)
		jobData, _ := trackResp["job"].(map[string]any)
		if jobData == nil {
			t.Fatalf("jobData is nil in TrackJob Step 3 response: %s", rec.Body.String())
		}
		jobID, _ := jobData["id"].(string)
		if jobID == "" {
			t.Fatalf("jobID is empty in TrackJob Step 3 response: %s", rec.Body.String())
		}

		// Simulate employee recording waypoints total ~5 km (far less than booked 100 km)
		_ = s.UpdateJobLocation(ctx, jobID, 30.045, 30.0)

		// Attempt CompleteJob
		compReq := map[string]any{
			"job_id":          jobID,
			"cash_collected":  true,
			"requester_token": tokenEmp,
		}
		body, _ = json.Marshal(compReq)
		req = httptest.NewRequest("POST", "/users/jobs/complete", bytes.NewReader(body))
		req.Header.Set("X-Real-IP", nextIP())
		rec = httptest.NewRecorder()
		u.CompleteJob(rec, req)

		t.Logf("[RAW RESPONSE CompleteJob Under-Distance]: status=%d body=%s", rec.Code, rec.Body.String())
		if rec.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK with reconciliation payload, got %d", rec.Code)
		}
		var compResp map[string]any
		json.Unmarshal(rec.Body.Bytes(), &compResp)

		if compResp["status"] != string(models.JobStatusEscrowReconciliationRequired) {
			t.Errorf("Expected status %s, got %v", models.JobStatusEscrowReconciliationRequired, compResp["status"])
		}
		note, _ := compResp["reconciliation_note"].(string)
		if !strings.Contains(note, "tracked_distance_mismatch") {
			t.Errorf("Expected note to contain 'tracked_distance_mismatch', got %q", note)
		}

		// Confirm DB status is escrow_reconciliation_required (not auto-completed)
		dbJob := s.GetJob(ctx, jobID)
		if dbJob == nil {
			t.Fatalf("dbJob is nil for jobID %s in Step 3", jobID)
		}
		if dbJob.Status != models.JobStatusEscrowReconciliationRequired {
			t.Errorf("Expected DB job status escrow_reconciliation_required, got %s", dbJob.Status)
		}
	})

	// -------------------------------------------------------------------------
	// STEP 4: OVER-DISTANCE LEGITIMATE DETOUR & GUARANTEED FLOOR + ESCROW CAP
	// -------------------------------------------------------------------------
	t.Run("E2E Step 4: Over-distance detour applies guaranteed floor and non-COD escrow cap", func(t *testing.T) {
		// Deposit $100 in owner wallet
		_ = s.Deposit(ctx, ownerID, 100.0)

		tokenCust2, _ := jwtutil.GenerateToken("cust2-adr0007", "customer", ownerID, "cust2@example.com")
		trackReq := map[string]any{
			"owner_id":       tokenOwner,
			"service_id":     svcStdDelivery.ID,
			"user_id":        tokenCust2,
			"employee_id":    tokenEmp,
			"payment_method": "wallet",
			"location":       models.Location{Latitude: 30.0, Longitude: 30.0},
		}
		body, _ := json.Marshal(trackReq)
		req := httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(body))
		req.Header.Set("X-Real-IP", nextIP())
		rec := httptest.NewRecorder()
		u.TrackJob(rec, req)

		if rec.Code != http.StatusCreated {
			t.Fatalf("Expected 201 Created on TrackJob Step 4, got %d: %s", rec.Code, rec.Body.String())
		}
		var trackResp map[string]any
		json.Unmarshal(rec.Body.Bytes(), &trackResp)
		jobData, _ := trackResp["job"].(map[string]any)
		if jobData == nil {
			t.Fatalf("jobData is nil in TrackJob Step 4 response: %s", rec.Body.String())
		}
		jobID, _ := jobData["id"].(string)
		if jobID == "" {
			t.Fatalf("jobID is empty in TrackJob Step 4 response: %s", rec.Body.String())
		}
		lockedEscrow, _ := jobData["locked_escrow_amount"].(float64)

		// Simulate driver taking a detour (waypoints adding ~27 km -> A_actual ~$65.60)
		_ = s.UpdateJobLocation(ctx, jobID, 30.15, 30.0)
		_ = s.UpdateJobLocation(ctx, jobID, 30.25, 30.0)

		// Complete job
		compReq := map[string]any{
			"job_id":          jobID,
			"requester_token": tokenEmp,
		}
		body, _ = json.Marshal(compReq)
		req = httptest.NewRequest("POST", "/users/jobs/complete", bytes.NewReader(body))
		req.Header.Set("X-Real-IP", nextIP())
		rec = httptest.NewRecorder()
		u.CompleteJob(rec, req)

		t.Logf("[RAW RESPONSE CompleteJob Over-Distance Escrow Cap]: status=%d body=%s", rec.Code, rec.Body.String())
		if rec.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK on complete job, got %d: %s", rec.Code, rec.Body.String())
		}
		var compResp map[string]any
		json.Unmarshal(rec.Body.Bytes(), &compResp)
		totalAmount, _ := compResp["total_amount"].(float64)

		// Payout MUST be capped at lockedEscrow ($32.22) for non-COD job
		if totalAmount != lockedEscrow {
			t.Errorf("Expected payout capped at locked escrow (%.2f), got %.2f", lockedEscrow, totalAmount)
		}
	})

	// -------------------------------------------------------------------------
	// STEP 5: GPS SPEED-PLAUSIBILITY CHECK (>150 KM/H REJECTION)
	// -------------------------------------------------------------------------
	t.Run("E2E Step 5: Speed check (>150km/h) rejects teleportation jumps", func(t *testing.T) {
		tokenCust3, _ := jwtutil.GenerateToken("cust3-adr0007", "customer", ownerID, "cust3@example.com")
		trackReq := map[string]any{
			"owner_id":       tokenOwner,
			"service_id":     svcStdDelivery.ID,
			"user_id":        tokenCust3,
			"employee_id":    tokenEmp,
			"payment_method": "cod",
			"location":       models.Location{Latitude: 30.0, Longitude: 30.0},
		}
		body, _ := json.Marshal(trackReq)
		req := httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(body))
		req.Header.Set("X-Real-IP", nextIP())
		rec := httptest.NewRecorder()
		u.TrackJob(rec, req)

		if rec.Code != http.StatusCreated {
			t.Fatalf("Expected 201 Created on TrackJob Step 5, got %d: %s", rec.Code, rec.Body.String())
		}
		var trackResp map[string]any
		json.Unmarshal(rec.Body.Bytes(), &trackResp)
		jobData, _ := trackResp["job"].(map[string]any)
		if jobData == nil {
			t.Fatalf("jobData is nil in TrackJob Step 5 response: %s", rec.Body.String())
		}
		jobID, _ := jobData["id"].(string)
		if jobID == "" {
			t.Fatalf("jobID is empty in TrackJob Step 5 response: %s", rec.Body.String())
		}

		// Submit instantaneous jump: (30.0, 30.0) -> (40.0, 40.0) = ~1400 km jump in 1 second
		locReq := map[string]any{
			"job_id":          jobID,
			"latitude":        40.0,
			"longitude":       40.0,
			"requester_token": tokenEmp,
		}
		body, _ = json.Marshal(locReq)
		req = httptest.NewRequest("POST", "/users/jobs/location", bytes.NewReader(body))
		req.Header.Set("X-Real-IP", nextIP())
		rec = httptest.NewRecorder()
		u.UpdateJobLocation(rec, req)

		t.Logf("[RAW RESPONSE UpdateJobLocation Teleportation Jump]: status=%d body=%s", rec.Code, rec.Body.String())
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("Expected 400 Bad Request on teleportation speed jump, got %d", rec.Code)
		}
		if !strings.Contains(rec.Body.String(), "speed") && !strings.Contains(rec.Body.String(), "implausible") {
			t.Errorf("Expected speed warning in response, got %s", rec.Body.String())
		}
	})
}
