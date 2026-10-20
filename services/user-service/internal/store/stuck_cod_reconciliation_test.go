package store

import (
	"context"
	"testing"

	"go.mongodb.org/mongo-driver/v2/bson"

	"github.com/project/user-service/internal/models"
)

// TestStuckCODReconciliation_CountAndRepair: the count is read-only; the
// repair is a dry run without apply, then completes only the
// under_distance_mismatch COD jobs with the booked amount as cash and a
// distance_review flag, releases the courier lock, and is idempotent.
func TestStuckCODReconciliation_CountAndRepair(t *testing.T) {
	db, _ := beErrRawDB(t)
	ctx := context.Background()
	note := "tracked_distance_mismatch: actual 5.00 km vs booked 99.90 km"
	agreed := 120.0
	if _, err := db.Collection("services").InsertOne(ctx, bson.M{
		"_id": "svc-stuck", "tenant_id": "own-stuck", "category": "delivery",
		"tenant_base_price": 10.0, "tenant_price_per_km": 2.0,
	}); err != nil {
		t.Fatalf("seed service: %v", err)
	}
	jobs := bson.A{
		// repairable: cash = 10 + 99.9*2 = 209.80
		bson.M{"_id": "cod-stuck-1", "owner_id": "own-stuck", "employee_id": "emp-stuck", "service_id": "svc-stuck",
			"payment_method": "cod", "status": "escrow_reconciliation_required", "locked_escrow_amount": 0.0,
			"booked_distance": 99.9, "reconciliation_note": note, "escrow_failure_reason": "under_distance_mismatch"},
		// repairable with agreed price and no locked_escrow_amount field
		bson.M{"_id": "cod-stuck-2", "owner_id": "own-stuck", "service_id": "svc-stuck", "agreed_price": agreed,
			"payment_method": "cod", "status": "escrow_reconciliation_required",
			"reconciliation_note": note, "escrow_failure_reason": "under_distance_mismatch"},
		// counted but skipped: other reason
		bson.M{"_id": "cod-stuck-other", "owner_id": "own-stuck", "service_id": "svc-stuck",
			"payment_method": "cod", "status": "escrow_reconciliation_required", "locked_escrow_amount": 0.0,
			"escrow_failure_reason": "rollback failed"},
		// not counted: wallet with escrow held, COD completed, COD with locked escrow
		bson.M{"_id": "wallet-stuck", "owner_id": "own-stuck", "service_id": "svc-stuck",
			"payment_method": "wallet", "status": "escrow_reconciliation_required", "locked_escrow_amount": 209.8,
			"escrow_failure_reason": "under_distance_mismatch"},
		bson.M{"_id": "cod-done", "owner_id": "own-stuck", "service_id": "svc-stuck",
			"payment_method": "cod", "status": "completed"},
		bson.M{"_id": "cod-locked", "owner_id": "own-stuck", "service_id": "svc-stuck",
			"payment_method": "cod", "status": "escrow_reconciliation_required", "locked_escrow_amount": 50.0,
			"escrow_failure_reason": "under_distance_mismatch"},
	}
	if _, err := db.Collection("jobs").InsertMany(ctx, jobs); err != nil {
		t.Fatalf("seed jobs: %v", err)
	}
	if _, err := db.Collection("employee_locations").InsertOne(ctx, bson.M{
		"_id": "emp-stuck", "tenant_id": "own-stuck", "employee_id": "emp-stuck", "active_job_id": "cod-stuck-1",
	}); err != nil {
		t.Fatalf("seed employee location: %v", err)
	}
	statusOf := func(id string) string {
		var j models.Job
		if err := db.Collection("jobs").FindOne(ctx, bson.M{"_id": id}).Decode(&j); err != nil {
			t.Fatalf("read job %s: %v", id, err)
		}
		return string(j.Status)
	}

	report, err := CountStuckCODReconciliationJobs(ctx, db)
	if err != nil {
		t.Fatalf("count: %v", err)
	}
	if report.Total != 3 || report.Repairable != 2 || report.ByReason["under_distance_mismatch"] != 2 || report.ByReason["rollback failed"] != 1 {
		t.Errorf("count report = %+v, want total 3, repairable 2", report)
	}

	dry, err := RepairStuckCODReconciliationJobs(ctx, db, false)
	if err != nil {
		t.Fatalf("dry run: %v", err)
	}
	if dry.Applied || len(dry.Repaired) != 2 || len(dry.Skipped) != 1 {
		t.Errorf("dry run = %+v, want 2 planned, 1 skipped, not applied", dry)
	}
	if statusOf("cod-stuck-1") != "escrow_reconciliation_required" {
		t.Fatalf("dry run must not write")
	}

	res, err := RepairStuckCODReconciliationJobs(ctx, db, true)
	if err != nil {
		t.Fatalf("repair: %v", err)
	}
	if !res.Applied || len(res.Repaired) != 2 || len(res.Skipped) != 1 || res.Skipped[0].JobID != "cod-stuck-other" {
		t.Errorf("repair = %+v, want 2 repaired, cod-stuck-other skipped", res)
	}
	wantCash := map[string]float64{"cod-stuck-1": 209.8, "cod-stuck-2": agreed}
	for id, cash := range wantCash {
		var j models.Job
		if err := db.Collection("jobs").FindOne(ctx, bson.M{"_id": id}).Decode(&j); err != nil {
			t.Fatalf("read %s: %v", id, err)
		}
		if j.Status != models.JobStatusCompleted {
			t.Errorf("%s status = %s, want completed", id, j.Status)
		}
		if j.ActualCashAmount == nil || *j.ActualCashAmount != cash {
			t.Errorf("%s actual_cash_amount = %v, want %.2f", id, j.ActualCashAmount, cash)
		}
		if j.DistanceReview == nil || j.DistanceReview.ActualKm != 5 || j.DistanceReview.BookedKm != 99.9 ||
			j.DistanceReview.Source != models.DistanceReviewSourceRepair || j.DistanceReview.FlaggedAt.IsZero() {
			t.Errorf("%s distance_review = %+v", id, j.DistanceReview)
		}
		if j.ReconciliationNote != note {
			t.Errorf("%s reconciliation_note changed: %q", id, j.ReconciliationNote)
		}
	}
	for _, id := range []string{"cod-stuck-other", "wallet-stuck", "cod-locked"} {
		if statusOf(id) != "escrow_reconciliation_required" {
			t.Errorf("%s must be left in escrow_reconciliation_required", id)
		}
	}
	var loc bson.M
	if err := db.Collection("employee_locations").FindOne(ctx, bson.M{"_id": "emp-stuck"}).Decode(&loc); err != nil || loc["active_job_id"] != "" {
		t.Errorf("courier lock not released: %v (%v)", loc, err)
	}

	again, err := RepairStuckCODReconciliationJobs(ctx, db, true)
	if err != nil {
		t.Fatalf("second repair: %v", err)
	}
	if len(again.Repaired) != 0 {
		t.Errorf("repair is not idempotent: second run repaired %+v", again.Repaired)
	}
	after, err := CountStuckCODReconciliationJobs(ctx, db)
	if err != nil || after.Total != 1 || after.Repairable != 0 {
		t.Errorf("count after repair = %+v (%v), want total 1, repairable 0", after, err)
	}
}

func TestParseDistanceMismatchNote(t *testing.T) {
	a, b := parseDistanceMismatchNote("tracked_distance_mismatch: actual 2.10 km vs booked 10.50 km")
	if a != 2.1 || b != 10.5 {
		t.Errorf("got %v %v, want 2.1 10.5", a, b)
	}
	if a, b := parseDistanceMismatchNote("something else"); a != 0 || b != 0 {
		t.Errorf("unparseable note: got %v %v, want 0 0", a, b)
	}
}
