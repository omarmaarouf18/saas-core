package handlers

import (
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
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
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
	cfg := &config.Config{
		AuthServiceURL:       "http://127.0.0.1:1",
		UserServiceURL:       "http://127.0.0.1:1",
		InternalServiceToken: "mock-internal-token",
		AllowedOrigin:        "http://localhost:3000",
	}
	h := NewChat(nil, mongoStore, cfg, rdb)

	internals := []string{
		"token has invalid", "invalid claims", "token is malformed",
		"invalid number of segments", "signature", "jwtutil: ",
		"unexpected end of JSON", "cannot unmarshal", "invalid character",
		"mongo", "Mongo", "BSON", "duplicate key", "connection refused",
		"store: ",
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
