package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/project/shared/infra/ratelimit"
	"github.com/redis/go-redis/v9"
)

func TestLoggingMiddleware(t *testing.T) {
	middleware := Logging("http://localhost:3000")

	// 1. OPTIONS preflight request
	nextHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	handler := middleware(nextHandler)

	req := httptest.NewRequest("OPTIONS", "/api/v1/auth/login", nil)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Errorf("Expected 200 OK for OPTIONS preflight, got %d", rec.Code)
	}
	if rec.Header().Get("Access-Control-Allow-Origin") != "http://localhost:3000" {
		t.Errorf("Expected Access-Control-Allow-Origin header set")
	}

	// 2. GET request status tracking & hijack fallback
	sr := &statusRecorder{
		ResponseWriter: rec,
		statusCode:     http.StatusOK,
	}
	sr.WriteHeader(http.StatusCreated)
	if sr.statusCode != http.StatusCreated {
		t.Errorf("Expected statusCode 201, got %d", sr.statusCode)
	}

	_, _, err := sr.Hijack()
	if err == nil {
		t.Errorf("Expected error hijacking unsupportive ResponseWriter, got nil")
	}
}

func TestRateLimitMiddleware(t *testing.T) {
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()

	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	rl := ratelimit.NewRateLimiter(rdb, 5, 1*time.Minute, "gw-test")
	gwLimiter := NewRateLimiter(rl)
	middleware := RateLimit(gwLimiter)

	nextHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	handler := middleware(nextHandler)

	// 1. IPs parsing check
	ips := []string{"192.168.1.1:8080", "[::1]:8080", "10.0.0.1"}
	for _, rawIP := range ips {
		req := httptest.NewRequest("GET", "/api/v1/users/list", nil)
		req.RemoteAddr = rawIP
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Errorf("Expected 200 OK for IP %s, got %d", rawIP, rec.Code)
		}
	}

	// 2. Rate limit exceedance -> 429 Too Many Requests
	testIP := "203.0.113.5:1234"
	for i := 0; i < 5; i++ {
		req := httptest.NewRequest("GET", "/api/v1/users/list", nil)
		req.RemoteAddr = testIP
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)
	}

	// 6th attempt -> limited
	req := httptest.NewRequest("GET", "/api/v1/users/list", nil)
	req.RemoteAddr = testIP
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	if rec.Code != http.StatusTooManyRequests {
		t.Errorf("Expected 429 Too Many Requests after 5 attempts, got %d", rec.Code)
	}
}
