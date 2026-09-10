package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/project/chat-service/internal/chat"
	"github.com/project/chat-service/internal/config"
	"github.com/project/chat-service/internal/store"
)

func TestHandleResolveTicket_ConflictWhenAlreadyResolved(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	dbName := fmt.Sprintf("saas_chat_resolve_test_%d", time.Now().UnixNano())
	s, err := connectTestMongoDB(ctx, dbName)
	if err != nil {
		t.Skipf("skipping MongoDB test: %v", err)
		return
	}
	defer func() {
		_ = s.DropDatabase(ctx)
		_ = s.Close(ctx)
	}()

	hub := chat.NewHub()
	go hub.Run()
	defer hub.Close()

	cfg := &config.Config{
		AllowedOrigin: "http://localhost:3000",
	}

	h := NewChat(hub, s, cfg, nil)

	const token = "agent-token-test-123"
	agent := &store.SupportAgent{
		ID:     "agent-resolve-test",
		Status: "available",
		Token:  token,
	}
	if err := s.AddSupportAgent(ctx, agent); err != nil {
		t.Fatalf("failed to insert agent: %v", err)
	}

	ticket, err := s.CreateTicketAndAssign(ctx, "cust-1", "ctx-1")
	if err != nil {
		t.Fatalf("failed to create ticket: %v", err)
	}

	// 1. First resolve request: HTTP 200 OK
	body, _ := json.Marshal(map[string]string{"ticket_id": ticket.ID})
	req1 := httptest.NewRequest(http.MethodPost, "/chat/tickets/resolve?token="+token, bytes.NewReader(body))
	w1 := httptest.NewRecorder()
	h.HandleResolveTicket(w1, req1)

	if w1.Code != http.StatusOK {
		t.Fatalf("first resolve expected 200 OK, got %d: %s", w1.Code, w1.Body.String())
	}

	// 2. Second resolve request on already resolved ticket: HTTP 409 Conflict
	body2, _ := json.Marshal(map[string]string{"ticket_id": ticket.ID})
	req2 := httptest.NewRequest(http.MethodPost, "/chat/tickets/resolve?token="+token, bytes.NewReader(body2))
	w2 := httptest.NewRecorder()
	h.HandleResolveTicket(w2, req2)

	if w2.Code != http.StatusConflict {
		t.Fatalf("second resolve expected 409 Conflict, got %d: %s", w2.Code, w2.Body.String())
	}

	var errResp map[string]string
	if err := json.Unmarshal(w2.Body.Bytes(), &errResp); err != nil {
		t.Fatalf("failed to parse error response: %v", err)
	}
	if errResp["error"] != "ticket is already resolved" {
		t.Fatalf("expected error message 'ticket is already resolved', got %q", errResp["error"])
	}
}
