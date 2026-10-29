package handlers

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gorilla/websocket"
	"github.com/project/shared/infra/jwtutil"
)

func TestWebSocketAuth_HeadersAndSubprotocols(t *testing.T) {
	c, _, cleanup := setupTestChat(t)
	if c == nil {
		return
	}
	defer cleanup()

	// Spin up test HTTP server
	mux := http.NewServeMux()
	mux.HandleFunc("/chat/ws", c.HandleWebSocket)
	server := httptest.NewServer(mux)
	defer server.Close()

	wsURL := "ws" + strings.TrimPrefix(server.URL, "http") + "/chat/ws"

	token, err := jwtutil.GenerateToken("ws-header-user", "user", "tenant-1", "user@test.com")
	if err != nil {
		t.Fatalf("failed to generate token: %v", err)
	}

	dialer := websocket.Dialer{
		HandshakeTimeout: 5 * time.Second,
	}

	// 1. Authorization: Bearer header (no token in query string)
	t.Run("Authorization Bearer Header", func(t *testing.T) {
		header := http.Header{}
		header.Set("Authorization", "Bearer "+token)
		header.Set("Origin", "http://localhost:3000")

		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()

		conn, resp, err := dialer.DialContext(ctx, wsURL, header)
		if err != nil {
			t.Fatalf("failed to connect with Authorization header: %v", err)
		}
		defer conn.Close()

		if resp.StatusCode != http.StatusSwitchingProtocols {
			t.Fatalf("expected 101 Switching Protocols, got %d", resp.StatusCode)
		}
	})

	// 2. X-Reviewer-Token header
	t.Run("X-Reviewer-Token Header", func(t *testing.T) {
		header := http.Header{}
		header.Set("X-Reviewer-Token", token)
		header.Set("Origin", "http://localhost:3000")

		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()

		conn, resp, err := dialer.DialContext(ctx, wsURL, header)
		if err != nil {
			t.Fatalf("failed to connect with X-Reviewer-Token: %v", err)
		}
		defer conn.Close()

		if resp.StatusCode != http.StatusSwitchingProtocols {
			t.Fatalf("expected 101 Switching Protocols, got %d", resp.StatusCode)
		}
	})

	// 3. Sec-WebSocket-Protocol subprotocol negotiation (kyc-console-auth, <token>)
	t.Run("kyc-console-auth subprotocol", func(t *testing.T) {
		subDialer := websocket.Dialer{
			HandshakeTimeout: 5 * time.Second,
			Subprotocols:     []string{"kyc-console-auth", token},
		}
		header := http.Header{}
		header.Set("Origin", "http://localhost:3000")

		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()

		conn, resp, err := subDialer.DialContext(ctx, wsURL, header)
		if err != nil {
			t.Fatalf("failed to connect with kyc-console-auth subprotocol: %v", err)
		}
		defer conn.Close()

		if resp.StatusCode != http.StatusSwitchingProtocols {
			t.Fatalf("expected 101 Switching Protocols, got %d", resp.StatusCode)
		}
		if gotProto := resp.Header.Get("Sec-WebSocket-Protocol"); gotProto != "kyc-console-auth" {
			t.Fatalf("expected echoed subprotocol 'kyc-console-auth', got %q", gotProto)
		}
	})

	// 4. Deprecated ?token= query parameter fallback
	t.Run("Deprecated query token fallback", func(t *testing.T) {
		header := http.Header{}
		header.Set("Origin", "http://localhost:3000")

		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()

		conn, resp, err := dialer.DialContext(ctx, wsURL+"?token="+token, header)
		if err != nil {
			t.Fatalf("failed to connect with query token: %v", err)
		}
		defer conn.Close()

		if resp.StatusCode != http.StatusSwitchingProtocols {
			t.Fatalf("expected 101 Switching Protocols, got %d", resp.StatusCode)
		}
	})
}
