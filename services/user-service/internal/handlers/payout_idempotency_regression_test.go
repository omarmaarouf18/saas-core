package handlers

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/project/shared/infra/jwtutil"
	"github.com/project/user-service/internal/models"
)

// Regression tests for payout-request idempotency (independent QA audit Q1).
//
// Defect: POST /users/wallet/payout/request had no idempotency handling — a
// client network retry of the same logical request created TWO payout
// requests and deducted funds twice (literal pre-fix output:
// "first attempt status=201, retry status=201; payout requests created=2,
// withdrawable=100.00 (started 500.00)").
//
// Contract under test (mirrors TrackJob's established pattern):
//  1. Same Idempotency-Key on retry -> single payout request, single
//     deduction, second call replays the stored request (200).
//  2. A different key creates an independent request (keys actually gate).
//  3. Requests without any key keep the legacy per-request behavior.
func TestRequestPayout_IdempotencyKeyReplaysAndDeduplicates(t *testing.T) {
	h, s, ctx := setupCODFeeHarness(t)
	if h == nil {
		return
	}
	ownerID := "qa-payout-idem"
	if _, err := s.GetOrCreateWallet(ctx, ownerID); err != nil {
		t.Fatalf("wallet: %v", err)
	}
	if err := s.Deposit(ctx, ownerID, 500); err != nil {
		t.Fatalf("deposit: %v", err)
	}
	ownerToken, _ := jwtutil.GenerateToken(ownerID, "owner", ownerID, "o@idem.test")

	doPost := func(key string) (*httptest.ResponseRecorder, models.PayoutRequest) {
		body, _ := json.Marshal(map[string]any{
			"amount":          200,
			"payout_method":   "instapay",
			"idempotency_key": key,
		})
		req := httptest.NewRequest("POST", "/users/wallet/payout/request", bytes.NewReader(body))
		req.Header.Set("Authorization", "Bearer "+ownerToken)
		if key != "" {
			req.Header.Set("Idempotency-Key", key)
		}
		w := httptest.NewRecorder()
		h.RequestPayout(w, req)
		var pr models.PayoutRequest
		_ = json.Unmarshal(w.Body.Bytes(), &pr)
		return w, pr
	}

	w1, pr1 := doPost("retry-key-1")
	if w1.Code != http.StatusCreated {
		t.Fatalf("first attempt: got %d %s, want 201", w1.Code, w1.Body.String())
	}

	w2, pr2 := doPost("retry-key-1") // simulated network retry of the SAME request
	if w2.Code != http.StatusOK {
		t.Errorf("RETRY NOT REPLAYED: same Idempotency-Key returned %d, want 200 with the stored request", w2.Code)
	}
	if pr2.ID != pr1.ID {
		t.Errorf("RETRY DOUBLE-CREATED: retry returned payout %q, want original %q (funds deducted twice)", pr2.ID, pr1.ID)
	}
	if w2.Header().Get("X-Idempotent-Replay") != "true" {
		t.Errorf("replay not signalled: X-Idempotent-Replay header = %q, want true", w2.Header().Get("X-Idempotent-Replay"))
	}
	if w1.Header().Get("X-Idempotent-Replay") != "" {
		t.Errorf("original creation must not carry the replay header")
	}

	walletMid := s.GetWallet(ctx, ownerID)
	if walletMid.WithdrawableBalance != 300 {
		t.Errorf("DOUBLE DEDUCTION: withdrawable = %.2f after keyed retry, want 300.00", walletMid.WithdrawableBalance)
	}

	// A different logical request under a different key must create its own payout.
	w3, _ := doPost("other-intent")
	if w3.Code != http.StatusCreated {
		t.Errorf("distinct key should create independently, got %d", w3.Code)
	}

	// No key at all keeps legacy behavior: each call is a new request.
	bodyNoKey, _ := json.Marshal(map[string]any{"amount": 10, "payout_method": "instapay"})
	for i := 0; i < 2; i++ {
		req := httptest.NewRequest("POST", "/users/wallet/payout/request", bytes.NewReader(bodyNoKey))
		req.Header.Set("Authorization", "Bearer "+ownerToken)
		wr := httptest.NewRecorder()
		h.RequestPayout(wr, req)
		if wr.Code != http.StatusCreated {
			t.Fatalf("no-key attempt %d: got %d, want 201 (legacy behavior)", i+1, wr.Code)
		}
	}

	reqs, err := s.GetPayoutRequests(ctx, ownerID)
	if err != nil {
		t.Fatalf("list payouts: %v", err)
	}
	totalDeducted := 500 - s.GetWallet(ctx, ownerID).WithdrawableBalance
	t.Logf("payouts=%d totalDeducted=%.2f (200+200+10+10=420 expected)", len(reqs), totalDeducted)
	if len(reqs) != 4 {
		t.Errorf("expected exactly 4 payout requests (1 keyed + 1 other-key + 2 unkeyed), got %d", len(reqs))
	}
	if totalDeducted != 420 {
		t.Errorf("total deducted = %.2f, want 420.00", totalDeducted)
	}
}
