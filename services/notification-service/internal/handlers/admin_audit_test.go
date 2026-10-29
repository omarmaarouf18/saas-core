package handlers

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/project/notification-service/internal/store"
)

// TestAdminAudit_NotificationSendPersistsAndServesInternally checks that an
// admin notification send writes a notification-service admin_audit record
// (actor, action, target = send job id, reason, request id) and that
// GET /notifications/internal/admin-audit serves it to internal-token callers
// only (ADMIN-API-FIX).
func TestAdminAudit_NotificationSendPersistsAndServesInternally(t *testing.T) {
	_, memStore, mux, validRevToken, mockAuth := setupAdminNotificationTestContext(t)
	defer mockAuth.Close()

	payload, _ := json.Marshal(map[string]any{
		"reason":                "Emergency platform update",
		"audience":              map[string]any{"kind": "everyone"},
		"title":                 map[string]string{"en": "Update", "ar": "تحديث"},
		"body":                  map[string]string{"en": "Please update your app", "ar": "يرجى تحديث التطبيق"},
		"confirm_audience_size": 1200,
		"idempotency_key":       "audit-send-1",
	})
	req := httptest.NewRequest(http.MethodPost, "/admin/notifications/send", bytes.NewReader(payload))
	req.Header.Set("X-Internal-Token", "test-internal-token-456")
	req.Header.Set("X-Reviewer-Token", validRevToken)
	req.Header.Set("X-Request-ID", "req-send-1")
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusAccepted {
		t.Fatalf("send: expected 202, got %d: %s", rec.Code, rec.Body.String())
	}
	var sendResp struct {
		JobID string `json:"job_id"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &sendResp)

	memStore.mu.Lock()
	records := append([]store.AdminAuditRecord(nil), memStore.adminAudit...)
	memStore.mu.Unlock()
	if len(records) != 1 {
		t.Fatalf("expected 1 admin audit record, got %d", len(records))
	}
	got := records[0]
	if got.Source != "notification-service" || got.ActorID != "rev-operator-1" || got.Action != "notification.send" ||
		got.TargetType != "notification_send" || got.TargetID != sendResp.JobID || got.Reason != "Emergency platform update" || got.RequestID != "req-send-1" {
		t.Fatalf("unexpected record: %+v", got)
	}

	noTok := httptest.NewRecorder()
	mux.ServeHTTP(noTok, httptest.NewRequest(http.MethodGet, "/notifications/internal/admin-audit", nil))
	if noTok.Code != http.StatusUnauthorized {
		t.Fatalf("internal endpoint without token: expected 401, got %d", noTok.Code)
	}
	listReq := httptest.NewRequest(http.MethodGet, "/notifications/internal/admin-audit?action=notification.send", nil)
	listReq.Header.Set("X-Internal-Token", "test-internal-token-456")
	listRec := httptest.NewRecorder()
	mux.ServeHTTP(listRec, listReq)
	var resp struct {
		Entries []store.AdminAuditRecord `json:"entries"`
		Total   int64                    `json:"total"`
	}
	if err := json.Unmarshal(listRec.Body.Bytes(), &resp); err != nil || listRec.Code != http.StatusOK {
		t.Fatalf("internal list: %d %s (%v)", listRec.Code, listRec.Body.String(), err)
	}
	if resp.Total != 1 || resp.Entries[0].ID != got.ID {
		t.Fatalf("internal list: %+v", resp)
	}
}
