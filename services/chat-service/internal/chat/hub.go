// Package chat implements the WebSocket hub for managing real-time
// client connections, channel subscriptions, and message broadcasting.
package chat

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"sync"
	"time"

	"github.com/redis/go-redis/v9"
)

// Message represents a chat message flowing through the hub.
type Message struct {
	Channel        string   `json:"channel"`                   // target channel name
	SenderID       string   `json:"sender_id,omitempty"`       // mocked user identity from token
	SenderUsername string   `json:"sender_username,omitempty"` // point-in-time snapshot username captured at send-time
	Content        string   `json:"content,omitempty"`         // message body
	Type           string   `json:"type,omitempty"`            // "message", "join", "leave", "location_update"
	Latitude       *float64 `json:"latitude,omitempty"`        // live tracking latitude
	Longitude      *float64 `json:"longitude,omitempty"`       // live tracking longitude
	EmployeeID     string   `json:"employee_id,omitempty"`     // live tracking employee id
}

// Client represents a single WebSocket connection registered with the Hub.
type Client struct {
	ID        string          // unique connection ID (from token)
	Username  string          // point-in-time username of the client resolved at connection init time
	Channels  map[string]bool // channels this client is subscribed to
	Send      chan []byte     // outbound message buffer
	closeOnce sync.Once
}

// CloseSend safely closes the Send channel at most once, preventing panics on concurrent closes.
func (c *Client) CloseSend() {
	c.closeOnce.Do(func() {
		close(c.Send)
	})
}

type hubPubSubPayload struct {
	OriginInstanceID string   `json:"origin_instance_id"`
	Message          *Message `json:"message"`
}

// Hub maintains the set of active clients and broadcasts messages
// to clients subscribed to the target channel.
type Hub struct {
	mu         sync.RWMutex
	subMu      sync.Mutex                  // serializes dynamic Redis Pub/Sub subscribe and unsubscribe calls (Q16)
	clients    map[*Client]bool            // all connected clients
	channels   map[string]map[*Client]bool // channel → set of clients
	instanceID string                      // unique instance ID to prevent duplicate self-delivery from Redis

	rdb        *redis.Client
	pubsub     *redis.PubSub
	activeSubs map[string]int // channel -> count of local clients
	subCancel  context.CancelFunc
	stopOnce   sync.Once

	Register   chan *Client  // register requests from connections
	Unregister chan *Client  // unregister requests from connections
	Broadcast  chan *Message // inbound messages to broadcast
}

// NewHub creates and returns a new Hub instance.
func NewHub() *Hub {
	bytes := make([]byte, 16)
	if _, err := rand.Read(bytes); err != nil {
		bytes = []byte(fmt.Sprintf("%d", time.Now().UnixNano()))
	}
	instID := hex.EncodeToString(bytes)

	return &Hub{
		clients:    make(map[*Client]bool),
		channels:   make(map[string]map[*Client]bool),
		instanceID: instID,
		activeSubs: make(map[string]int),
		Register:   make(chan *Client),
		Unregister: make(chan *Client),
		Broadcast:  make(chan *Message),
	}
}

// SetRedisClient configures Redis Pub/Sub cross-instance fan-out.
func (h *Hub) SetRedisClient(rdb *redis.Client) {
	if rdb == nil {
		return
	}
	h.mu.Lock()
	defer h.mu.Unlock()

	h.rdb = rdb
	ctx, cancel := context.WithCancel(context.Background())
	h.subCancel = cancel
	h.pubsub = rdb.Subscribe(ctx, "account:events")

	go h.redisSubscriberLoop(ctx, h.pubsub)
	log.Printf("[HUB] Connected to Redis Pub/Sub for cross-replica chat fan-out (Instance ID: %s)", h.instanceID)
}

// DisconnectUser closes and removes all active WebSocket connections belonging to userID (F-03).
func (h *Hub) DisconnectUser(userID string) {
	h.mu.Lock()
	var channelsToSync []string
	for client := range h.clients {
		if client.ID == userID {
			client.CloseSend()
			delete(h.clients, client)
			for ch := range client.Channels {
				if members, exists := h.channels[ch]; exists {
					delete(members, client)
					if len(members) == 0 {
						delete(h.channels, ch)
					}
				}
				if count, exists := h.activeSubs[ch]; exists {
					h.activeSubs[ch] = count - 1
					if h.activeSubs[ch] <= 0 {
						delete(h.activeSubs, ch)
						channelsToSync = append(channelsToSync, ch)
					}
				}
			}
			log.Printf("[HUB] Force disconnected suspended user: %s", userID)
		}
	}
	h.mu.Unlock()

	for _, ch := range channelsToSync {
		h.syncRedisSubscription(ch)
	}
}

// Close gracefully stops the Redis Pub/Sub subscriber loop and closes all active WebSocket client connections.
func (h *Hub) Close() {
	h.stopOnce.Do(func() {
		h.mu.Lock()
		cancel := h.subCancel
		pubsub := h.pubsub

		for client := range h.clients {
			client.CloseSend()
			delete(h.clients, client)
		}
		h.channels = make(map[string]map[*Client]bool)
		h.activeSubs = make(map[string]int)
		h.mu.Unlock()

		h.subMu.Lock()
		defer h.subMu.Unlock()

		if cancel != nil {
			cancel()
		}
		if pubsub != nil {
			_ = pubsub.Close()
		}
	})
}

func (h *Hub) redisSubscriberLoop(ctx context.Context, pubsub *redis.PubSub) {
	ch := pubsub.Channel()
	for {
		select {
		case <-ctx.Done():
			return
		case msg, ok := <-ch:
			if !ok {
				return
			}

			if msg.Channel == "account:events" {
				var event struct {
					Action string `json:"action"`
					UserID string `json:"user_id"`
				}
				if err := json.Unmarshal([]byte(msg.Payload), &event); err == nil {
					if event.Action == "ACCOUNT_SUSPENDED" && event.UserID != "" {
						h.DisconnectUser(event.UserID)
					}
				}
				continue
			}

			var payload hubPubSubPayload
			if err := json.Unmarshal([]byte(msg.Payload), &payload); err != nil {
				log.Printf("[HUB] Failed to unmarshal Redis PubSub payload: %v", err)
				continue
			}

			// De-duplication: if message originated on this instance, skip local delivery
			// because it was already delivered locally in-process on origin broadcast.
			if payload.OriginInstanceID == h.instanceID {
				continue
			}

			if payload.Message != nil {
				h.deliverLocal(payload.Message)
			}
		}
	}
}

func redisChannelName(channel string) string {
	if channel == "" {
		return "chat:channel:global"
	}
	return "chat:channel:" + channel
}

// Run starts the hub's main event loop. Must be called as a goroutine.
//
//	go hub.Run()
func (h *Hub) Run() {
	for {
		select {
		case client := <-h.Register:
			h.mu.Lock()
			h.clients[client] = true
			h.mu.Unlock()
			log.Printf("[HUB] Client registered: %s (total: %d)", client.ID, h.ClientCount())

		case client := <-h.Unregister:
			h.mu.Lock()
			var channelsToSync []string
			if _, ok := h.clients[client]; ok {
				delete(h.clients, client)
				// Remove from all channel subscriptions.
				for ch := range client.Channels {
					if members, exists := h.channels[ch]; exists {
						delete(members, client)
						if len(members) == 0 {
							delete(h.channels, ch)
						}
					}
					if count, exists := h.activeSubs[ch]; exists {
						h.activeSubs[ch] = count - 1
						if h.activeSubs[ch] <= 0 {
							delete(h.activeSubs, ch)
							channelsToSync = append(channelsToSync, ch)
						}
					}
				}
				client.CloseSend()
			}
			h.mu.Unlock()

			for _, ch := range channelsToSync {
				h.syncRedisSubscription(ch)
			}
			log.Printf("[HUB] Client unregistered: %s (total: %d)", client.ID, h.ClientCount())

		case msg := <-h.Broadcast:
			// 1. Immediate local delivery on publishing instance (in-process)
			h.deliverLocal(msg)

			// 2. Publish to Redis for remote replica fan-out
			h.mu.RLock()
			rdb := h.rdb
			h.mu.RUnlock()

			if rdb != nil {
				payload := hubPubSubPayload{
					OriginInstanceID: h.instanceID,
					Message:          msg,
				}
				data, err := json.Marshal(payload)
				if err != nil {
					log.Printf("[HUB] Failed to marshal PubSub message payload: %v", err)
					continue
				}

				topic := redisChannelName(msg.Channel)
				ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
				if err := rdb.Publish(ctx, topic, data).Err(); err != nil {
					log.Printf("[REDIS-PUBSUB-WARNING] Failed to publish message to topic %s: %v", topic, err)
				}
				cancel()
			}
		}
	}
}

// syncRedisSubscription safely synchronizes Redis Pub/Sub subscription state for a given channel.
// Serialized via subMu to prevent concurrent subscribe/unsubscribe race conditions (Q16).
func (h *Hub) syncRedisSubscription(channel string) {
	h.subMu.Lock()
	defer h.subMu.Unlock()

	h.mu.RLock()
	count := h.activeSubs[channel]
	pubsub := h.pubsub
	h.mu.RUnlock()

	if pubsub == nil {
		return
	}

	topic := redisChannelName(channel)
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	if count > 0 {
		if err := pubsub.Subscribe(ctx, topic); err != nil {
			log.Printf("[REDIS-PUBSUB-WARNING] Failed to subscribe to Redis topic %s: %v", topic, err)
		} else {
			log.Printf("[HUB] Subscribed to Redis topic %s for dynamic channel %q", topic, channel)
		}
	} else {
		if err := pubsub.Unsubscribe(ctx, topic); err != nil {
			log.Printf("[REDIS-PUBSUB-WARNING] Failed to unsubscribe from Redis topic %s: %v", topic, err)
		} else {
			log.Printf("[HUB] Unsubscribed from Redis topic %s (zero local subscribers for %q)", topic, channel)
		}
	}
}

// Subscribe adds a client to a named channel.
func (h *Hub) Subscribe(client *Client, channel string) {
	h.mu.Lock()

	if _, exists := h.channels[channel]; !exists {
		h.channels[channel] = make(map[*Client]bool)
	}
	h.channels[channel][client] = true
	client.Channels[channel] = true

	h.activeSubs[channel]++
	isFirst := h.activeSubs[channel] == 1
	h.mu.Unlock()

	if isFirst {
		h.syncRedisSubscription(channel)
	}

	log.Printf("[HUB] Client %s joined channel %q", client.ID, channel)
}

// Unsubscribe removes a client from a named channel.
func (h *Hub) Unsubscribe(client *Client, channel string) {
	h.mu.Lock()

	isLast := false
	if members, exists := h.channels[channel]; exists {
		delete(members, client)
		if len(members) == 0 {
			delete(h.channels, channel)
		}
	}
	delete(client.Channels, channel)

	if count, exists := h.activeSubs[channel]; exists {
		h.activeSubs[channel] = count - 1
		if h.activeSubs[channel] <= 0 {
			delete(h.activeSubs, channel)
			isLast = true
		}
	}
	h.mu.Unlock()

	if isLast {
		h.syncRedisSubscription(channel)
	}

	log.Printf("[HUB] Client %s left channel %q", client.ID, channel)
}

// ClientCount returns the number of currently connected clients.
func (h *Hub) ClientCount() int {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return len(h.clients)
}

// ChannelCount returns the number of active channels.
func (h *Hub) ChannelCount() int {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return len(h.channels)
}

func (h *Hub) deliverLocal(msg *Message) {
	h.mu.RLock()
	defer h.mu.RUnlock()

	if msg.Channel == "" {
		// Global broadcast to all connected clients.
		for client := range h.clients {
			h.sendToClient(client, msg)
		}
	} else {
		// Channel-scoped broadcast.
		if members, exists := h.channels[msg.Channel]; exists {
			for client := range members {
				h.sendToClient(client, msg)
			}
		}
	}
}

// sendToClient attempts to write serialized message bytes to a client's
// send buffer. Drops the message if the buffer is full (non-blocking).
func (h *Hub) sendToClient(client *Client, msg *Message) {
	data, err := json.Marshal(msg)
	if err != nil {
		log.Printf("[HUB] Failed to marshal message: %v", err)
		return
	}

	select {
	case client.Send <- data:
	default:
		// Client buffer full — drop message to prevent blocking the hub.
		log.Printf("[HUB] Dropped message for slow client %s", client.ID)
	}
}
