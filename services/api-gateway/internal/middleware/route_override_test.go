package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"

	"github.com/project/shared/infra/ratelimit"
)

// TestRateLimitWithOverrides_SSEChurnDoesNotStarveGeneralBucket reproduces the
// production incident where aggressive SSE reconnect attempts on
// /api/v1/notifications/stream exhausted the single global per-IP budget and
// locked the client out of every unrelated endpoint. With bucket isolation,
// exhausting the SSE override budget must leave the general budget untouched.
func TestRateLimitWithOverrides_SSEChurnDoesNotStarveGeneralBucket(t *testing.T) {
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()

	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	general := NewRateLimiter(ratelimit.NewRateLimiter(rdb, 3, 1*time.Minute, "gw-test"), nil)
	sse := NewRateLimiter(ratelimit.NewRateLimiter(rdb, 2, 1*time.Minute, "gw-test-sse"), nil)

	handler := RateLimitWithOverrides(general, map[string]*RateLimiter{
		"/api/v1/notifications/stream": sse,
	})(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	do := func(path string) int {
		req := httptest.NewRequest(http.MethodGet, path, nil)
		req.RemoteAddr = "197.35.160.27:4444"
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)
		return rec.Code
	}

	// Exhaust the dedicated SSE bucket (limit 2): first two pass, third 429s.
	if got := do("/api/v1/notifications/stream"); got != http.StatusOK {
		t.Fatalf("stream request 1: expected 200, got %d", got)
	}
	if got := do("/api/v1/notifications/stream"); got != http.StatusOK {
		t.Fatalf("stream request 2: expected 200, got %d", got)
	}
	if got := do("/api/v1/notifications/stream"); got != http.StatusTooManyRequests {
		t.Fatalf("stream request 3: expected 429 (SSE bucket exhausted), got %d", got)
	}

	// The same IP's general-purpose traffic must be unaffected by the SSE churn.
	for i := 0; i < 3; i++ {
		if got := do("/api/v1/auth/user"); got != http.StatusOK {
			t.Fatalf("general request %d after SSE exhaustion: expected 200, got %d", i+1, got)
		}
	}
	// ...and the general bucket enforces its own independent limit.
	if got := do("/api/v1/auth/user"); got != http.StatusTooManyRequests {
		t.Fatalf("general request 4: expected 429 (general bucket exhausted), got %d", got)
	}
}

// TestRateLimitWithOverrides_NilOverridesMatchesLegacyBehavior guards the
// back-compat path: no overrides means every route shares the general bucket.
func TestRateLimitWithOverrides_NilOverridesMatchesLegacyBehavior(t *testing.T) {
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()

	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	general := NewRateLimiter(ratelimit.NewRateLimiter(rdb, 1, 1*time.Minute, "gw-test-single"), nil)
	handler := RateLimitWithOverrides(general, nil)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	do := func(path string) int {
		req := httptest.NewRequest(http.MethodGet, path, nil)
		req.RemoteAddr = "10.1.2.3:5555"
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)
		return rec.Code
	}

	if got := do("/api/v1/auth/user"); got != http.StatusOK {
		t.Fatalf("first request: expected 200, got %d", got)
	}
	// A different route draws from the SAME bucket when no overrides exist.
	if got := do("/api/v1/notifications/stream"); got != http.StatusTooManyRequests {
		t.Fatalf("second request on other route: expected 429 from shared bucket, got %d", got)
	}
}
