package handlers

import (
	"testing"
	"time"

	"golang.org/x/crypto/bcrypt"
)

// TestBcryptHashVerify checks the password hashing and verification flow
func TestBcryptHashVerify(t *testing.T) {
	password := "my-secret-password-123"
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		t.Fatalf("Failed to hash password: %v", err)
	}

	// Verify success case
	err = bcrypt.CompareHashAndPassword(hashedPassword, []byte(password))
	if err != nil {
		t.Errorf("Password verification failed: %v", err)
	}

	// Verify failure case
	err = bcrypt.CompareHashAndPassword(hashedPassword, []byte("wrong-password"))
	if err == nil {
		t.Errorf("Expected password verification to fail for wrong password")
	}
}

// TestRateLimiterLockout checks rate limit lockout counting and backoff
func TestRateLimiterLockout(t *testing.T) {
	rl := NewRateLimiter()
	key := "test-client-ip"

	// Initial state: not locked
	locked, _ := rl.IsLocked(key)
	if locked {
		t.Errorf("Expected key to not be locked initially")
	}

	// Record 4 failures (lockout threshold is 5)
	for i := 0; i < 4; i++ {
		rl.RecordFailure(key)
		locked, _ = rl.IsLocked(key)
		if locked {
			t.Errorf("Expected key to not be locked after %d failures", i+1)
		}
	}

	// 5th failure should trigger lockout
	duration := rl.RecordFailure(key)
	if duration != 30*time.Second {
		t.Errorf("Expected lockout duration to be 30 seconds, got %v", duration)
	}

	locked, remaining := rl.IsLocked(key)
	if !locked {
		t.Errorf("Expected key to be locked after 5 failures")
	}
	if remaining <= 0 || remaining > 30*time.Second {
		t.Errorf("Expected remaining duration to be <= 30 seconds, got %v", remaining)
	}

	// Reset rate limiter key
	rl.Reset(key)
	locked, _ = rl.IsLocked(key)
	if locked {
		t.Errorf("Expected key to be unlocked after reset")
	}
}

// TestOTPExpiryRejection simulates OTP verification where expiration times are set
func TestOTPExpiryRejection(t *testing.T) {
	now := time.Now()
	expiresAtPast := now.Add(-1 * time.Minute)
	expiresAtFuture := now.Add(5 * time.Minute)

	tests := []struct {
		name      string
		expiresAt time.Time
		nowTime   time.Time
		expectErr bool
	}{
		{
			name:      "Expired OTP",
			expiresAt: expiresAtPast,
			nowTime:   now,
			expectErr: true,
		},
		{
			name:      "Valid OTP",
			expiresAt: expiresAtFuture,
			nowTime:   now,
			expectErr: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			hasExpired := !tt.expiresAt.IsZero() && tt.expiresAt.Before(tt.nowTime)
			if hasExpired != tt.expectErr {
				t.Errorf("Expected expiry rejection check to return %v, got %v", tt.expectErr, hasExpired)
			}
		})
	}
}
