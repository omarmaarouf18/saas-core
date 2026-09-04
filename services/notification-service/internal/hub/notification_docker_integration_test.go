package hub

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/redis/go-redis/v9"
)

func TestRealDockerRedis_MultiInstanceSSEHubAndQ18Resolution(t *testing.T) {
	redisAddr := os.Getenv("REDIS_ADDR")
	if redisAddr == "" {
		redisAddr = "localhost:6380"
	}
	redisPassword := os.Getenv("REDIS_PASSWORD")
	if redisPassword == "" {
		redisPassword = "devpassword123"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	rdb1 := redis.NewClient(&redis.Options{Addr: redisAddr, Password: redisPassword})
	rdb2 := redis.NewClient(&redis.Options{Addr: redisAddr, Password: redisPassword})
	defer rdb1.Close()
	defer rdb2.Close()

	if err := rdb1.Ping(ctx).Err(); err != nil {
		t.Skipf("Skipping real Docker Redis integration test: Redis not reachable at %s (%v)", redisAddr, err)
		return
	}

	// 1. Cross-Instance PubSub Delivery Test
	sseHub1 := NewSSEHub()
	sseHub1.SetRedisClient(rdb1)
	defer sseHub1.Close()

	sseHub2 := NewSSEHub()
	sseHub2.SetRedisClient(rdb2)
	defer sseHub2.Close()

	sseClient1 := &SSEClient{
		ID:       "sse-client-instance-1",
		TenantID: "tenant-docker-cross",
		Role:     RoleOwner,
		Send:     make(chan []byte, 10),
	}
	sseHub1.Register(sseClient1)

	sseClient2 := &SSEClient{
		ID:       "sse-client-instance-2",
		TenantID: "tenant-docker-cross",
		Role:     RoleOwner,
		Send:     make(chan []byte, 10),
	}
	sseHub2.Register(sseClient2)

	notification := Notification{
		Type:     "job_alert",
		TenantID: "tenant-docker-cross",
		Title:    "New Job Assignment",
		Body:     "Job #1001 assigned",
	}

	sseHub1.Broadcast(notification)

	select {
	case data := <-sseClient1.Send:
		t.Logf("[PASS] Instance 1 SSE client received: payload=%s", string(data[:len(data)-1]))
	case <-time.After(2 * time.Second):
		t.Fatalf("Instance 1 SSE client did not receive notification!")
	}

	select {
	case data := <-sseClient2.Send:
		t.Logf("[PASS] Instance 2 SSE client received via Docker Redis: payload=%s", string(data[:len(data)-1]))
	case <-time.After(2 * time.Second):
		t.Fatalf("Instance 2 SSE client did not receive notification via Docker Redis!")
	}

	// 2. Q18 Resolution Verification: Local-First Delivery With Subscriber Loop Interruption
	t.Run("Q18 Resolution: Local delivery succeeds immediately even if subscriber loop closes", func(t *testing.T) {
		// Close sseHub1's subscriber loop connection to simulate a network glitch / subscriber hiccup
		sseHub1.mu.Lock()
		if sseHub1.pubsub != nil {
			_ = sseHub1.pubsub.Close()
		}
		sseHub1.mu.Unlock()

		notif2 := Notification{
			Type:     "status_update",
			TenantID: "tenant-docker-cross",
			Title:    "Status Update",
			Body:     "Job #1001 in progress",
		}
		sseHub1.Broadcast(notif2)

		// Local client on Instance 1 receives notification immediately via local-first in-process delivery
		select {
		case data := <-sseClient1.Send:
			t.Logf("[OBSERVED & RESOLVED] Instance 1 local client received notification via local-first path: payload=%s", string(data[:len(data)-1]))
		case <-time.After(1 * time.Second):
			t.Fatalf("Instance 1 local client should have received notification via local-first path")
		}

		// Remote client on Instance 2 still receives it via Redis Pub/Sub
		select {
		case data := <-sseClient2.Send:
			t.Logf("[OBSERVED] Instance 2 (remote) RECEIVED notification via Redis: payload=%s", string(data[:len(data)-1]))
		case <-time.After(1 * time.Second):
			t.Fatalf("Instance 2 should have received published notification")
		}
	})
}
