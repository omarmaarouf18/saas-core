package middleware

import (
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/project/shared/infra/ratelimit"
)

type RateLimiter struct {
	rl *ratelimit.RateLimiter
}

func NewRateLimiter(rl *ratelimit.RateLimiter) *RateLimiter {
	return &RateLimiter{rl: rl}
}

func (rl *RateLimiter) CheckAndRecord(key string) (bool, time.Duration) {
	return rl.rl.CheckAndRecord(key)
}

// getIP extracts the client IP from r.RemoteAddr only.
// At the gateway edge there is no trusted upstream proxy, so
// X-Forwarded-For and X-Real-IP are fully client-controlled and
// MUST NOT be used for rate-limit keying — an attacker can spoof a
// different value on every request to get a fresh bucket each time.
func getIP(r *http.Request) string {
	ip := r.RemoteAddr

	if strings.Contains(ip, "]") {
		if idx := strings.LastIndex(ip, ":"); idx != -1 {
			ip = ip[:idx]
		}
		ip = strings.Trim(ip, "[]")
	} else {
		if count := strings.Count(ip, ":"); count == 1 {
			if idx := strings.LastIndex(ip, ":"); idx != -1 {
				ip = ip[:idx]
			}
		}
	}
	return ip
}

// RateLimit is a middleware that enforces rate limiting on all incoming requests.
func RateLimit(limiter *RateLimiter) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			ip := getIP(r)
			if limited, remaining := limiter.CheckAndRecord(ip); limited {
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusTooManyRequests)
				fmt.Fprintf(w, `{"error":"too many requests, locked out for %.0f seconds"}`, remaining.Seconds())
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}
