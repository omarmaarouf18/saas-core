package chat

import (
	"fmt"
	"sync"
	"testing"
	"time"
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

	// Wait for the hub to process final unregistrations
	time.Sleep(50 * time.Millisecond)

	if hub.ClientCount() != 0 {
		t.Errorf("Expected 0 clients remaining, got %d", hub.ClientCount())
	}
	if hub.ChannelCount() != 0 {
		t.Errorf("Expected 0 channels remaining, got %d", hub.ChannelCount())
	}
}
