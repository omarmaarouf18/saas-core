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

// ---------------------------------------------------------------------------
// 1. TrackJob Creates PendingDispatch Without Pricing (Auto-Dispatch)
// ---------------------------------------------------------------------------

func TestCascade_TrackJob_CreatesPendingDispatchWithoutPricing(t *testing.T) {
	u, s, _, cleanup := setupDispatchTestHarness(t)
	if u == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	ownerID := "tenant-cascade-create"
	custID := "cust-cascade-create"
	empID := "emp-under-tenant-cascade-create"
	svcID := "svc-cascade-create"

	s.CreateService(ctx, &models.Service{
		ID:               svcID,
		TenantID:         ownerID,
		Name:             "Delivery Service",
		Category:         "delivery",
		TenantBasePrice:  25.0,
		TenantPricePerKM: 2.0,
		Latitude:         30.0444,
		Longitude:        31.2357,
	})

	// Seed fresh courier location (1 km away)
	now := time.Now().UTC()
	_ = s.UpsertEmployeeLocation(ctx, &models.EmployeeLocation{
		TenantID:   ownerID,
		EmployeeID: empID,
		Latitude:   30.0450,
		Longitude:  31.2360,
		UpdatedAt:  now,
	})

	tokenCust, _ := jwtutil.GenerateToken(custID, "user", ownerID, "cust@test.com")

	body, _ := json.Marshal(map[string]any{
		"service_id":     svcID,
		"user_id":        tokenCust,
		"payment_method": "cod",
		"location":       models.Location{Latitude: 30.0444, Longitude: 31.2357},
	})
	req := httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	u.TrackJob(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("Expected 201 Created for cascade dispatch job, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	var resp struct {
		Message string     `json:"message"`
		Job     models.Job `json:"job"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("Failed to decode response: %v", err)
	}

	if resp.Job.Status != models.JobStatusPendingDispatch {
		t.Errorf("Expected job status %q, got %q", models.JobStatusPendingDispatch, resp.Job.Status)
	}
	if resp.Job.EmployeeID != "" {
		t.Errorf("Expected job.EmployeeID to be empty before acceptance, got %q", resp.Job.EmployeeID)
	}
	if resp.Job.CurrentOfferedEmployeeID != empID {
		t.Errorf("Expected CurrentOfferedEmployeeID to be %q, got %q", empID, resp.Job.CurrentOfferedEmployeeID)
	}
	if resp.Job.OfferExpiresAt == nil {
		t.Errorf("Expected OfferExpiresAt to be set")
	} else if resp.Job.OfferExpiresAt.Before(now.Add(50 * time.Second)) {
		t.Errorf("Expected OfferExpiresAt to be ~60s in future, got %v", resp.Job.OfferExpiresAt)
	}
	// PRICING MUST NOT BE CALCULATED BEFORE ACCEPTANCE
	if resp.Job.BookedDistance != 0 {
		t.Errorf("Expected BookedDistance to be 0 before acceptance, got %v", resp.Job.BookedDistance)
	}
	if resp.Job.LockedEscrowAmount != 0 {
		t.Errorf("Expected LockedEscrowAmount to be 0 before acceptance, got %v", resp.Job.LockedEscrowAmount)
	}
}

// ---------------------------------------------------------------------------
// 2. Zero Couriers Available Transitions to Unavailable (NOT 422)
// ---------------------------------------------------------------------------

func TestCascade_TrackJob_ZeroCouriers_ReturnsUnavailableNot422(t *testing.T) {
	u, s, _, cleanup := setupDispatchTestHarness(t)
	if u == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	ownerID := "tenant-zero-couriers"
	custID := "cust-zero-couriers"
	svcID := "svc-zero-couriers"

	s.CreateService(ctx, &models.Service{
		ID:               svcID,
		TenantID:         ownerID,
		Name:             "Delivery Service",
		Category:         "delivery",
		TenantBasePrice:  25.0,
		TenantPricePerKM: 2.0,
		Latitude:         30.0444,
		Longitude:        31.2357,
	})

	tokenCust, _ := jwtutil.GenerateToken(custID, "user", ownerID, "cust@test.com")

	body, _ := json.Marshal(map[string]any{
		"service_id":     svcID,
		"user_id":        tokenCust,
		"payment_method": "cod",
		"location":       models.Location{Latitude: 30.0444, Longitude: 31.2357},
	})
	req := httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	u.TrackJob(rec, req)

	// MUST NOT be 422 UnprocessableEntity!
	if rec.Code != http.StatusCreated {
		t.Fatalf("Expected 201 Created with unavailable job, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	var resp struct {
		Job models.Job `json:"job"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &resp)

	if resp.Job.Status != models.JobStatusUnavailable {
		t.Errorf("Expected job status %q, got %q", models.JobStatusUnavailable, resp.Job.Status)
	}
	if resp.Job.BookedDistance != 0 {
		t.Errorf("Expected BookedDistance to be 0, got %v", resp.Job.BookedDistance)
	}
}

// ---------------------------------------------------------------------------
// 3. Sequential Cascade: Decline Advances to Next Nearest, Pricing at Accept
// ---------------------------------------------------------------------------

func TestCascade_SequentialOffers_DeclineAdvancesAndPricingAtAccept(t *testing.T) {
	u, s, _, cleanup := setupDispatchTestHarness(t)
	if u == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	ownerID := "tenant-cascade-adv"
	custID := "cust-cascade-adv"
	empClose := "emp-close-under-tenant-cascade-adv"
	empFar := "emp-far-under-tenant-cascade-adv"
	svcID := "svc-cascade-adv"

	s.CreateService(ctx, &models.Service{
		ID:               svcID,
		TenantID:         ownerID,
		Name:             "Transport Service",
		Category:         "transport",
		TenantBasePrice:  20.0,
		TenantPricePerKM: 5.0,
		Latitude:         30.0000,
		Longitude:        31.0000,
	})

	now := time.Now().UTC()
	// Customer at (30.0, 31.0)
	custLoc := models.Location{Latitude: 30.0000, Longitude: 31.0000}

	// empClose is ~1.11 km away (0.01 deg lat difference)
	_ = s.UpsertEmployeeLocation(ctx, &models.EmployeeLocation{
		TenantID:   ownerID,
		EmployeeID: empClose,
		Latitude:   30.0100,
		Longitude:  31.0000,
		UpdatedAt:  now,
	})

	// empFar is ~5.55 km away (0.05 deg lat difference)
	_ = s.UpsertEmployeeLocation(ctx, &models.EmployeeLocation{
		TenantID:   ownerID,
		EmployeeID: empFar,
		Latitude:   30.0500,
		Longitude:  31.0000,
		UpdatedAt:  now,
	})

	tokenCust, _ := jwtutil.GenerateToken(custID, "user", ownerID, "cust@test.com")
	tokenClose, _ := jwtutil.GenerateToken(empClose, "employee", ownerID, "close@test.com")
	tokenFar, _ := jwtutil.GenerateToken(empFar, "employee", ownerID, "far@test.com")

	// 1. Customer creates job without employee_id
	body, _ := json.Marshal(map[string]any{
		"service_id":     svcID,
		"user_id":        tokenCust,
		"payment_method": "cod",
		"location":       custLoc,
	})
	req := httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	u.TrackJob(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("TrackJob failed: %d, body: %s", rec.Code, rec.Body.String())
	}
	var trackResp struct {
		Job models.Job `json:"job"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &trackResp)
	jobID := trackResp.Job.ID

	// First offer must go to empClose (nearest)
	if trackResp.Job.CurrentOfferedEmployeeID != empClose {
		t.Fatalf("Expected first offer to go to nearest courier %q, got %q", empClose, trackResp.Job.CurrentOfferedEmployeeID)
	}

	// 2. empClose declines the offer
	declineBody, _ := json.Marshal(map[string]any{
		"job_id": jobID,
	})
	declineReq := httptest.NewRequest("POST", fmt.Sprintf("/users/employee/jobs/%s/decline", jobID), bytes.NewReader(declineBody))
	declineReq.Header.Set("Authorization", "Bearer "+tokenClose)
	declineRec := httptest.NewRecorder()
	u.DeclineJobOffer(declineRec, declineReq)

	if declineRec.Code != http.StatusOK {
		t.Fatalf("DeclineJobOffer failed: %d, body: %s", declineRec.Code, declineRec.Body.String())
	}

	// 3. Verify job advanced to empFar
	jobAfterDecline := s.GetJob(ctx, jobID)
	if jobAfterDecline == nil {
		t.Fatalf("Job %s not found", jobID)
	}
	if jobAfterDecline.Status != models.JobStatusPendingDispatch {
		t.Errorf("Expected status pending_dispatch after decline, got %q", jobAfterDecline.Status)
	}
	if jobAfterDecline.CurrentOfferedEmployeeID != empFar {
		t.Fatalf("Expected offer to cascade to next nearest %q, got %q", empFar, jobAfterDecline.CurrentOfferedEmployeeID)
	}
	// Distance and pricing STILL not calculated!
	if jobAfterDecline.BookedDistance != 0 {
		t.Errorf("Expected BookedDistance still 0, got %v", jobAfterDecline.BookedDistance)
	}

	// 4. empFar accepts the offer!
	acceptBody, _ := json.Marshal(map[string]any{
		"job_id": jobID,
	})
	acceptReq := httptest.NewRequest("POST", fmt.Sprintf("/users/employee/jobs/%s/accept", jobID), bytes.NewReader(acceptBody))
	acceptReq.Header.Set("Authorization", "Bearer "+tokenFar)
	acceptRec := httptest.NewRecorder()
	u.AcceptJobOffer(acceptRec, acceptReq)

	if acceptRec.Code != http.StatusOK {
		t.Fatalf("AcceptJobOffer failed: %d, body: %s", acceptRec.Code, acceptRec.Body.String())
	}

	// 5. Verify final accepted state & pricing derives from empFar (NOT empClose)
	jobFinal := s.GetJob(ctx, jobID)
	if jobFinal.EmployeeID != empFar {
		t.Errorf("Expected assigned EmployeeID to be %q, got %q", empFar, jobFinal.EmployeeID)
	}
	if jobFinal.Status != models.JobStatusAwaitingPriceResponse {
		t.Errorf("Expected transport job status to be awaiting_price_response, got %q", jobFinal.Status)
	}
	expectedDistFar := haversineKm(custLoc.Latitude, custLoc.Longitude, 30.0500, 31.0000)
	if math.Abs(jobFinal.BookedDistance-expectedDistFar) > 0.01 {
		t.Errorf("Expected BookedDistance to be based on empFar (~%.3f km), got %.3f km", expectedDistFar, jobFinal.BookedDistance)
	}
	expectedPriceFar := math.Round((20.0+(expectedDistFar*5.0))*100) / 100
	if math.Abs(jobFinal.SuggestedPrice-expectedPriceFar) > 0.02 {
		t.Errorf("Expected SuggestedPrice based on empFar (~%.2f), got %.2f", expectedPriceFar, jobFinal.SuggestedPrice)
	}
}

// ---------------------------------------------------------------------------
// 4. Race 1: Two jobs cascading to the same courier — courier accepts only one
// ---------------------------------------------------------------------------

func TestCascade_Race1_TwoJobsToSameCourier_AcceptOnlyOne(t *testing.T) {
	u, s, _, cleanup := setupDispatchTestHarness(t)
	if u == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	ownerID := "tenant-race-two-jobs"
	empSolo := "emp-solo-under-tenant-race-two-jobs"
	empBackup := "emp-backup-under-tenant-race-two-jobs"
	svcID := "svc-race-two-jobs"

	s.CreateService(ctx, &models.Service{
		ID:               svcID,
		TenantID:         ownerID,
		Name:             "Delivery Service",
		Category:         "delivery",
		TenantBasePrice:  30.0,
		TenantPricePerKM: 3.0,
		Latitude:         30.0000,
		Longitude:        31.0000,
	})

	now := time.Now().UTC()
	// empSolo is closest (1 km away)
	_ = s.UpsertEmployeeLocation(ctx, &models.EmployeeLocation{
		TenantID:   ownerID,
		EmployeeID: empSolo,
		Latitude:   30.0100,
		Longitude:  31.0000,
		UpdatedAt:  now,
	})
	// empBackup is farther (5 km away)
	_ = s.UpsertEmployeeLocation(ctx, &models.EmployeeLocation{
		TenantID:   ownerID,
		EmployeeID: empBackup,
		Latitude:   30.0500,
		Longitude:  31.0000,
		UpdatedAt:  now,
	})

	tokenCust1, _ := jwtutil.GenerateToken("cust-1", "user", ownerID, "cust1@test.com")
	tokenCust2, _ := jwtutil.GenerateToken("cust-2", "user", ownerID, "cust2@test.com")
	tokenSolo, _ := jwtutil.GenerateToken(empSolo, "employee", ownerID, "solo@test.com")

	// Create Job 1 -> offered to empSolo
	body1, _ := json.Marshal(map[string]any{
		"service_id":     svcID,
		"user_id":        tokenCust1,
		"payment_method": "cod",
		"location":       models.Location{Latitude: 30.0, Longitude: 31.0},
	})
	req1 := httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(body1))
	rec1 := httptest.NewRecorder()
	u.TrackJob(rec1, req1)
	var resp1 struct{ Job models.Job }
	_ = json.Unmarshal(rec1.Body.Bytes(), &resp1)
	job1ID := resp1.Job.ID

	// Create Job 2 -> also nearest to empSolo (offered to empSolo)
	body2, _ := json.Marshal(map[string]any{
		"service_id":     svcID,
		"user_id":        tokenCust2,
		"payment_method": "cod",
		"location":       models.Location{Latitude: 30.0, Longitude: 31.0},
	})
	req2 := httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(body2))
	rec2 := httptest.NewRecorder()
	u.TrackJob(rec2, req2)
	var resp2 struct{ Job models.Job }
	_ = json.Unmarshal(rec2.Body.Bytes(), &resp2)
	job2ID := resp2.Job.ID

	// Courier accepts Job 1 -> SUCCESS!
	acceptReq1 := httptest.NewRequest("POST", fmt.Sprintf("/users/employee/jobs/%s/accept", job1ID), nil)
	acceptReq1.Header.Set("Authorization", "Bearer "+tokenSolo)
	acceptRec1 := httptest.NewRecorder()
	u.AcceptJobOffer(acceptRec1, acceptReq1)

	if acceptRec1.Code != http.StatusOK {
		t.Fatalf("Accepting Job 1 failed: %d, body: %s", acceptRec1.Code, acceptRec1.Body.String())
	}

	job1 := s.GetJob(ctx, job1ID)
	if job1.Status != models.JobStatusActive {
		t.Fatalf("Expected Job 1 to be active, got %s", job1.Status)
	}

	// Courier tries to accept Job 2 -> MUST BE REJECTED (courier is already busy with active Job 1)
	acceptReq2 := httptest.NewRequest("POST", fmt.Sprintf("/users/employee/jobs/%s/accept", job2ID), nil)
	acceptReq2.Header.Set("Authorization", "Bearer "+tokenSolo)
	acceptRec2 := httptest.NewRecorder()
	u.AcceptJobOffer(acceptRec2, acceptReq2)

	if acceptRec2.Code != http.StatusConflict {
		t.Fatalf("Expected 409 Conflict when busy courier tries to accept second job, got %d. Body: %s", acceptRec2.Code, acceptRec2.Body.String())
	}

	// Job 2 offer to empSolo should be invalidated and cascaded to empBackup!
	job2 := s.GetJob(ctx, job2ID)
	if job2.CurrentOfferedEmployeeID != empBackup {
		t.Errorf("Expected Job 2 to cascade to empBackup, got %q", job2.CurrentOfferedEmployeeID)
	}
}

// ---------------------------------------------------------------------------
// 5. Race 2: Boundary Expiry Race
// ---------------------------------------------------------------------------

func TestCascade_Race2_BoundaryExpiry(t *testing.T) {
	u, s, _, cleanup := setupDispatchTestHarness(t)
	if u == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	ownerID := "tenant-race-boundary"
	empID := "emp-under-tenant-race-boundary"
	svcID := "svc-race-boundary"

	s.CreateService(ctx, &models.Service{
		ID:               svcID,
		TenantID:         ownerID,
		Name:             "Delivery Service",
		Category:         "delivery",
		TenantBasePrice:  30.0,
		TenantPricePerKM: 3.0,
		Latitude:         30.0000,
		Longitude:        31.0000,
	})

	now := time.Now().UTC()
	_ = s.UpsertEmployeeLocation(ctx, &models.EmployeeLocation{
		TenantID:   ownerID,
		EmployeeID: empID,
		Latitude:   30.0100,
		Longitude:  31.0000,
		UpdatedAt:  now,
	})

	// Create job with an offer that expired 1 millisecond ago
	expired := now.Add(-1 * time.Millisecond)
	job := &models.Job{
		ID:                       "job-boundary-expired",
		OwnerID:                  ownerID,
		UserID:                   "cust-boundary",
		ServiceID:                svcID,
		Status:                   models.JobStatusPendingDispatch,
		CurrentOfferedEmployeeID: empID,
		OfferExpiresAt:           &expired,
		OfferedEmployeeIDs:       []string{empID},
		Location:                 models.Location{Latitude: 30.0, Longitude: 31.0},
		PaymentMethod:            "cod",
		CreatedAt:                now.Add(-61 * time.Second),
		UpdatedAt:                now.Add(-61 * time.Second),
	}
	_ = s.CreateJob(ctx, job)

	tokenEmp, _ := jwtutil.GenerateToken(empID, "employee", ownerID, "emp@test.com")

	// Courier attempts to accept expired offer
	req := httptest.NewRequest("POST", "/users/employee/jobs/job-boundary-expired/accept", nil)
	req.Header.Set("Authorization", "Bearer "+tokenEmp)
	rec := httptest.NewRecorder()
	u.AcceptJobOffer(rec, req)

	// Must be rejected deterministically as expired!
	if rec.Code != http.StatusConflict {
		t.Fatalf("Expected 409 Conflict for accept on expired offer, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// Job should have cascaded to unavailable (since empID was only courier)
	updated := s.GetJob(ctx, job.ID)
	if updated.Status != models.JobStatusUnavailable {
		t.Errorf("Expected job status to be unavailable after cascade exhaustion, got %q", updated.Status)
	}
}

// ---------------------------------------------------------------------------
// 6. Race 3: Stale Courier Location Auto-Declines Offer
// ---------------------------------------------------------------------------

func TestCascade_Race3_StaleCourierLocation_AutoDeclines(t *testing.T) {
	u, s, _, cleanup := setupDispatchTestHarness(t)
	if u == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	ownerID := "tenant-stale-loc"
	empStale := "emp-stale-under-tenant-stale-loc"
	empFresh := "emp-fresh-under-tenant-stale-loc"
	svcID := "svc-stale-loc"

	s.CreateService(ctx, &models.Service{
		ID:               svcID,
		TenantID:         ownerID,
		Name:             "Delivery Service",
		Category:         "delivery",
		TenantBasePrice:  30.0,
		TenantPricePerKM: 3.0,
		Latitude:         30.0000,
		Longitude:        31.0000,
	})

	now := time.Now().UTC()
	// empStale ping was 6 minutes ago (> 5 min freshness window)
	_ = s.UpsertEmployeeLocation(ctx, &models.EmployeeLocation{
		TenantID:   ownerID,
		EmployeeID: empStale,
		Latitude:   30.0100,
		Longitude:  31.0000,
		UpdatedAt:  now.Add(-6 * time.Minute),
	})

	// empFresh ping was just now
	_ = s.UpsertEmployeeLocation(ctx, &models.EmployeeLocation{
		TenantID:   ownerID,
		EmployeeID: empFresh,
		Latitude:   30.0200,
		Longitude:  31.0000,
		UpdatedAt:  now,
	})

	// Create job with offer to empStale
	future := now.Add(50 * time.Second)
	job := &models.Job{
		ID:                       "job-stale-location",
		OwnerID:                  ownerID,
		UserID:                   "cust-stale",
		ServiceID:                svcID,
		Status:                   models.JobStatusPendingDispatch,
		CurrentOfferedEmployeeID: empStale,
		OfferExpiresAt:           &future,
		OfferedEmployeeIDs:       []string{empStale},
		Location:                 models.Location{Latitude: 30.0, Longitude: 31.0},
		PaymentMethod:            "cod",
		CreatedAt:                now,
		UpdatedAt:                now,
	}
	_ = s.CreateJob(ctx, job)

	tokenStale, _ := jwtutil.GenerateToken(empStale, "employee", ownerID, "stale@test.com")

	// Courier attempts to accept with stale location
	req := httptest.NewRequest("POST", "/users/employee/jobs/job-stale-location/accept", nil)
	req.Header.Set("Authorization", "Bearer "+tokenStale)
	rec := httptest.NewRecorder()
	u.AcceptJobOffer(rec, req)

	// Must be rejected due to stale location!
	if rec.Code != http.StatusConflict {
		t.Fatalf("Expected 409 Conflict when courier with stale location tries to accept, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// Cascade should have automatically advanced to empFresh
	updated := s.GetJob(ctx, job.ID)
	if updated.CurrentOfferedEmployeeID != empFresh {
		t.Errorf("Expected job offer to cascade to empFresh, got %q", updated.CurrentOfferedEmployeeID)
	}
}

// ---------------------------------------------------------------------------
// 7. Cancellation during pending_dispatch halts cascade cleanly
// ---------------------------------------------------------------------------

func TestCascade_CustomerCancelsDuringPendingDispatch_HaltsCascade(t *testing.T) {
	u, s, _, cleanup := setupDispatchTestHarness(t)
	if u == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	ownerID := "tenant-cancel-cascade"
	emp1 := "emp1-under-tenant-cancel-cascade"
	emp2 := "emp2-under-tenant-cancel-cascade"
	svcID := "svc-cancel-cascade"
	custID := "cust-canceller"

	s.CreateService(ctx, &models.Service{
		ID:               svcID,
		TenantID:         ownerID,
		Name:             "Delivery Service",
		Category:         "delivery",
		TenantBasePrice:  25.0,
		TenantPricePerKM: 2.0,
		Latitude:         30.0000,
		Longitude:        31.0000,
	})

	now := time.Now().UTC()
	_ = s.UpsertEmployeeLocation(ctx, &models.EmployeeLocation{
		TenantID:   ownerID,
		EmployeeID: emp1,
		Latitude:   30.0100,
		Longitude:  31.0000,
		UpdatedAt:  now,
	})
	_ = s.UpsertEmployeeLocation(ctx, &models.EmployeeLocation{
		TenantID:   ownerID,
		EmployeeID: emp2,
		Latitude:   30.0200,
		Longitude:  31.0000,
		UpdatedAt:  now,
	})

	tokenCust, _ := jwtutil.GenerateToken(custID, "user", ownerID, "cust@test.com")
	tokenEmp1, _ := jwtutil.GenerateToken(emp1, "employee", ownerID, "emp1@test.com")

	// 1. Customer books a job (triggers pending_dispatch cascade)
	trackBody := map[string]any{
		"user_id":        tokenCust,
		"service_id":     svcID,
		"payment_method": "wallet",
		"location": models.Location{
			Latitude:  30.0000,
			Longitude: 31.0000,
		},
	}
	b, _ := json.Marshal(trackBody)
	req := httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(b))
	req.Header.Set("Authorization", "Bearer "+tokenCust)
	rec := httptest.NewRecorder()
	u.TrackJob(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("TrackJob failed: %d, body: %s", rec.Code, rec.Body.String())
	}
	var trackResp map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &trackResp)
	jobMap := trackResp["job"].(map[string]any)
	jobID := jobMap["id"].(string)

	// Verify job created in pending_dispatch and offered to emp1
	job := s.GetJob(ctx, jobID)
	if job.Status != models.JobStatusPendingDispatch || job.CurrentOfferedEmployeeID != emp1 {
		t.Fatalf("Expected job in pending_dispatch with offer to emp1, got status=%s, offered=%s", job.Status, job.CurrentOfferedEmployeeID)
	}

	// 2. Customer cancels the job while it is still in pending_dispatch
	cancelBody := map[string]any{
		"job_id":       jobID,
		"requester_id": tokenCust,
		"reason":       "Customer changed their mind",
	}
	cb, _ := json.Marshal(cancelBody)
	cancelReq := httptest.NewRequest("POST", "/users/jobs/cancel", bytes.NewReader(cb))
	cancelReq.Header.Set("Authorization", "Bearer "+tokenCust)
	cancelRec := httptest.NewRecorder()
	u.CancelJob(cancelRec, cancelReq)

	if cancelRec.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK for cancelling pending_dispatch job, got %d. Body: %s", cancelRec.Code, cancelRec.Body.String())
	}

	// Verify job is cancelled and current offer is cleared
	cancelledJob := s.GetJob(ctx, jobID)
	if cancelledJob.Status != models.JobStatusCancelled {
		t.Errorf("Expected job status to be cancelled, got %q", cancelledJob.Status)
	}
	if cancelledJob.CurrentOfferedEmployeeID != "" {
		t.Errorf("Expected current_offered_employee_id to be cleared, got %q", cancelledJob.CurrentOfferedEmployeeID)
	}
	if cancelledJob.CancellationReason != "Customer changed their mind" {
		t.Errorf("Expected cancellation reason 'Customer changed their mind', got %q", cancelledJob.CancellationReason)
	}

	// 3. Courier emp1 tries to accept the now-cancelled job -> Must be rejected with 409 Conflict!
	acceptReq := httptest.NewRequest("POST", "/users/employee/jobs/"+jobID+"/accept", nil)
	acceptReq.Header.Set("Authorization", "Bearer "+tokenEmp1)
	acceptRec := httptest.NewRecorder()
	u.AcceptJobOffer(acceptRec, acceptReq)

	if acceptRec.Code != http.StatusConflict {
		t.Fatalf("Expected 409 Conflict when accepting cancelled job, got %d. Body: %s", acceptRec.Code, acceptRec.Body.String())
	}

	// 4. Verify cascade did NOT advance to emp2 (cascade halted)
	afterAttempt := s.GetJob(ctx, jobID)
	if afterAttempt.Status != models.JobStatusCancelled {
		t.Errorf("Job status should remain cancelled, got %q", afterAttempt.Status)
	}
	if afterAttempt.CurrentOfferedEmployeeID != "" {
		t.Errorf("Job should not have been offered to anyone else, got offered: %q", afterAttempt.CurrentOfferedEmployeeID)
	}
}
