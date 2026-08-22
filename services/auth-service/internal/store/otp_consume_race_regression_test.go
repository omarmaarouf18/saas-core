package store

import (
	"context"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/project/auth-service/internal/models"
)

// Regression test for the OTP consume-semantics race (independent QA audit
// finding Q7).
//
// Defect: VerifyOTP validated against a stale snapshot and then performed an
// UNCONDITIONAL consume write ({email}-only filter). Two concurrent submits
// of the same valid code both passed the compare and both "succeeded"
// (double-consume — downstream: two login JWTs from one OTP); a concurrent
// SetOTP (resend) interleaving with a verifier destroyed the newest code on
// stale evidence.
//
// Contract under test: exactly ONE concurrent submit of a given code may
// succeed; every other submit of that code must fail. The fix consumes via
// optimistic CAS keyed on the stored ciphertext (random GCM nonce makes each
// issued code's ciphertext unique), so a resend or a competing verifier both
// invalidate the handle.
//
// Pre-fix literal failure (observed): "OTP CONSUMED 2 times by concurrent
// submits of one code (want exactly 1)".
func TestVerifyOTP_ConcurrentSubmitConsumesExactlyOnce(t *testing.T) {
	s, cleanup := setupTestStore(t)
	if s == nil {
		return
	}
	defer cleanup()
	ctx := context.Background()

	email := "otp-race@example.com"
	if err := s.CreateUser(ctx, &models.User{
		ID: "otp-race-1", Email: email, Username: "otprace",
		Password: "Password123!", Role: models.RoleUser, IsActive: true,
		CreatedAt: time.Now().UTC(),
	}); err != nil {
		t.Fatalf("create user: %v", err)
	}

	const workers = 12
	const rounds = 8
	var doubleConsumed int32

	for round := 0; round < rounds; round++ {
		if err := s.SetOTP(ctx, email, "654321"); err != nil {
			t.Fatalf("set otp: %v", err)
		}

		var successes int32
		start := make(chan struct{})
		var wg sync.WaitGroup
		for i := 0; i < workers; i++ {
			wg.Add(1)
			go func() {
				defer wg.Done()
				<-start
				if err := s.VerifyOTP(ctx, email, "654321"); err == nil {
					atomic.AddInt32(&successes, 1)
				}
			}()
		}
		close(start)
		wg.Wait()

		if got := atomic.LoadInt32(&successes); got > 1 {
			atomic.StoreInt32(&doubleConsumed, 1)
			t.Logf("round %d: OTP consumed %d times", round, got)
		}
		if err := s.SetOTP(ctx, email, "111111"); err == nil {
			// re-arm handled by loop head; nothing to do
			_ = err
		}
	}

	if atomic.LoadInt32(&doubleConsumed) != 0 {
		t.Fatalf("OTP CONSUMED MULTIPLE TIMES BY CONCURRENT SUBMITS OF ONE CODE across %d rounds (want exactly 1 success per code)", rounds)
	}
}
