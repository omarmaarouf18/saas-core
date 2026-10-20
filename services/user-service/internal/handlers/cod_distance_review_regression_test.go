package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"testing"
	"time"

	"github.com/project/shared/infra/jwtutil"
	"github.com/project/user-service/internal/models"
	"github.com/project/user-service/internal/store"
)

// FIX-COD-RECON: the ADR-0007 under-distance check ran before the COD branch
// of CompleteJob, so a COD delivery whose tracked GPS trail was < 70 % of the
// booked distance was parked in escrow_reconciliation_required and returned
// early: the collected cash was never recorded and the job sat in the escrow
// queue although no platform money was held.

const codReviewOwner = "owner-cod-review"

// seedCODReviewService creates a delivery service (base 10, 2/km) for the
// FIX-COD-RECON tests and returns an owner token.
func seedCODReviewService(t *testing.T, s *store.MongoDB, ctx context.Context) string {
	t.Helper()
	mustCreateService(t, s, ctx, &models.Service{
		ID: "svc-cod-review", TenantID: codReviewOwner, Name: "Review Delivery", Category: "delivery",
		TenantBasePrice: 10.0, TenantPricePerKM: 2.0, Latitude: 30.0, Longitude: 30.0,
	})
	tok, _ := jwtutil.GenerateToken(codReviewOwner, "owner", codReviewOwner, "o@codreview.test")
	return tok
}

// codReviewJob is an active delivery job booked at 99.9 km whose single
// waypoint is ~5 km from the pickup (well under the 70 % threshold) unless
// waypoints are overridden.
func codReviewJob(id, payment string, waypoints []models.Location) *models.Job {
	if waypoints == nil {
		waypoints = []models.Location{{Latitude: 30.045, Longitude: 30.0}}
	}
	return &models.Job{
		ID: id, OwnerID: codReviewOwner, EmployeeID: "emp-cod-review", UserID: "cust-cod-review",
		ServiceID: "svc-cod-review", Status: models.JobStatusActive, PaymentMethod: payment,
		Location:       models.Location{Latitude: 30.0, Longitude: 30.0},
		Destination:    models.Location{Latitude: 30.9, Longitude: 30.0},
		BookedDistance: 99.9, Waypoints: waypoints,
		CreatedAt: time.Now().Add(-30 * time.Minute).UTC(), UpdatedAt: time.Now().UTC(),
	}
}

// jobDocJSON returns the stored job as raw JSON so assertions on new fields
// compile (and fail honestly) against pre-fix models.
func jobDocJSON(t *testing.T, s *store.MongoDB, ctx context.Context, id string) (*models.Job, map[string]any) {
	t.Helper()
	job := s.GetJob(ctx, id)
	if job == nil {
		t.Fatalf("job %s not found", id)
	}
	raw, _ := json.Marshal(job)
	var m map[string]any
	_ = json.Unmarshal(raw, &m)
	return job, m
}

// TestCompleteJob_CODUnderDistanceCompletesWithReviewFlag: COD + mismatch
// must return 200, complete the job, record the collected cash and attach a
// distance_review flag without touching the escrow reconciliation status.
func TestCompleteJob_CODUnderDistanceCompletesWithReviewFlag(t *testing.T) {
	h, s, ctx := setupCODFeeHarness(t)
	if h == nil {
		return
	}
	tok := seedCODReviewService(t, s, ctx)
	job := codReviewJob("job-cod-review-short", "cod", nil)
	if err := s.CreateJob(ctx, job); err != nil {
		t.Fatalf("create job: %v", err)
	}

	w, res := completeViaHTTP(t, h, map[string]any{
		"job_id": job.ID, "cash_collected": true, "actual_cash_amount": 150.25, "requester_id": tok,
	})
	if w.Code != http.StatusOK {
		t.Fatalf("CompleteJob: want 200, got %d %s", w.Code, w.Body.String())
	}
	if res["cash_amount_recorded"] != 150.25 {
		t.Errorf("response cash_amount_recorded = %v, want 150.25 (COD path must run)", res["cash_amount_recorded"])
	}

	got, doc := jobDocJSON(t, s, ctx, job.ID)
	if got.Status != models.JobStatusCompleted {
		t.Errorf("status = %s, want completed (COD completion must never be blocked by the distance check)", got.Status)
	}
	if doc["actual_cash_amount"] != 150.25 {
		t.Errorf("actual_cash_amount = %v, want 150.25 (collected cash was never recorded)", doc["actual_cash_amount"])
	}
	if doc["locked_escrow_amount"] != nil {
		t.Errorf("locked_escrow_amount = %v, want absent (COD holds no platform money)", doc["locked_escrow_amount"])
	}
	review, ok := doc["distance_review"].(map[string]any)
	if !ok {
		t.Fatalf("distance_review flag missing on stored job: %s", mustJSON(doc))
	}
	if booked, _ := review["booked_km"].(float64); booked != 99.9 {
		t.Errorf("distance_review.booked_km = %v, want 99.9", review["booked_km"])
	}
	if actual, _ := review["actual_km"].(float64); actual <= 0 || actual >= 0.70*99.9 {
		t.Errorf("distance_review.actual_km = %v, want the tracked (~5 km) distance", review["actual_km"])
	}
	if at, _ := review["flagged_at"].(string); at == "" {
		t.Errorf("distance_review.flagged_at missing: %v", review)
	}
	if _, ok := res["distance_review"]; !ok {
		t.Errorf("response lacks distance_review: %v", res)
	}
}

// TestCompleteJob_CODNormalDistanceUnchanged: a COD job whose trail matches
// the booking completes exactly as before and carries no review flag.
func TestCompleteJob_CODNormalDistanceUnchanged(t *testing.T) {
	h, s, ctx := setupCODFeeHarness(t)
	if h == nil {
		return
	}
	tok := seedCODReviewService(t, s, ctx)
	job := codReviewJob("job-cod-review-normal", "cod", []models.Location{
		{Latitude: 30.45, Longitude: 30.0}, {Latitude: 30.9, Longitude: 30.0},
	})
	if err := s.CreateJob(ctx, job); err != nil {
		t.Fatalf("create job: %v", err)
	}

	w, res := completeViaHTTP(t, h, map[string]any{
		"job_id": job.ID, "cash_collected": true, "actual_cash_amount": 209.8, "requester_id": tok,
	})
	if w.Code != http.StatusOK {
		t.Fatalf("CompleteJob: want 200, got %d %s", w.Code, w.Body.String())
	}
	if res["cash_amount_recorded"] != 209.8 {
		t.Errorf("cash_amount_recorded = %v, want 209.8", res["cash_amount_recorded"])
	}
	if _, ok := res["distance_review"]; ok {
		t.Errorf("unexpected distance_review in response: %v", res)
	}
	got, doc := jobDocJSON(t, s, ctx, job.ID)
	if got.Status != models.JobStatusCompleted || doc["actual_cash_amount"] != 209.8 {
		t.Errorf("want completed with cash 209.8, got status=%s cash=%v", got.Status, doc["actual_cash_amount"])
	}
	if _, ok := doc["distance_review"]; ok {
		t.Errorf("unexpected distance_review on stored job: %v", doc["distance_review"])
	}
}

// TestCompleteJob_WalletUnderDistanceStillReconciles: non-COD behaviour is
// unchanged — the job is still parked in escrow_reconciliation_required with
// the locked escrow preserved and no review flag.
func TestCompleteJob_WalletUnderDistanceStillReconciles(t *testing.T) {
	h, s, ctx := setupCODFeeHarness(t)
	if h == nil {
		return
	}
	tok := seedCODReviewService(t, s, ctx)
	job := codReviewJob("job-wallet-review-short", "wallet", nil)
	job.LockedEscrowAmount = 209.8
	if err := s.CreateJob(ctx, job); err != nil {
		t.Fatalf("create job: %v", err)
	}
	if err := s.Deposit(ctx, codReviewOwner, 300.0); err != nil {
		t.Fatalf("deposit: %v", err)
	}
	if err := s.LockEscrow(ctx, codReviewOwner, job.ID, 209.8); err != nil {
		t.Fatalf("lock escrow: %v", err)
	}

	w, res := completeViaHTTP(t, h, map[string]any{"job_id": job.ID, "requester_id": tok})
	if w.Code != http.StatusOK {
		t.Fatalf("CompleteJob: want 200, got %d %s", w.Code, w.Body.String())
	}
	if res["status"] != string(models.JobStatusEscrowReconciliationRequired) {
		t.Errorf("response status = %v, want escrow_reconciliation_required", res["status"])
	}
	got, doc := jobDocJSON(t, s, ctx, job.ID)
	if got.Status != models.JobStatusEscrowReconciliationRequired {
		t.Errorf("status = %s, want escrow_reconciliation_required", got.Status)
	}
	if got.LockedEscrowAmount != 209.8 || got.EscrowFailureReason != "under_distance_mismatch" {
		t.Errorf("want locked 209.8 / reason under_distance_mismatch, got %.2f / %q", got.LockedEscrowAmount, got.EscrowFailureReason)
	}
	if _, ok := doc["distance_review"]; ok {
		t.Errorf("non-COD job must not carry distance_review: %v", doc["distance_review"])
	}
}

func mustJSON(v any) string {
	b, _ := json.Marshal(v)
	return string(bytes.TrimSpace(b))
}
