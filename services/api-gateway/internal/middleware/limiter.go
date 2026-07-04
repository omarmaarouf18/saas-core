package middleware

import (
	"fmt"
	"net/http"
	"strings"
	"sync"
	"time"
)

type RequestRecord struct {
	Count       int
	LockedUntil time.Time
	LastRequest time.Time
}

type RateLimiter struct {
	mu      sync.Mutex
	records map[string]*RequestRecord
	limit   int
	window  time.Duration
	cap     int
}

func NewRateLimiter(limit int, window time.Duration) *RateLimiter {
	return &RateLimiter{
		records: make(map[string]*RequestRecord),
		limit:   limit,
		window:  window,
		cap:     300,
	}
}

func (rl *RateLimiter) CheckAndRecord(key string) (bool, time.Duration) {
	if key == "" {
		return false, 0
	}
	rl.mu.Lock()
	defer rl.mu.Unlock()

	now := time.Now()
	rec, exists := rl.records[key]
	if !exists {
		rec = &RequestRecord{
			Count:       1,
			LastRequest: now,
		}
		rl.records[key] = rec
		return false, 0
	}

	if now.Before(rec.LockedUntil) {
		return true, rec.LockedUntil.Sub(now)
	}

	if now.Sub(rec.LastRequest) > rl.window {
		rec.Count = 0
	}

	rec.Count++
	rec.LastRequest = now

	if rec.Count > rl.limit {
		backoffSeconds := 30 << (rec.Count - rl.limit - 1)
		if backoffSeconds > rl.cap {
			backoffSeconds = rl.cap
		}
		rec.LockedUntil = now.Add(time.Duration(backoffSeconds) * time.Second)
		return true, time.Duration(backoffSeconds) * time.Second
	}

	return false, 0
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
