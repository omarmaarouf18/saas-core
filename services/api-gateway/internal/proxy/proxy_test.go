package proxy

import (
	"encoding/json"
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

	// 3. Create reverse proxy
	proxyHandler, err := New(route, gatewaySecret, http.DefaultTransport)
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

	// 5. Test Route matching & Security Header Stripping/Injection
	// A request with client-spoofed X-Internal-Token and X-Forwarded-For
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

	// 6. Test Unknown Route returns 404
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
