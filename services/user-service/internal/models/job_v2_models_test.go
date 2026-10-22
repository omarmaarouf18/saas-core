package models

// ADR-0028 Job Model v2: model-level unit tests.
//
//  1. Role DTO projections and the recipient-phone redaction window —
//     employees keep recipient context only while the job is active;
//     once the job is terminal the phone is redacted (name/notes
//     survive for record-keeping). Owner and customer views always see
//     the recipient.
//  2. status_history actor sanitization for participant DTOs (admin
//     reviewer / system actor IDs never leave the tenant audit path).
//  3. sub_status is projected only under status == "active".
//  4. Booking input validators: recipient phone shapes and bounds,
//     package size tokens, address sanitization.
//  5. ETA straight-line estimate formula (ADR-0028 §2.5).

import (
	"encoding/json"
	"strings"
	"testing"
	"time"
)

func v2TestRecipient() *JobRecipient {
	return &JobRecipient{Name: "Mona Kamal", Phone: "+201012345678", Notes: "Leave with doorman"}
}

func TestOwnerDTOAlwaysExposesRecipient(t *testing.T) {
	for _, st := range []JobStatus{
		JobStatusPendingDispatch, JobStatusActive, JobStatusCompleted, JobStatusCancelled,
	} {
		j := &Job{ID: "j", Status: st, Recipient: v2TestRecipient()}
		dto := NewOwnerJobResponse(j)
		if dto.Recipient == nil || dto.Recipient.Phone != "+201012345678" {
			t.Errorf("owner DTO lost recipient phone at status %q: %+v", st, dto.Recipient)
		}
	}
}

func TestCustomerDTOAlwaysExposesRecipient(t *testing.T) {
	for _, st := range []JobStatus{
		JobStatusPendingDispatch, JobStatusActive, JobStatusCompleted, JobStatusCancelled,
	} {
		j := &Job{ID: "j", Status: st, Recipient: v2TestRecipient()}
		dto := NewCustomerJobResponse(j)
		if dto.Recipient == nil || dto.Recipient.Phone != "+201012345678" {
			t.Errorf("customer DTO lost recipient phone at status %q: %+v", st, dto.Recipient)
		}
	}
}

// ADR-0028 §2.1: employee sees recipient "from acceptance to completion";
// after a terminal transition recipient.phone is redacted immediately.
func TestEmployeeDTORecipientPhoneRedactedAfterTerminal(t *testing.T) {
	cases := []struct {
		name      string
		status    JobStatus
		wantPhone string
	}{
		{"active_keeps_phone", JobStatusActive, "+201012345678"},
		{"completed_redacts", JobStatusCompleted, ""},
		{"cancelled_redacts", JobStatusCancelled, ""},
		{"unavailable_redacts", JobStatusUnavailable, ""},
		{"pending_dispatch_redacts", JobStatusPendingDispatch, ""},
		{"awaiting_price_redacts", JobStatusAwaitingPriceResponse, ""},
		{"reconciliation_redacts", JobStatusEscrowReconciliationRequired, ""},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			j := &Job{ID: "j", Status: tc.status, Recipient: v2TestRecipient()}
			dto := NewEmployeeJobResponse(j, "emp-1")
			if dto.Recipient == nil {
				t.Fatalf("recipient dropped from employee DTO")
			}
			if dto.Recipient.Phone != tc.wantPhone {
				t.Errorf("status %q: phone = %q, want %q", tc.status, dto.Recipient.Phone, tc.wantPhone)
			}
			if dto.Recipient.Name != "Mona Kamal" || dto.Recipient.Notes != "Leave with doorman" {
				t.Errorf("status %q: name/notes must survive redaction: %+v", tc.status, dto.Recipient)
			}
		})
	}
}

// The redaction must be a projection: mutating the DTO copy must never
// reach the stored job, and vice versa.
func TestEmployeeDTORecipientRedactionIsACopy(t *testing.T) {
	j := &Job{ID: "j", Status: JobStatusCompleted, Recipient: v2TestRecipient()}
	dto := NewEmployeeJobResponse(j, "emp-1")
	dto.Recipient.Phone = "leaked"
	if j.Recipient.Phone != "+201012345678" {
		t.Errorf("redacted DTO mutation leaked into the stored job: %+v", j.Recipient)
	}
}

func TestLegacyJobWithoutRecipientYieldsNilRecipient(t *testing.T) {
	j := &Job{ID: "legacy", Status: JobStatusCompleted}
	if dto := NewEmployeeJobResponse(j, "e"); dto.Recipient != nil {
		t.Errorf("legacy job must project nil recipient, got %+v", dto.Recipient)
	}
	if dto := NewCustomerJobResponse(j); dto.Recipient != nil {
		t.Errorf("legacy job must project nil recipient, got %+v", dto.Recipient)
	}
}

func TestStatusHistoryActorSanitizedForParticipants(t *testing.T) {
	now := time.Now().UTC()
	hist := []JobStatusHistoryEntry{
		{Status: JobStatusActive, SubStatus: SubStatusHeadingToPickup, At: now, ActorRole: ActorRoleEmployee, ActorID: "emp-1"},
		{Status: JobStatusCancelled, At: now, ActorRole: ActorRoleAdmin, ActorID: "reviewer-77", Reason: "ops refund"},
		{Status: JobStatusPendingDispatch, At: now, ActorRole: ActorRoleSystem, ActorID: "sweep-45s", Reason: "offer expired"},
		{Status: JobStatusCompleted, At: now, ActorRole: ActorRoleOwner, ActorID: "tenant-9", Reason: "accepted"},
	}
	participant := SanitizeStatusHistoryForParticipant(hist)
	if got := participant[0].ActorID; got != "emp-1" {
		t.Errorf("employee actor id must survive: %q", got)
	}
	if got := participant[1].ActorID; got != "" {
		t.Errorf("admin actor id must be sanitized for participants, got %q", got)
	}
	if got := participant[2].ActorID; got != "" {
		t.Errorf("system actor id must be sanitized for participants, got %q", got)
	}
	if got := participant[3].ActorID; got != "tenant-9" {
		t.Errorf("owner actor id must survive: %q", got)
	}
	// Reasons/sub-statuses are operational context, not audit IDs.
	if participant[1].Reason != "ops refund" {
		t.Errorf("reason must survive sanitization: %+v", participant[1])
	}
	// Owner view keeps the full (unsanitized) slice: NewOwnerJobResponse
	// copies the stored slice reference, admin/system IDs included.
	owner := NewOwnerJobResponse(&Job{ID: "j", Status: JobStatusCancelled, StatusHistory: hist})
	if owner.StatusHistory[1].ActorID != "reviewer-77" {
		t.Errorf("owner DTO must keep full audit ids, got %q", owner.StatusHistory[1].ActorID)
	}
	// Input slice must not be mutated.
	if hist[1].ActorID != "reviewer-77" {
		t.Errorf("sanitizer mutated its input slice: %+v", hist[1])
	}
}

func TestSubStatusProjectedOnlyWhileActive(t *testing.T) {
	active := &Job{ID: "j", Status: JobStatusActive, SubStatus: SubStatusPickedUp}
	if dto := NewOwnerJobResponse(active); dto.SubStatus != SubStatusPickedUp {
		t.Errorf("owner active sub_status = %q", dto.SubStatus)
	}
	if dto := NewCustomerJobResponse(active); dto.SubStatus != SubStatusPickedUp {
		t.Errorf("customer active sub_status = %q", dto.SubStatus)
	}
	if dto := NewEmployeeJobResponse(active, "e"); dto.SubStatus != SubStatusPickedUp {
		t.Errorf("employee active sub_status = %q", dto.SubStatus)
	}
	// Belt-and-braces: a stale sub_status on a terminal row is dropped.
	stale := &Job{ID: "j2", Status: JobStatusCompleted, SubStatus: SubStatusHeadingToPickup}
	for _, dto := range []any{NewOwnerJobResponse(stale), NewCustomerJobResponse(stale), NewEmployeeJobResponse(stale, "e")} {
		var got string
		switch d := dto.(type) {
		case OwnerJobResponse:
			got = d.SubStatus
		case CustomerJobResponse:
			got = d.SubStatus
		case EmployeeJobResponse:
			got = d.SubStatus
		}
		if got != "" {
			t.Errorf("terminal row must not project sub_status, got %q", got)
		}
	}
}

// History entries and the new booking fields marshal with the JSON keys
// the frontend contracts expect.
func TestJobV2JSONShapes(t *testing.T) {
	eta := 12
	j := Job{
		ID:                       "j-json",
		Status:                   JobStatusActive,
		Recipient:                &JobRecipient{Phone: "+201012345678"},
		PackageDetails:           &PackageDetails{Size: PackageSizeMedium},
		SubStatus:                SubStatusHeadingToPickup,
		EstimatedDurationMinutes: &eta,
	}
	b, err := json.Marshal(NewCustomerJobResponse(&j))
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	for _, key := range []string{
		"recipient", "package_details", "sub_status", "estimated_duration_minutes",
	} {
		if !strings.Contains(string(b), `"`+key+`"`) {
			t.Errorf("customer JSON missing key %q: %s", key, b)
		}
	}
	// courier_phone is handler-overlaid (S2S auth lookup), not ctor
	// generated — empty must be omitted from the pure projection.
	dto := NewCustomerJobResponse(&j)
	if strings.Contains(string(mustJSON(t, dto)), `"courier_phone"`) {
		t.Errorf("pure ctor must leave courier_phone omitted: %s", b)
	}
	dto.CourierPhone = "+201099998888"
	if !strings.Contains(string(mustJSON(t, dto)), `"courier_phone":"+201099998888"`) {
		t.Errorf("overlaid courier_phone must serialize: %s", b)
	}
	empty := Job{ID: "empty", Status: JobStatusPendingDispatch}
	eb, err := json.Marshal(NewCustomerJobResponse(&empty))
	if err != nil {
		t.Fatalf("marshal legacy: %v", err)
	}
	for _, key := range []string{
		"recipient", "package_details", "sub_status", "estimated_duration_minutes", "courier_phone", "status_history",
	} {
		if strings.Contains(string(eb), `"`+key+`"`) {
			t.Errorf("legacy customer JSON must omit key %q: %s", key, eb)
		}
	}
}

func mustJSON(t *testing.T, v any) []byte {
	t.Helper()
	b, err := json.Marshal(v)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	return b
}
