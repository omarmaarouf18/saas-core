package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"github.com/project/shared/infra/jwtutil"
	"github.com/project/user-service/internal/models"
)

// Pagination regression tests for the two unbounded read endpoints.
//
// Pre-fix: GetLedger / GetRatings materialized EVERY matching document into
// memory and serialized it — large-response DoS surface and slow queries at
// scale. Post-fix: server-side defaults (ledger 100/page, ratings 50/page),
// client-tunable via ?limit/&offset, hard caps (500/200).

func seedLedgerEntries(t *testing.T, s interface {
	Deposit(context.Context, string, float64) error
}, ctx context.Context, tenant string, n int) {
	t.Helper()
	var wg sync.WaitGroup
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if err := s.Deposit(ctx, tenant, 1.0); err != nil {
				t.Errorf("seed deposit: %v", err)
			}
		}()
	}
	wg.Wait()
}

func ledgerCount(t *testing.T, h *UserService, ownerToken string, query string) int {
	t.Helper()
	sep := "?"
	if query != "" {
		sep = "&"
	}
	req := httptest.NewRequest("GET", "/users/ledger"+query+sep+"tenant_token="+ownerToken, nil)
	w := httptest.NewRecorder()
	h.GetLedger(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("GET /users/ledger failed: %d %s", w.Code, w.Body.String())
	}
	var res struct {
		Count   int               `json:"count"`
		Entries []json.RawMessage `json:"entries"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &res); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if res.Count != len(res.Entries) {
		t.Fatalf("count/entries mismatch: %d vs %d", res.Count, len(res.Entries))
	}
	return res.Count
}

// TestGetLedger_DefaultCapAndPagination reproduces the unbounded ledger read.
func TestGetLedger_DefaultCapAndPagination(t *testing.T) {
	h, s, ctx := setupCODFeeHarness(t)
	if h == nil {
		return
	}

	ownerID := "owner-ledger-page"
	seedLedgerEntries(t, s, ctx, ownerID, 150)

	ownerToken, _ := jwtutil.GenerateToken(ownerID, "owner", ownerID, "o@lp.test")

	if got := ledgerCount(t, h, ownerToken, ""); got != 100 {
		t.Errorf("UNBOUNDED LEDGER READ: default page returned %d entries, want 100 (server-side default cap)", got)
	}
	if got := ledgerCount(t, h, ownerToken, "?limit=10"); got != 10 {
		t.Errorf("limit param ignored: got %d, want 10", got)
	}
	if got := ledgerCount(t, h, ownerToken, "?limit=10&offset=140"); got != 10 {
		t.Errorf("offset param ignored: got %d, want 10", got)
	}
	if got := ledgerCount(t, h, ownerToken, "?limit=100000"); got > 500 {
		t.Errorf("max cap not enforced: %d entries returned, hard cap is 500", got)
	}
}

// TestGetRatings_DefaultCapAndPagination reproduces the unbounded ratings read.
func TestGetRatings_DefaultCapAndPagination(t *testing.T) {
	h, s, ctx := setupCODFeeHarness(t)
	if h == nil {
		return
	}

	target := "emp-ratings-page"
	for i := 0; i < 60; i++ {
		if err := s.CreateRating(ctx, &models.Rating{
			ID: fmt.Sprintf("rate-seed-%d", i), JobID: fmt.Sprintf("job-%d", i),
			RatedBy: "cust", RatedUser: target, Stars: 5,
			CreatedAt: time.Now().UTC(),
		}); err != nil {
			t.Fatalf("seed rating: %v", err)
		}
	}

	reqerToken, _ := jwtutil.GenerateToken("cust", "customer", "cust", "c@rp.test")

	countRatings := func(query string) int {
		req := httptest.NewRequest("GET", "/users/ratings"+query, nil)
		req.Header.Set("Authorization", "Bearer "+reqerToken)
		w := httptest.NewRecorder()
		h.GetRatings(w, req)
		if w.Code != http.StatusOK {
			t.Fatalf("GET /users/ratings failed: %d %s", w.Code, w.Body.String())
		}
		var res struct {
			Count   int               `json:"count"`
			Ratings []json.RawMessage `json:"ratings"`
		}
		if err := json.Unmarshal(w.Body.Bytes(), &res); err != nil {
			t.Fatalf("decode: %v", err)
		}
		return res.Count
	}

	if got := countRatings("?user_id=" + target); got != 50 {
		t.Errorf("UNBOUNDED RATINGS READ: default page returned %d ratings, want 50 (server-side default cap)", got)
	}
	if got := countRatings("?user_id=" + target + "&limit=5"); got != 5 {
		t.Errorf("limit param ignored: got %d, want 5", got)
	}
	if got := countRatings("?user_id=" + target + "&limit=5&offset=55"); got != 5 {
		t.Errorf("offset param ignored: got %d, want 5", got)
	}
}
