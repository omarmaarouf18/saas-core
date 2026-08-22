package store

import (
	"context"
	"strings"
	"testing"

	"github.com/project/user-service/internal/models"
)

// Payout requests deduct funds at creation time, but there was NO rejection
// path: a rejected payout silently consumed the owner's money forever. This
// suite pins the RejectPayoutRequest capability (CAS-guarded status flip +
// balance restoration + ledger entry). The admin-facing endpoint remains
// deferred to the Support Agent Console per ADR-0018; this is the store
// capability that console will call.
func TestRejectPayoutRequest_RestoresBalancesAndLedgers(t *testing.T) {
	s, cleanup := setupTestMongoDB(t)
	defer cleanup()

	ctx := context.Background()
	tenantID := "payout-reject-tenant"

	if err := s.Deposit(ctx, tenantID, 100.0); err != nil {
		t.Fatalf("deposit failed: %v", err)
	}

	req, err := s.CreatePayoutRequest(ctx, tenantID, models.CreatePayoutRequestInput{
		Amount: 40.0, PayoutMethod: "bank_transfer", AccountDetails: "acct-1",
	})
	if err != nil {
		t.Fatalf("CreatePayoutRequest failed: %v", err)
	}

	wal := s.GetWallet(ctx, tenantID)
	if wal.WithdrawableBalance != 60.0 || wal.TotalBalance != 60.0 {
		t.Fatalf("setup: expected balances 60/60 after payout request, got withdrawable=%.2f total=%.2f", wal.WithdrawableBalance, wal.TotalBalance)
	}

	// The capability under test: reject with reason and restore funds.
	if err := s.RejectPayoutRequest(ctx, req.ID, "bank account verification failed"); err != nil {
		t.Fatalf("RejectPayoutRequest failed: %v", err)
	}

	wal = s.GetWallet(ctx, tenantID)
	if wal.WithdrawableBalance != 100.0 || wal.TotalBalance != 100.0 {
		t.Errorf("expected funds restored to 100/100 after rejection, got withdrawable=%.2f total=%.2f", wal.WithdrawableBalance, wal.TotalBalance)
	}

	// Status must be rejected with the reason recorded.
	prs, err := s.GetPayoutRequests(ctx, tenantID)
	if err != nil {
		t.Fatalf("GetPayoutRequests failed: %v", err)
	}
	found := false
	for _, pr := range prs {
		if pr.ID == req.ID {
			found = true
			if pr.Status != models.PayoutStatusRejected {
				t.Errorf("expected payout status %q, got %q", models.PayoutStatusRejected, pr.Status)
			}
			if !strings.Contains(pr.RejectionReason, "verification failed") {
				t.Errorf("expected rejection reason recorded, got %q", pr.RejectionReason)
			}
		}
	}
	if !found {
		t.Fatalf("payout request %s not found in listing", req.ID)
	}

	// Ledger must contain a refund entry crediting the owner back.
	ledger := s.GetLedger(ctx, tenantID, 0, 0)
	refundFound := false
	for _, e := range ledger {
		if e.Type == models.TxPayoutRefund && e.Amount == 40.0 {
			refundFound = true
		}
	}
	if !refundFound {
		t.Errorf("expected a payout_refund ledger entry of 40.0, got %+v", ledger)
	}

	// Double-reject must fail via the CAS guard on status=requested.
	if err := s.RejectPayoutRequest(ctx, req.ID, "second attempt"); err == nil {
		t.Error("expected error rejecting an already-rejected payout request")
	}
}
