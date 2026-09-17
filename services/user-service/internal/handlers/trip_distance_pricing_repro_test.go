package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"math"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/project/shared/infra/jwtutil"
	"github.com/project/user-service/internal/models"
)

// TestRepro_PricingFormulaUsesCourierDistanceInsteadOfTripDistance reproduces the
// CRITICAL money-correctness bug where pricing is computed from courier proximity
// instead of pickup -> destination trip distance.
func TestRepro_PricingFormulaUsesCourierDistanceInsteadOfTripDistance(t *testing.T) {
	// Service: Base fee = $20.00, Rate = $3.00 / km
	basePrice := 20.0
	pricePerKM := 3.0

	// Locations:
	// Pickup (A): Cairo Downtown (30.0444, 31.2357)
	pickupCairo := models.Location{Latitude: 30.0444, Longitude: 31.2357}
	// Destination (B): Alexandria Library (31.2089, 29.9092) -> ~181.32 km actual trip
	destAlexandria := models.Location{Latitude: 31.2089, Longitude: 29.9092}
	actualTripDist := haversineKm(pickupCairo.Latitude, pickupCairo.Longitude, destAlexandria.Latitude, destAlexandria.Longitude)
	expectedTripPrice := math.Round((basePrice+(actualTripDist*pricePerKM))*100) / 100

	// Courier is stationed very close to customer at pickup: ~0.10 km (100 meters away)
	courierCloseCairo := models.Location{Latitude: 30.0453, Longitude: 31.2357}
	courierProximityDist := haversineKm(pickupCairo.Latitude, pickupCairo.Longitude, courierCloseCairo.Latitude, courierCloseCairo.Longitude)
	buggyCourierPrice := math.Round((basePrice+(courierProximityDist*pricePerKM))*100) / 100

	t.Logf("=== REPRO PROOF PARAMETERS (Long Trip, Close Courier) ===")
	t.Logf("Pickup: Cairo (%.4f, %.4f)", pickupCairo.Latitude, pickupCairo.Longitude)
	t.Logf("Destination: Alexandria (%.4f, %.4f)", destAlexandria.Latitude, destAlexandria.Longitude)
	t.Logf("Actual Trip Distance: %.2f km -> Expected Trip Price: $%.2f", actualTripDist, expectedTripPrice)
	t.Logf("Courier Location: Cairo Downtown (%.4f, %.4f)", courierCloseCairo.Latitude, courierCloseCairo.Longitude)
	t.Logf("Courier Proximity Distance: %.2f km -> Buggy Courier-Proximity Price: $%.2f", courierProximityDist, buggyCourierPrice)

	// -------------------------------------------------------------------------
	// Repro Scenario 1: Direct Employee Assignment at Booking Time
	// -------------------------------------------------------------------------
	t.Run("DirectAssignment_PricesTripNotCourierProximity", func(t *testing.T) {
		u, s, _, cleanup := setupDispatchTestHarness(t)
		if u == nil {
			return
		}
		defer cleanup()

		ctx := context.Background()
		ownerID := "repro-owner-direct"
		empID := "emp-under-repro-owner-direct"
		custID := "repro-cust-direct"
		svcID := "svc-repro-direct"

		_ = s.UpsertSubscription(ctx, &models.Subscription{
			ID: "sub-" + ownerID, TenantID: ownerID, Tier: models.PlanPaid, StartedAt: time.Now().UTC(),
		})
		s.CreateService(ctx, &models.Service{
			ID: svcID, TenantID: ownerID, Name: "Transport Service", Category: "transport",
			TenantBasePrice: basePrice, TenantPricePerKM: pricePerKM, Latitude: 30.0444, Longitude: 31.2357,
		})
		_ = s.UpsertEmployeeLocation(ctx, &models.EmployeeLocation{
			TenantID: ownerID, EmployeeID: empID, Latitude: courierCloseCairo.Latitude, Longitude: courierCloseCairo.Longitude, UpdatedAt: time.Now().UTC(),
		})

		tokenCust, _ := jwtutil.GenerateToken(custID, "user", ownerID, "cust@repro.com")
		tokenEmp, _ := jwtutil.GenerateToken(empID, "employee", ownerID, "emp@repro.com")

		body, _ := json.Marshal(map[string]any{
			"service_id":     svcID,
			"user_id":        tokenCust,
			"employee_id":    tokenEmp,
			"payment_method": "cod",
			"location":       pickupCairo,
			"destination":    destAlexandria,
		})
		req := httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(body))
		rec := httptest.NewRecorder()
		u.TrackJob(rec, req)

		if rec.Code != http.StatusCreated {
			t.Fatalf("Expected 201 Created on TrackJob, got %d: %s", rec.Code, rec.Body.String())
		}
		var resp map[string]any
		_ = json.Unmarshal(rec.Body.Bytes(), &resp)
		jobData := resp["job"].(map[string]any)
		suggestedPrice := jobData["suggested_price"].(float64)

		t.Logf("[Direct Assignment] Suggested Price: $%.2f (Expected Trip Price: $%.2f, Buggy Courier Price: $%.2f)",
			suggestedPrice, expectedTripPrice, buggyCourierPrice)

		if math.Abs(suggestedPrice-expectedTripPrice) > 0.05 {
			t.Errorf("CRITICAL BUG REPRODUCED: TrackJob priced job at $%.2f (courier-to-customer proximity), expected $%.2f (pickup-to-destination trip distance)!",
				suggestedPrice, expectedTripPrice)
		}
	})

	// -------------------------------------------------------------------------
	// Repro Scenario 2: Cascade Dispatch Acceptance Pricing
	// -------------------------------------------------------------------------
	t.Run("CascadeAccept_PricesTripNotCourierProximity", func(t *testing.T) {
		u, s, _, cleanup := setupDispatchTestHarness(t)
		if u == nil {
			return
		}
		defer cleanup()

		ctx := context.Background()
		ownerID := "repro-owner-cascade"
		empID := "emp-under-repro-owner-cascade"
		custID := "repro-cust-cascade"
		svcID := "svc-repro-cascade"

		_ = s.UpsertSubscription(ctx, &models.Subscription{
			ID: "sub-" + ownerID, TenantID: ownerID, Tier: models.PlanPaid, StartedAt: time.Now().UTC(),
		})
		s.CreateService(ctx, &models.Service{
			ID: svcID, TenantID: ownerID, Name: "Transport Service", Category: "transport",
			TenantBasePrice: basePrice, TenantPricePerKM: pricePerKM, Latitude: 30.0444, Longitude: 31.2357,
		})
		_ = s.UpsertEmployeeLocation(ctx, &models.EmployeeLocation{
			TenantID: ownerID, EmployeeID: empID, Latitude: courierCloseCairo.Latitude, Longitude: courierCloseCairo.Longitude, UpdatedAt: time.Now().UTC(),
		})

		tokenCust, _ := jwtutil.GenerateToken(custID, "user", ownerID, "cust@repro.com")
		tokenEmp, _ := jwtutil.GenerateToken(empID, "employee", ownerID, "emp@repro.com")

		body, _ := json.Marshal(map[string]any{
			"service_id":     svcID,
			"user_id":        tokenCust,
			"payment_method": "cod",
			"location":       pickupCairo,
			"destination":    destAlexandria,
		})
		req := httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(body))
		rec := httptest.NewRecorder()
		u.TrackJob(rec, req)

		if rec.Code != http.StatusCreated {
			t.Fatalf("Expected 201 Created on auto-dispatch TrackJob, got %d: %s", rec.Code, rec.Body.String())
		}
		var resp map[string]any
		_ = json.Unmarshal(rec.Body.Bytes(), &resp)
		jobData := resp["job"].(map[string]any)
		jobID := jobData["id"].(string)

		acceptReq := httptest.NewRequest("POST", fmt.Sprintf("/users/employee/jobs/%s/accept", jobID), nil)
		acceptReq.Header.Set("Authorization", "Bearer "+tokenEmp)
		acceptRec := httptest.NewRecorder()
		u.AcceptJobOffer(acceptRec, acceptReq)

		if acceptRec.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK on AcceptJobOffer, got %d: %s", acceptRec.Code, acceptRec.Body.String())
		}
		var acceptResp map[string]any
		_ = json.Unmarshal(acceptRec.Body.Bytes(), &acceptResp)
		acceptedJob := acceptResp["job"].(map[string]any)
		suggestedPrice := acceptedJob["suggested_price"].(float64)

		t.Logf("[Cascade Accept] Suggested Price: $%.2f (Expected Trip Price: $%.2f, Buggy Courier Price: $%.2f)",
			suggestedPrice, expectedTripPrice, buggyCourierPrice)

		if math.Abs(suggestedPrice-expectedTripPrice) > 0.05 {
			t.Errorf("CRITICAL BUG REPRODUCED: AcceptJobOffer priced job at $%.2f (courier-to-customer proximity), expected $%.2f (pickup-to-destination trip distance)!",
				suggestedPrice, expectedTripPrice)
		}
	})

	// -------------------------------------------------------------------------
	// Repro Scenario 3: Mirror Case (Short Trip, Far Courier)
	// -------------------------------------------------------------------------
	t.Run("MirrorCase_ShortTrip_DistantCourier_PricesTripNotCourierDistance", func(t *testing.T) {
		u, s, _, cleanup := setupDispatchTestHarness(t)
		if u == nil {
			return
		}
		defer cleanup()

		ctx := context.Background()
		ownerID := "repro-owner-mirror"
		empID := "emp-under-repro-owner-mirror"
		custID := "repro-cust-mirror"
		svcID := "svc-repro-mirror"

		_ = s.UpsertSubscription(ctx, &models.Subscription{
			ID: "sub-" + ownerID, TenantID: ownerID, Tier: models.PlanPaid, StartedAt: time.Now().UTC(),
		})
		s.CreateService(ctx, &models.Service{
			ID: svcID, TenantID: ownerID, Name: "Transport Service", Category: "transport",
			TenantBasePrice: basePrice, TenantPricePerKM: pricePerKM, Latitude: 30.0444, Longitude: 31.2357,
		})

		// Courier is far away in Alexandria (~181 km away)
		courierFarAlexandria := models.Location{Latitude: 31.2089, Longitude: 29.9092}
		_ = s.UpsertEmployeeLocation(ctx, &models.EmployeeLocation{
			TenantID: ownerID, EmployeeID: empID, Latitude: courierFarAlexandria.Latitude, Longitude: courierFarAlexandria.Longitude, UpdatedAt: time.Now().UTC(),
		})

		// Trip is very short: Cairo Downtown to Tahrir Museum (~0.43 km)
		destTahrirMuseum := models.Location{Latitude: 30.0478, Longitude: 31.2336}
		shortTripDist := haversineKm(pickupCairo.Latitude, pickupCairo.Longitude, destTahrirMuseum.Latitude, destTahrirMuseum.Longitude)
		expectedShortTripPrice := math.Round((basePrice+(shortTripDist*pricePerKM))*100) / 100

		courierDistance := haversineKm(pickupCairo.Latitude, pickupCairo.Longitude, courierFarAlexandria.Latitude, courierFarAlexandria.Longitude)
		buggyFarCourierPrice := math.Round((basePrice+(courierDistance*pricePerKM))*100) / 100

		t.Logf("=== MIRROR CASE PARAMETERS (Short Trip, Far Courier) ===")
		t.Logf("Pickup: Cairo (%.4f, %.4f)", pickupCairo.Latitude, pickupCairo.Longitude)
		t.Logf("Destination: Tahrir Museum (%.4f, %.4f)", destTahrirMuseum.Latitude, destTahrirMuseum.Longitude)
		t.Logf("Short Trip Distance: %.2f km -> Expected Price: $%.2f", shortTripDist, expectedShortTripPrice)
		t.Logf("Courier Far Location: Alexandria (%.4f, %.4f)", courierFarAlexandria.Latitude, courierFarAlexandria.Longitude)
		t.Logf("Courier Distance: %.2f km -> Buggy Courier Distance Price: $%.2f", courierDistance, buggyFarCourierPrice)

		tokenCust, _ := jwtutil.GenerateToken(custID, "user", ownerID, "cust@repro.com")
		tokenEmp, _ := jwtutil.GenerateToken(empID, "employee", ownerID, "emp@repro.com")

		body, _ := json.Marshal(map[string]any{
			"service_id":     svcID,
			"user_id":        tokenCust,
			"employee_id":    tokenEmp,
			"payment_method": "cod",
			"location":       pickupCairo,
			"destination":    destTahrirMuseum,
		})
		req := httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(body))
		rec := httptest.NewRecorder()
		u.TrackJob(rec, req)

		if rec.Code != http.StatusCreated {
			t.Fatalf("Expected 201 Created on TrackJob, got %d: %s", rec.Code, rec.Body.String())
		}
		var resp map[string]any
		_ = json.Unmarshal(rec.Body.Bytes(), &resp)
		jobData := resp["job"].(map[string]any)
		suggestedPrice := jobData["suggested_price"].(float64)

		t.Logf("[Mirror Case] Suggested Price: $%.2f (Expected Trip Price: $%.2f, Buggy Far Courier Price: $%.2f)",
			suggestedPrice, expectedShortTripPrice, buggyFarCourierPrice)

		if math.Abs(suggestedPrice-expectedShortTripPrice) > 0.05 {
			t.Errorf("CRITICAL BUG REPRODUCED: TrackJob priced job at $%.2f (charging customer for courier's 181km travel from Alexandria), expected $%.2f (actual 0.43km trip distance)!",
				suggestedPrice, expectedShortTripPrice)
		}
	})
}
