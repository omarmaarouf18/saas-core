package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/project/shared/infra/jwtutil"
	"github.com/project/user-service/internal/models"
)

// TestRepro_B01_CourierWithPendingOfferNotReoffered reproduces B-01:
// Courier A currently holds an active, unexpired job offer for Job 1.
// When Job 2 is created for the same tenant, candidate selection must NOT re-offer Courier A;
// it must offer Job 2 to the next available courier (Courier B).
func TestRepro_B01_CourierWithPendingOfferNotReoffered(t *testing.T) {
	u, s, _, cleanup := setupDispatchTestHarness(t)
	if u == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	ownerID := "tenant-b01-repro"
	cust1ID := "cust1-b01-repro"
	cust2ID := "cust2-b01-repro"
	svcID := "svc-b01-repro"

	pickupLat := 30.0444
	pickupLon := 31.2357

	s.CreateService(ctx, &models.Service{
		ID:               svcID,
		TenantID:         ownerID,
		Name:             "Express Delivery",
		Category:         "delivery",
		TenantBasePrice:  25.0,
		TenantPricePerKM: 2.0,
		Latitude:         pickupLat,
		Longitude:        pickupLon,
	})

	empA := fmt.Sprintf("empA-under-%s", ownerID)
	empB := fmt.Sprintf("empB-under-%s", ownerID)

	now := time.Now().UTC()
	// Courier A is closer (~0.5 km)
	_ = s.UpsertEmployeeLocation(ctx, &models.EmployeeLocation{
		TenantID:   ownerID,
		EmployeeID: empA,
		Latitude:   30.0489,
		Longitude:  31.2357,
		UpdatedAt:  now,
	})
	// Courier B is slightly farther (~1.5 km)
	_ = s.UpsertEmployeeLocation(ctx, &models.EmployeeLocation{
		TenantID:   ownerID,
		EmployeeID: empB,
		Latitude:   30.0579,
		Longitude:  31.2357,
		UpdatedAt:  now,
	})

	tokenCust1, _ := jwtutil.GenerateToken(cust1ID, "user", ownerID, "cust1@test.com")
	tokenCust2, _ := jwtutil.GenerateToken(cust2ID, "user", ownerID, "cust2@test.com")

	// 1. Customer 1 books Job 1 -> offered to nearest Courier A
	body1, _ := json.Marshal(map[string]any{
		"service_id":     svcID,
		"user_id":        tokenCust1,
		"location":       map[string]float64{"latitude": pickupLat, "longitude": pickupLon},
		"payment_method": "cod",
	})
	req1 := httptest.NewRequest(http.MethodPost, "/users/jobs/track", bytes.NewReader(body1))
	req1.Header.Set("Authorization", "Bearer "+tokenCust1)
	rec1 := httptest.NewRecorder()
	u.TrackJob(rec1, req1)

	if rec1.Code != http.StatusCreated {
		t.Fatalf("TrackJob 1 failed: %d %s", rec1.Code, rec1.Body.String())
	}

	var resp1 struct {
		Job models.Job `json:"job"`
	}
	_ = json.NewDecoder(rec1.Body).Decode(&resp1)
	job1 := resp1.Job
	if job1.CurrentOfferedEmployeeID != empA {
		t.Fatalf("Expected Job 1 to be offered to nearest courier A (%s), got %s", empA, job1.CurrentOfferedEmployeeID)
	}

	// 2. Customer 2 books Job 2 WHILE Job 1 is still pending dispatch with Courier A
	body2, _ := json.Marshal(map[string]any{
		"service_id":     svcID,
		"user_id":        tokenCust2,
		"location":       map[string]float64{"latitude": pickupLat, "longitude": pickupLon},
		"payment_method": "cod",
	})
	req2 := httptest.NewRequest(http.MethodPost, "/users/jobs/track", bytes.NewReader(body2))
	req2.Header.Set("Authorization", "Bearer "+tokenCust2)
	rec2 := httptest.NewRecorder()
	u.TrackJob(rec2, req2)

	if rec2.Code != http.StatusCreated {
		t.Fatalf("TrackJob 2 failed: %d %s", rec2.Code, rec2.Body.String())
	}

	var resp2 struct {
		Job models.Job `json:"job"`
	}
	_ = json.NewDecoder(rec2.Body).Decode(&resp2)
	job2 := resp2.Job

	// B-01 Assertion: Courier A already holds pending offer for Job 1, so Job 2 MUST be offered to Courier B!
	if job2.CurrentOfferedEmployeeID == empA {
		t.Fatalf("B-01 REPRO FAILED (BUG CONFIRMED): Courier A with pending offer on Job 1 was re-offered Job 2! Expected offer to Courier B (%s), got %s", empB, job2.CurrentOfferedEmployeeID)
	}
	if job2.CurrentOfferedEmployeeID != empB {
		t.Fatalf("Expected Job 2 to be offered to Courier B (%s), got %s", empB, job2.CurrentOfferedEmployeeID)
	}
}

// TestRepro_B02_CourierInReconciliationExcludedFromOffers reproduces B-02:
// Courier A holds an ActiveJobID lock from a job in escrow_reconciliation_required.
// When a new booking is created, candidate selection must NOT offer the job to Courier A,
// because Courier A cannot accept it (409 courier_busy). It must offer to Courier B.
func TestRepro_B02_CourierInReconciliationExcludedFromOffers(t *testing.T) {
	u, s, _, cleanup := setupDispatchTestHarness(t)
	if u == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	ownerID := "tenant-b02-repro"
	custID := "cust-b02-repro"
	svcID := "svc-b02-repro"

	pickupLat := 30.0444
	pickupLon := 31.2357

	s.CreateService(ctx, &models.Service{
		ID:               svcID,
		TenantID:         ownerID,
		Name:             "Express Delivery",
		Category:         "delivery",
		TenantBasePrice:  25.0,
		TenantPricePerKM: 2.0,
		Latitude:         pickupLat,
		Longitude:        pickupLon,
	})

	empA := fmt.Sprintf("empA-under-%s", ownerID)
	empB := fmt.Sprintf("empB-under-%s", ownerID)

	now := time.Now().UTC()
	// Courier A is closer (~0.5 km)
	_ = s.UpsertEmployeeLocation(ctx, &models.EmployeeLocation{
		TenantID:   ownerID,
		EmployeeID: empA,
		Latitude:   30.0489,
		Longitude:  31.2357,
		UpdatedAt:  now,
	})
	// Courier B is slightly farther (~1.5 km)
	_ = s.UpsertEmployeeLocation(ctx, &models.EmployeeLocation{
		TenantID:   ownerID,
		EmployeeID: empB,
		Latitude:   30.0579,
		Longitude:  31.2357,
		UpdatedAt:  now,
	})

	// Courier A is locked in escrow_reconciliation_required for an earlier job
	reconJobID := "job-recon-b02"
	_ = s.CreateJob(ctx, &models.Job{
		ID:         reconJobID,
		OwnerID:    ownerID,
		EmployeeID: empA,
		UserID:     custID,
		ServiceID:  svcID,
		Status:     models.JobStatusEscrowReconciliationRequired,
		Location:   models.Location{Latitude: pickupLat, Longitude: pickupLon},
	})
	_, _ = s.TryAcquireCourierLock(ctx, ownerID, empA, reconJobID)

	tokenCust, _ := jwtutil.GenerateToken(custID, "user", ownerID, "cust@test.com")

	// Customer books a new job
	body, _ := json.Marshal(map[string]any{
		"service_id":     svcID,
		"user_id":        tokenCust,
		"location":       map[string]float64{"latitude": pickupLat, "longitude": pickupLon},
		"payment_method": "cod",
	})
	req := httptest.NewRequest(http.MethodPost, "/users/jobs/track", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+tokenCust)
	rec := httptest.NewRecorder()
	u.TrackJob(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("TrackJob failed: %d %s", rec.Code, rec.Body.String())
	}

	var resp struct {
		Job models.Job `json:"job"`
	}
	_ = json.NewDecoder(rec.Body).Decode(&resp)

	// B-02 Assertion: Courier A is locked in reconciliation, so job MUST NOT be offered to Courier A.
	if resp.Job.CurrentOfferedEmployeeID == empA {
		t.Fatalf("B-02 REPRO FAILED (BUG CONFIRMED): Courier A locked in reconciliation was offered job! Expected Courier B (%s), got %s", empB, resp.Job.CurrentOfferedEmployeeID)
	}
	if resp.Job.CurrentOfferedEmployeeID != empB {
		t.Fatalf("Expected job to be offered to Courier B (%s), got %s", empB, resp.Job.CurrentOfferedEmployeeID)
	}
}

// TestRepro_A01_EquidistantCouriersDeterministicTieBreaking reproduces A-01:
// When multiple couriers are equidistant from the pickup point,
// ranking must be 100% deterministic and reproducible across repeated runs.
func TestRepro_A01_EquidistantCouriersDeterministicTieBreaking(t *testing.T) {
	u, s, _, cleanup := setupDispatchTestHarness(t)
	if u == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	ownerID := "tenant-a01-repro"
	svcID := "svc-a01-repro"

	pickupLat := 30.0444
	pickupLon := 31.2357

	s.CreateService(ctx, &models.Service{
		ID:               svcID,
		TenantID:         ownerID,
		Name:             "Branch Service",
		Category:         "delivery",
		TenantBasePrice:  25.0,
		TenantPricePerKM: 2.0,
		Latitude:         pickupLat,
		Longitude:        pickupLon,
	})

	emp1 := fmt.Sprintf("emp1-under-%s", ownerID)
	emp2 := fmt.Sprintf("emp2-under-%s", ownerID)
	emp3 := fmt.Sprintf("emp3-under-%s", ownerID)

	now := time.Now().UTC()
	for _, emp := range []string{emp1, emp2, emp3} {
		_ = s.UpsertEmployeeLocation(ctx, &models.EmployeeLocation{
			TenantID:   ownerID,
			EmployeeID: emp,
			Latitude:   pickupLat,
			Longitude:  pickupLon,
			UpdatedAt:  now,
		})
	}

	firstPicks := make(map[string]int)

	// Rotate insertion order across runs to simulate MongoDB cursor variation
	candidates := []string{emp1, emp2, emp3}
	for i := 0; i < 9; i++ {
		// Drop and re-insert in rotated order: [0,1,2], [1,2,0], [2,0,1]
		_ = s.DropDatabase(ctx)
		s.CreateService(ctx, &models.Service{
			ID:               svcID,
			TenantID:         ownerID,
			Name:             "Branch Service",
			Category:         "delivery",
			TenantBasePrice:  25.0,
			TenantPricePerKM: 2.0,
			Latitude:         pickupLat,
			Longitude:        pickupLon,
		})
		order := []string{
			candidates[i%3],
			candidates[(i+1)%3],
			candidates[(i+2)%3],
		}
		for _, emp := range order {
			_ = s.UpsertEmployeeLocation(ctx, &models.EmployeeLocation{
				TenantID:   ownerID,
				EmployeeID: emp,
				Latitude:   pickupLat,
				Longitude:  pickupLon,
				UpdatedAt:  now,
			})
		}

		candidate, err := u.findNextAvailableEmployee(ctx, ownerID, models.Location{Latitude: pickupLat, Longitude: pickupLon}, nil)
		if err != nil {
			t.Fatalf("findNextAvailableEmployee failed on iteration %d: %v", i, err)
		}
		firstPicks[candidate.EmployeeID]++
	}

	// A-01 Assertion: Tie-breaking must be 100% deterministic (the same courier must win regardless of input order)
	if len(firstPicks) > 1 {
		t.Fatalf("A-01 REPRO FAILED (BUG CONFIRMED): Non-deterministic tie-breaking for equidistant couriers! First pick distribution across rotated runs: %v", firstPicks)
	}
}
