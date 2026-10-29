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

		// Verify other reviewer endpoints (e.g. GET /auth/kyb-kye/pending, SuspendAccount, ReactivateAccount) also return 429
		reqQueue := httptest.NewRequest(http.MethodGet, "/auth/kyb-kye/pending", nil)
		reqQueue.RemoteAddr = clientIP
		reqQueue.Header.Set("X-Internal-Token", a.internalServiceToken)
		reqQueue.Header.Set("X-Reviewer-Token", validToken)
		recQueue := httptest.NewRecorder()
		a.GetPendingKYBKYESubmissions(recQueue, reqQueue)
		if recQueue.Code != http.StatusTooManyRequests {
			t.Errorf("queue during lockout: expected 429, got %d (body: %s)", recQueue.Code, recQueue.Body.String())
		}

		reqSuspend := httptest.NewRequest(http.MethodPost, "/auth/accounts/suspend", nil)
		reqSuspend.RemoteAddr = clientIP
		reqSuspend.Header.Set("X-Internal-Token", a.internalServiceToken)
		reqSuspend.Header.Set("X-Reviewer-Token", validToken)
		recSuspend := httptest.NewRecorder()
		a.SuspendAccount(recSuspend, reqSuspend)
		if recSuspend.Code != http.StatusTooManyRequests {
			t.Errorf("suspend during lockout: expected 429, got %d (body: %s)", recSuspend.Code, recSuspend.Body.String())
		}

		reqReactivate := httptest.NewRequest(http.MethodPost, "/auth/accounts/reactivate", nil)
		reqReactivate.RemoteAddr = clientIP
		reqReactivate.Header.Set("X-Internal-Token", a.internalServiceToken)
		reqReactivate.Header.Set("X-Reviewer-Token", validToken)
		recReactivate := httptest.NewRecorder()
		a.ReactivateAccount(recReactivate, reqReactivate)
		if recReactivate.Code != http.StatusTooManyRequests {
			t.Errorf("reactivate during lockout: expected 429, got %d (body: %s)", recReactivate.Code, recReactivate.Body.String())
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

func TestReviewerRateLimiting_ForwardedClientIP_TokenPrefix_GlobalCeiling(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	jwtutil.Init("z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")

	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	dbName := fmt.Sprintf("saas_auth_rev_rl2_test_%d", time.Now().UnixNano())
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

	validToken := "valid-reviewer-token-secret-987654321"
	rev := &models.Reviewer{
		ID:    "rev-rl-2",
		Name:  "Forwarded Rate Limit Reviewer",
		Token: validToken,
	}
	if err := s.AddReviewer(ctx, rev); err != nil {
		t.Fatalf("AddReviewer failed: %v", err)
	}

	consoleIP := "172.20.0.9:50000"

	t.Run("ForwardedClientIP_IsolatesReviewersBehindSingleConsole", func(t *testing.T) {
		clientIPA := "203.0.113.10"
		clientIPB := "203.0.113.20"

		// Reviewer A fails 3 times with bad tokens from console
		for i := 1; i <= 3; i++ {
			req := httptest.NewRequest(http.MethodGet, "/auth/reviewer/verify", nil)
			req.RemoteAddr = consoleIP
			req.Header.Set("X-Internal-Token", a.internalServiceToken)
			req.Header.Set(ConsoleClientIPHeader, clientIPA)
			req.Header.Set("X-Reviewer-Token", fmt.Sprintf("bad-token-a-%d", i))
			rec := httptest.NewRecorder()
			a.VerifyReviewer(rec, req)
			if i < 3 && rec.Code != http.StatusUnauthorized {
				t.Fatalf("attempt %d: expected 401, got %d", i, rec.Code)
			}
			if i == 3 && rec.Code != http.StatusTooManyRequests {
				t.Fatalf("attempt 3: expected 429, got %d", rec.Code)
			}
		}

		// Reviewer A's 4th attempt from same forwarded IP is rejected with 429
		reqA4 := httptest.NewRequest(http.MethodGet, "/auth/reviewer/verify", nil)
		reqA4.RemoteAddr = consoleIP
		reqA4.Header.Set("X-Internal-Token", a.internalServiceToken)
		reqA4.Header.Set(ConsoleClientIPHeader, clientIPA)
		reqA4.Header.Set("X-Reviewer-Token", validToken)
		recA4 := httptest.NewRecorder()
		a.VerifyReviewer(recA4, reqA4)
		if recA4.Code != http.StatusTooManyRequests {
			t.Fatalf("Reviewer A: expected 429 during lockout, got %d", recA4.Code)
		}

		// Reviewer B behind the EXACT SAME console (consoleIP) with distinct forwarded IP succeeds!
		reqB := httptest.NewRequest(http.MethodGet, "/auth/reviewer/verify", nil)
		reqB.RemoteAddr = consoleIP
		reqB.Header.Set("X-Internal-Token", a.internalServiceToken)
		reqB.Header.Set(ConsoleClientIPHeader, clientIPB)
		reqB.Header.Set("X-Reviewer-Token", validToken)
		recB := httptest.NewRecorder()
		a.VerifyReviewer(recB, reqB)
		if recB.Code != http.StatusOK {
			t.Fatalf("Reviewer B: expected 200 OK behind same console, got %d (body: %s)", recB.Code, recB.Body.String())
		}
	})

	t.Run("RotatingForwardedFor_DoesNotResetPerIPLimit", func(t *testing.T) {
		// A caller holding the internal token but rotating X-Forwarded-For
		// (what a client could do through the gateway's /admin/version
		// handler before ADMIN-API-FIX) stays on one per-IP key: RemoteAddr.
		rotatorIP := "172.20.0.50:41000"
		for i := 1; i <= 3; i++ {
			req := httptest.NewRequest(http.MethodGet, "/auth/reviewer/verify", nil)
			req.RemoteAddr = rotatorIP
			req.Header.Set("X-Internal-Token", a.internalServiceToken)
			req.Header.Set("X-Forwarded-For", fmt.Sprintf("192.0.2.%d", 100+i))
			req.Header.Set("X-Reviewer-Token", fmt.Sprintf("rotating-bad-token-%d-%d", time.Now().UnixNano(), i))
			rec := httptest.NewRecorder()
			a.VerifyReviewer(rec, req)
			if i < 3 && rec.Code != http.StatusUnauthorized {
				t.Fatalf("attempt %d: expected 401, got %d", i, rec.Code)
			}
			if i == 3 && rec.Code != http.StatusTooManyRequests {
				t.Fatalf("attempt 3: expected 429 (rotating XFF must not reset the limit), got %d", rec.Code)
			}
		}
		req := httptest.NewRequest(http.MethodGet, "/auth/reviewer/verify", nil)
		req.RemoteAddr = rotatorIP
		req.Header.Set("X-Internal-Token", a.internalServiceToken)
		req.Header.Set("X-Forwarded-For", "192.0.2.250")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		a.VerifyReviewer(rec, req)
		if rec.Code != http.StatusTooManyRequests {
			t.Fatalf("fresh XFF with valid token during lockout: expected 429, got %d", rec.Code)
		}
	})

	t.Run("TokenHashPrefix_LimitsAttemptsTargetingSameCredentialAcrossIPs", func(t *testing.T) {
		targetTokenPrefix := "target-token-under-attack"

		// Attacker rotates forwarded IP across 3 attempts targeting targetTokenPrefix
		for i := 1; i <= 3; i++ {
			req := httptest.NewRequest(http.MethodGet, "/auth/reviewer/verify", nil)
			req.RemoteAddr = consoleIP
			req.Header.Set("X-Internal-Token", a.internalServiceToken)
			req.Header.Set(ConsoleClientIPHeader, fmt.Sprintf("198.51.100.%d", 10+i))
			req.Header.Set("X-Reviewer-Token", targetTokenPrefix)
			rec := httptest.NewRecorder()
			a.VerifyReviewer(rec, req)
			if i < 3 && rec.Code != http.StatusUnauthorized {
				t.Fatalf("attempt %d: expected 401, got %d", i, rec.Code)
			}
			if i == 3 && rec.Code != http.StatusTooManyRequests {
				t.Fatalf("attempt 3: expected 429 for token hash prefix, got %d", rec.Code)
			}
		}

		// 4th attempt from a fresh IP with the same token prefix is blocked with 429
		req4 := httptest.NewRequest(http.MethodGet, "/auth/reviewer/verify", nil)
		req4.RemoteAddr = consoleIP
		req4.Header.Set("X-Internal-Token", a.internalServiceToken)
		req4.Header.Set(ConsoleClientIPHeader, "198.51.100.99")
		req4.Header.Set("X-Reviewer-Token", targetTokenPrefix)
		rec4 := httptest.NewRecorder()
		a.VerifyReviewer(rec4, req4)
		if rec4.Code != http.StatusTooManyRequests {
			t.Fatalf("expected 429 for token hash prefix from fresh IP, got %d", rec4.Code)
		}
	})

	t.Run("GlobalCeiling_LocksOutReviewerAuthWhenCeilingExceeded", func(t *testing.T) {
		a.limiter.ResetReviewerGlobal()
		// Set global ceiling threshold to 4 failures
		a.limiter.SetReviewerGlobalCeiling(4, 5*time.Minute)

		// 4 failed attempts with unique IPs and unique tokens
		for i := 1; i <= 4; i++ {
			req := httptest.NewRequest(http.MethodGet, "/auth/reviewer/verify", nil)
			req.RemoteAddr = consoleIP
			req.Header.Set("X-Internal-Token", a.internalServiceToken)
			req.Header.Set(ConsoleClientIPHeader, fmt.Sprintf("10.0.1.%d", i))
			req.Header.Set("X-Reviewer-Token", fmt.Sprintf("unique-token-%d-%d", time.Now().UnixNano(), i))
			rec := httptest.NewRecorder()
			a.VerifyReviewer(rec, req)
			if i < 4 && rec.Code != http.StatusUnauthorized {
				t.Fatalf("attempt %d: expected 401, got %d", i, rec.Code)
			}
			if i == 4 && rec.Code != http.StatusTooManyRequests {
				t.Fatalf("attempt 4 (ceiling hit): expected 429, got %d", rec.Code)
			}
		}

		// 5th attempt from any IP even with valid token is rejected with 429 due to global ceiling
		req5 := httptest.NewRequest(http.MethodGet, "/auth/reviewer/verify", nil)
		req5.RemoteAddr = consoleIP
		req5.Header.Set("X-Internal-Token", a.internalServiceToken)
		req5.Header.Set(ConsoleClientIPHeader, "10.0.2.1")
		req5.Header.Set("X-Reviewer-Token", validToken)
		rec5 := httptest.NewRecorder()
		a.VerifyReviewer(rec5, req5)
		if rec5.Code != http.StatusTooManyRequests {
			t.Fatalf("expected 429 under global ceiling lockout, got %d", rec5.Code)
		}
	})

	t.Run("UntrustedCaller_CannotSpoofForwardedClientIPWithoutInternalToken", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/auth/reviewer/verify", nil)
		req.RemoteAddr = "192.0.2.1:12345"
		req.Header.Set("X-Internal-Token", "invalid-or-missing-token")
		req.Header.Set("X-Forwarded-For", "10.0.0.1")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		a.VerifyReviewer(rec, req)
		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("expected 401 Unauthorized for caller without internal token, got %d", rec.Code)
		}
	})
}
