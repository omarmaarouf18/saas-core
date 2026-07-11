package handlers

import (
	"strings"
	"time"

	"github.com/redis/go-redis/v9"
	"github.com/project/auth-service/internal/ratelimit"
)

type RateLimiter struct {
	ipLimiter    *ratelimit.AuthRateLimiter
	emailLimiter *ratelimit.AuthRateLimiter
}

func NewRateLimiter(client *redis.Client) *RateLimiter {
	return &RateLimiter{
		ipLimiter:    ratelimit.NewAuthRateLimiter(client, "auth:ip"),
		emailLimiter: ratelimit.NewAuthRateLimiter(client, "auth:email"),
	}
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

