// Package handlers implements HTTP handlers for the notification-service.
package handlers

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"time"

	"github.com/project/notification-service/internal/hub"
)

// Notification holds dependencies for notification handlers.
type Notification struct {
	hub            *hub.SSEHub
	authServiceURL string
	allowedOrigin  string
	limiter        *RateLimiter
}

// NewNotification creates a new handler group.
func NewNotification(h *hub.SSEHub, authServiceURL string, allowedOrigin string) *Notification {
	if allowedOrigin == "" {
		allowedOrigin = "http://localhost:3000"
	}
	return &Notification{
		hub:            h,
		authServiceURL: authServiceURL,
		allowedOrigin:  allowedOrigin,
		limiter:        NewRateLimiter(5, 1*time.Minute),
	}
}

// RegisterRoutes mounts notification endpoints.
func (n *Notification) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/notifications/stream", n.Stream)
	mux.HandleFunc("/notifications/send", n.Send)
	mux.HandleFunc("/notifications/broadcast/job-alert", n.BroadcastJobAlert)
}

// ---------------------------------------------------------------------------
// GET /notifications/stream?token=<id>&tenant_id=<tid>&role=<role>
// ---------------------------------------------------------------------------

// Stream establishes an SSE connection for real-time notifications.
func (n *Notification) Stream(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, `{"error":"use GET"}`, http.StatusMethodNotAllowed)
		return
	}

	token := r.URL.Query().Get("token")
	if token == "" {
		http.Error(w, `{"error":"token required"}`, http.StatusBadRequest)
		return
	}

	tenantID, role, ok := n.verifyAndResolve(token)
	if !ok {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusForbidden)
		w.Write([]byte(`{"error": "invalid or inactive token"}`))
		return
	}

	// Set SSE headers.
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	w.Header().Set("Access-Control-Allow-Origin", n.allowedOrigin)

	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, `{"error":"streaming not supported"}`, http.StatusInternalServerError)
		return
	}

	client := &hub.SSEClient{
		ID:       token,
		TenantID: tenantID,
		Role:     role,
		Send:     make(chan []byte, 64),
		Done:     make(chan struct{}),
	}

	n.hub.Register(client)
	defer n.hub.Unregister(client)

	// Send initial connection event.
	fmt.Fprintf(w, "event: connected\ndata: {\"client_id\":%q,\"role\":%q}\n\n", token, role)
	flusher.Flush()

	log.Printf("[NOTIF] SSE stream opened: token=%s tenant=%s role=%s", token, tenantID, role)

	// Stream loop.
	ctx := r.Context()
	for {
		select {
		case <-ctx.Done():
			log.Printf("[NOTIF] SSE stream closed (client disconnect): %s", token)
			return
		case msg, ok := <-client.Send:
			if !ok {
				return
			}
			w.Write(msg)
			flusher.Flush()
		}
	}
}

func (n *Notification) verifyAndResolve(token string) (string, hub.Role, bool) {
	if token == "" {
		return "", "", false
	}

	url := fmt.Sprintf("%s/auth/user?id=%s", n.authServiceURL, token)
	resp, err := http.Get(url)
	if err != nil {
		log.Printf("[NOTIF] Error calling auth-service: %v", err)
		return "", "", false
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		log.Printf("[NOTIF] Auth service returned status %d for token %s", resp.StatusCode, token)
		return "", "", false
	}

	var user struct {
		ID       string `json:"id"`
		Role     string `json:"role"`
		TenantID string `json:"tenant_id"`
		IsActive bool   `json:"is_active"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&user); err != nil {
		log.Printf("[NOTIF] Failed to decode user from auth-service: %v", err)
		return "", "", false
	}

	if !user.IsActive {
		log.Printf("[NOTIF] User %s is not active", user.ID)
		return "", "", false
	}

	var r hub.Role
	switch user.Role {
	case "owner":
		r = hub.RoleOwner
	case "employee":
		r = hub.RoleEmployee
	case "user", "client":
		r = hub.RoleClient
	default:
		r = hub.RoleClient
	}

	return user.TenantID, r, true
}

// ---------------------------------------------------------------------------
// POST /notifications/send
// ---------------------------------------------------------------------------

// sendRequest is the expected JSON body for POST /notifications/send.
type sendRequest struct {
	Type     string     `json:"type"`
	TenantID string     `json:"tenant_id"`
	Title    string     `json:"title"`
	Body     string     `json:"body"`
	Roles    []hub.Role `json:"roles,omitempty"` // empty = broadcast to all roles
}

// Send pushes a notification to matching connected clients.
func (n *Notification) Send(w http.ResponseWriter, r *http.Request) {
	ip := getIP(r)
	if limited, remaining := n.limiter.CheckAndRecord(ip); limited {
		writeJSON(w, http.StatusTooManyRequests, map[string]string{
			"error": fmt.Sprintf("too many requests, locked out for %.0f seconds", remaining.Seconds()),
		})
		return
	}

	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use POST"})
		return
	}

	var req sendRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON: " + err.Error()})
		return
	}
	if req.Title == "" || req.Body == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "title and body required"})
		return
	}

	notif := hub.Notification{
		ID:        fmt.Sprintf("notif-%d", time.Now().UnixNano()),
		Type:      req.Type,
		TenantID:  req.TenantID,
		Title:     req.Title,
		Body:      req.Body,
		Roles:     req.Roles,
		Timestamp: time.Now().UTC(),
	}
	if notif.Type == "" {
		notif.Type = "popup"
	}

	n.hub.Broadcast(notif)

	writeJSON(w, http.StatusOK, map[string]any{
		"message":      "notification dispatched",
		"notification": notif,
		"active_clients": n.hub.ClientCount(),
	})
}

// ---------------------------------------------------------------------------
// POST /notifications/broadcast/job-alert
// ---------------------------------------------------------------------------

type jobAlertRequest struct {
	TenantID    string `json:"tenant_id"`
	JobID       string `json:"job_id"`
	ServiceName string `json:"service_name"`
	Description string `json:"description"`
}

// BroadcastJobAlert sends a New Job Alert to all role pools for a tenant.
func (n *Notification) BroadcastJobAlert(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use POST"})
		return
	}

	var req jobAlertRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON: " + err.Error()})
		return
	}
	if req.TenantID == "" || req.JobID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "tenant_id and job_id required"})
		return
	}

	notif := hub.Notification{
		ID:        fmt.Sprintf("job-alert-%d", time.Now().UnixNano()),
		Type:      "job_alert",
		TenantID:  req.TenantID,
		Title:     "🆕 New Job Alert",
		Body:      fmt.Sprintf("New job %s for service %s: %s", req.JobID, req.ServiceName, req.Description),
		Roles:     []hub.Role{hub.RoleOwner, hub.RoleEmployee, hub.RoleClient},
		Timestamp: time.Now().UTC(),
	}

	n.hub.Broadcast(notif)

	writeJSON(w, http.StatusOK, map[string]any{
		"message":        "job alert broadcast sent",
		"notification":   notif,
		"active_clients": n.hub.ClientCount(),
		"clients_by_role": n.hub.ClientsByRole(),
	})
}

func writeJSON(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}
