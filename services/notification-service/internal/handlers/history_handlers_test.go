package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/project/notification-service/internal/config"
	"github.com/project/notification-service/internal/hub"
	"github.com/project/notification-service/internal/store"
	"github.com/project/shared/infra/jwtutil"
	"github.com/redis/go-redis/v9"
)

type memoryStore struct {
	mu            sync.Mutex
	notifications []store.Notification
}

func newMemoryStore() *memoryStore {
	return &memoryStore{
		notifications: make([]store.Notification, 0),
	}
}

func (m *memoryStore) InsertNotification(ctx context.Context, notif *store.Notification) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if notif.ID == "" {
		notif.ID = fmt.Sprintf("notif-%d", time.Now().UnixNano())
	}
	if notif.Timestamp.IsZero() {
		notif.Timestamp = time.Now().UTC()
	}
	m.notifications = append(m.notifications, *notif)
	return nil
}

func (m *memoryStore) ListForUser(ctx context.Context, tenantID, userID string, roles []string, limit int, before *time.Time) ([]store.Notification, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	var matched []store.Notification
	for _, n := range m.notifications {
		// Tenant check
		if n.TenantID != tenantID && !n.Global {
			continue
		}
		// Recipient check
		isDirect := n.UserID == userID
		for _, uid := range n.UserIDs {
			if uid == userID {
				isDirect = true
				break
			}
		}
		isRole := false
		for _, r := range roles {
			for _, nr := range n.Roles {
				if nr == r {
					isRole = true
					break
				}
			}
		}
		isBroadcastAll := (n.UserID == "" && len(n.UserIDs) == 0 && len(n.Roles) == 0)

		if !isDirect && !isRole && !isBroadcastAll {
			continue
		}

		if before != nil && !before.IsZero() && !n.Timestamp.Before(*before) {
			continue
		}

		matched = append(matched, n)
	}

	// Sort newest first
	for i := 0; i < len(matched); i++ {
		for j := i + 1; j < len(matched); j++ {
			if matched[i].Timestamp.Before(matched[j].Timestamp) {
				matched[i], matched[j] = matched[j], matched[i]
			}
		}
	}

	if limit > 0 && len(matched) > limit {
		matched = matched[:limit]
	}
	return matched, nil
}

func (m *memoryStore) MarkRead(ctx context.Context, tenantID, userID, notificationID string) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	for i, n := range m.notifications {
		if n.ID == notificationID {
			if n.TenantID != tenantID && !n.Global {
				return store.ErrNotFound
			}
			if n.UserID != "" && n.UserID != userID {
				return store.ErrNotFound
			}
			m.notifications[i].IsRead = true
			return nil
		}
	}
	return store.ErrNotFound
}

func (m *memoryStore) MarkAllRead(ctx context.Context, tenantID, userID string) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	for i, n := range m.notifications {
		if n.TenantID == tenantID || n.Global {
			if n.UserID == "" || n.UserID == userID {
				m.notifications[i].IsRead = true
			}
		}
	}
	return nil
}

func (m *memoryStore) Delete(ctx context.Context, tenantID, userID, notificationID string) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	for i, n := range m.notifications {
		if n.ID == notificationID {
			if n.TenantID != tenantID && !n.Global {
				return store.ErrNotFound
			}
			if n.UserID != "" && n.UserID != userID {
				return store.ErrNotFound
			}
			m.notifications = append(m.notifications[:i], m.notifications[i+1:]...)
			return nil
		}
	}
	return store.ErrNotFound
}

func (m *memoryStore) DeleteAll(ctx context.Context, tenantID, userID string) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	remaining := make([]store.Notification, 0)
	for _, n := range m.notifications {
		if (n.TenantID == tenantID || n.Global) && (n.UserID == "" || n.UserID == userID) {
			continue // deleted
		}
		remaining = append(remaining, n)
	}
	m.notifications = remaining
	return nil
}

func (m *memoryStore) Close(ctx context.Context) error {
	return nil
}

func setupHandlerTestContext(t *testing.T) (*Notification, *memoryStore, *http.ServeMux, string, string) {
	jwtutil.Init("z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")

	mockAuth := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		id := r.URL.Query().Get("id")
		tenant := "tenant-alice"
		role := "client"
		if id == "user-bob" {
			tenant = "tenant-bob"
			role = "owner"
		} else if id == "user-eve" {
			tenant = "tenant-alice"
			role = "client"
		}
		json.NewEncoder(w).Encode(map[string]any{
			"id":        id,
			"role":      role,
			"is_active": true,
			"tenant_id": tenant,
		})
	}))
	t.Cleanup(mockAuth.Close)

	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	t.Cleanup(mr.Close)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	t.Cleanup(func() { _ = rdb.Close() })

	sseHub := hub.NewSSEHub()
	memStore := newMemoryStore()

	cfg := &config.Config{
		AuthServiceURL:       mockAuth.URL,
		AllowedOrigin:        "http://localhost:3000",
		InternalServiceToken: "secret-internal-token",
	}

	n := NewNotification(sseHub, memStore, cfg, rdb)
	mux := http.NewServeMux()
	n.RegisterRoutes(mux)

	tokenAlice, _ := jwtutil.GenerateToken("user-alice", "client", "tenant-alice", "alice@example.com")
	tokenBob, _ := jwtutil.GenerateToken("user-bob", "owner", "tenant-bob", "bob@example.com")

	return n, memStore, mux, tokenAlice, tokenBob
}

func TestHistoryEndpoint_AuthAndErrors(t *testing.T) {
	_, _, mux, tokenAlice, _ := setupHandlerTestContext(t)

	// 1. Missing Authorization header -> 401
	req := httptest.NewRequest("GET", "/notifications/history", nil)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Errorf("Expected 401 for missing auth header, got %d", rec.Code)
	}

	// 2. Invalid header format -> 401
	req = httptest.NewRequest("GET", "/notifications/history", nil)
	req.Header.Set("Authorization", "Basic 12345")
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Errorf("Expected 401 for non-Bearer auth header, got %d", rec.Code)
	}

	// 3. Empty Bearer token -> 401
	req = httptest.NewRequest("GET", "/notifications/history", nil)
	req.Header.Set("Authorization", "Bearer ")
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Errorf("Expected 401 for empty Bearer token, got %d", rec.Code)
	}

	// 4. Invalid Bearer token -> 401
	req = httptest.NewRequest("GET", "/notifications/history", nil)
	req.Header.Set("Authorization", "Bearer invalid.jwt.token")
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Errorf("Expected 401 for invalid JWT, got %d", rec.Code)
	}

	// 5. Method not allowed (POST on /notifications/history) -> 405
	req = httptest.NewRequest("POST", "/notifications/history", nil)
	req.Header.Set("Authorization", "Bearer "+tokenAlice)
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusMethodNotAllowed {
		t.Errorf("Expected 405 for POST /notifications/history, got %d", rec.Code)
	}
}

func TestHistoryEndpoint_PaginationAndIsolation(t *testing.T) {
	_, memStore, mux, tokenAlice, tokenBob := setupHandlerTestContext(t)

	now := time.Now().UTC()
	// Populate items for Alice (tenant-alice)
	for i := 1; i <= 5; i++ {
		_ = memStore.InsertNotification(context.Background(), &store.Notification{
			ID:        fmt.Sprintf("notif-alice-%d", i),
			TenantID:  "tenant-alice",
			UserID:    "user-alice",
			Title:     fmt.Sprintf("Alice Notification %d", i),
			Body:      "Details",
			Timestamp: now.Add(time.Duration(i) * time.Minute),
		})
	}

	// Populate item for Bob (tenant-bob)
	_ = memStore.InsertNotification(context.Background(), &store.Notification{
		ID:        "notif-bob-1",
		TenantID:  "tenant-bob",
		UserID:    "user-bob",
		Title:     "Bob Notification 1",
		Body:      "Details Bob",
		Timestamp: now.Add(10 * time.Minute),
	})

	// Alice queries history -> must see Alice's 5 items, newest first, and NEVER Bob's items
	req := httptest.NewRequest("GET", "/notifications/history?limit=3", nil)
	req.Header.Set("Authorization", "Bearer "+tokenAlice)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	var resp struct {
		Notifications []store.Notification `json:"notifications"`
		HasMore       bool                 `json:"has_more"`
	}
	if err := json.NewDecoder(rec.Body).Decode(&resp); err != nil {
		t.Fatalf("Failed to decode response: %v", err)
	}

	if len(resp.Notifications) != 3 {
		t.Fatalf("Expected 3 items on page 1, got %d", len(resp.Notifications))
	}
	if !resp.HasMore {
		t.Errorf("Expected has_more=true")
	}
	if resp.Notifications[0].ID != "notif-alice-5" || resp.Notifications[1].ID != "notif-alice-4" {
		t.Fatalf("Unexpected ordering: %+v", resp.Notifications)
	}

	// Cross-tenant verification: verify Bob does not see Alice's notifications
	reqBob := httptest.NewRequest("GET", "/notifications/history", nil)
	reqBob.Header.Set("Authorization", "Bearer "+tokenBob)
	recBob := httptest.NewRecorder()
	mux.ServeHTTP(recBob, reqBob)

	var respBob struct {
		Notifications []store.Notification `json:"notifications"`
	}
	_ = json.NewDecoder(recBob.Body).Decode(&respBob)
	if len(respBob.Notifications) != 1 || respBob.Notifications[0].ID != "notif-bob-1" {
		t.Fatalf("Bob saw unauthorized notifications: %+v", respBob.Notifications)
	}
}

func TestMarkReadEndpoint(t *testing.T) {
	_, memStore, mux, tokenAlice, tokenBob := setupHandlerTestContext(t)

	_ = memStore.InsertNotification(context.Background(), &store.Notification{
		ID:        "item-to-read",
		TenantID:  "tenant-alice",
		UserID:    "user-alice",
		Title:     "Please read",
		IsRead:    false,
		Timestamp: time.Now().UTC(),
	})

	// 1. Missing auth -> 401
	req := httptest.NewRequest("POST", "/notifications/item-to-read/read", nil)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Errorf("Expected 401 for unauthenticated mark-read, got %d", rec.Code)
	}

	// 2. Cross-tenant attempt (Bob tries to mark Alice's notification read) -> 404
	req = httptest.NewRequest("POST", "/notifications/item-to-read/read", nil)
	req.Header.Set("Authorization", "Bearer "+tokenBob)
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusNotFound {
		t.Errorf("Expected 404 for cross-tenant mark-read, got %d", rec.Code)
	}

	// 3. Legitimate user (Alice) marks it read -> 200
	req = httptest.NewRequest("POST", "/notifications/item-to-read/read", nil)
	req.Header.Set("Authorization", "Bearer "+tokenAlice)
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// Verify status in store
	aliceItems, _ := memStore.ListForUser(context.Background(), "tenant-alice", "user-alice", nil, 10, nil)
	if len(aliceItems) != 1 || !aliceItems[0].IsRead {
		t.Fatalf("Expected is_read=true in store, got: %+v", aliceItems)
	}
}

func TestReadAllEndpoint(t *testing.T) {
	_, memStore, mux, tokenAlice, _ := setupHandlerTestContext(t)

	_ = memStore.InsertNotification(context.Background(), &store.Notification{
		ID:        "alice-unread-1",
		TenantID:  "tenant-alice",
		UserID:    "user-alice",
		IsRead:    false,
		Timestamp: time.Now().UTC(),
	})
	_ = memStore.InsertNotification(context.Background(), &store.Notification{
		ID:        "bob-unread-1",
		TenantID:  "tenant-bob",
		UserID:    "user-bob",
		IsRead:    false,
		Timestamp: time.Now().UTC(),
	})

	// Alice calls POST /notifications/read-all
	req := httptest.NewRequest("POST", "/notifications/read-all", nil)
	req.Header.Set("Authorization", "Bearer "+tokenAlice)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK, got %d", rec.Code)
	}

	// Verify Alice's item is read, Bob's item remains unread
	aItems, _ := memStore.ListForUser(context.Background(), "tenant-alice", "user-alice", nil, 10, nil)
	if len(aItems) != 1 || !aItems[0].IsRead {
		t.Errorf("Alice's notification should be read")
	}

	bItems, _ := memStore.ListForUser(context.Background(), "tenant-bob", "user-bob", nil, 10, nil)
	if len(bItems) != 1 || bItems[0].IsRead {
		t.Errorf("Bob's notification should remain unread!")
	}
}

func TestDeleteEndpoints(t *testing.T) {
	_, memStore, mux, tokenAlice, tokenBob := setupHandlerTestContext(t)

	_ = memStore.InsertNotification(context.Background(), &store.Notification{
		ID:        "alice-del-1",
		TenantID:  "tenant-alice",
		UserID:    "user-alice",
		Timestamp: time.Now().UTC(),
	})
	_ = memStore.InsertNotification(context.Background(), &store.Notification{
		ID:        "alice-del-2",
		TenantID:  "tenant-alice",
		UserID:    "user-alice",
		Timestamp: time.Now().UTC(),
	})
	_ = memStore.InsertNotification(context.Background(), &store.Notification{
		ID:        "bob-stay-1",
		TenantID:  "tenant-bob",
		UserID:    "user-bob",
		Timestamp: time.Now().UTC(),
	})

	// 1. Bob attempts DELETE /notifications/alice-del-1 -> 404
	req := httptest.NewRequest("DELETE", "/notifications/alice-del-1", nil)
	req.Header.Set("Authorization", "Bearer "+tokenBob)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusNotFound {
		t.Errorf("Expected 404 for cross-tenant DELETE, got %d", rec.Code)
	}

	// 2. Alice deletes alice-del-1 -> 200
	req = httptest.NewRequest("DELETE", "/notifications/alice-del-1", nil)
	req.Header.Set("Authorization", "Bearer "+tokenAlice)
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK for DELETE /notifications/{id}, got %d", rec.Code)
	}

	// 3. Alice clears all notifications -> DELETE /notifications
	req = httptest.NewRequest("DELETE", "/notifications", nil)
	req.Header.Set("Authorization", "Bearer "+tokenAlice)
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK for DELETE /notifications, got %d", rec.Code)
	}

	// Alice has 0 notifications
	aItems, _ := memStore.ListForUser(context.Background(), "tenant-alice", "user-alice", nil, 10, nil)
	if len(aItems) != 0 {
		t.Errorf("Expected 0 notifications for Alice, got %d", len(aItems))
	}

	// Bob still has bob-stay-1
	bItems, _ := memStore.ListForUser(context.Background(), "tenant-bob", "user-bob", nil, 10, nil)
	if len(bItems) != 1 || bItems[0].ID != "bob-stay-1" {
		t.Errorf("Bob's notification was affected by Alice's DELETE! Items: %+v", bItems)
	}
}

func TestSendAndBroadcastJobAlert_Persistence(t *testing.T) {
	_, memStore, mux, _, _ := setupHandlerTestContext(t)

	// 1. Send pushes notification and persists into store
	sendPayload := map[string]any{
		"type":      "system",
		"tenant_id": "tenant-alice",
		"user_id":   "user-alice",
		"title":     "System notice",
		"body":      "Maintenance at midnight",
	}
	sendBytes, _ := json.Marshal(sendPayload)
	req := httptest.NewRequest("POST", "/notifications/send", bytes.NewReader(sendBytes))
	req.Header.Set("X-Internal-Token", "secret-internal-token")
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK for /notifications/send, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// Verify item was persisted
	items, err := memStore.ListForUser(context.Background(), "tenant-alice", "user-alice", nil, 10, nil)
	if err != nil || len(items) != 1 || items[0].Title != "System notice" {
		t.Fatalf("Expected persisted notification in store, got: %+v, err: %v", items, err)
	}

	// 2. BroadcastJobAlert pushes alert and persists into store
	jobAlertPayload := map[string]any{
		"tenant_id":    "tenant-alice",
		"job_id":       "job-12345",
		"employee_id":  "user-alice",
		"service_name": "Delivery",
		"description":  "Urgent parcel",
	}
	alertBytes, _ := json.Marshal(jobAlertPayload)
	reqAlert := httptest.NewRequest("POST", "/notifications/broadcast/job-alert", bytes.NewReader(alertBytes))
	reqAlert.Header.Set("X-Internal-Token", "secret-internal-token")
	recAlert := httptest.NewRecorder()
	mux.ServeHTTP(recAlert, reqAlert)

	if recAlert.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK for /notifications/broadcast/job-alert, got %d. Body: %s", recAlert.Code, recAlert.Body.String())
	}

	// Verify job alert was persisted
	itemsAfter, _ := memStore.ListForUser(context.Background(), "tenant-alice", "user-alice", nil, 10, nil)
	if len(itemsAfter) != 2 {
		t.Fatalf("Expected 2 persisted notifications, got %d", len(itemsAfter))
	}
}

// TestManualVerificationNarrative verifies the exact manual workflow:
// Send via POST /notifications/send -> Retrieve via GET /notifications/history (no SSE connected) ->
// Mark read via POST /notifications/{id}/read -> Confirm GET /notifications/history reflects is_read: true ->
// Delete via DELETE /notifications/{id} -> Confirm GET /notifications/history is empty.
func TestManualVerificationNarrative(t *testing.T) {
	_, _, mux, tokenAlice, _ := setupHandlerTestContext(t)

	// Step 1: Send notification via POST /notifications/send
	sendPayload := map[string]any{
		"type":      "system",
		"tenant_id": "tenant-alice",
		"user_id":   "user-alice",
		"title":     "Urgent Account Update",
		"body":      "Your billing profile has been updated successfully.",
	}
	sendBytes, _ := json.Marshal(sendPayload)
	sendReq := httptest.NewRequest("POST", "/notifications/send", bytes.NewReader(sendBytes))
	sendReq.Header.Set("X-Internal-Token", "secret-internal-token")
	sendRec := httptest.NewRecorder()
	mux.ServeHTTP(sendRec, sendReq)

	if sendRec.Code != http.StatusOK {
		t.Fatalf("POST /notifications/send failed: %d %s", sendRec.Code, sendRec.Body.String())
	}
	var sendResp struct {
		Notification store.Notification `json:"notification"`
	}
	_ = json.NewDecoder(sendRec.Body).Decode(&sendResp)
	notifID := sendResp.Notification.ID
	if notifID == "" {
		t.Fatalf("Expected non-empty notification ID in send response")
	}
	t.Logf("[Step 1 OK] Sent notification ID=%s", notifID)

	// Step 2: Retrieve via GET /notifications/history WITHOUT any active SSE stream
	histReq := httptest.NewRequest("GET", "/notifications/history", nil)
	histReq.Header.Set("Authorization", "Bearer "+tokenAlice)
	histRec := httptest.NewRecorder()
	mux.ServeHTTP(histRec, histReq)

	if histRec.Code != http.StatusOK {
		t.Fatalf("GET /notifications/history failed: %d %s", histRec.Code, histRec.Body.String())
	}
	var histResp struct {
		Notifications []store.Notification `json:"notifications"`
		HasMore       bool                 `json:"has_more"`
	}
	_ = json.NewDecoder(histRec.Body).Decode(&histResp)
	if len(histResp.Notifications) != 1 {
		t.Fatalf("Expected 1 notification in history, got %d", len(histResp.Notifications))
	}
	if histResp.Notifications[0].ID != notifID {
		t.Fatalf("Expected notification %s, got %s", notifID, histResp.Notifications[0].ID)
	}
	if histResp.Notifications[0].IsRead {
		t.Fatalf("Expected notification to be initially unread (is_read=false)")
	}
	t.Logf("[Step 2 OK] Retrieved from history without active SSE: ID=%s, IsRead=%v", notifID, histResp.Notifications[0].IsRead)

	// Step 3: Mark read via POST /notifications/{id}/read
	readReq := httptest.NewRequest("POST", fmt.Sprintf("/notifications/%s/read", notifID), nil)
	readReq.Header.Set("Authorization", "Bearer "+tokenAlice)
	readRec := httptest.NewRecorder()
	mux.ServeHTTP(readRec, readReq)

	if readRec.Code != http.StatusOK {
		t.Fatalf("POST /notifications/%s/read failed: %d %s", notifID, readRec.Code, readRec.Body.String())
	}
	t.Logf("[Step 3 OK] Marked notification as read: ID=%s", notifID)

	// Step 4: Confirm GET /notifications/history reflects is_read: true
	histReq2 := httptest.NewRequest("GET", "/notifications/history", nil)
	histReq2.Header.Set("Authorization", "Bearer "+tokenAlice)
	histRec2 := httptest.NewRecorder()
	mux.ServeHTTP(histRec2, histReq2)

	var histResp2 struct {
		Notifications []store.Notification `json:"notifications"`
	}
	_ = json.NewDecoder(histRec2.Body).Decode(&histResp2)
	if len(histResp2.Notifications) != 1 || !histResp2.Notifications[0].IsRead {
		t.Fatalf("Expected is_read=true in history response, got: %+v", histResp2.Notifications)
	}
	t.Logf("[Step 4 OK] Confirmed GET /notifications/history reflects is_read=true")

	// Step 5: Delete notification via DELETE /notifications/{id}
	delReq := httptest.NewRequest("DELETE", fmt.Sprintf("/notifications/%s", notifID), nil)
	delReq.Header.Set("Authorization", "Bearer "+tokenAlice)
	delRec := httptest.NewRecorder()
	mux.ServeHTTP(delRec, delReq)

	if delRec.Code != http.StatusOK {
		t.Fatalf("DELETE /notifications/%s failed: %d %s", notifID, delRec.Code, delRec.Body.String())
	}
	t.Logf("[Step 5 OK] Deleted notification ID=%s", notifID)

	// Step 6: Confirm history is now empty
	histReq3 := httptest.NewRequest("GET", "/notifications/history", nil)
	histReq3.Header.Set("Authorization", "Bearer "+tokenAlice)
	histRec3 := httptest.NewRecorder()
	mux.ServeHTTP(histRec3, histReq3)

	var histResp3 struct {
		Notifications []store.Notification `json:"notifications"`
	}
	_ = json.NewDecoder(histRec3.Body).Decode(&histResp3)
	if len(histResp3.Notifications) != 0 {
		t.Fatalf("Expected 0 notifications in history after delete, got %d", len(histResp3.Notifications))
	}
	t.Logf("[Step 6 OK] Confirmed GET /notifications/history is empty after delete")
}
