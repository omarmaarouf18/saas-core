package handlers

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/project/notification-service/internal/config"
	"github.com/project/notification-service/internal/hub"
)

func TestNotificationHandlersAuth(t *testing.T) {
	sseHub := hub.NewSSEHub()
	internalToken := "secret-internal-token"
	cfg := &config.Config{
		AuthServiceURL:       "http://localhost:3002",
		AllowedOrigin:        "http://localhost:3000",
		InternalServiceToken: internalToken,
	}
	n := NewNotification(sseHub, cfg)

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
