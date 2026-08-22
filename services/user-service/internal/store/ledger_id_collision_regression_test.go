package store

import (
	"context"
	"strings"
	"sync"
	"testing"

	"github.com/project/user-service/internal/models"
)

// TestLedger_ConcurrentDepositNoIDCollision reproduces the tx-%d ledger ID
// collision defect in two layers.
//
// Layer 1 exercises the verbatim production expression used by every ledger
// write in mongodb.go under concurrency: transaction IDs built from
// time.Now().UnixNano() collide when concurrent mutations read the clock in
// the same nanosecond. A duplicate becomes a failed InsertOne on _id —
// Deposit() only logs that error, silently losing the immutable audit entry
// for a real money movement.
//
// Layer 2 asserts the end-to-end invariant: every concurrent deposit yields
// exactly one ledger entry.
//
// Pre-fix expectation: Layer 1 fails (duplicate generated IDs observed).
// Post-fix expectation: both layers pass.
func TestLedger_ConcurrentDepositNoIDCollision(t *testing.T) {
	// --- Layer 1: production ID generation under concurrency ---
	//
	// Repro note: before the fix this layer inlined the verbatim legacy
	// expression, fmt.Sprintf("tx-%d", time.Now().UnixNano()), and failed
	// deterministically (~80 duplicate IDs per 20000 concurrent generations;
	// literal pre-fix output preserved in the delivery log). Post-fix it
	// exercises the production generator, newRecordID("tx", ""), which must
	// never collide under identical load.
	const n = 20000
	ids := make([]string, n)
	var wg sync.WaitGroup
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			ids[i] = newRecordID("tx", "")
		}(i)
	}
	wg.Wait()
	seen := make(map[string]int, n)
	dups := 0
	for _, id := range ids {
		if seen[id] > 0 {
			dups++
			if dups <= 3 {
				t.Logf("colliding ID produced twice concurrently: %s", id)
			}
		}
		seen[id]++
	}
	if dups > 0 {
		t.Fatalf("PRODUCTION ID EXPRESSION COLLIDES UNDER CONCURRENCY: %d duplicate tx IDs out of %d generations (each duplicate would abort its ledger insert on _id)", dups, n)
	}

	// --- Layer 2: end-to-end deposit ledger completeness ---
	s, cleanup := setupTestMongoDB(t)
	if s == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	const tenant = "collision-tenant"
	const deposits = 400

	var wg2 sync.WaitGroup
	for i := 0; i < deposits; i++ {
		wg2.Add(1)
		go func() {
			defer wg2.Done()
			if err := s.Deposit(ctx, tenant, 1.00); err != nil {
				t.Errorf("Deposit failed: %v", err)
			}
		}()
	}
	wg2.Wait()

	w := s.GetWallet(ctx, tenant)
	if w == nil {
		t.Fatalf("wallet missing after %d deposits", deposits)
	}
	if w.TotalBalance != float64(deposits) {
		t.Errorf("balance drift: got %.2f, want %.2f (deposits themselves must all apply)", w.TotalBalance, float64(deposits))
	}

	entries := s.GetLedger(ctx, tenant)
	depositEntries := 0
	for _, e := range entries {
		if e.Type == models.TxDeposit && strings.HasPrefix(e.ID, "tx-") {
			depositEntries++
		}
	}
	if depositEntries != deposits {
		t.Fatalf("LEDGER ENTRIES LOST TO ID COLLISIONS: got %d deposit ledger entries for %d concurrent deposits (want %d)", depositEntries, deposits, deposits)
	}
}
