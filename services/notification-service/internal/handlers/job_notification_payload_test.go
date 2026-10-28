package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"

	"github.com/alicebob/miniredis/v2"
	"github.com/project/notification-service/internal/config"
	"github.com/project/notification-service/internal/hub"
	"github.com/project/notification-service/internal/store"
	"github.com/project/shared/infra/jwtutil"
	"github.com/redis/go-redis/v9"
)

func TestJobNotifications_PayloadCarriesJobIDAndStableEventType(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	jwtutil.Init(os.Getenv("JWT_SECRET"))

	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	targetUserID := "user-job-target"
	tenantID := "tenant-job-owner"
	jobID := "job-order-abc-123"

	mockAuth := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{
			"id":        targetUserID,
			"tenant_id": tenantID,
			"role":      "client",
			"is_active": true,
		})
	}))
	defer mockAuth.Close()

	internalToken := "test-internal-token"
	cfg := &config.Config{
		AuthServiceURL:       mockAuth.URL,
		InternalServiceToken: internalToken,
		AllowedOrigin:        "*",
	}

	h := hub.NewSSEHub()
	memStore := newMemoryStore()
	n := NewNotification(h, memStore, cfg, rdb)

	mux := http.NewServeMux()
	n.RegisterRoutes(mux)

	// 1. Test POST /notifications/send with job_id and stable event type
	sendPayload := map[string]any{
		"type":      "job_accepted",
		"tenant_id": tenantID,
		"user_id":   targetUserID,
		"job_id":    jobID,
		"title":     "Courier Assigned",
		"body":      "Your courier has accepted! Final fare: EGP 25",
		"roles":     []string{"client", "user"},
	}
	bodyBytes, _ := json.Marshal(sendPayload)
	req := httptest.NewRequest(http.MethodPost, "/notifications/send", bytes.NewReader(bodyBytes))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Internal-Token", internalToken)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK from /notifications/send, got %d: %s", rec.Code, rec.Body.String())
	}

	var sendResp struct {
		Message      string           `json:"message"`
		Notification hub.Notification `json:"notification"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &sendResp); err != nil {
		t.Fatalf("unmarshal send response: %v", err)
	}

	if sendResp.Notification.JobID != jobID {
		t.Errorf("expected job_id %q in send response, got %q", jobID, sendResp.Notification.JobID)
	}
	if sendResp.Notification.Type != "job_accepted" {
		t.Errorf("expected stable event type 'job_accepted', got %q", sendResp.Notification.Type)
	}

	// Verify ToClient wire projection includes JobID
	clientWire := sendResp.Notification.ToClient()
	if clientWire.JobID != jobID {
		t.Errorf("expected client wire JobID %q, got %q", jobID, clientWire.JobID)
	}

	// 2. Verify persistence in Store
	storedList, err := memStore.ListForUser(context.Background(), tenantID, targetUserID, []string{"client", "user"}, 10, nil)
	if err != nil {
		t.Fatalf("list store notifications: %v", err)
	}
	if len(storedList) == 0 {
		t.Fatalf("expected at least 1 stored notification")
	}
	if storedList[0].JobID != jobID {
		t.Errorf("stored notification JobID = %q, want %q", storedList[0].JobID, jobID)
	}
	if storedList[0].Type != "job_accepted" {
		t.Errorf("stored notification Type = %q, want 'job_accepted'", storedList[0].Type)
	}

	// 3. Test POST /notifications/broadcast/job-alert carries job_id
	jobAlertPayload := map[string]any{
		"tenant_id":    tenantID,
		"job_id":       "job-alert-xyz-789",
		"service_name": "Express Delivery",
		"description":  "Documents pickup",
	}
	alertBytes, _ := json.Marshal(jobAlertPayload)
	reqAlert := httptest.NewRequest(http.MethodPost, "/notifications/broadcast/job-alert", bytes.NewReader(alertBytes))
	reqAlert.Header.Set("Content-Type", "application/json")
	reqAlert.Header.Set("X-Internal-Token", internalToken)
	recAlert := httptest.NewRecorder()
	mux.ServeHTTP(recAlert, reqAlert)

	if recAlert.Code != http.StatusOK {
		t.Fatalf("expected 200 OK from broadcast job alert, got %d: %s", recAlert.Code, recAlert.Body.String())
	}

	var alertResp struct {
		Notification hub.Notification `json:"notification"`
	}
	if err := json.Unmarshal(recAlert.Body.Bytes(), &alertResp); err != nil {
		t.Fatalf("unmarshal alertResp: %v", err)
	}
	if alertResp.Notification.JobID != "job-alert-xyz-789" {
		t.Errorf("expected job_id 'job-alert-xyz-789' in alert response, got %q", alertResp.Notification.JobID)
	}

	// 4. Test GET /notifications/history returns job_id in item payload
	userToken, _ := jwtutil.GenerateToken(targetUserID, "user", tenantID, "user@example.com")
	reqHistory := httptest.NewRequest(http.MethodGet, "/notifications/history?limit=10", nil)
	reqHistory.Header.Set("Authorization", "Bearer "+userToken)
	recHistory := httptest.NewRecorder()
	mux.ServeHTTP(recHistory, reqHistory)

	if recHistory.Code != http.StatusOK {
		t.Fatalf("expected 200 from history, got %d: %s", recHistory.Code, recHistory.Body.String())
	}

	var historyResp struct {
		Notifications []store.Notification `json:"notifications"`
	}
	if err := json.Unmarshal(recHistory.Body.Bytes(), &historyResp); err != nil {
		t.Fatalf("unmarshal historyResp: %v", err)
	}
	if len(historyResp.Notifications) == 0 {
		t.Fatalf("expected notifications in history")
	}
	found := false
	for _, nItem := range historyResp.Notifications {
		if nItem.JobID == jobID {
			found = true
			break
		}
	}
	if !found {
		t.Errorf("expected to find notification with job_id %q in history", jobID)
	}
}
