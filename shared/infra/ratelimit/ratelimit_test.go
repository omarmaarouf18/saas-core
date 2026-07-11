package ratelimit

import (
	"sync"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"
)

func TestRateLimiterSharedAndConcurrent(t *testing.T) {
	// 1. Start miniredis
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()

	// 2. Create two client instances pointed at the same Redis (simulating scaling out)
	rdb1 := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb1.Close()

	rdb2 := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb2.Close()

	// Create RateLimiters on both clients
	rl1 := NewRateLimiter(rdb1, 10, 1*time.Minute, "test-service")
	rl2 := NewRateLimiter(rdb2, 10, 1*time.Minute, "test-service")

	key := "192.168.1.1"

	// 3. Increment requests using BOTH rate limiter client instances
	for i := 0; i < 5; i++ {
		limited, _ := rl1.CheckAndRecord(key)
		if limited {
			t.Errorf("expected not to be limited on iteration %d via client 1", i)
		}
	}
	for i := 0; i < 5; i++ {
		limited, _ := rl2.CheckAndRecord(key)
		if limited {
			t.Errorf("expected not to be limited on iteration %d via client 2", i)
		}
	}

	// 4. The 11th request (combined limit is 10) must be limited, regardless of which client calls it
	limited, backoff := rl1.CheckAndRecord(key)
	if !limited {
		t.Errorf("expected 11th request to be rate limited (sharing failed)")
	}
	if backoff < 29*time.Second || backoff > 31*time.Second {
		t.Errorf("expected backoff around 30s, got %v", backoff)
	}

	limited, _ = rl2.CheckAndRecord(key)
	if !limited {
		t.Errorf("expected client 2 to also observe the rate limit lockout (sharing failed)")
	}
}

func TestRateLimiterConcurrency(t *testing.T) {
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()

	// Simulate 10 concurrent clients hitting the rate limiter at the same time
	const numClients = 10
	const requestsPerClient = 20
	const limit = 50

	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	rl := NewRateLimiter(rdb, limit, 1*time.Minute, "concurrent-service")
	key := "shared-ip"

	var wg sync.WaitGroup
	var mu sync.Mutex
	limitedCount := 0
	successCount := 0

	for i := 0; i < numClients; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for j := 0; j < requestsPerClient; j++ {
				limited, _ := rl.CheckAndRecord(key)
				mu.Lock()
				if limited {
					limitedCount++
				} else {
					successCount++
				}
				mu.Unlock()
			}
		}()
	}

	wg.Wait()

	// We expect exactly 'limit' requests to succeed, and the rest to be rate limited
	if successCount != limit {
		t.Errorf("expected exactly %d successful requests, got %d", limit, successCount)
	}
	expectedLimited := (numClients * requestsPerClient) - limit
	if limitedCount != expectedLimited {
		t.Errorf("expected exactly %d limited requests, got %d", expectedLimited, limitedCount)
	}
}

func TestAuthRateLimiterLockoutShared(t *testing.T) {
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()

	rdb1 := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb1.Close()

	rdb2 := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb2.Close()

	authRl1 := NewAuthRateLimiter(rdb1, "auth:email")
	authRl2 := NewAuthRateLimiter(rdb2, "auth:email")

	email := "user@example.com"

	// Record 4 failures on client 1
	for i := 0; i < 4; i++ {
		backoff := authRl1.RecordFailure(email)
		if backoff != 0 {
			t.Errorf("expected no lockout on failure %d", i+1)
		}
	}

	// 5th failure on client 2 must trigger lockout
	backoff := authRl2.RecordFailure(email)
	if backoff == 0 {
		t.Errorf("expected 5th failure (on client 2) to trigger lockout")
	}

	// Check lockout on both clients
	locked1, _ := authRl1.IsLocked(email)
	locked2, _ := authRl2.IsLocked(email)

	if !locked1 || !locked2 {
		t.Errorf("lockout was not correctly shared: client1=%v, client2=%v", locked1, locked2)
	}

	// Reset on client 1 should reset lockout on client 2 too
	authRl1.Reset(email)

	locked1, _ = authRl1.IsLocked(email)
	locked2, _ = authRl2.IsLocked(email)

	if locked1 || locked2 {
		t.Errorf("reset was not correctly shared: client1=%v, client2=%v", locked1, locked2)
	}
}

func TestRateLimiterFailClosed(t *testing.T) {
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	rl := NewRateLimiter(rdb, 10, 1*time.Minute, "fail-closed-service")
	authRl := NewAuthRateLimiter(rdb, "auth:ip")

	key := "test-key"

	// Stop miniredis to simulate runtime network failure
	rdb.Close()
	mr.Close()

	// 1. Check RateLimiter fail closed
	limited, retryAfter := rl.CheckAndRecord(key)
	if !limited {
		t.Errorf("expected rate limiter to fail closed on Redis unavailability")
	}
	if retryAfter != 30*time.Second {
		t.Errorf("expected 30s fallback retry time, got %v", retryAfter)
	}

	// 2. Check AuthRateLimiter fail closed (IsLocked)
	locked, lockoutDur := authRl.IsLocked(key)
	if !locked {
		t.Errorf("expected auth rate limiter (IsLocked) to fail closed on Redis unavailability")
	}
	if lockoutDur != 5*time.Minute {
		t.Errorf("expected 5m fallback lockout, got %v", lockoutDur)
	}

	// 3. Check AuthRateLimiter fail closed (RecordFailure)
	backoff := authRl.RecordFailure(key)
	if backoff != 5*time.Minute {
		t.Errorf("expected auth rate limiter (RecordFailure) to fail closed on Redis unavailability with 5m backoff, got %v", backoff)
	}
}
