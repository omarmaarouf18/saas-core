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

func TestPickupJob_ReturnsEmployeeJobResponseProjection(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	if os.Getenv("MONGO_URI") == "" {
		os.Setenv("MONGO_URI", "mongodb://root:devpassword123@localhost:27017/saas_platform?authSource=admin")
	}
	s, _, ctx, cleanup := setupClosedStatusHarness(t)
	defer cleanup()

	ownerID := "owner-pickup-dto"
	empID := "emp-pickup-dto"
	custID := "cust-pickup-dto"
	jobID := "job-pickup-dto-1"

	u := v2UserServiceWithRoles(t, s, ownerID, empID)

	actualCash := 120.50
	activeJob := &models.Job{
		ID:                 jobID,
		OwnerID:            ownerID,
		ServiceID:          "svc-pickup-dto",
		UserID:             custID,
		EmployeeID:         empID,
		Status:             models.JobStatusActive,
		SubStatus:          models.SubStatusHeadingToPickup,
		BookedDistance:     5.0,
		PaymentMethod:      "cash_on_delivery",
		ActualCashAmount:   &actualCash, // Owner/reconciliation field! Must NOT be exposed to employee
		LockedEscrowAmount: 0.0,
		Location: models.Location{
			Latitude: 30.0444, Longitude: 31.2357, Address: "Pickup Address",
		},
		Destination: models.Location{
			Latitude: 30.0500, Longitude: 31.2400, Address: "Dropoff Address",
		},
		CreatedAt: time.Now().UTC().Add(-10 * time.Minute),
		UpdatedAt: time.Now().UTC().Add(-5 * time.Minute),
	}
	if err := s.CreateJob(ctx, activeJob); err != nil {
		t.Fatalf("seed CreateJob: %v", err)
	}

	empToken, _ := jwtutil.GenerateToken(empID, "employee", ownerID, "courier@example.com")

	body, _ := json.Marshal(map[string]any{
		"job_id": jobID,
	})
	req := httptest.NewRequest(http.MethodPost, "/users/jobs/pickup", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+empToken)
	rec := httptest.NewRecorder()

	u.PickupJob(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK from PickupJob, got %d: %s", rec.Code, rec.Body.String())
	}

	var resp map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("unmarshal response: %v", err)
	}

	jobObj, ok := resp["job"].(map[string]any)
	if !ok {
		t.Fatalf("expected 'job' object in response, got %v", resp)
	}

	// Verify sub_status was updated to picked_up
	if subStatus, _ := jobObj["sub_status"].(string); subStatus != models.SubStatusPickedUp {
		t.Errorf("expected sub_status %q, got %q", models.SubStatusPickedUp, subStatus)
	}

	// CRITICAL CHECK: Owner-only field actual_cash_amount MUST NOT be present in employee response
	if val, exists := jobObj["actual_cash_amount"]; exists {
		t.Errorf("actual_cash_amount must NOT be exposed in EmployeeJobResponse, got %v", val)
	}
}
