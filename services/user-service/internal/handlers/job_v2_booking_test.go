package handlers

// ADR-0028 v2 booking inputs (item: TrackJob validation + first
// status_history entry):
//  - recipient / package_details / structured address text are optional;
//    present-but-invalid values fail fast with stable field-specific 400
//    error codes before any employee/KYC/escrow work.
//  - valid values are trimmed/sanitized, snapshotted onto the job, and
//    echoed back from the booking response.
//  - creation always appends the first server-generated status_history
//    entry (initial status, customer actor, "job created" reason).
//  - legacy payloads without any v2 field behave exactly as before.

import (
	"encoding/json"
	"net/http"
	"os"
	"strings"
	"testing"
	"time"
	"unicode/utf8"

	"github.com/project/shared/infra/jwtutil"
	"github.com/project/user-service/internal/models"
)

func TestV2TrackJob_RecipientPackageAddressRoundTrip(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	s, _, ctx, cleanup := setupClosedStatusHarness(t)
	defer cleanup()
	u, _ := trackJobClosedStatusHarness(t, s)

	seedClosedStatusSub(t, s, ctx, "v2-owner-1", models.PlanPaid, time.Now().UTC().Add(time.Hour))
	mustCreateService(t, s, ctx, &models.Service{
		ID: "svc-v2-1", TenantID: "v2-owner-1", Name: "V2 Shop",
		Category: "delivery", TenantBasePrice: 10.0, TenantPricePerKM: 1.0,
		Latitude: 30.0444, Longitude: 31.2357,
	})

	tokenUser, _ := jwtutil.GenerateToken("cust-v2-1", "user", "v2-owner-1", "c1@example.com")
	rec := postClosedStatusTrack(t, u, map[string]any{
		"service_id": "svc-v2-1", "user_id": tokenUser, "payment_method": "cod",
		"location": map[string]any{
			"latitude": 30.0444, "longitude": 31.2357,
			"address": "  15 شارع قصر النيل " + "  ",
		},
		"destination": map[string]any{
			"latitude": 30.05, "longitude": 31.24,
			"address": "4 شارع التحرير، الدقي",
		},
		"recipient": map[string]any{
			"name":  "  محمود إبراهيم  ",
			"phone": "+201012345678",
			"notes": "يرجى الاتصال قبل الوصول",
		},
		"package_details": map[string]any{
			"size":  "SMALL",
			"notes": "أوراق ومستندات هامة",
		},
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

	// Echoed recipient is trimmed, phone normalize-preserved, size lowercased.
	recipient, _ := jobRaw["recipient"].(map[string]any)
	if recipient == nil {
		t.Fatalf("response missing recipient: %s", rec.Body.String())
	}
	if got, _ := recipient["name"].(string); got != "محمود إبراهيم" {
		t.Errorf("recipient name not trimmed: %q", got)
	}
	if got, _ := recipient["phone"].(string); got != "+201012345678" {
		t.Errorf("recipient phone = %q", got)
	}
	packageDetails, _ := jobRaw["package_details"].(map[string]any)
	if packageDetails == nil {
		t.Fatalf("response missing package_details: %s", rec.Body.String())
	}
	if got, _ := packageDetails["size"].(string); got != "small" {
		t.Errorf("package size not normalized: %q", got)
	}

	// Structured address text is sanitized (trimmed, control chars stripped).
	loc, _ := jobRaw["location"].(map[string]any)
	if got, _ := loc["address"].(string); got != "15 شارع قصر النيل" {
		t.Errorf("location.address not trimmed: %q", got)
	}

	// First status_history entry: initial status + customer actor.
	status0, _ := jobRaw["status"].(string)
	history, _ := jobRaw["status_history"].([]any)
	if len(history) != 1 {
		t.Fatalf("expected exactly 1 creation history entry, got %d: %s", len(history), rec.Body.String())
	}
	entry, _ := history[0].(map[string]any)
	if got, _ := entry["status"].(string); got != status0 {
		t.Errorf("entry status %q != initial status %q", got, status0)
	}
	if got, _ := entry["actor_role"].(string); got != "customer" {
		t.Errorf("entry actor_role = %q, want customer", got)
	}
	if _, present := entry["actor_id"]; present && entry["actor_id"] != "" {
		t.Errorf("creation entry must not carry actor_id, got %v", entry["actor_id"])
	}
	if got, _ := entry["reason"].(string); got != "job created" {
		t.Errorf("entry reason = %q", got)
	}

	// Persisted job echoes the same v2 snapshot (raw store read).
	id, _ := jobRaw["id"].(string)
	stored := s.GetJob(ctx, id)
	if stored == nil {
		t.Fatalf("stored job not found")
	}
	if stored.Recipient == nil || stored.Recipient.Phone != "+201012345678" {
		t.Errorf("stored recipient wrong: %+v", stored.Recipient)
	}
	if stored.PackageDetails == nil || stored.PackageDetails.Size != models.PackageSizeSmall {
		t.Errorf("stored package_details wrong: %+v", stored.PackageDetails)
	}
	if stored.Location.Address != "15 شارع قصر النيل" {
		t.Errorf("stored location.address = %q", stored.Location.Address)
	}
	if stored.Destination.Address != "4 شارع التحرير، الدقي" {
		t.Errorf("stored destination.address = %q", stored.Destination.Address)
	}
	if len(stored.StatusHistory) != 1 || stored.StatusHistory[0].Status != stored.Status ||
		stored.StatusHistory[0].ActorRole != models.ActorRoleCustomer {
		t.Errorf("stored status_history wrong: %+v", stored.StatusHistory)
	}
}

func TestV2TrackJob_ValidationErrors(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	s, _, ctx, cleanup := setupClosedStatusHarness(t)
	defer cleanup()
	u, _ := trackJobClosedStatusHarness(t, s)

	seedClosedStatusSub(t, s, ctx, "v2-owner-2", models.PlanPaid, time.Now().UTC().Add(time.Hour))
	mustCreateService(t, s, ctx, &models.Service{
		ID: "svc-v2-2", TenantID: "v2-owner-2", Name: "V2 Shop 2",
		Category: "delivery", TenantBasePrice: 10.0, TenantPricePerKM: 1.0,
		Latitude: 30.0444, Longitude: 31.2357,
	})
	tokenUser, _ := jwtutil.GenerateToken("cust-v2-2", "user", "v2-owner-2", "c2@example.com")

	loc := map[string]any{"latitude": 30.0444, "longitude": 31.2357}
	dest := map[string]any{"latitude": 30.05, "longitude": 31.24}
	base := func() map[string]any {
		return map[string]any{
			"service_id": "svc-v2-2", "user_id": tokenUser, "payment_method": "cod",
			"location": loc, "destination": dest,
		}
	}

	cases := []struct {
		name    string
		mutate  func(m map[string]any)
		wantErr string
	}{
		{
			"recipient_name_too_long",
			func(m map[string]any) {
				m["recipient"] = map[string]any{"name": strings.Repeat("ن", models.MaxRecipientNameLength+1)}
			},
			"recipient_name_too_long",
		},
		{
			"recipient_phone_invalid",
			func(m map[string]any) { m["recipient"] = map[string]any{"phone": "0123456789"} },
			"recipient_phone_invalid",
		},
		{
			"recipient_notes_too_long",
			func(m map[string]any) {
				m["recipient"] = map[string]any{"notes": strings.Repeat("م", models.MaxRecipientNotesLen+1)}
			},
			"recipient_notes_too_long",
		},
		{
			"package_size_invalid",
			func(m map[string]any) { m["package_details"] = map[string]any{"size": "huge"} },
			"package_size_invalid",
		},
		{
			"package_notes_too_long",
			func(m map[string]any) {
				m["package_details"] = map[string]any{"notes": strings.Repeat("م", models.MaxPackageNotesLen+1)}
			},
			"package_notes_too_long",
		},
		{
			"address_too_long",
			func(m map[string]any) {
				m["destination"] = map[string]any{
					"latitude": 30.05, "longitude": 31.24,
					"address": strings.Repeat("ع", models.MaxAddressLength+1),
				}
			},
			"address_too_long",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			payload := base()
			tc.mutate(payload)
			rec := postClosedStatusTrack(t, u, payload)
			if rec.Code != http.StatusBadRequest {
				t.Fatalf("expected 400, got %d: %s", rec.Code, rec.Body.String())
			}
			var body map[string]any
			if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
				t.Fatalf("decode: %v", err)
			}
			if body["error"] != tc.wantErr {
				t.Errorf("expected %q, got %q (body: %s)", tc.wantErr, body["error"], rec.Body.String())
			}
		})
	}
}

func TestV2TrackJob_AcceptedBoundaryValues(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	s, _, ctx, cleanup := setupClosedStatusHarness(t)
	defer cleanup()
	u, _ := trackJobClosedStatusHarness(t, s)

	seedClosedStatusSub(t, s, ctx, "v2-owner-3", models.PlanPaid, time.Now().UTC().Add(time.Hour))
	mustCreateService(t, s, ctx, &models.Service{
		ID: "svc-v2-3", TenantID: "v2-owner-3", Name: "V2 Shop 3",
		Category: "delivery", TenantBasePrice: 10.0, TenantPricePerKM: 1.0,
		Latitude: 30.0444, Longitude: 31.2357,
	})
	tokenUser, _ := jwtutil.GenerateToken("cust-v2-3", "user", "v2-owner-3", "c3@example.com")

	// Boundary stays valid: exactly at each cap, bare Egyptian trunk form,
	// and a non-whitespace control character that must be stripped silently.
	rec := postClosedStatusTrack(t, u, map[string]any{
		"service_id": "svc-v2-3", "user_id": tokenUser, "payment_method": "cod",
		"location": map[string]any{
			"latitude": 30.0444, "longitude": 31.2357,
			// 250 visible runes + one trailing control char: sanitization
			// strips the \x01, leaving exactly the 250 cap.
			"address": strings.Repeat("x", models.MaxAddressLength) + "\x01",
		},
		"destination": map[string]any{"latitude": 30.05, "longitude": 31.24},
		"recipient": map[string]any{
			"name":  strings.Repeat("ن", models.MaxRecipientNameLength),
			"phone": "01112345678",
		},
		"package_details": map[string]any{"size": "large"},
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d: %s", rec.Code, rec.Body.String())
	}
	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode: %v", err)
	}
	jobRaw, _ := body["job"].(map[string]any)
	if jobRaw == nil {
		t.Fatalf("missing job object: %s", rec.Body.String())
	}
	recipient, _ := jobRaw["recipient"].(map[string]any)
	if got, _ := recipient["name"].(string); utf8.RuneCountInString(got) != models.MaxRecipientNameLength {
		t.Errorf("boundary name length wrong: %d", utf8.RuneCountInString(got))
	}
	if got, _ := recipient["phone"].(string); got != "01112345678" {
		t.Errorf("trunk-form phone = %q", got)
	}
	loc, _ := jobRaw["location"].(map[string]any)
	gotAddr, _ := loc["address"].(string)
	if strings.ContainsRune(gotAddr, '\x01') {
		t.Errorf("control chars not stripped: %q", gotAddr)
	}
	if utf8.RuneCountInString(gotAddr) != models.MaxAddressLength {
		t.Errorf("address = %d runes, want %d", utf8.RuneCountInString(gotAddr), models.MaxAddressLength)
	}
}

func TestV2TrackJob_WhitespaceOnlyRecipientNormalizes(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	s, _, ctx, cleanup := setupClosedStatusHarness(t)
	defer cleanup()
	u, _ := trackJobClosedStatusHarness(t, s)

	seedClosedStatusSub(t, s, ctx, "v2-owner-4", models.PlanPaid, time.Now().UTC().Add(time.Hour))
	mustCreateService(t, s, ctx, &models.Service{
		ID: "svc-v2-4", TenantID: "v2-owner-4", Name: "V2 Shop 4",
		Category: "delivery", TenantBasePrice: 10.0, TenantPricePerKM: 1.0,
		Latitude: 30.0444, Longitude: 31.2357,
	})
	tokenUser, _ := jwtutil.GenerateToken("cust-v2-4", "user", "v2-owner-4", "c4@example.com")

	rec := postClosedStatusTrack(t, u, map[string]any{
		"service_id": "svc-v2-4", "user_id": tokenUser, "payment_method": "cod",
		"location":        map[string]any{"latitude": 30.0444, "longitude": 31.2357},
		"destination":     map[string]any{"latitude": 30.05, "longitude": 31.24},
		"recipient":       map[string]any{"name": "   ", "notes": "  "},
		"package_details": map[string]any{"size": "  "},
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d: %s", rec.Code, rec.Body.String())
	}
	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode: %v", err)
	}
	jobRaw, _ := body["job"].(map[string]any)
	if _, present := jobRaw["recipient"]; present {
		t.Errorf("whitespace-only recipient must normalize to absent: %s", rec.Body.String())
	}
	if _, present := jobRaw["package_details"]; present {
		t.Errorf("whitespace-only package_details must normalize to absent: %s", rec.Body.String())
	}
}

// Legacy payloads (no v2 fields) must behave exactly as before, and the
// response must not grow the new keys.
func TestV2TrackJob_LegacyPayloadUnchanged(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	s, _, ctx, cleanup := setupClosedStatusHarness(t)
	defer cleanup()
	u, _ := trackJobClosedStatusHarness(t, s)

	seedClosedStatusSub(t, s, ctx, "v2-owner-5", models.PlanPaid, time.Now().UTC().Add(time.Hour))
	mustCreateService(t, s, ctx, &models.Service{
		ID: "svc-v2-5", TenantID: "v2-owner-5", Name: "V2 Shop 5",
		Category: "delivery", TenantBasePrice: 10.0, TenantPricePerKM: 1.0,
		Latitude: 30.0444, Longitude: 31.2357,
	})
	tokenUser, _ := jwtutil.GenerateToken("cust-v2-5", "user", "v2-owner-5", "c5@example.com")

	rec := postClosedStatusTrack(t, u, map[string]any{
		"service_id": "svc-v2-5", "user_id": tokenUser, "payment_method": "cod",
		"location":    map[string]any{"latitude": 30.0444, "longitude": 31.2357},
		"destination": map[string]any{"latitude": 30.05, "longitude": 31.24},
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d: %s", rec.Code, rec.Body.String())
	}
	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode: %v", err)
	}
	jobRaw, _ := body["job"].(map[string]any)
	for _, key := range []string{"recipient", "package_details", "sub_status", "estimated_duration_minutes"} {
		if _, present := jobRaw[key]; present {
			t.Errorf("legacy booking leaked key %q", key)
		}
	}
	// Creation history entry is the one intentional change: it is present
	// and matches the initial status.
	history, _ := jobRaw["status_history"].([]any)
	if len(history) != 1 {
		t.Fatalf("expected exactly 1 creation entry, got %v", history)
	}
	entry, _ := history[0].(map[string]any)
	if got, _ := entry["actor_role"].(string); got != "customer" {
		t.Errorf("creation entry actor = %q", got)
	}
}
