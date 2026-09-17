package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/project/shared/infra/jwtutil"
	"github.com/project/user-service/internal/models"
)

func TestGetJob_RoleBasedDTOFiltering(t *testing.T) {
	u, s, _, cleanup := setupDispatchTestHarness(t)
	if u == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	ownerID := "owner-tenant-leak-test"
	custID := "cust-user-leak-test"
	empAssigned := "emp-assigned-leak-test"
	empOffered := "emp-offered-leak-test"
	empCandidate := "emp-candidate-leak-test"
	attackerID := "attacker-unrelated-user"
	svcID := "svc-leak-test"

	s.CreateService(ctx, &models.Service{
		ID:               svcID,
		TenantID:         ownerID,
		Name:             "Leak Test Service",
		Category:         "delivery",
		TenantBasePrice:  20.0,
		TenantPricePerKM: 1.5,
		Latitude:         30.0444,
		Longitude:        31.2357,
	})

	now := time.Now().UTC()
	offerExpiry := now.Add(5 * time.Minute)

	// Seed fresh courier location for empOffered
	_ = s.UpsertEmployeeLocation(ctx, &models.EmployeeLocation{
		TenantID:   ownerID,
		EmployeeID: empOffered,
		Latitude:   30.0450,
		Longitude:  31.2360,
		UpdatedAt:  now,
	})

	// Active job with assigned employee and internal reconciliation/escrow data
	activeJobID := "job-active-leak-test"
	activeJob := &models.Job{
		ID:                       activeJobID,
		OwnerID:                  ownerID,
		UserID:                   custID,
		ServiceID:                svcID,
		EmployeeID:               empAssigned,
		Status:                   models.JobStatusActive,
		Location:                 models.Location{Latitude: 30.0444, Longitude: 31.2357},
		CurrentLocation:          &models.Location{Latitude: 30.0450, Longitude: 31.2360},
		PaymentMethod:            "wallet",
		CancellationReason:       "cancellation reason sample",
		LockedEscrowAmount:       185.50,
		ReconciliationNote:       "CONFIDENTIAL: Stuck escrow under manual review",
		EscrowFailureReason:      "CONFIDENTIAL: Haversine distance < 70% threshold",
		SuggestedPrice:           25.0,
		BookedDistance:           12.8,
		AssignedEmployeeLocation: &models.Location{Latitude: 30.04, Longitude: 31.23},
		CurrentOfferedEmployeeID: empOffered,
		OfferExpiresAt:           &offerExpiry,
		OfferedEmployeeIDs:       []string{empOffered, empCandidate},
		CreatedAt:                now,
		UpdatedAt:                now,
	}
	if err := s.CreateJob(ctx, activeJob); err != nil {
		t.Fatalf("Failed to create active job: %v", err)
	}

	// Pending dispatch job with currently offered courier
	pendingJobID := "job-pending-dispatch-leak-test"
	pendingJob := &models.Job{
		ID:                       pendingJobID,
		OwnerID:                  ownerID,
		UserID:                   custID,
		ServiceID:                svcID,
		Status:                   models.JobStatusPendingDispatch,
		Location:                 models.Location{Latitude: 30.0444, Longitude: 31.2357},
		CurrentLocation:          &models.Location{Latitude: 30.0450, Longitude: 31.2360},
		PaymentMethod:            "wallet",
		LockedEscrowAmount:       185.50,
		ReconciliationNote:       "CONFIDENTIAL: Pending review note",
		EscrowFailureReason:      "CONFIDENTIAL: Pending failure reason",
		SuggestedPrice:           25.0,
		BookedDistance:           12.8,
		AssignedEmployeeLocation: &models.Location{Latitude: 30.04, Longitude: 31.23},
		CurrentOfferedEmployeeID: empOffered,
		OfferExpiresAt:           &offerExpiry,
		OfferedEmployeeIDs:       []string{empOffered, empCandidate},
		CreatedAt:                now,
		UpdatedAt:                now,
	}
	if err := s.CreateJob(ctx, pendingJob); err != nil {
		t.Fatalf("Failed to create pending job: %v", err)
	}

	tokenCust, _ := jwtutil.GenerateToken(custID, "customer", custID, "cust@test.com")
	tokenOwner, _ := jwtutil.GenerateToken(ownerID, "owner", ownerID, "owner@test.com")
	tokenAssignedEmp, _ := jwtutil.GenerateToken(empAssigned, "employee", ownerID, "emp1@test.com")
	tokenOfferedEmp, _ := jwtutil.GenerateToken(empOffered, "employee", ownerID, "emp2@test.com")
	tokenCandidateEmp, _ := jwtutil.GenerateToken(empCandidate, "employee", ownerID, "emp3@test.com")
	tokenAttacker, _ := jwtutil.GenerateToken(attackerID, "customer", attackerID, "attacker@test.com")

	t.Run("Customer calling GET /users/jobs/get excludes leaked internal fields", func(t *testing.T) {
		req := httptest.NewRequest("GET", "/users/jobs/get?id="+activeJobID+"&requester_id="+tokenCust, nil)
		rec := httptest.NewRecorder()
		u.GetJob(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK for customer, got %d: %s", rec.Code, rec.Body.String())
		}

		var rawMap map[string]any
		if err := json.Unmarshal(rec.Body.Bytes(), &rawMap); err != nil {
			t.Fatalf("Failed to unmarshal customer JSON: %v", err)
		}

		// Must NOT contain leaked internal fields (check key absence)
		leakedKeys := []string{
			"locked_escrow_amount",
			"reconciliation_note",
			"escrow_failure_reason",
			"offered_employee_ids",
			"current_offered_employee_id",
			"booked_distance",
			"assigned_employee_location",
			"owner_id",
			"user_id",
			"waypoints",
			"actual_cash_amount",
			"offer_expires_at",
		}
		for _, key := range leakedKeys {
			if _, exists := rawMap[key]; exists {
				t.Errorf("Customer response leaks field %q: value=%v", key, rawMap[key])
			}
		}

		// Must contain legitimate customer fields
		expectedCustomerFields := map[string]any{
			"id":                  activeJobID,
			"service_id":          svcID,
			"employee_id":         empAssigned,
			"status":              string(models.JobStatusActive),
			"payment_method":      "wallet",
			"cancellation_reason": "cancellation reason sample",
		}
		for k, expectedVal := range expectedCustomerFields {
			if rawMap[k] != expectedVal {
				t.Errorf("Customer field %q mismatch: expected %v, got %v", k, expectedVal, rawMap[k])
			}
		}
		if _, exists := rawMap["location"]; !exists {
			t.Errorf("Customer response missing location")
		}
		if _, exists := rawMap["current_location"]; !exists {
			t.Errorf("Customer response missing current_location for live tracking")
		}
	})

	t.Run("Owner calling GET /users/jobs/get receives complete tenant detail", func(t *testing.T) {
		req := httptest.NewRequest("GET", "/users/jobs/get?id="+activeJobID+"&requester_id="+tokenOwner, nil)
		rec := httptest.NewRecorder()
		u.GetJob(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK for owner, got %d: %s", rec.Code, rec.Body.String())
		}

		var rawMap map[string]any
		if err := json.Unmarshal(rec.Body.Bytes(), &rawMap); err != nil {
			t.Fatalf("Failed to unmarshal owner JSON: %v", err)
		}

		// Owner legitimately receives escrow and reconciliation data
		if rawMap["locked_escrow_amount"] != 185.50 {
			t.Errorf("Expected locked_escrow_amount 185.50 for owner, got %v", rawMap["locked_escrow_amount"])
		}
		if rawMap["reconciliation_note"] != "CONFIDENTIAL: Stuck escrow under manual review" {
			t.Errorf("Expected reconciliation_note for owner, got %v", rawMap["reconciliation_note"])
		}
		if rawMap["escrow_failure_reason"] != "CONFIDENTIAL: Haversine distance < 70% threshold" {
			t.Errorf("Expected escrow_failure_reason for owner, got %v", rawMap["escrow_failure_reason"])
		}
		if rawMap["owner_id"] != ownerID {
			t.Errorf("Expected owner_id %q, got %v", ownerID, rawMap["owner_id"])
		}
		if rawMap["user_id"] != custID {
			t.Errorf("Expected user_id %q, got %v", custID, rawMap["user_id"])
		}
		if rawMap["current_offered_employee_id"] != empOffered {
			t.Errorf("Expected current_offered_employee_id %q, got %v", empOffered, rawMap["current_offered_employee_id"])
		}
		if _, exists := rawMap["offered_employee_ids"]; !exists {
			t.Errorf("Expected offered_employee_ids for owner")
		}
	})

	t.Run("isInternal call with X-Internal-Token receives complete raw Job unfiltered", func(t *testing.T) {
		req := httptest.NewRequest("GET", "/users/jobs/get?id="+activeJobID, nil)
		req.Header.Set("X-Internal-Token", "mock-internal-token")
		rec := httptest.NewRecorder()
		u.GetJob(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK for internal call, got %d: %s", rec.Code, rec.Body.String())
		}

		var rawMap map[string]any
		if err := json.Unmarshal(rec.Body.Bytes(), &rawMap); err != nil {
			t.Fatalf("Failed to unmarshal internal JSON: %v", err)
		}

		// Raw Job struct includes internal pricing calculation fields
		if rawMap["booked_distance"] != 12.8 {
			t.Errorf("Expected booked_distance 12.8 for internal call, got %v", rawMap["booked_distance"])
		}
		if _, exists := rawMap["assigned_employee_location"]; !exists {
			t.Errorf("Expected assigned_employee_location for internal call")
		}
		if rawMap["locked_escrow_amount"] != 185.50 {
			t.Errorf("Expected locked_escrow_amount for internal call, got %v", rawMap["locked_escrow_amount"])
		}
		if rawMap["reconciliation_note"] != "CONFIDENTIAL: Stuck escrow under manual review" {
			t.Errorf("Expected reconciliation_note for internal call, got %v", rawMap["reconciliation_note"])
		}
	})

	t.Run("Assigned employee calling GET /users/jobs/get excludes reconciliation notes and other candidate IDs", func(t *testing.T) {
		req := httptest.NewRequest("GET", "/users/jobs/get?id="+activeJobID+"&requester_id="+tokenAssignedEmp, nil)
		rec := httptest.NewRecorder()
		u.GetJob(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK for assigned employee, got %d: %s", rec.Code, rec.Body.String())
		}

		var rawMap map[string]any
		if err := json.Unmarshal(rec.Body.Bytes(), &rawMap); err != nil {
			t.Fatalf("Failed to unmarshal assigned employee JSON: %v", err)
		}

		// Forbidden fields must not exist
		forbiddenKeys := []string{
			"reconciliation_note",
			"escrow_failure_reason",
			"offered_employee_ids",
			"current_offered_employee_id",
			"booked_distance",
			"assigned_employee_location",
		}
		for _, key := range forbiddenKeys {
			if _, exists := rawMap[key]; exists {
				t.Errorf("Assigned employee response leaks field %q: value=%v", key, rawMap[key])
			}
		}

		// Necessary employee fields must exist
		if rawMap["id"] != activeJobID {
			t.Errorf("Expected id %q, got %v", activeJobID, rawMap["id"])
		}
		if rawMap["owner_id"] != ownerID {
			t.Errorf("Expected owner_id %q, got %v", ownerID, rawMap["owner_id"])
		}
		if rawMap["user_id"] != custID {
			t.Errorf("Expected user_id %q, got %v", custID, rawMap["user_id"])
		}
		if rawMap["employee_id"] != empAssigned {
			t.Errorf("Expected employee_id %q, got %v", empAssigned, rawMap["employee_id"])
		}
		if rawMap["payment_method"] != "wallet" {
			t.Errorf("Expected payment_method wallet, got %v", rawMap["payment_method"])
		}
	})

	t.Run("Offered courier viewing pending offer receives own offer ID but not competitor candidate IDs", func(t *testing.T) {
		req := httptest.NewRequest("GET", "/users/jobs/get?id="+pendingJobID+"&requester_id="+tokenOfferedEmp, nil)
		rec := httptest.NewRecorder()
		u.GetJob(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK for offered courier, got %d: %s", rec.Code, rec.Body.String())
		}

		var rawMap map[string]any
		if err := json.Unmarshal(rec.Body.Bytes(), &rawMap); err != nil {
			t.Fatalf("Failed to unmarshal offered courier JSON: %v", err)
		}

		// Offered courier sees their own offer ID and offer countdown
		if rawMap["current_offered_employee_id"] != empOffered {
			t.Errorf("Expected current_offered_employee_id %q, got %v", empOffered, rawMap["current_offered_employee_id"])
		}
		if _, exists := rawMap["offer_expires_at"]; !exists {
			t.Errorf("Expected offer_expires_at for offered courier")
		}

		// But cannot see the list of all offered couriers or reconciliation internals
		for _, forbidden := range []string{
			"offered_employee_ids",
			"reconciliation_note",
			"escrow_failure_reason",
			"booked_distance",
			"assigned_employee_location",
		} {
			if _, exists := rawMap[forbidden]; exists {
				t.Errorf("Offered courier response leaks forbidden field %q: value=%v", forbidden, rawMap[forbidden])
			}
		}
	})

	t.Run("Unoffered candidate courier is rejected with 403 Forbidden", func(t *testing.T) {
		req := httptest.NewRequest("GET", "/users/jobs/get?id="+pendingJobID+"&requester_id="+tokenCandidateEmp, nil)
		rec := httptest.NewRecorder()
		u.GetJob(rec, req)

		if rec.Code != http.StatusForbidden {
			t.Errorf("Expected 403 Forbidden for unoffered candidate courier, got %d", rec.Code)
		}
	})

	t.Run("Unrelated customer is rejected with 403 Forbidden", func(t *testing.T) {
		req := httptest.NewRequest("GET", "/users/jobs/get?id="+activeJobID+"&requester_id="+tokenAttacker, nil)
		rec := httptest.NewRecorder()
		u.GetJob(rec, req)

		if rec.Code != http.StatusForbidden {
			t.Errorf("Expected 403 Forbidden for unrelated user, got %d", rec.Code)
		}
	})

	t.Run("Employee job listing GET /users/jobs/get?requester_id=... returns filtered EmployeeJobResponse", func(t *testing.T) {
		req := httptest.NewRequest("GET", "/users/jobs/get?requester_id="+tokenAssignedEmp, nil)
		rec := httptest.NewRecorder()
		u.GetJob(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK for employee job listing, got %d: %s", rec.Code, rec.Body.String())
		}

		var jobList []map[string]any
		if err := json.Unmarshal(rec.Body.Bytes(), &jobList); err != nil {
			t.Fatalf("Failed to unmarshal employee job list: %v", err)
		}

		if len(jobList) == 0 {
			t.Fatalf("Expected at least 1 job in employee list")
		}

		for _, item := range jobList {
			for _, forbidden := range []string{
				"reconciliation_note",
				"escrow_failure_reason",
				"offered_employee_ids",
				"booked_distance",
				"assigned_employee_location",
			} {
				if _, exists := item[forbidden]; exists {
					t.Errorf("Job in employee listing leaks forbidden field %q: value=%v", forbidden, item[forbidden])
				}
			}
		}
	})
}
