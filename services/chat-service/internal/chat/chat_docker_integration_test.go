package chat

import (
	"context"
	"encoding/json"
	"os"
	"testing"
	"time"

	"github.com/redis/go-redis/v9"
)

func TestRealDockerRedis_MultiInstanceChatHub(t *testing.T) {
	redisAddr := os.Getenv("REDIS_ADDR")
	if redisAddr == "" {
		redisAddr = "localhost:6380"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	rdb1 := redis.NewClient(&redis.Options{Addr: redisAddr})
	rdb2 := redis.NewClient(&redis.Options{Addr: redisAddr})
	defer rdb1.Close()
	defer rdb2.Close()

	if err := rdb1.Ping(ctx).Err(); err != nil {
		t.Skipf("Skipping real Docker Redis integration test: Redis not reachable at %s (%v)", redisAddr, err)
		return
	}

	hub1 := NewHub()
	hub1.SetRedisClient(rdb1)
	go hub1.Run()
	defer hub1.Close()

	hub2 := NewHub()
	hub2.SetRedisClient(rdb2)
	go hub2.Run()
	defer hub2.Close()

	client1 := &Client{
		ID:       "client-instance-1",
		Username: "Alice",
		Channels: make(map[string]bool),
		Send:     make(chan []byte, 10),
	}
	hub1.Register <- client1
	hub1.Subscribe(client1, "job:real-cross-test")

	client2 := &Client{
		ID:       "client-instance-2",
		Username: "Bob",
		Channels: make(map[string]bool),
		Send:     make(chan []byte, 10),
	}
	hub2.Register <- client2
	hub2.Subscribe(client2, "job:real-cross-test")

	time.Sleep(200 * time.Millisecond)

	msg := &Message{
		Channel:        "job:real-cross-test",
		SenderID:       client1.ID,
		SenderUsername: client1.Username,
		Content:        "Hello from Instance 1 across real Docker Redis!",
		Type:           "message",
	}

	hub1.Broadcast <- msg

	select {
	case data := <-client1.Send:
		var recMsg Message
		_ = json.Unmarshal(data, &recMsg)
		t.Logf("[PASS] Instance 1 local delivery: sender=%s content=%q", recMsg.SenderUsername, recMsg.Content)
	case <-time.After(2 * time.Second):
		t.Fatalf("Instance 1 local delivery failed!")
	}

	select {
	case data := <-client2.Send:
		var recMsg Message
		_ = json.Unmarshal(data, &recMsg)
		t.Logf("[PASS] Instance 2 remote delivery via Docker Redis: sender=%s content=%q", recMsg.SenderUsername, recMsg.Content)
	case <-time.After(2 * time.Second):
		t.Fatalf("Instance 2 remote Redis PubSub delivery failed!")
	}
}
