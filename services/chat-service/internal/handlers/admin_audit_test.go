package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/project/chat-service/internal/store"
)

// TestAdminAudit_TicketAcceptPersistsAndServesInternally checks that a
// reviewer ticket accept writes a chat-service admin_audit record and that
// GET /chat/internal/admin-audit serves it to internal-token callers only
// (ADMIN-API-FIX).
func TestAdminAudit_TicketAcceptPersistsAndServesInternally(t *testing.T) {
	c, mongoStore, validToken, authServer := setupAdminTicketsTestEnvironment(t)
	defer authServer.Close()
	ctx := context.Background()

	ticket, err := mongoStore.CreateTicketAndAssign(ctx, "cust-audit-1", "job-audit-201")
	if err != nil {
		t.Fatalf("create ticket: %v", err)
	}
	req := httptest.NewRequest(http.MethodPost, "/chat/admin/tickets/accept", bytes.NewReader([]byte(fmt.Sprintf(`{"ticket_id":"%s"}`, ticket.ID))))
	req.Header.Set("X-Internal-Token", "test-internal-token")
	req.Header.Set("X-Reviewer-Token", validToken)
	req.Header.Set("X-Request-ID", "req-accept-1")
	rec := httptest.NewRecorder()
	c.AdminAcceptTicket(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("accept: expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	records, total, err := mongoStore.ListAdminAudit(ctx, store.AdminAuditFilter{Action: "ticket.accept"}, 10)
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if total != 1 {
		t.Fatalf("expected 1 ticket.accept record, got %d", total)
	}
	got := records[0]
	if got.Source != "chat-service" || got.ActorID == "" || got.TargetType != "ticket" || got.TargetID != ticket.ID || got.RequestID != "req-accept-1" || got.CreatedAt.IsZero() {
		t.Fatalf("unexpected record: %+v", got)
	}

	mux := http.NewServeMux()
	c.RegisterRoutes(mux)
	noTok := httptest.NewRecorder()
	mux.ServeHTTP(noTok, httptest.NewRequest(http.MethodGet, "/chat/internal/admin-audit", nil))
	if noTok.Code != http.StatusUnauthorized {
		t.Fatalf("internal endpoint without token: expected 401, got %d", noTok.Code)
	}
	listReq := httptest.NewRequest(http.MethodGet, "/chat/internal/admin-audit?target_id="+ticket.ID, nil)
	listReq.Header.Set("X-Internal-Token", "test-internal-token")
	listRec := httptest.NewRecorder()
	mux.ServeHTTP(listRec, listReq)
	var resp struct {
		Entries []store.AdminAuditRecord `json:"entries"`
		Total   int64                    `json:"total"`
	}
	if err := json.Unmarshal(listRec.Body.Bytes(), &resp); err != nil || listRec.Code != http.StatusOK {
		t.Fatalf("internal list: %d %s (%v)", listRec.Code, listRec.Body.String(), err)
	}
	if resp.Total != 1 || resp.Entries[0].ID != got.ID {
		t.Fatalf("internal list: %+v", resp)
	}
}
