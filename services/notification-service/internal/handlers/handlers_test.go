package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/golang-jwt/jwt/v5"
	"github.com/project/notification-service/internal/config"
	"github.com/project/notification-service/internal/hub"
	"github.com/project/shared/infra/jwtutil"
	"github.com/redis/go-redis/v9"
)

type safeRecorder struct {
	*httptest.ResponseRecorder
	mu  sync.Mutex
	buf bytes.Buffer
}

func newSafeRecorder() *safeRecorder {
	return &safeRecorder{
		ResponseRecorder: httptest.NewRecorder(),
	}
}

func (sr *safeRecorder) Write(p []byte) (int, error) {
	sr.mu.Lock()
	defer sr.mu.Unlock()
	sr.buf.Write(p)
	return sr.ResponseRecorder.Write(p)
}

func (sr *safeRecorder) BodyString() string {
	sr.mu.Lock()
	defer sr.mu.Unlock()
	return sr.buf.String()
}

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
		// Poll until client is registered in the hub, then cancel
		deadline := time.Now().Add(2 * time.Second)
		for sseHub.ClientCount() == 0 && time.Now().Before(deadline) {
			time.Sleep(2 * time.Millisecond)
		}
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

func TestStreamAuthScenarios(t *testing.T) {
	jwtutil.Init("z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")

	mockAuth := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]any{
			"id":        "user-123",
			"role":      "owner",
			"is_active": true,
			"tenant_id": "tenant-1",
		})
	}))
	defer mockAuth.Close()

	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()
	jwtutil.SetRedisClient(rdb)
	defer jwtutil.SetRedisClient(nil)

	sseHub := hub.NewSSEHub()
	cfg := &config.Config{
		AuthServiceURL:       mockAuth.URL,
		AllowedOrigin:        "http://localhost:3000",
		InternalServiceToken: "secret-internal-token",
	}
	n := NewNotification(sseHub, cfg, rdb)

	t.Run("Malformed token check", func(t *testing.T) {
		req := httptest.NewRequest("GET", "/notifications/stream?token=malformed-token-xyz", nil)
		rec := httptest.NewRecorder()
		n.Stream(rec, req)
		if rec.Code != http.StatusForbidden {
			t.Errorf("Expected 403 Forbidden for malformed token, got %d", rec.Code)
		}
		if !strings.Contains(rec.Body.String(), "invalid or inactive token") {
			t.Errorf("Expected invalid token error, got: %s", rec.Body.String())
		}
	})

	t.Run("Expired token check", func(t *testing.T) {
		expiredClaims := jwtutil.Claims{
			UserID:   "expired-user",
			Role:     "user",
			TenantID: "tenant-1",
			Email:    "expired@example.com",
			RegisteredClaims: jwt.RegisteredClaims{
				ExpiresAt: jwt.NewNumericDate(time.Now().Add(-1 * time.Hour)),
				IssuedAt:  jwt.NewNumericDate(time.Now().Add(-2 * time.Hour)),
				ID:        "expired-jti-456",
			},
		}
		tokenObj := jwt.NewWithClaims(jwt.SigningMethodHS256, expiredClaims)
		expiredToken, _ := tokenObj.SignedString([]byte("z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2"))

		req := httptest.NewRequest("GET", "/notifications/stream?token="+expiredToken, nil)
		rec := httptest.NewRecorder()
		n.Stream(rec, req)
		if rec.Code != http.StatusForbidden {
			t.Errorf("Expected 403 Forbidden for expired token, got %d", rec.Code)
		}
	})

	t.Run("Revoked token check", func(t *testing.T) {
		validToken, err := jwtutil.GenerateToken("revoked-user", "user", "tenant-1", "revoked@example.com")
		if err != nil {
			t.Fatalf("failed to generate token: %v", err)
		}
		err = jwtutil.RevokeToken(validToken)
		if err != nil {
			t.Fatalf("failed to revoke token: %v", err)
		}

		req := httptest.NewRequest("GET", "/notifications/stream?token="+validToken, nil)
		rec := httptest.NewRecorder()
		n.Stream(rec, req)
		if rec.Code != http.StatusForbidden {
			t.Errorf("Expected 403 Forbidden for revoked token, got %d", rec.Code)
		}
	})
}

func TestStreamTenantScopingAndIsolation(t *testing.T) {
	jwtutil.Init("z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")

	mockAuth := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		id := r.URL.Query().Get("id")
		tenant := "tenant-a"
		if id == "user-b" {
			tenant = "tenant-b"
		}
		json.NewEncoder(w).Encode(map[string]any{
			"id":        id,
			"role":      "owner",
			"is_active": true,
			"tenant_id": tenant,
		})
	}))
	defer mockAuth.Close()

	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	sseHub := hub.NewSSEHub()
	cfg := &config.Config{
		AuthServiceURL:       mockAuth.URL,
		AllowedOrigin:        "http://localhost:3000",
		InternalServiceToken: "secret-internal-token",
	}
	n := NewNotification(sseHub, cfg, rdb)

	tokenA, _ := jwtutil.GenerateToken("user-a", "owner", "tenant-a", "a@test.com")
	tokenB, _ := jwtutil.GenerateToken("user-b", "owner", "tenant-b", "b@test.com")

	ctxA, cancelA := context.WithCancel(context.Background())
	defer cancelA()
	reqA := httptest.NewRequest("GET", "/notifications/stream?token="+tokenA, nil)
	reqA = reqA.WithContext(ctxA)
	recA := newSafeRecorder()

	ctxB, cancelB := context.WithCancel(context.Background())
	defer cancelB()
	reqB := httptest.NewRequest("GET", "/notifications/stream?token="+tokenB, nil)
	reqB = reqB.WithContext(ctxB)
	recB := newSafeRecorder()

	var wg sync.WaitGroup
	wg.Add(2)

	// Connect user A and user B to their streams
	go func() {
		// Wait until both clients are registered in the hub
		defer wg.Done()
		n.Stream(recA, reqA)
	}()
	go func() {
		defer wg.Done()
		n.Stream(recB, reqB)
	}()

	// Wait until both clients are registered in the hub
	deadline := time.Now().Add(2 * time.Second)
	for sseHub.ClientCount() < 2 && time.Now().Before(deadline) {
		time.Sleep(2 * time.Millisecond)
	}

	notif := hub.Notification{
		ID:       "notif-1",
		Type:     "popup",
		TenantID: "tenant-a",
		Title:    "Tenant A Alert",
		Body:     "This is for Tenant A only",
	}
	sseHub.Broadcast(notif)

	// Wait until Tenant A alert has been written to recA's buffer
	deadline = time.Now().Add(2 * time.Second)
	for !strings.Contains(recA.BodyString(), "Tenant A Alert") && time.Now().Before(deadline) {
		time.Sleep(2 * time.Millisecond)
	}

	// Cancel contexts and wait for streams to exit before reading ResponseRecorders
	cancelA()
	cancelB()
	wg.Wait()

	bodyA := recA.ResponseRecorder.Body.String()
	if !strings.Contains(bodyA, "Tenant A Alert") {
		t.Errorf("Expected Tenant A to receive notification, got: %q", bodyA)
	}

	bodyB := recB.ResponseRecorder.Body.String()
	if strings.Contains(bodyB, "Tenant A Alert") {
		t.Errorf("Security Violation: Tenant B received tenant-scoped notification of Tenant A!")
	}
}

func TestSSEHubCleanupAndConcurrencyStress(t *testing.T) {
	jwtutil.Init("z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")

	mockAuth := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{
			"id":        "user-1",
			"role":      "owner",
			"is_active": true,
			"tenant_id": "tenant-1",
		})
	}))
	defer mockAuth.Close()

	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	sseHub := hub.NewSSEHub()
	cfg := &config.Config{
		AuthServiceURL:       mockAuth.URL,
		AllowedOrigin:        "http://localhost:3000",
		InternalServiceToken: "secret-internal-token",
	}
	n := NewNotification(sseHub, cfg, rdb)

	const numClients = 50
	var wg sync.WaitGroup
	wg.Add(numClients)

	stopBroadcaster := make(chan struct{})
	go func() {
		ticker := time.NewTicker(2 * time.Millisecond)
		defer ticker.Stop()
		for {
			select {
			case <-ticker.C:
				sseHub.Broadcast(hub.Notification{
					ID:       "broadcast-race",
					Type:     "popup",
					TenantID: "tenant-1",
					Title:    "Race Check",
					Body:     "Check me",
				})
			case <-stopBroadcaster:
				return
			}
		}
	}()

	for i := 0; i < numClients; i++ {
		go func(idx int) {
			defer wg.Done()

			token, _ := jwtutil.GenerateToken(fmt.Sprintf("user-%d", idx), "owner", "tenant-1", "user@test.com")
			ctx, cancel := context.WithCancel(context.Background())
			req := httptest.NewRequest("GET", "/notifications/stream?token="+token, nil)
			req = req.WithContext(ctx)
			rec := newSafeRecorder()

			go func() {
				// Wait until the client registers (indicated by receiving "event: connected")
				deadline := time.Now().Add(2 * time.Second)
				for !strings.Contains(rec.BodyString(), "event: connected") && time.Now().Before(deadline) {
					time.Sleep(2 * time.Millisecond)
				}
				// Staggered disconnect
				time.Sleep(time.Duration(10+idx%15) * time.Millisecond)
				cancel()
			}()

			n.Stream(rec, req)
		}(i)
	}

	wg.Wait()
	close(stopBroadcaster)

	// Wait until client count reaches 0 with a timeout
	deadline := time.Now().Add(2 * time.Second)
	for sseHub.ClientCount() > 0 && time.Now().Before(deadline) {
		time.Sleep(2 * time.Millisecond)
	}

	if sseHub.ClientCount() != 0 {
		t.Errorf("Expected sseHub ClientCount to return to 0 after all client disconnects, got %d", sseHub.ClientCount())
	}
}

func TestStreamAuthUnavailableFailClosed(t *testing.T) {
	jwtutil.Init("z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")

	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	sseHub := hub.NewSSEHub()
	cfg := &config.Config{
		AuthServiceURL:       "http://127.0.0.1:9999",
		AllowedOrigin:        "http://localhost:3000",
		InternalServiceToken: "secret-internal-token",
	}
	n := NewNotification(sseHub, cfg, rdb)

	token, _ := jwtutil.GenerateToken("user-1", "owner", "tenant-1", "test@example.com")
	req := httptest.NewRequest("GET", "/notifications/stream?token="+token, nil)
	rec := httptest.NewRecorder()

	n.Stream(rec, req)

	if rec.Code != http.StatusServiceUnavailable {
		t.Errorf("Expected fail-closed status 503 Service Unavailable, got %d", rec.Code)
	}

	var resp map[string]string
	if err := json.NewDecoder(rec.Body).Decode(&resp); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	if resp["error"] != "service_unavailable" {
		t.Errorf("Expected error key to be 'service_unavailable', got: %s", resp["error"])
	}
}

func TestRegisterRoutes(t *testing.T) {
	sseHub := hub.NewSSEHub()
	cfg := &config.Config{
		AuthServiceURL:       "http://localhost:3002",
		AllowedOrigin:        "http://localhost:3000",
		InternalServiceToken: "secret-internal-token",
	}
	n := NewNotification(sseHub, cfg, nil)

	mux := http.NewServeMux()
	n.RegisterRoutes(mux)

	routes := []struct {
		method string
		path   string
	}{
		{"GET", "/notifications/stream"},
		{"POST", "/notifications/send"},
		{"POST", "/notifications/broadcast/job-alert"},
	}

	for _, r := range routes {
		req := httptest.NewRequest(r.method, r.path, nil)
		_, pattern := mux.Handler(req)
		if pattern == "" {
			t.Errorf("Expected pattern for %s %s, got empty", r.method, r.path)
		}
	}
}

func TestSend_ExtraCoverage(t *testing.T) {
	sseHub := hub.NewSSEHub()
	cfg := &config.Config{
		AuthServiceURL:       "http://localhost:3002",
		AllowedOrigin:        "http://localhost:3000",
		InternalServiceToken: "secret-internal-token",
	}
	n := NewNotification(sseHub, cfg, nil)

	// 1. Non-POST method -> 405 MethodNotAllowed
	req := httptest.NewRequest("GET", "/notifications/send", nil)
	rec := httptest.NewRecorder()
	n.Send(rec, req)
	if rec.Code != http.StatusMethodNotAllowed {
		t.Errorf("Expected 405 MethodNotAllowed, got %d", rec.Code)
	}

	// 2. Missing token -> 401 Unauthorized
	req = httptest.NewRequest("POST", "/notifications/send", strings.NewReader(`{"title":"hello"}`))
	rec = httptest.NewRecorder()
	n.Send(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Errorf("Expected 401 Unauthorized for missing token, got %d", rec.Code)
	}
}

func TestBroadcastJobAlert_ExtraCoverage(t *testing.T) {
	sseHub := hub.NewSSEHub()
	cfg := &config.Config{
		AuthServiceURL:       "http://localhost:3002",
		AllowedOrigin:        "http://localhost:3000",
		InternalServiceToken: "secret-internal-token",
	}
	n := NewNotification(sseHub, cfg, nil)

	// 1. Non-POST method -> 405 MethodNotAllowed
	req := httptest.NewRequest("GET", "/notifications/broadcast/job-alert", nil)
	rec := httptest.NewRecorder()
	n.BroadcastJobAlert(rec, req)
	if rec.Code != http.StatusMethodNotAllowed {
		t.Errorf("Expected 405 MethodNotAllowed, got %d", rec.Code)
	}

	// 2. Missing or invalid internal token -> 401 Unauthorized
	req = httptest.NewRequest("POST", "/notifications/broadcast/job-alert", strings.NewReader(`{"job_id":"j-1"}`))
	req.Header.Set("X-Internal-Token", "invalid-token")
	rec = httptest.NewRecorder()
	n.BroadcastJobAlert(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Errorf("Expected 401 Unauthorized for invalid internal token, got %d", rec.Code)
	}

	// 3. Malformed JSON body -> 400 Bad Request
	req = httptest.NewRequest("POST", "/notifications/broadcast/job-alert", strings.NewReader(`{"job_id":`))
	req.Header.Set("X-Internal-Token", "secret-internal-token")
	rec = httptest.NewRecorder()
	n.BroadcastJobAlert(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("Expected 400 Bad Request for malformed JSON, got %d", rec.Code)
	}
}
