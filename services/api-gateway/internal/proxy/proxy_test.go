package proxy

import (
	"context"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/project/gateway/internal/config"
	"github.com/project/gateway/internal/middleware"
	"github.com/project/shared/infra/ratelimit"
	"github.com/redis/go-redis/v9"
)

type backendRequestInfo struct {
	Path          string              `json:"path"`
	Headers       map[string][]string `json:"headers"`
	InternalToken string              `json:"internal_token"`
	GatewaySecret string              `json:"gateway_secret"`
	ForwardedFor  string              `json:"forwarded_for"`
}

func TestGatewayProxyAndSecurity(t *testing.T) {
	gatewaySecret := "my-secure-gateway-secret"

	// 1. Spin up a mock backend service
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)

		info := backendRequestInfo{
			Path:          r.URL.Path,
			Headers:       r.Header,
			InternalToken: r.Header.Get("X-Internal-Token"),
			GatewaySecret: r.Header.Get("X-Gateway-Secret"),
			ForwardedFor:  r.Header.Get("X-Forwarded-For"),
		}
		_ = json.NewEncoder(w).Encode(info)
	}))
	defer backend.Close()

	// 2. Define route configuration
	route := config.ServiceRoute{
		Prefix:      "/api/v1/auth/",
		Target:      backend.URL,
		StripPrefix: "/api/v1",
	}

	trustedProxies := []string{"127.0.0.1", "::1"}

	// 3. Create reverse proxy
	proxyHandler, err := New(route, gatewaySecret, trustedProxies, http.DefaultTransport)
	if err != nil {
		t.Fatalf("failed to create proxy: %v", err)
	}

	// 4. Register routes on ServeMux
	mux := http.NewServeMux()
	mux.Handle(route.Prefix, proxyHandler)

	// Register catch-all default route returning 404
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("gateway root"))
	})

	// 5. Test Untrusted Direct Connection (Spoofed X-Forwarded-For)
	// A request with client-spoofed X-Internal-Token and X-Forwarded-For from untrusted RemoteAddr
	req := httptest.NewRequest("POST", "/api/v1/auth/signup", nil)
	req.Header.Set("X-Internal-Token", "spoofed-internal-token")
	req.Header.Set("X-Forwarded-For", "1.1.1.1")
	req.RemoteAddr = "2.2.2.2:12345"

	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", rec.Code)
	}

	var resInfo backendRequestInfo
	if err := json.Unmarshal(rec.Body.Bytes(), &resInfo); err != nil {
		t.Fatalf("failed to parse backend response: %v", err)
	}

	// Verify prefix stripping: /api/v1/auth/signup -> /auth/signup
	if resInfo.Path != "/auth/signup" {
		t.Errorf("expected path /auth/signup at backend, got %s", resInfo.Path)
	}

	// Verify X-Internal-Token was stripped
	if resInfo.InternalToken != "" {
		t.Errorf("expected X-Internal-Token to be stripped, but got %q", resInfo.InternalToken)
	}

	// Verify X-Gateway-Secret was correctly injected
	if resInfo.GatewaySecret != gatewaySecret {
		t.Errorf("expected X-Gateway-Secret %q, got %q", gatewaySecret, resInfo.GatewaySecret)
	}

	// Verify X-Forwarded-For was overwritten to match RemoteAddr and not the client spoofed value
	if !strings.HasPrefix(resInfo.ForwardedFor, "2.2.2.2:12345") {
		t.Errorf("expected X-Forwarded-For to start with '2.2.2.2:12345', got %q", resInfo.ForwardedFor)
	}

	// 6. Test Trusted Proxy Connection with legitimate X-Forwarded-For header
	reqTrusted := httptest.NewRequest("POST", "/api/v1/auth/signup", nil)
	reqTrusted.Header.Set("X-Forwarded-For", "203.0.113.195")
	reqTrusted.RemoteAddr = "127.0.0.1:54321"

	recTrusted := httptest.NewRecorder()
	mux.ServeHTTP(recTrusted, reqTrusted)

	if recTrusted.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", recTrusted.Code)
	}

	var resTrustedInfo backendRequestInfo
	if err := json.Unmarshal(recTrusted.Body.Bytes(), &resTrustedInfo); err != nil {
		t.Fatalf("failed to parse backend response: %v", err)
	}

	if resTrustedInfo.ForwardedFor != "203.0.113.195, 127.0.0.1" {
		t.Errorf("expected X-Forwarded-For to be '203.0.113.195, 127.0.0.1', got %q", resTrustedInfo.ForwardedFor)
	}

	// 7. Test Trusted Proxy Connection with NO X-Forwarded-For header (fallback)
	reqTrustedNoXFF := httptest.NewRequest("POST", "/api/v1/auth/signup", nil)
	reqTrustedNoXFF.RemoteAddr = "127.0.0.1:54321"

	recTrustedNoXFF := httptest.NewRecorder()
	mux.ServeHTTP(recTrustedNoXFF, reqTrustedNoXFF)

	if recTrustedNoXFF.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", recTrustedNoXFF.Code)
	}

	var resTrustedNoXFFInfo backendRequestInfo
	if err := json.Unmarshal(recTrustedNoXFF.Body.Bytes(), &resTrustedNoXFFInfo); err != nil {
		t.Fatalf("failed to parse backend response: %v", err)
	}

	if !strings.HasPrefix(resTrustedNoXFFInfo.ForwardedFor, "127.0.0.1:54321") {
		t.Errorf("expected X-Forwarded-For to start with '127.0.0.1:54321', got %q", resTrustedNoXFFInfo.ForwardedFor)
	}

	// 8. Test Unknown Route returns 404
	req404 := httptest.NewRequest("GET", "/api/v1/unknown-service/foo", nil)
	rec404 := httptest.NewRecorder()
	mux.ServeHTTP(rec404, req404)

	if rec404.Code != http.StatusNotFound {
		t.Errorf("expected 404 for unknown route, got %d", rec404.Code)
	}
}

func TestGatewayRateLimiting(t *testing.T) {
	// 1. Setup miniredis and redis client
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()

	redisClient := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer redisClient.Close()

	// 2. Setup gateway rate limiter (limit = 3 requests per minute for this test)
	rl := ratelimit.NewRateLimiter(redisClient, 3, 1*time.Minute, "gateway")
	limiter := middleware.NewRateLimiter(rl)

	mux := http.NewServeMux()
	mux.HandleFunc("/api/v1/test", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})

	// Wrap handler in rate limit middleware
	handler := middleware.RateLimit(limiter)(mux)

	// 3. Perform requests
	clientIP := "192.168.1.50:54321"

	// Request 1, 2, 3 should succeed
	for i := 1; i <= 3; i++ {
		req := httptest.NewRequest("GET", "/api/v1/test", nil)
		req.RemoteAddr = clientIP
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)

		if rec.Code != http.StatusOK {
			t.Errorf("request %d: expected 200 OK, got %d", i, rec.Code)
		}
	}

	// Request 4 should be rate limited (429)
	req := httptest.NewRequest("GET", "/api/v1/test", nil)
	req.RemoteAddr = clientIP
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusTooManyRequests {
		t.Errorf("expected 429 Too Many Requests, got %d", rec.Code)
	}
}

func TestRouteSegregation(t *testing.T) {
	internalToken := "my-secret-internal-token"
	mux := http.NewServeMux()

	// Public health check route
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"status":"ok"}`))
	})

	// Internal health check route
	mux.HandleFunc("/health/internal", func(w http.ResponseWriter, r *http.Request) {
		gotToken := r.Header.Get("X-Internal-Token")
		if gotToken != internalToken {
			w.WriteHeader(http.StatusForbidden)
			_, _ = w.Write([]byte(`{"error":"access denied"}`))
			return
		}
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"status":"ok"}`))
	})

	// 1. Request to public route works without token
	reqPublic := httptest.NewRequest("GET", "/health", nil)
	recPublic := httptest.NewRecorder()
	mux.ServeHTTP(recPublic, reqPublic)
	if recPublic.Code != http.StatusOK {
		t.Errorf("Expected 200 OK for public route, got %d", recPublic.Code)
	}

	// 2. Request to internal route without token is rejected
	reqInternalNoToken := httptest.NewRequest("GET", "/health/internal", nil)
	recInternalNoToken := httptest.NewRecorder()
	mux.ServeHTTP(recInternalNoToken, reqInternalNoToken)
	if recInternalNoToken.Code != http.StatusForbidden {
		t.Errorf("Expected 403 Forbidden for internal route without token, got %d", recInternalNoToken.Code)
	}

	// 3. Request to internal route with correct token works
	reqInternalWithToken := httptest.NewRequest("GET", "/health/internal", nil)
	reqInternalWithToken.Header.Set("X-Internal-Token", internalToken)
	recInternalWithToken := httptest.NewRecorder()
	mux.ServeHTTP(recInternalWithToken, reqInternalWithToken)
	if recInternalWithToken.Code != http.StatusOK {
		t.Errorf("Expected 200 OK for internal route with token, got %d", recInternalWithToken.Code)
	}
}

func TestLimiterHardenAndFailClosed(t *testing.T) {
	t.Run("Harden against X-Forwarded-For spoofing", func(t *testing.T) {
		mr, err := miniredis.Run()
		if err != nil {
			t.Fatalf("failed to start miniredis: %v", err)
		}
		defer mr.Close()

		redisClient := redis.NewClient(&redis.Options{Addr: mr.Addr()})
		defer redisClient.Close()

		rl := ratelimit.NewRateLimiter(redisClient, 1, 1*time.Minute, "gateway")
		limiter := middleware.NewRateLimiter(rl)

		mux := http.NewServeMux()
		mux.HandleFunc("/test", func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusOK)
		})
		handler := middleware.RateLimit(limiter)(mux)

		// Send request with RemoteAddr and spoofed X-Forwarded-For
		req1 := httptest.NewRequest("GET", "/test", nil)
		req1.RemoteAddr = "203.0.113.195:1234"
		req1.Header.Set("X-Forwarded-For", "198.51.100.1") // spoof attempts
		rec1 := httptest.NewRecorder()
		handler.ServeHTTP(rec1, req1)
		if rec1.Code != http.StatusOK {
			t.Errorf("Expected 200 OK, got %d", rec1.Code)
		}

		// Verify that the rate limit key created in Redis uses the RemoteAddr IP
		keys, err := redisClient.Keys(context.Background(), "*").Result()
		if err != nil {
			t.Fatalf("failed to query keys: %v", err)
		}
		foundRemoteAddrKey := false
		for _, k := range keys {
			if strings.Contains(k, "203.0.113.195") {
				foundRemoteAddrKey = true
			}
			if strings.Contains(k, "198.51.100.1") {
				t.Errorf("Security Violation: Rate limit tracked spoofed X-Forwarded-For header!")
			}
		}
		if !foundRemoteAddrKey {
			t.Errorf("Expected rate limit key for 203.0.113.195 to be found, keys were: %v", keys)
		}
	})

	t.Run("Fail-closed when Redis is unreachable", func(t *testing.T) {
		// Use a closed Redis client to simulate unreachability
		mr, err := miniredis.Run()
		if err != nil {
			t.Fatalf("failed to start miniredis: %v", err)
		}
		addr := mr.Addr()
		mr.Close() // immediately close to make it unreachable

		redisClient := redis.NewClient(&redis.Options{Addr: addr})

		rl := ratelimit.NewRateLimiter(redisClient, 10, 1*time.Minute, "gateway")
		limiter := middleware.NewRateLimiter(rl)

		mux := http.NewServeMux()
		mux.HandleFunc("/test", func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusOK)
		})
		handler := middleware.RateLimit(limiter)(mux)

		req := httptest.NewRequest("GET", "/test", nil)
		req.RemoteAddr = "127.0.0.1:1234"
		rec := httptest.NewRecorder()

		handler.ServeHTTP(rec, req)

		// Should fail-closed and return 429 Too Many Requests
		if rec.Code != http.StatusTooManyRequests {
			t.Errorf("Expected fail-closed 429 Too Many Requests when Redis is down, got %d", rec.Code)
		}
	})
}

func TestLoggingExcludesSensitiveData(t *testing.T) {
	var logBuf strings.Builder
	log.SetOutput(&logBuf)
	defer log.SetOutput(nil)

	mux := http.NewServeMux()
	mux.HandleFunc("/test", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})

	handler := middleware.Logging("http://localhost:3000")(mux)

	body := strings.NewReader(`{"password":"my-super-secret-password-123"}`)
	req := httptest.NewRequest("POST", "/test?token=sensitive-query-token", body)
	req.Header.Set("Authorization", "Bearer sensitive-jwt-auth-token")
	rec := httptest.NewRecorder()

	handler.ServeHTTP(rec, req)

	logOutput := logBuf.String()

	if !strings.Contains(logOutput, "[TRAFFIC] POST /test") {
		t.Errorf("Expected log to contain request path, got: %q", logOutput)
	}

	if strings.Contains(logOutput, "my-super-secret-password-123") {
		t.Errorf("Security Leak: Password logged in gateway logs!")
	}
	if strings.Contains(logOutput, "sensitive-jwt-auth-token") {
		t.Errorf("Security Leak: Authorization token logged in gateway logs!")
	}
	if strings.Contains(logOutput, "sensitive-query-token") {
		t.Errorf("Security Leak: Query parameters logged in gateway logs!")
	}
}

func TestProxyOversizedAndMalformedBodyForwarded(t *testing.T) {
	var receivedBody string
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		bodyBytes, _ := io.ReadAll(r.Body)
		receivedBody = string(bodyBytes)
	}))
	defer backend.Close()

	route := config.ServiceRoute{
		Prefix:      "/test/",
		Target:      backend.URL,
		StripPrefix: "/test",
	}

	proxyHandler, err := New(route, "secret", []string{"127.0.0.1"}, http.DefaultTransport)
	if err != nil {
		t.Fatalf("failed to create proxy: %v", err)
	}

	largePayload := strings.Repeat("A", 5*1024*1024)
	req := httptest.NewRequest("POST", "/test/foo", strings.NewReader(largePayload))
	rec := httptest.NewRecorder()

	proxyHandler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Errorf("Expected 200 OK, got %d", rec.Code)
	}
	if len(receivedBody) != len(largePayload) {
		t.Errorf("Expected backend to receive entire 5MB body, got length %d", len(receivedBody))
	}

	malformedPayload := `{"invalid json`
	reqMalformed := httptest.NewRequest("POST", "/test/foo", strings.NewReader(malformedPayload))
	recMalformed := httptest.NewRecorder()

	proxyHandler.ServeHTTP(recMalformed, reqMalformed)

	if recMalformed.Code != http.StatusOK {
		t.Errorf("Expected 200 OK for forwarded malformed body, got %d", recMalformed.Code)
	}
	if receivedBody != malformedPayload {
		t.Errorf("Expected backend to receive malformed payload %q, got %q", malformedPayload, receivedBody)
	}
}
