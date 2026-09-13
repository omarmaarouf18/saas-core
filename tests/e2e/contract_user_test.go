package e2e

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"testing"
	"time"

	"go.mongodb.org/mongo-driver/v2/bson"
)

// TestContract_UserService systematically exercises the API contracts, HTTP verbs,
// auth requirements, negative boundaries, CAS concurrency semantics, and response schemas
// for all 34 canonical user-service routes in the parity inventory.
func TestContract_UserService(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()

	cfg := LoadConfig()
	db, err := ConnectStagingDB(ctx, cfg.MongoURI)
	if err != nil {
		t.Fatalf("Failed to connect to staging DB: %v", err)
	}
	defer db.Close(ctx)

	// Unique test run identities
	ts := time.Now().UnixNano()
	testTenantID := fmt.Sprintf("tenant_usr_%d", ts)
	// In Quick Delivery architecture, owner user ID is tenant ID
	testOwnerID := testTenantID
	testOwnerEmail := fmt.Sprintf("owner_%d@contract.test", ts)
	testServiceID := fmt.Sprintf("svc_usr_%d", ts)

	testCourierID := fmt.Sprintf("cour_usr_%d", ts)
	testCourierEmail := fmt.Sprintf("cour_%d@contract.test", ts)

	// Dedicated couriers for dispatch offer accept/decline testing (avoids courier_busy on active courier)
	testCourier2ID := fmt.Sprintf("cour2_usr_%d", ts)
	testCourier2Email := fmt.Sprintf("cour2_%d@contract.test", ts)
	testCourier3ID := fmt.Sprintf("cour3_usr_%d", ts)
	testCourier3Email := fmt.Sprintf("cour3_%d@contract.test", ts)

	testCustID := fmt.Sprintf("cust_usr_%d", ts)
	testCustEmail := fmt.Sprintf("cust_%d@contract.test", ts)

	unauthCustID := fmt.Sprintf("cust_unauth_%d", ts)
	unauthCustEmail := fmt.Sprintf("unauth_%d@contract.test", ts)

	otherTenantID := fmt.Sprintf("other_tenant_%d", ts)
	otherOwnerEmail := fmt.Sprintf("other_owner_%d@contract.test", ts)

	adminSubTenantID := fmt.Sprintf("admin_sub_tenant_%d", ts)

	reviewerID := fmt.Sprintf("rev_usr_%d", ts)
	rawReviewerToken := fmt.Sprintf("rev_token_usr_%d", ts)

	cleanupEntities := func() {
		db.CleanupTestEntities(ctx,
			[]string{testTenantID, otherTenantID, adminSubTenantID},
			[]string{testOwnerID, testCourierID, testCourier2ID, testCourier3ID, testCustID, unauthCustID, otherTenantID, reviewerID},
		)
		_ = FlushAllAuthRateLimits(ctx, cfg.RedisURI)
	}
	defer cleanupEntities()
	cleanupEntities()

	// 1. Seed Staging DB State
	if err := db.SeedTenantAndService(ctx, testTenantID, testOwnerID, testServiceID, 25.0, 5.0, 30.0444, 31.2357); err != nil {
		t.Fatalf("Failed to seed tenant and service: %v", err)
	}
	if err := db.SeedCourier(ctx, testTenantID, testCourierID, testCourierEmail, 30.0450, 31.2360); err != nil {
		t.Fatalf("Failed to seed courier: %v", err)
	}
	if err := db.SeedCourier(ctx, testTenantID, testCourier2ID, testCourier2Email, 30.0452, 31.2362); err != nil {
		t.Fatalf("Failed to seed courier 2: %v", err)
	}
	if err := db.SeedCourier(ctx, testTenantID, testCourier3ID, testCourier3Email, 30.0454, 31.2364); err != nil {
		t.Fatalf("Failed to seed courier 3: %v", err)
	}
	if err := db.SeedCustomer(ctx, testTenantID, testCustID, testCustEmail); err != nil {
		t.Fatalf("Failed to seed customer: %v", err)
	}
	if err := db.SeedCustomer(ctx, "unrelated_tenant", unauthCustID, unauthCustEmail); err != nil {
		t.Fatalf("Failed to seed unrelated customer: %v", err)
	}
	if err := db.SeedTenantAndService(ctx, otherTenantID, otherTenantID, "svc_other_"+otherTenantID, 20.0, 4.0, 30.05, 31.25); err != nil {
		t.Fatalf("Failed to seed other tenant: %v", err)
	}
	if err := db.SeedWallet(ctx, testTenantID, 500.0); err != nil {
		t.Fatalf("Failed to seed wallet: %v", err)
	}
	if err := db.SeedFreeSubscription(ctx, adminSubTenantID); err != nil {
		t.Fatalf("Failed to seed admin sub tenant: %v", err)
	}
	if err := db.SeedReviewer(ctx, reviewerID, "QA Ops Reviewer", rawReviewerToken); err != nil {
		t.Fatalf("Failed to seed reviewer: %v", err)
	}

	// 2. Generate Actor JWTs
	ownerToken, err := cfg.GenerateJWT(testOwnerID, "owner", testTenantID, testOwnerEmail)
	if err != nil {
		t.Fatalf("Failed to generate owner token: %v", err)
	}
	courierToken, err := cfg.GenerateJWT(testCourierID, "employee", testTenantID, testCourierEmail)
	if err != nil {
		t.Fatalf("Failed to generate courier token: %v", err)
	}
	courier2Token, err := cfg.GenerateJWT(testCourier2ID, "employee", testTenantID, testCourier2Email)
	if err != nil {
		t.Fatalf("Failed to generate courier 2 token: %v", err)
	}
	courier3Token, err := cfg.GenerateJWT(testCourier3ID, "employee", testTenantID, testCourier3Email)
	if err != nil {
		t.Fatalf("Failed to generate courier 3 token: %v", err)
	}
	custToken, err := cfg.GenerateJWT(testCustID, "user", testTenantID, testCustEmail)
	if err != nil {
		t.Fatalf("Failed to generate customer token: %v", err)
	}
	unauthCustToken, err := cfg.GenerateJWT(unauthCustID, "user", "unrelated_tenant", unauthCustEmail)
	if err != nil {
		t.Fatalf("Failed to generate unrelated customer token: %v", err)
	}
	otherOwnerToken, err := cfg.GenerateJWT(otherTenantID, "owner", otherTenantID, otherOwnerEmail)
	if err != nil {
		t.Fatalf("Failed to generate other owner token: %v", err)
	}

	reviewerHeaders := map[string]string{
		"X-Reviewer-Token": rawReviewerToken,
		"Content-Type":     "application/json",
	}

	_ = FlushAllAuthRateLimits(ctx, cfg.RedisURI)

	// =========================================================================
	// GROUP A: Services Directory & CRUD (4 Endpoints)
	// =========================================================================

	// 1. GET /users/services
	t.Run("GET_Users_Services", func(t *testing.T) {
		url := fmt.Sprintf("%s/api/v1/users/services", cfg.GatewayURL)

		// Negative: Invalid coordinates -> 400
		respBadCoord, _, err := GetJSON(ctx, url+"?lat=95&lon=200&near_by=true", "")
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respBadCoord.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for invalid coordinates, got %d", respBadCoord.StatusCode)
		}

		// Wrong Method: DELETE -> 405
		respDel, _, err := DeleteJSON(ctx, url, "")
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respDel.StatusCode != http.StatusMethodNotAllowed {
			t.Errorf("Expected 405 for DELETE /users/services, got %d", respDel.StatusCode)
		}

		// Happy Path: Spatial search query -> 200 OK
		respGood, body, err := GetJSON(ctx, url+"?lat=30.0444&lon=31.2357&near_by=true&radius=100", "")
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK for services query, got %d: %s", respGood.StatusCode, string(body))
		}

		var parsed struct {
			Count    int   `json:"count"`
			Services []any `json:"services"`
		}
		if err := json.Unmarshal(body, &parsed); err != nil || parsed.Count < 1 {
			t.Errorf("Expected services list schema, got count=%d, err=%v", parsed.Count, err)
		}
	})

	var createdServiceID string

	// 2. POST /users/services
	t.Run("POST_Users_Services", func(t *testing.T) {
		url := fmt.Sprintf("%s/api/v1/users/services", cfg.GatewayURL)

		// Negative: Anonymous -> 400 or 401
		respAnon, _, _ := PostJSON(ctx, url, "", map[string]any{"name": "Anon Service"})
		if respAnon.StatusCode != http.StatusBadRequest && respAnon.StatusCode != http.StatusUnauthorized {
			t.Errorf("Expected 400/401 for anonymous service creation, got %d", respAnon.StatusCode)
		}

		// Negative: Customer role forbidden -> 401/403
		respCust, _, _ := PostJSON(ctx, url, custToken, map[string]any{
			"name":     "Illegal Cust Service",
			"category": "delivery",
		})
		if respCust.StatusCode != http.StatusUnauthorized && respCust.StatusCode != http.StatusForbidden {
			t.Errorf("Expected 401/403 for customer service creation, got %d", respCust.StatusCode)
		}

		// Negative: Invalid category -> 400
		respBadCat, _, _ := PostJSON(ctx, url, ownerToken, map[string]any{
			"name":                "Bad Cat Service",
			"category":            "flying_carpet",
			"tenant_base_price":   10.0,
			"tenant_price_per_km": 2.0,
			"latitude":            30.0444,
			"longitude":           31.2357,
		})
		if respBadCat.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for invalid category, got %d", respBadCat.StatusCode)
		}

		// Negative: Invalid coordinates -> 400
		respBadCoord, _, _ := PostJSON(ctx, url, ownerToken, map[string]any{
			"name":      "Bad Coord Service",
			"category":  "delivery",
			"latitude":  150.0,
			"longitude": 31.2357,
		})
		if respBadCoord.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for invalid coordinates, got %d", respBadCoord.StatusCode)
		}

		// Happy Path: Owner with KYC approved and Paid tier -> 201 Created
		newSvcPayload := map[string]any{
			"name":                "Cairo Courier Express",
			"category":            "delivery",
			"tenant_base_price":   30.0,
			"tenant_price_per_km": 4.5,
			"latitude":            30.0444,
			"longitude":           31.2357,
			"coverage_radius_km":  25.0,
			"address":             "Tahrir Square, Cairo",
			"working_hours":       "08:00 - 22:00",
		}
		respGood, body, err := PostJSON(ctx, url, ownerToken, newSvcPayload)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusCreated {
			t.Fatalf("Expected 201 Created for service creation, got %d: %s", respGood.StatusCode, string(body))
		}

		var parsed struct {
			Message string `json:"message"`
			Service struct {
				ID       string `json:"id"`
				TenantID string `json:"tenant_id"`
				Name     string `json:"name"`
			} `json:"service"`
		}
		if err := json.Unmarshal(body, &parsed); err != nil || parsed.Service.ID == "" {
			t.Fatalf("Failed to parse created service response: %v", err)
		}
		createdServiceID = parsed.Service.ID
	})

	// 3. PUT /users/services (and companion route /users/services/update)
	t.Run("PUT_Users_Services", func(t *testing.T) {
		url := fmt.Sprintf("%s/api/v1/users/services", cfg.GatewayURL)

		// Negative: Missing service ID -> 400
		respNoID, _, _ := PutJSON(ctx, url, ownerToken, map[string]any{
			"name": "Updated Name Without ID",
		})
		if respNoID.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for missing service ID in PUT, got %d", respNoID.StatusCode)
		}

		// Happy Path: Canonical route PUT -> 200 OK
		updatePayload := map[string]any{
			"id":                 createdServiceID,
			"name":               "Cairo Courier Express Updated",
			"working_hours":      "07:00 - 23:00",
			"coverage_radius_km": 30.0,
		}
		respGood, body, err := PutJSON(ctx, url, ownerToken, updatePayload)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK for PUT service, got %d: %s", respGood.StatusCode, string(body))
		}

		// Companion Route Parity: PUT /users/services/update
		companionURL := fmt.Sprintf("%s/api/v1/users/services/update", cfg.GatewayURL)
		respComp, bodyComp, err := PutJSON(ctx, companionURL, ownerToken, updatePayload)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respComp.StatusCode != http.StatusOK {
			t.Errorf("Expected 200 OK for companion PUT /users/services/update, got %d: %s", respComp.StatusCode, string(bodyComp))
		}
	})

	// 4. PATCH /users/services (and companion route /users/services/update)
	t.Run("PATCH_Users_Services", func(t *testing.T) {
		url := fmt.Sprintf("%s/api/v1/users/services", cfg.GatewayURL)

		patchPayload := map[string]any{
			"id":            createdServiceID,
			"working_hours": "09:00 - 21:00",
		}
		respGood, body, err := PatchJSON(ctx, url, ownerToken, patchPayload)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK for PATCH service, got %d: %s", respGood.StatusCode, string(body))
		}

		// Companion Route Parity: PATCH /users/services/update
		companionURL := fmt.Sprintf("%s/api/v1/users/services/update", cfg.GatewayURL)
		respComp, bodyComp, err := PatchJSON(ctx, companionURL, ownerToken, patchPayload)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respComp.StatusCode != http.StatusOK {
			t.Errorf("Expected 200 OK for companion PATCH /users/services/update, got %d: %s", respComp.StatusCode, string(bodyComp))
		}
	})

	// =========================================================================
	// GROUP B: Jobs Booking & Negotiation (8 Endpoints)
	// =========================================================================

	var bookedDeliveryJobID string

	// 5. POST /users/jobs/track
	t.Run("POST_Users_Jobs_Track", func(t *testing.T) {
		_ = FlushAllAuthRateLimits(ctx, cfg.RedisURI)
		url := fmt.Sprintf("%s/api/v1/users/jobs/track", cfg.GatewayURL)

		// Negative: Missing service_id / user_id -> 400
		respNoSvc, _, _ := PostJSON(ctx, url, custToken, map[string]any{})
		if respNoSvc.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for missing service_id/user_id, got %d", respNoSvc.StatusCode)
		}

		// Negative: Invalid user token -> 401
		respBadToken, _, _ := PostJSON(ctx, url, "", map[string]any{
			"service_id": testServiceID,
			"user_token": "invalid_jwt_token",
			"location":   map[string]any{"latitude": 30.0444, "longitude": 31.2357},
		})
		if respBadToken.StatusCode != http.StatusUnauthorized {
			t.Errorf("Expected 401 for invalid user token, got %d", respBadToken.StatusCode)
		}

		// Negative: Invalid coordinates -> 400
		respBadCoord, _, _ := PostJSON(ctx, url, custToken, map[string]any{
			"service_id": testServiceID,
			"user_token": custToken,
			"location":   map[string]any{"latitude": 999.0, "longitude": 31.0},
		})
		if respBadCoord.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for invalid job coordinates, got %d", respBadCoord.StatusCode)
		}

		// Wrong Method: GET -> 405
		respGet, _, _ := GetJSON(ctx, url, custToken)
		if respGet.StatusCode != http.StatusMethodNotAllowed {
			t.Errorf("Expected 405 for GET /users/jobs/track, got %d", respGet.StatusCode)
		}

		// Happy Path: Book delivery job (COD) -> 201 Created
		bookPayload := map[string]any{
			"service_id":     testServiceID,
			"user_token":     custToken,
			"payment_method": "cod",
			"location":       map[string]any{"latitude": 30.0444, "longitude": 31.2357},
		}
		respGood, body, err := PostJSON(ctx, url, custToken, bookPayload)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusCreated {
			t.Fatalf("Expected 201 Created for job booking, got %d: %s", respGood.StatusCode, string(body))
		}

		var parsed struct {
			Message string `json:"message"`
			Job     struct {
				ID      string `json:"id"`
				OwnerID string `json:"owner_id"`
				UserID  string `json:"user_id"`
				Status  string `json:"status"`
			} `json:"job"`
		}
		if err := json.Unmarshal(body, &parsed); err != nil || parsed.Job.ID == "" {
			t.Fatalf("Failed to parse booked job response: %v", err)
		}
		bookedDeliveryJobID = parsed.Job.ID

		// Associate courier with the job and set active for completion/rating tests
		_, _ = db.client.Database("staging_user_db").Collection("jobs").UpdateOne(
			ctx,
			bson.M{"_id": bookedDeliveryJobID},
			bson.M{"$set": bson.M{"employee_id": testCourierID, "status": "active"}},
		)
	})

	// 6. GET /users/jobs/get
	t.Run("GET_Users_Jobs_Get", func(t *testing.T) {
		url := fmt.Sprintf("%s/api/v1/users/jobs/get", cfg.GatewayURL)

		// Negative: Missing ID and requester -> 400/401
		respNoParam, _, _ := GetJSON(ctx, url, "")
		if respNoParam.StatusCode != http.StatusBadRequest && respNoParam.StatusCode != http.StatusUnauthorized {
			t.Errorf("Expected 400/401 for GET /users/jobs/get without params, got %d", respNoParam.StatusCode)
		}

		// Negative: Non-existent job ID -> 404
		resp404, _, _ := GetJSON(ctx, url+"?id=job-nonexistent-0000", custToken)
		if resp404.StatusCode != http.StatusNotFound {
			t.Errorf("Expected 404 for non-existent job ID, got %d", resp404.StatusCode)
		}

		// Negative: IDOR check (unrelated customer) -> 403 Forbidden
		respIDOR, _, _ := GetJSON(ctx, fmt.Sprintf("%s?id=%s", url, bookedDeliveryJobID), unauthCustToken)
		if respIDOR.StatusCode != http.StatusForbidden {
			t.Errorf("Expected 403 Forbidden for IDOR query on job, got %d", respIDOR.StatusCode)
		}

		// Wrong Method: POST -> 405
		respPost, _, _ := PostJSON(ctx, url, custToken, map[string]any{})
		if respPost.StatusCode != http.StatusMethodNotAllowed {
			t.Errorf("Expected 405 for POST /users/jobs/get, got %d", respPost.StatusCode)
		}

		// Happy Path: Authenticated customer retrieves job -> 200 OK
		respGood, body, err := GetJSON(ctx, fmt.Sprintf("%s?id=%s", url, bookedDeliveryJobID), custToken)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK for job retrieval, got %d: %s", respGood.StatusCode, string(body))
		}

		var parsed struct {
			ID      string `json:"id"`
			OwnerID string `json:"owner_id"`
			Status  string `json:"status"`
		}
		if err := json.Unmarshal(body, &parsed); err != nil || parsed.ID != bookedDeliveryJobID {
			t.Errorf("Expected valid job schema, got id=%s, err=%v", parsed.ID, err)
		}
	})

	// 7. GET /users/jobs/owner
	t.Run("GET_Users_Jobs_Owner", func(t *testing.T) {
		_ = FlushAllAuthRateLimits(ctx, cfg.RedisURI)
		url := fmt.Sprintf("%s/api/v1/users/jobs/owner", cfg.GatewayURL)

		// Negative: Anonymous -> 401
		respAnon, _, _ := GetJSON(ctx, url, "")
		if respAnon.StatusCode != http.StatusUnauthorized {
			t.Errorf("Expected 401 for anonymous owner jobs, got %d", respAnon.StatusCode)
		}

		// Negative: Customer token -> 403 Forbidden (owner role required)
		respCust, _, _ := GetJSON(ctx, url, custToken)
		if respCust.StatusCode != http.StatusForbidden {
			t.Errorf("Expected 403 for customer token on owner jobs, got %d", respCust.StatusCode)
		}

		// Negative: IDOR check: explicit mismatch in owner_id -> 403
		respIDOR, _, _ := GetJSON(ctx, url+"?owner_id=other_owner_id", ownerToken)
		if respIDOR.StatusCode != http.StatusForbidden {
			t.Errorf("Expected 403 for IDOR owner_id mismatch, got %d", respIDOR.StatusCode)
		}

		// Happy Path: Owner queries their jobs -> 200 OK
		respGood, body, err := GetJSON(ctx, url, ownerToken)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK for owner jobs, got %d: %s", respGood.StatusCode, string(body))
		}

		var parsed []map[string]any
		if err := json.Unmarshal(body, &parsed); err != nil || len(parsed) < 1 {
			t.Errorf("Expected owner jobs array schema, got len=%d, err=%v", len(parsed), err)
		}
	})

	// 8. GET /users/jobs/mine
	t.Run("GET_Users_Jobs_Mine", func(t *testing.T) {
		_ = FlushAllAuthRateLimits(ctx, cfg.RedisURI)
		url := fmt.Sprintf("%s/api/v1/users/jobs/mine", cfg.GatewayURL)

		// Negative: Anonymous -> 401
		respAnon, _, _ := GetJSON(ctx, url, "")
		if respAnon.StatusCode != http.StatusUnauthorized {
			t.Errorf("Expected 401 for anonymous customer jobs, got %d", respAnon.StatusCode)
		}

		// Negative: Owner token -> 403 Forbidden (customer role required)
		respOwner, _, _ := GetJSON(ctx, url, ownerToken)
		if respOwner.StatusCode != http.StatusForbidden {
			t.Errorf("Expected 403 for owner token on customer jobs, got %d", respOwner.StatusCode)
		}

		// Negative: IDOR check: explicit mismatch in user_id -> 403
		respIDOR, _, _ := GetJSON(ctx, url+"?user_id=other_user_id", custToken)
		if respIDOR.StatusCode != http.StatusForbidden {
			t.Errorf("Expected 403 for IDOR user_id mismatch, got %d", respIDOR.StatusCode)
		}

		// Happy Path: Customer queries their booked jobs -> 200 OK
		respGood, body, err := GetJSON(ctx, url, custToken)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK for customer jobs, got %d: %s", respGood.StatusCode, string(body))
		}

		var parsed []map[string]any
		if err := json.Unmarshal(body, &parsed); err != nil || len(parsed) < 1 {
			t.Errorf("Expected customer jobs array schema, got len=%d, err=%v", len(parsed), err)
		}
	})

	// Setup Transport Service & Transport Job for Negotiation
	transportSvcID := fmt.Sprintf("svc_trans_%d", ts)
	_, _ = db.client.Database("staging_user_db").Collection("services").InsertOne(ctx, bson.M{
		"_id":                 transportSvcID,
		"tenant_id":           testTenantID,
		"owner_id":            testOwnerID,
		"name":                "City Ride Transport",
		"category":            "transport",
		"tenant_base_price":   40.0,
		"tenant_price_per_km": 10.0,
		"latitude":            30.0444,
		"longitude":           31.2357,
		"coverage_radius_km":  50.0,
		"is_active":           true,
	})

	negotiationJobID := fmt.Sprintf("job_neg_%d", ts)
	expiryTime := time.Now().UTC().Add(10 * time.Minute)
	_ = db.SeedJob(ctx, bson.M{
		"_id":                       negotiationJobID,
		"owner_id":                  testTenantID,
		"employee_id":               testCourierID,
		"user_id":                   testCustID,
		"service_id":                transportSvcID,
		"status":                    "awaiting_price_response",
		"payment_method":            "cod",
		"suggested_price":           100.0,
		"price_proposal_expires_at": expiryTime,
		"location":                  bson.M{"latitude": 30.0444, "longitude": 31.2357},
		"created_at":                time.Now().UTC(),
		"updated_at":                time.Now().UTC(),
	})

	// 9. POST /users/jobs/propose-price
	t.Run("POST_Users_Jobs_Propose_Price", func(t *testing.T) {
		_ = FlushAllAuthRateLimits(ctx, cfg.RedisURI)
		url := fmt.Sprintf("%s/api/v1/users/jobs/propose-price", cfg.GatewayURL)

		// Negative: Anonymous -> 400 or 401
		respAnon, _, _ := PostJSON(ctx, url, "", map[string]any{"job_id": negotiationJobID, "proposed_price": 110.0})
		if respAnon.StatusCode != http.StatusBadRequest && respAnon.StatusCode != http.StatusUnauthorized {
			t.Errorf("Expected 400/401 for anonymous price proposal, got %d", respAnon.StatusCode)
		}

		// Negative: Missing job_id -> 400
		respNoJob, _, _ := PostJSON(ctx, url, custToken, map[string]any{"proposed_price": 110.0})
		if respNoJob.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for missing job_id in proposal, got %d", respNoJob.StatusCode)
		}

		// Negative: Unassigned third-party user -> 403
		respForbidden, _, _ := PostJSON(ctx, url, unauthCustToken, map[string]any{
			"job_id":         negotiationJobID,
			"proposed_price": 110.0,
		})
		if respForbidden.StatusCode != http.StatusForbidden {
			t.Errorf("Expected 403 Forbidden for unassigned user proposal, got %d", respForbidden.StatusCode)
		}

		// Negative: Non-transport category job -> 400 invalid_category
		respNonTransport, _, _ := PostJSON(ctx, url, custToken, map[string]any{
			"job_id":         bookedDeliveryJobID, // delivery service
			"proposed_price": 110.0,
		})
		if respNonTransport.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for non-transport proposal, got %d", respNonTransport.StatusCode)
		}

		// Happy Path: Customer proposes 110.0 for transport job -> 200 OK
		respGood, body, err := PostJSON(ctx, url, custToken, map[string]any{
			"job_id":         negotiationJobID,
			"proposed_price": 110.0,
		})
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK for price proposal, got %d: %s", respGood.StatusCode, string(body))
		}

		// Duplicate proposal check: cannot propose while proposal is already pending -> 400
		respDup, _, _ := PostJSON(ctx, url, custToken, map[string]any{
			"job_id":         negotiationJobID,
			"proposed_price": 120.0,
		})
		if respDup.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 proposal_already_submitted on duplicate proposal, got %d", respDup.StatusCode)
		}
	})

	// 10. POST /users/jobs/respond-price
	t.Run("POST_Users_Jobs_Respond_Price", func(t *testing.T) {
		_ = FlushAllAuthRateLimits(ctx, cfg.RedisURI)
		url := fmt.Sprintf("%s/api/v1/users/jobs/respond-price", cfg.GatewayURL)

		// Negative: Missing decision -> 400
		respNoDec, _, _ := PostJSON(ctx, url, courierToken, map[string]any{
			"job_id": negotiationJobID,
		})
		if respNoDec.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for missing decision, got %d", respNoDec.StatusCode)
		}

		// Negative: Invalid decision value -> 400
		respBadDec, _, _ := PostJSON(ctx, url, courierToken, map[string]any{
			"job_id":   negotiationJobID,
			"decision": "maybe",
		})
		if respBadDec.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for invalid decision, got %d", respBadDec.StatusCode)
		}

		// Negative: Unassigned user -> 403
		respForbidden, _, _ := PostJSON(ctx, url, unauthCustToken, map[string]any{
			"job_id":   negotiationJobID,
			"decision": "accept",
		})
		if respForbidden.StatusCode != http.StatusForbidden {
			t.Errorf("Expected 403 for unassigned respondent, got %d", respForbidden.StatusCode)
		}

		// Happy Path: Courier accepts price proposal -> 200 OK
		respGood, body, err := PostJSON(ctx, url, courierToken, map[string]any{
			"job_id":   negotiationJobID,
			"decision": "accept",
		})
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK for respond-price, got %d: %s", respGood.StatusCode, string(body))
		}
	})

	// 11. POST /users/jobs/complete
	t.Run("POST_Users_Jobs_Complete", func(t *testing.T) {
		_ = FlushAllAuthRateLimits(ctx, cfg.RedisURI)
		url := fmt.Sprintf("%s/api/v1/users/jobs/complete", cfg.GatewayURL)

		// Negative: Anonymous -> 401
		respAnon, _, _ := PostJSON(ctx, url, "", map[string]any{"job_id": bookedDeliveryJobID})
		if respAnon.StatusCode != http.StatusUnauthorized {
			t.Errorf("Expected 401 for anonymous complete, got %d", respAnon.StatusCode)
		}

		// Negative: Missing job_id -> 400
		respNoJob, _, _ := PostJSON(ctx, url, courierToken, map[string]any{})
		if respNoJob.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for missing job_id in complete, got %d", respNoJob.StatusCode)
		}

		// Negative: Unassigned user -> 403 Forbidden
		respForbidden, _, _ := PostJSON(ctx, url, unauthCustToken, map[string]any{"job_id": bookedDeliveryJobID})
		if respForbidden.StatusCode != http.StatusForbidden {
			t.Errorf("Expected 403 for unassigned user complete, got %d", respForbidden.StatusCode)
		}

		// Negative: Missing cash collection confirmation for COD job -> 400
		respNoCash, _, _ := PostJSON(ctx, url, courierToken, map[string]any{
			"job_id": bookedDeliveryJobID,
		})
		if respNoCash.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for missing cash_collected on COD job complete, got %d", respNoCash.StatusCode)
		}

		// Happy Path: Courier confirms cash collected and completes job -> 200 OK
		completePayload := map[string]any{
			"job_id":             bookedDeliveryJobID,
			"cash_collected":     true,
			"actual_cash_amount": 30.0,
		}
		respGood, body, err := PostJSON(ctx, url, courierToken, completePayload)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK for job complete, got %d: %s", respGood.StatusCode, string(body))
		}

		// CAS Conflict Check: Completing already completed job -> 409 Conflict
		respConflict, _, err := PostJSON(ctx, url, courierToken, completePayload)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respConflict.StatusCode != http.StatusConflict {
			t.Errorf("Expected 409 Conflict for completing already completed job, got %d", respConflict.StatusCode)
		}
	})

	// 12. POST /users/jobs/cancel
	t.Run("POST_Users_Jobs_Cancel", func(t *testing.T) {
		_ = FlushAllAuthRateLimits(ctx, cfg.RedisURI)
		url := fmt.Sprintf("%s/api/v1/users/jobs/cancel", cfg.GatewayURL)

		// Create an active job to test cancellation rules
		cancelTargetJobID := fmt.Sprintf("job_cancel_%d", ts)
		_ = db.SeedJob(ctx, bson.M{
			"_id":            cancelTargetJobID,
			"owner_id":       testTenantID,
			"user_id":        testCustID,
			"service_id":     testServiceID,
			"status":         "active",
			"payment_method": "cod",
			"location":       bson.M{"latitude": 30.0444, "longitude": 31.2357},
			"created_at":     time.Now().UTC(),
			"updated_at":     time.Now().UTC(),
		})

		// Negative: Missing reason -> 400
		respNoReason, _, _ := PostJSON(ctx, url, ownerToken, map[string]any{
			"job_id": cancelTargetJobID,
		})
		if respNoReason.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for missing reason in cancel, got %d", respNoReason.StatusCode)
		}

		// Negative: Reason exceeds 500 characters -> 400
		longReason := strings.Repeat("A", 501)
		respLong, _, _ := PostJSON(ctx, url, ownerToken, map[string]any{
			"job_id": cancelTargetJobID,
			"reason": longReason,
		})
		if respLong.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for reason exceeding 500 chars, got %d", respLong.StatusCode)
		}

		// Negative: Customer attempting to cancel active job -> 403 Forbidden (must file ticket)
		respCustActive, _, _ := PostJSON(ctx, url, custToken, map[string]any{
			"job_id": cancelTargetJobID,
			"reason": "Customer attempt to cancel active job",
		})
		if respCustActive.StatusCode != http.StatusForbidden {
			t.Errorf("Expected 403 for customer cancelling active job, got %d", respCustActive.StatusCode)
		}

		// Happy Path: Owner cancels active job -> 200 OK
		respGood, body, err := PostJSON(ctx, url, ownerToken, map[string]any{
			"job_id": cancelTargetJobID,
			"reason": "Owner cancelled dispatch due to depot emergency",
		})
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK for owner job cancellation, got %d: %s", respGood.StatusCode, string(body))
		}

		// Conflict Check: Cancelling already cancelled job -> 409 Conflict
		respConflict, _, err := PostJSON(ctx, url, ownerToken, map[string]any{
			"job_id": cancelTargetJobID,
			"reason": "Double cancel",
		})
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respConflict.StatusCode != http.StatusConflict {
			t.Errorf("Expected 409 Conflict when cancelling already cancelled job, got %d", respConflict.StatusCode)
		}
	})

	// =========================================================================
	// GROUP C: Employee Dispatch & Tracking (5 Endpoints)
	// =========================================================================

	offerJobID1 := fmt.Sprintf("job_offer_1_%d", ts)
	offerExpiry := time.Now().UTC().Add(10 * time.Minute)
	_ = db.SeedJob(ctx, bson.M{
		"_id":                         offerJobID1,
		"owner_id":                    testTenantID,
		"user_id":                     testCustID,
		"service_id":                  testServiceID,
		"status":                      "pending_dispatch",
		"current_offered_employee_id": testCourier2ID,
		"offer_expires_at":            offerExpiry,
		"payment_method":              "cod",
		"location":                    bson.M{"latitude": 30.0444, "longitude": 31.2357},
		"created_at":                  time.Now().UTC(),
		"updated_at":                  time.Now().UTC(),
	})

	// 13. POST /users/employee/jobs/{id}/accept & companion POST /users/employee/jobs/accept
	t.Run("POST_Users_Employee_Jobs_Accept", func(t *testing.T) {
		_ = FlushAllAuthRateLimits(ctx, cfg.RedisURI)
		urlPath := fmt.Sprintf("%s/api/v1/users/employee/jobs/%s/accept", cfg.GatewayURL, offerJobID1)

		// Negative: Anonymous -> 401
		respAnon, _, _ := PostJSON(ctx, urlPath, "", nil)
		if respAnon.StatusCode != http.StatusUnauthorized {
			t.Errorf("Expected 401 for anonymous accept, got %d", respAnon.StatusCode)
		}

		// Negative: Customer role forbidden -> 401/403
		respCust, _, _ := PostJSON(ctx, urlPath, custToken, nil)
		if respCust.StatusCode != http.StatusUnauthorized && respCust.StatusCode != http.StatusForbidden {
			t.Errorf("Expected 401/403 for customer accepting employee job, got %d", respCust.StatusCode)
		}

		// Happy Path: Courier 2 accepts offer via path parameter route -> 200 OK
		respGood, body, err := PostJSON(ctx, urlPath, courier2Token, nil)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK for courier accept, got %d: %s", respGood.StatusCode, string(body))
		}

		// Conflict Check: Accepting job that is no longer pending_dispatch -> 409 Conflict
		respConflict, _, err := PostJSON(ctx, urlPath, courier2Token, nil)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respConflict.StatusCode != http.StatusConflict {
			t.Errorf("Expected 409 Conflict for accepting already accepted job, got %d", respConflict.StatusCode)
		}

		// Companion Route Parity: Seed offer job for courier 3 and test POST /users/employee/jobs/accept
		offerJobIDComp := fmt.Sprintf("job_offer_comp_%d", ts)
		_ = db.SeedJob(ctx, bson.M{
			"_id":                         offerJobIDComp,
			"owner_id":                    testTenantID,
			"user_id":                     testCustID,
			"service_id":                  testServiceID,
			"status":                      "pending_dispatch",
			"current_offered_employee_id": testCourier3ID,
			"offer_expires_at":            offerExpiry,
			"payment_method":              "cod",
			"location":                    bson.M{"latitude": 30.0444, "longitude": 31.2357},
			"created_at":                  time.Now().UTC(),
			"updated_at":                  time.Now().UTC(),
		})

		compURL := fmt.Sprintf("%s/api/v1/users/employee/jobs/accept", cfg.GatewayURL)
		respComp, bodyComp, err := PostJSON(ctx, compURL, courier3Token, map[string]any{"job_id": offerJobIDComp})
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respComp.StatusCode != http.StatusOK {
			t.Errorf("Expected 200 OK for companion accept route, got %d: %s", respComp.StatusCode, string(bodyComp))
		}
	})

	// 14. POST /users/employee/jobs/{id}/decline & companion POST /users/employee/jobs/decline
	t.Run("POST_Users_Employee_Jobs_Decline", func(t *testing.T) {
		_ = FlushAllAuthRateLimits(ctx, cfg.RedisURI)
		offerJobID2 := fmt.Sprintf("job_offer_2_%d", ts)
		_ = db.SeedJob(ctx, bson.M{
			"_id":                         offerJobID2,
			"owner_id":                    testTenantID,
			"user_id":                     testCustID,
			"service_id":                  testServiceID,
			"status":                      "pending_dispatch",
			"current_offered_employee_id": testCourierID,
			"offer_expires_at":            offerExpiry,
			"payment_method":              "cod",
			"location":                    bson.M{"latitude": 30.0444, "longitude": 31.2357},
			"created_at":                  time.Now().UTC(),
			"updated_at":                  time.Now().UTC(),
		})

		urlPath := fmt.Sprintf("%s/api/v1/users/employee/jobs/%s/decline", cfg.GatewayURL, offerJobID2)

		// Negative: Anonymous -> 401
		respAnon, _, _ := PostJSON(ctx, urlPath, "", nil)
		if respAnon.StatusCode != http.StatusUnauthorized {
			t.Errorf("Expected 401 for anonymous decline, got %d", respAnon.StatusCode)
		}

		// Happy Path: Courier declines offer -> 200 OK
		respGood, body, err := PostJSON(ctx, urlPath, courierToken, nil)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK for courier decline, got %d: %s", respGood.StatusCode, string(body))
		}

		// Companion Route Parity: Seed third offer job and test POST /users/employee/jobs/decline
		offerJobIDDeclineComp := fmt.Sprintf("job_offer_dec_%d", ts)
		_ = db.SeedJob(ctx, bson.M{
			"_id":                         offerJobIDDeclineComp,
			"owner_id":                    testTenantID,
			"user_id":                     testCustID,
			"service_id":                  testServiceID,
			"status":                      "pending_dispatch",
			"current_offered_employee_id": testCourierID,
			"offer_expires_at":            offerExpiry,
			"payment_method":              "cod",
			"location":                    bson.M{"latitude": 30.0444, "longitude": 31.2357},
			"created_at":                  time.Now().UTC(),
			"updated_at":                  time.Now().UTC(),
		})

		compURL := fmt.Sprintf("%s/api/v1/users/employee/jobs/decline", cfg.GatewayURL)
		respComp, bodyComp, err := PostJSON(ctx, compURL, courierToken, map[string]any{"job_id": offerJobIDDeclineComp})
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respComp.StatusCode != http.StatusOK {
			t.Errorf("Expected 200 OK for companion decline route, got %d: %s", respComp.StatusCode, string(bodyComp))
		}
	})

	// 15. POST /users/employee/location
	t.Run("POST_Users_Employee_Location", func(t *testing.T) {
		url := fmt.Sprintf("%s/api/v1/users/employee/location", cfg.GatewayURL)

		// Negative: Customer role forbidden -> 403
		respCust, _, _ := PostJSON(ctx, url, custToken, map[string]any{
			"latitude":  30.0444,
			"longitude": 31.2357,
		})
		if respCust.StatusCode != http.StatusForbidden {
			t.Errorf("Expected 403 for customer updating courier location, got %d", respCust.StatusCode)
		}

		// Negative: Invalid coordinates -> 400
		respBadCoord, _, _ := PostJSON(ctx, url, courierToken, map[string]any{
			"latitude":  95.0,
			"longitude": 31.2357,
		})
		if respBadCoord.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for out-of-range coordinates, got %d", respBadCoord.StatusCode)
		}

		// Happy Path: Courier posts availability location -> 200 OK
		respGood, body, err := PostJSON(ctx, url, courierToken, map[string]any{
			"latitude":  30.0450,
			"longitude": 31.2360,
		})
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK for employee location update, got %d: %s", respGood.StatusCode, string(body))
		}
	})

	// 16. POST /users/jobs/location/update
	t.Run("POST_Users_Jobs_Location_Update", func(t *testing.T) {
		url := fmt.Sprintf("%s/api/v1/users/jobs/location/update", cfg.GatewayURL)

		// Create an active job created 10 minutes ago to ensure speed plausibility
		activeTrackingJobID := fmt.Sprintf("job_track_loc_%d", ts)
		_ = db.SeedJob(ctx, bson.M{
			"_id":            activeTrackingJobID,
			"owner_id":       testTenantID,
			"employee_id":    testCourierID,
			"user_id":        testCustID,
			"service_id":     testServiceID,
			"status":         "active",
			"payment_method": "cod",
			"location":       bson.M{"latitude": 30.0444, "longitude": 31.2357},
			"created_at":     time.Now().UTC().Add(-10 * time.Minute),
			"updated_at":     time.Now().UTC().Add(-10 * time.Minute),
		})

		// Negative: Customer role forbidden -> 401/403
		respCust, _, _ := PostJSON(ctx, url, custToken, map[string]any{
			"job_id":          activeTrackingJobID,
			"requester_token": custToken,
			"latitude":        30.0450,
			"longitude":       31.2360,
		})
		if respCust.StatusCode != http.StatusUnauthorized && respCust.StatusCode != http.StatusForbidden {
			t.Errorf("Expected 401/403 for customer updating job location, got %d", respCust.StatusCode)
		}

		// Negative: Missing job_id -> 400
		respNoJob, _, _ := PostJSON(ctx, url, courierToken, map[string]any{
			"requester_token": courierToken,
			"latitude":        30.0450,
			"longitude":       31.2360,
		})
		if respNoJob.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for missing job_id in location update, got %d", respNoJob.StatusCode)
		}

		// Happy Path: Courier posts tracking coordinates -> 200 OK
		respGood, body, err := PostJSON(ctx, url, courierToken, map[string]any{
			"job_id":          activeTrackingJobID,
			"requester_token": courierToken,
			"latitude":        30.0450,
			"longitude":       31.2360,
		})
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK for job location update, got %d: %s", respGood.StatusCode, string(body))
		}
	})

	// 17. GET /users/employees/available
	t.Run("GET_Users_Employees_Available", func(t *testing.T) {
		_ = FlushAllAuthRateLimits(ctx, cfg.RedisURI)
		url := fmt.Sprintf("%s/api/v1/users/employees/available", cfg.GatewayURL)

		// Negative: Anonymous -> 401
		respAnon, _, _ := GetJSON(ctx, url, "")
		if respAnon.StatusCode != http.StatusUnauthorized {
			t.Errorf("Expected 401 for anonymous available employees query, got %d", respAnon.StatusCode)
		}

		// Negative: IDOR check (owner querying different tenant) -> 403
		respIDOR, _, _ := GetJSON(ctx, url+"?tenant_id=unrelated_tenant", ownerToken)
		if respIDOR.StatusCode != http.StatusForbidden {
			t.Errorf("Expected 403 for IDOR tenant_id mismatch, got %d", respIDOR.StatusCode)
		}

		// Happy Path: Owner queries available employees for their tenant -> 200 OK
		respGood, body, err := GetJSON(ctx, url, ownerToken)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK for available employees, got %d: %s", respGood.StatusCode, string(body))
		}

		var parsed struct {
			Count     int              `json:"count"`
			TenantID  string           `json:"tenant_id"`
			Employees []map[string]any `json:"employees"`
		}
		if err := json.Unmarshal(body, &parsed); err != nil || parsed.Count < 1 {
			t.Errorf("Expected available employees schema with seeded courier, got count=%d, err=%v", parsed.Count, err)
		}
	})

	// =========================================================================
	// GROUP D: Wallet, Ledger, Config, Subscription (7 Endpoints)
	// =========================================================================

	// 18. GET /users/wallet
	t.Run("GET_Users_Wallet", func(t *testing.T) {
		url := fmt.Sprintf("%s/api/v1/users/wallet", cfg.GatewayURL)

		// Negative: Anonymous -> 400 or 401
		respAnon, _, _ := GetJSON(ctx, url, "")
		if respAnon.StatusCode != http.StatusBadRequest && respAnon.StatusCode != http.StatusUnauthorized {
			t.Errorf("Expected 400/401 for anonymous wallet query, got %d", respAnon.StatusCode)
		}

		// Negative: Customer role forbidden -> 401/403
		respCust, _, _ := GetJSON(ctx, url+"?tenant_token="+custToken, custToken)
		if respCust.StatusCode != http.StatusUnauthorized && respCust.StatusCode != http.StatusForbidden {
			t.Errorf("Expected 401/403 for customer querying wallet, got %d", respCust.StatusCode)
		}

		// Happy Path: Owner queries wallet balance -> 200 OK
		respGood, body, err := GetJSON(ctx, url+"?tenant_token="+ownerToken, ownerToken)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK for wallet query, got %d: %s", respGood.StatusCode, string(body))
		}

		var parsed struct {
			TotalBalance        float64 `json:"total_balance"`
			EscrowBalance       float64 `json:"escrow_balance"`
			WithdrawableBalance float64 `json:"withdrawable_balance"`
		}
		if err := json.Unmarshal(body, &parsed); err != nil || parsed.TotalBalance < 500.0 {
			t.Errorf("Unexpected wallet schema or balance: total=%.2f, err=%v", parsed.TotalBalance, err)
		}
	})

	// 19. POST /users/wallet/deposit
	t.Run("POST_Users_Wallet_Deposit", func(t *testing.T) {
		_ = FlushAllAuthRateLimits(ctx, cfg.RedisURI)
		url := fmt.Sprintf("%s/api/v1/users/wallet/deposit", cfg.GatewayURL)

		// Negative: Negative deposit amount -> 400
		respNeg, _, _ := PostJSON(ctx, url, ownerToken, map[string]any{
			"tenant_token": ownerToken,
			"amount":       -100.0,
		})
		if respNeg.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for negative deposit amount, got %d", respNeg.StatusCode)
		}

		// Negative: Sub-cent fractional amount that rounds to zero -> 400
		respSubCent, _, _ := PostJSON(ctx, url, ownerToken, map[string]any{
			"tenant_token": ownerToken,
			"amount":       0.001,
		})
		if respSubCent.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for sub-cent deposit, got %d", respSubCent.StatusCode)
		}

		// Negative: Exceeds 1,000,000 max deposit -> 400
		respTooLarge, _, _ := PostJSON(ctx, url, ownerToken, map[string]any{
			"tenant_token": ownerToken,
			"amount":       2_000_000.0,
		})
		if respTooLarge.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for oversized deposit, got %d", respTooLarge.StatusCode)
		}

		// Happy Path: Valid deposit of 100.00 -> 200 OK
		respGood, body, err := PostJSON(ctx, url, ownerToken, map[string]any{
			"tenant_token": ownerToken,
			"amount":       100.00,
		})
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK for deposit, got %d: %s", respGood.StatusCode, string(body))
		}
	})

	// 20. POST /users/wallet/payout/request
	t.Run("POST_Users_Wallet_Payout_Request", func(t *testing.T) {
		_ = FlushAllAuthRateLimits(ctx, cfg.RedisURI)
		url := fmt.Sprintf("%s/api/v1/users/wallet/payout/request", cfg.GatewayURL)

		// Negative: Anonymous -> 400 or 401
		respAnon, _, _ := PostJSON(ctx, url, "", map[string]any{"amount": 50.0})
		if respAnon.StatusCode != http.StatusBadRequest && respAnon.StatusCode != http.StatusUnauthorized {
			t.Errorf("Expected 400/401 for anonymous payout, got %d", respAnon.StatusCode)
		}

		// Negative: Exceeds balance -> 400
		respOver, _, _ := PostJSON(ctx, url, ownerToken, map[string]any{
			"amount":        999999.0,
			"payout_method": "bank_transfer",
			"account_info":  "EG1234567890",
		})
		if respOver.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for payout exceeding withdrawable balance, got %d", respOver.StatusCode)
		}

		// Negative: Missing payout method -> 400
		respNoMethod, _, _ := PostJSON(ctx, url, ownerToken, map[string]any{
			"amount": 50.0,
		})
		if respNoMethod.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for missing payout method, got %d", respNoMethod.StatusCode)
		}

		// Happy Path: Valid payout request of 50.00 -> 201 Created
		payoutPayload := map[string]any{
			"amount":        50.00,
			"payout_method": "bank_transfer",
			"account_info":  "IBAN: EG990001000000000123456789",
		}
		respGood, body, err := PostJSON(ctx, url, ownerToken, payoutPayload)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusCreated {
			t.Fatalf("Expected 201 Created for payout request, got %d: %s", respGood.StatusCode, string(body))
		}

		var parsed struct {
			ID           string  `json:"id"`
			TenantID     string  `json:"tenant_id"`
			Amount       float64 `json:"amount"`
			Status       string  `json:"status"`
			PayoutMethod string  `json:"payout_method"`
		}
		if err := json.Unmarshal(body, &parsed); err != nil || parsed.ID == "" || parsed.Amount != 50.0 {
			t.Errorf("Invalid payout response schema: %s", string(body))
		}
	})

	// 21. GET /users/wallet/payout/requests
	t.Run("GET_Users_Wallet_Payout_Requests", func(t *testing.T) {
		_ = FlushAllAuthRateLimits(ctx, cfg.RedisURI)
		url := fmt.Sprintf("%s/api/v1/users/wallet/payout/requests", cfg.GatewayURL)

		// Negative: Anonymous -> 400 or 401
		respAnon, _, _ := GetJSON(ctx, url, "")
		if respAnon.StatusCode != http.StatusBadRequest && respAnon.StatusCode != http.StatusUnauthorized {
			t.Errorf("Expected 400/401 for anonymous payout requests list, got %d", respAnon.StatusCode)
		}

		// Happy Path: Owner fetches historical payout requests -> 200 OK
		respGood, body, err := GetJSON(ctx, url, ownerToken)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK for payout requests list, got %d: %s", respGood.StatusCode, string(body))
		}

		var parsed []map[string]any
		if err := json.Unmarshal(body, &parsed); err != nil || len(parsed) < 1 {
			t.Errorf("Expected non-empty payout requests list, got len=%d, err=%v", len(parsed), err)
		}
	})

	// 22. GET /users/ledger
	t.Run("GET_Users_Ledger", func(t *testing.T) {
		_ = FlushAllAuthRateLimits(ctx, cfg.RedisURI)
		url := fmt.Sprintf("%s/api/v1/users/ledger", cfg.GatewayURL)

		// Negative: Anonymous -> 400 or 401
		respAnon, _, _ := GetJSON(ctx, url, "")
		if respAnon.StatusCode != http.StatusBadRequest && respAnon.StatusCode != http.StatusUnauthorized {
			t.Errorf("Expected 400/401 for anonymous ledger, got %d", respAnon.StatusCode)
		}

		// Happy Path: Owner queries financial ledger -> 200 OK
		respGood, body, err := GetJSON(ctx, url+"?tenant_token="+ownerToken, ownerToken)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK for ledger query, got %d: %s", respGood.StatusCode, string(body))
		}

		var parsed struct {
			Count   int   `json:"count"`
			Entries []any `json:"entries"`
			Limit   int   `json:"limit"`
			Offset  int   `json:"offset"`
		}
		if err := json.Unmarshal(body, &parsed); err != nil {
			t.Errorf("Failed to parse ledger schema: %v", err)
		}
	})

	// 23. GET /users/platform/config
	t.Run("GET_Users_Platform_Config", func(t *testing.T) {
		url := fmt.Sprintf("%s/api/v1/users/platform/config", cfg.GatewayURL)

		// Happy Path: Public retrieval -> 200 OK
		respGood, body, err := GetJSON(ctx, url, "")
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK for platform config, got %d: %s", respGood.StatusCode, string(body))
		}

		var parsed struct {
			CommissionRate float64 `json:"commission_rate"`
			FeeCap         float64 `json:"fee_cap"`
		}
		if err := json.Unmarshal(body, &parsed); err != nil {
			t.Errorf("Failed to parse platform config schema: %v", err)
		}
	})

	// 24. POST /users/subscription
	t.Run("POST_Users_Subscription", func(t *testing.T) {
		_ = FlushAllAuthRateLimits(ctx, cfg.RedisURI)
		url := fmt.Sprintf("%s/api/v1/users/subscription", cfg.GatewayURL)

		// Negative: Requester token does not match tenant -> 403 Forbidden
		respForbidden, _, _ := PostJSON(ctx, url, ownerToken, map[string]any{
			"tenant_id":    otherOwnerToken,
			"requester_id": ownerToken,
			"tier":         "free",
		})
		if respForbidden.StatusCode != http.StatusForbidden {
			t.Errorf("Expected 403 for mismatched tenant subscription update, got %d", respForbidden.StatusCode)
		}

		// Negative: Invalid tier -> 400
		respBadTier, _, _ := PostJSON(ctx, url, ownerToken, map[string]any{
			"tenant_id":    ownerToken,
			"requester_id": ownerToken,
			"tier":         "platinum_ultra",
		})
		if respBadTier.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for invalid subscription tier, got %d", respBadTier.StatusCode)
		}

		// Happy Path: Downgrade/switch to free tier -> 200 OK
		respFree, bodyFree, err := PostJSON(ctx, url, ownerToken, map[string]any{
			"tenant_id":    ownerToken,
			"requester_id": ownerToken,
			"tier":         "free",
		})
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respFree.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK for free subscription, got %d: %s", respFree.StatusCode, string(bodyFree))
		}

		// Happy Path: Upgrade request to paid tier -> 202 Accepted
		respPaid, bodyPaid, err := PostJSON(ctx, url, ownerToken, map[string]any{
			"tenant_id":    ownerToken,
			"requester_id": ownerToken,
			"tier":         "paid",
		})
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respPaid.StatusCode != http.StatusAccepted {
			t.Fatalf("Expected 202 Accepted for paid subscription request, got %d: %s", respPaid.StatusCode, string(bodyPaid))
		}

		// Restore paid subscription for downstream tests
		_, _ = db.client.Database("staging_user_db").Collection("subscriptions").UpdateOne(
			ctx,
			bson.M{"_id": testTenantID},
			bson.M{"$set": bson.M{"tier": "paid", "plan": "paid", "status": "active"}},
		)
	})

	// =========================================================================
	// GROUP E: Internal & Ratings (3 Endpoints)
	// =========================================================================

	// 25. GET /users/subscription/internal
	t.Run("GET_Users_Subscription_Internal", func(t *testing.T) {
		// External Gateway Edge Stripping Test: Calling through gateway edge strips X-Internal-Token -> 401
		gatewayURL := fmt.Sprintf("%s/api/v1/users/subscription/internal?tenant_id=%s", cfg.GatewayURL, testTenantID)
		respSpoof, _, err := DoRequestWithHeaders(ctx, http.MethodGet, gatewayURL, map[string]string{"X-Internal-Token": cfg.InternalToken}, nil)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respSpoof.StatusCode != http.StatusUnauthorized && respSpoof.StatusCode != http.StatusForbidden {
			t.Errorf("Expected 401/403 for internal endpoint accessed through gateway edge, got %d", respSpoof.StatusCode)
		}
	})

	// 26. POST /users/jobs/rate
	t.Run("POST_Users_Jobs_Rate", func(t *testing.T) {
		_ = FlushAllAuthRateLimits(ctx, cfg.RedisURI)
		url := fmt.Sprintf("%s/api/v1/users/jobs/rate", cfg.GatewayURL)

		// Negative: Stars out of range -> 400
		respBadStars, _, _ := PostJSON(ctx, url, ownerToken, map[string]any{
			"job_id":     bookedDeliveryJobID,
			"rated_by":   ownerToken,
			"rated_user": courierToken,
			"stars":      6,
		})
		if respBadStars.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for stars > 5, got %d", respBadStars.StatusCode)
		}

		// Negative: Comment exceeds 1000 characters -> 400
		respLongComment, _, _ := PostJSON(ctx, url, ownerToken, map[string]any{
			"job_id":     bookedDeliveryJobID,
			"rated_by":   ownerToken,
			"rated_user": courierToken,
			"stars":      5,
			"comment":    strings.Repeat("Great service! ", 100),
		})
		if respLongComment.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for comment > 1000 chars, got %d", respLongComment.StatusCode)
		}

		// Negative: Unrelated user rating -> 403 Forbidden
		respForbidden, _, _ := PostJSON(ctx, url, unauthCustToken, map[string]any{
			"job_id":     bookedDeliveryJobID,
			"rated_by":   unauthCustToken,
			"rated_user": courierToken,
			"stars":      5,
		})
		if respForbidden.StatusCode != http.StatusForbidden {
			t.Errorf("Expected 403 Forbidden for unauthorized rating attempt, got %d", respForbidden.StatusCode)
		}

		// Happy Path: Owner rates courier on completed delivery job -> 201 Created
		respGood, body, err := PostJSON(ctx, url, ownerToken, map[string]any{
			"job_id":     bookedDeliveryJobID,
			"rated_by":   ownerToken,
			"rated_user": courierToken,
			"stars":      5,
			"comment":    "Fast and reliable courier delivery.",
		})
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusCreated && respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 201 Created for job rating, got %d: %s", respGood.StatusCode, string(body))
		}
	})

	// 27. GET /users/ratings
	t.Run("GET_Users_Ratings", func(t *testing.T) {
		_ = FlushAllAuthRateLimits(ctx, cfg.RedisURI)
		url := fmt.Sprintf("%s/api/v1/users/ratings", cfg.GatewayURL)

		// Negative: Missing user_id -> 400
		respNoUser, _, _ := GetJSON(ctx, url, ownerToken)
		if respNoUser.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for missing user_id in ratings query, got %d", respNoUser.StatusCode)
		}

		// Happy Path: Query ratings for courier -> 200 OK
		respGood, body, err := GetJSON(ctx, fmt.Sprintf("%s?user_id=%s", url, testCourierID), ownerToken)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK for ratings query, got %d: %s", respGood.StatusCode, string(body))
		}

		var parsed struct {
			Ratings       []map[string]any `json:"ratings"`
			Count         int              `json:"count"`
			AverageRating float64          `json:"average_rating"`
		}
		if err := json.Unmarshal(body, &parsed); err != nil || parsed.Count < 1 || parsed.AverageRating != 5.0 {
			t.Errorf("Unexpected ratings schema: count=%d, avg=%.2f, err=%v", parsed.Count, parsed.AverageRating, err)
		}
	})

	// =========================================================================
	// GROUP F: Reconciliation Queue (4 Endpoints)
	// =========================================================================

	reconcileJobID := fmt.Sprintf("job_recon_%d", ts)
	actualCash := 50.0
	_ = db.SeedJob(ctx, bson.M{
		"_id":                   reconcileJobID,
		"owner_id":              testTenantID,
		"employee_id":           testCourierID,
		"user_id":               testCustID,
		"service_id":            testServiceID,
		"status":                "escrow_reconciliation_required",
		"payment_method":        "cod",
		"actual_cash_amount":    actualCash,
		"locked_escrow_amount":  50.0,
		"reconciliation_note":   "Discrepancy reported during cash drop-off",
		"escrow_failure_reason": "cash_mismatch",
		"location":              bson.M{"latitude": 30.0444, "longitude": 31.2357},
		"created_at":            time.Now().UTC(),
		"updated_at":            time.Now().UTC(),
	})

	// 28. GET /users/jobs/reconciliation-queue
	t.Run("GET_Users_Jobs_Reconciliation_Queue", func(t *testing.T) {
		_ = FlushAllAuthRateLimits(ctx, cfg.RedisURI)
		url := fmt.Sprintf("%s/api/v1/users/jobs/reconciliation-queue", cfg.GatewayURL)

		// Negative: Customer role forbidden -> 403
		respCust, _, _ := GetJSON(ctx, url, custToken)
		if respCust.StatusCode != http.StatusForbidden {
			t.Errorf("Expected 403 for customer querying reconciliation queue, got %d", respCust.StatusCode)
		}

		// Negative: IDOR check: explicit mismatch in owner_id -> 403
		respIDOR, _, _ := GetJSON(ctx, url+"?owner_id=other_owner", ownerToken)
		if respIDOR.StatusCode != http.StatusForbidden {
			t.Errorf("Expected 403 for IDOR owner mismatch, got %d", respIDOR.StatusCode)
		}

		// Happy Path: Owner queries reconciliation queue -> 200 OK
		respGood, body, err := GetJSON(ctx, url, ownerToken)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK for reconciliation queue, got %d: %s", respGood.StatusCode, string(body))
		}

		var parsed []map[string]any
		if err := json.Unmarshal(body, &parsed); err != nil || len(parsed) < 1 {
			t.Errorf("Expected non-empty reconciliation queue, got len=%d, err=%v", len(parsed), err)
		}
	})

	// 29. POST /users/jobs/reconciliation-resolve
	t.Run("POST_Users_Jobs_Reconciliation_Resolve", func(t *testing.T) {
		_ = FlushAllAuthRateLimits(ctx, cfg.RedisURI)
		url := fmt.Sprintf("%s/api/v1/users/jobs/reconciliation-resolve", cfg.GatewayURL)

		// Negative: Invalid decision value -> 400
		respBadDec, _, _ := PostJSON(ctx, url, ownerToken, map[string]any{
			"job_id":   reconcileJobID,
			"decision": "keep_both",
		})
		if respBadDec.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for invalid reconciliation decision, got %d", respBadDec.StatusCode)
		}

		// Negative: Non-existent job ID -> 404
		resp404, _, _ := PostJSON(ctx, url, ownerToken, map[string]any{
			"job_id":   "job-nonexistent-0000",
			"decision": "refund_to_customer",
		})
		if resp404.StatusCode != http.StatusNotFound {
			t.Errorf("Expected 404 for non-existent job ID, got %d", resp404.StatusCode)
		}

		// Happy Path: Owner resolves reconciliation -> 200 OK
		respGood, body, err := PostJSON(ctx, url, ownerToken, map[string]any{
			"job_id":   reconcileJobID,
			"decision": "refund_to_customer",
		})
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK for reconciliation resolution, got %d: %s", respGood.StatusCode, string(body))
		}

		// CAS Conflict Check: Attempting to resolve already resolved job -> 409 Conflict
		respConflict, _, err := PostJSON(ctx, url, ownerToken, map[string]any{
			"job_id":   reconcileJobID,
			"decision": "refund_to_customer",
		})
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respConflict.StatusCode != http.StatusConflict {
			t.Errorf("Expected 409 Conflict for resolving already settled job, got %d", respConflict.StatusCode)
		}
	})

	// Seed Disputed Job for Admin / Reviewer Endpoints
	adminReconcileJobID := fmt.Sprintf("job_admin_recon_%d", ts)
	_ = db.SeedJob(ctx, bson.M{
		"_id":                   adminReconcileJobID,
		"owner_id":              testTenantID,
		"employee_id":           testCourierID,
		"user_id":               testCustID,
		"service_id":            testServiceID,
		"status":                "escrow_reconciliation_required",
		"payment_method":        "cod",
		"actual_cash_amount":    50.0,
		"locked_escrow_amount":  50.0,
		"reconciliation_note":   "Customer and courier disputing cash amount",
		"escrow_failure_reason": "cash_mismatch",
		"location":              bson.M{"latitude": 30.0444, "longitude": 31.2357},
		"created_at":            time.Now().UTC(),
		"updated_at":            time.Now().UTC(),
	})

	// 30. GET /admin/reconciliation/queue & companion /users/admin/reconciliation/queue
	t.Run("GET_Admin_Reconciliation_Queue", func(t *testing.T) {
		consoleURL := fmt.Sprintf("%s/api/reconciliation/queue", cfg.ConsoleURL)

		// Negative: Missing reviewer token -> 401
		respBad, _, err := DoRequestWithHeaders(ctx, http.MethodGet, consoleURL, nil, nil)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respBad.StatusCode != http.StatusUnauthorized {
			t.Errorf("Expected 401 without reviewer token, got %d", respBad.StatusCode)
		}

		// Happy Path: Reviewer queries global reconciliation queue -> 200 OK
		respGood, body, err := DoRequestWithHeaders(ctx, http.MethodGet, consoleURL+"?page=1&limit=20", reviewerHeaders, nil)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK for admin reconciliation queue, got %d: %s", respGood.StatusCode, string(body))
		}

		var parsed struct {
			Jobs  []map[string]any `json:"jobs"`
			Total int              `json:"total"`
			Page  int              `json:"page"`
			Limit int              `json:"limit"`
		}
		if err := json.Unmarshal(body, &parsed); err != nil || parsed.Total < 1 {
			t.Errorf("Expected non-empty admin reconciliation queue, got total=%d, err=%v", parsed.Total, err)
		}
	})

	// 31. POST /admin/reconciliation/resolve & companion /users/admin/reconciliation/resolve
	t.Run("POST_Admin_Reconciliation_Resolve", func(t *testing.T) {
		consoleURL := fmt.Sprintf("%s/api/reconciliation/resolve", cfg.ConsoleURL)

		// Negative: Missing reason -> 400
		badReq := map[string]any{
			"job_id":   adminReconcileJobID,
			"decision": "release_to_employee",
		}
		badBytes, _ := json.Marshal(badReq)
		respBad, _, _ := DoRequestWithHeaders(ctx, http.MethodPost, consoleURL, reviewerHeaders, badBytes)
		if respBad.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for missing reason in admin resolve, got %d", respBad.StatusCode)
		}

		// Happy Path: Reviewer resolves dispute -> 200 OK
		goodReq := map[string]any{
			"job_id":   adminReconcileJobID,
			"decision": "release_to_employee",
			"reason":   "Courier provided valid delivery photo and digital signature verification.",
		}
		goodBytes, _ := json.Marshal(goodReq)
		respGood, body, err := DoRequestWithHeaders(ctx, http.MethodPost, consoleURL, reviewerHeaders, goodBytes)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK for admin dispute resolve, got %d: %s", respGood.StatusCode, string(body))
		}

		// CAS Conflict Check: Repeating resolve on already resolved job -> 409 Conflict
		respConflict, _, err := DoRequestWithHeaders(ctx, http.MethodPost, consoleURL, reviewerHeaders, goodBytes)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respConflict.StatusCode != http.StatusConflict {
			t.Errorf("Expected 409 Conflict when resolving already settled dispute, got %d", respConflict.StatusCode)
		}
	})

	// =========================================================================
	// GROUP G: Admin Subscriptions (3 Endpoints)
	// =========================================================================

	// 32. GET /admin/subscriptions & companions /users/admin/subscriptions, /admin/subscriptions/queue
	t.Run("GET_Admin_Subscriptions", func(t *testing.T) {
		consoleURL := fmt.Sprintf("%s/api/subscriptions", cfg.ConsoleURL)

		// Negative: Missing reviewer token -> 401
		respBad, _, err := DoRequestWithHeaders(ctx, http.MethodGet, consoleURL, nil, nil)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respBad.StatusCode != http.StatusUnauthorized {
			t.Errorf("Expected 401 without reviewer token, got %d", respBad.StatusCode)
		}

		// Happy Path: Reviewer queries global subscriptions list -> 200 OK
		respGood, body, err := DoRequestWithHeaders(ctx, http.MethodGet, consoleURL+"?page=1&limit=20", reviewerHeaders, nil)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK for admin subscriptions list, got %d: %s", respGood.StatusCode, string(body))
		}

		var parsed struct {
			Subscriptions []map[string]any `json:"subscriptions"`
			Total         int              `json:"total"`
		}
		if err := json.Unmarshal(body, &parsed); err != nil {
			t.Errorf("Failed to parse admin subscriptions response schema: %v", err)
		}
	})

	// 33. POST /admin/subscriptions/activate & companion /users/admin/subscriptions/activate
	t.Run("POST_Admin_Subscriptions_Activate", func(t *testing.T) {
		consoleURL := fmt.Sprintf("%s/api/subscriptions/activate", cfg.ConsoleURL)

		// Negative: Missing tenant_id and subscription_id -> 400
		respNoID, _, _ := DoRequestWithHeaders(ctx, http.MethodPost, consoleURL, reviewerHeaders, []byte("{}"))
		if respNoID.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for missing tenant_id in activate, got %d", respNoID.StatusCode)
		}

		// Happy Path: Reviewer activates paid subscription for adminSubTenantID -> 200 OK
		actReq := map[string]any{
			"tenant_id":     adminSubTenantID,
			"duration_days": 30,
		}
		actBytes, _ := json.Marshal(actReq)
		respGood, body, err := DoRequestWithHeaders(ctx, http.MethodPost, consoleURL, reviewerHeaders, actBytes)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK for subscription activation, got %d: %s", respGood.StatusCode, string(body))
		}

		// CAS Conflict Check: Attempting to activate an already active paid subscription -> 409 Conflict
		respConflict, _, err := DoRequestWithHeaders(ctx, http.MethodPost, consoleURL, reviewerHeaders, actBytes)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respConflict.StatusCode != http.StatusConflict {
			t.Errorf("Expected 409 Conflict for activating already active subscription, got %d", respConflict.StatusCode)
		}
	})

	// 34. POST /admin/subscriptions/revoke & companion /users/admin/subscriptions/revoke
	t.Run("POST_Admin_Subscriptions_Revoke", func(t *testing.T) {
		consoleURL := fmt.Sprintf("%s/api/subscriptions/revoke", cfg.ConsoleURL)

		// Negative: Missing reason -> 400
		badReq := map[string]any{
			"tenant_id": adminSubTenantID,
		}
		badBytes, _ := json.Marshal(badReq)
		respBad, _, _ := DoRequestWithHeaders(ctx, http.MethodPost, consoleURL, reviewerHeaders, badBytes)
		if respBad.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 for missing reason in revoke, got %d", respBad.StatusCode)
		}

		// Happy Path: Reviewer revokes subscription with mandatory reason -> 200 OK
		revokeReq := map[string]any{
			"tenant_id": adminSubTenantID,
			"reason":    "Terms of service violation regarding billing chargeback.",
		}
		revBytes, _ := json.Marshal(revokeReq)
		respGood, body, err := DoRequestWithHeaders(ctx, http.MethodPost, consoleURL, reviewerHeaders, revBytes)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respGood.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK for subscription revocation, got %d: %s", respGood.StatusCode, string(body))
		}

		// CAS Conflict Check: Revoking an already revoked subscription -> 409 Conflict
		respConflict, _, err := DoRequestWithHeaders(ctx, http.MethodPost, consoleURL, reviewerHeaders, revBytes)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		if respConflict.StatusCode != http.StatusConflict {
			t.Errorf("Expected 409 Conflict for revoking already revoked subscription, got %d", respConflict.StatusCode)
		}
	})
}
