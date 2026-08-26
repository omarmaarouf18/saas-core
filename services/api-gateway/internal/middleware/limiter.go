package middleware

import (
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/project/gateway/internal/iputil"
	"github.com/project/shared/infra/ratelimit"
)

type RateLimiter struct {
	rl             *ratelimit.RateLimiter
	trustedProxies []string
}

func NewRateLimiter(rl *ratelimit.RateLimiter, trustedProxies ...[]string) *RateLimiter {
	var tp []string
	if len(trustedProxies) > 0 {
		tp = trustedProxies[0]
	}
	return &RateLimiter{rl: rl, trustedProxies: tp}
}

func (rl *RateLimiter) CheckAndRecord(key string) (bool, time.Duration) {
	return rl.rl.CheckAndRecord(key)
}

// getIP extracts the client IP for rate limiting using trusted proxy aware resolution.
// Trust Chain Hop 1 (Caddy -> api-gateway):
// X-Forwarded-For is trusted ONLY when r.RemoteAddr comes from a trusted proxy in trustedProxies.
// Otherwise, r.RemoteAddr is used directly to prevent IP spoofing attacks.
func (rl *RateLimiter) getIP(r *http.Request) string {
	return iputil.ResolveClientIP(r, rl.trustedProxies)
}

// RateLimit is a middleware that enforces rate limiting on all incoming requests.
func RateLimit(limiter *RateLimiter) func(http.Handler) http.Handler {
	return RateLimitWithOverrides(limiter, nil)
}

// RateLimitWithOverrides enforces per-client-IP rate limiting with dedicated
// buckets for specific path prefixes. Long-lived or aggressively-reconnecting
// endpoints (e.g. the SSE notifications stream) must be isolated into their
// own bucket: their connect churn would otherwise exhaust the single global
// per-IP budget and lock the client out of every unrelated API endpoint.
// The longest matching registered prefix wins; unmatched paths use the
// general limiter.
//
// Loopback callers (Docker HEALTHCHECK probes, local diagnostics) are exempt:
// they share one tiny ::1 bucket that health verification depends on, and a
// locked healthcheck surfaces as a false "unhealthy" container state.
func RateLimitWithOverrides(limiter *RateLimiter, overrides map[string]*RateLimiter) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			effective := limiter
			if prefix := longestOf(overrides, r.URL.Path); prefix != "" {
				effective = overrides[prefix]
			}
			ip := effective.getIP(r)
			if ip == "127.0.0.1" || ip == "::1" {
				next.ServeHTTP(w, r)
				return
			}
			if limited, remaining := effective.CheckAndRecord(ip); limited {
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusTooManyRequests)
				// #nosec G705 //nolint:gosec -- raw JSON response does not contain user-provided HTML, XSS not possible
				fmt.Fprintf(w, `{"error":"too many requests, locked out for %.0f seconds"}`, remaining.Seconds())
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

// longestOf returns the longest registered override prefix that path starts
// with, or "" when none match.
func longestOf(overrides map[string]*RateLimiter, path string) string {
	best := ""
	for prefix := range overrides {
		if strings.HasPrefix(path, prefix) && len(prefix) > len(best) {
			best = prefix
		}
	}
	return best
}
