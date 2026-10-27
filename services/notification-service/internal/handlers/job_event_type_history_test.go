package handlers

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"

	"github.com/alicebob/miniredis/v2"
	"github.com/project/notification-service/internal/config"
	"github.com/project/notification-service/internal/hub"
	"github.com/project/shared/infra/jwtutil"
	"github.com/redis/go-redis/v9"
)

// BE-GAPS-FIX item 1: history items about a job carry event_type == type
// (derived, so documents stored before the field existed get it too);
// items without a job carry none.
func TestNotificationHistory_JobItemsCarryEventType(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	jwtutil.Init(os.Getenv("JWT_SECRET"))

	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	userID, tenantID := "cust-evt", "tenant-evt"
	mockAuth := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{"id": userID, "tenant_id": tenantID, "role": "client", "is_active": true})
	}))
	defer mockAuth.Close()

	internalToken := "test-internal-token"
	n := NewNotification(hub.NewSSEHub(), newMemoryStore(), &config.Config{
		AuthServiceURL: mockAuth.URL, InternalServiceToken: internalToken, AllowedOrigin: "*",
	}, rdb)
	mux := http.NewServeMux()
	n.RegisterRoutes(mux)

	send := func(payload map[string]any) {
		t.Helper()
		b, _ := json.Marshal(payload)
		req := httptest.NewRequest(http.MethodPost, "/notifications/send", bytes.NewReader(b))
		req.Header.Set("X-Internal-Token", internalToken)
		rec := httptest.NewRecorder()
		mux.ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("send: %d %s", rec.Code, rec.Body.String())
		}
	}
	send(map[string]any{"type": "job_delivered", "tenant_id": tenantID, "user_id": userID, "job_id": "job-evt-1",
		"title": "Delivered", "body": "Job job-evt-1 was delivered.", "roles": []string{"client", "user"}})
	send(map[string]any{"type": "ticket_resolved", "tenant_id": tenantID, "user_id": userID,
		"title": "Resolved", "body": "Ticket resolved", "roles": []string{"client", "user"}})

	token, _ := jwtutil.GenerateToken(userID, "user", tenantID, "cust@example.com")
	req := httptest.NewRequest(http.MethodGet, "/notifications/history?limit=10", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("history: %d %s", rec.Code, rec.Body.String())
	}
	var resp struct {
		Notifications []map[string]any `json:"notifications"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if len(resp.Notifications) != 2 {
		t.Fatalf("expected 2 history items, got %d: %s", len(resp.Notifications), rec.Body.String())
	}
	for _, it := range resp.Notifications {
		switch it["type"] {
		case "job_delivered":
			if it["event_type"] != "job_delivered" || it["job_id"] != "job-evt-1" {
				t.Errorf("job item = %v, want event_type job_delivered and job_id", it)
			}
		case "ticket_resolved":
			if _, ok := it["event_type"]; ok {
				t.Errorf("non-job item carries event_type: %v", it)
			}
		default:
			t.Errorf("unexpected item %v", it)
		}
	}
}
