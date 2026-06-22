// Package handlers implements HTTP/WebSocket handlers for the chat-service.
package handlers

import (
	"encoding/json"
	"log"
	"net/http"
	"time"

	"github.com/gorilla/websocket"
	"github.com/project/chat-service/internal/chat"
)

const (
	// Time allowed to write a message to the peer.
	writeWait = 10 * time.Second
	// Time allowed to read the next pong message from the peer.
	pongWait = 60 * time.Second
	// Send pings to peer with this period. Must be less than pongWait.
	pingPeriod = (pongWait * 9) / 10
	// Maximum message size allowed from peer (64 KB).
	maxMessageSize = 64 * 1024
)

// upgrader specifies parameters for upgrading an HTTP connection to WebSocket.
var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	// Allow all origins in development; restrict in production.
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}

// wsMessage is the expected JSON structure from WebSocket clients.
type wsMessage struct {
	Action  string `json:"action"`            // "subscribe", "unsubscribe", "message"
	Channel string `json:"channel,omitempty"` // target channel
	Content string `json:"content,omitempty"` // message content
}

// Chat holds dependencies for the WebSocket handlers.
type Chat struct {
	hub *chat.Hub
}

// NewChat creates a new Chat handler group.
func NewChat(hub *chat.Hub) *Chat {
	return &Chat{hub: hub}
}

// RegisterRoutes mounts chat endpoints on the given ServeMux.
// Paths include the /chat/ prefix to align with the gateway's routing:
//
//	/api/v1/chat/ws → chat-service → /chat/ws
func (c *Chat) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/chat/ws", c.HandleWebSocket)
}

// HandleWebSocket upgrades the HTTP connection to a WebSocket protocol.
// The client must provide a ?token= query parameter for user identification.
//
//	GET /chat/ws?token=<user_token>
func (c *Chat) HandleWebSocket(w http.ResponseWriter, r *http.Request) {
	// Parse the token query parameter for mocked user identification.
	token := r.URL.Query().Get("token")
	if token == "" {
		http.Error(w, `{"error": "missing token query parameter"}`, http.StatusUnauthorized)
		return
	}

	// Upgrade HTTP → WebSocket.
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("[WS] Upgrade failed for token=%s: %v", token, err)
		return
	}

	// Create a new hub client.
	client := &chat.Client{
		ID:       token,
		Channels: make(map[string]bool),
		Send:     make(chan []byte, 256),
	}

	// Register with the hub.
	c.hub.Register <- client

	log.Printf("[WS] Connection established: token=%s remote=%s", token, conn.RemoteAddr())

	// Launch read/write pumps in separate goroutines.
	go c.writePump(conn, client)
	go c.readPump(conn, client)
}

// readPump reads messages from the WebSocket connection and dispatches
// them to the hub based on the action type.
func (c *Chat) readPump(conn *websocket.Conn, client *chat.Client) {
	defer func() {
		c.hub.Unregister <- client
		conn.Close()
		log.Printf("[WS] Read pump closed: %s", client.ID)
	}()

	conn.SetReadLimit(maxMessageSize)
	conn.SetReadDeadline(time.Now().Add(pongWait))
	conn.SetPongHandler(func(string) error {
		conn.SetReadDeadline(time.Now().Add(pongWait))
		return nil
	})

	for {
		_, raw, err := conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseNormalClosure) {
				log.Printf("[WS] Unexpected close from %s: %v", client.ID, err)
			}
			break
		}

		var msg wsMessage
		if err := json.Unmarshal(raw, &msg); err != nil {
			log.Printf("[WS] Invalid JSON from %s: %v", client.ID, err)
			continue
		}

		switch msg.Action {
		case "subscribe":
			if msg.Channel != "" {
				c.hub.Subscribe(client, msg.Channel)
				// Send confirmation back to the client.
				confirm, _ := json.Marshal(map[string]string{
					"type":    "subscribed",
					"channel": msg.Channel,
				})
				select {
				case client.Send <- confirm:
				default:
				}
			}

		case "unsubscribe":
			if msg.Channel != "" {
				c.hub.Unsubscribe(client, msg.Channel)
				confirm, _ := json.Marshal(map[string]string{
					"type":    "unsubscribed",
					"channel": msg.Channel,
				})
				select {
				case client.Send <- confirm:
				default:
				}
			}

		case "message":
			if msg.Content != "" {
				c.hub.Broadcast <- &chat.Message{
					Channel:  msg.Channel,
					SenderID: client.ID,
					Content:  msg.Content,
					Type:     "message",
				}
			}

		default:
			log.Printf("[WS] Unknown action %q from %s", msg.Action, client.ID)
		}
	}
}

// writePump pumps messages from the hub to the WebSocket connection.
// It also sends periodic pings to detect dead connections.
func (c *Chat) writePump(conn *websocket.Conn, client *chat.Client) {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		conn.Close()
		log.Printf("[WS] Write pump closed: %s", client.ID)
	}()

	for {
		select {
		case message, ok := <-client.Send:
			conn.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				// Hub closed the channel — send a close frame.
				conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}

			w, err := conn.NextWriter(websocket.TextMessage)
			if err != nil {
				return
			}
			w.Write(message)

			// Batch any queued messages into the current write.
			n := len(client.Send)
			for i := 0; i < n; i++ {
				w.Write([]byte("\n"))
				w.Write(<-client.Send)
			}

			if err := w.Close(); err != nil {
				return
			}

		case <-ticker.C:
			conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}
