// Package handlers implements HTTP handlers for the notification-service.
package handlers

import (
	"crypto/subtle"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/project/notification-service/internal/config"
	"github.com/project/notification-service/internal/hub"
	"github.com/project/shared/infra/handlerutil"
	"github.com/project/shared/infra/jwtutil"
	"github.com/project/shared/infra/ratelimit"
	"github.com/project/shared/infra/resilience"
	"github.com/project/shared/infra/tlsutil"
	"github.com/redis/go-redis/v9"
)

// maxConcurrentStreamsPerTenant caps simultaneously open SSE streams for a
// single tenant identity so one token cannot exhaust server FDs/memory.
const maxConcurrentStreamsPerTenant = 5

// Notification holds dependencies for notification handlers.
type Notification struct {
	hub                  *hub.SSEHub
	authServiceURL       string
	allowedOrigin        string
	limiter              *handlerutil.RateLimiter
	streamLimiter        *handlerutil.RateLimiter
	streamCaps           map[string]int
	streamCapsMu         sync.Mutex
	internalServiceToken string
	resilienceClient     *resilience.ResilienceClient
}

// NewNotification creates a new handler group.
func NewNotification(h *hub.SSEHub, cfg *config.Config, rdb *redis.Client) *Notification {
	allowedOrigin := cfg.AllowedOrigin
	if allowedOrigin == "" {
		allowedOrigin = "http://localhost:3000"
	}

	var client *http.Client
	if cfg.TLSCertPath != "" && cfg.TLSKeyPath != "" && cfg.TLSCAPath != "" {
		var err error
		client, err = tlsutil.NewClient(cfg.TLSCertPath, cfg.TLSKeyPath, cfg.TLSCAPath)
		if err != nil {
			log.Fatalf("[NOTIF] Failed to initialize TLS http client: %v", err)
		}
	} else {
		client = http.DefaultClient
	}

	rl := ratelimit.NewRateLimiter(rdb, 5, 1*time.Minute, "notification")
	streamRl := ratelimit.NewRateLimiter(rdb, 30, 1*time.Minute, "notification:stream")

	resClient := resilience.NewClient(client, "auth-service", 2, 5*time.Second)

	return &Notification{
		hub:                  h,
		authServiceURL:       cfg.AuthServiceURL,
		allowedOrigin:        allowedOrigin,
		limiter:              handlerutil.NewRateLimiter(rl),
		streamLimiter:        handlerutil.NewRateLimiter(streamRl),
		streamCaps:           make(map[string]int),
		internalServiceToken: cfg.InternalServiceToken,
		resilienceClient:     resClient,
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
	w.Header().Set("Access-Control-Allow-Origin", n.allowedOrigin)

	if r.Method != http.MethodGet {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusMethodNotAllowed)
		writeBytes(w, []byte(`{"error":"use GET"}`))
		return
	}

	token := r.URL.Query().Get("token")
	if token == "" {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		writeBytes(w, []byte(`{"error":"token required"}`))
		return
	}

	tenantID, role, ok, err := n.verifyAndResolve(token)
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusServiceUnavailable)
		writeBytes(w, []byte(`{"error": "service_unavailable", "message": "Authentication service is temporarily unavailable. Please try again later."}`))
		return
	}
	if !ok {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusForbidden)
		writeBytes(w, []byte(`{"error": "invalid or inactive token"}`))
		return
	}

	// Rate-limit new stream registrations per tenant and cap concurrent
	// streams per tenant so one identity cannot exhaust server resources.
	if limited, remaining := n.streamLimiter.CheckAndRecord("sse:" + tenantID); limited {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusTooManyRequests)
		writeBytes(w, []byte(fmt.Sprintf(`{"error":"too many requests","message":"stream registration limit exceeded; retry in %.0f seconds"}`, remaining.Seconds())))
		return
	}
	if !n.acquireStreamSlot(tenantID) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusTooManyRequests)
		writeBytes(w, []byte(`{"error":"too many requests","message":"concurrent stream limit exceeded for this account"}`))
		return
	}
	defer n.releaseStreamSlot(tenantID)

	// Set SSE headers.
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")

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
	}

	n.hub.Register(client)
	defer n.hub.Unregister(client)

	// Send initial connection event.
	// #nosec G705 -- token and role are checked/resolved server-side and do not contain HTML/XSS payloads
	fmt.Fprintf(w, "event: connected\ndata: {\"client_id\":%q,\"role\":%q}\n\n", token, role)
	flusher.Flush()

	log.Printf("[NOTIF] SSE stream opened: tenant_id=%s role=%s", tenantID, role)

	// Stream loop.
	ctx := r.Context()
	for {
		select {
		case <-ctx.Done():
			log.Printf("[NOTIF] SSE stream closed (client disconnect) tenant_id=%s", tenantID)
			return
		case msg, ok := <-client.Send:
			if !ok {
				return
			}
			if _, err := w.Write(msg); err != nil {
				log.Printf("[ERROR] failed to write stream chunk: %v", err)
				return
			}
			flusher.Flush()
		}
	}
}

func (n *Notification) verifyAndResolve(token string) (string, hub.Role, bool, error) {
	if token == "" {
		return "", "", false, nil
	}

	// 1. Primary trust boundary: Validate JWT token signature and expiry locally
	claims, err := jwtutil.ValidateToken(token)
	if err != nil {
		log.Printf("[NOTIF] JWT validation failed: %v", err)
		return "", "", false, nil
	}

	// 2. Secondary trust boundary: verify against auth-service using extracted user ID (internal call)
	authURL := fmt.Sprintf("%s/auth/user?id=%s", n.authServiceURL, claims.UserID)
	// #nosec G704 -- authServiceURL is config-controlled and claims.UserID is cryptographically verified from JWT
	req, err := http.NewRequest("GET", authURL, nil)
	if err != nil {
		log.Printf("[NOTIF] Error building auth-service request: %v", err)
		return "", "", false, err
	}
	req.Header.Set("X-Internal-Token", n.internalServiceToken)
	resp, err := n.resilienceClient.Do(req)
	if err != nil {
		log.Printf("[NOTIF] Error calling auth-service: %v", err)
		return "", "", false, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		// #nosec G706 -- claims.UserID is validated and sourced from cryptographically signed JWT token
		log.Printf("[NOTIF] Auth service returned status %d for user ID %s", resp.StatusCode, claims.UserID)
		return "", "", false, nil
	}

	var user struct {
		ID       string `json:"id"`
		Role     string `json:"role"`
		TenantID string `json:"tenant_id"`
		IsActive bool   `json:"is_active"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&user); err != nil {
		log.Printf("[NOTIF] Failed to decode user from auth-service: %v", err)
		return "", "", false, err
	}

	if !user.IsActive {
		log.Printf("[NOTIF] User %s is not active", user.ID)
		return "", "", false, nil
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

	return user.TenantID, r, true, nil
}

// ---------------------------------------------------------------------------
// POST /notifications/send
// ---------------------------------------------------------------------------

// sendRequest is the expected JSON body for POST /notifications/send.
type sendRequest struct {
	Type     string     `json:"type"`
	TenantID string     `json:"tenant_id"`
	UserID   string     `json:"user_id,omitempty"`
	UserIDs  []string   `json:"user_ids,omitempty"`
	Global   bool       `json:"global,omitempty"`
	Title    string     `json:"title"`
	Body     string     `json:"body"`
	Roles    []hub.Role `json:"roles,omitempty"` // empty = broadcast to all roles
}

// Send pushes a notification to matching connected clients.
func (n *Notification) Send(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use POST"})
		return
	}

	gotToken := r.Header.Get("X-Internal-Token")
	if subtle.ConstantTimeCompare([]byte(gotToken), []byte(n.internalServiceToken)) != 1 {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized: internal token required"})
		return
	}

	ip := handlerutil.GetIP(r)
	if limited, remaining := n.limiter.CheckAndRecord(ip); limited {
		writeJSON(w, http.StatusTooManyRequests, map[string]string{
			"error": fmt.Sprintf("too many requests, locked out for %.0f seconds", remaining.Seconds()),
		})
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
	if req.TenantID == "" && !req.Global {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "tenant_id is required unless global is true"})
		return
	}

	notif := hub.Notification{
		ID:        fmt.Sprintf("notif-%d", time.Now().UnixNano()),
		Type:      req.Type,
		TenantID:  req.TenantID,
		UserID:    req.UserID,
		UserIDs:   req.UserIDs,
		Global:    req.Global,
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
		"message":        "notification dispatched",
		"notification":   notif,
		"active_clients": n.hub.ClientCount(),
	})
}

// ---------------------------------------------------------------------------
// POST /notifications/broadcast/job-alert
// ---------------------------------------------------------------------------

type jobAlertRequest struct {
	TenantID    string `json:"tenant_id"`
	JobID       string `json:"job_id"`
	EmployeeID  string `json:"employee_id,omitempty"`
	ServiceName string `json:"service_name"`
	Description string `json:"description"`
}

// BroadcastJobAlert sends a New Job Alert to all role pools for a tenant.
func (n *Notification) BroadcastJobAlert(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use POST"})
		return
	}

	gotToken := r.Header.Get("X-Internal-Token")
	if subtle.ConstantTimeCompare([]byte(gotToken), []byte(n.internalServiceToken)) != 1 {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized: internal token required"})
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
		UserID:    req.EmployeeID,
		Title:     "🆕 New Job Alert",
		Body:      fmt.Sprintf("New job %s for service %s: %s", req.JobID, req.ServiceName, req.Description),
		Roles:     []hub.Role{hub.RoleOwner, hub.RoleEmployee, hub.RoleClient},
		Timestamp: time.Now().UTC(),
	}

	n.hub.Broadcast(notif)

	writeJSON(w, http.StatusOK, map[string]any{
		"message":         "job alert broadcast sent",
		"notification":    notif,
		"active_clients":  n.hub.ClientCount(),
		"clients_by_role": n.hub.ClientsByRole(),
	})
}

func writeBytes(w http.ResponseWriter, data []byte) {
	handlerutil.WriteBytes(w, data)
}

func writeJSON(w http.ResponseWriter, status int, data any) {
	handlerutil.WriteJSON(w, status, data)
}

// acquireStreamSlot reserves one concurrent SSE stream slot for the tenant,
// returning false when the tenant already holds the maximum allowed.
func (n *Notification) acquireStreamSlot(tenantID string) bool {
	n.streamCapsMu.Lock()
	defer n.streamCapsMu.Unlock()
	if n.streamCaps[tenantID] >= maxConcurrentStreamsPerTenant {
		return false
	}
	n.streamCaps[tenantID]++
	return true
}

// releaseStreamSlot returns a previously acquired SSE stream slot.
func (n *Notification) releaseStreamSlot(tenantID string) {
	n.streamCapsMu.Lock()
	defer n.streamCapsMu.Unlock()
	if n.streamCaps[tenantID] > 0 {
		n.streamCaps[tenantID]--
	}
}
