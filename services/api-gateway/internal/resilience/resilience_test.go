package resilience

import (
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"

	"github.com/sony/gobreaker/v2"
)

func TestResilienceClient_RetryIdempotent(t *testing.T) {
	var attempts int32
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		atomic.AddInt32(&attempts, 1)
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer ts.Close()

	client := NewClient(http.DefaultClient, "test-retry-idempotent", 2, 50*time.Millisecond)
	// We want to speed up backoff during tests
	client.initialBackoff = 1 * time.Millisecond
	client.maxBackoff = 2 * time.Millisecond

	// 1. Test idempotent request (GET) -> Expect 3 total attempts (1 initial + 2 retries)
	req, _ := http.NewRequest("GET", ts.URL, nil)
	resp, err := client.Do(req)
	if err == nil {
		resp.Body.Close()
		t.Fatal("expected error from all-failing server")
	}

	finalAttempts := atomic.LoadInt32(&attempts)
	if finalAttempts != 3 {
		t.Errorf("expected 3 total attempts for GET, got %d", finalAttempts)
	}

	// Reset attempts count
	atomic.StoreInt32(&attempts, 0)

	// 2. Test non-idempotent request (POST) -> Expect exactly 1 attempt (no retries)
	reqPOST, _ := http.NewRequest("POST", ts.URL, nil)
	respPOST, errPOST := client.Do(reqPOST)
	if errPOST == nil {
		respPOST.Body.Close()
		t.Fatal("expected error from all-failing server")
	}

	finalPOSTAttempts := atomic.LoadInt32(&attempts)
	if finalPOSTAttempts != 1 {
		t.Errorf("expected exactly 1 attempt for POST, got %d", finalPOSTAttempts)
	}
}

func TestResilienceClient_CircuitBreakerTripAndRecover(t *testing.T) {
	var failMode int32 = 1 // 1 for fail, 0 for succeed
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if atomic.LoadInt32(&failMode) == 1 {
			w.WriteHeader(http.StatusInternalServerError)
		} else {
			w.WriteHeader(http.StatusOK)
		}
	}))
	defer ts.Close()

	client := NewClient(http.DefaultClient, "test-breaker-trip", 0, 50*time.Millisecond)
	// Modify breaker settings for quick cooldown in test
	client.breaker = gobreaker.NewCircuitBreaker[*http.Response](gobreaker.Settings{
		Name:        "test-breaker-trip",
		MaxRequests: 1, // 1 success in half-open will close it
		Timeout:     50 * time.Millisecond, // 50ms cooldown in open state
		ReadyToTrip: func(counts gobreaker.Counts) bool {
			return counts.ConsecutiveFailures >= 3 // trip after 3 consecutive failures
		},
	})

	// 1. Force failures until the breaker trips
	req, _ := http.NewRequest("GET", ts.URL, nil)
	for i := 0; i < 3; i++ {
		_, err := client.Do(req)
		if err == nil {
			t.Fatal("expected error")
		}
	}

	// 2. The 4th request should fail immediately with breaker open error without reaching the server
	_, err := client.Do(req)
	if err != gobreaker.ErrOpenState {
		t.Fatalf("expected breaker open state error, got: %v", err)
	}

	// 3. Wait for the cooldown timeout to expire
	time.Sleep(60 * time.Millisecond)

	// 4. Set server to succeed, request should succeed and close the breaker
	atomic.StoreInt32(&failMode, 0)
	resp, err := client.Do(req)
	if err != nil {
		t.Fatalf("expected request to succeed in half-open state, got error: %v", err)
	}
	resp.Body.Close()

	// 5. Breaker should be closed now, verify subsequent request works
	resp2, err2 := client.Do(req)
	if err2 != nil {
		t.Fatalf("expected closed breaker request to succeed, got error: %v", err2)
	}
	resp2.Body.Close()
}

func TestResilienceClient_AuthorizationFailClosed(t *testing.T) {
	// Tripped breaker on authorization-lookup must result in access denied
	client := NewClient(http.DefaultClient, "test-auth-fail-closed", 0, 50*time.Millisecond)
	// Trip breaker immediately
	client.breaker = gobreaker.NewCircuitBreaker[*http.Response](gobreaker.Settings{
		Name: "test-auth-fail-closed",
		ReadyToTrip: func(counts gobreaker.Counts) bool {
			return true
		},
	})
	
	// Execute first request to trip it
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer ts.Close()
	req, _ := http.NewRequest("GET", ts.URL, nil)
	_, _ = client.Do(req)

	// Verify breaker is open
	if client.breaker.State() != gobreaker.StateOpen {
		t.Fatal("expected breaker to be open")
	}

	// Simulated verifyToken/canAccessChannel logic
	verifyTokenSim := func() (bool, error) {
		req, _ := http.NewRequest("GET", ts.URL, nil)
		resp, err := client.Do(req)
		if err != nil {
			// This represents ErrOpenState or network failure
			return false, err
		}
		defer resp.Body.Close()
		return resp.StatusCode == http.StatusOK, nil
	}

	// Run authorization sim
	allowed, err := verifyTokenSim()
	if allowed {
		t.Fatal("expected authorization to fail closed when breaker is open")
	}
	if err != gobreaker.ErrOpenState {
		t.Fatalf("expected error to be ErrOpenState, got: %v", err)
	}
}
