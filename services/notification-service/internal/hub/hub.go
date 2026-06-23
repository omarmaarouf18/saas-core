// Package hub implements a Server-Sent Events (SSE) broadcasting hub
// for real-time notification delivery to role-based session pools.
package hub

import (
	"encoding/json"
	"fmt"
	"log"
	"sync"
	"time"
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
	Type      string    `json:"type"`      // "job_alert", "status_update", "system", "popup"
	TenantID  string    `json:"tenant_id"` // scope to tenant
	Title     string    `json:"title"`
	Body      string    `json:"body"`
	Roles     []Role    `json:"roles"`     // target roles (empty = broadcast all)
	Timestamp time.Time `json:"timestamp"`
}

// SSEClient represents a single SSE connection.
type SSEClient struct {
	ID       string
	TenantID string
	Role     Role
	Send     chan []byte
	Done     chan struct{}
}

// SSEHub manages SSE client pools organized by role and tenant.
type SSEHub struct {
	mu      sync.RWMutex
	clients map[*SSEClient]bool
}

// NewSSEHub creates a new hub.
func NewSSEHub() *SSEHub {
	return &SSEHub{clients: make(map[*SSEClient]bool)}
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

// Broadcast sends a notification to all matching clients based on tenant and role filters.
func (h *SSEHub) Broadcast(n Notification) {
	if n.Timestamp.IsZero() {
		n.Timestamp = time.Now().UTC()
	}
	if n.ID == "" {
		n.ID = fmt.Sprintf("notif-%d", time.Now().UnixNano())
	}

	data, err := json.Marshal(n)
	if err != nil {
		log.Printf("[SSE-HUB] Failed to marshal notification: %v", err)
		return
	}

	// Format as SSE event.
	ssePayload := fmt.Appendf(nil, "event: notification\ndata: %s\n\n", data)

	h.mu.RLock()
	defer h.mu.RUnlock()

	sent := 0
	for client := range h.clients {
		// Tenant scoping: if notification has a tenant, only send to that tenant's clients.
		if n.TenantID != "" && client.TenantID != n.TenantID {
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
	log.Printf("[SSE-HUB] Broadcast: type=%s tenant=%s → %d clients", n.Type, n.TenantID, sent)
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
