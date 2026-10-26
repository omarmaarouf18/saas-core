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

func TestPickupJob_StableErrorCodes(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	if os.Getenv("MONGO_URI") == "" {
		os.Setenv("MONGO_URI", "mongodb://root:devpassword123@localhost:27017/saas_platform?authSource=admin")
	}
	s, _, ctx, cleanup := setupClosedStatusHarness(t)
	defer cleanup()

	ownerID := "owner-pickup-err"
	assignedCourier := "emp-assigned-err"
	otherCourier := "emp-other-err"
	u := v2UserServiceWithRoles(t, s, ownerID, assignedCourier, otherCourier)

	assignedToken, _ := jwtutil.GenerateToken(assignedCourier, "employee", ownerID, "assigned@example.com")
	otherToken, _ := jwtutil.GenerateToken(otherCourier, "employee", ownerID, "other@example.com")

	// 1. Missing job_id
	req1 := httptest.NewRequest(http.MethodPost, "/users/jobs/pickup", bytes.NewReader([]byte(`{"job_id": ""}`)))
	req1.Header.Set("Content-Type", "application/json")
	req1.Header.Set("Authorization", "Bearer "+assignedToken)
	rec1 := httptest.NewRecorder()
	u.PickupJob(rec1, req1)
	if rec1.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for empty job_id, got %d", rec1.Code)
	}
	var b1 map[string]string
	_ = json.Unmarshal(rec1.Body.Bytes(), &b1)
	if b1["code"] != "job_id_required" || b1["error"] != "job_id is required" || b1["message"] != "job_id is required" {
		t.Errorf("unexpected body for missing job_id: %s", rec1.Body.String())
	}

	// 2. Missing token
	req2 := httptest.NewRequest(http.MethodPost, "/users/jobs/pickup", bytes.NewReader([]byte(`{"job_id": "job-123"}`)))
	req2.Header.Set("Content-Type", "application/json")
	rec2 := httptest.NewRecorder()
	u.PickupJob(rec2, req2)
	if rec2.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 for missing token, got %d", rec2.Code)
	}
	var b2 map[string]string
	_ = json.Unmarshal(rec2.Body.Bytes(), &b2)
	if b2["code"] != "unauthorized" || b2["error"] != "requester token is required" {
		t.Errorf("unexpected body for missing token: %s", rec2.Body.String())
	}

	// 3. Job not found
	req3 := httptest.NewRequest(http.MethodPost, "/users/jobs/pickup", bytes.NewReader([]byte(`{"job_id": "nonexistent"}`)))
	req3.Header.Set("Content-Type", "application/json")
	req3.Header.Set("Authorization", "Bearer "+assignedToken)
	rec3 := httptest.NewRecorder()
	u.PickupJob(rec3, req3)
	if rec3.Code != http.StatusNotFound {
		t.Fatalf("expected 404 for nonexistent job, got %d", rec3.Code)
	}
	var b3 map[string]string
	_ = json.Unmarshal(rec3.Body.Bytes(), &b3)
	if b3["code"] != "job_not_found" || b3["error"] != "job not found" {
		t.Errorf("unexpected body for nonexistent job: %s", rec3.Body.String())
	}

	// Create job in database
	activeJob := &models.Job{
		ID:          "job-pickup-err-1",
		OwnerID:     ownerID,
		ServiceID:   "svc-err",
		UserID:      "cust-err",
		EmployeeID:  assignedCourier,
		Status:      models.JobStatusActive,
		SubStatus:   models.SubStatusHeadingToPickup,
		Location:    models.Location{Latitude: 30.0444, Longitude: 31.2357},
		Destination: models.Location{Latitude: 30.05, Longitude: 31.24},
		CreatedAt:   time.Now().UTC(),
		UpdatedAt:   time.Now().UTC(),
	}
	if err := s.CreateJob(ctx, activeJob); err != nil {
		t.Fatalf("create job: %v", err)
	}

	// 4. Access denied (other courier)
	req4 := httptest.NewRequest(http.MethodPost, "/users/jobs/pickup", bytes.NewReader([]byte(`{"job_id": "job-pickup-err-1"}`)))
	req4.Header.Set("Content-Type", "application/json")
	req4.Header.Set("Authorization", "Bearer "+otherToken)
	rec4 := httptest.NewRecorder()
	u.PickupJob(rec4, req4)
	if rec4.Code != http.StatusForbidden {
		t.Fatalf("expected 403 for other courier, got %d", rec4.Code)
	}
	var b4 map[string]string
	_ = json.Unmarshal(rec4.Body.Bytes(), &b4)
	if b4["code"] != "access_denied" || b4["error"] != "access denied: only the assigned courier can confirm pickup" {
		t.Errorf("unexpected body for access denied: %s", rec4.Body.String())
	}

	// 5. Successful pickup first time
	req5 := httptest.NewRequest(http.MethodPost, "/users/jobs/pickup", bytes.NewReader([]byte(`{"job_id": "job-pickup-err-1"}`)))
	req5.Header.Set("Content-Type", "application/json")
	req5.Header.Set("Authorization", "Bearer "+assignedToken)
	rec5 := httptest.NewRecorder()
	u.PickupJob(rec5, req5)
	if rec5.Code != http.StatusOK {
		t.Fatalf("expected 200 for pickup, got %d: %s", rec5.Code, rec5.Body.String())
	}

	// 6. Already picked up (double pickup)
	req6 := httptest.NewRequest(http.MethodPost, "/users/jobs/pickup", bytes.NewReader([]byte(`{"job_id": "job-pickup-err-1"}`)))
	req6.Header.Set("Content-Type", "application/json")
	req6.Header.Set("Authorization", "Bearer "+assignedToken)
	rec6 := httptest.NewRecorder()
	u.PickupJob(rec6, req6)
	if rec6.Code != http.StatusConflict {
		t.Fatalf("expected 409 for already picked up, got %d", rec6.Code)
	}
	var b6 map[string]string
	_ = json.Unmarshal(rec6.Body.Bytes(), &b6)
	if b6["code"] != "already_picked_up" || b6["error"] != "job already picked up" || b6["message"] != "job already picked up" {
		t.Errorf("unexpected body for already picked up: %s", rec6.Body.String())
	}
}
