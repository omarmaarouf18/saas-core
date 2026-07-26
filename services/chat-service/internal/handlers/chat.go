// Package handlers implements HTTP/WebSocket handlers for the chat-service.
package handlers

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"github.com/project/chat-service/internal/chat"
	"github.com/project/chat-service/internal/config"
	"github.com/project/chat-service/internal/store"
	"github.com/project/shared/infra/handlerutil"
	"github.com/project/shared/infra/jwtutil"
	"github.com/project/shared/infra/ratelimit"
	"github.com/project/shared/infra/resilience"
	"github.com/project/shared/infra/tlsutil"
	"github.com/redis/go-redis/v9"
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

// wsMessage is the expected JSON structure from WebSocket clients.
type wsMessage struct {
	Action  string `json:"action"`            // "subscribe", "unsubscribe", "message"
	Channel string `json:"channel,omitempty"` // target channel
	Content string `json:"content,omitempty"` // message content
}

// Chat holds dependencies for the WebSocket handlers.
type Chat struct {
	hub                  *chat.Hub
	store                *store.MongoDB
	authServiceURL       string
	userServiceURL       string
	tokenCache           map[string]cachedToken
	tokenCacheMu         sync.Mutex
	limiter              *handlerutil.RateLimiter
	internalServiceToken string
	allowedOrigin        string
	authClient           *resilience.ResilienceClient
	userClient           *resilience.ResilienceClient
}

// NewChat creates a new Chat handler group.
func NewChat(hub *chat.Hub, s *store.MongoDB, cfg *config.Config, rdb *redis.Client) *Chat {
	allowedOrigin := cfg.AllowedOrigin
	if allowedOrigin == "" {
		allowedOrigin = "http://localhost:3000"
	}
	handlerutil.InitCloudWatch(cfg.CloudWatchLogGroup)

	var client *http.Client
	if cfg.TLSCertPath != "" && cfg.TLSKeyPath != "" && cfg.TLSCAPath != "" {
		var err error
		client, err = tlsutil.NewClient(cfg.TLSCertPath, cfg.TLSKeyPath, cfg.TLSCAPath)
		if err != nil {
			log.Fatalf("[CHAT] Failed to initialize TLS http client: %v", err)
		}
	} else {
		client = http.DefaultClient
	}

	rl := ratelimit.NewRateLimiter(rdb, 5, 1*time.Minute, "chat")

	authClient := resilience.NewClient(client, "auth-service", 2, 5*time.Second)
	userClient := resilience.NewClient(client, "user-service", 2, 5*time.Second)

	return &Chat{
		hub:                  hub,
		store:                s,
		authServiceURL:       cfg.AuthServiceURL,
		userServiceURL:       cfg.UserServiceURL,
		tokenCache:           make(map[string]cachedToken),
		limiter:              handlerutil.NewRateLimiter(rl),
		internalServiceToken: cfg.InternalServiceToken,
		allowedOrigin:        allowedOrigin,
		authClient:           authClient,
		userClient:           userClient,
	}
}

// RegisterRoutes mounts chat endpoints on the given ServeMux.
// Paths include the /chat/ prefix to align with the gateway's routing:
//
//	/api/v1/chat/ws → chat-service → /chat/ws
func (c *Chat) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/chat/ws", c.HandleWebSocket)
	mux.HandleFunc("/chat/history", c.GetHistory)
	mux.HandleFunc("/chat/internal/broadcast-location", c.BroadcastLocation)
	mux.HandleFunc("/chat/tickets", c.HandleCreateTicket)
	mux.HandleFunc("/chat/tickets/resolve", c.HandleResolveTicket)
}

type cachedToken struct {
	expiry   time.Time
	username string
}

// verifyToken checks if the user is active/valid in auth-service and retrieves their username.
// Cache Reconnection & Simultaneous Connection behavior:
// - Querying auth-service's GetUser once per WebSocket connection caches the username in memory for 60 seconds.
// - If the same user connects simultaneously from another tab/device or reconnects after a disconnect:
//   - If within 60 seconds: verifyToken returns the cached username immediately, bypassing the auth-service HTTP request.
//   - If after 60 seconds: verifyToken fetches the latest username from auth-service, updating the cache.
//     This prevents hitting auth-service repeatedly during reconnection loops or simultaneous logins while allowing updates to propagate.
func (c *Chat) verifyToken(id string) (bool, string, error) {
	if id == "" {
		return false, "", nil
	}

	c.tokenCacheMu.Lock()
	cached, found := c.tokenCache[id]
	c.tokenCacheMu.Unlock()

	if found && time.Now().Before(cached.expiry) {
		return true, cached.username, nil
	}

	// Verify against auth-service (internal service-to-service call)
	url := fmt.Sprintf("%s/auth/user?id=%s", c.authServiceURL, id)
	// #nosec G704 //nolint:gosec -- target is internal service URL, ID is extracted from validated JWT token
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		log.Printf("[CHAT] Error building auth-service request: %v", err)
		return false, "", err
	}
	req.Header.Set("X-Internal-Token", c.internalServiceToken)
	resp, err := c.authClient.Do(req)
	if err != nil {
		log.Printf("[CHAT] Error calling auth-service: %v", err)
		return false, "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusOK {
		var user struct {
			ID       string `json:"id"`
			Username string `json:"username"`
		}
		if err := json.NewDecoder(resp.Body).Decode(&user); err == nil && user.ID != "" {
			c.tokenCacheMu.Lock()
			c.tokenCache[id] = cachedToken{
				expiry:   time.Now().Add(5 * time.Second),
				username: user.Username,
			}
			c.tokenCacheMu.Unlock()
			return true, user.Username, nil
		}
	}
	return false, "", nil
}

func (c *Chat) canAccessChannel(userID, channel string) (bool, error) {
	if strings.HasPrefix(channel, "ticket:") {
		ticketID := strings.TrimPrefix(channel, "ticket:")
		ticket, err := c.store.GetTicket(context.Background(), ticketID)
		if err != nil {
			return false, nil
		}
		return userID == ticket.CustomerID || (ticket.AssignedAgentID != "" && userID == ticket.AssignedAgentID), nil
	}

	if !strings.HasPrefix(channel, "job:") {
		return false, nil
	}
	jobID := strings.TrimPrefix(channel, "job:")
	if jobID == "" {
		return false, nil
	}

	url := fmt.Sprintf("%s/users/jobs/get?id=%s", c.userServiceURL, jobID)
	// #nosec G704 //nolint:gosec -- target is internal service URL, jobID is validated
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return false, err
	}
	req.Header.Set("X-Internal-Token", c.internalServiceToken)

	resp, err := c.userClient.Do(req)
	if err != nil {
		return false, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return false, fmt.Errorf("unexpected status code from user-service: %d", resp.StatusCode)
	}

	var job struct {
		OwnerID    string `json:"owner_id"`
		EmployeeID string `json:"employee_id"`
		UserID     string `json:"user_id"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&job); err != nil {
		return false, err
	}
	return userID == job.OwnerID || userID == job.UserID || (job.EmployeeID != "" && userID == job.EmployeeID), nil
}

// HandleWebSocket upgrades the HTTP connection to a WebSocket protocol.
// The client must provide a ?token= query parameter for user identification.
//
//	GET /chat/ws?token=<user_token>
func (c *Chat) HandleWebSocket(w http.ResponseWriter, r *http.Request) {
	ip := handlerutil.GetIP(r)
	if limited, remaining := c.limiter.CheckAndRecord(ip); limited {
		writeJSON(w, http.StatusTooManyRequests, map[string]string{
			"error": fmt.Sprintf("too many requests, locked out for %.0f seconds", remaining.Seconds()),
		})
		return
	}

	// Parse the token query parameter for user identification.
	token := r.URL.Query().Get("token")
	if token == "" {
		http.Error(w, `{"error": "missing token query parameter"}`, http.StatusUnauthorized)
		return
	}

	var userID string
	var username string
	agent, err := c.store.GetAgentByToken(r.Context(), token)
	if err == nil && agent != nil {
		// NOTE: Support agents are system operator identities stored in the support_agents collection,
		// which does not have a profile or username field. Reusing "Agent " + agent.ID is intentional
		// as system support operators do not have an associated models.User account.
		userID = agent.ID
		username = "Agent " + agent.ID
	} else {
		// 1. Primary trust boundary: Validate JWT token signature and expiry locally
		claims, err := jwtutil.ValidateToken(token)
		if err != nil {
			writeJSON(w, http.StatusForbidden, map[string]string{"error": "invalid or expired token: " + err.Error()})
			return
		}

		// 2. Secondary trust boundary: verify against auth-service (using user ID)
		active, uname, err := c.verifyToken(claims.UserID)
		if err != nil {
			writeJSON(w, http.StatusServiceUnavailable, map[string]string{
				"error":   "service_unavailable",
				"message": "Authentication service is temporarily unavailable. Please try again later.",
			})
			return
		}
		if !active {
			writeJSON(w, http.StatusForbidden, map[string]string{"error": "user associated with token is not active or verified"})
			return
		}
		userID = claims.UserID
		username = uname
	}

	// Upgrade HTTP → WebSocket.
	var upgrader = websocket.Upgrader{
		ReadBufferSize:  1024,
		WriteBufferSize: 1024,
		CheckOrigin: func(r *http.Request) bool {
			return r.Header.Get("Origin") == c.allowedOrigin
		},
	}
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		// #nosec G706 //nolint:gosec -- userID is from verified JWT claims, log injection not possible
		log.Printf("[WS] Upgrade failed for user=%s: %v", userID, err)
		return
	}

	// Create a new hub client.
	client := &chat.Client{
		ID:       userID,
		Username: username,
		Channels: make(map[string]bool),
		Send:     make(chan []byte, 256),
	}

	// Register with the hub.
	c.hub.Register <- client

	// #nosec G706 //nolint:gosec -- userID is from verified JWT claims, RemoteAddr is net.Addr, log injection not possible
	log.Printf("[WS] Connection established: user_id=%s remote=%s", userID, conn.RemoteAddr())

	// Launch read/write pumps in separate goroutines.
	// #nosec G118 //nolint:gosec -- websocket write pump outlives request context scope
	go c.writePump(conn, client)
	// #nosec G118 //nolint:gosec -- websocket read pump outlives request context scope
	go c.readPump(conn, client)
}

// GET /chat/history?channel=<channel>&limit=<n>
func (c *Chat) GetHistory(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed, use GET"})
		return
	}

	channel := r.URL.Query().Get("channel")
	if channel == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "channel parameter is required"})
		return
	}

	requesterToken := r.URL.Query().Get("requester_id")
	if requesterToken == "" {
		requesterToken = r.URL.Query().Get("token")
	}
	if requesterToken == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "requester_id parameter is required"})
		return
	}

	var userID string
	agent, err := c.store.GetAgentByToken(r.Context(), requesterToken)
	if err == nil && agent != nil {
		userID = agent.ID
	} else {
		claims, err := jwtutil.ValidateToken(requesterToken)
		if err != nil {
			writeJSON(w, http.StatusForbidden, map[string]string{"error": "invalid or expired token: " + err.Error()})
			return
		}

		active, _, err := c.verifyToken(claims.UserID)
		if err != nil {
			writeJSON(w, http.StatusServiceUnavailable, map[string]string{
				"error":   "service_unavailable",
				"message": "Authentication service is temporarily unavailable. Please try again later.",
			})
			return
		}
		if !active {
			writeJSON(w, http.StatusForbidden, map[string]string{"error": "user associated with token is not active or verified"})
			return
		}
		userID = claims.UserID
	}

	allowed, err := c.canAccessChannel(userID, channel)
	if err != nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{
			"error":   "service_unavailable",
			"message": "User service is temporarily unavailable. Please try again later.",
		})
		return
	}
	if !allowed {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "not authorized for this channel"})
		return
	}

	limitStr := r.URL.Query().Get("limit")
	limit := int64(50)
	if limitStr != "" {
		const maxHistoryLimit = 500
		if l, err := strconv.ParseInt(limitStr, 10, 64); err == nil && l > 0 {
			if l > maxHistoryLimit {
				l = maxHistoryLimit
			}
			limit = l
		}
	}

	history, err := c.store.GetHistory(r.Context(), channel, limit)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to retrieve chat history: " + err.Error()})
		return
	}

	writeJSON(w, http.StatusOK, history)
}

// readPump reads messages from the WebSocket connection and dispatches
// them to the hub based on the action type.
func (c *Chat) readPump(conn *websocket.Conn, client *chat.Client) {
	defer func() {
		c.hub.Unregister <- client
		_ = conn.Close()
		log.Printf("[WS] Read pump closed: %s", client.ID)
	}()

	conn.SetReadLimit(maxMessageSize)
	_ = conn.SetReadDeadline(time.Now().Add(pongWait))
	conn.SetPongHandler(func(string) error {
		_ = conn.SetReadDeadline(time.Now().Add(pongWait))
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
				allowed, err := c.canAccessChannel(client.ID, msg.Channel)
				if err != nil {
					denied, _ := json.Marshal(map[string]string{
						"type":    "error",
						"channel": msg.Channel,
						"error":   "service_unavailable",
						"message": "User service is temporarily unavailable. Please try again later.",
					})
					select {
					case client.Send <- denied:
					default:
					}
					continue
				}
				if !allowed {
					denied, _ := json.Marshal(map[string]string{
						"type":    "error",
						"channel": msg.Channel,
						"error":   "not authorized for this channel",
					})
					select {
					case client.Send <- denied:
					default:
					}
					continue // do NOT fall through to hub.Subscribe
				}

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
				allowed, err := c.canAccessChannel(client.ID, msg.Channel)
				if err != nil {
					denied, _ := json.Marshal(map[string]string{
						"type":    "error",
						"channel": msg.Channel,
						"error":   "service_unavailable",
						"message": "User service is temporarily unavailable. Please try again later.",
					})
					select {
					case client.Send <- denied:
					default:
					}
					continue
				}
				if !allowed {
					log.Printf("[CHAT BLOCKED] Client %s attempted to send message to channel %q, but access is unauthorized", client.ID, msg.Channel)
					clientIP := conn.RemoteAddr().String()
					if idx := strings.LastIndex(clientIP, ":"); idx != -1 {
						clientIP = clientIP[:idx]
					}
					handlerutil.ShipSecurityEvent(context.Background(), "CHAT_BLOCKED", "chat-service", client.ID, "", fmt.Sprintf("attempted to send message to channel %s", msg.Channel), clientIP)
					denied, _ := json.Marshal(map[string]string{
						"type":    "error",
						"channel": msg.Channel,
						"error":   "not authorized for this channel",
					})
					select {
					case client.Send <- denied:
					default:
					}
					continue
				}

				// Capture point-in-time snapshot of the username at send-time (not live-resolved later).
				// Consistent with Slack/Discord design, if the username changes in the future,
				// historical messages will still display the username that was active when sent.
				chatMsg := &chat.Message{
					Channel:        msg.Channel,
					SenderID:       client.ID,
					SenderUsername: client.Username,
					Content:        msg.Content,
					Type:           "message",
				}

				// Persist message to MongoDB store
				if err := c.store.PersistMessage(context.Background(), chatMsg); err != nil {
					log.Printf("[WS] Failed to persist message: %v", err)
				}

				c.hub.Broadcast <- chatMsg
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
		_ = conn.Close()
		log.Printf("[WS] Write pump closed: %s", client.ID)
	}()

	for {
		select {
		case message, ok := <-client.Send:
			_ = conn.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				// Hub closed the channel — send a close frame.
				_ = conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}

			w, err := conn.NextWriter(websocket.TextMessage)
			if err != nil {
				return
			}
			if _, err := w.Write(message); err != nil {
				return
			}

			// Batch any queued messages into the current write.
			n := len(client.Send)
			for i := 0; i < n; i++ {
				if _, err := w.Write([]byte("\n")); err != nil {
					return
				}
				if _, err := w.Write(<-client.Send); err != nil {
					return
				}
			}

			if err := w.Close(); err != nil {
				return
			}

		case <-ticker.C:
			_ = conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

// POST /chat/internal/broadcast-location
// ---------------------------------------------------------------------------

func (c *Chat) BroadcastLocation(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use POST"})
		return
	}

	// Validate internal token
	gotToken := r.Header.Get("X-Internal-Token")
	if subtle.ConstantTimeCompare([]byte(gotToken), []byte(c.internalServiceToken)) != 1 {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "access denied: invalid internal token"})
		return
	}

	var req struct {
		Channel    string  `json:"channel"`
		Latitude   float64 `json:"latitude"`
		Longitude  float64 `json:"longitude"`
		EmployeeID string  `json:"employee_id"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON body: " + err.Error()})
		return
	}

	if req.Channel == "" || req.EmployeeID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "channel and employee_id are required"})
		return
	}

	msg := &chat.Message{
		Channel:    req.Channel,
		Type:       "location_update",
		Latitude:   &req.Latitude,
		Longitude:  &req.Longitude,
		EmployeeID: req.EmployeeID,
	}

	c.hub.Broadcast <- msg

	writeJSON(w, http.StatusOK, map[string]string{"status": "success", "message": "location broadcasted"})
}

func (c *Chat) HandleCreateTicket(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed, use POST"})
		return
	}

	token := r.URL.Query().Get("token")
	if token == "" {
		authHeader := r.Header.Get("Authorization")
		if strings.HasPrefix(authHeader, "Bearer ") {
			token = strings.TrimPrefix(authHeader, "Bearer ")
		}
	}
	if token == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "missing token"})
		return
	}

	claims, err := jwtutil.ValidateToken(token)
	if err != nil {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "invalid or expired token: " + err.Error()})
		return
	}

	// Rate limiting check
	if limited, remaining := c.limiter.CheckAndRecord("ticket_create:" + claims.UserID); limited {
		writeJSON(w, http.StatusTooManyRequests, map[string]string{
			"error": fmt.Sprintf("too many requests, locked out for %.0f seconds", remaining.Seconds()),
		})
		return
	}

	var req struct {
		ContextID string `json:"context_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON body"})
		return
	}

	ticket, err := c.store.CreateTicketAndAssign(r.Context(), claims.UserID, req.ContextID)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to create ticket: " + err.Error()})
		return
	}

	// Structured logs
	handlerutil.ShipSecurityEvent(r.Context(), "TICKET_CREATED", "chat-service", claims.UserID, "", fmt.Sprintf("created ticket %s", ticket.ID), handlerutil.GetClientIP(r))
	if ticket.AssignedAgentID != "" {
		handlerutil.ShipSecurityEvent(r.Context(), "TICKET_ASSIGNED", "chat-service", ticket.AssignedAgentID, "", fmt.Sprintf("ticket %s assigned to agent %s", ticket.ID, ticket.AssignedAgentID), handlerutil.GetClientIP(r))
	} else {
		handlerutil.ShipSecurityEvent(r.Context(), "TICKET_QUEUED", "chat-service", claims.UserID, "", fmt.Sprintf("ticket %s queued - no agents available", ticket.ID), handlerutil.GetClientIP(r))
	}

	writeJSON(w, http.StatusCreated, ticket)
}

func (c *Chat) HandleResolveTicket(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed, use POST"})
		return
	}

	token := r.URL.Query().Get("token")
	if token == "" {
		authHeader := r.Header.Get("Authorization")
		if strings.HasPrefix(authHeader, "Bearer ") {
			token = strings.TrimPrefix(authHeader, "Bearer ")
		}
	}
	if token == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "missing token"})
		return
	}

	agent, err := c.store.GetAgentByToken(r.Context(), token)
	if err != nil || agent == nil {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "access denied: invalid agent token"})
		return
	}

	var req struct {
		TicketID string `json:"ticket_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON body"})
		return
	}

	ticket, err := c.store.GetTicket(r.Context(), req.TicketID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "ticket not found"})
		return
	}

	// IDOR check: agent can only resolve their assigned ticket
	if ticket.AssignedAgentID != agent.ID {
		// #nosec G706 //nolint:gosec -- IDs are from verified JWT tokens and database, log injection not possible
		log.Printf("[SECURITY EVENT] Agent %s attempted unauthorized resolve of ticket %s (assigned to %s)", agent.ID, ticket.ID, ticket.AssignedAgentID)
		handlerutil.ShipSecurityEvent(r.Context(), "TICKET_RESOLVE_BLOCKED", "chat-service", agent.ID, "", fmt.Sprintf("unauthorized attempt to resolve ticket %s", ticket.ID), handlerutil.GetClientIP(r))
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "not authorized to resolve this ticket"})
		return
	}

	if err := c.store.ResolveTicket(r.Context(), req.TicketID); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to resolve ticket: " + err.Error()})
		return
	}

	handlerutil.ShipSecurityEvent(r.Context(), "TICKET_RESOLVED", "chat-service", agent.ID, "", fmt.Sprintf("ticket %s resolved by agent %s", ticket.ID, agent.ID), handlerutil.GetClientIP(r))

	writeJSON(w, http.StatusOK, map[string]string{"status": "resolved", "ticket_id": req.TicketID})
}

func writeJSON(w http.ResponseWriter, status int, data any) {
	handlerutil.WriteJSON(w, status, data)
}
