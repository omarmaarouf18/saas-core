package handlers

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/project/auth-service/internal/config"
	"github.com/project/auth-service/internal/models"
	"github.com/project/auth-service/internal/otpcrypto"
	"github.com/project/auth-service/internal/storage"
	"github.com/project/auth-service/internal/store"
	"github.com/project/shared/infra/jwtutil"
	"github.com/redis/go-redis/v9"
)

// TestReviewerLogin_RateLimiting_3Attempts5MinLockout reproduces and tests
// the 3-attempt threshold -> 5-minute lockout behavior for reviewer authentication:
// 1. 3 failed attempts from an IP / token hash trigger a 5-minute lockout.
// 2. A 4th attempt with the CORRECT token during lockout is rejected with HTTP 429.
// 3. Fast-forwarding past 5 minutes clears the lockout and permits login.
// 4. A successful login before 3 failures resets the attempt counter.
func TestReviewerLogin_RateLimiting_3Attempts5MinLockout(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	jwtutil.Init("z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")

	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	dbName := fmt.Sprintf("saas_auth_rev_rl_test_%d", time.Now().UnixNano())
	cipher, err := otpcrypto.NewCipher("", "local")
	if err != nil {
		t.Fatalf("failed to create cipher: %v", err)
	}

	s, err := store.NewMongoDB(ctx, mongoURI, dbName, cipher)
	if err != nil {
		t.Skipf("Skipping reviewer rate limit integration tests: MongoDB not available at %s (%v)", mongoURI, err)
		return
	}
	defer func() {
		_ = s.DropDatabase(context.Background())
	}()

	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	cfg := &config.Config{
		AppEnv:                "local",
		GatewaySecret:         "mock-gateway-secret",
		InternalServiceToken:  "mock-internal-token",
		JWTSecret:             "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2",
		DocumentSigningSecret: "doc-signing-secret-key-32bytes-long-test",
	}

	tempDir := t.TempDir()
	storeLoc, _ := storage.NewLocalStorage(tempDir, "/api/v1", cfg.DocumentSigningSecret, "", "test")
	a := NewAuth(s, &mockOTPDispatcher{}, cfg, rdb, storeLoc)

	validToken := "valid-reviewer-token-secret-123456789"
	rev := &models.Reviewer{
		ID:    "rev-rl-1",
		Name:  "Rate Limit Test Reviewer",
		Token: validToken,
	}
	if err := s.AddReviewer(ctx, rev); err != nil {
		t.Fatalf("AddReviewer failed: %v", err)
	}

	t.Run("LockoutEngagedAfter3Failures_4thAttemptRejected429", func(t *testing.T) {
		clientIP := "198.51.100.10:45678"

		// 1st failed attempt
		req1 := httptest.NewRequest(http.MethodGet, "/auth/reviewer/verify", nil)
		req1.RemoteAddr = clientIP
		req1.Header.Set("X-Internal-Token", a.internalServiceToken)
		req1.Header.Set("X-Reviewer-Token", "wrong-token-attempt-1")
		rec1 := httptest.NewRecorder()
		a.VerifyReviewer(rec1, req1)
		if rec1.Code != http.StatusUnauthorized {
			t.Errorf("attempt 1: expected 401, got %d (body: %s)", rec1.Code, rec1.Body.String())
		}

		// 2nd failed attempt
		req2 := httptest.NewRequest(http.MethodGet, "/auth/reviewer/verify", nil)
		req2.RemoteAddr = clientIP
		req2.Header.Set("X-Internal-Token", a.internalServiceToken)
		req2.Header.Set("X-Reviewer-Token", "wrong-token-attempt-2")
		rec2 := httptest.NewRecorder()
		a.VerifyReviewer(rec2, req2)
		if rec2.Code != http.StatusUnauthorized {
			t.Errorf("attempt 2: expected 401, got %d (body: %s)", rec2.Code, rec2.Body.String())
		}

		// 3rd failed attempt -> triggers 5-minute lockout
		req3 := httptest.NewRequest(http.MethodGet, "/auth/reviewer/verify", nil)
		req3.RemoteAddr = clientIP
		req3.Header.Set("X-Internal-Token", a.internalServiceToken)
		req3.Header.Set("X-Reviewer-Token", "wrong-token-attempt-3")
		rec3 := httptest.NewRecorder()
		a.VerifyReviewer(rec3, req3)
		if rec3.Code != http.StatusTooManyRequests {
			t.Errorf("attempt 3: expected 429 Too Many Requests, got %d (body: %s)", rec3.Code, rec3.Body.String())
		}

		// 4th attempt: even with VALID token, must be blocked with 429
		req4 := httptest.NewRequest(http.MethodGet, "/auth/reviewer/verify", nil)
		req4.RemoteAddr = clientIP
		req4.Header.Set("X-Internal-Token", a.internalServiceToken)
		req4.Header.Set("X-Reviewer-Token", validToken)
		rec4 := httptest.NewRecorder()
		a.VerifyReviewer(rec4, req4)
		if rec4.Code != http.StatusTooManyRequests {
			t.Errorf("attempt 4 (valid token during lockout): expected 429, got %d (body: %s)", rec4.Code, rec4.Body.String())
		}

		// Verify other reviewer endpoints (e.g. GET /auth/kyb-kye/pending) also return 429
		reqQueue := httptest.NewRequest(http.MethodGet, "/auth/kyb-kye/pending", nil)
		reqQueue.RemoteAddr = clientIP
		reqQueue.Header.Set("X-Internal-Token", a.internalServiceToken)
		reqQueue.Header.Set("X-Reviewer-Token", validToken)
		recQueue := httptest.NewRecorder()
		a.GetPendingKYBKYESubmissions(recQueue, reqQueue)
		if recQueue.Code != http.StatusTooManyRequests {
			t.Errorf("queue during lockout: expected 429, got %d (body: %s)", recQueue.Code, recQueue.Body.String())
		}

		// Fast-forward miniredis clock past 5 minutes (301 seconds)
		mr.FastForward(301 * time.Second)

		// 5th attempt after lockout expiry: valid token must now succeed (HTTP 200)
		req5 := httptest.NewRequest(http.MethodGet, "/auth/reviewer/verify", nil)
		req5.RemoteAddr = clientIP
		req5.Header.Set("X-Internal-Token", a.internalServiceToken)
		req5.Header.Set("X-Reviewer-Token", validToken)
		rec5 := httptest.NewRecorder()
		a.VerifyReviewer(rec5, req5)
		if rec5.Code != http.StatusOK {
			t.Errorf("attempt 5 (after lockout expiry): expected 200 OK, got %d (body: %s)", rec5.Code, rec5.Body.String())
		}
	})

	t.Run("SuccessResetsCounterBeforeLockout", func(t *testing.T) {
		clientIP := "198.51.100.20:54321"

		// 2 failed attempts
		for i := 1; i <= 2; i++ {
			req := httptest.NewRequest(http.MethodGet, "/auth/reviewer/verify", nil)
			req.RemoteAddr = clientIP
			req.Header.Set("X-Internal-Token", a.internalServiceToken)
			req.Header.Set("X-Reviewer-Token", fmt.Sprintf("bad-attempt-%d", i))
			rec := httptest.NewRecorder()
			a.VerifyReviewer(rec, req)
			if rec.Code != http.StatusUnauthorized {
				t.Fatalf("expected 401 on failure %d, got %d", i, rec.Code)
			}
		}

		// 1 successful login resets the failure counter
		reqSuccess := httptest.NewRequest(http.MethodGet, "/auth/reviewer/verify", nil)
		reqSuccess.RemoteAddr = clientIP
		reqSuccess.Header.Set("X-Internal-Token", a.internalServiceToken)
		reqSuccess.Header.Set("X-Reviewer-Token", validToken)
		recSuccess := httptest.NewRecorder()
		a.VerifyReviewer(recSuccess, reqSuccess)
		if recSuccess.Code != http.StatusOK {
			t.Fatalf("expected 200 on success, got %d", recSuccess.Code)
		}

		// Next 2 failed attempts must NOT trigger lockout because counter was reset
		for i := 1; i <= 2; i++ {
			req := httptest.NewRequest(http.MethodGet, "/auth/reviewer/verify", nil)
			req.RemoteAddr = clientIP
			req.Header.Set("X-Internal-Token", a.internalServiceToken)
			req.Header.Set("X-Reviewer-Token", fmt.Sprintf("bad-post-reset-%d", i))
			rec := httptest.NewRecorder()
			a.VerifyReviewer(rec, req)
			if rec.Code != http.StatusUnauthorized {
				t.Fatalf("expected 401 on failure %d after reset, got %d (body: %s)", i, rec.Code, rec.Body.String())
			}
		}
	})
}
