package hub

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"
)

// TestQ18_LocalFirstDelivery_SucceedsDespiteSubscriberHiccup verifies that
// local delivery is local-first in-process and does not rely on Redis Pub/Sub loopback.
// Even if the subscriber loop has closed or lagged, local clients on the origin instance
// receive the notification immediately.
func TestQ18_LocalFirstDelivery_SucceedsDespiteSubscriberHiccup(t *testing.T) {
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("Failed to start miniredis: %v", err)
	}
	defer mr.Close()

	rdbA := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdbA.Close()

	hubA := NewSSEHub()
	defer hubA.Close()
	hubA.SetRedisClient(rdbA)

	clientA := &SSEClient{
		ID:       "client-A-local",
		TenantID: "tenant-q18",
		Role:     RoleOwner,
		Send:     make(chan []byte, 10),
	}
	hubA.Register(clientA)

	// Simulate subscriber connection hiccup: close subscriber connection while rdb client is still active
	hubA.mu.Lock()
	if hubA.pubsub != nil {
		_ = hubA.pubsub.Close()
	}
	hubA.mu.Unlock()

	// Broadcast notification on Instance A
	notif := Notification{
		ID:        "notif-q18-local",
		Type:      "popup",
		TenantID:  "tenant-q18",
		Title:     "Local Alert",
		Body:      "Dispatched locally on Instance A",
		Timestamp: time.Now().UTC(),
	}
	hubA.Broadcast(notif)

	// Local-first delivery guarantees clientA on Instance A receives the message immediately
	select {
	case msg := <-clientA.Send:
		t.Logf("[PASS] Local-first delivery succeeded immediately despite subscriber hiccup: %s", string(msg))
	case <-time.After(500 * time.Millisecond):
		t.Fatalf("Local client on Instance A failed to receive notification!")
	}
}

// TestQ18_CrossInstanceDelivery_And_OriginDedup verifies that:
// 1. Instance A delivers locally to clientA in-process.
// 2. Instance A publishes to Redis tagged with its OriginInstanceID.
// 3. When Redis loops back to Instance A, Instance A deduplicates and does NOT send a second copy.
// 4. Instance B receives the Redis publication and delivers it to clientB.
func TestQ18_CrossInstanceDelivery_And_OriginDedup(t *testing.T) {
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("Failed to start miniredis: %v", err)
	}
	defer mr.Close()

	rdbA := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdbA.Close()

	rdbB := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdbB.Close()

	hubA := NewSSEHub()
	hubA.SetRedisClient(rdbA)
	defer hubA.Close()

	hubB := NewSSEHub()
	hubB.SetRedisClient(rdbB)
	defer hubB.Close()

	clientA := &SSEClient{
		ID:       "client-A",
		TenantID: "tenant-q18",
		Role:     RoleOwner,
		Send:     make(chan []byte, 10),
	}
	hubA.Register(clientA)

	clientB := &SSEClient{
		ID:       "client-B",
		TenantID: "tenant-q18",
		Role:     RoleOwner,
		Send:     make(chan []byte, 10),
	}
	hubB.Register(clientB)

	// Hub A broadcasts a notification
	notif := Notification{
		ID:        "notif-q18-dedup",
		Type:      "job_alert",
		TenantID:  "tenant-q18",
		Title:     "Cross-Instance Job Alert",
		Body:      "Dispatched from Instance A",
		Timestamp: time.Now().UTC(),
	}
	hubA.Broadcast(notif)

	// 1. Verify clientA received notification immediately
	select {
	case msg := <-clientA.Send:
		t.Logf("[PASS] clientA received local delivery: %s", string(msg))
	case <-time.After(500 * time.Millisecond):
		t.Fatalf("clientA on Instance A missed local notification")
	}

	// 2. Verify clientB on remote Instance B received notification via Redis Pub/Sub
	select {
	case msg := <-clientB.Send:
		t.Logf("[PASS] clientB received cross-instance delivery: %s", string(msg))
	case <-time.After(1 * time.Second):
		t.Fatalf("clientB on Instance B missed cross-instance notification via Redis")
	}

	// 3. Verify clientA does NOT receive a duplicate message from Redis pub/sub echo
	time.Sleep(100 * time.Millisecond)
	select {
	case extra := <-clientA.Send:
		t.Fatalf("clientA received duplicate notification from Redis pub/sub echo: %s", string(extra))
	default:
		t.Logf("[PASS] clientA did not receive duplicate message (origin-ID deduplication verified)")
	}
}

// TestQ18_StartupWindowRace_ClosedByReadiness verifies that when an SSE connection
// is established while Redis subscription is in-flight, WaitForReady closes the
// startup-window race: the handshake does not consider the connection ready until
// the subscription is confirmed active on Redis. Consequently, a notification published
// by simulated Instance B right as the connection opens is successfully received.
func TestQ18_StartupWindowRace_ClosedByReadiness(t *testing.T) {
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("Failed to start miniredis: %v", err)
	}
	defer mr.Close()

	rdbA := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdbA.Close()

	rdbB := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdbB.Close()

	hubA := NewSSEHub()
	defer hubA.Close()

	// Asynchronously connect Redis to simulate startup subscription handshake in flight
	go hubA.SetRedisClient(rdbA)

	// Ensure SetRedisClient goroutine has initialized hubA.rdb before WaitForReady checks it
	for i := 0; i < 100; i++ {
		hubA.mu.RLock()
		rdbSet := hubA.rdb != nil
		hubA.mu.RUnlock()
		if rdbSet {
			break
		}
		time.Sleep(1 * time.Millisecond)
	}

	clientA := &SSEClient{
		ID:       "client-A-startup",
		TenantID: "tenant-q18",
		Role:     RoleOwner,
		Send:     make(chan []byte, 10),
	}

	// Wait for subscription readiness before considering connection ready
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	if err := hubA.WaitForReady(ctx); err != nil {
		t.Fatalf("WaitForReady failed: %v", err)
	}
	hubA.Register(clientA)

	// Simulated Instance B publishes a notification immediately
	notif := Notification{
		ID:        "notif-q18-startup-success",
		Type:      "job_alert",
		TenantID:  "tenant-q18",
		Title:     "Startup Window Closed",
		Body:      "Dispatched from Instance B",
		Timestamp: time.Now().UTC(),
	}
	data, err := json.Marshal(notif)
	if err != nil {
		t.Fatalf("Failed to marshal notification: %v", err)
	}

	publishRes := rdbB.Publish(context.Background(), "notify:tenant:tenant-q18", data)
	if publishRes.Err() != nil {
		t.Fatalf("Instance B publish failed: %v", publishRes.Err())
	}
	subCount, err := publishRes.Result()
	if err != nil {
		t.Fatalf("Failed to get publish result: %v", err)
	}
	if subCount == 0 {
		t.Fatalf("Expected Redis to have active subscribers, got 0")
	}
	t.Logf("Redis confirmed %d active subscribers at publish time", subCount)

	// Verify clientA successfully received the notification
	select {
	case msg := <-clientA.Send:
		t.Logf("[PASS] clientA received notification in previously-failing scenario: %s", string(msg))
	case <-time.After(1 * time.Second):
		t.Fatalf("clientA missed notification; startup-window race was not resolved")
	}
}
