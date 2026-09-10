package chat

import (
	"fmt"
	"sync"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"
)

func TestClient_CloseSend_Idempotent(t *testing.T) {
	client := &Client{
		ID:       "client-idempotent-close",
		Channels: make(map[string]bool),
		Send:     make(chan []byte, 10),
	}

	const concurrency = 20
	var wg sync.WaitGroup
	wg.Add(concurrency)

	// Multiple concurrent goroutines attempt to close Send channel simultaneously
	for i := 0; i < concurrency; i++ {
		go func() {
			defer wg.Done()
			client.CloseSend()
		}()
	}
	wg.Wait()

	// Verify channel is closed
	select {
	case _, ok := <-client.Send:
		if ok {
			t.Errorf("expected Send channel to be closed, but was open")
		}
	default:
		t.Errorf("expected read from closed channel to succeed immediately")
	}
}

func TestHub_Close_ConcurrentWithUnregister(t *testing.T) {
	hub := NewHub()
	go hub.Run()

	const clientCount = 50
	clients := make([]*Client, clientCount)
	for i := 0; i < clientCount; i++ {
		clients[i] = &Client{
			ID:       fmt.Sprintf("concurrent-client-%d", i),
			Channels: make(map[string]bool),
			Send:     make(chan []byte, 10),
		}
		hub.Register <- clients[i]
		hub.Subscribe(clients[i], "test-concurrent-channel")
	}

	time.Sleep(20 * time.Millisecond)

	var wg sync.WaitGroup
	wg.Add(clientCount + 1)

	// Close hub in one goroutine
	go func() {
		defer wg.Done()
		hub.Close()
	}()

	// Concurrently unregister clients
	for i := 0; i < clientCount; i++ {
		c := clients[i]
		go func() {
			defer wg.Done()
			hub.Unregister <- c
		}()
	}

	wg.Wait()
}

func TestHub_RedisPubSub_SubscribeUnsubscribe_Serialized(t *testing.T) {
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("Failed to start miniredis: %v", err)
	}
	defer mr.Close()

	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	hub := NewHub()
	hub.SetRedisClient(rdb)
	go hub.Run()
	defer hub.Close()

	const iterations = 30
	var wg sync.WaitGroup
	wg.Add(iterations)

	// Rapidly subscribe and unsubscribe to the same channel
	for i := 0; i < iterations; i++ {
		go func(idx int) {
			defer wg.Done()
			c := &Client{
				ID:       fmt.Sprintf("client-rapid-%d", idx),
				Channels: make(map[string]bool),
				Send:     make(chan []byte, 10),
			}
			hub.Register <- c
			hub.Subscribe(c, "hot-channel")
			time.Sleep(5 * time.Millisecond)
			hub.Unsubscribe(c, "hot-channel")
			hub.Unregister <- c
		}(i)
	}

	wg.Wait()
	time.Sleep(50 * time.Millisecond)

	hub.mu.RLock()
	activeCount := hub.activeSubs["hot-channel"]
	hub.mu.RUnlock()

	if activeCount != 0 {
		t.Errorf("expected 0 active subscriptions on hot-channel, got %d", activeCount)
	}
}
