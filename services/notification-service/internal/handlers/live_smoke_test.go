package handlers

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
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

// TestStream_LiveSmoke_EndToEndNotificationDelivery performs an end-to-end smoke test:
//  1. Opens a real HTTP SSE connection to GET /notifications/stream with a valid JWT token.
//  2. Confirms receipt of the initial "event: connected" handshake frame.
//  3. Dispatches a real notification from a different code path (POST /notifications/send with internal token,
//     as called by auth-service for KYC review outcome and account suspension).
//  4. Verifies the notification is delivered live over the HTTP SSE stream.
//  5. Simulates Instance B publishing a cross-instance notification via Redis Pub/Sub,
//     and verifies receipt over the same live HTTP SSE stream.
//  6. Confirms origin-ID deduplication prevents echo duplicates.
func TestStream_LiveSmoke_EndToEndNotificationDelivery(t *testing.T) {
	jwtSecret := "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2"
	jwtutil.Init(jwtSecret)

	// 1. Setup mock auth-service for token verification
	mockAuth := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if r.URL.Query().Get("id") == "smoke-user-1" {
			w.WriteHeader(http.StatusOK)
			_ = json.NewEncoder(w).Encode(map[string]any{
				"id":        "smoke-user-1",
				"role":      "owner",
				"tenant_id": "tenant-smoke-1",
				"is_active": true,
			})
			return
		}
		w.WriteHeader(http.StatusNotFound)
	}))
	defer mockAuth.Close()

	// 2. Setup Redis and Notification Service
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()

	rdbA := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdbA.Close()

	rdbB := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdbB.Close()

	sseHub := hub.NewSSEHub()
	sseHub.SetRedisClient(rdbA)
	defer sseHub.Close()

	internalToken := "smoke-internal-token-q18"
	cfg := &config.Config{
		AuthServiceURL:       mockAuth.URL,
		AllowedOrigin:        "*",
		InternalServiceToken: internalToken,
	}

	notifHandler := NewNotification(sseHub, nil, cfg, rdbA)

	mux := http.NewServeMux()
	notifHandler.RegisterRoutes(mux)

	server := httptest.NewServer(mux)
	defer server.Close()

	// Generate valid JWT token for smoke-user-1
	token, err := jwtutil.GenerateToken("smoke-user-1", "owner", "tenant-smoke-1", "smoke@test.com")
	if err != nil {
		t.Fatalf("failed to generate token: %v", err)
	}

	// 3. Open real HTTP SSE connection
	streamCtx, streamCancel := context.WithCancel(context.Background())
	defer streamCancel()

	streamReq, err := http.NewRequestWithContext(streamCtx, "GET", server.URL+"/notifications/stream?token="+token, nil)
	if err != nil {
		t.Fatalf("failed to build stream request: %v", err)
	}

	client := &http.Client{Timeout: 0}
	resp, err := client.Do(streamReq)
	if err != nil {
		t.Fatalf("failed to connect to SSE stream: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 OK from SSE stream, got %d", resp.StatusCode)
	}

	reader := bufio.NewReader(resp.Body)

	// Helper to read an SSE event block (lines until double newline)
	readSSEEvent := func(timeout time.Duration) (string, error) {
		type result struct {
			content string
			err     error
		}
		ch := make(chan result, 1)
		go func() {
			var sb strings.Builder
			for {
				line, err := reader.ReadString('\n')
				if err != nil {
					ch <- result{"", err}
					return
				}
				sb.WriteString(line)
				if line == "\n" || line == "\r\n" {
					ch <- result{sb.String(), nil}
					return
				}
			}
		}()

		select {
		case res := <-ch:
			return res.content, res.err
		case <-time.After(timeout):
			return "", fmt.Errorf("timeout waiting for SSE event")
		}
	}

	// 4. Verify initial connection event
	event1, err := readSSEEvent(3 * time.Second)
	if err != nil {
		t.Fatalf("failed to read connected event: %v", err)
	}
	t.Logf("Received Initial SSE Event:\n%s", event1)
	if !strings.Contains(event1, "event: connected") {
		t.Fatalf("expected 'event: connected', got: %s", event1)
	}

	// 5. Dispatch real notification from a different code path:
	// Simulating auth-service dispatching a KYC review outcome via POST /notifications/send
	sendPayload := map[string]any{
		"type":      "kyc_approved",
		"tenant_id": "tenant-smoke-1",
		"user_id":   "smoke-user-1",
		"title":     "KYC Verification Approved",
		"body":      "Congratulations, your owner verification documents were reviewed and approved.",
	}
	sendBytes, _ := json.Marshal(sendPayload)

	sendReq, err := http.NewRequest("POST", server.URL+"/notifications/send", bytes.NewReader(sendBytes))
	if err != nil {
		t.Fatalf("failed to build send request: %v", err)
	}
	sendReq.Header.Set("Content-Type", "application/json")
	sendReq.Header.Set("X-Internal-Token", internalToken)

	sendResp, err := http.DefaultClient.Do(sendReq)
	if err != nil {
		t.Fatalf("failed to call /notifications/send: %v", err)
	}
	defer sendResp.Body.Close()

	if sendResp.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 OK from /notifications/send, got %d", sendResp.StatusCode)
	}
	t.Logf("POST /notifications/send succeeded with status 200")

	// 6. Confirm receipt over the live HTTP SSE stream
	event2, err := readSSEEvent(3 * time.Second)
	if err != nil {
		t.Fatalf("failed to read notification event: %v", err)
	}
	t.Logf("Received Live Notification on SSE Stream:\n%s", event2)
	if !strings.Contains(event2, "event: notification") {
		t.Fatalf("expected 'event: notification', got: %s", event2)
	}
	if !strings.Contains(event2, "KYC Verification Approved") {
		t.Fatalf("expected title 'KYC Verification Approved' in payload, got: %s", event2)
	}

	// 7. Cross-Instance Delivery Smoke Test:
	// Instance B publishes a notification over Redis Pub/Sub
	crossNotif := hub.Notification{
		ID:        "smoke-cross-inst-2",
		Type:      "account_reactivated",
		TenantID:  "tenant-smoke-1",
		UserID:    "smoke-user-1",
		Title:     "Account Reactivated",
		Body:      "Dispatched from Instance B via Redis Pub/Sub",
		Timestamp: time.Now().UTC(),
	}
	crossPayload := struct {
		OriginInstanceID string           `json:"origin_instance_id"`
		Notification     hub.Notification `json:"notification"`
	}{
		OriginInstanceID: "simulated-instance-B",
		Notification:     crossNotif,
	}
	crossBytes, _ := json.Marshal(crossPayload)

	if err := rdbB.Publish(context.Background(), "notify:tenant:tenant-smoke-1", crossBytes).Err(); err != nil {
		t.Fatalf("Instance B publish failed: %v", err)
	}

	// 8. Confirm receipt of cross-instance notification on the same live SSE stream
	event3, err := readSSEEvent(3 * time.Second)
	if err != nil {
		t.Fatalf("failed to read cross-instance notification event: %v", err)
	}
	t.Logf("Received Cross-Instance Notification on SSE Stream:\n%s", event3)
	if !strings.Contains(event3, "event: notification") {
		t.Fatalf("expected 'event: notification', got: %s", event3)
	}
	if !strings.Contains(event3, "Account Reactivated") {
		t.Fatalf("expected 'Account Reactivated' in payload, got: %s", event3)
	}

	// 9. Confirm origin deduplication: no echo duplicate event received
	_, err = readSSEEvent(200 * time.Millisecond)
	if err == nil {
		t.Fatalf("unexpected duplicate event received on SSE stream")
	}
	t.Logf("[SMOKE TEST PASS] Live HTTP SSE connection verified end-to-end with local dispatch, cross-instance dispatch, and origin deduplication.")
}
