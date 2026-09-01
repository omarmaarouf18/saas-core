package handlers

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"strings"

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
	if internalToken == "" || internalToken != c.internalServiceToken {
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

// AdminResolveTicket marks a ticket as resolved with mandatory notes (ADR-0023).
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

	handlerutil.ShipSecurityEvent(ctx, "ADMIN_TICKET_RESOLVED", "chat-service", reviewer.ID, ticket.CustomerID, fmt.Sprintf("resolved ticket %s (customer=%s, note=%s)", ticket.ID, ticket.CustomerID, note), handlerutil.GetClientIP(r))

	writeJSON(w, http.StatusOK, map[string]any{
		"message": "ticket resolved successfully",
		"ticket":  ticket,
	})
}
