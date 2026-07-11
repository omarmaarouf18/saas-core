package ratelimit

import (
	"context"
	"fmt"
	"log"
	"time"

	"github.com/redis/go-redis/v9"
)

// NewRedisClient creates and pings a Redis client to ensure reachability.
func NewRedisClient(redisURI string) (*redis.Client, error) {
	opts, err := redis.ParseURL(redisURI)
	if err != nil {
		opts = &redis.Options{
			Addr: redisURI,
		}
	}
	rdb := redis.NewClient(opts)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := rdb.Ping(ctx).Err(); err != nil {
		return nil, err
	}
	return rdb, nil
}

// RateLimiter is a Redis-backed sliding window rate limiter with exponential backoff lockout.
type RateLimiter struct {
	client *redis.Client
	limit  int
	window time.Duration
	cap    int
	prefix string
}

func NewRateLimiter(client *redis.Client, limit int, window time.Duration, prefix string) *RateLimiter {
	return &RateLimiter{
		client: client,
		limit:  limit,
		window: window,
		cap:    300,
		prefix: prefix,
	}
}

const checkAndRecordScript = `
local countKey = KEYS[1]
local lockoutKey = KEYS[2]

local limit = tonumber(ARGV[1])
local window = tonumber(ARGV[2])
local cap = tonumber(ARGV[3])

-- 1. Check if locked out
local lockoutTTL = redis.call('TTL', lockoutKey)
if lockoutTTL > 0 then
    return {1, lockoutTTL}
end

-- 2. Increment count
local count = redis.call('INCR', countKey)
redis.call('EXPIRE', countKey, window)

-- 3. Check if limit exceeded
if count > limit then
    local diff = count - limit - 1
    local backoff = 30 * (2 ^ diff)
    if backoff > cap then
        backoff = cap
    end
    redis.call('SET', lockoutKey, '1', 'EX', math.floor(backoff))
    return {1, math.floor(backoff)}
end

return {0, 0}
`

func (rl *RateLimiter) CheckAndRecord(key string) (bool, time.Duration) {
	if key == "" {
		return false, 0
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	countKey := fmt.Sprintf("ratelimit:%s:count:%s", rl.prefix, key)
	lockoutKey := fmt.Sprintf("ratelimit:%s:lockout:%s", rl.prefix, key)

	res, err := rl.client.Eval(ctx, checkAndRecordScript, []string{countKey, lockoutKey}, rl.limit, int(rl.window.Seconds()), rl.cap).Result()
	if err != nil {
		// FAIL CLOSED: Log critical error and block request
		log.Printf("[SECURITY CRITICAL] Redis rate limiter error (FAIL CLOSED): %v. Restricting traffic for key: %s", err, key)
		return true, 30 * time.Second
	}

	results, ok := res.([]interface{})
	if !ok || len(results) < 2 {
		log.Printf("[SECURITY CRITICAL] Unexpected rate limiter response: %v. Fail closed for key: %s", res, key)
		return true, 30 * time.Second
	}

	limited := results[0].(int64) == 1
	ttl := results[1].(int64)

	return limited, time.Duration(ttl) * time.Second
}

// AuthRateLimiter is a Redis-backed dual-key lockout tracker (IP + email).
type AuthRateLimiter struct {
	client *redis.Client
	cap    int
	prefix string
}

func NewAuthRateLimiter(client *redis.Client, prefix string) *AuthRateLimiter {
	return &AuthRateLimiter{
		client: client,
		cap:    300,
		prefix: prefix,
	}
}

const recordFailureScript = `
local countKey = KEYS[1]
local lockoutKey = KEYS[2]
local cap = tonumber(ARGV[1])

local count = redis.call('INCR', countKey)
redis.call('EXPIRE', countKey, 86400) -- 24h TTL for count

if count >= 5 then
    local diff = count - 5
    local backoff = 30 * (2 ^ diff)
    if backoff > cap then
        backoff = cap
    end
    redis.call('SET', lockoutKey, '1', 'EX', math.floor(backoff))
    return math.floor(backoff)
end
return 0
`

func (rl *AuthRateLimiter) IsLocked(key string) (bool, time.Duration) {
	if key == "" {
		return false, 0
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	lockoutKey := fmt.Sprintf("ratelimit:%s:lockout:%s", rl.prefix, key)
	ttl, err := rl.client.TTL(ctx, lockoutKey).Result()
	if err != nil {
		log.Printf("[SECURITY CRITICAL] Redis IsLocked check error (FAIL CLOSED): %v. Locking key: %s", err, key)
		return true, 5 * time.Minute
	}

	if ttl > 0 {
		return true, ttl
	}
	return false, 0
}

func (rl *AuthRateLimiter) RecordFailure(key string) time.Duration {
	if key == "" {
		return 0
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	countKey := fmt.Sprintf("ratelimit:%s:count:%s", rl.prefix, key)
	lockoutKey := fmt.Sprintf("ratelimit:%s:lockout:%s", rl.prefix, key)

	res, err := rl.client.Eval(ctx, recordFailureScript, []string{countKey, lockoutKey}, rl.cap).Result()
	if err != nil {
		log.Printf("[SECURITY CRITICAL] Redis RecordFailure error (FAIL CLOSED): %v. Enforcing lockout for key: %s", err, key)
		return 5 * time.Minute
	}

	backoffSec, ok := res.(int64)
	if !ok {
		log.Printf("[SECURITY CRITICAL] Unexpected RecordFailure response: %v. Fail closed for key: %s", res, key)
		return 5 * time.Minute
	}

	return time.Duration(backoffSec) * time.Second
}

func (rl *AuthRateLimiter) Reset(key string) {
	if key == "" {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	countKey := fmt.Sprintf("ratelimit:%s:count:%s", rl.prefix, key)
	lockoutKey := fmt.Sprintf("ratelimit:%s:lockout:%s", rl.prefix, key)

	_, err := rl.client.Del(ctx, countKey, lockoutKey).Result()
	if err != nil {
		log.Printf("[ERROR] Failed to reset rate limiter keys in Redis: %v", err)
	}
}
