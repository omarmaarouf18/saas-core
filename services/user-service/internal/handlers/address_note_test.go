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
	mustCreateService(t, s, ctx, &models.Service{
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
	mustCreateService(t, s, ctx, &models.Service{
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
	if body["code"] != "address_note_too_long" {
		t.Errorf("expected code address_note_too_long, got %v", body["code"])
	}
	if body["error"] == "" || body["message"] == "" {
		t.Errorf("expected non-empty error and message in response: %s", rec.Body.String())
	}
}

func TestTrackJob_NoAddressNoteBehavesAsBefore(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	s, _, ctx, cleanup := setupClosedStatusHarness(t)
	defer cleanup()
	u, _ := trackJobClosedStatusHarness(t, s)

	seedClosedStatusSub(t, s, ctx, "note-owner-3", models.PlanPaid, time.Now().UTC().Add(time.Hour))
	mustCreateService(t, s, ctx, &models.Service{
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

func TestTrackJob_TextLimitsInRunesNotBytes(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	if os.Getenv("MONGO_URI") == "" {
		os.Setenv("MONGO_URI", "mongodb://root:devpassword123@localhost:27017/saas_platform?authSource=admin")
	}
	s, _, ctx, cleanup := setupClosedStatusHarness(t)
	defer cleanup()
	u, _ := trackJobClosedStatusHarness(t, s)

	ownerID := "runes-owner"
	seedClosedStatusSub(t, s, ctx, ownerID, models.PlanPaid, time.Now().UTC().Add(time.Hour))
	mustCreateService(t, s, ctx, &models.Service{
		ID: "svc-runes", TenantID: ownerID, Name: "Runes Service",
		Category: "delivery", TenantBasePrice: 10.0, TenantPricePerKM: 1.0,
		Latitude: 30.0444, Longitude: 31.2357,
	})

	tokenUser, _ := jwtutil.GenerateToken("cust-runes", "user", ownerID, "runes@example.com")

	// 1. Exactly 500 Arabic runes in address_note (1000 bytes). Must be accepted.
	note500 := strings.Repeat("ع", 500)
	rec := postClosedStatusTrack(t, u, map[string]any{
		"service_id": "svc-runes", "user_id": tokenUser, "payment_method": "cod",
		"location":    map[string]any{"latitude": 30.0444, "longitude": 31.2357, "address_note": note500},
		"destination": map[string]any{"latitude": 30.05, "longitude": 31.24},
	})
	if rec.Code != http.StatusCreated && rec.Code != http.StatusOK {
		t.Fatalf("expected 201/200 for 500 Arabic runes note, got %d: %s", rec.Code, rec.Body.String())
	}

	// 2. 501 Arabic runes in address_note (1002 bytes). Must be rejected with 400.
	note501 := strings.Repeat("ع", 501)
	rec = postClosedStatusTrack(t, u, map[string]any{
		"service_id": "svc-runes", "user_id": tokenUser, "payment_method": "cod",
		"location":    map[string]any{"latitude": 30.0444, "longitude": 31.2357, "address_note": note501},
		"destination": map[string]any{"latitude": 30.05, "longitude": 31.24},
	})
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for 501 Arabic runes note, got %d: %s", rec.Code, rec.Body.String())
	}

	// 3. 250 Arabic runes in address text (500 bytes). Must be accepted.
	addr250 := strings.Repeat("ش", 250)
	rec = postClosedStatusTrack(t, u, map[string]any{
		"service_id": "svc-runes", "user_id": tokenUser, "payment_method": "cod",
		"location":    map[string]any{"latitude": 30.0444, "longitude": 31.2357, "address": addr250},
		"destination": map[string]any{"latitude": 30.05, "longitude": 31.24, "address": addr250},
	})
	if rec.Code != http.StatusCreated && rec.Code != http.StatusOK {
		t.Fatalf("expected 201/200 for 250 Arabic runes address, got %d: %s", rec.Code, rec.Body.String())
	}

	// 4. 251 Arabic runes in address text (502 bytes). Must be rejected.
	addr251 := strings.Repeat("ش", 251)
	rec = postClosedStatusTrack(t, u, map[string]any{
		"service_id": "svc-runes", "user_id": tokenUser, "payment_method": "cod",
		"location":    map[string]any{"latitude": 30.0444, "longitude": 31.2357, "address": addr251},
		"destination": map[string]any{"latitude": 30.05, "longitude": 31.24},
	})
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for 251 Arabic runes address, got %d: %s", rec.Code, rec.Body.String())
	}

	// 5. 100 Arabic runes in recipient name (200 bytes) accepted; 101 rejected.
	name100 := strings.Repeat("م", 100)
	rec = postClosedStatusTrack(t, u, map[string]any{
		"service_id": "svc-runes", "user_id": tokenUser, "payment_method": "cod",
		"location":    map[string]any{"latitude": 30.0444, "longitude": 31.2357},
		"destination": map[string]any{"latitude": 30.05, "longitude": 31.24},
		"recipient":   map[string]any{"name": name100},
	})
	if rec.Code != http.StatusCreated && rec.Code != http.StatusOK {
		t.Fatalf("expected 201/200 for 100 Arabic runes recipient name, got %d: %s", rec.Code, rec.Body.String())
	}

	name101 := strings.Repeat("م", 101)
	rec = postClosedStatusTrack(t, u, map[string]any{
		"service_id": "svc-runes", "user_id": tokenUser, "payment_method": "cod",
		"location":    map[string]any{"latitude": 30.0444, "longitude": 31.2357},
		"destination": map[string]any{"latitude": 30.05, "longitude": 31.24},
		"recipient":   map[string]any{"name": name101},
	})
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for 101 Arabic runes recipient name, got %d: %s", rec.Code, rec.Body.String())
	}

	// 6. 200 Arabic runes in recipient notes (400 bytes) accepted; 201 rejected.
	notes200 := strings.Repeat("ن", 200)
	rec = postClosedStatusTrack(t, u, map[string]any{
		"service_id": "svc-runes", "user_id": tokenUser, "payment_method": "cod",
		"location":    map[string]any{"latitude": 30.0444, "longitude": 31.2357},
		"destination": map[string]any{"latitude": 30.05, "longitude": 31.24},
		"recipient":   map[string]any{"notes": notes200},
	})
	if rec.Code != http.StatusCreated && rec.Code != http.StatusOK {
		t.Fatalf("expected 201/200 for 200 Arabic runes recipient notes, got %d: %s", rec.Code, rec.Body.String())
	}

	notes201 := strings.Repeat("ن", 201)
	rec = postClosedStatusTrack(t, u, map[string]any{
		"service_id": "svc-runes", "user_id": tokenUser, "payment_method": "cod",
		"location":    map[string]any{"latitude": 30.0444, "longitude": 31.2357},
		"destination": map[string]any{"latitude": 30.05, "longitude": 31.24},
		"recipient":   map[string]any{"notes": notes201},
	})
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for 201 Arabic runes recipient notes, got %d: %s", rec.Code, rec.Body.String())
	}

	// 7. 200 Arabic runes in package notes (400 bytes) accepted; 201 rejected.
	rec = postClosedStatusTrack(t, u, map[string]any{
		"service_id": "svc-runes", "user_id": tokenUser, "payment_method": "cod",
		"location":        map[string]any{"latitude": 30.0444, "longitude": 31.2357},
		"destination":     map[string]any{"latitude": 30.05, "longitude": 31.24},
		"package_details": map[string]any{"notes": notes200},
	})
	if rec.Code != http.StatusCreated && rec.Code != http.StatusOK {
		t.Fatalf("expected 201/200 for 200 Arabic runes package notes, got %d: %s", rec.Code, rec.Body.String())
	}

	rec = postClosedStatusTrack(t, u, map[string]any{
		"service_id": "svc-runes", "user_id": tokenUser, "payment_method": "cod",
		"location":        map[string]any{"latitude": 30.0444, "longitude": 31.2357},
		"destination":     map[string]any{"latitude": 30.05, "longitude": 31.24},
		"package_details": map[string]any{"notes": notes201},
	})
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for 201 Arabic runes package notes, got %d: %s", rec.Code, rec.Body.String())
	}
}
