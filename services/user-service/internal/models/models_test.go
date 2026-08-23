package models

import (
	"encoding/json"
	"testing"
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

func TestValidJobStatus(t *testing.T) {
	validStatuses := []JobStatus{
		JobStatusPending,
		JobStatusAwaitingPriceResponse,
		JobStatusActive,
		JobStatusCompleted,
		JobStatusCancelled,
		JobStatusEscrowReconciliationRequired,
	}

	for _, st := range validStatuses {
		if !ValidJobStatus(st) {
			t.Errorf("Expected status %q to be valid", st)
		}
	}

	if ValidJobStatus("invalid_status") {
		t.Errorf("Expected 'invalid_status' to be invalid")
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
