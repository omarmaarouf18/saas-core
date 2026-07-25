package models

import (
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
		JobStatusActive,
		JobStatusCompleted,
		JobStatusCancelled,
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
