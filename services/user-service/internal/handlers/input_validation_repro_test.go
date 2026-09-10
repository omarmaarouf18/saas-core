package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/project/shared/infra/jwtutil"
	"github.com/project/user-service/internal/models"
)

func TestRepro_Q20_CancelJob_UnboundedReason(t *testing.T) {
	u, s, _, cleanup := setupDispatchTestHarness(t)
	if u == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	ownerID := "tenant-q20-cancel"
	custID := "cust-q20-cancel"
	svcID := "svc-q20-cancel"

	s.CreateService(ctx, &models.Service{
		ID:               svcID,
		TenantID:         ownerID,
		Name:             "Delivery Service",
		Category:         "delivery",
		TenantBasePrice:  20.0,
		TenantPricePerKM: 2.0,
		Latitude:         30.0444,
		Longitude:        31.2357,
	})

	jobID := "job-q20-cancel"
	s.CreateJob(ctx, &models.Job{
		ID:            jobID,
		OwnerID:       ownerID,
		UserID:        custID,
		ServiceID:     svcID,
		Status:        models.JobStatusPendingDispatch,
		Location:      models.Location{Latitude: 30.0444, Longitude: 31.2357},
		CreatedAt:     time.Now().UTC(),
		PaymentMethod: "cod",
	})

	tokenCust, _ := jwtutil.GenerateToken(custID, "user", ownerID, "cust@test.com")

	// Huge reason: 10,000 characters
	hugeReason := strings.Repeat("A", 10000)
	body, _ := json.Marshal(map[string]any{
		"job_id":       jobID,
		"reason":       hugeReason,
		"requester_id": tokenCust,
	})

	req := httptest.NewRequest(http.MethodPost, "/users/jobs/cancel", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+tokenCust)
	rec := httptest.NewRecorder()

	u.CancelJob(rec, req)

	// Pre-fix: succeeds with 200 OK (unbounded string accepted and persisted)
	// Post-fix: must reject with 400 Bad Request
	if rec.Code == http.StatusOK {
		t.Errorf("REPRO CONFIRMED Q20: CancelJob accepted 10,000 character unbounded reason with 200 OK!")
	} else if rec.Code == http.StatusBadRequest {
		t.Logf("PASS: CancelJob rejected oversized reason with 400 Bad Request")
	} else {
		t.Logf("CancelJob returned status %d: %s", rec.Code, rec.Body.String())
	}
}

func TestRepro_Q20_RequestPayout_UnboundedAccountDetails(t *testing.T) {
	u, s, _, cleanup := setupDispatchTestHarness(t)
	if u == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	ownerID := "tenant-q20-payout"

	// Create wallet with balance
	_ = s.Deposit(ctx, ownerID, 1000.0)

	tokenOwner, _ := jwtutil.GenerateToken(ownerID, "owner", ownerID, "owner@test.com")

	// Huge account_details: 10,000 characters
	hugeDetails := strings.Repeat("X", 10000)
	body, _ := json.Marshal(map[string]any{
		"amount":          100.0,
		"payout_method":   "bank_transfer",
		"account_details": hugeDetails,
	})

	req := httptest.NewRequest(http.MethodPost, "/users/wallet/payout/request", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+tokenOwner)
	rec := httptest.NewRecorder()

	u.RequestPayout(rec, req)

	// Pre-fix: succeeds with 201 Created (unbounded string accepted and persisted)
	// Post-fix: must reject with 400 Bad Request
	if rec.Code == http.StatusCreated {
		t.Errorf("REPRO CONFIRMED Q20: RequestPayout accepted 10,000 character unbounded account_details with 201 Created!")
	} else if rec.Code == http.StatusBadRequest {
		t.Logf("PASS: RequestPayout rejected oversized account_details with 400 Bad Request")
	} else {
		t.Logf("RequestPayout returned status %d: %s", rec.Code, rec.Body.String())
	}
}

func TestRepro_Q21_CreateService_NegativeCoverageRadius(t *testing.T) {
	u, _, _, cleanup := setupDispatchTestHarness(t)
	if u == nil {
		return
	}
	defer cleanup()

	ownerID := "tenant-q21-svc"
	tokenOwner, _ := jwtutil.GenerateToken(ownerID, "owner", ownerID, "owner@test.com")

	body, _ := json.Marshal(map[string]any{
		"name":                "Negative Radius Express",
		"category":            "delivery",
		"tenant_base_price":   15.0,
		"tenant_price_per_km": 2.5,
		"coverage_radius_km":  -25.0, // NEGATIVE!
		"latitude":            30.0444,
		"longitude":           31.2357,
	})

	req := httptest.NewRequest(http.MethodPost, "/users/services", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+tokenOwner)
	rec := httptest.NewRecorder()

	u.CreateService(rec, req)

	// Pre-fix: returns 201 Created (negative coverage_radius_km accepted at create)
	// Post-fix: must return 400 Bad Request
	if rec.Code == http.StatusCreated {
		t.Errorf("REPRO CONFIRMED Q21: CreateService accepted negative coverage_radius_km (-25.0) with 201 Created!")
	} else if rec.Code == http.StatusBadRequest {
		t.Logf("PASS: CreateService rejected negative coverage_radius_km with 400 Bad Request")
	} else {
		t.Logf("CreateService returned status %d: %s", rec.Code, rec.Body.String())
	}
}

func TestRepro_Q21_RequestPayout_ArbitraryPayoutMethod(t *testing.T) {
	u, s, _, cleanup := setupDispatchTestHarness(t)
	if u == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	ownerID := "tenant-q21-method"
	_ = s.Deposit(ctx, ownerID, 500.0)

	tokenOwner, _ := jwtutil.GenerateToken(ownerID, "owner", ownerID, "owner@test.com")

	body, _ := json.Marshal(map[string]any{
		"amount":          50.0,
		"payout_method":   "arbitrary_junk_crypto",
		"account_details": "valid-details",
	})

	req := httptest.NewRequest(http.MethodPost, "/users/wallet/payout/request", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+tokenOwner)
	rec := httptest.NewRecorder()

	u.RequestPayout(rec, req)

	// Pre-fix: succeeds with 201 Created (arbitrary junk method accepted)
	// Post-fix: must return 400 Bad Request
	if rec.Code == http.StatusCreated {
		t.Errorf("REPRO CONFIRMED Q21: RequestPayout accepted arbitrary payout_method 'arbitrary_junk_crypto' with 201 Created!")
	} else if rec.Code == http.StatusBadRequest {
		t.Logf("PASS: RequestPayout rejected invalid payout_method with 400 Bad Request")
	} else {
		t.Logf("RequestPayout returned status %d: %s", rec.Code, rec.Body.String())
	}
}

func TestRepro_Q21_TrackJob_ArbitraryPaymentMethod(t *testing.T) {
	u, s, _, cleanup := setupDispatchTestHarness(t)
	if u == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	ownerID := "tenant-q21-paym"
	custID := "cust-q21-paym"
	svcID := "svc-q21-paym"

	s.CreateService(ctx, &models.Service{
		ID:               svcID,
		TenantID:         ownerID,
		Name:             "Delivery",
		Category:         "delivery",
		TenantBasePrice:  20.0,
		TenantPricePerKM: 2.0,
		Latitude:         30.0444,
		Longitude:        31.2357,
	})

	tokenCust, _ := jwtutil.GenerateToken(custID, "user", ownerID, "cust@test.com")

	body, _ := json.Marshal(map[string]any{
		"service_id":     svcID,
		"user_id":        tokenCust,
		"payment_method": "unsupported_foreign_method",
		"location":       map[string]float64{"latitude": 30.0444, "longitude": 31.2357},
	})

	req := httptest.NewRequest(http.MethodPost, "/users/jobs/track", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+tokenCust)
	rec := httptest.NewRecorder()

	u.TrackJob(rec, req)

	// In test bypass mode, pre-fix accepted any non-cod string.
	// Post-fix: must reject with 400 Bad Request because it's not in {"cod", "wallet"}.
	t.Logf("TrackJob response: %d %s", rec.Code, rec.Body.String())
	if rec.Code == http.StatusCreated {
		t.Errorf("REPRO CONFIRMED Q21: TrackJob accepted arbitrary payment_method 'unsupported_foreign_method' with 201 Created!")
	} else if rec.Code == http.StatusBadRequest {
		t.Logf("PASS: TrackJob rejected invalid payment_method with 400 Bad Request")
	} else {
		t.Logf("TrackJob returned status %d: %s", rec.Code, rec.Body.String())
	}
}

func TestRepro_Q19_WalletDeposit_UnboundedBodyRead(t *testing.T) {
	u, _, _, cleanup := setupDispatchTestHarness(t)
	if u == nil {
		return
	}
	defer cleanup()

	ownerID := "tenant-q19-deposit"
	tokenOwner, _ := jwtutil.GenerateToken(ownerID, "owner", ownerID, "owner@test.com")

	// 2 MB payload (oversized)
	hugePayload := fmt.Sprintf(`{"tenant_token":%q,"amount":100.0,"padding":%q}`, tokenOwner, strings.Repeat("B", 2*1024*1024))

	req := httptest.NewRequest(http.MethodPost, "/users/wallet/deposit", strings.NewReader(hugePayload))
	req.Header.Set("Authorization", "Bearer "+tokenOwner)
	rec := httptest.NewRecorder()

	u.WalletDeposit(rec, req)

	// Pre-fix: reads full 2MB and returns 200 OK
	// Post-fix: capped at 1MB, returns 400 Bad Request (failed to read body or body too large)
	if rec.Code == http.StatusOK {
		t.Errorf("REPRO CONFIRMED Q19: WalletDeposit read and processed 2MB unbounded payload with 200 OK!")
	} else if rec.Code == http.StatusBadRequest || rec.Code == http.StatusRequestEntityTooLarge {
		t.Logf("PASS: WalletDeposit rejected 2MB oversized payload with status %d", rec.Code)
	} else {
		t.Logf("WalletDeposit returned status %d: %s", rec.Code, rec.Body.String())
	}
}
