package handlers

import (
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

// TestRepro_Q27_SSEConnectedEchoesUserIDNotRawToken verifies that the SSE handshake
// event: connected echoes claims.UserID rather than the raw bearer token in client_id.
func TestRepro_Q27_SSEConnectedEchoesUserIDNotRawToken(t *testing.T) {
	jwtutil.Init("z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")

	mockAuth := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_ = json.NewEncoder(w).Encode(map[string]any{
			"id":        "user-q27-actual-id",
			"role":      "owner",
			"is_active": true,
			"tenant_id": "tenant-q27",
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

	n := NewNotification(sseHub, nil, cfg, rdb)

	goodToken, _ := jwtutil.GenerateToken("user-q27-actual-id", "owner", "tenant-q27", "q27@example.com")
	ctx, cancel := context.WithCancel(context.Background())
	req := httptest.NewRequest("GET", "/notifications/stream?token="+goodToken, nil)
	req = req.WithContext(ctx)
	rec := httptest.NewRecorder()

	go func() {
		deadline := time.Now().Add(2 * time.Second)
		for sseHub.ClientCount() == 0 && time.Now().Before(deadline) {
			time.Sleep(2 * time.Millisecond)
		}
		cancel()
	}()

	n.Stream(rec, req)

	body := rec.Body.String()
	if !strings.Contains(body, "event: connected") {
		t.Fatalf("Expected event: connected in response, got: %s", body)
	}

	// Pre-fix: body contains the raw bearer token in client_id: `data: {"client_id":"<goodToken>","role":"owner"}`
	// Post-fix: body must contain the UserID: `data: {"client_id":"user-q27-actual-id","role":"owner"}`
	if strings.Contains(body, goodToken) {
		t.Errorf("REPRO CONFIRMED Q27: SSE stream leaked raw JWT token in event: connected payload! Body snippet: %s", body)
	} else if strings.Contains(body, `"client_id":"user-q27-actual-id"`) {
		t.Logf("PASS: SSE stream correctly echoed claims.UserID and omitted raw bearer token")
	} else {
		t.Errorf("Unexpected SSE body: %s", body)
	}
}
