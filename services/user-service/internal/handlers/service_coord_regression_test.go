package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/project/shared/infra/jwtutil"
	"github.com/project/user-service/internal/models"
)

// Service create/update previously accepted arbitrary coordinates (e.g.
// latitude 9999), poisoning the 2dsphere proximity index used by
// ListServices for every customer. ListServices validates; the write paths
// did not.

func TestCreateService_RejectsInvalidCoordinates(t *testing.T) {
	u, _, _, cleanup := idemRaceSetup(t)
	defer cleanup()

	tokenOwner, _ := jwtutil.GenerateToken("coord-owner", "owner", "coord-owner", "coord@example.com")

	body, _ := json.Marshal(map[string]any{
		"owner_id":            tokenOwner,
		"name":                "Poisoned Service",
		"category":            "delivery",
		"tenant_base_price":   10.0,
		"tenant_price_per_km": 1.0,
		"latitude":            9999.0,
		"longitude":           31.0,
	})
	req := httptest.NewRequest("POST", "/users/services", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	u.CreateService(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 invalid_coordinates for latitude=9999, got %d. Body: %s", rec.Code, rec.Body.String())
	}
	if got := rec.Body.String(); !bytes.Contains([]byte(got), []byte("invalid_coordinates")) {
		t.Errorf("expected invalid_coordinates error code, got: %s", got)
	}
}

func TestUpdateService_RejectsInvalidCoordinates(t *testing.T) {
	u, s, _, cleanup := idemRaceSetup(t)
	defer cleanup()

	ctx := context.Background()
	s.CreateService(ctx, &models.Service{
		ID: "coord-svc-2", TenantID: "coord-owner-2", Name: "Valid Service",
		Category: "delivery", TenantBasePrice: 10.0, TenantPricePerKM: 1.0,
		Latitude: 30.0, Longitude: 31.0,
	})

	// UpdateService authorizes via the owner Bearer token.
	tokenOwner, _ := jwtutil.GenerateToken("coord-owner-2", "owner", "coord-owner-2", "coord2@example.com")
	req := httptest.NewRequest("PUT", "/users/services", nil)
	req.Header.Set("Authorization", "Bearer "+tokenOwner)
	_ = req

	badLon := 9999.0
	body, _ := json.Marshal(map[string]any{
		"service_id": "coord-svc-2",
		"owner_id":   tokenOwner,
		"longitude":  badLon,
	})
	putReq := httptest.NewRequest("PUT", "/users/services", bytes.NewReader(body))
	putReq.Header.Set("Authorization", "Bearer "+tokenOwner)
	rec := httptest.NewRecorder()
	u.UpdateService(rec, putReq)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 invalid_coordinates for longitude=9999 on update, got %d. Body: %s", rec.Code, rec.Body.String())
	}
	t.Logf("update rejection body: %s", rec.Body.String())
}

// GetJob previously resolved the job ID from the `user_token` query param
// FIRST, falling back to `id`. The Flutter map-tracking provider sends BOTH
// (`?id=<jobID>&user_token=<JWT>`), so the JWT string was looked up as a job
// ID and customer map hydration always received 404.
func TestGetJob_UserTokenParamDoesNotShadowJobID(t *testing.T) {
	u, s, _, cleanup := idemRaceSetup(t)
	defer cleanup()

	ctx := context.Background()
	ownerID := "shadow-owner"
	svcID := "shadow-svc"
	s.CreateService(ctx, &models.Service{ID: svcID, TenantID: ownerID, TenantBasePrice: 5.0, TenantPricePerKM: 0.0, Latitude: 30.0, Longitude: 30.0})
	job := &models.Job{ID: "shadow-job-1", OwnerID: ownerID, UserID: "shadow-cust", ServiceID: svcID,
		Status: models.JobStatusActive, PaymentMethod: "cod",
		Location: models.Location{Latitude: 30.0, Longitude: 30.0}, CreatedAt: time.Now().Add(-time.Hour)}
	_ = s.CreateJob(ctx, job)

	tokenCust, _ := jwtutil.GenerateToken("shadow-cust", "user", ownerID, "shadow-cust@example.com")

	// The corrected hydration contract (what MapTrackingProvider sends after
	// this fix): id + requester_id. user_token must not shadow the job ID.
	req := httptest.NewRequest("GET", "/users/jobs/get?id=shadow-job-1&requester_id="+tokenCust, nil)
	rec := httptest.NewRecorder()
	u.GetJob(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 for ?id=&requester_id=, got %d. Body: %s", rec.Code, rec.Body.String())
	}
	var got map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &got)
	if id, _ := got["id"].(string); id != "shadow-job-1" {
		t.Errorf("expected job shadow-job-1, got: %s", rec.Body.String())
	}

	// Legacy callers that still append user_token alongside the correct
	// params must get the same job — user_token must never win ID resolution.
	reqLegacy := httptest.NewRequest("GET", "/users/jobs/get?id=shadow-job-1&requester_id="+tokenCust+"&user_token="+tokenCust, nil)
	recLegacy := httptest.NewRecorder()
	u.GetJob(recLegacy, reqLegacy)
	if recLegacy.Code != http.StatusOK {
		t.Errorf("legacy param combination broken: %d %s", recLegacy.Code, recLegacy.Body.String())
	}
}
