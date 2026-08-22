package store

import (
	"context"
	"testing"

	"github.com/project/user-service/internal/models"
)

// These tests reproduce the missing compensating-revert defect in
// MongoDB.RefundEscrow's non-transactional fallback path (used on standalone
// mongod deployments without replica-set transactions, and on session-start
// failure). The fallback executes three sequential steps:
//
//	(a) job CAS update  — deduct locked_escrow_amount, set status=cancelled
//	(b) wallet CAS      — escrow_balance -= amount, withdrawable += amount
//	(c) ledger insert   — audit entry
//
// When a later step fails after earlier ones succeeded, nothing restores the
// job document or the moved funds. This test deterministically forces the
// FINAL step (c) to fail by rebinding the ledger collection handle
// (unexported struct field, same package) to an invalid namespace, so the
// ledger insert returns "(InvalidNamespace)" while steps (a)+(b) complete
// normally — exercising BOTH compensation dimensions at once: moved funds
// (escrow -> withdrawable) and the mutated job document. The fix applies the
// same compensating-revert pattern symmetrically to a step-(b) failure
// (revert job only) and a step-(c) failure (revert funds + job).
//
// NOTE: a step-(b)-failure variant was attempted by rebinding s.wallets,
// but that handle is ALSO used by RefundEscrow's entry read
// (GetOrCreateWallet), so the injection aborted the sequence before any
// mutation — a vacuous test. It was removed rather than kept green for the
// wrong reason.
//
// Pre-fix expectation: this test fails — the error is returned but mutated
// state (job status/lock, wallet balances) is never compensated.
// Post-fix expectation: compensating reverts restore the pre-call state.

func seedRefundFixture(t *testing.T, s *MongoDB) {
	ctx := context.Background()
	if err := s.Deposit(ctx, "refund-owner", 100); err != nil {
		t.Fatalf("deposit: %v", err)
	}
	jobID := "refund-job-1"
	if err := s.CreateJob(ctx, &models.Job{ID: jobID, OwnerID: "refund-owner", Status: models.JobStatusPending}); err != nil {
		t.Fatalf("create job: %v", err)
	}
	if err := s.LockEscrow(ctx, "refund-owner", jobID, 60); err != nil {
		t.Fatalf("lock escrow: %v", err)
	}
	// Mirror the TrackJob handler sequence: the job-side lock record is
	// persisted separately from the wallet move.
	if err := s.UpdateJobLockedEscrow(ctx, jobID, 60); err != nil {
		t.Fatalf("persist job locked escrow: %v", err)
	}
	if err := s.UpdateJobStatus(ctx, jobID, models.JobStatusActive); err != nil {
		t.Fatalf("activate job: %v", err)
	}
}

// TestRefundEscrow_FallbackLedgerFailureRevertsFunds forces step (c) to fail
// after steps (a)+(b) succeeded.
func TestRefundEscrow_FallbackLedgerFailureRevertsFunds(t *testing.T) {
	s, cleanupDB := setupTestMongoDB(t)
	if s == nil {
		return
	}
	defer cleanupDB()
	seedRefundFixture(t, s)

	ctx := context.Background()
	realLedger := s.ledger
	s.ledger = s.db.Collection("ledger\x00injected-failure")
	defer func() { s.ledger = realLedger }()

	err := s.RefundEscrow(ctx, "refund-owner", "refund-job-1", 60)
	if err == nil {
		t.Fatal("expected RefundEscrow to return the injected ledger-step failure")
	}

	w := s.GetWallet(ctx, "refund-owner")
	if w == nil {
		t.Fatal("wallet missing")
	}
	if w.EscrowBalance != 60 || w.WithdrawableBalance != 40 {
		t.Errorf("FUNDS NOT COMPENSATED AFTER LEDGER FAILURE: escrow=%.2f withdrawable=%.2f, want escrow=60.00 withdrawable=40.00 (money moved with no audit trail and no revert)", w.EscrowBalance, w.WithdrawableBalance)
	}
	job := s.GetJob(ctx, "refund-job-1")
	if job == nil {
		t.Fatal("job vanished")
	}
	if job.Status != models.JobStatusActive || job.LockedEscrowAmount != 60 {
		t.Errorf("JOB MUTATION NOT COMPENSATED: status=%q locked=%.2f, want active/60.00", job.Status, job.LockedEscrowAmount)
	}
}
