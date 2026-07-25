package handlers

import (
	"strings"
	"time"

	"github.com/project/shared/infra/ratelimit"
	"github.com/redis/go-redis/v9"
)

type RateLimiter struct {
	ipLimiter      *ratelimit.AuthRateLimiter
	emailLimiter   *ratelimit.AuthRateLimiter
	generalLimiter *ratelimit.RateLimiter
}

func NewRateLimiter(client *redis.Client) *RateLimiter {
	var gen *ratelimit.RateLimiter
	if client != nil {
		gen = ratelimit.NewRateLimiter(client, 30, 1*time.Minute, "auth:employees")
	}
	return &RateLimiter{
		ipLimiter:      ratelimit.NewAuthRateLimiter(client, "auth:ip"),
		emailLimiter:   ratelimit.NewAuthRateLimiter(client, "auth:email"),
		generalLimiter: gen,
	}
}

// CheckAndRecord checks and records a hit against the sliding window rate limiter for general endpoint keys.
// Returns true and remaining lockout duration if limited.
func (rl *RateLimiter) CheckAndRecord(key string) (bool, time.Duration) {
	if key == "" || rl == nil || rl.generalLimiter == nil {
		return false, 0
	}
	return rl.generalLimiter.CheckAndRecord(key)
}

func (rl *RateLimiter) getLimiter(key string) *ratelimit.AuthRateLimiter {
	if strings.Contains(key, "@") {
		return rl.emailLimiter
	}
	return rl.ipLimiter
}

// IsLocked checks if a key (email or IP) is currently locked out.
// Returns true and the remaining duration if locked.
func (rl *RateLimiter) IsLocked(key string) (bool, time.Duration) {
	if key == "" {
		return false, 0
	}
	return rl.getLimiter(key).IsLocked(key)
}

// RecordFailure records a failure for a key and returns the lockout duration if locked.
func (rl *RateLimiter) RecordFailure(key string) time.Duration {
	if key == "" {
		return 0
	}
	return rl.getLimiter(key).RecordFailure(key)
}

// Reset resets the failure record for a key upon successful auth.
func (rl *RateLimiter) Reset(key string) {
	if key == "" {
		return
	}
	rl.getLimiter(key).Reset(key)
}
