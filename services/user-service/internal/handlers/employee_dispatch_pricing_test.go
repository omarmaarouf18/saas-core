package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"math"
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

func setupDispatchTestHarness(t *testing.T) (*UserService, *store.MongoDB, *redis.Client, func()) {
	t.Helper()
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	dbName := fmt.Sprintf("saas_platform_dispatch_test_%d", time.Now().UnixNano())
	s, err := store.NewMongoDB(ctx, "mongodb://root:devpassword123@localhost:27017/saas_platform?authSource=admin", dbName)
	if err != nil {
		cancel()
		t.Skipf("Skipping: MongoDB not available (%v)", err)
		return nil, nil, nil, nil
	}

	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})

	mockAuthServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		id := r.URL.Query().Get("id")
		role := "owner"
		tenantID := id
		isActive := !strings.Contains(id, "deactivated")

		if strings.Contains(id, "emp") {
			role = "employee"
			if strings.Contains(id, "-under-") {
				parts := strings.Split(id, "-under-")
				if len(parts) > 1 {
					tenantID = parts[1]
				}
			} else if strings.HasPrefix(id, "emp-") {
				tenantID = strings.TrimPrefix(id, "emp-")
			}
		} else if strings.Contains(id, "cust") || strings.Contains(id, "user") {
			role = "user"
		}

		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]any{
			"id":         id,
			"role":       role,
			"kyc_status": "approved",
			"is_active":  isActive,
			"tenant_id":  tenantID,
		})
	}))

	cfg := &config.Config{
		AuthServiceURL:         mockAuthServer.URL,
		InternalServiceToken:   "mock-internal-token",
		AppEnv:                 "test",
		AllowTestPaymentBypass: true,
	}
	u := NewUserService(s, cfg, rdb)
	cleanup := func() {
		mockAuthServer.Close()
		rdb.Close()
		_ = s.DropDatabase(context.Background())
		s.Close(context.Background())
		cancel()
	}
	return u, s, rdb, cleanup
}

// ---------------------------------------------------------------------------
// 1. Employee Standalone Location Ping Endpoint Tests
// ---------------------------------------------------------------------------

func TestUpdateEmployeeLocation_Endpoint(t *testing.T) {
	u, s, _, cleanup := setupDispatchTestHarness(t)
	if u == nil {
		return
	}
	defer cleanup()

	ownerID := "tenant-test-owner"
	empID := "emp-under-tenant-test-owner"
	custID := "cust-1"

	tokenEmp, _ := jwtutil.GenerateToken(empID, "employee", ownerID, "emp@test.com")
	tokenOwner, _ := jwtutil.GenerateToken(ownerID, "owner", ownerID, "owner@test.com")
	tokenCust, _ := jwtutil.GenerateToken(custID, "user", ownerID, "cust@test.com")

	t.Run("Non-employee caller is rejected with 403 Forbidden", func(t *testing.T) {
		body, _ := json.Marshal(models.EmployeeLocationPingRequest{
			RequesterToken: tokenCust,
			Latitude:       30.05,
			Longitude:      31.20,
		})
		req := httptest.NewRequest("POST", "/users/employee/location", bytes.NewReader(body))
		rec := httptest.NewRecorder()
		u.UpdateEmployeeLocation(rec, req)
		if rec.Code != http.StatusForbidden {
			t.Errorf("Expected 403 for user role pinging employee location, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		bodyOwner, _ := json.Marshal(models.EmployeeLocationPingRequest{
			RequesterToken: tokenOwner,
			Latitude:       30.05,
			Longitude:      31.20,
		})
		reqOwner := httptest.NewRequest("POST", "/users/employee/location", bytes.NewReader(bodyOwner))
		recOwner := httptest.NewRecorder()
		u.UpdateEmployeeLocation(recOwner, reqOwner)
		if recOwner.Code != http.StatusForbidden {
			t.Errorf("Expected 403 for owner role pinging employee location, got %d", recOwner.Code)
		}
	})

	t.Run("Invalid coordinates are rejected with 400 Bad Request", func(t *testing.T) {
		body, _ := json.Marshal(models.EmployeeLocationPingRequest{
			RequesterToken: tokenEmp,
			Latitude:       999.0,
			Longitude:      31.20,
		})
		req := httptest.NewRequest("POST", "/users/employee/location", bytes.NewReader(body))
		rec := httptest.NewRecorder()
		u.UpdateEmployeeLocation(rec, req)
		if rec.Code != http.StatusBadRequest {
			t.Errorf("Expected 400 for out-of-bounds coordinates, got %d", rec.Code)
		}
	})

	t.Run("Valid location ping persists to store and returns 200 OK", func(t *testing.T) {
		body, _ := json.Marshal(models.EmployeeLocationPingRequest{
			RequesterToken: tokenEmp,
			Latitude:       30.0500,
			Longitude:      31.2000,
		})
		req := httptest.NewRequest("POST", "/users/employee/location", bytes.NewReader(body))
		rec := httptest.NewRecorder()
		u.UpdateEmployeeLocation(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("Expected 200 for valid ping, got %d. Body: %s", rec.Code, rec.Body.String())
		}

		// Verify in MongoDB
		loc, err := s.GetEmployeeLocation(context.Background(), ownerID, empID)
		if err != nil || loc == nil {
			t.Fatalf("Expected location in DB, got err: %v, loc: %v", err, loc)
		}
		if loc.Latitude != 30.0500 || loc.Longitude != 31.2000 {
			t.Errorf("DB coordinates mismatch: got lat=%f, lon=%f", loc.Latitude, loc.Longitude)
		}
	})

	t.Run("Rapid succession ping within 3s is rejected with 429 Too Many Requests", func(t *testing.T) {
		empRapid := "emp-rapid-under-tenant-test-owner"
		tokenRapid, _ := jwtutil.GenerateToken(empRapid, "employee", ownerID, "rapid@test.com")

		body, _ := json.Marshal(models.EmployeeLocationPingRequest{
			RequesterToken: tokenRapid,
			Latitude:       30.0501,
			Longitude:      31.2001,
		})
		req1 := httptest.NewRequest("POST", "/users/employee/location", bytes.NewReader(body))
		rec1 := httptest.NewRecorder()
		u.UpdateEmployeeLocation(rec1, req1)
		if rec1.Code != http.StatusOK {
			t.Fatalf("Expected 200 for first ping, got %d. Body: %s", rec1.Code, rec1.Body.String())
		}

		req2 := httptest.NewRequest("POST", "/users/employee/location", bytes.NewReader(body))
		rec2 := httptest.NewRecorder()
		u.UpdateEmployeeLocation(rec2, req2)
		if rec2.Code != http.StatusTooManyRequests {
			t.Errorf("Expected 429 for rapid second ping, got %d. Body: %s", rec2.Code, rec2.Body.String())
		}
	})

	t.Run("Implausible speed is rejected with 400 Bad Request", func(t *testing.T) {
		empTeleport := "emp-under-teleport-owner"
		tokTeleport, _ := jwtutil.GenerateToken(empTeleport, "employee", "teleport-owner", "teleport@test.com")

		body1, _ := json.Marshal(models.EmployeeLocationPingRequest{
			RequesterToken: tokTeleport,
			Latitude:       30.0444,
			Longitude:      31.2357,
		})
		req1 := httptest.NewRequest("POST", "/users/employee/location", bytes.NewReader(body1))
		rec1 := httptest.NewRecorder()
		u.UpdateEmployeeLocation(rec1, req1)
		if rec1.Code != http.StatusOK {
			t.Fatalf("Expected 200 for initial location, got %d. Body: %s", rec1.Code, rec1.Body.String())
		}

		ctx := context.Background()
		_ = s.UpsertEmployeeLocation(ctx, &models.EmployeeLocation{
			TenantID:   "teleport-owner",
			EmployeeID: empTeleport,
			Latitude:   30.0444,
			Longitude:  31.2357,
			UpdatedAt:  time.Now().UTC().Add(-10 * time.Second),
		})
		u.setTestLocationLastUpdate("emp:"+empTeleport, time.Now().Add(-10*time.Second))

		body2, _ := json.Marshal(models.EmployeeLocationPingRequest{
			RequesterToken: tokTeleport,
			Latitude:       31.2001,
			Longitude:      29.9187,
		})
		req2 := httptest.NewRequest("POST", "/users/employee/location", bytes.NewReader(body2))
		rec2 := httptest.NewRecorder()
		u.UpdateEmployeeLocation(rec2, req2)
		if rec2.Code != http.StatusBadRequest {
			t.Errorf("Expected 400 Bad Request for teleportation jump (> 150 km/h), got %d. Body: %s", rec2.Code, rec2.Body.String())
		}
		if !strings.Contains(rec2.Body.String(), "implausible_speed") {
			t.Errorf("Expected implausible_speed error, got: %s", rec2.Body.String())
		}
	})
}

// ---------------------------------------------------------------------------
// 2. Fresh vs Stale Availability Query Tests
// ---------------------------------------------------------------------------

func TestDispatch_FreshVsStaleAvailabilityQuery(t *testing.T) {
	_, s, _, cleanup := setupDispatchTestHarness(t)
	if s == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	tenantID := "tenant-fresh-stale"

	now := time.Now().UTC()

	// Courier 1: fresh ping (2 minutes ago)
	_ = s.UpsertEmployeeLocation(ctx, &models.EmployeeLocation{
		TenantID:   tenantID,
		EmployeeID: "emp-under-tenant-fresh-stale-1",
		Latitude:   30.0,
		Longitude:  30.0,
		UpdatedAt:  now.Add(-2 * time.Minute),
	})

	// Courier 2: stale ping (8 minutes ago, > 5 min window)
	_ = s.UpsertEmployeeLocation(ctx, &models.EmployeeLocation{
		TenantID:   tenantID,
		EmployeeID: "emp-under-tenant-fresh-stale-2",
		Latitude:   30.1,
		Longitude:  30.1,
		UpdatedAt:  now.Add(-8 * time.Minute),
	})

	fresh, err := s.GetFreshEmployeeLocations(ctx, tenantID, 5*time.Minute)
	if err != nil {
		t.Fatalf("GetFreshEmployeeLocations failed: %v", err)
	}

	if len(fresh) != 1 {
		t.Fatalf("Expected exactly 1 fresh courier, got %d", len(fresh))
	}
	if fresh[0].EmployeeID != "emp-under-tenant-fresh-stale-1" {
		t.Errorf("Expected fresh courier 1, got %s", fresh[0].EmployeeID)
	}
}

// ---------------------------------------------------------------------------
// 3. Nearest-Employee Selection with Multiple Candidates
// ---------------------------------------------------------------------------

func TestDispatch_NearestEmployeeSelection(t *testing.T) {
	u, s, _, cleanup := setupDispatchTestHarness(t)
	if u == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	ownerID := "tenant-multi-candidate"
	svcID := "svc-multi-cand"

	s.CreateService(ctx, &models.Service{
		ID:               svcID,
		TenantID:         ownerID,
		Name:             "Multi-Courier Delivery",
		Category:         "transport",
		TenantBasePrice:  40.0,
		TenantPricePerKM: 2.0,
		Latitude:         30.0444,
		Longitude:        31.2357,
	})

	// Customer pickup location: Giza Zoo (30.0222, 31.2133)
	custLoc := models.Location{Latitude: 30.0222, Longitude: 31.2133}
	now := time.Now().UTC()

	// Candidate A: Maadi (30.0, 31.3) — ~10 km away
	_ = s.UpsertEmployeeLocation(ctx, &models.EmployeeLocation{
		TenantID:   ownerID,
		EmployeeID: "emp-A-under-tenant-multi-candidate",
		Latitude:   30.0,
		Longitude:  31.3,
		UpdatedAt:  now,
	})

	// Candidate B (CLOSEST): Dokki (30.0380, 31.2120) — ~1.7 km away
	_ = s.UpsertEmployeeLocation(ctx, &models.EmployeeLocation{
		TenantID:   ownerID,
		EmployeeID: "emp-B-under-tenant-multi-candidate",
		Latitude:   30.0380,
		Longitude:  31.2120,
		UpdatedAt:  now,
	})

	// Candidate C: Heliopolis (30.0900, 31.3200) — ~13 km away
	_ = s.UpsertEmployeeLocation(ctx, &models.EmployeeLocation{
		TenantID:   ownerID,
		EmployeeID: "emp-C-under-tenant-multi-candidate",
		Latitude:   30.0900,
		Longitude:  31.3200,
		UpdatedAt:  now,
	})

	// Candidate D: Inactive courier close by
	_ = s.UpsertEmployeeLocation(ctx, &models.EmployeeLocation{
		TenantID:   ownerID,
		EmployeeID: "emp-deactivated-under-tenant-multi-candidate",
		Latitude:   30.0230,
		Longitude:  31.2140,
		UpdatedAt:  now,
	})

	nearest, err := u.findNearestAvailableEmployee(ctx, ownerID, custLoc)
	if err != nil {
		t.Fatalf("findNearestAvailableEmployee failed: %v", err)
	}

	if nearest.EmployeeID != "emp-B-under-tenant-multi-candidate" {
		t.Fatalf("Expected Candidate B (closest active) to be selected, but got %s", nearest.EmployeeID)
	}
}

// ---------------------------------------------------------------------------
// 4. Rejection Paths: no_couriers_available and employee_location_unavailable
// ---------------------------------------------------------------------------

func TestDispatch_RejectionPaths(t *testing.T) {
	u, s, _, cleanup := setupDispatchTestHarness(t)
	if u == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	ownerID := "tenant-no-courier"
	svcID := "svc-no-courier"

	s.CreateService(ctx, &models.Service{
		ID:               svcID,
		TenantID:         ownerID,
		Name:             "Delivery Service",
		Category:         "transport",
		TenantBasePrice:  30.0,
		TenantPricePerKM: 1.5,
		Latitude:         30.0444,
		Longitude:        31.2357,
	})

	tokenCust, _ := jwtutil.GenerateToken("cust-rejection", "user", ownerID, "cust@test.com")

	t.Run("Auto-dispatch with NO available couriers returns 201 with unavailable status", func(t *testing.T) {
		body, _ := json.Marshal(map[string]any{
			"service_id":     svcID,
			"user_id":        tokenCust,
			"payment_method": "cod",
			"location":       models.Location{Latitude: 30.05, Longitude: 31.25},
		})
		req := httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(body))
		rec := httptest.NewRecorder()
		u.TrackJob(rec, req)

		if rec.Code != http.StatusCreated {
			t.Fatalf("Expected 201 Created for no couriers available, got %d. Body: %s", rec.Code, rec.Body.String())
		}
		var resp struct {
			Job models.Job `json:"job"`
		}
		_ = json.Unmarshal(rec.Body.Bytes(), &resp)
		if resp.Job.Status != models.JobStatusUnavailable {
			t.Errorf("Expected 'unavailable' status, got %q", resp.Job.Status)
		}
	})

	t.Run("Direct-assign with unpinged employee returns 422 employee_location_unavailable", func(t *testing.T) {
		unpingedEmpID := "emp-unpinged-under-tenant-no-courier"
		tokenUnpingedEmp, _ := jwtutil.GenerateToken(unpingedEmpID, "employee", ownerID, "unpinged@test.com")

		body, _ := json.Marshal(map[string]any{
			"service_id":     svcID,
			"user_id":        tokenCust,
			"employee_id":    tokenUnpingedEmp,
			"payment_method": "cod",
			"location":       models.Location{Latitude: 30.05, Longitude: 31.25},
		})
		req := httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(body))
		rec := httptest.NewRecorder()
		u.TrackJob(rec, req)

		if rec.Code != http.StatusUnprocessableEntity {
			t.Fatalf("Expected 422 for employee_location_unavailable, got %d. Body: %s", rec.Code, rec.Body.String())
		}
		var resp map[string]string
		_ = json.Unmarshal(rec.Body.Bytes(), &resp)
		if resp["error"] != "employee_location_unavailable" {
			t.Errorf("Expected 'employee_location_unavailable' error code, got %q", resp["error"])
		}
	})
}

// ---------------------------------------------------------------------------
// 5. End-to-End Pricing Test: Employee Location vs Business Address Proof
// ---------------------------------------------------------------------------

func TestPricing_EmployeeLocationVsBusinessAddress_EndToEnd(t *testing.T) {
	u, s, _, cleanup := setupDispatchTestHarness(t)
	if u == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	ownerID := "tenant-pricing-proof"
	empID := "emp-under-tenant-pricing-proof"
	custID := "cust-pricing-proof"
	svcID := "svc-pricing-proof"

	// 1. Registered business address: Cairo downtown (30.0444, 31.2357)
	// Base Price = $50.00, Rate = $2.00 / km
	s.CreateService(ctx, &models.Service{
		ID:               svcID,
		TenantID:         ownerID,
		Name:             "Proof Transport Service",
		Category:         "transport",
		TenantBasePrice:  50.0,
		TenantPricePerKM: 2.0,
		Latitude:         30.0444,
		Longitude:        31.2357,
	})

	// 2. Customer pickup location: Giza (30.0131, 31.2089)
	// Distance customer <-> business address: ~4.33 km
	customerLoc := models.Location{Latitude: 30.0131, Longitude: 31.2089}
	oldBuggyDistance := haversineKm(customerLoc.Latitude, customerLoc.Longitude, 30.0444, 31.2357)
	oldBuggyPrice := math.Round((50.0+(oldBuggyDistance*2.0))*100) / 100

	// 3. Assigned courier is actually located far away in Alexandria (31.2001, 29.9187)
	// Distance customer <-> courier location: ~180.89 km
	courierLat := 31.2001
	courierLon := 29.9187
	expectedCorrectDistance := haversineKm(customerLoc.Latitude, customerLoc.Longitude, courierLat, courierLon)
	expectedCorrectPrice := math.Round((50.0+(expectedCorrectDistance*2.0))*100) / 100

	_ = s.UpsertEmployeeLocation(ctx, &models.EmployeeLocation{
		TenantID:   ownerID,
		EmployeeID: empID,
		Latitude:   courierLat,
		Longitude:  courierLon,
		UpdatedAt:  time.Now().UTC(),
	})

	tokenCust, _ := jwtutil.GenerateToken(custID, "user", ownerID, "cust@test.com")
	tokenOwner, _ := jwtutil.GenerateToken(ownerID, "owner", ownerID, "owner@test.com")
	tokenEmp, _ := jwtutil.GenerateToken(empID, "employee", ownerID, "emp@test.com")

	// 4. Book job via customer TrackJob (auto-dispatch picks the Alexandria courier)
	trackBody, _ := json.Marshal(map[string]any{
		"service_id":     svcID,
		"user_id":        tokenCust,
		"payment_method": "cod",
		"location":       customerLoc,
	})
	req := httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(trackBody))
	rec := httptest.NewRecorder()
	u.TrackJob(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("Expected 201 Created on TrackJob, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	var trackResp map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &trackResp)
	jobData, ok := trackResp["job"].(map[string]any)
	if !ok || jobData == nil {
		t.Fatalf("Expected job object in response, got: %s", rec.Body.String())
	}

	jobID := jobData["id"].(string)
	if jobData["status"] != string(models.JobStatusPendingDispatch) {
		t.Fatalf("Expected initial job status pending_dispatch, got %v", jobData["status"])
	}

	// 5. Courier accepts the dispatch offer -> Pricing happens at accept-time
	acceptReq := httptest.NewRequest("POST", fmt.Sprintf("/users/employee/jobs/%s/accept", jobID), nil)
	acceptReq.Header.Set("Authorization", "Bearer "+tokenEmp)
	acceptRec := httptest.NewRecorder()
	u.AcceptJobOffer(acceptRec, acceptReq)

	if acceptRec.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK on AcceptJobOffer, got %d. Body: %s", acceptRec.Code, acceptRec.Body.String())
	}

	var acceptResp map[string]any
	_ = json.Unmarshal(acceptRec.Body.Bytes(), &acceptResp)
	acceptedJobData := acceptResp["job"].(map[string]any)
	suggestedPrice := acceptedJobData["suggested_price"].(float64)

	// MATHEMATICAL PROOF:
	t.Logf("Old buggy price (business address distance %.2f km): $%.2f", oldBuggyDistance, oldBuggyPrice)
	t.Logf("Expected correct price (courier location distance %.2f km): $%.2f", expectedCorrectDistance, expectedCorrectPrice)
	t.Logf("Actual calculated suggested price: $%.2f", suggestedPrice)

	if math.Abs(suggestedPrice-expectedCorrectPrice) > 0.05 {
		t.Errorf("Price does NOT match courier location math! Expected ~$%.2f, got $%.2f", expectedCorrectPrice, suggestedPrice)
	}
	if math.Abs(suggestedPrice-oldBuggyPrice) < 5.0 {
		t.Fatalf("CRITICAL BUG: Price matches the old fixed business address ($%.2f) instead of the courier's location!", suggestedPrice)
	}

	// 6. Verify snapshot on Job in DB
	dbJob := s.GetJob(ctx, jobID)
	if dbJob == nil {
		t.Fatalf("Job %s not found in DB", jobID)
	}
	if dbJob.BookedDistance <= 0 {
		t.Errorf("Expected BookedDistance to be snapshotted on Job, got %f", dbJob.BookedDistance)
	}
	if dbJob.AssignedEmployeeLocation == nil {
		t.Fatalf("Expected AssignedEmployeeLocation to be snapshotted on Job, got nil")
	}
	if dbJob.AssignedEmployeeLocation.Latitude != courierLat || dbJob.AssignedEmployeeLocation.Longitude != courierLon {
		t.Errorf("Snapshotted AssignedEmployeeLocation mismatch: got lat=%f, lon=%f", dbJob.AssignedEmployeeLocation.Latitude, dbJob.AssignedEmployeeLocation.Longitude)
	}

	// 6. Driver accepts suggested price and completes job
	acceptBody, _ := json.Marshal(map[string]any{
		"job_id":          jobID,
		"decision":        "accept",
		"requester_token": tokenEmp,
	})
	reqAccept := httptest.NewRequest("POST", "/users/jobs/respond-price", bytes.NewReader(acceptBody))
	recAccept := httptest.NewRecorder()
	u.RespondPrice(recAccept, reqAccept)
	if recAccept.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK on respond-price accept, got %d. Body: %s", recAccept.Code, recAccept.Body.String())
	}

	completeBody, _ := json.Marshal(map[string]any{
		"job_id":          jobID,
		"cash_collected":  true,
		"requester_token": tokenOwner,
	})
	reqComplete := httptest.NewRequest("POST", "/users/jobs/complete", bytes.NewReader(completeBody))
	recComplete := httptest.NewRecorder()
	u.CompleteJob(recComplete, reqComplete)
	if recComplete.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK on CompleteJob, got %d. Body: %s", recComplete.Code, recComplete.Body.String())
	}

	var completeResp map[string]any
	_ = json.Unmarshal(recComplete.Body.Bytes(), &completeResp)
	totalAmount, _ := completeResp["total_amount"].(float64)

	if math.Abs(totalAmount-expectedCorrectPrice) > 0.05 {
		t.Errorf("Final complete job total_amount $%.2f does not match expected $%.2f", totalAmount, expectedCorrectPrice)
	}
}
