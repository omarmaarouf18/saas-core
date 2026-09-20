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
	"sync/atomic"
	"testing"
	"time"

	"github.com/project/chat-service/internal/chat"
	"github.com/project/chat-service/internal/config"
	"github.com/project/chat-service/internal/store"
	"github.com/project/shared/infra/resilience"
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

	// Mock Auth & Notification Service
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

		if r.URL.Path == "/notifications/send" {
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte(`{"status":"success","message":"notification sent"}`))
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
		InternalServiceToken:   "test-internal-token",
		AuthServiceURL:         mockServer.URL,
		NotificationServiceURL: mockServer.URL,
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

func TestAdminTickets_Authentication_TransientFailureDiscrimination(t *testing.T) {
	var authStatus int
	var authBody string

	mockAuthServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(authStatus)
		_, _ = w.Write([]byte(authBody))
	}))
	defer mockAuthServer.Close()

	cfg := &config.Config{
		InternalServiceToken:   "test-internal-token",
		AuthServiceURL:         mockAuthServer.URL,
		NotificationServiceURL: mockAuthServer.URL,
	}

	c := NewChat(chat.NewHub(), nil, cfg, nil)

	testCases := []struct {
		name                 string
		status               int
		body                 string
		invalidServerAddress bool
		wantCode             int
	}{
		{
			name:     "Auth-Service 401 Unauthorized -> Chat-Service 401",
			status:   http.StatusUnauthorized,
			body:     `{"error":"invalid or expired reviewer token"}`,
			wantCode: http.StatusUnauthorized,
		},
		{
			name:     "Auth-Service 403 Forbidden -> Chat-Service 401",
			status:   http.StatusForbidden,
			body:     `{"error":"reviewer account suspended"}`,
			wantCode: http.StatusUnauthorized,
		},
		{
			name:     "Auth-Service 429 Too Many Requests -> Chat-Service 503 (Explicitly Not 401)",
			status:   http.StatusTooManyRequests,
			body:     `{"error":"too many requests, try again later"}`,
			wantCode: http.StatusServiceUnavailable,
		},
		{
			name:     "Auth-Service 500 Internal Server Error -> Chat-Service 503 (Explicitly Not 401)",
			status:   http.StatusInternalServerError,
			body:     `{"error":"database connection pool exhausted"}`,
			wantCode: http.StatusServiceUnavailable,
		},
		{
			name:     "Auth-Service 502 Bad Gateway -> Chat-Service 503 (Explicitly Not 401)",
			status:   http.StatusBadGateway,
			body:     `{"error":"bad gateway"}`,
			wantCode: http.StatusServiceUnavailable,
		},
		{
			name:     "Auth-Service 503 Service Unavailable -> Chat-Service 503 (Explicitly Not 401)",
			status:   http.StatusServiceUnavailable,
			body:     `{"error":"upstream down for maintenance"}`,
			wantCode: http.StatusServiceUnavailable,
		},
		{
			name:                 "Network Error / Unreachable Auth-Service -> Chat-Service 503 (Explicitly Not 401)",
			invalidServerAddress: true,
			wantCode:             http.StatusServiceUnavailable,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			authStatus = tc.status
			authBody = tc.body

			if tc.invalidServerAddress {
				c.authServiceURL = "http://127.0.0.1:1" // Unreachable port
			} else {
				c.authServiceURL = mockAuthServer.URL
			}

			// 1. Assert AdminListTickets returns the expected code (and explicitly NOT 401 when 503 expected)
			reqList := httptest.NewRequest(http.MethodGet, "/chat/admin/tickets", nil)
			reqList.Header.Set("X-Internal-Token", "test-internal-token")
			reqList.Header.Set("X-Reviewer-Token", "any-reviewer-token")
			recList := httptest.NewRecorder()
			c.AdminListTickets(recList, reqList)

			if recList.Code != tc.wantCode {
				t.Fatalf("AdminListTickets: expected HTTP %d, got %d (body: %s)", tc.wantCode, recList.Code, recList.Body.String())
			}
			if tc.wantCode == http.StatusServiceUnavailable && recList.Code == http.StatusUnauthorized {
				t.Fatalf("AdminListTickets: transient failure returned HTTP 401 Unauthorized! Must return 503 Service Unavailable")
			}

			// 2. Assert AdminResolveTicket returns the expected code
			bodyResolve := `{"ticket_id":"tkt-123","resolution_note":"Fixed customer issue"}`
			reqResolve := httptest.NewRequest(http.MethodPost, "/chat/admin/tickets/resolve", strings.NewReader(bodyResolve))
			reqResolve.Header.Set("X-Internal-Token", "test-internal-token")
			reqResolve.Header.Set("X-Reviewer-Token", "any-reviewer-token")
			recResolve := httptest.NewRecorder()
			c.AdminResolveTicket(recResolve, reqResolve)

			if recResolve.Code != tc.wantCode {
				t.Fatalf("AdminResolveTicket: expected HTTP %d, got %d (body: %s)", tc.wantCode, recResolve.Code, recResolve.Body.String())
			}
			if tc.wantCode == http.StatusServiceUnavailable && recResolve.Code == http.StatusUnauthorized {
				t.Fatalf("AdminResolveTicket: transient failure returned HTTP 401 Unauthorized! Must return 503 Service Unavailable")
			}

			// 3. Assert AdminAcceptTicket returns the expected code
			reqAccept := httptest.NewRequest(http.MethodPost, "/chat/admin/tickets/accept", strings.NewReader(`{"ticket_id":"tkt-123"}`))
			reqAccept.Header.Set("X-Internal-Token", "test-internal-token")
			reqAccept.Header.Set("X-Reviewer-Token", "any-reviewer-token")
			recAccept := httptest.NewRecorder()
			c.AdminAcceptTicket(recAccept, reqAccept)

			if recAccept.Code != tc.wantCode {
				t.Fatalf("AdminAcceptTicket: expected HTTP %d, got %d (body: %s)", tc.wantCode, recAccept.Code, recAccept.Body.String())
			}
			if tc.wantCode == http.StatusServiceUnavailable && recAccept.Code == http.StatusUnauthorized {
				t.Fatalf("AdminAcceptTicket: transient failure returned HTTP 401 Unauthorized! Must return 503 Service Unavailable")
			}
		})
	}
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
	_, _ = mongoStore.AdminResolveTicket(ctx, t1.ID, "resolved for test", "reviewer-test")

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

func TestAdminResolveTicket_NotificationAndChatMessageDelivery(t *testing.T) {
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://root:devpassword123@localhost:27017/saas_platform?authSource=admin"
	}
	dbName := fmt.Sprintf("saas_chat_test_delivery_%d", time.Now().UnixNano())
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	mongoStore, err := store.NewMongoDB(ctx, mongoURI, dbName)
	if err != nil {
		t.Fatalf("failed to connect to mongodb for test: %v", err)
	}

	validReviewerToken := "valid-reviewer-delivery-token"
	var mu sync.Mutex
	var capturedNotifications []map[string]any
	notificationStatusCode := http.StatusOK

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

		if r.URL.Path == "/notifications/send" {
			mu.Lock()
			defer mu.Unlock()
			if notificationStatusCode != http.StatusOK {
				w.WriteHeader(notificationStatusCode)
				_, _ = w.Write([]byte(`{"error":"notification service temporary outage"}`))
				return
			}
			var payload map[string]any
			_ = json.NewDecoder(r.Body).Decode(&payload)
			capturedNotifications = append(capturedNotifications, payload)
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte(`{"status":"success","message":"notification sent"}`))
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
		InternalServiceToken:   "test-internal-token",
		AuthServiceURL:         mockServer.URL,
		NotificationServiceURL: mockServer.URL,
	}

	hub := chat.NewHub()
	go hub.Run()

	c := NewChat(hub, mongoStore, cfg, nil)

	t.Run("HappyPath_NotifiesCustomerAndPersistsChatMessage", func(t *testing.T) {
		mu.Lock()
		capturedNotifications = nil
		notificationStatusCode = http.StatusOK
		mu.Unlock()

		ticket, err := mongoStore.CreateTicketAndAssign(ctx, "cust-delivery-123", "job-ctx-456")
		if err != nil {
			t.Fatalf("failed to create ticket: %v", err)
		}

		resolutionNote := "Your refund has been credited to your wallet balance."
		body, _ := json.Marshal(AdminResolveTicketRequest{
			TicketID:       ticket.ID,
			ResolutionNote: resolutionNote,
		})
		req := httptest.NewRequest(http.MethodPost, "/chat/admin/tickets/resolve", bytes.NewReader(body))
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validReviewerToken)
		rec := httptest.NewRecorder()
		c.AdminResolveTicket(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 OK, got %d: %s", rec.Code, rec.Body.String())
		}

		var resp map[string]any
		if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
			t.Fatalf("failed to parse response JSON: %v", err)
		}

		if resp["customer_notified"] != true {
			t.Errorf("expected customer_notified == true, got %v", resp["customer_notified"])
		}

		// 1. Verify notification was dispatched to notification-service
		mu.Lock()
		if len(capturedNotifications) != 1 {
			t.Fatalf("expected exactly 1 notification dispatched, got %d", len(capturedNotifications))
		}
		notif := capturedNotifications[0]
		mu.Unlock()

		if notif["type"] != "ticket_resolved" {
			t.Errorf("expected type ticket_resolved, got %v", notif["type"])
		}
		if notif["user_id"] != "cust-delivery-123" {
			t.Errorf("expected user_id cust-delivery-123, got %v", notif["user_id"])
		}
		if notif["title"] != "Support Ticket Resolved" {
			t.Errorf("expected title 'Support Ticket Resolved', got %v", notif["title"])
		}
		if !strings.Contains(fmt.Sprint(notif["body"]), resolutionNote) {
			t.Errorf("expected body to contain resolution note, got %v", notif["body"])
		}

		// 2. Verify chat message was persisted in the ticket channel
		channel := "ticket:" + ticket.ID
		msgs, err := mongoStore.GetHistory(ctx, channel, 10)
		if err != nil {
			t.Fatalf("failed to get chat history for %s: %v", channel, err)
		}
		if len(msgs) != 1 {
			t.Fatalf("expected 1 chat message in channel %s, got %d", channel, len(msgs))
		}
		msg := msgs[0]
		if msg.SenderID != "system:support" {
			t.Errorf("expected sender_id 'system:support', got %q", msg.SenderID)
		}
		if msg.SenderUsername != "Support Team" {
			t.Errorf("expected sender_username 'Support Team', got %q", msg.SenderUsername)
		}
		if msg.Type != "ticket_resolution" {
			t.Errorf("expected type 'ticket_resolution', got %q", msg.Type)
		}
		if !strings.Contains(msg.Content, resolutionNote) {
			t.Errorf("expected message content to contain %q, got %q", resolutionNote, msg.Content)
		}
	})

	t.Run("NotificationServiceOutage_GracefullyFailsNotificationWithoutFailingResolution", func(t *testing.T) {
		mu.Lock()
		capturedNotifications = nil
		notificationStatusCode = http.StatusInternalServerError
		mu.Unlock()

		ticket, err := mongoStore.CreateTicketAndAssign(ctx, "cust-delivery-fail", "job-ctx-789")
		if err != nil {
			t.Fatalf("failed to create ticket: %v", err)
		}

		resolutionNote := "Compensation coupon issued for delivery delay."
		body, _ := json.Marshal(AdminResolveTicketRequest{
			TicketID:       ticket.ID,
			ResolutionNote: resolutionNote,
		})
		req := httptest.NewRequest(http.MethodPost, "/chat/admin/tickets/resolve", bytes.NewReader(body))
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validReviewerToken)
		rec := httptest.NewRecorder()
		c.AdminResolveTicket(rec, req)

		// Resolution must still succeed 200 OK
		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 OK despite notification outage, got %d: %s", rec.Code, rec.Body.String())
		}

		var resp map[string]any
		if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
			t.Fatalf("failed to parse response JSON: %v", err)
		}

		if resp["customer_notified"] != false {
			t.Errorf("expected customer_notified == false during outage, got %v", resp["customer_notified"])
		}
		if resp["notify_error"] == nil || !strings.Contains(fmt.Sprint(resp["notify_error"]), "500") {
			t.Errorf("expected notify_error mentioning 500, got %v", resp["notify_error"])
		}

		// Ticket status in Mongo must still be resolved
		resolved, err := mongoStore.GetTicket(ctx, ticket.ID)
		if err != nil {
			t.Fatalf("failed to get ticket: %v", err)
		}
		if resolved.Status != "resolved" {
			t.Errorf("expected ticket status resolved, got %s", resolved.Status)
		}

		// Chat message must still be persisted
		channel := "ticket:" + ticket.ID
		msgs, err := mongoStore.GetHistory(ctx, channel, 10)
		if err != nil {
			t.Fatalf("failed to get chat history for %s: %v", channel, err)
		}
		if len(msgs) != 1 {
			t.Fatalf("expected 1 chat message in channel %s, got %d", channel, len(msgs))
		}
	})
}

func TestAdminAcceptTicket(t *testing.T) {
	c, mongoStore, validToken, authServer := setupAdminTicketsTestEnvironment(t)
	defer authServer.Close()
	ctx := context.Background()

	t.Run("Method Not Allowed (GET)", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/chat/admin/tickets/accept", nil)
		rec := httptest.NewRecorder()
		c.AdminAcceptTicket(rec, req)

		if rec.Code != http.StatusMethodNotAllowed {
			t.Fatalf("expected 405 Method Not Allowed, got %d", rec.Code)
		}
	})

	t.Run("Unauthorized - Missing Internal Token", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodPost, "/chat/admin/tickets/accept", nil)
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		c.AdminAcceptTicket(rec, req)

		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("expected 401 Unauthorized, got %d", rec.Code)
		}
	})

	t.Run("Unauthorized - Invalid Reviewer Token", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodPost, "/chat/admin/tickets/accept", nil)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", "invalid-token")
		rec := httptest.NewRecorder()
		c.AdminAcceptTicket(rec, req)

		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("expected 401 Unauthorized, got %d", rec.Code)
		}
	})

	t.Run("Missing Ticket ID", func(t *testing.T) {
		body := bytes.NewReader([]byte(`{}`))
		req := httptest.NewRequest(http.MethodPost, "/chat/admin/tickets/accept", body)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		c.AdminAcceptTicket(rec, req)

		if rec.Code != http.StatusBadRequest {
			t.Fatalf("expected 400 Bad Request for missing ticket_id, got %d", rec.Code)
		}
	})

	t.Run("Ticket Not Found", func(t *testing.T) {
		body := bytes.NewReader([]byte(`{"ticket_id":"nonexistent-tkt-999"}`))
		req := httptest.NewRequest(http.MethodPost, "/chat/admin/tickets/accept", body)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		c.AdminAcceptTicket(rec, req)

		if rec.Code != http.StatusNotFound {
			t.Fatalf("expected 404 Not Found, got %d: %s", rec.Code, rec.Body.String())
		}
	})

	t.Run("Success - Pending Ticket Accepted", func(t *testing.T) {
		ticket, err := mongoStore.CreateTicketAndAssign(ctx, "cust-accept-1", "job-accept-101")
		if err != nil {
			t.Fatalf("failed to create ticket: %v", err)
		}
		if ticket.Status != "pending" {
			t.Fatalf("expected ticket initially pending, got %s", ticket.Status)
		}

		body := bytes.NewReader([]byte(fmt.Sprintf(`{"ticket_id":"%s"}`, ticket.ID)))
		req := httptest.NewRequest(http.MethodPost, "/chat/admin/tickets/accept", body)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		c.AdminAcceptTicket(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 OK, got %d: %s", rec.Code, rec.Body.String())
		}

		// Verify ticket status in DB
		updated, err := mongoStore.GetTicket(ctx, ticket.ID)
		if err != nil {
			t.Fatalf("failed to fetch updated ticket: %v", err)
		}
		if updated.Status != "assigned" {
			t.Errorf("expected status 'assigned', got '%s'", updated.Status)
		}
		if updated.AssignedReviewer != "reviewer-ticket-admin" || updated.AssignedAgentID != "reviewer-ticket-admin" {
			t.Errorf("expected assigned reviewer/agent 'reviewer-ticket-admin', got agent='%s', reviewer='%s'", updated.AssignedAgentID, updated.AssignedReviewer)
		}

		// Verify system chat message was persisted
		channel := "ticket:" + ticket.ID
		history, err := mongoStore.GetHistory(ctx, channel, 10)
		if err != nil {
			t.Fatalf("failed to get chat history: %v", err)
		}
		if len(history) != 1 {
			t.Fatalf("expected 1 system chat message, got %d", len(history))
		}
		if history[0].Content != "A support agent has joined your ticket" {
			t.Errorf("expected message 'A support agent has joined your ticket', got '%s'", history[0].Content)
		}

		// Attempting to accept already assigned ticket returns 409 Conflict
		body2 := bytes.NewReader([]byte(fmt.Sprintf(`{"ticket_id":"%s"}`, ticket.ID)))
		req2 := httptest.NewRequest(http.MethodPost, "/chat/admin/tickets/accept", body2)
		req2.Header.Set("X-Internal-Token", "test-internal-token")
		req2.Header.Set("X-Reviewer-Token", validToken)
		rec2 := httptest.NewRecorder()
		c.AdminAcceptTicket(rec2, req2)

		if rec2.Code != http.StatusConflict {
			t.Fatalf("expected 409 Conflict on already assigned ticket, got %d: %s", rec2.Code, rec2.Body.String())
		}
	})

	t.Run("Accept Already Resolved Ticket Rejection", func(t *testing.T) {
		ticket, err := mongoStore.CreateTicketAndAssign(ctx, "cust-accept-resolved", "job-102")
		if err != nil {
			t.Fatalf("failed to create ticket: %v", err)
		}
		_, err = mongoStore.AdminResolveTicket(ctx, ticket.ID, "Resolution", "reviewer-123")
		if err != nil {
			t.Fatalf("failed to resolve ticket: %v", err)
		}

		body := bytes.NewReader([]byte(fmt.Sprintf(`{"ticket_id":"%s"}`, ticket.ID)))
		req := httptest.NewRequest(http.MethodPost, "/chat/admin/tickets/accept", body)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		c.AdminAcceptTicket(rec, req)

		if rec.Code != http.StatusConflict {
			t.Fatalf("expected 409 Conflict on already resolved ticket, got %d", rec.Code)
		}
	})
}

func TestAdminAcceptTicket_CASConcurrencyRace(t *testing.T) {
	c, mongoStore, validToken, authServer := setupAdminTicketsTestEnvironment(t)
	defer authServer.Close()
	ctx := context.Background()

	ticket, err := mongoStore.CreateTicketAndAssign(ctx, "cust-accept-race", "job-race-99")
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
			body := bytes.NewReader([]byte(fmt.Sprintf(`{"ticket_id":"%s"}`, ticket.ID)))
			req := httptest.NewRequest(http.MethodPost, "/chat/admin/tickets/accept", body)
			req.Header.Set("X-Internal-Token", "test-internal-token")
			req.Header.Set("X-Reviewer-Token", validToken)
			rec := httptest.NewRecorder()
			c.AdminAcceptTicket(rec, req)
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
		t.Fatalf("AdminAcceptTicket CAS race failed: expected exactly 1 200 OK and 1 409 Conflict, got %+v", results)
	}
}

func TestAdminTickets_CircuitBreaker_OpenHalfOpenClosedLifecycle(t *testing.T) {
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://root:devpassword123@localhost:27017/saas_platform?authSource=admin"
	}
	dbName := fmt.Sprintf("saas_chat_cb_test_%d", time.Now().UnixNano())
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	mongoStore, err := store.NewMongoDB(ctx, mongoURI, dbName)
	if err != nil {
		t.Fatalf("failed to connect to mongodb for test: %v", err)
	}

	validReviewerToken := "valid-reviewer-tickets-token"

	// Seed a test ticket for accept/resolve
	tkt, err := mongoStore.CreateTicketAndAssign(context.Background(), "cust-test-cb", "job-cb-1")
	if err != nil {
		t.Fatalf("failed to seed ticket: %v", err)
	}

	var callCount atomic.Int32

	// Fake auth-service HTTP server: fails (500, 503, connection reset via hijack) for first 5 calls, then succeeds.
	mockAuthServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/notifications/send" {
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte(`{"status":"success"}`))
			return
		}

		if r.URL.Path != "/auth/reviewer/verify" {
			w.WriteHeader(http.StatusNotFound)
			return
		}

		count := callCount.Add(1)
		if count <= 5 {
			// Cover multiple failure modes:
			// Calls 1 & 2: HTTP 500
			// Call 3: connection reset / dropped via hijack
			// Call 4: HTTP 503
			// Call 5: HTTP 500
			switch count {
			case 3:
				hj, ok := w.(http.Hijacker)
				if ok {
					conn, _, err := hj.Hijack()
					if err == nil {
						_ = conn.Close()
						return
					}
				}
				w.WriteHeader(http.StatusInternalServerError)
				_, _ = w.Write([]byte(`{"error":"connection drop fallback"}`))
			case 4:
				w.WriteHeader(http.StatusServiceUnavailable)
				_, _ = w.Write([]byte(`{"error":"auth-service temporarily overloaded"}`))
			default:
				w.WriteHeader(http.StatusInternalServerError)
				_, _ = w.Write([]byte(`{"error":"auth-service database error"}`))
			}
			return
		}

		// Calls 6+: Succeeds
		revTok := r.Header.Get("X-Reviewer-Token")
		if revTok == validReviewerToken {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte(`{"id":"reviewer-ticket-admin","name":"Support Ops Admin"}`))
			return
		}
		w.WriteHeader(http.StatusUnauthorized)
		_, _ = w.Write([]byte(`{"error":"invalid reviewer token"}`))
	}))

	t.Cleanup(func() {
		mockAuthServer.Close()
		dropCtx, dropCancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer dropCancel()
		client, err := mongo.Connect(dropCtx, options.Client().ApplyURI(mongoURI))
		if err == nil {
			_ = client.Database(dbName).Drop(dropCtx)
			_ = client.Disconnect(dropCtx)
		}
	})

	cfg := &config.Config{
		InternalServiceToken:   "test-internal-token",
		AuthServiceURL:         mockAuthServer.URL,
		NotificationServiceURL: mockAuthServer.URL,
	}

	hub := chat.NewHub()
	go hub.Run()

	c := NewChat(hub, mongoStore, cfg, nil)

	getAuthBreakerStat := func() *resilience.BreakerStats {
		for _, s := range resilience.GetBreakerStats() {
			if s.Name == "auth-service" {
				return &s
			}
		}
		return nil
	}

	// -------------------------------------------------------------------------
	// Phase 1: Calls 1 to 5 fail against fake auth-service
	// -------------------------------------------------------------------------
	// Initial state: Breaker is closed
	stat := getAuthBreakerStat()
	if stat == nil || stat.State != "closed" {
		t.Fatalf("expected initial breaker state 'closed', got %+v", stat)
	}

	// Request 1: GET /chat/admin/tickets (attempts 1, 2, 3 -> calls 1, 2, 3 fail)
	req1 := httptest.NewRequest(http.MethodGet, "/chat/admin/tickets", nil)
	req1.Header.Set("X-Internal-Token", "test-internal-token")
	req1.Header.Set("X-Reviewer-Token", validReviewerToken)
	rec1 := httptest.NewRecorder()
	c.AdminListTickets(rec1, req1)

	if rec1.Code != http.StatusServiceUnavailable {
		t.Fatalf("Request 1: expected HTTP 503, got %d: %s", rec1.Code, rec1.Body.String())
	}
	if callCount.Load() != 3 {
		t.Fatalf("Request 1: expected 3 calls to fake server, got %d", callCount.Load())
	}
	stat = getAuthBreakerStat()
	if stat.State != "closed" || stat.ConsecFailures != 3 {
		t.Fatalf("after Request 1: expected state 'closed' with 3 consecutive failures, got %+v", stat)
	}

	// Request 2: POST /chat/admin/tickets/accept (attempts 1, 2 -> calls 4, 5 fail -> TRIPS BREAKER TO OPEN; attempt 3 fast-fails)
	req2 := httptest.NewRequest(http.MethodPost, "/chat/admin/tickets/accept", strings.NewReader(fmt.Sprintf(`{"ticket_id":"%s"}`, tkt.ID)))
	req2.Header.Set("X-Internal-Token", "test-internal-token")
	req2.Header.Set("X-Reviewer-Token", validReviewerToken)
	rec2 := httptest.NewRecorder()
	c.AdminAcceptTicket(rec2, req2)

	if rec2.Code != http.StatusServiceUnavailable {
		t.Fatalf("Request 2: expected HTTP 503, got %d: %s", rec2.Code, rec2.Body.String())
	}
	if callCount.Load() != 5 {
		t.Fatalf("Request 2: expected exactly 5 calls to fake server, got %d", callCount.Load())
	}

	// Breaker must now be OPEN
	stat = getAuthBreakerStat()
	if stat == nil || stat.State != "open" {
		t.Fatalf("expected breaker state 'open' after 5 consecutive failures, got %+v", stat)
	}

	// -------------------------------------------------------------------------
	// Phase 2: Subsequent calls fail fast in OPEN state (no HTTP calls attempted)
	// -------------------------------------------------------------------------
	// Request 3: POST /chat/admin/tickets/resolve
	start3 := time.Now()
	bodyResolve := fmt.Sprintf(`{"ticket_id":"%s","resolution_note":"Fixed issue"}`, tkt.ID)
	req3 := httptest.NewRequest(http.MethodPost, "/chat/admin/tickets/resolve", strings.NewReader(bodyResolve))
	req3.Header.Set("X-Internal-Token", "test-internal-token")
	req3.Header.Set("X-Reviewer-Token", validReviewerToken)
	rec3 := httptest.NewRecorder()
	c.AdminResolveTicket(rec3, req3)
	dur3 := time.Since(start3)

	if rec3.Code != http.StatusServiceUnavailable {
		t.Fatalf("Request 3 (resolve): expected HTTP 503 while breaker is open, got %d: %s", rec3.Code, rec3.Body.String())
	}
	if dur3 > 50*time.Millisecond {
		t.Fatalf("Request 3 (resolve): expected fast-fail under 50ms, took %v", dur3)
	}
	if callCount.Load() != 5 {
		t.Fatalf("Request 3 (resolve): fake server must not be called while open, got %d calls", callCount.Load())
	}

	// Request 4: GET /chat/admin/tickets
	start4 := time.Now()
	req4 := httptest.NewRequest(http.MethodGet, "/chat/admin/tickets", nil)
	req4.Header.Set("X-Internal-Token", "test-internal-token")
	req4.Header.Set("X-Reviewer-Token", validReviewerToken)
	rec4 := httptest.NewRecorder()
	c.AdminListTickets(rec4, req4)
	dur4 := time.Since(start4)

	if rec4.Code != http.StatusServiceUnavailable {
		t.Fatalf("Request 4 (list): expected HTTP 503 while breaker is open, got %d", rec4.Code)
	}
	if dur4 > 50*time.Millisecond {
		t.Fatalf("Request 4 (list): expected fast-fail under 50ms, took %v", dur4)
	}
	if callCount.Load() != 5 {
		t.Fatalf("Request 4 (list): fake server must not be called while open, got %d calls", callCount.Load())
	}

	// Assert BreakerStats still reports open
	stat = getAuthBreakerStat()
	if stat.State != "open" {
		t.Fatalf("expected breaker state to remain 'open', got %s", stat.State)
	}

	// -------------------------------------------------------------------------
	// Phase 3: Wait for breaker Timeout window (15 seconds) to elapse
	// -------------------------------------------------------------------------
	time.Sleep(15500 * time.Millisecond)

	// -------------------------------------------------------------------------
	// Phase 4: Fake server now succeeds. Breaker transitions half-open -> closed after MaxRequests (3) successes
	// -------------------------------------------------------------------------
	// Success 1 (half-open): GET /chat/admin/tickets
	req5 := httptest.NewRequest(http.MethodGet, "/chat/admin/tickets", nil)
	req5.Header.Set("X-Internal-Token", "test-internal-token")
	req5.Header.Set("X-Reviewer-Token", validReviewerToken)
	rec5 := httptest.NewRecorder()
	c.AdminListTickets(rec5, req5)

	if rec5.Code != http.StatusOK {
		t.Fatalf("Success 1 (half-open): expected HTTP 200 OK, got %d: %s", rec5.Code, rec5.Body.String())
	}
	if callCount.Load() != 6 {
		t.Fatalf("Success 1 (half-open): expected callCount 6, got %d", callCount.Load())
	}
	stat = getAuthBreakerStat()
	if stat.State != "half-open" {
		t.Fatalf("expected breaker state 'half-open' after 1 success, got %s", stat.State)
	}

	// Success 2 (half-open): POST /chat/admin/tickets/accept
	req6 := httptest.NewRequest(http.MethodPost, "/chat/admin/tickets/accept", strings.NewReader(fmt.Sprintf(`{"ticket_id":"%s"}`, tkt.ID)))
	req6.Header.Set("X-Internal-Token", "test-internal-token")
	req6.Header.Set("X-Reviewer-Token", validReviewerToken)
	rec6 := httptest.NewRecorder()
	c.AdminAcceptTicket(rec6, req6)

	if rec6.Code != http.StatusOK {
		t.Fatalf("Success 2 (half-open): expected HTTP 200 OK, got %d: %s", rec6.Code, rec6.Body.String())
	}
	if callCount.Load() != 7 {
		t.Fatalf("Success 2 (half-open): expected callCount 7, got %d", callCount.Load())
	}
	stat = getAuthBreakerStat()
	if stat.State != "half-open" {
		t.Fatalf("expected breaker state 'half-open' after 2 successes, got %s", stat.State)
	}

	// Success 3 (half-open): POST /chat/admin/tickets/resolve
	req7 := httptest.NewRequest(http.MethodPost, "/chat/admin/tickets/resolve", strings.NewReader(bodyResolve))
	req7.Header.Set("X-Internal-Token", "test-internal-token")
	req7.Header.Set("X-Reviewer-Token", validReviewerToken)
	rec7 := httptest.NewRecorder()
	c.AdminResolveTicket(rec7, req7)

	if rec7.Code != http.StatusOK {
		t.Fatalf("Success 3 (half-open): expected HTTP 200 OK, got %d: %s", rec7.Code, rec7.Body.String())
	}
	if callCount.Load() != 8 {
		t.Fatalf("Success 3 (half-open): expected callCount 8, got %d", callCount.Load())
	}

	// Breaker should now be closed after 3 consecutive successes (MaxRequests: 3)
	stat = getAuthBreakerStat()
	if stat == nil || stat.State != "closed" {
		t.Fatalf("expected breaker state 'closed' after 3 consecutive successes, got %+v", stat)
	}

	// Subsequent call executes in closed state
	req8 := httptest.NewRequest(http.MethodGet, "/chat/admin/tickets", nil)
	req8.Header.Set("X-Internal-Token", "test-internal-token")
	req8.Header.Set("X-Reviewer-Token", validReviewerToken)
	rec8 := httptest.NewRecorder()
	c.AdminListTickets(rec8, req8)

	if rec8.Code != http.StatusOK {
		t.Fatalf("Subsequent call (closed): expected HTTP 200 OK, got %d: %s", rec8.Code, rec8.Body.String())
	}
	stat = getAuthBreakerStat()
	if stat.State != "closed" {
		t.Fatalf("expected breaker state to remain 'closed', got %s", stat.State)
	}
}
