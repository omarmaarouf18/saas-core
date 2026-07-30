// Package hub implements a Server-Sent Events (SSE) broadcasting hub
// for real-time notification delivery to role-based session pools.
package hub

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"sync"
	"time"

	"github.com/project/notification-service/internal/fcm"
	"github.com/redis/go-redis/v9"
)

// Role represents the session pool a client belongs to.
type Role string

const (
	RoleOwner    Role = "owner"
	RoleEmployee Role = "employee"
	RoleClient   Role = "client"
)

// Notification is the payload broadcast to connected clients.
type Notification struct {
	ID        string    `json:"id"`
	Type      string    `json:"type"`               // "job_alert", "status_update", "system", "popup"
	TenantID  string    `json:"tenant_id"`          // scope to tenant
	UserID    string    `json:"user_id,omitempty"`  // target user ID if single recipient
	UserIDs   []string  `json:"user_ids,omitempty"` // target user IDs if multiple recipients
	Global    bool      `json:"global"`             // explicit opt-in for platform-wide global broadcast
	Title     string    `json:"title"`
	Body      string    `json:"body"`
	Roles     []Role    `json:"roles"` // target roles (empty = broadcast all)
	Timestamp time.Time `json:"timestamp"`
}

// SSEClient represents a single SSE connection.
type SSEClient struct {
	ID       string
	TenantID string
	Role     Role
	Send     chan []byte
}

// DeviceTokenFetcher defines interface for cross-service token lookup and stale token unregistration.
type DeviceTokenFetcher interface {
	GetUserDeviceTokens(ctx context.Context, userID string) ([]string, error)
	UnregisterStaleToken(ctx context.Context, userID, token string) error
}

// SSEHub manages SSE client pools organized by role and tenant.
type SSEHub struct {
	mu                 sync.RWMutex
	clients            map[*SSEClient]bool
	rdb                *redis.Client
	pubsub             *redis.PubSub
	cancel             context.CancelFunc
	stopOnce           sync.Once
	fcmDispatcher      fcm.Dispatcher
	deviceTokenFetcher DeviceTokenFetcher
}

// NewSSEHub creates a new hub.
func NewSSEHub() *SSEHub {
	return &SSEHub{clients: make(map[*SSEClient]bool)}
}

// SetRedisClient configures Redis Pub/Sub cross-instance fan-out.
func (h *SSEHub) SetRedisClient(rdb *redis.Client) {
	if rdb == nil {
		return
	}
	h.mu.Lock()
	defer h.mu.Unlock()

	h.rdb = rdb
	ctx, cancel := context.WithCancel(context.Background())
	h.cancel = cancel
	h.pubsub = rdb.PSubscribe(ctx, "notify:*")

	go h.redisSubscriberLoop(ctx, h.pubsub)
	log.Printf("[SSE-HUB] Connected to Redis Pub/Sub for cross-replica notification fan-out")
}

// Close gracefully stops the Redis Pub/Sub subscriber loop.
func (h *SSEHub) Close() {
	h.stopOnce.Do(func() {
		h.mu.Lock()
		cancel := h.cancel
		pubsub := h.pubsub
		h.mu.Unlock()

		if cancel != nil {
			cancel()
		}
		if pubsub != nil {
			_ = pubsub.Close()
		}
	})
}

func (h *SSEHub) redisSubscriberLoop(ctx context.Context, pubsub *redis.PubSub) {
	ch := pubsub.Channel()
	for {
		select {
		case <-ctx.Done():
			return
		case msg, ok := <-ch:
			if !ok {
				return
			}
			var n Notification
			if err := json.Unmarshal([]byte(msg.Payload), &n); err != nil {
				log.Printf("[SSE-HUB] Failed to unmarshal Redis notification payload: %v", err)
				continue
			}
			h.deliverLocal(n)
		}
	}
}

// Register adds a client to the hub.
func (h *SSEHub) Register(c *SSEClient) {
	h.mu.Lock()
	h.clients[c] = true
	h.mu.Unlock()
	log.Printf("[SSE-HUB] Client registered: id=%s tenant=%s role=%s (total: %d)",
		c.ID, c.TenantID, c.Role, h.ClientCount())
}

// Unregister removes a client from the hub.
func (h *SSEHub) Unregister(c *SSEClient) {
	h.mu.Lock()
	if _, ok := h.clients[c]; ok {
		delete(h.clients, c)
		close(c.Send)
	}
	h.mu.Unlock()
	log.Printf("[SSE-HUB] Client unregistered: id=%s (total: %d)", c.ID, h.ClientCount())
}

// BroadcastGlobal sends a notification platform-wide to all clients regardless of tenant.
func (h *SSEHub) BroadcastGlobal(n Notification) {
	n.Global = true
	h.Broadcast(n)
}

// Broadcast sends a notification to all matching clients based on tenant and role filters.
func (h *SSEHub) Broadcast(n Notification) {
	if n.Timestamp.IsZero() {
		n.Timestamp = time.Now().UTC()
	}
	if n.ID == "" {
		bytes := make([]byte, 16)
		if _, err := rand.Read(bytes); err == nil {
			n.ID = fmt.Sprintf("notif-%s", hex.EncodeToString(bytes))
		} else {
			n.ID = fmt.Sprintf("notif-%d", time.Now().UnixNano())
		}
	}

	data, err := json.Marshal(n)
	if err != nil {
		log.Printf("[SSE-HUB] Failed to marshal notification: %v", err)
		return
	}

	h.mu.RLock()
	rdb := h.rdb
	h.mu.RUnlock()

	if rdb != nil {
		channel := "notify:global"
		if !n.Global {
			channel = fmt.Sprintf("notify:tenant:%s", n.TenantID)
		}

		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()

		if err := rdb.Publish(ctx, channel, data).Err(); err != nil {
			log.Printf("[REDIS-PUBSUB-WARNING] Failed to publish notification to Redis channel %s: %v — falling back to local delivery", channel, err)
			h.deliverLocal(n)
		}
	} else {
		h.deliverLocal(n)
	}

	// Parallel non-blocking FCM push delivery
	go h.dispatchPush(n)
}

// SetPushDispatcher configures parallel FCM push notification delivery.
func (h *SSEHub) SetPushDispatcher(dispatcher fcm.Dispatcher, fetcher DeviceTokenFetcher) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.fcmDispatcher = dispatcher
	h.deviceTokenFetcher = fetcher
}

func (h *SSEHub) dispatchPush(n Notification) {
	h.mu.RLock()
	fcmDisp := h.fcmDispatcher
	fetcher := h.deviceTokenFetcher
	h.mu.RUnlock()

	if fcmDisp == nil || !fcmDisp.IsEnabled() || fetcher == nil {
		return
	}

	defer func() {
		if r := recover(); r != nil {
			log.Printf("[FCM-PUSH] Recovered from panic in push dispatch: %v", r)
		}
	}()

	var targetUserIDs []string
	if n.UserID != "" {
		targetUserIDs = append(targetUserIDs, n.UserID)
	}
	for _, uid := range n.UserIDs {
		if uid != "" && uid != n.UserID {
			targetUserIDs = append(targetUserIDs, uid)
		}
	}

	if len(targetUserIDs) == 0 {
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	dataMap := map[string]string{
		"id":        n.ID,
		"type":      n.Type,
		"tenant_id": n.TenantID,
	}

	for _, userID := range targetUserIDs {
		tokens, err := fetcher.GetUserDeviceTokens(ctx, userID)
		if err != nil {
			log.Printf("[FCM-PUSH] Failed to fetch device tokens for user %s: %v", userID, err)
			continue
		}

		if len(tokens) == 0 {
			log.Printf("[FCM-PUSH] Debug: user %s has no registered device tokens (silent no-op)", userID)
			continue
		}

		for _, token := range tokens {
			isStale, err := fcmDisp.SendPush(ctx, token, n.Title, n.Body, dataMap)
			if isStale {
				log.Printf("[FCM-PUSH] Cleaning up stale token for user %s", userID)
				_ = fetcher.UnregisterStaleToken(ctx, userID, token)
			} else if err != nil {
				log.Printf("[FCM-PUSH] Push to user %s failed: %v", userID, err)
			}
		}
	}
}

func (h *SSEHub) deliverLocal(n Notification) {
	data, err := json.Marshal(n)
	if err != nil {
		log.Printf("[SSE-HUB] Failed to marshal notification for local delivery: %v", err)
		return
	}

	// Format as SSE event.
	ssePayload := fmt.Appendf(nil, "event: notification\ndata: %s\n\n", data)

	h.mu.RLock()
	defer h.mu.RUnlock()

	sent := 0
	for client := range h.clients {
		// Tenant scoping: unless explicitly marked global, only send to clients belonging to the target tenant.
		if !n.Global && client.TenantID != n.TenantID {
			continue
		}
		// Role filtering: if roles specified, only send to matching roles.
		if len(n.Roles) > 0 && !containsRole(n.Roles, client.Role) {
			continue
		}
		select {
		case client.Send <- ssePayload:
			sent++
		default:
			log.Printf("[SSE-HUB] Dropped notification for slow client %s", client.ID)
		}
	}
	log.Printf("[SSE-HUB] Broadcast: type=%s tenant=%s → %d local clients", n.Type, n.TenantID, sent)
}

// ClientCount returns the number of connected clients.
func (h *SSEHub) ClientCount() int {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return len(h.clients)
}

// ClientsByRole returns a count per role.
func (h *SSEHub) ClientsByRole() map[Role]int {
	h.mu.RLock()
	defer h.mu.RUnlock()
	counts := map[Role]int{}
	for c := range h.clients {
		counts[c.Role]++
	}
	return counts
}

func containsRole(roles []Role, target Role) bool {
	for _, r := range roles {
		if r == target {
			return true
		}
	}
	return false
}
