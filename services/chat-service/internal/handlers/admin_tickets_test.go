package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/project/chat-service/internal/chat"
	"github.com/project/chat-service/internal/config"
	"github.com/project/chat-service/internal/store"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

func setupAdminTicketsTestEnvironment(t *testing.T) (*Chat, *store.MongoDB, string, *httptest.Server) {
	t.Helper()

	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://root:devpassword123@localhost:27017/saas_platform?authSource=admin"
	}
	dbName := fmt.Sprintf("saas_chat_test_%d", time.Now().UnixNano())
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	mongoStore, err := store.NewMongoDB(ctx, mongoURI, dbName)
	if err != nil {
		t.Fatalf("failed to connect to mongodb for test: %v", err)
	}

	validReviewerToken := "valid-reviewer-tickets-token"

	// Mock Auth Service for reviewer verification
	mockServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		internalTok := r.Header.Get("X-Internal-Token")
		if internalTok != "test-internal-token" {
			w.WriteHeader(http.StatusForbidden)
			_, _ = w.Write([]byte(`{"error":"invalid internal token"}`))
			return
		}

		if r.URL.Path == "/auth/reviewer/verify" {
			revTok := r.Header.Get("X-Reviewer-Token")
			if revTok == validReviewerToken {
				w.WriteHeader(http.StatusOK)
				_, _ = w.Write([]byte(`{"id":"reviewer-ticket-admin","name":"Support Ops Admin"}`))
				return
			}
			w.WriteHeader(http.StatusUnauthorized)
			_, _ = w.Write([]byte(`{"error":"invalid reviewer token"}`))
			return
		}

		w.WriteHeader(http.StatusNotFound)
	}))

	t.Cleanup(func() {
		mockServer.Close()
		dropCtx, dropCancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer dropCancel()
		client, err := mongo.Connect(dropCtx, options.Client().ApplyURI(mongoURI))
		if err == nil {
			_ = client.Database(dbName).Drop(dropCtx)
			_ = client.Disconnect(dropCtx)
		}
	})

	cfg := &config.Config{
		InternalServiceToken: "test-internal-token",
		AuthServiceURL:       mockServer.URL,
	}

	hub := chat.NewHub()
	go hub.Run()

	c := NewChat(hub, mongoStore, cfg, nil)
	return c, mongoStore, validReviewerToken, mockServer
}

func TestAdminTickets_Authentication(t *testing.T) {
	c, _, validToken, _ := setupAdminTicketsTestEnvironment(t)

	t.Run("Missing Internal Token Rejected", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/chat/admin/tickets", nil)
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		c.AdminListTickets(rec, req)

		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("expected 401 Unauthorized, got %d", rec.Code)
		}
	})

	t.Run("Missing Reviewer Token Rejected", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/chat/admin/tickets", nil)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		rec := httptest.NewRecorder()
		c.AdminListTickets(rec, req)

		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("expected 401 Unauthorized, got %d", rec.Code)
		}
	})

	t.Run("Invalid Reviewer Token Rejected", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/chat/admin/tickets", nil)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", "invalid-reviewer-token")
		rec := httptest.NewRecorder()
		c.AdminListTickets(rec, req)

		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("expected 401 Unauthorized, got %d", rec.Code)
		}
	})

	t.Run("Valid Reviewer Token Succeeded", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/chat/admin/tickets", nil)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		c.AdminListTickets(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 OK, got %d: %s", rec.Code, rec.Body.String())
		}
	})
}

func TestAdminTickets_ListingAndFiltering(t *testing.T) {
	c, mongoStore, validToken, _ := setupAdminTicketsTestEnvironment(t)
	ctx := context.Background()

	// Seed 3 tickets
	t1, err := mongoStore.CreateTicketAndAssign(ctx, "cust-alpha", "job-101")
	if err != nil {
		t.Fatalf("failed to create ticket 1: %v", err)
	}
	t2, err := mongoStore.CreateTicketAndAssign(ctx, "cust-beta", "job-102")
	if err != nil {
		t.Fatalf("failed to create ticket 2: %v", err)
	}
	t3, err := mongoStore.CreateTicketAndAssign(ctx, "cust-gamma", "job-103")
	if err != nil {
		t.Fatalf("failed to create ticket 3: %v", err)
	}

	// Resolve t1
	_ = mongoStore.ResolveTicket(ctx, t1.ID)

	t.Run("List All Tickets", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/chat/admin/tickets", nil)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		c.AdminListTickets(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 OK, got %d: %s", rec.Code, rec.Body.String())
		}

		var resp AdminListTicketsResponse
		_ = json.NewDecoder(rec.Body).Decode(&resp)
		if resp.Total != 3 {
			t.Fatalf("expected 3 total tickets, got %d", resp.Total)
		}
	})

	t.Run("Filter By Status Resolved", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/chat/admin/tickets?status=resolved", nil)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		c.AdminListTickets(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 OK, got %d: %s", rec.Code, rec.Body.String())
		}

		var resp AdminListTicketsResponse
		_ = json.NewDecoder(rec.Body).Decode(&resp)
		if resp.Total != 1 || resp.Tickets[0].ID != t1.ID {
			t.Fatalf("expected ticket %s in resolved filter, got %+v", t1.ID, resp)
		}
	})

	t.Run("Search By Customer ID", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/chat/admin/tickets?search=beta", nil)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		c.AdminListTickets(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 OK, got %d: %s", rec.Code, rec.Body.String())
		}

		var resp AdminListTicketsResponse
		_ = json.NewDecoder(rec.Body).Decode(&resp)
		if resp.Total != 1 || resp.Tickets[0].ID != t2.ID {
			t.Fatalf("expected ticket %s for beta search, got %+v", t2.ID, resp)
		}
	})

	_ = t3
}

func TestAdminTickets_ResolutionLifecycleAndValidation(t *testing.T) {
	c, mongoStore, validToken, _ := setupAdminTicketsTestEnvironment(t)
	ctx := context.Background()

	ticket, err := mongoStore.CreateTicketAndAssign(ctx, "cust-resolve-test", "job-resolve-99")
	if err != nil {
		t.Fatalf("failed to create ticket: %v", err)
	}

	t.Run("Mandatory Note Validation", func(t *testing.T) {
		cases := []struct {
			name string
			note string
		}{
			{"Empty Note", ""},
			{"Whitespace Note", "    "},
			{"Oversized Note", strings.Repeat("a", 1001)},
		}

		for _, tc := range cases {
			t.Run(tc.name, func(t *testing.T) {
				body, _ := json.Marshal(AdminResolveTicketRequest{
					TicketID:       ticket.ID,
					ResolutionNote: tc.note,
				})
				req := httptest.NewRequest(http.MethodPost, "/chat/admin/tickets/resolve", bytes.NewReader(body))
				req.Header.Set("X-Internal-Token", "test-internal-token")
				req.Header.Set("X-Reviewer-Token", validToken)
				rec := httptest.NewRecorder()
				c.AdminResolveTicket(rec, req)

				if rec.Code != http.StatusBadRequest {
					t.Fatalf("expected 400 Bad Request for %s, got %d: %s", tc.name, rec.Code, rec.Body.String())
				}
			})
		}
	})

	t.Run("Valid Resolution", func(t *testing.T) {
		body, _ := json.Marshal(AdminResolveTicketRequest{
			TicketID:       ticket.ID,
			ResolutionNote: "Customer issue resolved via refund coupon and phone follow-up.",
		})
		req := httptest.NewRequest(http.MethodPost, "/chat/admin/tickets/resolve", bytes.NewReader(body))
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		c.AdminResolveTicket(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 OK, got %d: %s", rec.Code, rec.Body.String())
		}

		resolved, err := mongoStore.GetTicket(ctx, ticket.ID)
		if err != nil {
			t.Fatalf("failed to get ticket: %v", err)
		}
		if resolved.Status != "resolved" {
			t.Fatalf("expected status resolved, got %s", resolved.Status)
		}
		if resolved.ResolvedBy != "reviewer-ticket-admin" {
			t.Errorf("expected resolved_by reviewer-ticket-admin, got %s", resolved.ResolvedBy)
		}
		if resolved.ResolutionNote != "Customer issue resolved via refund coupon and phone follow-up." {
			t.Errorf("unexpected resolution note: %s", resolved.ResolutionNote)
		}
		if resolved.ResolvedAt == nil {
			t.Errorf("expected non-nil resolved_at")
		}
	})

	t.Run("Resolve Already Resolved Ticket Rejection", func(t *testing.T) {
		body, _ := json.Marshal(AdminResolveTicketRequest{
			TicketID:       ticket.ID,
			ResolutionNote: "Duplicate resolve attempt",
		})
		req := httptest.NewRequest(http.MethodPost, "/chat/admin/tickets/resolve", bytes.NewReader(body))
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		c.AdminResolveTicket(rec, req)

		if rec.Code != http.StatusConflict {
			t.Fatalf("expected 409 Conflict when resolving already resolved ticket, got %d", rec.Code)
		}
	})
}

func TestAdminTickets_CASConcurrencyRace(t *testing.T) {
	c, mongoStore, validToken, _ := setupAdminTicketsTestEnvironment(t)
	ctx := context.Background()

	ticket, err := mongoStore.CreateTicketAndAssign(ctx, "cust-race", "job-race-88")
	if err != nil {
		t.Fatalf("failed to create ticket: %v", err)
	}

	var wg sync.WaitGroup
	results := make([]int, 2)

	for i := 0; i < 2; i++ {
		wg.Add(1)
		idx := i
		go func() {
			defer wg.Done()
			body, _ := json.Marshal(AdminResolveTicketRequest{
				TicketID:       ticket.ID,
				ResolutionNote: fmt.Sprintf("Concurrent resolution note from worker %d", idx),
			})
			req := httptest.NewRequest(http.MethodPost, "/chat/admin/tickets/resolve", bytes.NewReader(body))
			req.Header.Set("X-Internal-Token", "test-internal-token")
			req.Header.Set("X-Reviewer-Token", validToken)
			rec := httptest.NewRecorder()
			c.AdminResolveTicket(rec, req)
			results[idx] = rec.Code
		}()
	}

	wg.Wait()

	count200 := 0
	count409 := 0
	for _, code := range results {
		if code == http.StatusOK {
			count200++
		} else if code == http.StatusConflict {
			count409++
		}
	}

	if count200 != 1 || count409 != 1 {
		t.Fatalf("CAS concurrency race failed: expected exactly 1 200 OK and 1 409 Conflict, got %+v", results)
	}
}
