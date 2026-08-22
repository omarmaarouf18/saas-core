package store

import (
	"context"
	"testing"

	"github.com/project/user-service/internal/models"
)

// Regression test for the RejectPayoutRequest fund-stranding defect
// (independent QA audit finding Q2).
//
// Defect: the status CAS flip (requested -> rejected) consumed the request
// BEFORE the wallet restore; if the restore failed (wallet document missing,
// transient error), the payout was stuck "rejected" with the owner's funds
// permanently stranded — a retry was refused by the already-consumed CAS and
// no compensating path existed.
//
// Contract under test:
//  1. A failed rejection must leave the payout back in "requested" state so
//     it can be retried (compensating revert of the status flip).
//  2. A subsequent successful rejection restores balances, records the
//     payout_refund ledger entry, and lands in "rejected".
//  3. Double-reject remains CAS-refused.
//
// Pre-fix literal failure: `payout status="rejected", wallet withdrawable=0.00
// (expected 300.00 if refunded), payout_refund ledger entries=0` with retry
// refused via "not found or not in requested state".
func TestRejectPayoutRequest_FailedRejectStaysRetryable(t *testing.T) {
	s, cleanup := setupTestMongoDB(t)
	if s == nil {
		return
	}
	defer cleanup()
	ctx := context.Background()

	const tenant = "qa-stuck-reject"
	if err := s.Deposit(ctx, tenant, 300); err != nil {
		t.Fatalf("deposit: %v", err)
	}
	pr, err := s.CreatePayoutRequest(ctx, tenant, models.CreatePayoutRequestInput{
		Amount: 100, PayoutMethod: "instapay",
	})
	if err != nil {
		t.Fatalf("create payout: %v", err)
	}

	// Force the wallet-restore step to fail: remove the wallet document so
	// the unguarded $inc matches nothing.
	if _, err := s.wallets.DeleteOne(ctx, map[string]any{"tenant_id": tenant}); err != nil {
		t.Fatalf("delete wallet: %v", err)
	}

	firstErr := s.RejectPayoutRequest(ctx, pr.ID, "qa audit repro")
	if firstErr == nil {
		t.Fatal("expected RejectPayoutRequest to fail while the wallet is missing")
	}
	t.Logf("first reject error: %v", firstErr)

	readStatus := func() string {
		var doc struct {
			Status string `bson:"status"`
		}
		if err := s.payoutRequests.FindOne(ctx, map[string]any{"_id": pr.ID}).Decode(&doc); err != nil {
			t.Fatalf("read payout: %v", err)
		}
		return doc.Status
	}
	payoutStatus := readStatus()

	if payoutStatus != string(models.PayoutStatusRequested) {
		t.Fatalf("STRANDED REJECTION: payout consumed by failed reject (status=%q); must revert to %q so the rejection can be retried",
			payoutStatus, models.PayoutStatusRequested)
	}

	// Retry path: recreate the wallet exactly as any operator-driven recovery
	// would, then reject again — this must now succeed end to end.
	if _, err := s.GetOrCreateWallet(ctx, tenant); err != nil {
		t.Fatalf("recreate wallet: %v", err)
	}
	if err := s.RejectPayoutRequest(ctx, pr.ID, "qa audit retry"); err != nil {
		t.Fatalf("retry reject after wallet recovery: %v", err)
	}

	w := s.GetWallet(ctx, tenant)
	if w == nil || w.WithdrawableBalance != 100 {
		t.Fatalf("restored withdrawable = %.2f, want 100.00 (0 recreated balance + 100 refund)", w.WithdrawableBalance)
	}
	refunds := 0
	for _, e := range s.GetLedger(ctx, tenant, 500, 0) {
		if e.Type == models.TxPayoutRefund && e.Amount == 100 {
			refunds++
		}
	}
	if refunds != 1 {
		t.Fatalf("payout_refund ledger entries = %d, want 1", refunds)
	}
	if got := readStatus(); got != string(models.PayoutStatusRejected) {
		t.Fatalf("final status = %q, want rejected", got)
	}

	// Triple-reject protection unchanged.
	if err := s.RejectPayoutRequest(ctx, pr.ID, "double reject"); err == nil {
		t.Fatal("expected double-reject CAS refusal")
	}
}
