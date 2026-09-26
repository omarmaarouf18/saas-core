package handlers

// Round-trip tests for Option C (customer/owner-typed landmark notes):
//  - TrackJob persists trimmed address notes on both locations and returns
//    them in the created job (the same payload the employee fetch reads).
//  - Over-long notes fail fast with a field-specific 400 before any
//    employee/KYC/escrow work; no job record is created.
//  - Absent notes behave exactly as before (empty, omitted in JSON).

import (
	"encoding/json"
	"net/http"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/project/shared/infra/jwtutil"
	"github.com/project/user-service/internal/models"
)

func TestTrackJob_AddressNoteRoundTrip(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	s, _, ctx, cleanup := setupClosedStatusHarness(t)
	defer cleanup()
	u, _ := trackJobClosedStatusHarness(t, s)

	seedClosedStatusSub(t, s, ctx, "note-owner", models.PlanPaid, time.Now().UTC().Add(time.Hour))
	s.CreateService(ctx, &models.Service{
		ID: "svc-note", TenantID: "note-owner", Name: "Note Shop",
		Category: "delivery", TenantBasePrice: 10.0, TenantPricePerKM: 1.0,
		Latitude: 30.0444, Longitude: 31.2357,
	})

	tokenUser, _ := jwtutil.GenerateToken("cust-1", "user", "note-owner", "cust@example.com")
	rec := postClosedStatusTrack(t, u, map[string]any{
		"service_id": "svc-note", "user_id": tokenUser, "payment_method": "cod",
		"location":    map[string]any{"latitude": 30.0444, "longitude": 31.2357, "address_note": "  Home gate, 3rd floor  "},
		"destination": map[string]any{"latitude": 30.05, "longitude": 31.24, "address_note": "beside Ahmed's kiosk"},
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d: %s", rec.Code, rec.Body.String())
	}

	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	jobRaw, ok := body["job"].(map[string]any)
	if !ok {
		t.Fatalf("response has no job object: %s", rec.Body.String())
	}
	loc, _ := jobRaw["location"].(map[string]any)
	dest, _ := jobRaw["destination"].(map[string]any)
	// Trimmed at creation, returned in the creation payload.
	if loc["address_note"] != "Home gate, 3rd floor" {
		t.Errorf("pickup note not trimmed/returned: %v", loc["address_note"])
	}
	if dest["address_note"] != "beside Ahmed's kiosk" {
		t.Errorf("destination note not returned: %v", dest["address_note"])
	}

	// The employee fetch path reads the same stored record.
	id, _ := jobRaw["id"].(string)
	stored := s.GetJob(ctx, id)
	if stored == nil {
		t.Fatalf("stored job not found")
	}
	if stored.Location.AddressNote != "Home gate, 3rd floor" {
		t.Errorf("stored pickup note = %q", stored.Location.AddressNote)
	}
	if stored.Destination.AddressNote != "beside Ahmed's kiosk" {
		t.Errorf("stored destination note = %q", stored.Destination.AddressNote)
	}
}

func TestTrackJob_AddressNoteTooLongRejected(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	s, _, ctx, cleanup := setupClosedStatusHarness(t)
	defer cleanup()
	u, _ := trackJobClosedStatusHarness(t, s)

	seedClosedStatusSub(t, s, ctx, "note-owner-2", models.PlanPaid, time.Now().UTC().Add(time.Hour))
	s.CreateService(ctx, &models.Service{
		ID: "svc-note-2", TenantID: "note-owner-2", Name: "Note Shop 2",
		Category: "delivery", TenantBasePrice: 10.0, TenantPricePerKM: 1.0,
		Latitude: 30.0444, Longitude: 31.2357,
	})

	tokenUser, _ := jwtutil.GenerateToken("cust-9", "user", "note-owner-2", "c9@example.com")
	long := strings.Repeat("x", models.MaxAddressNoteLength+1)
	rec := postClosedStatusTrack(t, u, map[string]any{
		"service_id": "svc-note-2", "user_id": tokenUser, "payment_method": "cod",
		"location":    map[string]any{"latitude": 30.0444, "longitude": 31.2357},
		"destination": map[string]any{"latitude": 30.05, "longitude": 31.24, "address_note": long},
	})
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d: %s", rec.Code, rec.Body.String())
	}
	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if body["error"] != "address_note_too_long" {
		t.Errorf("expected address_note_too_long, got %v", body["error"])
	}
}

func TestTrackJob_NoAddressNoteBehavesAsBefore(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	s, _, ctx, cleanup := setupClosedStatusHarness(t)
	defer cleanup()
	u, _ := trackJobClosedStatusHarness(t, s)

	seedClosedStatusSub(t, s, ctx, "note-owner-3", models.PlanPaid, time.Now().UTC().Add(time.Hour))
	s.CreateService(ctx, &models.Service{
		ID: "svc-note-3", TenantID: "note-owner-3", Name: "Note Shop 3",
		Category: "delivery", TenantBasePrice: 10.0, TenantPricePerKM: 1.0,
		Latitude: 30.0444, Longitude: 31.2357,
	})

	tokenUser, _ := jwtutil.GenerateToken("cust-3", "user", "note-owner-3", "c3@example.com")
	rec := postClosedStatusTrack(t, u, map[string]any{
		"service_id": "svc-note-3", "user_id": tokenUser, "payment_method": "cod",
		"location":    map[string]any{"latitude": 30.0444, "longitude": 31.2357},
		"destination": map[string]any{"latitude": 30.05, "longitude": 31.24},
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d: %s", rec.Code, rec.Body.String())
	}
	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	jobRaw, _ := body["job"].(map[string]any)
	loc, _ := jobRaw["location"].(map[string]any)
	dest, _ := jobRaw["destination"].(map[string]any)
	if _, present := loc["address_note"]; present {
		t.Errorf("empty pickup note should be omitted, got %v", loc["address_note"])
	}
	if _, present := dest["address_note"]; present {
		t.Errorf("empty destination note should be omitted, got %v", dest["address_note"])
	}
}
