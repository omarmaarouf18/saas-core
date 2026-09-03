package handlers

import (
	"bytes"
	"context"
	"crypto/subtle"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/project/chat-service/internal/chat"
	"github.com/project/chat-service/internal/store"
	"github.com/project/shared/infra/handlerutil"
)

// ReviewerClaims represents the validated reviewer identity from auth-service.
type ReviewerClaims struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

// authenticateReviewer validates that the inbound request contains valid X-Internal-Token
// and a reviewer token verified by auth-service (ADR-0021/ADR-0023).
func (c *Chat) authenticateReviewer(r *http.Request) (*ReviewerClaims, error) {
	internalToken := r.Header.Get("X-Internal-Token")
	if c.internalServiceToken == "" || subtle.ConstantTimeCompare([]byte(internalToken), []byte(c.internalServiceToken)) != 1 {
		return nil, fmt.Errorf("missing or invalid X-Internal-Token")
	}

	reviewerToken := r.Header.Get("X-Reviewer-Token")
	if reviewerToken == "" {
		reviewerToken = r.Header.Get("Authorization")
		if strings.HasPrefix(reviewerToken, "Bearer ") {
			reviewerToken = strings.TrimPrefix(reviewerToken, "Bearer ")
		}
	}
	if reviewerToken == "" {
		return nil, fmt.Errorf("missing reviewer token")
	}

	// Verify reviewer credential with auth-service
	reqURL := fmt.Sprintf("%s/auth/reviewer/verify", c.authServiceURL)
	req, err := http.NewRequestWithContext(r.Context(), http.MethodGet, reqURL, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create auth verification request: %w", err)
	}
	req.Header.Set("X-Internal-Token", c.internalServiceToken)
	req.Header.Set("X-Reviewer-Token", reviewerToken)

	resp, err := c.authClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("reviewer verification failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("unauthorized reviewer: status %d", resp.StatusCode)
	}

	var claims ReviewerClaims
	if err := json.NewDecoder(resp.Body).Decode(&claims); err != nil {
		return nil, fmt.Errorf("failed to parse reviewer claims: %w", err)
	}
	return &claims, nil
}

// AdminListTicketsResponse is the JSON response for GET /admin/tickets.
type AdminListTicketsResponse struct {
	Tickets []store.ComplaintTicket `json:"tickets"`
	Total   int                     `json:"total"`
	Page    int                     `json:"page"`
	Limit   int                     `json:"limit"`
}

// AdminResolveTicketRequest is the JSON body for POST /admin/tickets/resolve.
type AdminResolveTicketRequest struct {
	TicketID       string `json:"ticket_id"`
	ResolutionNote string `json:"resolution_note"` // Mandatory (1-1000 characters)
}

// AdminListTickets lists support tickets across all users with status/search filters and pagination (ADR-0023).
// GET /chat/admin/tickets & GET /admin/tickets
func (c *Chat) AdminListTickets(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}

	reviewer, err := c.authenticateReviewer(r)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": err.Error()})
		return
	}

	ctx := r.Context()
	status := strings.TrimSpace(r.URL.Query().Get("status"))
	search := strings.TrimSpace(r.URL.Query().Get("search"))

	page := int64(1)
	if pStr := r.URL.Query().Get("page"); pStr != "" {
		if p, err := strconv.ParseInt(pStr, 10, 64); err == nil && p > 0 {
			page = p
		}
	}

	limit := int64(20)
	if lStr := r.URL.Query().Get("limit"); lStr != "" {
		if l, err := strconv.ParseInt(lStr, 10, 64); err == nil && l > 0 && l <= 100 {
			limit = l
		}
	}

	tickets, total, err := c.store.ListTickets(ctx, status, search, page, limit)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to list tickets: " + err.Error()})
		return
	}

	handlerutil.ShipSecurityEvent(ctx, "ADMIN_TICKETS_LISTED", "chat-service", reviewer.ID, "", fmt.Sprintf("listed %d tickets (total=%d, status=%s, page=%d)", len(tickets), total, status, page), handlerutil.GetClientIP(r))

	writeJSON(w, http.StatusOK, AdminListTicketsResponse{
		Tickets: tickets,
		Total:   int(total),
		Page:    int(page),
		Limit:   int(limit),
	})
}

// dispatchTicketResolvedNotification posts an internal customer notification to notification-service.
func (c *Chat) dispatchTicketResolvedNotification(ctx context.Context, ticket *store.ComplaintTicket, resolutionNote string) (bool, string) {
	if ticket == nil || ticket.CustomerID == "" {
		return false, "missing customer ID"
	}

	notificationURL := c.notificationServiceURL
	if notificationURL == "" {
		notificationURL = "http://notification-service:3004"
	}
	sendURL := strings.TrimSuffix(notificationURL, "/") + "/notifications/send"

	payload := map[string]any{
		"type":    "ticket_resolved",
		"global":  true,
		"user_id": ticket.CustomerID,
		"title":   "Support Ticket Resolved",
		"body":    fmt.Sprintf("Your ticket (%s) has been resolved: %s", ticket.ID, resolutionNote),
	}

	bodyBytes, err := json.Marshal(payload)
	if err != nil {
		log.Printf("[ADMIN-TICKET-NOTIFY] Failed to marshal notification payload for ticket %s: %v", ticket.ID, err)
		return false, err.Error()
	}

	reqCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	// #nosec G704 // internal service URL
	req, err := http.NewRequestWithContext(reqCtx, http.MethodPost, sendURL, bytes.NewReader(bodyBytes))
	if err != nil {
		log.Printf("[ADMIN-TICKET-NOTIFY] Failed to build notification request for ticket %s: %v", ticket.ID, err)
		return false, err.Error()
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Internal-Token", c.internalServiceToken)

	var resp *http.Response
	if c.notificationClient != nil {
		resp, err = c.notificationClient.Do(req)
	} else {
		resp, err = http.DefaultClient.Do(req)
	}
	if err != nil {
		log.Printf("[ADMIN-TICKET-NOTIFY] Failed to dispatch notification for ticket %s to user %s: %v", ticket.ID, ticket.CustomerID, err)
		return false, err.Error()
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		log.Printf("[ADMIN-TICKET-NOTIFY] notification-service returned status %d for ticket %s", resp.StatusCode, ticket.ID)
		return false, fmt.Sprintf("notification-service returned status %d", resp.StatusCode)
	}

	return true, ""
}

// AdminResolveTicket marks a ticket as resolved with mandatory notes (ADR-0023),
// persists a system resolution chat message to the ticket channel, and dispatches a customer notification.
// POST /chat/admin/tickets/resolve & POST /admin/tickets/resolve
func (c *Chat) AdminResolveTicket(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}

	reviewer, err := c.authenticateReviewer(r)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": err.Error()})
		return
	}

	var req AdminResolveTicketRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON: " + err.Error()})
		return
	}

	ticketID := strings.TrimSpace(req.TicketID)
	if ticketID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "ticket_id is required"})
		return
	}

	note := strings.TrimSpace(req.ResolutionNote)
	if len(note) < 1 || len(note) > 1000 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "resolution_note is required (1-1000 characters)"})
		return
	}

	ctx := r.Context()
	ticket, err := c.store.AdminResolveTicket(ctx, ticketID, note, reviewer.ID)
	if err != nil {
		if strings.Contains(err.Error(), "already resolved") || strings.Contains(err.Error(), "concurrently modified") {
			writeJSON(w, http.StatusConflict, map[string]string{"error": err.Error()})
			return
		}
		if strings.Contains(err.Error(), "not found") {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	// 1. Persist system chat message into the ticket channel
	chatMsg := &chat.Message{
		Channel:        "ticket:" + ticket.ID,
		SenderID:       "system:support",
		SenderUsername: "Support Team",
		Content:        fmt.Sprintf("Ticket resolved: %s", note),
		Type:           "ticket_resolution",
	}
	if err := c.store.PersistMessage(ctx, chatMsg); err != nil {
		log.Printf("[ADMIN-TICKET] Failed to persist resolution chat message for ticket %s: %v", ticket.ID, err)
	} else if c.hub != nil {
		select {
		case c.hub.Broadcast <- chatMsg:
		default:
		}
	}

	// 2. Dispatch customer notification via notification-service
	notified, notifyErr := c.dispatchTicketResolvedNotification(ctx, ticket, note)

	handlerutil.ShipSecurityEvent(ctx, "ADMIN_TICKET_RESOLVED", "chat-service", reviewer.ID, ticket.CustomerID, fmt.Sprintf("resolved ticket %s (customer=%s, note=%s, notified=%t)", ticket.ID, ticket.CustomerID, note, notified), handlerutil.GetClientIP(r))

	respData := map[string]any{
		"message":           "ticket resolved successfully",
		"ticket":            ticket,
		"customer_notified": notified,
	}
	if !notified && notifyErr != "" {
		respData["notify_error"] = notifyErr
	}

	writeJSON(w, http.StatusOK, respData)
}
