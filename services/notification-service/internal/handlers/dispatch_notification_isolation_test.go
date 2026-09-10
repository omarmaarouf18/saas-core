package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/project/notification-service/internal/config"
	"github.com/project/notification-service/internal/hub"
	"github.com/redis/go-redis/v9"
)

// TestRepro_N01_SSEHubIgnoresUserID_BroadcastsPrivateOfferToAllEmployees verifies
// that a private job offer targeted at courier A is ONLY received by courier A,
// and NOT received by courier B.
func TestRepro_N01_SSEHubIgnoresUserID_BroadcastsPrivateOfferToAllEmployees(t *testing.T) {
	sHub := hub.NewSSEHub()
	defer sHub.Close()

	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	internalToken := "test-internal-token"
	cfg := &config.Config{
		InternalServiceToken: internalToken,
	}
	memStore := newMemoryStore()
	n := NewNotification(sHub, memStore, cfg, rdb)

	tenantID := "tenant-n01"
	empA := "courier-A"
	empB := "courier-B"

	// Register 2 employee clients connected to SSE under the same tenant
	clientA := &hub.SSEClient{
		ID:       "conn-A",
		UserID:   empA,
		TenantID: tenantID,
		Role:     hub.RoleEmployee,
		Send:     make(chan []byte, 10),
	}
	clientB := &hub.SSEClient{
		ID:       "conn-B",
		UserID:   empB,
		TenantID: tenantID,
		Role:     hub.RoleEmployee,
		Send:     make(chan []byte, 10),
	}

	sHub.Register(clientA)
	sHub.Register(clientB)
	defer sHub.Unregister(clientA)
	defer sHub.Unregister(clientB)

	// Dispatch targeted job offer notification payload (as constructed by sendJobOfferNotification)
	jobOfferPayload := map[string]any{
		"type":      "job_offer",
		"tenant_id": tenantID,
		"user_id":   empA, // strictly targeted at courier A
		"title":     "New Job Offer",
		"body":      "You have an incoming job offer for job job-101. Respond within 60 seconds.",
		"roles":     []string{"employee"},
	}
	bodyBytes, _ := json.Marshal(jobOfferPayload)

	req := httptest.NewRequest("POST", "/notifications/send", bytes.NewReader(bodyBytes))
	req.Header.Set("X-Internal-Token", internalToken)
	rec := httptest.NewRecorder()

	n.Send(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK from /notifications/send, got %d: %s", rec.Code, rec.Body.String())
	}

	readSSE := func(ch chan []byte) string {
		select {
		case msg := <-ch:
			return string(msg)
		case <-time.After(150 * time.Millisecond):
			return ""
		}
	}

	msgA := readSSE(clientA.Send)
	msgB := readSSE(clientB.Send)

	if msgA == "" {
		t.Fatalf("Expected Courier A to receive private job offer SSE notification, but received nothing")
	}

	// N-01 Assertion: Courier B MUST NOT receive courier A's private job offer
	if msgB != "" {
		t.Fatalf("N-01 REPRO FAILED (BUG CONFIRMED): Courier B received private job offer targeted at Courier A: %s", msgB)
	}
}

// TestRepro_N02_NotificationHistoryQueryLeaksOtherCouriersOffers verifies
// that courier B's notification history query does NOT return courier A's private job offer.
func TestRepro_N02_NotificationHistoryQueryLeaksOtherCouriersOffers(t *testing.T) {
	sHub := hub.NewSSEHub()
	defer sHub.Close()

	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	internalToken := "test-internal-token"
	cfg := &config.Config{
		InternalServiceToken: internalToken,
	}
	memStore := newMemoryStore()
	n := NewNotification(sHub, memStore, cfg, rdb)

	tenantID := "tenant-n02"
	empA := "courier-A"
	empB := "courier-B"

	// Dispatch targeted job offer for courier A
	jobOfferPayload := map[string]any{
		"type":      "job_offer",
		"tenant_id": tenantID,
		"user_id":   empA, // strictly intended for courier A
		"title":     "New Job Offer",
		"body":      "You have an incoming job offer for job job-101. Respond within 60 seconds.",
		"roles":     []string{"employee"},
	}
	bodyBytes, _ := json.Marshal(jobOfferPayload)

	req := httptest.NewRequest("POST", "/notifications/send", bytes.NewReader(bodyBytes))
	req.Header.Set("X-Internal-Token", internalToken)
	rec := httptest.NewRecorder()
	n.Send(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK from /notifications/send, got %d: %s", rec.Code, rec.Body.String())
	}

	// Courier B queries history with role "employee"
	notifsForB, err := memStore.ListForUser(context.Background(), tenantID, empB, []string{"employee"}, 10, nil)
	if err != nil {
		t.Fatalf("ListForUser failed: %v", err)
	}

	// N-02 Assertion: Courier B's history must NOT contain courier A's private job offer
	if len(notifsForB) > 0 {
		t.Fatalf("N-02 REPRO FAILED (BUG CONFIRMED): Courier B sees Courier A's private job offer in history: count=%d, first=%+v", len(notifsForB), notifsForB[0])
	}

	// Courier A queries history - should see their job offer
	notifsForA, err := memStore.ListForUser(context.Background(), tenantID, empA, []string{"employee"}, 10, nil)
	if err != nil {
		t.Fatalf("ListForUser failed: %v", err)
	}
	if len(notifsForA) != 1 {
		t.Fatalf("Expected Courier A to see exactly 1 notification in history, got %d", len(notifsForA))
	}
}
