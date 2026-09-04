package chat

import (
	"context"
	"fmt"
	"sync"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"
)

func TestHubConcurrencyStress(t *testing.T) {
	hub := NewHub()
	go hub.Run()

	const numClients = 100
	var wg sync.WaitGroup
	wg.Add(numClients)

	// Spawn a concurrent broadcaster
	stopBroadcaster := make(chan struct{})
	go func() {
		ticker := time.NewTicker(2 * time.Millisecond)
		defer ticker.Stop()
		for {
			select {
			case <-ticker.C:
				hub.Broadcast <- &Message{
					Channel: "test-channel",
					Content: "Hello world",
				}
			case <-stopBroadcaster:
				return
			}
		}
	}()

	for i := 0; i < numClients; i++ {
		go func(idx int) {
			defer wg.Done()

			client := &Client{
				ID:       fmt.Sprintf("client-%d", idx),
				Channels: make(map[string]bool),
				Send:     make(chan []byte, 100),
			}

			// Register
			hub.Register <- client

			// Subscribe
			hub.Subscribe(client, "test-channel")

			// Do some reads from client's Send channel to consume broadcast messages
			go func() {
				for range client.Send {
					// consume
				}
			}()

			time.Sleep(10 * time.Millisecond)

			// Unsubscribe
			hub.Unsubscribe(client, "test-channel")

			// Unregister
			hub.Unregister <- client
		}(i)
	}

	wg.Wait()
	close(stopBroadcaster)

	// Poll until the hub processes final unregistrations
	deadline := time.Now().Add(2 * time.Second)
	for (hub.ClientCount() > 0 || hub.ChannelCount() > 0) && time.Now().Before(deadline) {
		time.Sleep(2 * time.Millisecond)
	}

	if hub.ClientCount() != 0 {
		t.Errorf("Expected 0 clients remaining, got %d", hub.ClientCount())
	}
	if hub.ChannelCount() != 0 {
		t.Errorf("Expected 0 channels remaining, got %d", hub.ChannelCount())
	}
}

func TestHub_MultiInstanceRedisPubSubDelivery(t *testing.T) {
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("Failed to start miniredis: %v", err)
	}
	defer mr.Close()

	rdb1 := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb1.Close()

	rdb2 := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb2.Close()

	hub1 := NewHub()
	hub1.SetRedisClient(rdb1)
	go hub1.Run()
	defer hub1.Close()

	hub2 := NewHub()
	hub2.SetRedisClient(rdb2)
	go hub2.Run()
	defer hub2.Close()

	c1OnHub1 := &Client{ID: "client-1-hub1", Channels: make(map[string]bool), Send: make(chan []byte, 10)}
	c2OnHub2 := &Client{ID: "client-2-hub2", Channels: make(map[string]bool), Send: make(chan []byte, 10)}
	c3OnHub2 := &Client{ID: "client-3-hub2-other-channel", Channels: make(map[string]bool), Send: make(chan []byte, 10)}

	hub1.Register <- c1OnHub1
	hub2.Register <- c2OnHub2
	hub2.Register <- c3OnHub2

	hub1.Subscribe(c1OnHub1, "job:456")
	hub2.Subscribe(c2OnHub2, "job:456")
	hub2.Subscribe(c3OnHub2, "job:789")

	// Allow time for dynamic Redis Pub/Sub subscription setup
	time.Sleep(100 * time.Millisecond)

	// Broadcast on Hub 1 to channel job:456
	msg := &Message{
		Channel:  "job:456",
		SenderID: "client-1-hub1",
		Content:  "Cross-instance WebSocket chat test",
	}
	hub1.Broadcast <- msg

	// 1. Verify c1OnHub1 (origin hub) receives message immediately
	select {
	case data := <-c1OnHub1.Send:
		if len(data) == 0 {
			t.Errorf("c1OnHub1 should have received message")
		}
	case <-time.After(1 * time.Second):
		t.Errorf("c1OnHub1 on Hub 1 timed out waiting for local message")
	}

	// 2. Verify c2OnHub2 (remote hub, same channel job:456) receives message via Redis Pub/Sub
	select {
	case data := <-c2OnHub2.Send:
		if len(data) == 0 {
			t.Errorf("c2OnHub2 should have received message")
		}
	case <-time.After(1 * time.Second):
		t.Errorf("c2OnHub2 on Hub 2 timed out waiting for cross-instance message via Redis Pub/Sub")
	}

	// 3. Verify c3OnHub2 (remote hub, different channel job:789) does NOT receive message
	select {
	case <-c3OnHub2.Send:
		t.Errorf("c3OnHub2 in channel job:789 should NOT receive message addressed to job:456")
	default:
	}

	// Clean up subscriptions
	hub1.Unsubscribe(c1OnHub1, "job:456")
	hub2.Unsubscribe(c2OnHub2, "job:456")
	hub2.Unsubscribe(c3OnHub2, "job:789")

	hub1.Unregister <- c1OnHub1
	hub2.Unregister <- c2OnHub2
	hub2.Unregister <- c3OnHub2
}

func TestHub_AccountSuspended_ForceClosesConnection_F03(t *testing.T) {
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()

	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	h := NewHub()
	go h.Run()
	defer h.Close()

	h.SetRedisClient(rdb)

	client := &Client{
		ID:       "suspended-user-123",
		Channels: make(map[string]bool),
		Send:     make(chan []byte, 10),
	}

	h.Register <- client

	// Give register a brief moment to process
	time.Sleep(50 * time.Millisecond)
	if h.ClientCount() != 1 {
		t.Fatalf("expected 1 client registered, got %d", h.ClientCount())
	}

	// Publish ACCOUNT_SUSPENDED event via Redis
	pubPayload := `{"action":"ACCOUNT_SUSPENDED","user_id":"suspended-user-123"}`
	if err := rdb.Publish(context.Background(), "account:events", pubPayload).Err(); err != nil {
		t.Fatalf("failed to publish suspension event: %v", err)
	}

	// Verify client Send channel is closed
	select {
	case _, ok := <-client.Send:
		if ok {
			t.Errorf("expected client.Send channel to be closed on suspension, but received value")
		}
	case <-time.After(2 * time.Second):
		t.Fatalf("timed out waiting for client.Send channel to be closed after ACCOUNT_SUSPENDED event")
	}

	// Verify client count dropped to 0
	if h.ClientCount() != 0 {
		t.Errorf("expected 0 clients in hub after suspension disconnect, got %d", h.ClientCount())
	}
}
