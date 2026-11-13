package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/project/chat-service/internal/config"
	"github.com/redis/go-redis/v9"
)

// A3: forced-failure cases must return the stable sanitized body — no
// JWT/DB/library internals may reach the client.
func TestSafeError_NoInternalsLeak_Chat(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	dbName := fmt.Sprintf("chat_safeerr_test_%d", time.Now().UnixNano())
	mongoStore, err := connectTestMongoDB(ctx, dbName)
	if err != nil {
		t.Skipf("MongoDB not available: %v", err)
		return
	}
	defer func() {
		_ = mongoStore.Close(context.Background())
	}()
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("miniredis: %v", err)
	}
	defer mr.Close()
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	const validReviewerToken = "valid-reviewer-token-xyz"
	mockAuthServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/auth/reviewer/verify" {
			revTok := r.Header.Get("X-Reviewer-Token")
			if revTok == validReviewerToken {
				w.WriteHeader(http.StatusOK)
				_, _ = w.Write([]byte(`{"id":"rev-safe-1","name":"Reviewer Safety"}`))
				return
			}
			w.WriteHeader(http.StatusUnauthorized)
			_, _ = w.Write([]byte(`{"error":"invalid reviewer token"}`))
			return
		}
		if r.URL.Path == "/notifications/send" {
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte(`{"status":"success"}`))
			return
		}
		w.WriteHeader(http.StatusNotFound)
	}))
	defer mockAuthServer.Close()

	cfg := &config.Config{
		AuthServiceURL:         mockAuthServer.URL,
		UserServiceURL:         mockAuthServer.URL,
		NotificationServiceURL: mockAuthServer.URL,
		InternalServiceToken:   "mock-internal-token",
		AllowedOrigin:          "http://localhost:3000",
	}
	h := NewChat(nil, mongoStore, cfg, rdb)

	internals := []string{
		"token has invalid", "invalid claims", "token is malformed",
		"invalid number of segments", "signature", "jwtutil: ",
		"unexpected end of JSON", "cannot unmarshal", "invalid character",
		"mongo", "Mongo", "BSON", "duplicate key", "connection refused",
		"store: ", "unauthorized reviewer:", "tkt-res-conf", "tkt-acc-conf",
	}

	t.Run("malformed token sanitized", func(t *testing.T) {
		req := httptest.NewRequest("GET", "/chat/history?channel=job:x&token=not-a-jwt&requester_id=y", nil)
		rec := httptest.NewRecorder()
		h.GetHistory(rec, req)
		if rec.Code != http.StatusForbidden {
			t.Fatalf("expected 403, got %d (%s)", rec.Code, rec.Body.String())
		}
		assertChatSanitized(t, rec.Body.String(), internals, "invalid_token")
	})

	t.Run("writeReviewerAuthError sanitized on invalid reviewer token", func(t *testing.T) {
		req := httptest.NewRequest("GET", "/chat/admin/tickets", nil)
		req.Header.Set("X-Internal-Token", "mock-internal-token")
		req.Header.Set("X-Reviewer-Token", "invalid-token")
		rec := httptest.NewRecorder()
		h.AdminListTickets(rec, req)
		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("expected 401, got %d (%s)", rec.Code, rec.Body.String())
		}
		assertChatSanitized(t, rec.Body.String(), internals, "unauthorized")
	})

	t.Run("AdminResolveTicket not found sanitized", func(t *testing.T) {
		body := bytes.NewReader([]byte(`{"ticket_id":"nonexistent-tkt-id","resolution_note":"Resolved"}`))
		req := httptest.NewRequest("POST", "/chat/admin/tickets/resolve", body)
		req.Header.Set("X-Internal-Token", "mock-internal-token")
		req.Header.Set("X-Reviewer-Token", validReviewerToken)
		rec := httptest.NewRecorder()
		h.AdminResolveTicket(rec, req)
		if rec.Code != http.StatusNotFound {
			t.Fatalf("expected 404, got %d (%s)", rec.Code, rec.Body.String())
		}
		assertChatSanitized(t, rec.Body.String(), internals, "not_found")
	})

	t.Run("AdminResolveTicket conflict sanitized", func(t *testing.T) {
		ticket, err := mongoStore.CreateTicketAndAssign(ctx, "cust-res-conf", "job-res-conf")
		if err != nil {
			t.Fatalf("failed to create ticket: %v", err)
		}
		_, err = mongoStore.AdminResolveTicket(ctx, ticket.ID, "first resolve", "rev-safe-1")
		if err != nil {
			t.Fatalf("first resolve failed: %v", err)
		}

		body := bytes.NewReader([]byte(fmt.Sprintf(`{"ticket_id":"%s","resolution_note":"second resolve"}`, ticket.ID)))
		req := httptest.NewRequest("POST", "/chat/admin/tickets/resolve", body)
		req.Header.Set("X-Internal-Token", "mock-internal-token")
		req.Header.Set("X-Reviewer-Token", validReviewerToken)
		rec := httptest.NewRecorder()
		h.AdminResolveTicket(rec, req)
		if rec.Code != http.StatusConflict {
			t.Fatalf("expected 409, got %d (%s)", rec.Code, rec.Body.String())
		}
		assertChatSanitized(t, rec.Body.String(), internals, "conflict")
	})

	t.Run("AdminAcceptTicket not found sanitized", func(t *testing.T) {
		body := bytes.NewReader([]byte(`{"ticket_id":"nonexistent-tkt-id"}`))
		req := httptest.NewRequest("POST", "/chat/admin/tickets/accept", body)
		req.Header.Set("X-Internal-Token", "mock-internal-token")
		req.Header.Set("X-Reviewer-Token", validReviewerToken)
		rec := httptest.NewRecorder()
		h.AdminAcceptTicket(rec, req)
		if rec.Code != http.StatusNotFound {
			t.Fatalf("expected 404, got %d (%s)", rec.Code, rec.Body.String())
		}
		assertChatSanitized(t, rec.Body.String(), internals, "not_found")
	})

	t.Run("AdminAcceptTicket conflict sanitized", func(t *testing.T) {
		ticket, err := mongoStore.CreateTicketAndAssign(ctx, "cust-acc-conf", "job-acc-conf")
		if err != nil {
			t.Fatalf("failed to create ticket: %v", err)
		}
		_, err = mongoStore.AdminAcceptTicket(ctx, ticket.ID, "rev-safe-1")
		if err != nil {
			t.Fatalf("first accept failed: %v", err)
		}

		body := bytes.NewReader([]byte(fmt.Sprintf(`{"ticket_id":"%s"}`, ticket.ID)))
		req := httptest.NewRequest("POST", "/chat/admin/tickets/accept", body)
		req.Header.Set("X-Internal-Token", "mock-internal-token")
		req.Header.Set("X-Reviewer-Token", validReviewerToken)
		rec := httptest.NewRecorder()
		h.AdminAcceptTicket(rec, req)
		if rec.Code != http.StatusConflict {
			t.Fatalf("expected 409, got %d (%s)", rec.Code, rec.Body.String())
		}
		assertChatSanitized(t, rec.Body.String(), internals, "conflict")
	})

	t.Run("UploadTicketAttachment unauthorized sanitized", func(t *testing.T) {
		req := httptest.NewRequest("POST", "/chat/tickets/tkt-safe-1/attachment", nil)
		rec := httptest.NewRecorder()
		h.UploadTicketAttachment(rec, req)
		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("expected 401, got %d (%s)", rec.Code, rec.Body.String())
		}
		assertChatSanitized(t, rec.Body.String(), internals, "unauthorized")
	})
}

func assertChatSanitized(t *testing.T, body string, internals []string, wantCode string) {
	t.Helper()
	var decoded map[string]any
	if err := json.Unmarshal([]byte(body), &decoded); err != nil {
		t.Fatalf("body not JSON: %s", body)
	}
	if decoded["code"] != wantCode {
		t.Errorf("expected code %q, got body %s", wantCode, body)
	}
	rid, ok := decoded["request_id"].(string)
	if !ok || len(rid) != 16 {
		t.Errorf("request_id missing/malformed in %s", body)
	}
	for _, leak := range internals {
		if strings.Contains(body, leak) {
			t.Errorf("internal detail %q leaked in body %s", leak, body)
		}
	}
}
