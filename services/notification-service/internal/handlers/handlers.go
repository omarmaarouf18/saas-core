// Package handlers implements HTTP handlers for the notification-service.
package handlers

import (
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/project/notification-service/internal/config"
	"github.com/project/notification-service/internal/hub"
	"github.com/project/notification-service/internal/store"
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
	store                store.Store
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
func NewNotification(h *hub.SSEHub, st store.Store, cfg *config.Config, rdb *redis.Client) *Notification {
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
		store:                st,
		authServiceURL:       cfg.AuthServiceURL,
		allowedOrigin:        allowedOrigin,
		limiter:              handlerutil.NewRateLimiter(rl),
		streamLimiter:        handlerutil.NewRateLimiter(streamRl),
		streamCaps:           make(map[string]int),
		internalServiceToken: cfg.InternalServiceToken,
		resilienceClient:     resClient,
	}
}

// SetStore dynamically sets the persistence store.
func (n *Notification) SetStore(st store.Store) {
	n.store = st
}

// RegisterRoutes mounts notification endpoints.
func (n *Notification) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/notifications/stream", n.Stream)
	mux.HandleFunc("/notifications/send", n.Send)
	mux.HandleFunc("/notifications/broadcast/job-alert", n.BroadcastJobAlert)
	mux.HandleFunc("/notifications/history", n.History)
	mux.HandleFunc("/notifications/read-all", n.ReadAll)
	mux.HandleFunc("/notifications/{id}/read", n.MarkRead)
	mux.HandleFunc("/notifications/{id}", func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		case http.MethodDelete:
			n.Delete(w, r)
		default:
			writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use DELETE"})
		}
	})
	mux.HandleFunc("/notifications", func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		case http.MethodDelete:
			n.DeleteAll(w, r)
		default:
			writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use DELETE"})
		}
	})
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

func (n *Notification) resolveToken(token string) (string, string, hub.Role, bool, error) {
	if token == "" {
		return "", "", "", false, nil
	}

	// 1. Primary trust boundary: Validate JWT token signature and expiry locally
	claims, err := jwtutil.ValidateToken(token)
	if err != nil {
		log.Printf("[NOTIF] JWT validation failed: %v", err)
		return "", "", "", false, nil
	}

	// 2. Secondary trust boundary: verify against auth-service using extracted user ID (internal call)
	authURL := fmt.Sprintf("%s/auth/user?id=%s", n.authServiceURL, claims.UserID)
	// #nosec G704 -- authServiceURL is config-controlled and claims.UserID is cryptographically verified from JWT
	req, err := http.NewRequest("GET", authURL, nil)
	if err != nil {
		log.Printf("[NOTIF] Error building auth-service request: %v", err)
		return "", "", "", false, err
	}
	req.Header.Set("X-Internal-Token", n.internalServiceToken)
	resp, err := n.resilienceClient.Do(req)
	if err != nil {
		log.Printf("[NOTIF] Error calling auth-service: %v", err)
		return "", "", "", false, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		// #nosec G706 -- claims.UserID is validated and sourced from cryptographically signed JWT token
		log.Printf("[NOTIF] Auth service returned status %d for user ID %s", resp.StatusCode, claims.UserID)
		return "", "", "", false, nil
	}

	var user struct {
		ID       string `json:"id"`
		Role     string `json:"role"`
		TenantID string `json:"tenant_id"`
		IsActive bool   `json:"is_active"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&user); err != nil {
		log.Printf("[NOTIF] Failed to decode user from auth-service: %v", err)
		return "", "", "", false, err
	}

	if !user.IsActive {
		log.Printf("[NOTIF] User %s is not active", user.ID)
		return "", "", "", false, nil
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

	return user.ID, user.TenantID, r, true, nil
}

func (n *Notification) verifyAndResolve(token string) (string, hub.Role, bool, error) {
	_, tenantID, role, ok, err := n.resolveToken(token)
	return tenantID, role, ok, err
}

func (n *Notification) authenticateHeader(r *http.Request) (userID, tenantID string, role hub.Role, status int, errMsg string) {
	authHeader := r.Header.Get("Authorization")
	if authHeader == "" {
		return "", "", "", http.StatusUnauthorized, "authorization header required"
	}
	parts := strings.SplitN(authHeader, " ", 2)
	if len(parts) != 2 || !strings.EqualFold(parts[0], "bearer") {
		return "", "", "", http.StatusUnauthorized, "invalid authorization format, expected Bearer <token>"
	}
	token := strings.TrimSpace(parts[1])
	if token == "" {
		return "", "", "", http.StatusUnauthorized, "bearer token cannot be empty"
	}

	uID, tID, rRole, ok, err := n.resolveToken(token)
	if err != nil {
		return "", "", "", http.StatusServiceUnavailable, "authentication service temporarily unavailable"
	}
	if !ok {
		return "", "", "", http.StatusUnauthorized, "invalid or expired token"
	}
	return uID, tID, rRole, http.StatusOK, ""
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
	// Empty-secret guard (QA audit Q23): never authenticate when unconfigured.
	if n.internalServiceToken == "" || subtle.ConstantTimeCompare([]byte(gotToken), []byte(n.internalServiceToken)) != 1 {
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

	if n.store != nil {
		roles := make([]string, len(notif.Roles))
		for i, r := range notif.Roles {
			roles[i] = string(r)
		}
		storeDoc := &store.Notification{
			ID:        notif.ID,
			Type:      notif.Type,
			TenantID:  notif.TenantID,
			UserID:    notif.UserID,
			UserIDs:   notif.UserIDs,
			Global:    notif.Global,
			Title:     notif.Title,
			Body:      notif.Body,
			Roles:     roles,
			Timestamp: notif.Timestamp,
			IsRead:    false,
		}
		if err := n.store.InsertNotification(r.Context(), storeDoc); err != nil {
			log.Printf("[NOTIF-STORE] Failed to persist notification %s: %v", notif.ID, err)
		}
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
	// Empty-secret guard (QA audit Q23): never authenticate when unconfigured.
	if n.internalServiceToken == "" || subtle.ConstantTimeCompare([]byte(gotToken), []byte(n.internalServiceToken)) != 1 {
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

	if n.store != nil {
		roles := make([]string, len(notif.Roles))
		for i, r := range notif.Roles {
			roles[i] = string(r)
		}
		storeDoc := &store.Notification{
			ID:        notif.ID,
			Type:      notif.Type,
			TenantID:  notif.TenantID,
			UserID:    notif.UserID,
			Title:     notif.Title,
			Body:      notif.Body,
			Roles:     roles,
			Timestamp: notif.Timestamp,
			IsRead:    false,
		}
		if err := n.store.InsertNotification(r.Context(), storeDoc); err != nil {
			log.Printf("[NOTIF-STORE] Failed to persist job alert %s: %v", notif.ID, err)
		}
	}

	n.hub.Broadcast(notif)

	writeJSON(w, http.StatusOK, map[string]any{
		"message":         "job alert broadcast sent",
		"notification":    notif,
		"active_clients":  n.hub.ClientCount(),
		"clients_by_role": n.hub.ClientsByRole(),
	})
}

// ---------------------------------------------------------------------------
// GET /notifications/history?limit=&before=
// ---------------------------------------------------------------------------

// History returns the authenticated user's persisted notification history.
func (n *Notification) History(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use GET"})
		return
	}

	userID, tenantID, role, status, errMsg := n.authenticateHeader(r)
	if status != http.StatusOK {
		writeJSON(w, status, map[string]string{"error": errMsg})
		return
	}

	limit := 30
	if lStr := r.URL.Query().Get("limit"); lStr != "" {
		if parsed, err := strconv.Atoi(lStr); err == nil && parsed > 0 {
			limit = parsed
			if limit > 100 {
				limit = 100
			}
		}
	}

	var before *time.Time
	if bStr := r.URL.Query().Get("before"); bStr != "" {
		if parsed, err := time.Parse(time.RFC3339Nano, bStr); err == nil {
			before = &parsed
		} else if parsed, err := time.Parse(time.RFC3339, bStr); err == nil {
			before = &parsed
		}
	}

	if n.store == nil {
		writeJSON(w, http.StatusOK, map[string]any{
			"notifications": []store.Notification{},
			"has_more":      false,
		})
		return
	}

	roles := []string{string(role)}
	items, err := n.store.ListForUser(r.Context(), tenantID, userID, roles, limit, before)
	if err != nil {
		log.Printf("[NOTIF] Failed to list notifications: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to list notifications"})
		return
	}

	hasMore := len(items) == limit

	writeJSON(w, http.StatusOK, map[string]any{
		"notifications": items,
		"has_more":      hasMore,
	})
}

// ---------------------------------------------------------------------------
// POST /notifications/{id}/read
// ---------------------------------------------------------------------------

// MarkRead marks a single notification as read for the authenticated user.
func (n *Notification) MarkRead(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use POST"})
		return
	}

	userID, tenantID, _, status, errMsg := n.authenticateHeader(r)
	if status != http.StatusOK {
		writeJSON(w, status, map[string]string{"error": errMsg})
		return
	}

	id := r.PathValue("id")
	if id == "" {
		trimmed := strings.TrimPrefix(r.URL.Path, "/notifications/")
		id = strings.TrimSuffix(trimmed, "/read")
	}
	if id == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "notification id required"})
		return
	}

	if n.store != nil {
		err := n.store.MarkRead(r.Context(), tenantID, userID, id)
		if err != nil {
			if errors.Is(err, store.ErrNotFound) {
				writeJSON(w, http.StatusNotFound, map[string]string{"error": "notification not found"})
				return
			}
			log.Printf("[NOTIF] Failed to mark read: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to mark notification as read"})
			return
		}
	}

	writeJSON(w, http.StatusOK, map[string]string{"message": "notification marked as read"})
}

// ---------------------------------------------------------------------------
// POST /notifications/read-all
// ---------------------------------------------------------------------------

// ReadAll marks all notifications read for the authenticated user.
func (n *Notification) ReadAll(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use POST"})
		return
	}

	userID, tenantID, _, status, errMsg := n.authenticateHeader(r)
	if status != http.StatusOK {
		writeJSON(w, status, map[string]string{"error": errMsg})
		return
	}

	if n.store != nil {
		if err := n.store.MarkAllRead(r.Context(), tenantID, userID); err != nil {
			log.Printf("[NOTIF] Failed to mark all read: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to mark all notifications as read"})
			return
		}
	}

	writeJSON(w, http.StatusOK, map[string]string{"message": "all notifications marked as read"})
}

// ---------------------------------------------------------------------------
// DELETE /notifications/{id}
// ---------------------------------------------------------------------------

// Delete removes a single notification for the authenticated user.
func (n *Notification) Delete(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodDelete {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use DELETE"})
		return
	}

	userID, tenantID, _, status, errMsg := n.authenticateHeader(r)
	if status != http.StatusOK {
		writeJSON(w, status, map[string]string{"error": errMsg})
		return
	}

	id := r.PathValue("id")
	if id == "" {
		id = strings.TrimPrefix(r.URL.Path, "/notifications/")
	}
	if id == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "notification id required"})
		return
	}

	if n.store != nil {
		err := n.store.Delete(r.Context(), tenantID, userID, id)
		if err != nil {
			if errors.Is(err, store.ErrNotFound) {
				writeJSON(w, http.StatusNotFound, map[string]string{"error": "notification not found"})
				return
			}
			log.Printf("[NOTIF] Failed to delete: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to delete notification"})
			return
		}
	}

	writeJSON(w, http.StatusOK, map[string]string{"message": "notification deleted"})
}

// ---------------------------------------------------------------------------
// DELETE /notifications
// ---------------------------------------------------------------------------

// DeleteAll clears all notifications for the authenticated user.
func (n *Notification) DeleteAll(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodDelete {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use DELETE"})
		return
	}

	userID, tenantID, _, status, errMsg := n.authenticateHeader(r)
	if status != http.StatusOK {
		writeJSON(w, status, map[string]string{"error": errMsg})
		return
	}

	if n.store != nil {
		if err := n.store.DeleteAll(r.Context(), tenantID, userID); err != nil {
			log.Printf("[NOTIF] Failed to delete all: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to delete all notifications"})
			return
		}
	}

	writeJSON(w, http.StatusOK, map[string]string{"message": "all notifications deleted"})
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
