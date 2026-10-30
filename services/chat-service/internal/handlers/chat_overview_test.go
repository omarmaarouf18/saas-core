package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestChat_GetInternalOverviewStats(t *testing.T) {
	c, mongoStore, _, _ := setupAdminTicketsTestEnvironment(t)
	ctx := context.Background()

	// Seed tickets:
	// 1. Pending ticket
	t1, err := mongoStore.CreateTicketAndAssign(ctx, "cust-1", "job-1")
	if err != nil {
		t.Fatalf("failed to seed ticket 1: %v", err)
	}
	// 2. Pending ticket
	t2, err := mongoStore.CreateTicketAndAssign(ctx, "cust-2", "job-2")
	if err != nil {
		t.Fatalf("failed to seed ticket 2: %v", err)
	}
	// 3. Assigned ticket
	t3, err := mongoStore.CreateTicketAndAssign(ctx, "cust-3", "job-3")
	if err != nil {
		t.Fatalf("failed to seed ticket 3: %v", err)
	}
	if _, err := mongoStore.AdminAcceptTicket(ctx, t3.ID, "reviewer-agent"); err != nil {
		t.Fatalf("failed to accept ticket 3: %v", err)
	}
	// 4. Resolved ticket
	t4, err := mongoStore.CreateTicketAndAssign(ctx, "cust-4", "job-4")
	if err != nil {
		t.Fatalf("failed to seed ticket 4: %v", err)
	}
	if _, err := mongoStore.AdminResolveTicket(ctx, t4.ID, "resolved note", "reviewer-admin"); err != nil {
		t.Fatalf("failed to resolve ticket 4: %v", err)
	}

	_ = t1
	_ = t2

	// 1. Unauthorized without internal token
	reqNoAuth := httptest.NewRequest(http.MethodGet, "/chat/internal/overview-stats", nil)
	recNoAuth := httptest.NewRecorder()
	c.GetInternalOverviewStats(recNoAuth, reqNoAuth)
	if recNoAuth.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 Unauthorized, got %d", recNoAuth.Code)
	}

	// 2. Method not allowed
	reqPost := httptest.NewRequest(http.MethodPost, "/chat/internal/overview-stats", nil)
	reqPost.Header.Set("X-Internal-Token", c.internalServiceToken)
	recPost := httptest.NewRecorder()
	c.GetInternalOverviewStats(recPost, reqPost)
	if recPost.Code != http.StatusMethodNotAllowed {
		t.Fatalf("expected 405 Method Not Allowed, got %d", recPost.Code)
	}

	// 3. Success
	req := httptest.NewRequest(http.MethodGet, "/chat/internal/overview-stats", nil)
	req.Header.Set("X-Internal-Token", c.internalServiceToken)
	rec := httptest.NewRecorder()
	c.GetInternalOverviewStats(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK, got %d: %s", rec.Code, rec.Body.String())
	}

	var stats map[string]int64
	if err := json.Unmarshal(rec.Body.Bytes(), &stats); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}

	if stats["open_tickets"] < 2 {
		t.Errorf("expected at least 2 open_tickets, got %d", stats["open_tickets"])
	}
	if stats["assigned_tickets"] < 1 {
		t.Errorf("expected at least 1 assigned_tickets, got %d", stats["assigned_tickets"])
	}
}
