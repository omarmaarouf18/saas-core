package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/project/notification-service/internal/config"
	"github.com/project/notification-service/internal/hub"
	"github.com/project/shared/infra/jwtutil"
	"github.com/redis/go-redis/v9"
)

func TestNotificationHandlersAuth(t *testing.T) {
	sseHub := hub.NewSSEHub()
	internalToken := "secret-internal-token"
	cfg := &config.Config{
		AuthServiceURL:       "http://localhost:3002",
		AllowedOrigin:        "http://localhost:3000",
		InternalServiceToken: internalToken,
	}
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	n := NewNotification(sseHub, cfg, rdb)

	t.Run("Send auth missing", func(t *testing.T) {
		reqBody := map[string]any{
			"type":      "popup",
			"tenant_id": "tenant-1",
			"title":     "Test",
			"body":      "Hello",
		}
		body, _ := json.Marshal(reqBody)
		req := httptest.NewRequest("POST", "/notifications/send", bytes.NewReader(body))
		rec := httptest.NewRecorder()

		n.Send(rec, req)

		if rec.Code != http.StatusUnauthorized {
			t.Errorf("Expected 401 Unauthorized, got %d. Body: %s", rec.Code, rec.Body.String())
		}
		if !strings.Contains(rec.Body.String(), "internal token required") {
			t.Errorf("Expected internal token error, got: %s", rec.Body.String())
		}
	})

	t.Run("Send auth invalid", func(t *testing.T) {
		reqBody := map[string]any{
			"type":      "popup",
			"tenant_id": "tenant-1",
			"title":     "Test",
			"body":      "Hello",
		}
		body, _ := json.Marshal(reqBody)
		req := httptest.NewRequest("POST", "/notifications/send", bytes.NewReader(body))
		req.Header.Set("X-Internal-Token", "wrong-token")
		rec := httptest.NewRecorder()

		n.Send(rec, req)

		if rec.Code != http.StatusUnauthorized {
			t.Errorf("Expected 401 Unauthorized, got %d. Body: %s", rec.Code, rec.Body.String())
		}
	})

	t.Run("Send auth valid", func(t *testing.T) {
		reqBody := map[string]any{
			"type":      "popup",
			"tenant_id": "tenant-1",
			"title":     "Test",
			"body":      "Hello",
		}
		body, _ := json.Marshal(reqBody)
		req := httptest.NewRequest("POST", "/notifications/send", bytes.NewReader(body))
		req.Header.Set("X-Internal-Token", internalToken)
		rec := httptest.NewRecorder()

		n.Send(rec, req)

		if rec.Code != http.StatusOK {
			t.Errorf("Expected 200 OK, got %d. Body: %s", rec.Code, rec.Body.String())
		}
	})

	t.Run("BroadcastJobAlert auth missing", func(t *testing.T) {
		reqBody := map[string]any{
			"tenant_id":    "tenant-1",
			"job_id":       "job-1",
			"service_name": "Cleaning",
			"description":  "Clean the house",
		}
		body, _ := json.Marshal(reqBody)
		req := httptest.NewRequest("POST", "/notifications/broadcast/job-alert", bytes.NewReader(body))
		rec := httptest.NewRecorder()

		n.BroadcastJobAlert(rec, req)

		if rec.Code != http.StatusUnauthorized {
			t.Errorf("Expected 401 Unauthorized, got %d. Body: %s", rec.Code, rec.Body.String())
		}
	})

	t.Run("BroadcastJobAlert auth valid", func(t *testing.T) {
		reqBody := map[string]any{
			"tenant_id":    "tenant-1",
			"job_id":       "job-1",
			"service_name": "Cleaning",
			"description":  "Clean the house",
		}
		body, _ := json.Marshal(reqBody)
		req := httptest.NewRequest("POST", "/notifications/broadcast/job-alert", bytes.NewReader(body))
		req.Header.Set("X-Internal-Token", internalToken)
		rec := httptest.NewRecorder()

		n.BroadcastJobAlert(rec, req)

		if rec.Code != http.StatusOK {
			t.Errorf("Expected 200 OK, got %d. Body: %s", rec.Code, rec.Body.String())
		}
	})
}

func TestStreamAndVerifyAndResolve(t *testing.T) {
	jwtutil.Init("z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")

	// Spin up a mock auth service
	mockAuth := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		id := r.URL.Query().Get("id")
		if id == "unauthorized-user" {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]any{
			"id":        id,
			"role":      "owner",
			"is_active": true,
			"tenant_id": "tenant-1",
		})
	}))
	defer mockAuth.Close()

	sseHub := hub.NewSSEHub()
	cfg := &config.Config{
		AuthServiceURL:       mockAuth.URL,
		AllowedOrigin:        "http://localhost:3000",
		InternalServiceToken: "secret-internal-token",
	}

	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	n := NewNotification(sseHub, cfg, rdb)

	// A. POST on /stream -> 405 Method Not Allowed
	req := httptest.NewRequest("POST", "/notifications/stream", nil)
	rec := httptest.NewRecorder()
	n.Stream(rec, req)
	if rec.Code != http.StatusMethodNotAllowed {
		t.Errorf("Expected 405 Method Not Allowed, got %d", rec.Code)
	}
	if rec.Header().Get("Access-Control-Allow-Origin") != "http://localhost:3000" {
		t.Errorf("Expected Access-Control-Allow-Origin header set on error response")
	}

	// B. GET on /stream without token -> 400 Bad Request
	req = httptest.NewRequest("GET", "/notifications/stream", nil)
	rec = httptest.NewRecorder()
	n.Stream(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("Expected 400 Bad Request, got %d", rec.Code)
	}
	if rec.Header().Get("Access-Control-Allow-Origin") != "http://localhost:3000" {
		t.Errorf("Expected Access-Control-Allow-Origin header set on error response")
	}

	// C. GET on /stream with invalid JWT token -> 403 Forbidden
	req = httptest.NewRequest("GET", "/notifications/stream?token=invalid-jwt", nil)
	rec = httptest.NewRecorder()
	n.Stream(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Errorf("Expected 403 Forbidden, got %d", rec.Code)
	}

	// D. GET on /stream with valid JWT token but unauthorized user -> 403 Forbidden
	badToken, _ := jwtutil.GenerateToken("unauthorized-user", "owner", "tenant-1", "bad@example.com")
	req = httptest.NewRequest("GET", "/notifications/stream?token="+badToken, nil)
	rec = httptest.NewRecorder()
	n.Stream(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Errorf("Expected 403 Forbidden, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// E. GET on /stream with valid JWT token -> 200 OK & initiates SSE
	goodToken, _ := jwtutil.GenerateToken("user-1", "owner", "tenant-1", "good@example.com")
	ctx, cancel := context.WithCancel(context.Background())
	req = httptest.NewRequest("GET", "/notifications/stream?token="+goodToken, nil)
	req = req.WithContext(ctx)
	rec = httptest.NewRecorder()

	// Run in a goroutine so we can disconnect it
	go func() {
		// Wait a moment and then cancel connection context
		time.Sleep(50 * time.Millisecond)
		cancel()
	}()

	n.Stream(rec, req)
	if rec.Code != http.StatusOK {
		t.Errorf("Expected 200 OK for successful SSE, got %d", rec.Code)
	}
	if !strings.Contains(rec.Body.String(), "event: connected") {
		t.Errorf("Expected connected event, got: %s", rec.Body.String())
	}
}
