package handlers

import (
	"sync"
	"time"
)

type FailureRecord struct {
	Count       int
	LockedUntil time.Time
}

type RateLimiter struct {
	mu       sync.Mutex
	failures map[string]*FailureRecord
}

func NewRateLimiter() *RateLimiter {
	return &RateLimiter{
		failures: make(map[string]*FailureRecord),
	}
}

// IsLocked checks if a key (email or IP) is currently locked out.
// Returns true and the remaining duration if locked.
func (rl *RateLimiter) IsLocked(key string) (bool, time.Duration) {
	if key == "" {
		return false, 0
	}
	rl.mu.Lock()
	defer rl.mu.Unlock()

	rec, exists := rl.failures[key]
	if !exists {
		return false, 0
	}

	now := time.Now()
	if now.Before(rec.LockedUntil) {
		return true, rec.LockedUntil.Sub(now)
	}

	return false, 0
}

// RecordFailure records a failure for a key and returns the lockout duration if locked.
func (rl *RateLimiter) RecordFailure(key string) time.Duration {
	if key == "" {
		return 0
	}
	rl.mu.Lock()
	defer rl.mu.Unlock()

	rec, exists := rl.failures[key]
	if !exists {
		rec = &FailureRecord{}
		rl.failures[key] = rec
	}

	rec.Count++
	if rec.Count >= 5 {
		// Exponential backoff starting at 30 seconds: 30s * 2^(count - 5)
		backoffSeconds := 30 << (rec.Count - 5)
		if backoffSeconds > 300 { // Cap at 5 minutes
			backoffSeconds = 300
		}
		rec.LockedUntil = time.Now().Add(time.Duration(backoffSeconds) * time.Second)
		return time.Duration(backoffSeconds) * time.Second
	}

	return 0
}

// Reset resets the failure record for a key upon successful auth.
func (rl *RateLimiter) Reset(key string) {
	if key == "" {
		return
	}
	rl.mu.Lock()
	defer rl.mu.Unlock()
	delete(rl.failures, key)
}
