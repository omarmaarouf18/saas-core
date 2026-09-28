package handlers

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/alicebob/miniredis/v2"
	"github.com/project/notification-service/internal/config"
	"github.com/project/notification-service/internal/hub"
	"github.com/redis/go-redis/v9"
)

// A3: forced-failure cases must return the stable sanitized body — no
// library internals may reach the client.
func TestSafeError_NoInternalsLeak_Notif(t *testing.T) {
	sseHub := hub.NewSSEHub()
	cfg := &config.Config{
		AuthServiceURL:       "http://localhost:3002",
		AllowedOrigin:        "http://localhost:3000",
		InternalServiceToken: "secret-internal-token",
	}
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("miniredis: %v", err)
	}
	defer mr.Close()
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()
	n := NewNotification(sseHub, nil, cfg, rdb)

	internals := []string{
		"unexpected end of JSON", "cannot unmarshal", "invalid character",
		"mongo", "Mongo", "BSON",
	}

	t.Run("malformed JSON sanitized", func(t *testing.T) {
		req := httptest.NewRequest("POST", "/notifications/send", strings.NewReader("{bad json"))
		req.Header.Set("X-Internal-Token", "secret-internal-token")
		rec := httptest.NewRecorder()
		n.Send(rec, req)
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("expected 400, got %d (%s)", rec.Code, rec.Body.String())
		}
		var decoded map[string]any
		if err := json.Unmarshal(rec.Body.Bytes(), &decoded); err != nil {
			t.Fatalf("body not JSON: %s", rec.Body.String())
		}
		if decoded["code"] != "invalid_json" {
			t.Errorf("expected code invalid_json, got %s", rec.Body.String())
		}
		for _, leak := range internals {
			if strings.Contains(rec.Body.String(), leak) {
				t.Errorf("internal detail %q leaked in body %s", leak, rec.Body.String())
			}
		}
	})
}
