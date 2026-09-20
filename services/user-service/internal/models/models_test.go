package models

import (
	"encoding/json"
	"testing"
	"time"
)

func TestNewGeoJSONPoint(t *testing.T) {
	pt := NewGeoJSONPoint(37.7749, -122.4194)
	if pt.Type != "Point" {
		t.Errorf("Expected Type 'Point', got %q", pt.Type)
	}
	if len(pt.Coordinates) != 2 || pt.Coordinates[0] != -122.4194 || pt.Coordinates[1] != 37.7749 {
		t.Errorf("Expected GeoJSON coordinates [-122.4194, 37.7749], got %v", pt.Coordinates)
	}
}

func TestValidPriceProposal(t *testing.T) {
	tests := []struct {
		name      string
		suggested float64
		proposed  float64
		expected  bool
	}{
		{
			name:      "exactly at lower bound (0.5 * P_system)",
			suggested: 100.0,
			proposed:  50.0,
			expected:  true,
		},
		{
			name:      "exactly at upper bound (1.5 * P_system)",
			suggested: 100.0,
			proposed:  150.0,
			expected:  true,
		},
		{
			name:      "just below lower bound (49.99 for 100.0)",
			suggested: 100.0,
			proposed:  49.99,
			expected:  false,
		},
		{
			name:      "just above upper bound (150.01 for 100.0)",
			suggested: 100.0,
			proposed:  150.01,
			expected:  false,
		},
		{
			name:      "equal to P_system itself",
			suggested: 100.0,
			proposed:  100.0,
			expected:  true,
		},
		{
			name:      "zero suggested and zero proposed price",
			suggested: 0.0,
			proposed:  0.0,
			expected:  false,
		},
		{
			name:      "zero suggested price with tiny positive proposed price",
			suggested: 0.0,
			proposed:  0.01,
			expected:  false,
		},
		{
			name:      "negative proposed price",
			suggested: 100.0,
			proposed:  -10.0,
			expected:  false,
		},
		{
			name:      "negative suggested price",
			suggested: -100.0,
			proposed:  50.0,
			expected:  false,
		},
		{
			name:      "valid mid-range proposal",
			suggested: 200.0,
			proposed:  250.0,
			expected:  true,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			result := ValidPriceProposal(tc.suggested, tc.proposed)
			if result != tc.expected {
				t.Errorf("ValidPriceProposal(%.2f, %.2f) = %v; want %v", tc.suggested, tc.proposed, result, tc.expected)
			}
		})
	}
}

// Regression: cancelled customer orders must carry the cancellation reason
// through the CustomerJobResponse DTO. The Flutter "My Orders" screen reads
// job.cancellation_reason, which the DTO previously dropped entirely.
func TestNewCustomerJobResponse_IncludesCancellationReason(t *testing.T) {
	job := &Job{
		ID:                 "job-cxl-1",
		ServiceID:          "svc-1",
		Status:             JobStatusCancelled,
		PaymentMethod:      "cod",
		CancellationReason: "Customer moved out of area",
	}
	resp := NewCustomerJobResponse(job)
	data, err := json.Marshal(resp)
	if err != nil {
		t.Fatalf("marshal failed: %v", err)
	}
	var parsed map[string]any
	if err := json.Unmarshal(data, &parsed); err != nil {
		t.Fatalf("unmarshal failed: %v", err)
	}
	reason, ok := parsed["cancellation_reason"].(string)
	if !ok {
		t.Fatalf("expected cancellation_reason in marshaled DTO, got: %s", string(data))
	}
	if reason != "Customer moved out of area" {
		t.Errorf("unexpected reason value: %q", reason)
	}
}

func TestNewEmployeeJobResponse_FiltersInternalFields(t *testing.T) {
	now := time.Now().UTC()
	offerExpiry := now.Add(5 * time.Minute)
	job := &Job{
		ID:                       "job-emp-filter-1",
		OwnerID:                  "owner-1",
		UserID:                   "cust-1",
		ServiceID:                "svc-1",
		EmployeeID:               "emp-assigned",
		Status:                   JobStatusActive,
		Location:                 Location{Latitude: 30.0444, Longitude: 31.2357},
		CurrentLocation:          &Location{Latitude: 30.0450, Longitude: 31.2360},
		PaymentMethod:            "cod",
		CancellationReason:       "customer requested",
		LockedEscrowAmount:       50.0,
		ReconciliationNote:       "Internal operator memo",
		EscrowFailureReason:      "Distance mismatch",
		BookedDistance:           10.5,
		AssignedEmployeeLocation: &Location{Latitude: 30.04, Longitude: 31.23},
		CurrentOfferedEmployeeID: "emp-offered",
		OfferExpiresAt:           &offerExpiry,
		OfferedEmployeeIDs:       []string{"emp-offered", "emp-next"},
		CreatedAt:                now,
		UpdatedAt:                now,
	}

	// 1. Assigned employee viewing job (not the offered courier)
	respAssigned := NewEmployeeJobResponse(job, "emp-assigned")
	dataAssigned, err := json.Marshal(respAssigned)
	if err != nil {
		t.Fatalf("marshal failed: %v", err)
	}
	var mapAssigned map[string]any
	if err := json.Unmarshal(dataAssigned, &mapAssigned); err != nil {
		t.Fatalf("unmarshal failed: %v", err)
	}

	// Forbidden fields must not exist
	for _, forbidden := range []string{
		"reconciliation_note",
		"escrow_failure_reason",
		"offered_employee_ids",
		"booked_distance",
		"assigned_employee_location",
		"current_offered_employee_id",
		"offer_expires_at",
	} {
		if _, exists := mapAssigned[forbidden]; exists {
			t.Errorf("assigned employee response contains forbidden field: %q", forbidden)
		}
	}

	// Required fields for assigned employee must exist
	if mapAssigned["id"] != "job-emp-filter-1" {
		t.Errorf("expected id job-emp-filter-1, got %v", mapAssigned["id"])
	}
	if mapAssigned["owner_id"] != "owner-1" {
		t.Errorf("expected owner_id owner-1, got %v", mapAssigned["owner_id"])
	}
	if mapAssigned["user_id"] != "cust-1" {
		t.Errorf("expected user_id cust-1, got %v", mapAssigned["user_id"])
	}
	if mapAssigned["employee_id"] != "emp-assigned" {
		t.Errorf("expected employee_id emp-assigned, got %v", mapAssigned["employee_id"])
	}

	// 2. Offered courier viewing pending offer
	respOffered := NewEmployeeJobResponse(job, "emp-offered")
	dataOffered, err := json.Marshal(respOffered)
	if err != nil {
		t.Fatalf("marshal failed: %v", err)
	}
	var mapOffered map[string]any
	if err := json.Unmarshal(dataOffered, &mapOffered); err != nil {
		t.Fatalf("unmarshal failed: %v", err)
	}

	// Offered courier sees their own offer ID and expiry
	if mapOffered["current_offered_employee_id"] != "emp-offered" {
		t.Errorf("expected current_offered_employee_id emp-offered, got %v", mapOffered["current_offered_employee_id"])
	}
	if _, exists := mapOffered["offer_expires_at"]; !exists {
		t.Errorf("expected offer_expires_at for currently offered employee")
	}

	// But still forbidden from seeing other candidates or reconciliation internals
	for _, forbidden := range []string{
		"reconciliation_note",
		"escrow_failure_reason",
		"offered_employee_ids",
		"booked_distance",
		"assigned_employee_location",
	} {
		if _, exists := mapOffered[forbidden]; exists {
			t.Errorf("offered employee response contains forbidden field: %q", forbidden)
		}
	}
}

func TestNewCustomerJobResponse_ExcludesLeakedFields(t *testing.T) {
	now := time.Now().UTC()
	offerExpiry := now.Add(5 * time.Minute)
	job := &Job{
		ID:                       "job-cust-filter-1",
		OwnerID:                  "owner-1",
		UserID:                   "cust-1",
		ServiceID:                "svc-1",
		EmployeeID:               "emp-1",
		Status:                   JobStatusActive,
		Location:                 Location{Latitude: 30.0444, Longitude: 31.2357},
		CurrentLocation:          &Location{Latitude: 30.0450, Longitude: 31.2360},
		PaymentMethod:            "wallet",
		CancellationReason:       "cancelled",
		LockedEscrowAmount:       150.0,
		ReconciliationNote:       "Escrow locked due to discrepancy",
		EscrowFailureReason:      "Distance check failed",
		BookedDistance:           14.2,
		AssignedEmployeeLocation: &Location{Latitude: 30.04, Longitude: 31.23},
		CurrentOfferedEmployeeID: "emp-offered",
		OfferExpiresAt:           &offerExpiry,
		OfferedEmployeeIDs:       []string{"emp-offered"},
		CreatedAt:                now,
		UpdatedAt:                now,
	}

	resp := NewCustomerJobResponse(job)
	data, err := json.Marshal(resp)
	if err != nil {
		t.Fatalf("marshal failed: %v", err)
	}
	var m map[string]any
	if err := json.Unmarshal(data, &m); err != nil {
		t.Fatalf("unmarshal failed: %v", err)
	}

	leakedFields := []string{
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
	for _, field := range leakedFields {
		if _, exists := m[field]; exists {
			t.Errorf("CustomerJobResponse leaks field %q: value=%v", field, m[field])
		}
	}
}
