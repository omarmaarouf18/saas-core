package handlers

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/project/shared/infra/handlerutil"
	"github.com/project/shared/infra/ratelimit"
	"github.com/redis/go-redis/v9"
)

// TestIsolatedRateLimiters_TrackBurstDoesNotBlockOthers proves that exhausting
// the user:track rate limiter (budget: 20 req/min) does NOT starve or lock out
// other user endpoints (cancel_job, propose_price, respond_price, rate_job, deposit).
func TestIsolatedRateLimiters_TrackBurstDoesNotBlockOthers(t *testing.T) {
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()

	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	newLimiter := func(limit int, name string) *handlerutil.RateLimiter {
		return handlerutil.NewRateLimiter(ratelimit.NewRateLimiter(rdb, limit, 1*time.Minute, name))
	}

	svc := &UserService{
		trackLimiter:        newLimiter(20, "user:track"),
		proposePriceLimiter: newLimiter(20, "user:propose_price"),
		respondPriceLimiter: newLimiter(20, "user:respond_price"),
		cancelJobLimiter:    newLimiter(10, "user:cancel_job"),
		rateJobLimiter:      newLimiter(10, "user:rate_job"),
		depositLimiter:      newLimiter(10, "user:deposit"),
		ticketLimiter:       newLimiter(10, "user:ticket"),
	}

	targetIP := "192.168.50.1:12345"

	// 1. Exhaust trackLimiter budget (20 calls)
	for i := 0; i < 20; i++ {
		req := httptest.NewRequest(http.MethodPost, "/users/jobs/track", bytes.NewReader([]byte(`{}`)))
		req.RemoteAddr = targetIP
		rec := httptest.NewRecorder()
		svc.TrackJob(rec, req)
		if rec.Code == http.StatusTooManyRequests {
			t.Fatalf("TrackJob call %d unexpectedly rate limited within 20/min budget", i+1)
		}
	}

	// 2. Call 21 on TrackJob must be rejected with 429
	reqTrack21 := httptest.NewRequest(http.MethodPost, "/users/jobs/track", bytes.NewReader([]byte(`{}`)))
	reqTrack21.RemoteAddr = targetIP
	recTrack21 := httptest.NewRecorder()
	svc.TrackJob(recTrack21, reqTrack21)
	if recTrack21.Code != http.StatusTooManyRequests {
		t.Fatalf("Expected 21st TrackJob call to be rate limited (429), got %d", recTrack21.Code)
	}

	// 3. Immediately verify other actions from the SAME IP are NOT blocked
	// A. CancelJob
	reqCancel := httptest.NewRequest(http.MethodPost, "/users/jobs/cancel", strings.NewReader(`{}`))
	reqCancel.RemoteAddr = targetIP
	recCancel := httptest.NewRecorder()
	svc.CancelJob(recCancel, reqCancel)
	if recCancel.Code == http.StatusTooManyRequests {
		t.Errorf("CancelJob falsely rate-limited after TrackJob burst! Shared-bucket bug persists.")
	}

	// B. ProposePrice
	reqPropose := httptest.NewRequest(http.MethodPost, "/users/jobs/propose-price", strings.NewReader(`{}`))
	reqPropose.RemoteAddr = targetIP
	recPropose := httptest.NewRecorder()
	svc.ProposePrice(recPropose, reqPropose)
	if recPropose.Code == http.StatusTooManyRequests {
		t.Errorf("ProposePrice falsely rate-limited after TrackJob burst! Shared-bucket bug persists.")
	}

	// C. RespondPrice
	reqRespond := httptest.NewRequest(http.MethodPost, "/users/jobs/respond-price", strings.NewReader(`{}`))
	reqRespond.RemoteAddr = targetIP
	recRespond := httptest.NewRecorder()
	svc.RespondPrice(recRespond, reqRespond)
	if recRespond.Code == http.StatusTooManyRequests {
		t.Errorf("RespondPrice falsely rate-limited after TrackJob burst! Shared-bucket bug persists.")
	}

	// D. RateJob
	reqRate := httptest.NewRequest(http.MethodPost, "/users/jobs/rate", strings.NewReader(`{}`))
	reqRate.RemoteAddr = targetIP
	recRate := httptest.NewRecorder()
	svc.RateJob(recRate, reqRate)
	if recRate.Code == http.StatusTooManyRequests {
		t.Errorf("RateJob falsely rate-limited after TrackJob burst! Shared-bucket bug persists.")
	}

	// E. WalletDeposit
	reqDeposit := httptest.NewRequest(http.MethodPost, "/users/wallet/deposit", strings.NewReader(`{}`))
	reqDeposit.RemoteAddr = targetIP
	recDeposit := httptest.NewRecorder()
	svc.WalletDeposit(recDeposit, reqDeposit)
	if recDeposit.Code == http.StatusTooManyRequests {
		t.Errorf("WalletDeposit falsely rate-limited after TrackJob burst! Shared-bucket bug persists.")
	}
}

// TestIsolatedRateLimiters_CancelJobBurstDoesNotBlockTrackOrPropose proves that
// exhausting the user:cancel_job rate limiter (budget: 10 req/min) does NOT
// block user:track or user:propose_price from the same IP.
func TestIsolatedRateLimiters_CancelJobBurstDoesNotBlockTrackOrPropose(t *testing.T) {
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()

	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	newLimiter := func(limit int, name string) *handlerutil.RateLimiter {
		return handlerutil.NewRateLimiter(ratelimit.NewRateLimiter(rdb, limit, 1*time.Minute, name))
	}

	svc := &UserService{
		trackLimiter:        newLimiter(20, "user:track"),
		proposePriceLimiter: newLimiter(20, "user:propose_price"),
		cancelJobLimiter:    newLimiter(10, "user:cancel_job"),
	}

	targetIP := "192.168.50.2:12345"

	// 1. Exhaust cancelJobLimiter budget (10 calls)
	for i := 0; i < 10; i++ {
		req := httptest.NewRequest(http.MethodPost, "/users/jobs/cancel", strings.NewReader(`{}`))
		req.RemoteAddr = targetIP
		rec := httptest.NewRecorder()
		svc.CancelJob(rec, req)
		if rec.Code == http.StatusTooManyRequests {
			t.Fatalf("CancelJob call %d unexpectedly rate limited within 10/min budget", i+1)
		}
	}

	// 2. Call 11 on CancelJob must be rejected with 429
	reqCancel11 := httptest.NewRequest(http.MethodPost, "/users/jobs/cancel", strings.NewReader(`{}`))
	reqCancel11.RemoteAddr = targetIP
	recCancel11 := httptest.NewRecorder()
	svc.CancelJob(recCancel11, reqCancel11)
	if recCancel11.Code != http.StatusTooManyRequests {
		t.Fatalf("Expected 11th CancelJob call to be rate limited (429), got %d", recCancel11.Code)
	}

	// 3. TrackJob and ProposePrice from same IP must NOT be rate limited
	reqTrack := httptest.NewRequest(http.MethodPost, "/users/jobs/track", bytes.NewReader([]byte(`{}`)))
	reqTrack.RemoteAddr = targetIP
	recTrack := httptest.NewRecorder()
	svc.TrackJob(recTrack, reqTrack)
	if recTrack.Code == http.StatusTooManyRequests {
		t.Errorf("TrackJob falsely rate-limited after CancelJob burst!")
	}

	reqPropose := httptest.NewRequest(http.MethodPost, "/users/jobs/propose-price", strings.NewReader(`{}`))
	reqPropose.RemoteAddr = targetIP
	recPropose := httptest.NewRecorder()
	svc.ProposePrice(recPropose, reqPropose)
	if recPropose.Code == http.StatusTooManyRequests {
		t.Errorf("ProposePrice falsely rate-limited after CancelJob burst!")
	}
}

// TestIsolatedRateLimiters_ProposePriceBurstDoesNotBlockRespondPrice proves that
// exhausting user:propose_price (20 req/min) does NOT block user:respond_price.
func TestIsolatedRateLimiters_ProposePriceBurstDoesNotBlockRespondPrice(t *testing.T) {
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()

	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	newLimiter := func(limit int, name string) *handlerutil.RateLimiter {
		return handlerutil.NewRateLimiter(ratelimit.NewRateLimiter(rdb, limit, 1*time.Minute, name))
	}

	svc := &UserService{
		proposePriceLimiter: newLimiter(20, "user:propose_price"),
		respondPriceLimiter: newLimiter(20, "user:respond_price"),
	}

	targetIP := "192.168.50.3:12345"

	// 1. Exhaust proposePriceLimiter budget (20 calls)
	for i := 0; i < 20; i++ {
		req := httptest.NewRequest(http.MethodPost, "/users/jobs/propose-price", strings.NewReader(`{}`))
		req.RemoteAddr = targetIP
		rec := httptest.NewRecorder()
		svc.ProposePrice(rec, req)
		if rec.Code == http.StatusTooManyRequests {
			t.Fatalf("ProposePrice call %d unexpectedly rate limited within 20/min budget", i+1)
		}
	}

	// 2. Call 21 on ProposePrice must be rejected with 429
	reqP21 := httptest.NewRequest(http.MethodPost, "/users/jobs/propose-price", strings.NewReader(`{}`))
	reqP21.RemoteAddr = targetIP
	recP21 := httptest.NewRecorder()
	svc.ProposePrice(recP21, reqP21)
	if recP21.Code != http.StatusTooManyRequests {
		t.Fatalf("Expected 21st ProposePrice call to be rate limited (429), got %d", recP21.Code)
	}

	// 3. RespondPrice from same IP must NOT be rate limited
	reqRespond := httptest.NewRequest(http.MethodPost, "/users/jobs/respond-price", strings.NewReader(`{}`))
	reqRespond.RemoteAddr = targetIP
	recRespond := httptest.NewRecorder()
	svc.RespondPrice(recRespond, reqRespond)
	if recRespond.Code == http.StatusTooManyRequests {
		t.Errorf("RespondPrice falsely rate-limited after ProposePrice burst!")
	}
}

// TestIsolatedRateLimiters_DepositAndRateJobIsolation proves that user:deposit (10/min)
// and user:rate_job (10/min) operate on completely separate budgets.
func TestIsolatedRateLimiters_DepositAndRateJobIsolation(t *testing.T) {
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()

	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	newLimiter := func(limit int, name string) *handlerutil.RateLimiter {
		return handlerutil.NewRateLimiter(ratelimit.NewRateLimiter(rdb, limit, 1*time.Minute, name))
	}

	svc := &UserService{
		depositLimiter: newLimiter(10, "user:deposit"),
		rateJobLimiter: newLimiter(10, "user:rate_job"),
	}

	targetIP := "192.168.50.4:12345"

	// 1. Exhaust depositLimiter budget (10 calls)
	for i := 0; i < 10; i++ {
		req := httptest.NewRequest(http.MethodPost, "/users/wallet/deposit", strings.NewReader(`{}`))
		req.RemoteAddr = targetIP
		rec := httptest.NewRecorder()
		svc.WalletDeposit(rec, req)
		if rec.Code == http.StatusTooManyRequests {
			t.Fatalf("WalletDeposit call %d unexpectedly rate limited within 10/min budget", i+1)
		}
	}

	// 2. Call 11 on WalletDeposit must be rejected with 429
	reqDep11 := httptest.NewRequest(http.MethodPost, "/users/wallet/deposit", strings.NewReader(`{}`))
	reqDep11.RemoteAddr = targetIP
	recDep11 := httptest.NewRecorder()
	svc.WalletDeposit(recDep11, reqDep11)
	if recDep11.Code != http.StatusTooManyRequests {
		t.Fatalf("Expected 11th WalletDeposit call to be rate limited (429), got %d", recDep11.Code)
	}

	// 3. RateJob from same IP must NOT be rate limited
	reqRate := httptest.NewRequest(http.MethodPost, "/users/jobs/rate", strings.NewReader(`{}`))
	reqRate.RemoteAddr = targetIP
	recRate := httptest.NewRecorder()
	svc.RateJob(recRate, reqRate)
	if recRate.Code == http.StatusTooManyRequests {
		t.Errorf("RateJob falsely rate-limited after WalletDeposit burst!")
	}
}

// TestIsolatedRateLimiters_RedisKeyPrefixes verifies that each per-action limiter
// creates independent Redis key prefixes matching the ADR-0016 specification.
func TestIsolatedRateLimiters_RedisKeyPrefixes(t *testing.T) {
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()

	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	newLimiter := func(limit int, name string) *handlerutil.RateLimiter {
		return handlerutil.NewRateLimiter(ratelimit.NewRateLimiter(rdb, limit, 1*time.Minute, name))
	}

	limiters := map[string]*handlerutil.RateLimiter{
		"user:track":         newLimiter(20, "user:track"),
		"user:propose_price": newLimiter(20, "user:propose_price"),
		"user:respond_price": newLimiter(20, "user:respond_price"),
		"user:cancel_job":    newLimiter(10, "user:cancel_job"),
		"user:rate_job":      newLimiter(10, "user:rate_job"),
		"user:deposit":       newLimiter(10, "user:deposit"),
		"user:ticket":        newLimiter(10, "user:ticket"),
	}

	clientKey := "client-test-key-1"
	for name, limiter := range limiters {
		limited, _ := limiter.CheckAndRecord(clientKey)
		if limited {
			t.Errorf("Limiter %s unexpectedly rate limited on first call", name)
		}
		expectedKey := "ratelimit:" + name + ":count:" + clientKey
		if !mr.Exists(expectedKey) {
			t.Errorf("Expected Redis key %q to exist for limiter %s", expectedKey, name)
		}
	}
}
