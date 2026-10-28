package handlers

import (
	"context"
	"log"
	"strings"
	"time"

	"github.com/project/shared/infra/ratelimit"
	"github.com/redis/go-redis/v9"
)

type RateLimiter struct {
	ipLimiter               *ratelimit.AuthRateLimiter
	emailLimiter            *ratelimit.AuthRateLimiter
	generalLimiter          *ratelimit.RateLimiter
	reviewerLimiter         *ratelimit.ReviewerRateLimiter
	client                  *redis.Client
	globalCeilingThreshold  int
	globalCeilingLockoutTTL time.Duration
}

func NewRateLimiter(client *redis.Client) *RateLimiter {
	var gen *ratelimit.RateLimiter
	if client != nil {
		gen = ratelimit.NewRateLimiter(client, 30, 1*time.Minute, "auth:employees")
	}
	return &RateLimiter{
		ipLimiter:               ratelimit.NewAuthRateLimiter(client, "auth:ip"),
		emailLimiter:            ratelimit.NewAuthRateLimiter(client, "auth:email"),
		generalLimiter:          gen,
		reviewerLimiter:         ratelimit.NewReviewerRateLimiter(client, "auth:reviewer"),
		client:                  client,
		globalCeilingThreshold:  20,
		globalCeilingLockoutTTL: 5 * time.Minute,
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

// IsReviewerLocked checks if a reviewer key (IP or token hash) is locked out.
func (rl *RateLimiter) IsReviewerLocked(key string) (bool, time.Duration) {
	if key == "" || rl == nil || rl.reviewerLimiter == nil {
		return false, 0
	}
	return rl.reviewerLimiter.IsLocked(key)
}

// RecordReviewerFailure records a reviewer auth failure and returns the lockout duration if locked.
func (rl *RateLimiter) RecordReviewerFailure(key string) time.Duration {
	if key == "" || rl == nil || rl.reviewerLimiter == nil {
		return 0
	}
	return rl.reviewerLimiter.RecordFailure(key)
}

// ResetReviewer clears reviewer failure history and lockout for a key upon successful auth.
func (rl *RateLimiter) ResetReviewer(key string) {
	if key == "" || rl == nil || rl.reviewerLimiter == nil {
		return
	}
	rl.reviewerLimiter.Reset(key)
}

// ResetReviewerGlobal clears the global reviewer failure counter and lockout.
func (rl *RateLimiter) ResetReviewerGlobal() {
	if rl == nil || rl.client == nil {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	_ = rl.client.Del(ctx, "ratelimit:auth:reviewer:count:global", "ratelimit:auth:reviewer:lockout:global").Err()
}

// SetReviewerGlobalCeiling overrides the global ceiling threshold and lockout TTL (for tests and tuning).
func (rl *RateLimiter) SetReviewerGlobalCeiling(threshold int, lockoutTTL time.Duration) {
	if rl != nil {
		rl.globalCeilingThreshold = threshold
		rl.globalCeilingLockoutTTL = lockoutTTL
	}
}

// IsReviewerGlobalLocked checks if the reviewer global ceiling lockout is currently engaged.
func (rl *RateLimiter) IsReviewerGlobalLocked() (bool, time.Duration) {
	if rl == nil || rl.client == nil {
		return false, 0
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	lockoutKey := "ratelimit:auth:reviewer:lockout:global"
	ttl, err := rl.client.TTL(ctx, lockoutKey).Result()
	if err != nil {
		log.Printf("[SECURITY CRITICAL] Redis ReviewerRateLimiter IsReviewerGlobalLocked check error (FAIL CLOSED): %v", err)
		lockoutTTL := rl.globalCeilingLockoutTTL
		if lockoutTTL <= 0 {
			lockoutTTL = 5 * time.Minute
		}
		return true, lockoutTTL
	}
	if ttl > 0 {
		return true, ttl
	}
	return false, 0
}

const reviewerGlobalRecordFailureScript = `
local countKey = KEYS[1]
local lockoutKey = KEYS[2]
local threshold = tonumber(ARGV[1])
local lockoutSec = tonumber(ARGV[2])

local count = redis.call('INCR', countKey)
redis.call('EXPIRE', countKey, lockoutSec)

if count >= threshold then
    redis.call('DEL', countKey)
    redis.call('SET', lockoutKey, '1', 'EX', lockoutSec)
    return lockoutSec
end
return 0
`

// RecordReviewerGlobalFailure records a failed reviewer attempt globally and returns lockout duration if ceiling reached.
func (rl *RateLimiter) RecordReviewerGlobalFailure() time.Duration {
	if rl == nil || rl.client == nil {
		return 0
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	countKey := "ratelimit:auth:reviewer:count:global"
	lockoutKey := "ratelimit:auth:reviewer:lockout:global"
	threshold := rl.globalCeilingThreshold
	if threshold <= 0 {
		threshold = 20
	}
	lockoutTTL := rl.globalCeilingLockoutTTL
	if lockoutTTL <= 0 {
		lockoutTTL = 5 * time.Minute
	}

	res, err := rl.client.Eval(ctx, reviewerGlobalRecordFailureScript, []string{countKey, lockoutKey}, threshold, int(lockoutTTL.Seconds())).Result()
	if err != nil {
		log.Printf("[SECURITY CRITICAL] Redis ReviewerRateLimiter RecordReviewerGlobalFailure error (FAIL CLOSED): %v", err)
		return lockoutTTL
	}
	backoffSec, ok := res.(int64)
	if !ok {
		return lockoutTTL
	}
	return time.Duration(backoffSec) * time.Second
}
