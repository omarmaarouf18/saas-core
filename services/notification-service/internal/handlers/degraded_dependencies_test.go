package handlers

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/alicebob/miniredis/v2"
	"github.com/project/notification-service/internal/config"
	"github.com/project/notification-service/internal/hub"
	"github.com/project/notification-service/internal/store"
	"github.com/redis/go-redis/v9"
)

// BE-HARDEN item 2: the notification-service must not panic when Redis or
// MongoDB is unreachable at startup.
//
//   - Redis down: the rate limiter has a nil client. The limiter fails closed
//     and POST /notifications/send answers 503 with the stable code
//     service_unavailable instead of panicking on the nil client.
//   - Mongo down: the store is a typed nil (*store.MongoDB). It must never
//     reach the store.Store interface; persistence is skipped and the
//     notification is still delivered live and over push.

func newSendRequest(t *testing.T, internalToken string) *http.Request {
	t.Helper()
	body, err := json.Marshal(map[string]any{
		"type":      "popup",
		"tenant_id": "tenant-1",
		"title":     "Test",
		"body":      "Hello",
	})
	if err != nil {
		t.Fatalf("marshal request body: %v", err)
	}
	req := httptest.NewRequest(http.MethodPost, "/notifications/send", bytes.NewReader(body))
	req.Header.Set("X-Internal-Token", internalToken)
	return req
}

// TestSend_RateLimiterWithoutRedis_FailsClosedWith503 covers the nil Redis
// client: no panic, the request is denied and the answer is 503 with a
// stable code.
func TestSend_RateLimiterWithoutRedis_FailsClosedWith503(t *testing.T) {
	const internalToken = "secret-internal-token"
	cfg := &config.Config{
		AuthServiceURL:       "http://localhost:3002",
		AllowedOrigin:        "http://localhost:3000",
		InternalServiceToken: internalToken,
	}

	// Redis was unreachable at startup: the limiter gets a nil client.
	n := NewNotification(hub.NewSSEHub(), nil, cfg, nil)

	rec := httptest.NewRecorder()
	n.Send(rec, newSendRequest(t, internalToken))

	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected 503 when the rate limiter has no Redis client, got %d: %s", rec.Code, rec.Body.String())
	}
	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if body["code"] != "service_unavailable" {
		t.Errorf("expected the stable code service_unavailable, got %v", body["code"])
	}
	if _, ok := body["request_id"]; !ok {
		t.Errorf("expected a request_id in the safe error body, got %v", body)
	}
}

// TestSend_TypedNilStore_SkipsPersistenceAndDelivers covers the typed nil
// store: the notification is still dispatched (live and push), nothing is
// persisted and nothing panics.
func TestSend_TypedNilStore_SkipsPersistenceAndDelivers(t *testing.T) {
	const internalToken = "secret-internal-token"
	cfg := &config.Config{
		AuthServiceURL:       "http://localhost:3002",
		AllowedOrigin:        "http://localhost:3000",
		InternalServiceToken: internalToken,
	}

	// Redis is up (only MongoDB is down in this scenario).
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	// MongoDB was unreachable at startup: mongoStore is a typed nil, exactly
	// what used to be handed to NewNotification as a store.Store.
	var mongoStore *store.MongoDB
	var typedNil store.Store = mongoStore

	sseHub := hub.NewSSEHub()
	n := NewNotification(sseHub, typedNil, cfg, rdb)

	rec := httptest.NewRecorder()
	n.Send(rec, newSendRequest(t, internalToken))

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 with a typed nil store, got %d: %s", rec.Code, rec.Body.String())
	}
	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if body["message"] != "notification dispatched" {
		t.Errorf("expected the notification to be dispatched, got %v", body["message"])
	}
}

// TestStoreUsable_TypedNilIsNotUsable pins the guard that keeps a typed nil
// out of the persistence path.
func TestStoreUsable_TypedNilIsNotUsable(t *testing.T) {
	if storeUsable(nil) {
		t.Error("a nil store must not be usable")
	}
	var mongoStore *store.MongoDB
	if storeUsable(mongoStore) {
		t.Error("a typed nil store must not be usable")
	}
}
