package handlers

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/project/user-service/internal/models"
)

// FIX-COD-RECON item 2: the COD distance_review flag is shown to the owner
// through the owner job DTO, never through the escrow reconciliation queue.

// TestOwnerJobDTO_DistanceReviewOwnerOnly: the flag is part of the owner DTO
// (omitted when unset) and absent from the customer and employee DTOs.
func TestOwnerJobDTO_DistanceReviewOwnerOnly(t *testing.T) {
	flagged := &models.Job{
		ID: "job-dto-review", OwnerID: "o", EmployeeID: "e", UserID: "c", Status: models.JobStatusCompleted,
		PaymentMethod: "cod",
		DistanceReview: &models.DistanceReview{
			ActualKm: 5, BookedKm: 99.9, FlaggedAt: time.Date(2026, 10, 20, 8, 0, 0, 0, time.UTC),
			Source: models.DistanceReviewSourceCompleteJob,
		},
	}
	asMap := func(v any) map[string]any {
		raw, _ := json.Marshal(v)
		var m map[string]any
		_ = json.Unmarshal(raw, &m)
		return m
	}

	owner := asMap(models.NewOwnerJobResponse(flagged))
	review, ok := owner["distance_review"].(map[string]any)
	if !ok {
		t.Fatalf("owner DTO lacks distance_review: %v", owner)
	}
	if review["actual_km"] != 5.0 || review["booked_km"] != 99.9 || review["flagged_at"] != "2026-10-20T08:00:00Z" {
		t.Errorf("owner DTO distance_review = %v", review)
	}
	if _, ok := asMap(models.NewCustomerJobResponse(flagged))["distance_review"]; ok {
		t.Errorf("customer DTO must not expose distance_review")
	}
	if _, ok := asMap(models.NewEmployeeJobResponse(flagged, "e"))["distance_review"]; ok {
		t.Errorf("employee DTO must not expose distance_review")
	}

	unflagged := *flagged
	unflagged.DistanceReview = nil
	if _, ok := asMap(models.NewOwnerJobResponse(&unflagged))["distance_review"]; ok {
		t.Errorf("owner DTO must omit distance_review when unset")
	}
}

// TestCODDistanceReview_VisibleToOwnerNotInReconciliationQueue: after a COD
// under-distance completion the owner sees the flag on GET /users/jobs/get,
// while /users/jobs/reconciliation-queue lists only the non-COD escrow job.
func TestCODDistanceReview_VisibleToOwnerNotInReconciliationQueue(t *testing.T) {
	h, s, ctx := setupCODFeeHarness(t)
	if h == nil {
		return
	}
	tok := seedCODReviewService(t, s, ctx)

	cod := codReviewJob("job-cod-review-visible", "cod", nil)
	wallet := codReviewJob("job-wallet-review-queued", "wallet", nil)
	wallet.LockedEscrowAmount = 209.8
	for _, j := range []*models.Job{cod, wallet} {
		if err := s.CreateJob(ctx, j); err != nil {
			t.Fatalf("create job %s: %v", j.ID, err)
		}
	}
	if err := s.Deposit(ctx, codReviewOwner, 300.0); err != nil {
		t.Fatalf("deposit: %v", err)
	}
	if err := s.LockEscrow(ctx, codReviewOwner, wallet.ID, 209.8); err != nil {
		t.Fatalf("lock escrow: %v", err)
	}
	if w, _ := completeViaHTTP(t, h, map[string]any{"job_id": cod.ID, "cash_collected": true, "requester_id": tok}); w.Code != http.StatusOK {
		t.Fatalf("complete COD: %d %s", w.Code, w.Body.String())
	}
	if w, _ := completeViaHTTP(t, h, map[string]any{"job_id": wallet.ID, "requester_id": tok}); w.Code != http.StatusOK {
		t.Fatalf("complete wallet: %d %s", w.Code, w.Body.String())
	}

	req := httptest.NewRequest(http.MethodGet, "/users/jobs/get?id="+cod.ID, nil)
	req.Header.Set("Authorization", "Bearer "+tok)
	w := httptest.NewRecorder()
	h.GetJob(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("GetJob: %d %s", w.Code, w.Body.String())
	}
	var ownerView map[string]any
	_ = json.Unmarshal(w.Body.Bytes(), &ownerView)
	if ownerView["status"] != string(models.JobStatusCompleted) {
		t.Errorf("owner view status = %v, want completed", ownerView["status"])
	}
	if _, ok := ownerView["distance_review"].(map[string]any); !ok {
		t.Errorf("owner job view lacks distance_review: %s", w.Body.String())
	}

	req = httptest.NewRequest(http.MethodGet, "/users/jobs/reconciliation-queue", nil)
	req.Header.Set("Authorization", "Bearer "+tok)
	w = httptest.NewRecorder()
	h.GetReconciliationQueue(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("GetReconciliationQueue: %d %s", w.Code, w.Body.String())
	}
	var queue []map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &queue); err != nil {
		t.Fatalf("decode queue: %v (%s)", err, w.Body.String())
	}
	ids := map[string]bool{}
	for _, j := range queue {
		ids[j["id"].(string)] = true
	}
	if ids[cod.ID] {
		t.Errorf("COD job %s must not be in the escrow reconciliation queue: %s", cod.ID, w.Body.String())
	}
	if !ids[wallet.ID] || len(queue) != 1 {
		t.Errorf("queue = %s, want only the wallet job %s", w.Body.String(), wallet.ID)
	}
}
