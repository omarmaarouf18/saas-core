package handlers

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"github.com/project/shared/infra/jwtutil"
	"github.com/project/user-service/internal/models"
)

// BE-GAPS-FIX item 2: a pickup that loses the CAS race (the job is active
// and assigned to the caller but no longer in the heading_to_pickup window
// when the update runs) answers 409 with the stable code job_state_changed,
// not the generic "conflict".
func TestPickupJob_LostRaceReturnsJobStateChanged(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	if os.Getenv("MONGO_URI") == "" {
		os.Setenv("MONGO_URI", "mongodb://root:devpassword123@localhost:27017/saas_platform?authSource=admin")
	}
	s, _, ctx, cleanup := setupClosedStatusHarness(t)
	defer cleanup()

	ownerID, empID := "owner-pickup-race", "emp-pickup-race"
	u := v2UserServiceWithRoles(t, s, ownerID, empID)

	// Active, assigned, but the sub_status is neither heading_to_pickup nor
	// picked_up: the handler's pre-checks pass and the store CAS misses,
	// exactly the state a concurrent exit from the pickup window leaves.
	if err := s.CreateJob(ctx, &models.Job{
		ID: "job-pickup-race", OwnerID: ownerID, ServiceID: "svc-race", UserID: "cust-race",
		EmployeeID: empID, Status: models.JobStatusActive,
		Location:    models.Location{Latitude: 30.0444, Longitude: 31.2357},
		Destination: models.Location{Latitude: 30.05, Longitude: 31.24},
		CreatedAt:   time.Now().UTC(), UpdatedAt: time.Now().UTC(),
	}); err != nil {
		t.Fatalf("seed job: %v", err)
	}

	token, _ := jwtutil.GenerateToken(empID, "employee", ownerID, "race@example.com")
	req := httptest.NewRequest(http.MethodPost, "/users/jobs/pickup", bytes.NewReader([]byte(`{"job_id": "job-pickup-race"}`)))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	u.PickupJob(rec, req)

	if rec.Code != http.StatusConflict {
		t.Fatalf("expected 409, got %d: %s", rec.Code, rec.Body.String())
	}
	var body map[string]string
	_ = json.Unmarshal(rec.Body.Bytes(), &body)
	if body["code"] != "job_state_changed" || body["error"] != "job state changed during pickup" || body["message"] != "job state changed during pickup" {
		t.Errorf("unexpected body for lost pickup race: %s", rec.Body.String())
	}
}
