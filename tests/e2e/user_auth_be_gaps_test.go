package e2e

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"image"
	"image/color"
	"image/jpeg"
	"mime/multipart"
	"net/http"
	"strings"
	"testing"
	"time"

	"go.mongodb.org/mongo-driver/v2/bson"
)

// TestE2E_UserAuthBEGaps covers the 4 key backend gap areas identified for redesign A:
// 1. Service create persists all fields (coverage radius, working hours, schedule) + service photo upload/read.
// 2. Saved addresses with coordinates (lat/lng) + frequent_addresses derived string compatibility.
// 3. POST /users/jobs/pickup returns EmployeeJobResponse projection (hiding actual_cash_amount) and stable error codes.
// 4. 2FA login code resend for pending challenges generates a fresh code and stores it.
func TestE2E_UserAuthBEGaps(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	cfg := LoadConfig()
	db, err := ConnectStagingDB(ctx, cfg.MongoURI)
	if err != nil {
		t.Fatalf("Failed to connect to staging DB: %v", err)
	}
	defer db.Close(ctx)

	ts := time.Now().UnixNano()
	ownerTenantID := fmt.Sprintf("tenant_gaps_%d", ts)
	ownerID := ownerTenantID
	ownerEmail := fmt.Sprintf("owner_gaps_%d@staging.local", ts)

	courierID := fmt.Sprintf("cour_gaps_%d", ts)
	courierEmail := fmt.Sprintf("cour_gaps_%d@staging.local", ts)

	custID := fmt.Sprintf("cust_gaps_%d", ts)
	custEmail := fmt.Sprintf("cust_gaps_%d@staging.local", ts)

	serviceID := fmt.Sprintf("svc_gaps_%d", ts)
	jobID := fmt.Sprintf("job_gaps_%d", ts)

	cleanupEntities := func() {
		db.CleanupTestEntities(ctx,
			[]string{ownerTenantID},
			[]string{ownerID, courierID, custID},
		)
		_ = FlushAllAuthRateLimits(ctx, cfg.RedisURI)
	}
	defer cleanupEntities()
	cleanupEntities()

	// Seed staging entities
	if err := db.SeedTenantAndService(ctx, ownerTenantID, ownerID, serviceID, 20.0, 3.0, 30.0444, 31.2357); err != nil {
		t.Fatalf("seed tenant and service: %v", err)
	}
	if err := db.SeedCourier(ctx, ownerTenantID, courierID, courierEmail, 30.0444, 31.2357); err != nil {
		t.Fatalf("seed courier: %v", err)
	}
	if err := db.SeedCustomer(ctx, ownerTenantID, custID, custEmail); err != nil {
		t.Fatalf("seed customer: %v", err)
	}

	ownerToken, _ := cfg.GenerateJWT(ownerID, "owner", ownerTenantID, ownerEmail)
	courierToken, _ := cfg.GenerateJWT(courierID, "employee", ownerTenantID, courierEmail)
	custToken, _ := cfg.GenerateJWT(custID, "user", ownerTenantID, custEmail)

	// -------------------------------------------------------------------------
	// 1. Service Create Persists All Fields + Photo Upload & Read
	// -------------------------------------------------------------------------
	t.Run("ServiceCreate_PersistsAllFields_AndPhoto", func(t *testing.T) {
		createSvcURL := fmt.Sprintf("%s/api/v1/users/services", cfg.GatewayURL)
		createPayload := map[string]any{
			"name":                "Redesign A Express Laundry",
			"category":            "delivery",
			"tenant_base_price":   35.0,
			"tenant_price_per_km": 4.5,
			"latitude":            30.0500,
			"longitude":           31.2400,
			"coverage_radius_km":  12.5,
			"address":             "45 Nile Corniche, Maadi",
			"working_hours":       "08:00 - 22:00",
			"schedule": map[string]any{
				"monday": []map[string]string{
					{"start": "08:00", "end": "22:00"},
				},
				"tuesday": []map[string]string{
					{"start": "08:00", "end": "22:00"},
				},
			},
		}

		resp, respBytes, err := PostJSON(ctx, createSvcURL, ownerToken, createPayload)
		if err != nil {
			t.Fatalf("POST /users/services failed: %v", err)
		}
		if resp.StatusCode != http.StatusCreated && resp.StatusCode != http.StatusOK {
			t.Fatalf("expected 201/200 for service create, got %d: %s", resp.StatusCode, string(respBytes))
		}

		var created map[string]any
		if err := json.Unmarshal(respBytes, &created); err != nil {
			t.Fatalf("decode create response: %v", err)
		}
		svcObj, ok := created["service"].(map[string]any)
		if !ok {
			svcObj = created
		}
		newSvcID, ok := svcObj["id"].(string)
		if !ok || newSvcID == "" {
			t.Fatalf("expected created service id, got %v", created)
		}

		// Verify fields returned from creation
		if addr, _ := svcObj["address"].(string); addr != "45 Nile Corniche, Maadi" {
			t.Errorf("expected address '45 Nile Corniche, Maadi', got %q", addr)
		}
		if rad, _ := svcObj["coverage_radius_km"].(float64); rad != 12.5 {
			t.Errorf("expected coverage_radius_km 12.5, got %v", rad)
		}
		if wh, _ := svcObj["working_hours"].(string); wh != "08:00 - 22:00" {
			t.Errorf("expected working_hours '08:00 - 22:00', got %q", wh)
		}

		// Test Photo Upload via POST /users/services/{id}/photo
		photoUploadURL := fmt.Sprintf("%s/api/v1/users/services/%s/photo", cfg.GatewayURL, newSvcID)

		// Generate valid test JPEG bytes
		img := image.NewRGBA(image.Rect(0, 0, 16, 16))
		for x := 0; x < 16; x++ {
			for y := 0; y < 16; y++ {
				img.Set(x, y, color.RGBA{R: 120, G: 200, B: 80, A: 255})
			}
		}
		var imgBuf bytes.Buffer
		_ = jpeg.Encode(&imgBuf, img, &jpeg.Options{Quality: 85})

		var mpBuf bytes.Buffer
		mpWriter := multipart.NewWriter(&mpBuf)
		part, err := mpWriter.CreateFormFile("photo", "service.jpg")
		if err != nil {
			t.Fatalf("create form file: %v", err)
		}
		_, _ = part.Write(imgBuf.Bytes())
		_ = mpWriter.Close()

		uploadHeaders := map[string]string{
			"Content-Type":  mpWriter.FormDataContentType(),
			"Authorization": "Bearer " + ownerToken,
		}
		photoResp, photoRespBytes, err := DoRequestWithHeaders(ctx, http.MethodPost, photoUploadURL, uploadHeaders, mpBuf.Bytes())
		if err != nil {
			t.Fatalf("photo upload failed: %v", err)
		}
		if photoResp.StatusCode != http.StatusOK {
			t.Fatalf("expected 200 OK for photo upload, got %d: %s", photoResp.StatusCode, string(photoRespBytes))
		}

		var photoResult map[string]any
		_ = json.Unmarshal(photoRespBytes, &photoResult)
		photoKey, _ := photoResult["photo_url"].(string)
		if photoKey == "" || !strings.HasPrefix(photoKey, "services/") {
			t.Errorf("expected storage key starting with 'services/', got %q", photoKey)
		}

		// Authenticated photo read via GET /users/services/{id}/photo
		photoReadURL := fmt.Sprintf("%s/api/v1/users/services/%s/photo", cfg.GatewayURL, newSvcID)
		readResp, readBytes, err := GetJSON(ctx, photoReadURL, custToken)
		if err != nil {
			t.Fatalf("GET service photo failed: %v", err)
		}
		if readResp.StatusCode != http.StatusOK {
			t.Fatalf("expected 200 OK reading photo, got %d: %s", readResp.StatusCode, string(readBytes))
		}
		if ct := readResp.Header.Get("Content-Type"); !strings.Contains(ct, "image/jpeg") {
			t.Errorf("expected Content-Type image/jpeg, got %q", ct)
		}

		// GET /users/services returns every field
		getSvcURL := fmt.Sprintf("%s/api/v1/users/services", cfg.GatewayURL)
		getResp, getBytes, err := GetJSON(ctx, getSvcURL, ownerToken)
		if err != nil {
			t.Fatalf("GET /users/services failed: %v", err)
		}
		if getResp.StatusCode != http.StatusOK {
			t.Fatalf("expected 200 from GET /users/services, got %d: %s", getResp.StatusCode, string(getBytes))
		}
		var getObj map[string]any
		_ = json.Unmarshal(getBytes, &getObj)
		var svcList []any
		if arr, ok := getObj["services"].([]any); ok {
			svcList = arr
		} else {
			var directArr []any
			_ = json.Unmarshal(getBytes, &directArr)
			svcList = directArr
		}

		found := false
		for _, raw := range svcList {
			s, ok := raw.(map[string]any)
			if !ok {
				continue
			}
			if s["id"] == newSvcID {
				found = true
				if s["address"] != "45 Nile Corniche, Maadi" {
					t.Errorf("stored address mismatch: %v", s["address"])
				}
				if s["working_hours"] != "08:00 - 22:00" {
					t.Errorf("stored working_hours mismatch: %v", s["working_hours"])
				}
				if s["photo_url"] != photoKey {
					t.Errorf("stored photo_url = %v, want %v", s["photo_url"], photoKey)
				}
				break
			}
		}
		if !found {
			t.Errorf("service %s not found in GET /users/services list (returned %s)", newSvcID, string(getBytes))
		}
	})

	// -------------------------------------------------------------------------
	// 2. Saved Addresses with Coordinates + Frequent Addresses Derived Compatibility
	// -------------------------------------------------------------------------
	t.Run("SavedAddresses_WithCoordinates_AndLegacySync", func(t *testing.T) {
		authURL := fmt.Sprintf("%s/api/v1/auth/user", cfg.GatewayURL)

		updatePayload := map[string]any{
			"saved_addresses": []map[string]any{
				{
					"id":           "addr-home-e2e",
					"label":        "Home",
					"address":      "10 Tahrir Square, Cairo",
					"address_note": "Floor 3, Apt 12",
					"lat":          30.0444,
					"lng":          31.2357,
				},
				{
					"id":           "addr-office-e2e",
					"label":        "Work",
					"address":      "Building B2, Smart Village, Giza",
					"address_note": "Main entrance",
					"latitude":     30.0750,
					"longitude":    31.0200,
				},
			},
		}

		putResp, putBytes, err := PutJSON(ctx, authURL, custToken, updatePayload)
		if err != nil {
			t.Fatalf("PUT /auth/user failed: %v", err)
		}
		if putResp.StatusCode != http.StatusOK {
			t.Fatalf("expected 200 OK from PUT /auth/user, got %d: %s", putResp.StatusCode, string(putBytes))
		}

		getResp, getBytes, err := GetJSON(ctx, authURL, custToken)
		if err != nil {
			t.Fatalf("GET /auth/user failed: %v", err)
		}
		if getResp.StatusCode != http.StatusOK {
			t.Fatalf("expected 200 from GET /auth/user, got %d: %s", getResp.StatusCode, string(getBytes))
		}

		var userProfile struct {
			SavedAddresses []struct {
				ID          string  `json:"id"`
				Label       string  `json:"label"`
				Address     string  `json:"address"`
				AddressNote string  `json:"address_note"`
				Lat         float64 `json:"lat"`
				Lng         float64 `json:"lng"`
				Latitude    float64 `json:"latitude"`
				Longitude   float64 `json:"longitude"`
			} `json:"saved_addresses"`
			FrequentAddresses []string `json:"frequent_addresses"`
		}
		if err := json.Unmarshal(getBytes, &userProfile); err != nil {
			t.Fatalf("decode profile: %v", err)
		}

		if len(userProfile.SavedAddresses) != 2 {
			t.Fatalf("expected 2 saved_addresses, got %d", len(userProfile.SavedAddresses))
		}
		if userProfile.SavedAddresses[0].Label != "Home" || userProfile.SavedAddresses[0].Lat != 30.0444 {
			t.Errorf("saved address 0 mismatch: %+v", userProfile.SavedAddresses[0])
		}
		if userProfile.SavedAddresses[1].Label != "Work" || userProfile.SavedAddresses[1].Lng != 31.0200 {
			t.Errorf("saved address 1 mismatch: %+v", userProfile.SavedAddresses[1])
		}

		// Legacy frequent_addresses synchronization
		if len(userProfile.FrequentAddresses) != 2 {
			t.Fatalf("expected 2 frequent_addresses, got %d", len(userProfile.FrequentAddresses))
		}
		if userProfile.FrequentAddresses[0] != "10 Tahrir Square, Cairo" ||
			userProfile.FrequentAddresses[1] != "Building B2, Smart Village, Giza" {
			t.Errorf("unexpected frequent_addresses: %+v", userProfile.FrequentAddresses)
		}
	})

	// -------------------------------------------------------------------------
	// 3. POST /users/jobs/pickup returns EmployeeJobResponse DTO & Stable Error Codes
	// -------------------------------------------------------------------------
	t.Run("Pickup_EmployeeJobResponseDTO_AndStableErrorCodes", func(t *testing.T) {
		// Seed an active job in staging user DB
		actualCash := 180.50
		seedJobDoc := bson.M{
			"_id":                  jobID,
			"id":                   jobID,
			"tenant_id":            ownerTenantID,
			"owner_id":             ownerTenantID,
			"service_id":           serviceID,
			"user_id":              custID,
			"employee_id":          courierID,
			"status":               "active",
			"sub_status":           "heading_to_pickup",
			"payment_method":       "cash_on_delivery",
			"actual_cash_amount":   actualCash, // Owner-only reconciliation field!
			"locked_escrow_amount": 0.0,
			"location": bson.M{
				"latitude": 30.0444, "longitude": 31.2357, "address": "Origin Point",
			},
			"destination": bson.M{
				"latitude": 30.0500, "longitude": 31.2400, "address": "Destination Point",
			},
			"booked_distance": 5.0,
			"created_at":      time.Now().UTC(),
			"updated_at":      time.Now().UTC(),
		}
		if err := db.SeedJob(ctx, seedJobDoc); err != nil {
			t.Fatalf("seed job: %v", err)
		}

		pickupURL := fmt.Sprintf("%s/api/v1/users/jobs/pickup", cfg.GatewayURL)

		// 1. Successful pickup by assigned courier
		resp, respBytes, err := PostJSON(ctx, pickupURL, courierToken, map[string]any{
			"job_id": jobID,
		})
		if err != nil {
			t.Fatalf("POST /users/jobs/pickup failed: %v", err)
		}
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("expected 200 OK for pickup, got %d: %s", resp.StatusCode, string(respBytes))
		}

		var pickupResult map[string]any
		if err := json.Unmarshal(respBytes, &pickupResult); err != nil {
			t.Fatalf("decode pickup response: %v", err)
		}

		jobObj, ok := pickupResult["job"].(map[string]any)
		if !ok {
			t.Fatalf("expected 'job' object in response, got %v", pickupResult)
		}

		if subStatus, _ := jobObj["sub_status"].(string); subStatus != "picked_up" {
			t.Errorf("expected sub_status 'picked_up', got %q", subStatus)
		}

		// CRITICAL DTO GUARD: EmployeeJobResponse must NOT contain actual_cash_amount
		if val, exists := jobObj["actual_cash_amount"]; exists {
			t.Errorf("actual_cash_amount leaked to employee pickup response: %v", val)
		}

		// 2. Double pickup conflict returns stable error code
		resp2, respBytes2, err := PostJSON(ctx, pickupURL, courierToken, map[string]any{
			"job_id": jobID,
		})
		if err != nil {
			t.Fatalf("second pickup failed: %v", err)
		}
		if resp2.StatusCode != http.StatusConflict {
			t.Fatalf("expected 409 Conflict for double pickup, got %d: %s", resp2.StatusCode, string(respBytes2))
		}
		var errResp map[string]string
		_ = json.Unmarshal(respBytes2, &errResp)
		if errResp["code"] != "already_picked_up" || errResp["error"] != "job already picked up" {
			t.Errorf("expected code already_picked_up, got %+v", errResp)
		}
	})

	// -------------------------------------------------------------------------
	// 4. 2FA Login Code Resend
	// -------------------------------------------------------------------------
	t.Run("ResendLoginCode_PendingChallenge", func(t *testing.T) {
		loginUserEmail := fmt.Sprintf("login2fa_%d@staging.local", ts)
		loginUserID := fmt.Sprintf("usr_2fa_%d", ts)

		// Seed user with pending 2FA login challenge (otp_verified == false and otp_code present)
		authUsers := db.client.Database("staging_auth_db").Collection("users")
		_, err := authUsers.InsertOne(ctx, bson.M{
			"_id":                loginUserID,
			"email":              loginUserEmail,
			"username":           "login_user_" + loginUserID,
			"role":               "user",
			"tenant_id":          ownerTenantID,
			"is_active":          true,
			"account_status":     "active",
			"two_factor_enabled": true,
			"otp_verified":       false,
			"otp_code":           "old_encrypted_otp_dummy",
			"otp_expires_at":     time.Now().UTC().Add(10 * time.Minute),
			"created_at":         time.Now().UTC(),
			"updated_at":         time.Now().UTC(),
		})
		if err != nil {
			t.Fatalf("seed 2fa user: %v", err)
		}

		resendURL := fmt.Sprintf("%s/api/v1/auth/resend-otp", cfg.GatewayURL)
		resp, respBytes, err := PostJSON(ctx, resendURL, "", map[string]string{
			"email": loginUserEmail,
		})
		if err != nil {
			t.Fatalf("POST /auth/resend-otp failed: %v", err)
		}
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("expected 200 OK from resend-otp, got %d: %s", resp.StatusCode, string(respBytes))
		}

		// Verify in MongoDB that OTP was refreshed
		var updatedUser bson.M
		err = authUsers.FindOne(ctx, bson.M{"_id": loginUserID}).Decode(&updatedUser)
		if err != nil {
			t.Fatalf("find updated user: %v", err)
		}

		newOTP, _ := updatedUser["otp_code"].(string)
		if newOTP == "" || newOTP == "old_encrypted_otp_dummy" {
			t.Errorf("expected new OTP code stored for login challenge resend, got %q", newOTP)
		}
	})
}
