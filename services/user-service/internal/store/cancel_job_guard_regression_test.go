package store

import (
	"context"
	"testing"

	"github.com/project/user-service/internal/models"
)

// Regression tests for the store.CancelJob trap arms (independent QA audit
// finding Q5).
//
// Defect: CancelJob's $in filter included escrow_reconciliation_required and
// cancelled while the write touched only status/reason — never locked escrow.
// A direct (internal/future-caller) cancel of a reconciliation-flagged funded
// job therefore stranded the lock permanently: resolution is gated on recon
// state, and every other guarded path excludes cancelled.
//
// Contract under test:
//  1. Direct cancellation of a recon-flagged funded job must be REJECTED,
//     leaving the job recoverable through its dedicated resolution path.
//  2. Cancellation-reason stamping is a separate, narrowly-guarded operation
//     that only fires on jobs already in status=cancelled.
//
// Pre-fix literal failure (repro): "TRAP ARM CONFIRMED: direct store cancel of
// a reconciliation-flagged FUNDED job succeeded — job status=cancelled,
// locked_escrow_amount=60.00 still recorded, wallet escrow_balance=60.00 still
// held, no refund path remains".
func TestCancelJob_ReconFundedJobNotSilentlyCancellable(t *testing.T) {
	s, cleanup := setupTestMongoDB(t)
	if s == nil {
		return
	}
	defer cleanup()
	ctx := context.Background()

	const owner = "q5-owner"
	if err := s.Deposit(ctx, owner, 100); err != nil {
		t.Fatalf("deposit: %v", err)
	}
	jobID := "q5-recon-job"
	if err := s.CreateJob(ctx, &models.Job{ID: jobID, OwnerID: owner, Status: models.JobStatusPending}); err != nil {
		t.Fatalf("create job: %v", err)
	}
	if err := s.LockEscrow(ctx, owner, jobID, 60); err != nil {
		t.Fatalf("lock escrow: %v", err)
	}
	if err := s.UpdateJobLockedEscrow(ctx, jobID, 60); err != nil {
		t.Fatalf("persist lock record: %v", err)
	}
	if err := s.UpdateJobStatus(ctx, jobID, models.JobStatusActive); err != nil {
		t.Fatalf("activate: %v", err)
	}
	if err := s.UpdateJobReconciliation(ctx, jobID, models.JobStatusEscrowReconciliationRequired, "qa note", "under_distance_mismatch", 60); err != nil {
		t.Fatalf("flag recon: %v", err)
	}

	// The trap arm: a direct caller cancels without settling escrow.
	err := s.CancelJob(ctx, jobID, "direct store cancel")
	if err == nil {
		job := s.GetJob(ctx, jobID)
		w := s.GetWallet(ctx, owner)
		t.Fatalf("TRAP ARM CONFIRMED: direct store cancel of a reconciliation-flagged FUNDED job succeeded — job status=%q, locked_escrow_amount=%.2f still recorded, wallet escrow_balance=%.2f still held, and no refund path remains (resolution is gated on recon state); want rejection",
			job.Status, job.LockedEscrowAmount, w.EscrowBalance)
	}

	job := s.GetJob(ctx, jobID)
	if job.Status != models.JobStatusEscrowReconciliationRequired {
		t.Errorf("job state changed by rejected cancel: %q, want escrow_reconciliation_required", job.Status)
	}
	if job.LockedEscrowAmount != 60 {
		t.Errorf("lock disturbed by rejected cancel: %.2f, want 60.00", job.LockedEscrowAmount)
	}

	// Recovery stays available: the guarded money transition settles escrow.
	if err := s.RefundEscrow(ctx, owner, jobID, 60); err != nil {
		t.Fatalf("recovery refund after rejected direct cancel: %v", err)
	}
	if w := s.GetWallet(ctx, owner); w.WithdrawableBalance != 100 || w.EscrowBalance != 0 {
		t.Errorf("post-recovery balances: withdrawable=%.2f escrow=%.2f, want 100.00/0.00", w.WithdrawableBalance, w.EscrowBalance)
	}
}

func TestSetCancellationReason_OnlyStampsCancelledJobs(t *testing.T) {
	s, cleanup := setupTestMongoDB(t)
	if s == nil {
		return
	}
	defer cleanup()
	ctx := context.Background()

	jobID := "q5-reason-job"
	if err := s.CreateJob(ctx, &models.Job{ID: jobID, OwnerID: "q5-owner2", Status: models.JobStatusActive}); err != nil {
		t.Fatalf("create job: %v", err)
	}

	if err := s.SetCancellationReason(ctx, jobID, "too early"); err == nil {
		t.Fatal("SetCancellationReason must refuse non-cancelled jobs")
	}

	if err := s.CancelJob(ctx, jobID, "initial reason"); err != nil {
		t.Fatalf("cancel active job: %v", err)
	}
	if err := s.SetCancellationReason(ctx, jobID, "refined reason"); err != nil {
		t.Fatalf("stamp reason on cancelled job: %v", err)
	}
	job := s.GetJob(ctx, jobID)
	if job.CancellationReason != "refined reason" || job.Status != models.JobStatusCancelled {
		t.Errorf("reason stamp failed: status=%q reason=%q", job.Status, job.CancellationReason)
	}
}
