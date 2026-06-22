// Package chat implements the WebSocket hub for managing real-time
// client connections, channel subscriptions, and message broadcasting.
package chat

import (
	"log"
	"sync"
)

// Message represents a chat message flowing through the hub.
type Message struct {
	Channel  string `json:"channel"`            // target channel name
	SenderID string `json:"sender_id"`           // mocked user identity from token
	Content  string `json:"content"`             // message body
	Type     string `json:"type,omitempty"`       // "message", "join", "leave"
}

// Client represents a single WebSocket connection registered with the Hub.
type Client struct {
	ID       string          // unique connection ID (from token)
	Channels map[string]bool // channels this client is subscribed to
	Send     chan []byte      // outbound message buffer
}

// Hub maintains the set of active clients and broadcasts messages
// to clients subscribed to the target channel.
type Hub struct {
	mu         sync.RWMutex
	clients    map[*Client]bool     // all connected clients
	channels   map[string]map[*Client]bool // channel → set of clients

	Register   chan *Client   // register requests from connections
	Unregister chan *Client   // unregister requests from connections
	Broadcast  chan *Message  // inbound messages to broadcast
}

// NewHub creates and returns a new Hub instance.
func NewHub() *Hub {
	return &Hub{
		clients:    make(map[*Client]bool),
		channels:   make(map[string]map[*Client]bool),
		Register:   make(chan *Client),
		Unregister: make(chan *Client),
		Broadcast:  make(chan *Message),
	}
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
				}
				close(client.Send)
			}
			h.mu.Unlock()
			log.Printf("[HUB] Client unregistered: %s (total: %d)", client.ID, h.ClientCount())

		case msg := <-h.Broadcast:
			h.mu.RLock()
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
			h.mu.RUnlock()
		}
	}
}

// Subscribe adds a client to a named channel.
func (h *Hub) Subscribe(client *Client, channel string) {
	h.mu.Lock()
	defer h.mu.Unlock()

	if _, exists := h.channels[channel]; !exists {
		h.channels[channel] = make(map[*Client]bool)
	}
	h.channels[channel][client] = true
	client.Channels[channel] = true

	log.Printf("[HUB] Client %s joined channel %q", client.ID, channel)
}

// Unsubscribe removes a client from a named channel.
func (h *Hub) Unsubscribe(client *Client, channel string) {
	h.mu.Lock()
	defer h.mu.Unlock()

	if members, exists := h.channels[channel]; exists {
		delete(members, client)
		if len(members) == 0 {
			delete(h.channels, channel)
		}
	}
	delete(client.Channels, channel)

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

// sendToClient attempts to write serialized message bytes to a client's
// send buffer. Drops the message if the buffer is full (non-blocking).
func (h *Hub) sendToClient(client *Client, msg *Message) {
	// Serialize message inline to avoid import cycle; handlers do the
	// full JSON marshal, but here we use a lightweight format.
	data := []byte(`{"channel":"` + msg.Channel +
		`","sender_id":"` + msg.SenderID +
		`","content":"` + msg.Content +
		`","type":"` + msg.Type + `"}`)

	select {
	case client.Send <- data:
	default:
		// Client buffer full — drop message to prevent blocking the hub.
		log.Printf("[HUB] Dropped message for slow client %s", client.ID)
	}
}
