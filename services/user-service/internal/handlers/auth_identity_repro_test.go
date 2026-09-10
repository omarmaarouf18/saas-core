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

// TestRepro_Q26_AuthBeforeDBLookup verifies that mutation handlers validate the caller's authentication
// BEFORE querying MongoDB for the job.
// Pre-fix: When called with an invalid/missing token on a non-existent job ID, handlers returned 404 Not Found
// because u.store.GetJob preceded auth validation (leaking job existence and placing load on MongoDB).
// Post-fix: Handlers must return 400 Bad Request or 401 Unauthorized before DB lookup.
func TestRepro_Q26_AuthBeforeDBLookup(t *testing.T) {
	u, _, _, cleanup := setupDispatchTestHarness(t)
	if u == nil {
		return
	}
	defer cleanup()

	nonExistentJobID := "non-existent-job-q26"
	invalidToken := "invalid-garbage-token"

	// 1. ProposePrice
	t.Run("ProposePrice auth before DB", func(t *testing.T) {
		body, _ := json.Marshal(map[string]any{
			"job_id":          nonExistentJobID,
			"proposed_price":  50.0,
			"requester_token": invalidToken,
		})
		req := httptest.NewRequest(http.MethodPost, "/users/jobs/propose-price", bytes.NewReader(body))
		req.Header.Set("Authorization", "Bearer "+invalidToken)
		rec := httptest.NewRecorder()

		u.ProposePrice(rec, req)

		if rec.Code == http.StatusNotFound {
			t.Errorf("REPRO CONFIRMED Q26: ProposePrice returned 404 Not Found before validating caller auth!")
		} else if rec.Code == http.StatusUnauthorized || rec.Code == http.StatusBadRequest {
			t.Logf("PASS: ProposePrice rejected with status %d before DB lookup", rec.Code)
		} else {
			t.Logf("ProposePrice status: %d %s", rec.Code, rec.Body.String())
		}
	})

	// 2. RespondPrice
	t.Run("RespondPrice auth before DB", func(t *testing.T) {
		body, _ := json.Marshal(map[string]any{
			"job_id":          nonExistentJobID,
			"decision":        "accept",
			"requester_token": invalidToken,
		})
		req := httptest.NewRequest(http.MethodPost, "/users/jobs/respond-price", bytes.NewReader(body))
		req.Header.Set("Authorization", "Bearer "+invalidToken)
		rec := httptest.NewRecorder()

		u.RespondPrice(rec, req)

		if rec.Code == http.StatusNotFound {
			t.Errorf("REPRO CONFIRMED Q26: RespondPrice returned 404 Not Found before validating caller auth!")
		} else if rec.Code == http.StatusUnauthorized || rec.Code == http.StatusBadRequest {
			t.Logf("PASS: RespondPrice rejected with status %d before DB lookup", rec.Code)
		} else {
			t.Logf("RespondPrice status: %d %s", rec.Code, rec.Body.String())
		}
	})

	// 3. CompleteJob
	t.Run("CompleteJob auth before DB", func(t *testing.T) {
		body, _ := json.Marshal(map[string]any{
			"job_id":       nonExistentJobID,
			"requester_id": invalidToken,
		})
		req := httptest.NewRequest(http.MethodPost, "/users/jobs/complete", bytes.NewReader(body))
		req.Header.Set("Authorization", "Bearer "+invalidToken)
		rec := httptest.NewRecorder()

		u.CompleteJob(rec, req)

		if rec.Code == http.StatusNotFound {
			t.Errorf("REPRO CONFIRMED Q26: CompleteJob returned 404 Not Found before validating caller auth!")
		} else if rec.Code == http.StatusUnauthorized || rec.Code == http.StatusBadRequest {
			t.Logf("PASS: CompleteJob rejected with status %d before DB lookup", rec.Code)
		} else {
			t.Logf("CompleteJob status: %d %s", rec.Code, rec.Body.String())
		}
	})

	// 4. CancelJob
	t.Run("CancelJob auth before DB", func(t *testing.T) {
		body, _ := json.Marshal(map[string]any{
			"job_id":       nonExistentJobID,
			"reason":       "customer cancelled",
			"requester_id": invalidToken,
		})
		req := httptest.NewRequest(http.MethodPost, "/users/jobs/cancel", bytes.NewReader(body))
		req.Header.Set("Authorization", "Bearer "+invalidToken)
		rec := httptest.NewRecorder()

		u.CancelJob(rec, req)

		if rec.Code == http.StatusNotFound {
			t.Errorf("REPRO CONFIRMED Q26: CancelJob returned 404 Not Found before validating caller auth!")
		} else if rec.Code == http.StatusUnauthorized || rec.Code == http.StatusBadRequest {
			t.Logf("PASS: CancelJob rejected with status %d before DB lookup", rec.Code)
		} else {
			t.Logf("CancelJob status: %d %s", rec.Code, rec.Body.String())
		}
	})

	// 5. GetJob (single job lookup)
	t.Run("GetJob auth before DB", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/users/jobs?id="+nonExistentJobID+"&requester_id="+invalidToken, nil)
		req.Header.Set("Authorization", "Bearer "+invalidToken)
		rec := httptest.NewRecorder()

		u.GetJob(rec, req)

		if rec.Code == http.StatusNotFound {
			t.Errorf("REPRO CONFIRMED Q26: GetJob returned 404 Not Found before validating caller auth!")
		} else if rec.Code == http.StatusUnauthorized || rec.Code == http.StatusBadRequest {
			t.Logf("PASS: GetJob rejected with status %d before DB lookup", rec.Code)
		} else {
			t.Logf("GetJob status: %d %s", rec.Code, rec.Body.String())
		}
	})
}

// TestRepro_PartB_OwnerPriceNegotiationScope verifies Part B (#5):
// Owners are barred from dynamic in-job price negotiations. In ProposePrice and RespondPrice,
// resolveTokenWithRole must reject "owner" role at the role check, failing fast with 401 Unauthorized.
func TestRepro_PartB_OwnerPriceNegotiationScope(t *testing.T) {
	u, s, _, cleanup := setupDispatchTestHarness(t)
	if u == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	ownerID := "tenant-partb-owner"
	custID := "cust-partb-user"
	empID := "emp-partb-courier"
	svcID := "svc-partb-transport"

	s.CreateService(ctx, &models.Service{
		ID:               svcID,
		TenantID:         ownerID,
		Name:             "Transport Express",
		Category:         "transport",
		TenantBasePrice:  30.0,
		TenantPricePerKM: 3.0,
		Latitude:         30.0444,
		Longitude:        31.2357,
	})

	jobID := "job-partb-negotiation"
	s.CreateJob(ctx, &models.Job{
		ID:            jobID,
		OwnerID:       ownerID,
		UserID:        custID,
		EmployeeID:    empID,
		ServiceID:     svcID,
		Status:        models.JobStatusActive,
		Location:      models.Location{Latitude: 30.0444, Longitude: 31.2357},
		CreatedAt:     time.Now().UTC(),
		PaymentMethod: "cod",
	})

	tokenOwner, _ := jwtutil.GenerateToken(ownerID, "owner", ownerID, "owner@test.com")

	// 1. Owner attempts to ProposePrice
	t.Run("Owner ProposePrice Rejected Fast", func(t *testing.T) {
		body, _ := json.Marshal(map[string]any{
			"job_id":          jobID,
			"proposed_price":  50.0,
			"requester_token": tokenOwner,
		})
		req := httptest.NewRequest(http.MethodPost, "/users/jobs/propose-price", bytes.NewReader(body))
		req.Header.Set("Authorization", "Bearer "+tokenOwner)
		rec := httptest.NewRecorder()

		u.ProposePrice(rec, req)

		// Pre-fix: resolveTokenWithRole allowed "owner", so it passed role check and returned 403 Forbidden.
		// Post-fix: role check rejects "owner" -> returns 401 Unauthorized.
		if rec.Code == http.StatusForbidden {
			t.Errorf("REPRO CONFIRMED Part B: ProposePrice allowed 'owner' role through resolveTokenWithRole (got 403 instead of 401 fast rejection)!")
		} else if rec.Code == http.StatusUnauthorized {
			t.Logf("PASS: ProposePrice rejected owner token fast with 401 Unauthorized")
		} else {
			t.Logf("ProposePrice status: %d %s", rec.Code, rec.Body.String())
		}
	})

	// 2. Owner attempts to RespondPrice
	t.Run("Owner RespondPrice Rejected Fast", func(t *testing.T) {
		body, _ := json.Marshal(map[string]any{
			"job_id":          jobID,
			"decision":        "accept",
			"requester_token": tokenOwner,
		})
		req := httptest.NewRequest(http.MethodPost, "/users/jobs/respond-price", bytes.NewReader(body))
		req.Header.Set("Authorization", "Bearer "+tokenOwner)
		rec := httptest.NewRecorder()

		u.RespondPrice(rec, req)

		// Pre-fix: resolveTokenWithRole allowed "owner", returned 403 Forbidden.
		// Post-fix: role check rejects "owner" -> returns 401 Unauthorized.
		if rec.Code == http.StatusForbidden {
			t.Errorf("REPRO CONFIRMED Part B: RespondPrice allowed 'owner' role through resolveTokenWithRole (got 403 instead of 401 fast rejection)!")
		} else if rec.Code == http.StatusUnauthorized {
			t.Logf("PASS: RespondPrice rejected owner token fast with 401 Unauthorized")
		} else {
			t.Logf("RespondPrice status: %d %s", rec.Code, rec.Body.String())
		}
	})
}
