package ratelimit

import (
	"errors"
	"testing"
)

// BE-HARDEN item 2: a rate limiter without a Redis client (Redis was
// unreachable at startup) must fail closed instead of panicking on the nil
// client.

func TestRateLimiter_NilClientFailsClosed(t *testing.T) {
	rl := NewRateLimiter(nil, 300, 1, "test-nil-client")

	// The historical entry point must not panic and must deny the request.
	limited, ttl := rl.CheckAndRecord("key-1")
	if !limited {
		t.Error("expected the request to be denied (fail closed)")
	}
	if ttl <= 0 {
		t.Errorf("expected a lockout duration, got %v", ttl)
	}

	// The detailed entry point reports why the request was denied.
	limited, ttl, err := rl.CheckAndRecordDetailed("key-2")
	if !limited {
		t.Error("expected the request to be denied (fail closed)")
	}
	if ttl <= 0 {
		t.Errorf("expected a lockout duration, got %v", ttl)
	}
	if !errors.Is(err, ErrNoRedisClient) {
		t.Errorf("expected ErrNoRedisClient, got %v", err)
	}
}

// A nil limiter must not panic either.
func TestRateLimiter_NilLimiterFailsClosed(t *testing.T) {
	var rl *RateLimiter
	limited, _, err := rl.CheckAndRecordDetailed("key-1")
	if !limited {
		t.Error("expected the request to be denied (fail closed)")
	}
	if !errors.Is(err, ErrNoRedisClient) {
		t.Errorf("expected ErrNoRedisClient, got %v", err)
	}
}

// The other limiters of the package share the nil-client hazard.
func TestOtherLimiters_NilClientDoesNotPanic(t *testing.T) {
	authRl := NewAuthRateLimiter(nil, "test-auth-nil-client")
	if locked, _ := authRl.IsLocked("key-1"); !locked {
		t.Error("expected the auth limiter to fail closed")
	}
	if d := authRl.RecordFailure("key-1"); d <= 0 {
		t.Errorf("expected a lockout duration, got %v", d)
	}
	authRl.Reset("key-1")

	reviewerRl := NewReviewerRateLimiter(nil, "test-reviewer-nil-client")
	if locked, _ := reviewerRl.IsLocked("key-1"); !locked {
		t.Error("expected the reviewer limiter to fail closed")
	}
	if d := reviewerRl.RecordFailure("key-1"); d <= 0 {
		t.Errorf("expected a lockout duration, got %v", d)
	}
	reviewerRl.Reset("key-1")
}
