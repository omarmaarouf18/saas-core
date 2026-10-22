package handlers

// ADR-0028 item 3: status_history on every transition. Two lifecycle walks
// at the handler level: each step drives a REAL endpoint (asserting its
// status code and job-level outcome), then reads the persisted job from the
// standalone test database to assert the EXACT status_history sequence the
// handlers+store produced. Endpoint responses carry the pre-mutation local
// job copy, so the DB (not the response echo) is the source of truth for
// appended entries.
//
//   1. delivery COD: TrackJob (cascade) -> accept -> complete
//   2. transport COD: TrackJob (cascade) -> accept -> propose-price ->
//      respond-price accept -> cancellation request -> owner rejection ->
//      second request -> owner approval (real cancel)
//
// The cancellation-request deltas are status-agnostic "$status" pipeline
// entries: the store resolves the ref to the job's live status at append
// time (active in both walks).

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/project/shared/infra/jwtutil"
	"github.com/project/shared/infra/testutil"
	"github.com/project/user-service/internal/config"
	"github.com/project/user-service/internal/models"
	"github.com/project/user-service/internal/store"
	"github.com/redis/go-redis/v9"
)

// v2UserServiceWithRoles clones trackJobClosedStatusHarness but with an auth
// mock that answers by role: the owner id, employee ids (and anything not
// listed), resolve with per-id role/tenant so verifyEmployeeAssignment can
// approve seeded couriers — the default harness mock stamps every id as
// role=owner, which correctly REJECTS couriers in cascade dispatch.
func v2UserServiceWithRoles(t *testing.T, s *store.MongoDB, ownerID string, empIDs ...string) *UserService {
	t.Helper()
	mockAuthServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		id := r.URL.Query().Get("id")
		resp := map[string]any{
			"id": id, "role": "owner", "kyc_status": "approved",
			"is_active": true, "tenant_id": id,
		}
		if id != ownerID {
			resp["role"] = "employee"
		}
		for _, e := range empIDs {
			if id == e {
				resp["role"] = "employee"
				resp["tenant_id"] = ownerID
			}
		}
		w.WriteHeader(http.StatusOK)
		_ = json.NewEncoder(w).Encode(resp)
	}))
	t.Cleanup(mockAuthServer.Close)
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	t.Cleanup(func() { mr.Close() })
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	t.Cleanup(func() { rdb.Close() })
	cfg := &config.Config{
		AuthServiceURL:       mockAuthServer.URL,
		InternalServiceToken: "mock-internal-token",
		AppEnv:               "test",
	}
	return NewUserService(s, cfg, rdb)
}

// v2JobID extracts the job id from a response carrying a job object.
func v2JobID(t *testing.T, resp *httptest.ResponseRecorder, step string) string {
	t.Helper()
	var body map[string]any
	if err := json.Unmarshal(resp.Body.Bytes(), &body); err != nil {
		t.Fatalf("%s: decode response: %v (%s)", step, err, resp.Body.String())
	}
	job, ok := body["job"].(map[string]any)
	if !ok {
		t.Fatalf("%s: response has no job object: %s", step, resp.Body.String())
	}
	id, _ := job["id"].(string)
	if id == "" {
		t.Fatalf("%s: empty job id: %s", step, resp.Body.String())
	}
	return id
}

// v2CheckEntry asserts history[idx] in the DB matches the expected
// transition (adr-0028 §2.3): status, actor role, actor id, reason.
func v2CheckEntry(t *testing.T, s *store.MongoDB, ctx context.Context, jobID string, idx int, wantStatus models.JobStatus, wantRole, wantActor, wantReason string) models.JobStatusHistoryEntry {
	t.Helper()
	job := s.GetJob(ctx, jobID)
	if job == nil {
		t.Fatalf("job %s not found in store", jobID)
	}
	if len(job.StatusHistory) <= idx {
		t.Fatalf("history too short at step %d: got %d entries: %+v", idx, len(job.StatusHistory), job.StatusHistory)
	}
	e := job.StatusHistory[idx]
	if e.Status != wantStatus {
		t.Errorf("history[%d].status = %q, want %q (history: %+v)", idx, e.Status, wantStatus, job.StatusHistory)
	}
	if e.ActorRole != wantRole {
		t.Errorf("history[%d].actor_role = %q, want %q", idx, e.ActorRole, wantRole)
	}
	if e.ActorID != wantActor {
		t.Errorf("history[%d].actor_id = %q, want %q", idx, e.ActorID, wantActor)
	}
	if wantReason != "" && e.Reason != wantReason {
		t.Errorf("history[%d].reason = %q, want %q", idx, e.Reason, wantReason)
	}
	return e
}

// v2CheckHistoryLen asserts the DB history has exactly n entries.
func v2CheckHistoryLen(t *testing.T, s *store.MongoDB, ctx context.Context, jobID string, n int) []models.JobStatusHistoryEntry {
	t.Helper()
	job := s.GetJob(ctx, jobID)
	if job == nil {
		t.Fatalf("job %s not found in store", jobID)
	}
	if len(job.StatusHistory) != n {
		t.Fatalf("expected exactly %d history entries, got %d: %+v", n, len(job.StatusHistory), job.StatusHistory)
	}
	return job.StatusHistory
}

// TestV2StatusHistory_CODDeliveryLifecycle walks a delivery job created
// through cascade dispatch as COD and completed through the tracker:
// pending_dispatch (created, customer) -> active (accepted, employee) ->
// completed (completed, employee).
func TestV2StatusHistory_CODDeliveryLifecycle(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	s, _, ctx, cleanup := setupClosedStatusHarness(t)
	defer cleanup()

	ownerID, custID, empID := "hist-owner-1", "hist-cust-1", "hist-emp-1"
	u := v2UserServiceWithRoles(t, s, ownerID, empID)
	seedClosedStatusSub(t, s, ctx, ownerID, models.PlanPaid, time.Now().UTC().Add(time.Hour))
	mustCreateService(t, s, ctx, &models.Service{
		ID: "svc-hist-1", TenantID: ownerID, Name: "Hist Delivery",
		Category: "delivery", TenantBasePrice: 10.0, TenantPricePerKM: 2.0,
		Latitude: 30.0444, Longitude: 31.2357,
	})
	if err := s.UpsertEmployeeLocation(ctx, &models.EmployeeLocation{
		TenantID: ownerID, EmployeeID: empID,
		Latitude: 30.0444, Longitude: 31.2357, UpdatedAt: time.Now().UTC(),
	}); err != nil {
		t.Fatalf("seed UpsertEmployeeLocation: %v", err)
	}

	tokenUser, _ := jwtutil.GenerateToken(custID, "user", ownerID, "hist-cust@x.com")
	tokenEmp, _ := jwtutil.GenerateToken(empID, "employee", ownerID, "hist-emp@x.com")

	rec := postClosedStatusTrack(t, u, map[string]any{
		"service_id":     "svc-hist-1",
		"user_id":        tokenUser,
		"payment_method": "cod",
		"location":       map[string]any{"latitude": 30.0444, "longitude": 31.2357},
		"destination":    map[string]any{"latitude": 30.05, "longitude": 31.24},
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("track: expected 201, got %d: %s", rec.Code, rec.Body.String())
	}
	jobID := v2JobID(t, rec, "track")
	v2CheckHistoryLen(t, s, ctx, jobID, 1)
	v2CheckEntry(t, s, ctx, jobID, 0, models.JobStatusPendingDispatch, "customer", "", "job created")

	// Courier accepts the cascade offer.
	acceptReq := httptest.NewRequest("POST", fmt.Sprintf("/users/employee/jobs/%s/accept", jobID), nil)
	acceptReq.Header.Set("Authorization", "Bearer "+tokenEmp)
	acceptRec := httptest.NewRecorder()
	u.AcceptJobOffer(acceptRec, acceptReq)
	if acceptRec.Code != http.StatusOK {
		t.Fatalf("accept: expected 200, got %d: %s", acceptRec.Code, acceptRec.Body.String())
	}
	v2CheckHistoryLen(t, s, ctx, jobID, 2)
	v2CheckEntry(t, s, ctx, jobID, 1, models.JobStatusActive, "employee", empID, "offer accepted")
	accepted := s.GetJob(ctx, jobID)
	if accepted.SubStatus != models.SubStatusHeadingToPickup {
		t.Fatalf("expected sub_status heading_to_pickup after accept, got %q", accepted.SubStatus)
	}

	// Courier confirms the physical pickup.
	pickBody, _ := json.Marshal(map[string]any{"job_id": jobID, "requester_token": tokenEmp})
	pickReq := httptest.NewRequest("POST", "/users/jobs/pickup", strings.NewReader(string(pickBody)))
	pickReq.Header.Set("Content-Type", "application/json")
	pickRec := httptest.NewRecorder()
	u.PickupJob(pickRec, pickReq)
	if pickRec.Code != http.StatusOK {
		t.Fatalf("pickup: expected 200, got %d: %s", pickRec.Code, pickRec.Body.String())
	}
	pickedUpRec := s.GetJob(ctx, jobID)
	if pickedUpRec.SubStatus != models.SubStatusPickedUp {
		t.Fatalf("expected sub_status picked_up after pickup, got %q", pickedUpRec.SubStatus)
	}
	v2CheckHistoryLen(t, s, ctx, jobID, 3)
	v2CheckEntry(t, s, ctx, jobID, 2, models.JobStatusActive, "employee", empID, "package picked up; heading to destination")

	// Double pickup is rejected with a stable conflict.
	pickReq2 := httptest.NewRequest("POST", "/users/jobs/pickup", strings.NewReader(string(pickBody)))
	pickReq2.Header.Set("Content-Type", "application/json")
	pickRec2 := httptest.NewRecorder()
	u.PickupJob(pickRec2, pickReq2)
	if pickRec2.Code != http.StatusConflict {
		t.Fatalf("double pickup: expected 409, got %d: %s", pickRec2.Code, pickRec2.Body.String())
	}

	// Courier completes the COD job.
	compBody, _ := json.Marshal(map[string]any{"job_id": jobID, "cash_collected": true})
	compReq := httptest.NewRequest("POST", "/users/jobs/complete", strings.NewReader(string(compBody)))
	compReq.Header.Set("Content-Type", "application/json")
	compReq.Header.Set("Authorization", "Bearer "+tokenEmp)
	compRec := httptest.NewRecorder()
	u.CompleteJob(compRec, compReq)
	if compRec.Code != http.StatusOK {
		t.Fatalf("complete: expected 200, got %d: %s", compRec.Code, compRec.Body.String())
	}
	entries := v2CheckHistoryLen(t, s, ctx, jobID, 4)
	// No waypoints were recorded on the walk, so ADR-0007's under-distance
	// review fires and the completion reason carries the review flag.
	v2CheckEntry(t, s, ctx, jobID, 3, models.JobStatusCompleted, "employee", empID, "COD job completed; under-distance review flagged (ADR-0007)")
	if entries[0].Status != models.JobStatusPendingDispatch ||
		entries[1].Status != models.JobStatusActive ||
		entries[2].Status != models.JobStatusActive ||
		entries[3].Status != models.JobStatusCompleted {
		t.Fatalf("unexpected final status walk: %+v", entries)
	}
	// ADR-0028 §2.9: sub_status is cleared on the exit from active.
	fin := s.GetJob(ctx, jobID)
	if fin.SubStatus != "" {
		t.Fatalf("expected sub_status cleared on completion, got %q", fin.SubStatus)
	}
}

// TestV2StatusHistory_TransportPriceAndCancellationLifecycle walks a
// transport job through price negotiation and the cancellation-request
// flow. The request/rejection deltas arrive while the job is active and
// must resolve the "$status" ref to the live status (active), never append
// an empty status.
func TestV2StatusHistory_TransportPriceAndCancellationLifecycle(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	s, _, ctx, cleanup := setupClosedStatusHarness(t)
	defer cleanup()

	ownerID, custID, empID := "hist-owner-2", "hist-cust-2", "hist-emp-2"
	u := v2UserServiceWithRoles(t, s, ownerID, empID)
	seedClosedStatusSub(t, s, ctx, ownerID, models.PlanPaid, time.Now().UTC().Add(time.Hour))
	mustCreateService(t, s, ctx, &models.Service{
		ID: "svc-hist-2", TenantID: ownerID, Name: "Hist Transport",
		Category: "transport", TenantBasePrice: 40.0, TenantPricePerKM: 2.0,
		Latitude: 30.0444, Longitude: 31.2357,
	})
	if err := s.UpsertEmployeeLocation(ctx, &models.EmployeeLocation{
		TenantID: ownerID, EmployeeID: empID,
		Latitude: 30.0444, Longitude: 31.2357, UpdatedAt: time.Now().UTC(),
	}); err != nil {
		t.Fatalf("seed UpsertEmployeeLocation: %v", err)
	}

	tokenUser, _ := jwtutil.GenerateToken(custID, "user", ownerID, "hist-cust2@x.com")
	tokenEmp, _ := jwtutil.GenerateToken(empID, "employee", ownerID, "hist-emp2@x.com")
	tokenOwner, _ := jwtutil.GenerateToken(ownerID, "owner", ownerID, "hist-owner2@x.com")

	var ipCounter int
	nextIP := func() string {
		ipCounter++
		return testutil.IP("hist-lifecycle", ipCounter)
	}

	rec := postClosedStatusTrack(t, u, map[string]any{
		"service_id":     "svc-hist-2",
		"user_id":        tokenUser,
		"payment_method": "cod",
		"location":       map[string]any{"latitude": 30.0444, "longitude": 31.2357},
		"destination":    map[string]any{"latitude": 30.05, "longitude": 31.24},
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("track: expected 201, got %d: %s", rec.Code, rec.Body.String())
	}
	jobID := v2JobID(t, rec, "track")
	v2CheckHistoryLen(t, s, ctx, jobID, 1)
	v2CheckEntry(t, s, ctx, jobID, 0, models.JobStatusPendingDispatch, "customer", "", "job created")

	// Courier accepts: transport goes to awaiting_price_response with the
	// system-suggested baseline price.
	acceptReq := httptest.NewRequest("POST", fmt.Sprintf("/users/employee/jobs/%s/accept", jobID), nil)
	acceptReq.Header.Set("Authorization", "Bearer "+tokenEmp)
	acceptRec := httptest.NewRecorder()
	u.AcceptJobOffer(acceptRec, acceptReq)
	if acceptRec.Code != http.StatusOK {
		t.Fatalf("accept: expected 200, got %d: %s", acceptRec.Code, acceptRec.Body.String())
	}
	v2CheckHistoryLen(t, s, ctx, jobID, 2)
	v2CheckEntry(t, s, ctx, jobID, 1, models.JobStatusAwaitingPriceResponse, "employee", empID, "offer accepted; awaiting price agreement")

	// Employee proposes an in-job price.
	propBody, _ := json.Marshal(map[string]any{"job_id": jobID, "proposed_price": 45.0, "requester_token": tokenEmp})
	propReq := httptest.NewRequest("POST", "/users/jobs/propose-price", strings.NewReader(string(propBody)))
	propReq.Header.Set("Content-Type", "application/json")
	propReq.Header.Set("X-Real-IP", nextIP())
	propRec := httptest.NewRecorder()
	u.ProposePrice(propRec, propReq)
	if propRec.Code != http.StatusOK {
		t.Fatalf("propose: expected 200, got %d: %s", propRec.Code, propRec.Body.String())
	}
	v2CheckHistoryLen(t, s, ctx, jobID, 3)
	v2CheckEntry(t, s, ctx, jobID, 2, models.JobStatusAwaitingPriceResponse, "employee", empID, "price proposed: 45.00")

	// Customer agrees: active.
	respBody, _ := json.Marshal(map[string]any{"job_id": jobID, "decision": "accept", "requester_token": tokenUser})
	respReq := httptest.NewRequest("POST", "/users/jobs/respond-price", strings.NewReader(string(respBody)))
	respReq.Header.Set("Content-Type", "application/json")
	respReq.Header.Set("X-Real-IP", nextIP())
	respRec := httptest.NewRecorder()
	u.RespondPrice(respRec, respReq)
	if respRec.Code != http.StatusOK {
		t.Fatalf("respond-accept: expected 200, got %d: %s", respRec.Code, respRec.Body.String())
	}
	v2CheckHistoryLen(t, s, ctx, jobID, 4)
	v2CheckEntry(t, s, ctx, jobID, 3, models.JobStatusActive, "customer", custID, "price agreed")
	agreed := s.GetJob(ctx, jobID)
	if agreed.SubStatus != models.SubStatusHeadingToPickup {
		t.Fatalf("expected sub_status heading_to_pickup after price agreement, got %q", agreed.SubStatus)
	}

	// Employee submits a cancellation request: status-UNION event with a
	// "$status" ref, resolved to the live active status.
	reqBody, _ := json.Marshal(map[string]any{"job_id": jobID, "reason": "traffic heavy", "requester_token": tokenEmp})
	reqReq := httptest.NewRequest("POST", "/users/jobs/request-cancellation", strings.NewReader(string(reqBody)))
	reqReq.Header.Set("Content-Type", "application/json")
	reqReq.Header.Set("X-Real-IP", nextIP())
	reqRec := httptest.NewRecorder()
	u.RequestCancellation(reqRec, reqReq)
	if reqRec.Code != http.StatusOK {
		t.Fatalf("request-cancellation: expected 200, got %d: %s", reqRec.Code, reqRec.Body.String())
	}
	v2CheckHistoryLen(t, s, ctx, jobID, 5)
	v2CheckEntry(t, s, ctx, jobID, 4, models.JobStatusActive, "employee", empID, "cancellation request submitted; reason: traffic heavy")

	// Owner rejects: still active; the rejection event keeps the live status.
	declBody, _ := json.Marshal(map[string]any{"job_id": jobID, "decision": "decline", "requester_token": tokenOwner})
	declReq := httptest.NewRequest("POST", "/users/jobs/respond-cancellation", strings.NewReader(string(declBody)))
	declReq.Header.Set("Content-Type", "application/json")
	declReq.Header.Set("X-Real-IP", nextIP())
	declRec := httptest.NewRecorder()
	u.RespondCancellation(declRec, declReq)
	if declRec.Code != http.StatusOK {
		t.Fatalf("respond-decline: expected 200, got %d: %s", declRec.Code, declRec.Body.String())
	}
	v2CheckHistoryLen(t, s, ctx, jobID, 6)
	v2CheckEntry(t, s, ctx, jobID, 5, models.JobStatusActive, "owner", ownerID, "cancellation request rejected; courier stays assigned")
	jobAfterReject := s.GetJob(ctx, jobID)
	if jobAfterReject.Status != models.JobStatusActive {
		t.Fatalf("expected active after rejection, got %q", jobAfterReject.Status)
	}

	// Second request after the rejection, then owner approval: the real
	// cancel transition carries the owner-cancelled entry.
	reqBody2, _ := json.Marshal(map[string]any{"job_id": jobID, "reason": "traffic heavy", "requester_token": tokenEmp})
	reqReq2 := httptest.NewRequest("POST", "/users/jobs/request-cancellation", strings.NewReader(string(reqBody2)))
	reqReq2.Header.Set("Content-Type", "application/json")
	reqReq2.Header.Set("X-Real-IP", nextIP())
	reqRec2 := httptest.NewRecorder()
	u.RequestCancellation(reqRec2, reqReq2)
	if reqRec2.Code != http.StatusOK {
		t.Fatalf("request-cancellation 2: expected 200, got %d: %s", reqRec2.Code, reqRec2.Body.String())
	}
	v2CheckHistoryLen(t, s, ctx, jobID, 7)
	v2CheckEntry(t, s, ctx, jobID, 6, models.JobStatusActive, "employee", empID, "cancellation request submitted; reason: traffic heavy")

	appBody, _ := json.Marshal(map[string]any{"job_id": jobID, "decision": "accept", "requester_token": tokenOwner})
	appReq := httptest.NewRequest("POST", "/users/jobs/respond-cancellation", strings.NewReader(string(appBody)))
	appReq.Header.Set("Content-Type", "application/json")
	appReq.Header.Set("X-Real-IP", nextIP())
	appRec := httptest.NewRecorder()
	u.RespondCancellation(appRec, appReq)
	if appRec.Code != http.StatusOK {
		t.Fatalf("respond-accept: expected 200, got %d: %s", appRec.Code, appRec.Body.String())
	}
	var appResp map[string]any
	if err := json.Unmarshal(appRec.Body.Bytes(), &appResp); err != nil {
		t.Fatalf("decode approval response: %v", err)
	}
	if got, _ := appResp["status"].(string); got != string(models.JobStatusCancelled) {
		t.Fatalf("expected cancelled after approval, got %q (%s)", got, appRec.Body.String())
	}

	// Exact DB-level history walk: 8 entries terminal cancelled last, and
	// NO zero-status entries (the "$status" refs resolved to active).
	entries := v2CheckHistoryLen(t, s, ctx, jobID, 8)
	for i, e := range entries {
		if e.Status == "" {
			t.Errorf("history[%d] has empty status ($status ref not resolved): %+v", i, e)
		}
	}
	last := entries[7]
	if last.Status != models.JobStatusCancelled || last.ActorRole != "owner" || last.ActorID != ownerID {
		t.Errorf("terminal cancel entry wrong: %+v", last)
	}
}
