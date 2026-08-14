package handlers

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/project/shared/infra/handlerutil"
	"github.com/project/shared/infra/jwtutil"
	"github.com/project/shared/infra/ratelimit"
	"github.com/redis/go-redis/v9"
)

func TestGetLedger_SingleRateLimitCheck(t *testing.T) {
	t.Setenv("JWT_SECRET", "test-jwt-secret-12345678901234567890")

	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()

	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	svc := &UserService{
		// Set ledgerLimiter budget to exactly 2 requests per minute
		ledgerLimiter: handlerutil.NewRateLimiter(ratelimit.NewRateLimiter(rdb, 2, 1*time.Minute, "test_ledger")),
	}

	token, err := jwtutil.GenerateToken("owner-tenant-123", "owner", "owner-tenant-123", "owner@example.com")
	if err != nil {
		t.Fatalf("Failed to generate token: %v", err)
	}

	// Call 1: Should succeed (1/2 used)
	req1 := httptest.NewRequest(http.MethodGet, "/users/ledger?tenant_token="+token, nil)
	rr1 := httptest.NewRecorder()
	svc.GetLedger(rr1, req1)
	if rr1.Code == http.StatusTooManyRequests {
		t.Fatalf("First GetLedger call unexpectedly rate limited (HTTP 429)")
	}

	// Call 2: Should succeed (2/2 used)
	req2 := httptest.NewRequest(http.MethodGet, "/users/ledger?tenant_token="+token, nil)
	rr2 := httptest.NewRecorder()
	svc.GetLedger(rr2, req2)
	if rr2.Code == http.StatusTooManyRequests {
		t.Fatalf("Second GetLedger call unexpectedly rate limited (HTTP 429) — double-charge bug detected!")
	}

	// Call 3: Should trigger rate limit (3/2 attempted -> 429)
	req3 := httptest.NewRequest(http.MethodGet, "/users/ledger?tenant_token="+token, nil)
	rr3 := httptest.NewRecorder()
	svc.GetLedger(rr3, req3)
	if rr3.Code != http.StatusTooManyRequests {
		t.Fatalf("Third GetLedger call expected HTTP 429, got %d", rr3.Code)
	}
}

func TestReadRateLimiters_Independence(t *testing.T) {
	t.Setenv("JWT_SECRET", "test-jwt-secret-12345678901234567890")

	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()

	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	svc := &UserService{
		// Set ratingsLimiter to 2 req/min and ownerJobsLimiter to 60 req/min
		ratingsLimiter:   handlerutil.NewRateLimiter(ratelimit.NewRateLimiter(rdb, 2, 1*time.Minute, "test_ratings")),
		ownerJobsLimiter: handlerutil.NewRateLimiter(ratelimit.NewRateLimiter(rdb, 60, 1*time.Minute, "test_owner_jobs")),
	}

	ownerToken, err := jwtutil.GenerateToken("owner-456", "owner", "owner-456", "owner@example.com")
	if err != nil {
		t.Fatalf("Failed to generate token: %v", err)
	}

	// Exhaust ratingsLimiter budget (2 calls)
	reqR1 := httptest.NewRequest(http.MethodGet, "/users/ratings?user_id=target-123", nil)
	reqR1.Header.Set("Authorization", "Bearer "+ownerToken)
	reqR1.RemoteAddr = "192.168.1.100:12345"
	rrR1 := httptest.NewRecorder()
	svc.GetRatings(rrR1, reqR1)

	reqR2 := httptest.NewRequest(http.MethodGet, "/users/ratings?user_id=target-123", nil)
	reqR2.Header.Set("Authorization", "Bearer "+ownerToken)
	reqR2.RemoteAddr = "192.168.1.100:12345"
	rrR2 := httptest.NewRecorder()
	svc.GetRatings(rrR2, reqR2)

	// Third GetRatings call must return 429 Too Many Requests
	reqR3 := httptest.NewRequest(http.MethodGet, "/users/ratings?user_id=target-123", nil)
	reqR3.Header.Set("Authorization", "Bearer "+ownerToken)
	reqR3.RemoteAddr = "192.168.1.100:12345"
	rrR3 := httptest.NewRecorder()
	svc.GetRatings(rrR3, reqR3)
	if rrR3.Code != http.StatusTooManyRequests {
		t.Fatalf("Expected GetRatings to be rate-limited (HTTP 429), got %d", rrR3.Code)
	}

	// Immediately call GetOwnerJobs with the same user token — must NOT be rate limited!
	reqJ := httptest.NewRequest(http.MethodGet, "/users/jobs/owner", nil)
	reqJ.Header.Set("Authorization", "Bearer "+ownerToken)
	rrJ := httptest.NewRecorder()
	svc.GetOwnerJobs(rrJ, reqJ)

	if rrJ.Code == http.StatusTooManyRequests {
		t.Fatalf("GetOwnerJobs was falsely rate-limited (HTTP 429) due to exhausted ratingsLimiter budget! Shared-bucket bug persists!")
	}
}
