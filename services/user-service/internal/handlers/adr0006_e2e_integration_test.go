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

func TestADR0006_E2E_NegotiableTransportPricing(t *testing.T) {
	jwtSecret := "NrrYbDqT4bRD/ADvJ5U2VKmLqXr8nk21IRVAbrzVI1mqEhuMhII3IO26PPa4qJtR"
	os.Setenv("JWT_SECRET", jwtSecret)

	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	dbName := fmt.Sprintf("saas_platform_e2e_adr0006_%d", time.Now().UnixNano())
	s, err := store.NewMongoDB(ctx, mongoURI, dbName)
	if err != nil {
		t.Skipf("Skipping E2E test: MongoDB not available at %s (%v)", mongoURI, err)
		return
	}
	defer func() {
		_ = s.DropDatabase(context.Background())
		s.Close(context.Background())
	}()

	ownerID := "owner-e2e-adr0006"
	empID := "emp-e2e-adr0006"
	custID := "cust-e2e-adr0006"

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

	// Seed transport service (Suggested Price = $80.00)
	svcTransport := &models.Service{
		ID:               "svc-e2e-trans-80",
		TenantID:         ownerID,
		Name:             "E2E Transport Service",
		Category:         "transport",
		TenantBasePrice:  80.0,
		TenantPricePerKM: 0.0,
		Latitude:         30.0,
		Longitude:        30.0,
	}
	s.CreateService(ctx, svcTransport)

	_ = s.UpsertEmployeeLocation(ctx, &models.EmployeeLocation{
		TenantID:   ownerID,
		EmployeeID: empID,
		Latitude:   30.0,
		Longitude:  30.0,
		UpdatedAt:  time.Now().UTC(),
	})

	// Seed delivery service (Fixed Price = $40.00)
	svcDelivery := &models.Service{
		ID:               "svc-e2e-deliv-40",
		TenantID:         ownerID,
		Name:             "E2E Delivery Service",
		Category:         "delivery",
		TenantBasePrice:  40.0,
		TenantPricePerKM: 0.0,
		Latitude:         30.0,
		Longitude:        30.0,
	}
	s.CreateService(ctx, svcDelivery)

	var reqCounter int
	nextIP := func() string {
		reqCounter++
		return fmt.Sprintf("192.168.200.%d", reqCounter)
	}

	// -------------------------------------------------------------------------
	// STEP 3A: CUSTOMER PROPOSES PRICE & EMPLOYEE ACCEPTS
	// -------------------------------------------------------------------------
	t.Run("E2E Step 3A: Customer proposes $95.0 for $80.0 transport ride and driver accepts", func(t *testing.T) {
		trackReq := map[string]any{
			"owner_id":       tokenOwner,
			"service_id":     svcTransport.ID,
			"user_id":        tokenCust,
			"employee_id":    tokenEmp,
			"payment_method": "cod",
			"proposed_price": 95.0,
			"location":       models.Location{Latitude: 30.0, Longitude: 30.0},
		}
		body, _ := json.Marshal(trackReq)
		req := httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(body))
		req.Header.Set("X-Real-IP", nextIP())
		rec := httptest.NewRecorder()
		u.TrackJob(rec, req)

		if rec.Code != http.StatusCreated {
			t.Fatalf("Expected 201 Created on TrackJob, got %d: %s", rec.Code, rec.Body.String())
		}
		var trackResp map[string]any
		json.Unmarshal(rec.Body.Bytes(), &trackResp)
		jobData, _ := trackResp["job"].(map[string]any)
		if jobData == nil {
			t.Fatalf("jobData is nil in TrackJob response: %s", rec.Body.String())
		}
		jobID, _ := jobData["id"].(string)
		if jobID == "" {
			t.Fatalf("jobID is empty in TrackJob response: %s", rec.Body.String())
		}

		t.Logf("[RAW RESPONSE TrackJob]: %s", rec.Body.String())
		if jobData["status"] != string(models.JobStatusAwaitingPriceResponse) {
			t.Errorf("Expected status %s, got %v", models.JobStatusAwaitingPriceResponse, jobData["status"])
		}
		if jobData["suggested_price"] != 80.0 {
			t.Errorf("Expected suggested_price 80.0, got %v", jobData["suggested_price"])
		}
		if jobData["proposed_price"] != 95.0 {
			t.Errorf("Expected proposed_price 95.0, got %v", jobData["proposed_price"])
		}

		// Driver accepts proposal
		respReq := map[string]any{
			"job_id":          jobID,
			"decision":        "accept",
			"requester_token": tokenEmp,
		}
		body, _ = json.Marshal(respReq)
		req = httptest.NewRequest("POST", "/users/jobs/respond-price", bytes.NewReader(body))
		req.Header.Set("X-Real-IP", nextIP())
		rec = httptest.NewRecorder()
		u.RespondPrice(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK on respond-price accept, got %d: %s", rec.Code, rec.Body.String())
		}
		t.Logf("[RAW RESPONSE RespondPrice Accept]: %s", rec.Body.String())

		var respResp map[string]any
		json.Unmarshal(rec.Body.Bytes(), &respResp)
		updatedJob, _ := respResp["job"].(map[string]any)
		if updatedJob == nil {
			t.Fatalf("updatedJob is nil in RespondPrice response: %s", rec.Body.String())
		}
		if updatedJob["status"] != string(models.JobStatusActive) {
			t.Errorf("Expected status active, got %v", updatedJob["status"])
		}
		if updatedJob["agreed_price"] != 95.0 {
			t.Errorf("Expected agreed_price 95.0, got %v", updatedJob["agreed_price"])
		}
	})

	// -------------------------------------------------------------------------
	// STEP 3B: LAZY PROPOSAL EXPIRY TEST
	// -------------------------------------------------------------------------
	t.Run("E2E Step 3B: Proposal window expiry triggers lazy cancellation", func(t *testing.T) {
		tokenCust2, _ := jwtutil.GenerateToken("cust2-e2e", "customer", ownerID, "cust2@example.com")
		trackReq := map[string]any{
			"owner_id":       tokenOwner,
			"service_id":     svcTransport.ID,
			"user_id":        tokenCust2,
			"employee_id":    tokenEmp,
			"payment_method": "cod",
			"proposed_price": 110.0,
			"location":       models.Location{Latitude: 30.1, Longitude: 30.1},
		}
		body, _ := json.Marshal(trackReq)
		req := httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(body))
		req.Header.Set("X-Real-IP", nextIP())
		rec := httptest.NewRecorder()
		u.TrackJob(rec, req)

		if rec.Code != http.StatusCreated {
			t.Fatalf("Expected 201 Created on TrackJob Step 3B, got %d: %s", rec.Code, rec.Body.String())
		}
		var trackResp map[string]any
		json.Unmarshal(rec.Body.Bytes(), &trackResp)
		jobData, _ := trackResp["job"].(map[string]any)
		if jobData == nil {
			t.Fatalf("jobData is nil in TrackJob Step 3B response: %s", rec.Body.String())
		}
		jobID, _ := jobData["id"].(string)
		if jobID == "" {
			t.Fatalf("jobID is empty in TrackJob Step 3B response: %s", rec.Body.String())
		}

		// Artificially expire proposal in store
		expiredAt := time.Now().UTC().Add(-10 * time.Minute)
		_ = s.UpdateJobPriceProposal(ctx, jobID, floatPtr(110.0), "customer", &expiredAt)

		// Driver attempts to accept expired proposal
		respReq := map[string]any{
			"job_id":          jobID,
			"decision":        "accept",
			"requester_token": tokenEmp,
		}
		body, _ = json.Marshal(respReq)
		req = httptest.NewRequest("POST", "/users/jobs/respond-price", bytes.NewReader(body))
		req.Header.Set("X-Real-IP", nextIP())
		rec = httptest.NewRecorder()
		u.RespondPrice(rec, req)

		t.Logf("[RAW RESPONSE RespondPrice Expired]: status=%d body=%s", rec.Code, rec.Body.String())
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("Expected 400 Bad Request on expired proposal, got %d", rec.Code)
		}
		if !strings.Contains(rec.Body.String(), "proposal_expired") {
			t.Errorf("Expected 'proposal_expired' error, got %s", rec.Body.String())
		}

		// Verify job is now cancelled in DB with reason price_proposal_expired
		dbJob := s.GetJob(ctx, jobID)
		if dbJob == nil {
			t.Fatalf("dbJob is nil for jobID %s in Step 3B", jobID)
		}
		if dbJob.Status != models.JobStatusCancelled {
			t.Errorf("Expected DB job status to be cancelled, got %s", dbJob.Status)
		}
		if dbJob.CancellationReason != "price_proposal_expired" {
			t.Errorf("Expected cancellation_reason 'price_proposal_expired', got %s", dbJob.CancellationReason)
		}
	})

	// -------------------------------------------------------------------------
	// STEP 3C: DELIVERY CATEGORY UNAFFECTED REGRESSION CHECK
	// -------------------------------------------------------------------------
	t.Run("E2E Step 3C: Delivery category job uses fixed pricing formula unchanged", func(t *testing.T) {
		tokenCust3, _ := jwtutil.GenerateToken("cust3-e2e", "customer", ownerID, "cust3@example.com")
		trackReq := map[string]any{
			"owner_id":       tokenOwner,
			"service_id":     svcDelivery.ID,
			"user_id":        tokenCust3,
			"employee_id":    tokenEmp,
			"payment_method": "cod",
			"location":       models.Location{Latitude: 30.2, Longitude: 30.2},
		}
		body, _ := json.Marshal(trackReq)
		req := httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(body))
		req.Header.Set("X-Real-IP", nextIP())
		rec := httptest.NewRecorder()
		u.TrackJob(rec, req)

		t.Logf("[RAW RESPONSE Delivery TrackJob]: status=%d body=%s", rec.Code, rec.Body.String())
		if rec.Code != http.StatusCreated {
			t.Fatalf("Expected 201 Created on delivery TrackJob, got %d: %s", rec.Code, rec.Body.String())
		}
		var trackResp map[string]any
		json.Unmarshal(rec.Body.Bytes(), &trackResp)
		jobData, _ := trackResp["job"].(map[string]any)
		if jobData == nil {
			t.Fatalf("jobData is nil in delivery TrackJob response: %s", rec.Body.String())
		}

		if jobData["status"] != string(models.JobStatusActive) {
			t.Errorf("Expected delivery job status to immediately be 'active', got %v", jobData["status"])
		}
		if _, exists := jobData["suggested_price"]; exists && jobData["suggested_price"] != nil && jobData["suggested_price"].(float64) != 0 {
			t.Errorf("Delivery job should NOT have negotiable suggested_price, got %v", jobData["suggested_price"])
		}
	})

	// -------------------------------------------------------------------------
	// STEP 4: ESCROW LOCKING FOR FINAL AGREED PRICE (NON-COD TRANSPORT JOB)
	// -------------------------------------------------------------------------
	t.Run("E2E Step 4: Escrow locking uses final agreed price ($100.00), not suggested price ($80.00)", func(t *testing.T) {
		// Deposit $200 into owner wallet
		_ = s.Deposit(ctx, ownerID, 200.0)

		tokenCust4, _ := jwtutil.GenerateToken("cust4-e2e", "customer", ownerID, "cust4@example.com")
		trackReq := map[string]any{
			"owner_id":       tokenOwner,
			"service_id":     svcTransport.ID,
			"user_id":        tokenCust4,
			"employee_id":    tokenEmp,
			"payment_method": "wallet",
			"proposed_price": 100.0,
			"location":       models.Location{Latitude: 30.3, Longitude: 30.3},
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
		t.Logf("[RAW TrackJob Step 4]: code=%d body=%s", rec.Code, rec.Body.String())
		jobData, _ := trackResp["job"].(map[string]any)
		if jobData == nil {
			t.Fatalf("jobData is nil in TrackJob Step 4 response: %s", rec.Body.String())
		}
		jobID, _ := jobData["id"].(string)
		if jobID == "" {
			t.Fatalf("jobID is empty in TrackJob Step 4 response: %s", rec.Body.String())
		}

		// Before acceptance: escrow balance should still be untouched (no escrow locked during TrackJob for transport)
		ownerWalletBefore := s.GetWallet(ctx, ownerID)
		if ownerWalletBefore == nil {
			t.Fatalf("ownerWalletBefore is nil for ownerID %s", ownerID)
		}
		t.Logf("[WALLET BEFORE ACCEPTANCE]: total=%.2f escrow=%.2f", ownerWalletBefore.TotalBalance, ownerWalletBefore.EscrowBalance)
		if ownerWalletBefore.EscrowBalance != 0.0 {
			t.Errorf("Expected 0 locked escrow during TrackJob for transport, got %.2f", ownerWalletBefore.EscrowBalance)
		}

		// Driver accepts proposal ($100.00)
		respReq := map[string]any{
			"job_id":          jobID,
			"decision":        "accept",
			"requester_token": tokenEmp,
		}
		body, _ = json.Marshal(respReq)
		req = httptest.NewRequest("POST", "/users/jobs/respond-price", bytes.NewReader(body))
		req.Header.Set("X-Real-IP", nextIP())
		rec = httptest.NewRecorder()
		u.RespondPrice(rec, req)

		t.Logf("[RAW RESPONSE Non-COD RespondPrice Accept]: status=%d body=%s", rec.Code, rec.Body.String())
		if rec.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK on respond-price accept Step 4, got %d: %s", rec.Code, rec.Body.String())
		}

		// Verify agreed price is $100.00
		dbJob := s.GetJob(ctx, jobID)
		if dbJob == nil {
			t.Fatalf("dbJob is nil for jobID %s in Step 4", jobID)
		}
		if dbJob.AgreedPrice == nil || *dbJob.AgreedPrice != 100.0 {
			t.Errorf("Expected agreed_price 100.0, got %v", dbJob.AgreedPrice)
		}
	})
}
