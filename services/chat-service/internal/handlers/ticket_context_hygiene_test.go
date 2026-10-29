package handlers

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/project/shared/infra/handlerutil"
	"github.com/project/shared/infra/jwtutil"
	"github.com/project/shared/infra/ratelimit"
	"github.com/redis/go-redis/v9"
)

func TestCreateTicket_ContextIDHygiene(t *testing.T) {
	secret := "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2"
	os.Setenv("JWT_SECRET", secret)
	jwtutil.Init(secret)

	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	c := &Chat{
		limiter: handlerutil.NewRateLimiter(ratelimit.NewRateLimiter(rdb, 60, time.Minute, "test")),
	}

	token, err := jwtutil.GenerateToken("cust-hygiene-user", "user", "tenant-1", "user@test.com")
	if err != nil {
		t.Fatalf("failed to generate token: %v", err)
	}

	invalidPayloads := []struct {
		name      string
		contextID string
	}{
		{name: "script tag", contextID: "<script>alert(1)</script>"},
		{name: "img tag with onerror", contextID: `"><img src=x onerror=alert(1)>`},
		{name: "spaces and quotes", contextID: `job ' or 1=1 --`},
		{name: "exceeds 64 chars", contextID: strings.Repeat("a", 65)},
		{name: "newline injection", contextID: "job-123\nmalicious"},
		{name: "control characters", contextID: "job-123\x00xss"},
	}

	for _, tc := range invalidPayloads {
		t.Run(tc.name, func(t *testing.T) {
			body, _ := json.Marshal(map[string]string{
				"context_id": tc.contextID,
			})
			req := httptest.NewRequest(http.MethodPost, "/chat/support/ticket", bytes.NewReader(body))
			req.Header.Set("Authorization", "Bearer "+token)
			rec := httptest.NewRecorder()

			c.HandleCreateTicket(rec, req)

			if rec.Code != http.StatusBadRequest {
				t.Fatalf("expected 400 Bad Request for %s, got %d: %s", tc.name, rec.Code, rec.Body.String())
			}

			var resp map[string]string
			if err := json.NewDecoder(rec.Body).Decode(&resp); err != nil {
				t.Fatalf("failed to decode response: %v", err)
			}
			if resp["code"] != "invalid_context_id" && resp["error"] != "invalid_context_id" {
				t.Fatalf("expected code 'invalid_context_id', got: %+v", resp)
			}
		})
	}
}
