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

	"github.com/alicebob/miniredis/v2"
	"github.com/golang-jwt/jwt/v5"
	"github.com/gorilla/websocket"
	"github.com/project/chat-service/internal/chat"
	"github.com/project/chat-service/internal/config"
	"github.com/project/chat-service/internal/store"
	"github.com/project/shared/infra/jwtutil"
	"github.com/redis/go-redis/v9"
)

func connectTestMongoDB(ctx context.Context, dbName string) (*store.MongoDB, error) {
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI != "" {
		return store.NewMongoDB(ctx, mongoURI, dbName)
	}

	s, err := store.NewMongoDB(ctx, "mongodb://root:devpassword123@localhost:27017/saas_platform?authSource=admin", dbName)
	if err == nil {
		testMsg := &chat.Message{Channel: "test", Content: "ping"}
		if err := s.PersistMessage(ctx, testMsg); err == nil {
			return s, nil
		}
		_ = s.Close(ctx)
	}

	return store.NewMongoDB(ctx, "mongodb://localhost:27017", dbName)
}

func TestCanAccessChannel(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	// Spin up a mock User Service to return job details
	mockUserServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")

		if r.Header.Get("X-Internal-Token") != "mock-internal-token" {
			w.WriteHeader(http.StatusUnauthorized)
			json.NewEncoder(w).Encode(map[string]string{"error": "unauthorized"})
			return
		}

		jobID := r.URL.Query().Get("id")

		if jobID == "valid-job-123" {
			w.WriteHeader(http.StatusOK)
			json.NewEncoder(w).Encode(map[string]string{
				"owner_id":    "job-owner-id",
				"employee_id": "job-employee-id",
				"user_id":     "job-user-id",
			})
			return
		}

		if jobID == "job-no-employee" {
			w.WriteHeader(http.StatusOK)
			json.NewEncoder(w).Encode(map[string]string{
				"owner_id":    "job-owner-id",
				"employee_id": "",
				"user_id":     "job-user-id",
			})
			return
		}

		if jobID == "job-pending-dispatch" {
			w.WriteHeader(http.StatusOK)
			json.NewEncoder(w).Encode(map[string]string{
				"owner_id":                    "job-owner-id",
				"employee_id":                 "",
				"user_id":                     "job-user-id",
				"status":                      "pending_dispatch",
				"current_offered_employee_id": "offered-courier-id",
			})
			return
		}

		if jobID == "job-offer-expired" {
			w.WriteHeader(http.StatusOK)
			json.NewEncoder(w).Encode(map[string]string{
				"owner_id":                    "job-owner-id",
				"employee_id":                 "",
				"user_id":                     "job-user-id",
				"status":                      "unavailable",
				"current_offered_employee_id": "",
			})
			return
		}

		if jobID == "job-offer-advanced" {
			w.WriteHeader(http.StatusOK)
			json.NewEncoder(w).Encode(map[string]string{
				"owner_id":                    "job-owner-id",
				"employee_id":                 "",
				"user_id":                     "job-user-id",
				"status":                      "pending_dispatch",
				"current_offered_employee_id": "next-courier-id",
			})
			return
		}

		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(map[string]string{"error": "job not found"})
	}))
	defer mockUserServer.Close()

	mockAuthServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")

		if r.Header.Get("X-Internal-Token") != "mock-internal-token" {
			w.WriteHeader(http.StatusUnauthorized)
			json.NewEncoder(w).Encode(map[string]string{"error": "unauthorized"})
			return
		}

		uid := r.URL.Query().Get("id")
		if uid == "owner-fleet-123" {
			w.WriteHeader(http.StatusOK)
			json.NewEncoder(w).Encode(map[string]any{
				"id":   "owner-fleet-123",
				"role": "owner",
			})
			return
		}
		if uid == "user-fleet-456" {
			w.WriteHeader(http.StatusOK)
			json.NewEncoder(w).Encode(map[string]any{
				"id":   "user-fleet-456",
				"role": "user",
			})
			return
		}

		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(map[string]string{"error": "user not found"})
	}))
	defer mockAuthServer.Close()

	// Instantiate Chat handler group (we can pass nil hub and store as they aren't used in canAccessChannel)
	cfg := &config.Config{
		AuthServiceURL:       mockAuthServer.URL,
		UserServiceURL:       mockUserServer.URL,
		InternalServiceToken: "mock-internal-token",
		AllowedOrigin:        "http://localhost:3000",
	}
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	chatHandler := NewChat(nil, nil, cfg, rdb)

	tests := []struct {
		name       string
		userID     string
		channel    string
		expectAuth bool
	}{
		{
			name:       "Owner Authorized",
			userID:     "job-owner-id",
			channel:    "job:valid-job-123",
			expectAuth: true,
		},
		{
			name:       "Employee Authorized",
			userID:     "job-employee-id",
			channel:    "job:valid-job-123",
			expectAuth: true,
		},
		{
			name:       "User/Client Authorized",
			userID:     "job-user-id",
			channel:    "job:valid-job-123",
			expectAuth: true,
		},
		{
			name:       "Offered Courier Authorized During Pending Dispatch (F-01 / Part B)",
			userID:     "offered-courier-id",
			channel:    "job:job-pending-dispatch",
			expectAuth: true,
		},
		{
			name:       "Unoffered Courier Denied During Pending Dispatch (F-01 / Part B)",
			userID:     "unoffered-courier-id",
			channel:    "job:job-pending-dispatch",
			expectAuth: false,
		},
		{
			name:       "Previous Courier Denied After Offer Expiry (Part B)",
			userID:     "offered-courier-id",
			channel:    "job:job-offer-expired",
			expectAuth: false,
		},
		{
			name:       "Previous Courier Denied After Cascade Advance (Part B)",
			userID:     "offered-courier-id",
			channel:    "job:job-offer-advanced",
			expectAuth: false,
		},
		{
			name:       "New Courier Authorized After Cascade Advance (Part B)",
			userID:     "next-courier-id",
			channel:    "job:job-offer-advanced",
			expectAuth: true,
		},
		{
			name:       "Fleet Owner Authorized",
			userID:     "owner-fleet-123",
			channel:    "fleet:owner-fleet-123",
			expectAuth: true,
		},
		{
			name:       "Fleet Non-Owner Role Gated",
			userID:     "user-fleet-456",
			channel:    "fleet:user-fleet-456",
			expectAuth: false,
		},
		{
			name:       "Fleet Mismatched Owner ID Gated",
			userID:     "owner-fleet-123",
			channel:    "fleet:other-owner-789",
			expectAuth: false,
		},
		{
			name:       "Unauthorized User",
			userID:     "malicious-user-id",
			channel:    "job:valid-job-123",
			expectAuth: false,
		},
		{
			name:       "Empty Employee ID Gated",
			userID:     "",
			channel:    "job:job-no-employee",
			expectAuth: false,
		},
		{
			name:       "Job Not Found Gated",
			userID:     "job-owner-id",
			channel:    "job:non-existent-job",
			expectAuth: false,
		},
		{
			name:       "Non-Job Channel Gated",
			userID:     "job-owner-id",
			channel:    "general-channel",
			expectAuth: false,
		},
		{
			name:       "Malformed Channel Name Gated",
			userID:     "job-owner-id",
			channel:    "job:",
			expectAuth: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			allowed, _ := chatHandler.canAccessChannel(tt.userID, tt.channel)
			if allowed != tt.expectAuth {
				t.Errorf("canAccessChannel(%q, %q) = %v; want %v", tt.userID, tt.channel, allowed, tt.expectAuth)
			}
		})
	}
}

func TestGetHistoryAccessControl(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")

	// Spin up mock user server
	mockUserServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		jobID := r.URL.Query().Get("id")
		if jobID == "valid-job-123" {
			json.NewEncoder(w).Encode(map[string]string{
				"owner_id":    "job-owner-id",
				"employee_id": "job-employee-id",
				"user_id":     "job-user-id",
			})
			return
		}
		w.WriteHeader(http.StatusNotFound)
	}))
	defer mockUserServer.Close()

	// Spin up mock auth server
	mockAuthServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusNotFound)
	}))
	defer mockAuthServer.Close()

	// Set up MongoDB or skip/mock if needed
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	dbName := fmt.Sprintf("chat_platform_test_%d", time.Now().UnixNano())
	mongoStore, err := connectTestMongoDB(ctx, dbName)
	if err != nil {
		t.Skipf("Skipping integration tests: MongoDB not available: %v", err)
		return
	}
	defer func() {
		_ = mongoStore.Close(context.Background())
	}()

	cfg2 := &config.Config{
		AuthServiceURL:       mockAuthServer.URL,
		UserServiceURL:       mockUserServer.URL,
		InternalServiceToken: "mock-internal-token",
		AllowedOrigin:        "http://localhost:3000",
	}
	mr2, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr2.Close()
	rdb2 := redis.NewClient(&redis.Options{Addr: mr2.Addr()})
	defer rdb2.Close()

	chatHandler := NewChat(nil, mongoStore, cfg2, rdb2)

	// Pre-seed some cache to bypass auth-service lookup
	chatHandler.tokenCache["job-owner-id"] = cachedToken{expiry: time.Now().Add(60 * time.Second), username: "owner_username"}
	chatHandler.tokenCache["stranger-id"] = cachedToken{expiry: time.Now().Add(60 * time.Second), username: "stranger_username"}

	tokenOwner, _ := jwtutil.GenerateToken("job-owner-id", "owner", "tenant-1", "owner@example.com")
	tokenStranger, _ := jwtutil.GenerateToken("stranger-id", "user", "tenant-1", "stranger@example.com")
	tokenInvalid := "invalid.jwt.token"

	// A. Missing channel parameter -> 400 Bad Request
	req := httptest.NewRequest("GET", "/chat/history", nil)
	rec := httptest.NewRecorder()
	chatHandler.GetHistory(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("Expected 400 Bad Request, got %d", rec.Code)
	}

	// B. Missing requester_id -> 400 Bad Request
	req = httptest.NewRequest("GET", "/chat/history?channel=job:valid-job-123", nil)
	rec = httptest.NewRecorder()
	chatHandler.GetHistory(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("Expected 400 Bad Request, got %d", rec.Code)
	}

	// C. Invalid token -> 403 Forbidden
	req = httptest.NewRequest("GET", "/chat/history?channel=job:valid-job-123&requester_id="+tokenInvalid, nil)
	rec = httptest.NewRecorder()
	chatHandler.GetHistory(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Errorf("Expected 403 Forbidden, got %d", rec.Code)
	}

	// D. Unauthorized channel access -> 403 Forbidden
	req = httptest.NewRequest("GET", "/chat/history?channel=job:valid-job-123&requester_id="+tokenStranger, nil)
	rec = httptest.NewRecorder()
	chatHandler.GetHistory(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Errorf("Expected 403 Forbidden, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// E. Authorized -> 200 OK
	req = httptest.NewRequest("GET", "/chat/history?channel=job:valid-job-123&requester_id="+tokenOwner, nil)
	rec = httptest.NewRecorder()
	chatHandler.GetHistory(rec, req)
	if rec.Code != http.StatusOK {
		t.Errorf("Expected 200 OK, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// F. Limit Clamping Verification
	// Let's populate 505 messages in the test database for the authorized channel
	for i := 0; i < 505; i++ {
		msg := &chat.Message{
			Channel:  "job:valid-job-123",
			SenderID: "job-owner-id",
			Content:  fmt.Sprintf("message %d", i),
			Type:     "text",
		}
		if err := mongoStore.PersistMessage(context.Background(), msg); err != nil {
			t.Fatalf("failed to insert test message: %v", err)
		}
	}

	// Request with limit=600. It should be clamped to 500.
	req = httptest.NewRequest("GET", "/chat/history?channel=job:valid-job-123&requester_id="+tokenOwner+"&limit=600", nil)
	rec = httptest.NewRecorder()
	chatHandler.GetHistory(rec, req)
	if rec.Code != http.StatusOK {
		t.Errorf("Expected 200 OK, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	var clampedHistory []chat.Message
	if err := json.NewDecoder(rec.Body).Decode(&clampedHistory); err != nil {
		t.Fatalf("failed to decode history response: %v", err)
	}

	if len(clampedHistory) != 500 {
		t.Errorf("Expected history to be clamped to 500, but got %d messages", len(clampedHistory))
	}
}

func TestComplaintRoutingConcurrency(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	dbName := fmt.Sprintf("chat_platform_test_%d", time.Now().UnixNano())
	mongoStore, err := connectTestMongoDB(ctx, dbName)
	if err != nil {
		t.Skipf("Skipping concurrency tests: MongoDB not available: %v", err)
		return
	}
	defer func() {
		_ = mongoStore.Close(context.Background())
	}()

	// 1. Seed 5 available agents
	numAgents := 5
	for i := 0; i < numAgents; i++ {
		agent := &store.SupportAgent{
			ID:     fmt.Sprintf("agent-%d", i),
			Status: "available",
			Token:  fmt.Sprintf("agent-token-%d", i),
		}
		if err := mongoStore.AddSupportAgent(ctx, agent); err != nil {
			t.Fatalf("failed to seed agent: %v", err)
		}
	}

	// 2. Concurrently create 20 tickets
	numTickets := 20
	var wg sync.WaitGroup
	resultsChan := make(chan *store.ComplaintTicket, numTickets)

	for i := 0; i < numTickets; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			var ticket *store.ComplaintTicket
			var err error
			for attempt := 0; attempt < 3; attempt++ {
				ticket, err = mongoStore.CreateTicketAndAssign(context.Background(), fmt.Sprintf("customer-%d", idx), "context-xyz")
				if err == nil {
					break
				}
				time.Sleep(10 * time.Millisecond)
			}
			if err != nil {
				t.Errorf("failed to create ticket: %v", err)
				return
			}
			resultsChan <- ticket
		}(i)
	}

	wg.Wait()
	close(resultsChan)

	assignedCount := 0
	pendingCount := 0
	assignedAgents := make(map[string]bool)

	for ticket := range resultsChan {
		if ticket.Status == "assigned" {
			assignedCount++
			if ticket.AssignedAgentID == "" {
				t.Errorf("ticket status is assigned but AssignedAgentID is empty")
			}
			if assignedAgents[ticket.AssignedAgentID] {
				t.Errorf("agent %s was assigned to multiple tickets concurrently!", ticket.AssignedAgentID)
			}
			assignedAgents[ticket.AssignedAgentID] = true
		} else if ticket.Status == "pending" {
			pendingCount++
			if ticket.AssignedAgentID != "" {
				t.Errorf("ticket status is pending but has AssignedAgentID %s", ticket.AssignedAgentID)
			}
		} else {
			t.Errorf("unexpected ticket status: %s", ticket.Status)
		}
	}

	// Since we seeded exactly 5 available agents, exactly 5 tickets should be assigned, and the rest 15 queued/pending.
	if assignedCount != numAgents {
		t.Errorf("expected exactly %d assigned tickets, got %d", numAgents, assignedCount)
	}
	expectedPending := numTickets - numAgents
	if pendingCount != expectedPending {
		t.Errorf("expected exactly %d pending tickets, got %d", expectedPending, pendingCount)
	}
}

func TestComplaintRoutingNoAgentsAvailable(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	dbName := fmt.Sprintf("chat_platform_test_%d", time.Now().UnixNano())
	mongoStore, err := connectTestMongoDB(ctx, dbName)
	if err != nil {
		t.Skipf("Skipping tests: MongoDB not available: %v", err)
		return
	}
	defer func() {
		_ = mongoStore.Close(context.Background())
	}()

	// Try to create a ticket with 0 agents seeded
	ticket, err := mongoStore.CreateTicketAndAssign(ctx, "customer-1", "job-123")
	if err != nil {
		t.Fatalf("failed to create ticket: %v", err)
	}

	if ticket.Status != "pending" {
		t.Errorf("expected ticket status to be 'pending', got %s", ticket.Status)
	}
	if ticket.AssignedAgentID != "" {
		t.Errorf("expected assigned agent to be empty, got %s", ticket.AssignedAgentID)
	}
}

func TestComplaintRoutingAccessControl(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	dbName := fmt.Sprintf("chat_platform_test_%d", time.Now().UnixNano())
	mongoStore, err := connectTestMongoDB(ctx, dbName)
	if err != nil {
		t.Skipf("Skipping tests: MongoDB not available: %v", err)
		return
	}
	defer func() {
		_ = mongoStore.Close(context.Background())
	}()

	// 1. Seed two agents
	agent1 := &store.SupportAgent{ID: "agent-1", Status: "available", Token: "agent-token-1"}
	agent2 := &store.SupportAgent{ID: "agent-2", Status: "available", Token: "agent-token-2"}
	_ = mongoStore.AddSupportAgent(ctx, agent1)
	_ = mongoStore.AddSupportAgent(ctx, agent2)

	// 2. Create ticket for customer-1, will be atomically assigned to agent-1
	ticket, err := mongoStore.CreateTicketAndAssign(ctx, "customer-1", "job-123")
	if err != nil {
		t.Fatalf("failed to create ticket: %v", err)
	}

	cfg := &config.Config{
		InternalServiceToken: "mock-internal-token",
		AllowedOrigin:        "http://localhost:3000",
	}
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	chatHandler := NewChat(nil, mongoStore, cfg, rdb)

	// 3. Verify access control checks (IDOR mitigation)
	// A. Customer-1 (owner of ticket) -> Authorized
	allowed, _ := chatHandler.canAccessChannel("customer-1", "ticket:"+ticket.ID)
	if !allowed {
		t.Errorf("expected customer-1 to be authorized for their ticket")
	}

	// B. Customer-2 (not owner) -> Unauthorized
	allowed, _ = chatHandler.canAccessChannel("customer-2", "ticket:"+ticket.ID)
	if allowed {
		t.Errorf("expected customer-2 to be unauthorized for another customer's ticket")
	}

	// C. Agent-1 (assigned agent) -> Authorized
	allowed, _ = chatHandler.canAccessChannel("agent-1", "ticket:"+ticket.ID)
	if !allowed {
		t.Errorf("expected assigned agent-1 to be authorized for the ticket")
	}

	// D. Agent-2 (different agent) -> Unauthorized
	allowed, _ = chatHandler.canAccessChannel("agent-2", "ticket:"+ticket.ID)
	if allowed {
		t.Errorf("expected agent-2 to be unauthorized for a ticket they are not assigned to")
	}
}

func setupTestChat(t *testing.T) (*Chat, *store.MongoDB, func()) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	jwtutil.Init("z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	dbName := fmt.Sprintf("saas_chat_test_%d", time.Now().UnixNano())
	s, err := connectTestMongoDB(ctx, dbName)
	if err != nil {
		t.Skipf("Skipping chat-service store integration tests: MongoDB not available (%v)", err)
		return nil, nil, nil
	}

	// Mock Auth/User Service
	mockAuthUserServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if r.URL.Path == "/auth/user" {
			id := r.URL.Query().Get("id")
			if id == "user-unauthorized" {
				w.WriteHeader(http.StatusForbidden)
				json.NewEncoder(w).Encode(map[string]any{"error": "user not found"})
				return
			}
			w.WriteHeader(http.StatusOK)
			json.NewEncoder(w).Encode(map[string]any{
				"id":         id,
				"role":       "owner",
				"kyc_status": "approved",
			})
			return
		}
		if r.URL.Path == "/users/jobs/detail" || r.URL.Path == "/users/jobs/get" {
			w.WriteHeader(http.StatusOK)
			json.NewEncoder(w).Encode(map[string]any{
				"owner_id":    "owner-1",
				"employee_id": "employee-1",
				"user_id":     "client-1",
			})
			return
		}
		w.WriteHeader(http.StatusNotFound)
	}))

	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	jwtutil.SetRedisClient(rdb)

	cfg := &config.Config{
		UserServiceURL:       mockAuthUserServer.URL,
		AuthServiceURL:       mockAuthUserServer.URL,
		InternalServiceToken: "mock-internal-token",
		AllowedOrigin:        "http://localhost:3000",
	}

	hub := chat.NewHub()
	go hub.Run()

	c := NewChat(hub, s, cfg, rdb)
	cleanup := func() {
		hub.Close()
		_ = s.DropDatabase(context.Background())
		_ = s.Close(context.Background())
		mr.Close()
		rdb.Close()
		mockAuthUserServer.Close()
		jwtutil.SetRedisClient(nil)
	}
	return c, s, cleanup
}

func TestWebSocketUpgradeFailures(t *testing.T) {
	c, _, cleanup := setupTestChat(t)
	if c == nil {
		return
	}
	defer cleanup()

	// A. Missing token query parameter -> 401 Unauthorized
	req := httptest.NewRequest("GET", "/chat/ws", nil)
	rec := httptest.NewRecorder()
	c.HandleWebSocket(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Errorf("Expected 401 Unauthorized, got %d", rec.Code)
	}

	// B. Invalid token query parameter -> 403 Forbidden
	req = httptest.NewRequest("GET", "/chat/ws?token=invalid-token", nil)
	rec = httptest.NewRecorder()
	c.HandleWebSocket(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Errorf("Expected 403 Forbidden, got %d", rec.Code)
	}
}

func TestBroadcastLocation(t *testing.T) {
	c, _, cleanup := setupTestChat(t)
	if c == nil {
		return
	}
	defer cleanup()

	// A. Wrong method -> 405 Method Not Allowed
	req := httptest.NewRequest("GET", "/chat/internal/broadcast-location", nil)
	rec := httptest.NewRecorder()
	c.BroadcastLocation(rec, req)
	if rec.Code != http.StatusMethodNotAllowed {
		t.Errorf("Expected 405 Method Not Allowed, got %d", rec.Code)
	}

	// B. Invalid internal token -> 403 Forbidden
	body := []byte(`{"channel":"job:1","latitude":12.34,"longitude":56.78,"employee_id":"emp-1"}`)
	req = httptest.NewRequest("POST", "/chat/internal/broadcast-location", bytes.NewReader(body))
	req.Header.Set("X-Internal-Token", "wrong-token")
	rec = httptest.NewRecorder()
	c.BroadcastLocation(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Errorf("Expected 403 Forbidden, got %d", rec.Code)
	}

	// C. Valid request -> 200 OK
	req = httptest.NewRequest("POST", "/chat/internal/broadcast-location", bytes.NewReader(body))
	req.Header.Set("X-Internal-Token", "mock-internal-token")
	rec = httptest.NewRecorder()
	c.BroadcastLocation(rec, req)
	if rec.Code != http.StatusOK {
		t.Errorf("Expected 200 OK, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// D. Missing fields -> 400 Bad Request
	badBody := []byte(`{"channel":"","employee_id":""}`)
	req = httptest.NewRequest("POST", "/chat/internal/broadcast-location", bytes.NewReader(badBody))
	req.Header.Set("X-Internal-Token", "mock-internal-token")
	rec = httptest.NewRecorder()
	c.BroadcastLocation(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("Expected 400 Bad Request, got %d", rec.Code)
	}
}

func TestHandleCreateTicket(t *testing.T) {
	c, _, cleanup := setupTestChat(t)
	if c == nil {
		return
	}
	defer cleanup()

	// A. Wrong method -> 405 Method Not Allowed
	req := httptest.NewRequest("GET", "/chat/tickets", nil)
	rec := httptest.NewRecorder()
	c.HandleCreateTicket(rec, req)
	if rec.Code != http.StatusMethodNotAllowed {
		t.Errorf("Expected 405 Method Not Allowed, got %d", rec.Code)
	}

	// B. Unauthenticated -> 401 Unauthorized
	body := []byte(`{"title":"complaint","description":"something went wrong"}`)
	req = httptest.NewRequest("POST", "/chat/tickets", bytes.NewReader(body))
	rec = httptest.NewRecorder()
	c.HandleCreateTicket(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Errorf("Expected 401 Unauthorized, got %d", rec.Code)
	}

	// C. Valid Request -> 201 Created
	token, _ := jwtutil.GenerateToken("user-1", "user", "tenant-1", "user@example.com")
	req = httptest.NewRequest("POST", "/chat/tickets", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+token)
	rec = httptest.NewRecorder()
	c.HandleCreateTicket(rec, req)
	if rec.Code != http.StatusCreated {
		t.Errorf("Expected 201 Created, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// D. Validation failure (malformed JSON) -> 400 Bad Request
	badBody := []byte(`{"context_id":`)
	req = httptest.NewRequest("POST", "/chat/tickets", bytes.NewReader(badBody))
	req.Header.Set("Authorization", "Bearer "+token)
	rec = httptest.NewRecorder()
	c.HandleCreateTicket(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("Expected 400 Bad Request, got %d", rec.Code)
	}
}

func TestChatWebSocketCommunication(t *testing.T) {
	c, _, cleanup := setupTestChat(t)
	if c == nil {
		return
	}
	defer cleanup()

	// 1. Create test server mapping the WS route
	mux := http.NewServeMux()
	mux.HandleFunc("/chat/ws", c.HandleWebSocket)
	server := httptest.NewServer(mux)
	defer server.Close()

	// WebSocket URL mapping
	wsURL := "ws" + strings.TrimPrefix(server.URL, "http") + "/chat/ws"

	// 2. Generate tokens
	tokenCustomer, _ := jwtutil.GenerateToken("client-1", "user", "", "customer@test.com")
	tokenEmployee, _ := jwtutil.GenerateToken("employee-1", "employee", "tenant-1", "employee@test.com")
	tokenOther, _ := jwtutil.GenerateToken("other-user", "user", "", "other@test.com")

	// 3. Connect Customer client
	dialer := websocket.Dialer{}
	header := http.Header{}
	header.Set("Origin", "http://localhost:3000")

	custConn, _, err := dialer.Dial(wsURL+"?token="+tokenCustomer, header)
	if err != nil {
		t.Fatalf("Failed to dial customer ws: %v", err)
	}
	defer custConn.Close()

	// Subscribe customer to job:123
	err = custConn.WriteJSON(map[string]string{
		"action":  "subscribe",
		"channel": "job:123",
	})
	if err != nil {
		t.Fatalf("Customer failed to subscribe: %v", err)
	}

	// Read customer subscription confirmation
	var confirm map[string]string
	err = custConn.ReadJSON(&confirm)
	if err != nil {
		t.Fatalf("Failed to read subscription confirmation: %v", err)
	}
	if confirm["type"] != "subscribed" || confirm["channel"] != "job:123" {
		t.Errorf("Unexpected subscription confirmation: %v", confirm)
	}

	// 4. Connect Employee client
	empConn, _, err := dialer.Dial(wsURL+"?token="+tokenEmployee, header)
	if err != nil {
		t.Fatalf("Failed to dial employee ws: %v", err)
	}
	defer empConn.Close()

	// Subscribe employee to job:123
	err = empConn.WriteJSON(map[string]string{
		"action":  "subscribe",
		"channel": "job:123",
	})
	if err != nil {
		t.Fatalf("Employee failed to subscribe: %v", err)
	}

	// Read employee subscription confirmation
	err = empConn.ReadJSON(&confirm)
	if err != nil {
		t.Fatalf("Failed to read subscription confirmation: %v", err)
	}

	// 5. Employee sends a message to job:123
	err = empConn.WriteJSON(map[string]string{
		"action":  "message",
		"channel": "job:123",
		"content": "Hello customer",
	})
	if err != nil {
		t.Fatalf("Employee failed to send message: %v", err)
	}

	// 6. Both Customer and Employee receive Employee's message
	var msgCust map[string]any
	err = custConn.ReadJSON(&msgCust)
	if err != nil {
		t.Fatalf("Customer failed to read message: %v", err)
	}
	if msgCust["content"] != "Hello customer" || msgCust["sender_id"] != "employee-1" {
		t.Errorf("Unexpected message received by customer: %v", msgCust)
	}

	var msgEmp map[string]any
	err = empConn.ReadJSON(&msgEmp)
	if err != nil {
		t.Fatalf("Employee failed to read own message: %v", err)
	}
	if msgEmp["content"] != "Hello customer" || msgEmp["sender_id"] != "employee-1" {
		t.Errorf("Unexpected message received by employee: %v", msgEmp)
	}

	// 7. Customer sends message back
	err = custConn.WriteJSON(map[string]string{
		"action":  "message",
		"channel": "job:123",
		"content": "Hello employee",
	})
	if err != nil {
		t.Fatalf("Customer failed to send message: %v", err)
	}

	// 8. Both Customer and Employee receive Customer's message
	err = custConn.ReadJSON(&msgCust)
	if err != nil {
		t.Fatalf("Customer failed to read own message: %v", err)
	}
	if msgCust["content"] != "Hello employee" || msgCust["sender_id"] != "client-1" {
		t.Errorf("Unexpected message received by customer: %v", msgCust)
	}

	err = empConn.ReadJSON(&msgEmp)
	if err != nil {
		t.Fatalf("Employee failed to read message: %v", err)
	}
	if msgEmp["content"] != "Hello employee" || msgEmp["sender_id"] != "client-1" {
		t.Errorf("Unexpected message received by employee: %v", msgEmp)
	}

	// 9. Negative case: Connect other unauthorized user and attempt to subscribe to job:123
	otherConn, _, err := dialer.Dial(wsURL+"?token="+tokenOther, header)
	if err != nil {
		t.Fatalf("Failed to dial other ws: %v", err)
	}
	defer otherConn.Close()

	err = otherConn.WriteJSON(map[string]string{
		"action":  "subscribe",
		"channel": "job:123",
	})
	if err != nil {
		t.Fatalf("Other user failed to subscribe: %v", err)
	}

	// Read other user rejection response
	var rejection map[string]string
	err = otherConn.ReadJSON(&rejection)
	if err != nil {
		t.Fatalf("Failed to read rejection response: %v", err)
	}
	if rejection["type"] != "error" || rejection["error"] != "not authorized for this channel" {
		t.Errorf("Expected authorization error, got: %v", rejection)
	}
}

func TestWebSocketUpgradeExtraGaps(t *testing.T) {
	c, _, cleanup := setupTestChat(t)
	if c == nil {
		return
	}
	defer cleanup()

	// 1. Malformed Token -> 403 Forbidden
	reqMalformed := httptest.NewRequest("GET", "/chat/ws?token=malformed.token.xyz", nil)
	recMalformed := httptest.NewRecorder()
	c.HandleWebSocket(recMalformed, reqMalformed)
	if recMalformed.Code != http.StatusForbidden {
		t.Errorf("Expected 403 Forbidden for malformed token, got %d", recMalformed.Code)
	}
	if !strings.Contains(recMalformed.Body.String(), "token is malformed") && !strings.Contains(recMalformed.Body.String(), "invalid or expired token") {
		t.Errorf("Expected body to contain malformed message, got: %s", recMalformed.Body.String())
	}

	// 2. Expired Token -> 403 Forbidden
	expiredClaims := jwtutil.Claims{
		UserID:   "expired-user",
		Role:     "user",
		TenantID: "tenant-1",
		Email:    "expired@example.com",
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(-1 * time.Hour)),
			IssuedAt:  jwt.NewNumericDate(time.Now().Add(-2 * time.Hour)),
			ID:        "expired-jti-123",
		},
	}
	tokenObj := jwt.NewWithClaims(jwt.SigningMethodHS256, expiredClaims)
	expiredToken, _ := tokenObj.SignedString([]byte("z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2"))

	reqExpired := httptest.NewRequest("GET", "/chat/ws?token="+expiredToken, nil)
	recExpired := httptest.NewRecorder()
	c.HandleWebSocket(recExpired, reqExpired)
	if recExpired.Code != http.StatusForbidden {
		t.Errorf("Expected 403 Forbidden for expired token, got %d", recExpired.Code)
	}
	if !strings.Contains(recExpired.Body.String(), "token has expired") {
		t.Errorf("Expected body to contain token expired message, got: %s", recExpired.Body.String())
	}

	// 3. Revoked (denylisted) Token -> 403 Forbidden
	validToken, err := jwtutil.GenerateToken("revoked-user", "user", "tenant-1", "revoked@example.com")
	if err != nil {
		t.Fatalf("failed to generate valid token: %v", err)
	}
	err = jwtutil.RevokeToken(validToken)
	if err != nil {
		t.Fatalf("failed to revoke token: %v", err)
	}

	reqRevoked := httptest.NewRequest("GET", "/chat/ws?token="+validToken, nil)
	recRevoked := httptest.NewRecorder()
	c.HandleWebSocket(recRevoked, reqRevoked)
	if recRevoked.Code != http.StatusForbidden {
		t.Errorf("Expected 403 Forbidden for revoked token, got %d", recRevoked.Code)
	}
	if !strings.Contains(recRevoked.Body.String(), "token has been revoked") {
		t.Errorf("Expected body to contain token revoked message, got: %s", recRevoked.Body.String())
	}
}

func TestChatExtraGapsWebSocketFlows(t *testing.T) {
	c, mongoStore, cleanup := setupTestChat(t)
	if c == nil {
		return
	}
	defer cleanup()

	// Create test server mapping the WS route
	mux := http.NewServeMux()
	mux.HandleFunc("/chat/ws", c.HandleWebSocket)
	server := httptest.NewServer(mux)
	defer server.Close()

	wsURL := "ws" + strings.TrimPrefix(server.URL, "http") + "/chat/ws"

	// Generate tokens
	tokenTenantBOwner, _ := jwtutil.GenerateToken("tenant-b-owner", "owner", "tenant-b", "ownerB@test.com")
	tokenOwner1, _ := jwtutil.GenerateToken("owner-1", "owner", "tenant-a", "owner1@test.com")

	// 1. Channel subscription authorization: Tenant B owner attempts to subscribe to Tenant A owner's job:valid-job-123
	dialer := websocket.Dialer{}
	header := http.Header{}
	header.Set("Origin", "http://localhost:3000")

	connB, _, err := dialer.Dial(wsURL+"?token="+tokenTenantBOwner, header)
	if err != nil {
		t.Fatalf("Failed to dial B ws: %v", err)
	}
	defer connB.Close()

	err = connB.WriteJSON(map[string]string{
		"action":  "subscribe",
		"channel": "job:valid-job-123",
	})
	if err != nil {
		t.Fatalf("Failed to write subscribe JSON: %v", err)
	}

	var respB map[string]string
	err = connB.ReadJSON(&respB)
	if err != nil {
		t.Fatalf("Failed to read subscribe JSON response: %v", err)
	}
	if respB["type"] != "error" || respB["error"] != "not authorized for this channel" {
		t.Errorf("Expected subscription rejection, got: %v", respB)
	}

	// 2. Message persistence & order check
	connA, _, err := dialer.Dial(wsURL+"?token="+tokenOwner1, header)
	if err != nil {
		t.Fatalf("Failed to dial A ws: %v", err)
	}
	defer connA.Close()

	err = connA.WriteJSON(map[string]string{
		"action":  "subscribe",
		"channel": "job:valid-job-123",
	})
	if err != nil {
		t.Fatalf("Failed to subscribe A: %v", err)
	}

	var confirmA map[string]string
	_ = connA.ReadJSON(&confirmA)

	messagesToSend := []string{"First message", "Second message", "Third message"}
	for _, m := range messagesToSend {
		err = connA.WriteJSON(map[string]string{
			"action":  "message",
			"channel": "job:valid-job-123",
			"content": m,
		})
		if err != nil {
			t.Fatalf("Failed to write message: %v", err)
		}
		// Read self broadcast reflection to sync
		var selfReflect map[string]any
		_ = connA.ReadJSON(&selfReflect)
		time.Sleep(10 * time.Millisecond)
	}

	// Retrieve history using GET /chat/history
	c.tokenCache["owner-1"] = cachedToken{expiry: time.Now().Add(60 * time.Second), username: "owner_username"}
	reqHist := httptest.NewRequest("GET", "/chat/history?channel=job:valid-job-123&requester_id="+tokenOwner1, nil)
	recHist := httptest.NewRecorder()
	c.GetHistory(recHist, reqHist)

	if recHist.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK for history, got %d. Body: %s", recHist.Code, recHist.Body.String())
	}

	var history []chat.Message
	if err := json.NewDecoder(recHist.Body).Decode(&history); err != nil {
		t.Fatalf("Failed to decode history: %v", err)
	}

	if len(history) < 3 {
		t.Fatalf("Expected at least 3 messages in history, got %d", len(history))
	}

	// Assert correct order (oldest to newest)
	histLen := len(history)
	if history[histLen-3].Content != "First message" {
		t.Errorf("Expected oldest message to be 'First message', got %s", history[histLen-3].Content)
	}
	if history[histLen-2].Content != "Second message" {
		t.Errorf("Expected middle message to be 'Second message', got %s", history[histLen-2].Content)
	}
	if history[histLen-1].Content != "Third message" {
		t.Errorf("Expected newest message to be 'Third message', got %s", history[histLen-1].Content)
	}

	// 3. Message from unauthorized channel does not get persisted
	// Try sending a message to a channel where user is not authorized (e.g. connB tries to send to job:valid-job-123)
	err = connB.WriteJSON(map[string]string{
		"action":  "message",
		"channel": "job:valid-job-123",
		"content": "Malicious non-persisted message",
	})
	if err != nil {
		t.Fatalf("Failed to write unauthorized message JSON: %v", err)
	}

	// Read error response
	var errResp map[string]string
	_ = connB.ReadJSON(&errResp)
	if errResp["type"] != "error" || errResp["error"] != "not authorized for this channel" {
		t.Errorf("Expected unauthorized message error, got: %v", errResp)
	}

	// Double-check history to ensure the unauthorized message was not persisted
	reqHist2 := httptest.NewRequest("GET", "/chat/history?channel=job:valid-job-123&requester_id="+tokenOwner1, nil)
	recHist2 := httptest.NewRecorder()
	c.GetHistory(recHist2, reqHist2)

	var history2 []chat.Message
	_ = json.NewDecoder(recHist2.Body).Decode(&history2)

	for _, msg := range history2 {
		if msg.Content == "Malicious non-persisted message" {
			t.Error("Found unauthorized message in chat history — security gate failed to prevent persistence!")
		}
	}

	// Double-check store directly to ensure the unauthorized message was not persisted in database
	histDirect, err := mongoStore.GetHistory(context.Background(), "job:valid-job-123", 50)
	if err != nil {
		t.Fatalf("failed to query history from store: %v", err)
	}
	for _, msg := range histDirect {
		if msg.Content == "Malicious non-persisted message" {
			t.Error("Found unauthorized message in chat history database store directly!")
		}
	}
}

func TestPersistedMessageSenderUsername(t *testing.T) {
	c, mongoStore, cleanup := setupTestChat(t)
	if c == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	msg := &chat.Message{
		Channel:        "job:test-job",
		SenderID:       "user-sender-123",
		SenderUsername: "sender_user",
		Content:        "Hello there",
		Type:           "message",
	}

	err := mongoStore.PersistMessage(ctx, msg)
	if err != nil {
		t.Fatalf("failed to persist message: %v", err)
	}

	history, err := mongoStore.GetHistory(ctx, "job:test-job", 10)
	if err != nil {
		t.Fatalf("failed to get history: %v", err)
	}

	if len(history) != 1 {
		t.Fatalf("expected 1 message in history, got %d", len(history))
	}

	if history[0].SenderUsername != "sender_user" {
		t.Errorf("expected sender_username to be 'sender_user', got %q", history[0].SenderUsername)
	}
}

func TestReconnectionCachingBehavior(t *testing.T) {
	c, _, cleanup := setupTestChat(t)
	if c == nil {
		return
	}
	defer cleanup()

	var callCount int
	var mu sync.Mutex

	mockAuth := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		callCount++
		mu.Unlock()

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]any{
			"id":         "user-cache-123",
			"username":   "cache_username",
			"role":       "owner",
			"kyc_status": "approved",
		})
	}))
	defer mockAuth.Close()

	c.authServiceURL = mockAuth.URL

	// 1. First connection / verification -> must call auth-service
	active, username, err := c.verifyToken("user-cache-123")
	if err != nil {
		t.Fatalf("verifyToken failed: %v", err)
	}
	if !active || username != "cache_username" {
		t.Fatalf("expected active and username 'cache_username', got %v, %q", active, username)
	}

	mu.Lock()
	if callCount != 1 {
		t.Errorf("expected 1 auth-service call, got %d", callCount)
	}
	mu.Unlock()

	// 2. Second verification within TTL (5s) -> should reuse cache and NOT call auth-service
	active2, username2, err := c.verifyToken("user-cache-123")
	if err != nil {
		t.Fatalf("verifyToken 2 failed: %v", err)
	}
	if !active2 || username2 != "cache_username" {
		t.Fatalf("expected active and username 'cache_username', got %v, %q", active2, username2)
	}

	mu.Lock()
	if callCount != 1 {
		t.Errorf("expected callCount to remain 1 (cached), got %d", callCount)
	}
	mu.Unlock()

	// 3. Manually expire/modify cache to simulate TTL expiration
	c.tokenCacheMu.Lock()
	entry := c.tokenCache["user-cache-123"]
	entry.expiry = time.Now().Add(-1 * time.Second) // expired
	c.tokenCache["user-cache-123"] = entry
	c.tokenCacheMu.Unlock()

	// 4. Verification after TTL expiration -> must call auth-service again
	active3, username3, err := c.verifyToken("user-cache-123")
	if err != nil {
		t.Fatalf("verifyToken 3 failed: %v", err)
	}
	if !active3 || username3 != "cache_username" {
		t.Fatalf("expected active and username 'cache_username', got %v, %q", active3, username3)
	}

	mu.Lock()
	if callCount != 2 {
		t.Errorf("expected callCount to increment to 2 (expired cache), got %d", callCount)
	}
	mu.Unlock()
}

func TestHandleResolveTicket(t *testing.T) {
	c, mongoStore, cleanup := setupTestChat(t)
	if c == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()

	// Seed agent 1 (assigned) and agent 2 (unassigned)
	agent1 := &store.SupportAgent{ID: "agent-resolve-1", Status: "available", Token: "agent-resolve-token-1"}
	agent2 := &store.SupportAgent{ID: "agent-resolve-2", Status: "available", Token: "agent-resolve-token-2"}
	if err := mongoStore.AddSupportAgent(ctx, agent1); err != nil {
		t.Fatalf("failed to add agent 1: %v", err)
	}
	if err := mongoStore.AddSupportAgent(ctx, agent2); err != nil {
		t.Fatalf("failed to add agent 2: %v", err)
	}

	// Create a ticket assigned to agent 1
	ticket, err := mongoStore.CreateTicketAndAssign(ctx, "customer-resolve-1", "context-123")
	if err != nil {
		t.Fatalf("failed to create ticket: %v", err)
	}

	tests := []struct {
		name           string
		method         string
		token          string
		headerToken    bool
		body           string
		expectedStatus int
	}{
		{
			name:           "Method Not Allowed (GET)",
			method:         "GET",
			token:          "agent-resolve-token-1",
			body:           fmt.Sprintf(`{"ticket_id":"%s"}`, ticket.ID),
			expectedStatus: http.StatusMethodNotAllowed,
		},
		{
			name:           "Missing Token",
			method:         "POST",
			token:          "",
			body:           fmt.Sprintf(`{"ticket_id":"%s"}`, ticket.ID),
			expectedStatus: http.StatusUnauthorized,
		},
		{
			name:           "Invalid Agent Token",
			method:         "POST",
			token:          "invalid-token-xyz",
			body:           fmt.Sprintf(`{"ticket_id":"%s"}`, ticket.ID),
			expectedStatus: http.StatusForbidden,
		},
		{
			name:           "Invalid JSON Body",
			method:         "POST",
			token:          "agent-resolve-token-1",
			body:           `{"ticket_id":`,
			expectedStatus: http.StatusBadRequest,
		},
		{
			name:           "Ticket Not Found",
			method:         "POST",
			token:          "agent-resolve-token-1",
			body:           `{"ticket_id":"non-existent-ticket-id"}`,
			expectedStatus: http.StatusNotFound,
		},
		{
			name:           "IDOR Mismatch - Agent 2 resolving Agent 1's ticket",
			method:         "POST",
			token:          "agent-resolve-token-2",
			body:           fmt.Sprintf(`{"ticket_id":"%s"}`, ticket.ID),
			expectedStatus: http.StatusForbidden,
		},
		{
			name:           "Success - Agent 1 resolving assigned ticket via query token",
			method:         "POST",
			token:          "agent-resolve-token-1",
			body:           fmt.Sprintf(`{"ticket_id":"%s"}`, ticket.ID),
			expectedStatus: http.StatusOK,
		},
		{
			name:           "Success - Agent 1 resolving assigned ticket via Bearer header",
			method:         "POST",
			token:          "agent-resolve-token-1",
			headerToken:    true,
			body:           fmt.Sprintf(`{"ticket_id":"%s"}`, ticket.ID),
			expectedStatus: http.StatusOK,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			url := "/chat/tickets/resolve"
			if tt.token != "" && !tt.headerToken {
				url += "?token=" + tt.token
			}
			var bodyReader *bytes.Reader
			if tt.body != "" {
				bodyReader = bytes.NewReader([]byte(tt.body))
			} else {
				bodyReader = bytes.NewReader([]byte{})
			}

			req := httptest.NewRequest(tt.method, url, bodyReader)
			if tt.headerToken && tt.token != "" {
				req.Header.Set("Authorization", "Bearer "+tt.token)
			}
			rec := httptest.NewRecorder()
			c.HandleResolveTicket(rec, req)

			if rec.Code != tt.expectedStatus {
				t.Errorf("Expected status %d, got %d. Body: %s", tt.expectedStatus, rec.Code, rec.Body.String())
			}
		})
	}
}

func TestRegisterRoutes(t *testing.T) {
	c, _, cleanup := setupTestChat(t)
	if c == nil {
		return
	}
	defer cleanup()

	mux := http.NewServeMux()
	c.RegisterRoutes(mux)

	routes := []struct {
		method string
		path   string
	}{
		{"GET", "/chat/ws"},
		{"GET", "/chat/history"},
		{"POST", "/chat/internal/broadcast-location"},
		{"POST", "/chat/tickets"},
		{"POST", "/chat/tickets/resolve"},
	}

	for _, r := range routes {
		req := httptest.NewRequest(r.method, r.path, nil)
		_, pattern := mux.Handler(req)
		if pattern == "" {
			t.Errorf("Expected pattern for %s %s, got empty", r.method, r.path)
		}
	}
}

func TestGetHistory_ExtraCoverage(t *testing.T) {
	c, _, cleanup := setupTestChat(t)
	if c == nil {
		return
	}
	defer cleanup()

	// 1. Non-GET method -> 405 MethodNotAllowed
	req := httptest.NewRequest("POST", "/chat/history?channel=job:123", nil)
	rec := httptest.NewRecorder()
	c.GetHistory(rec, req)
	if rec.Code != http.StatusMethodNotAllowed {
		t.Errorf("Expected 405 MethodNotAllowed, got %d", rec.Code)
	}

	// 2. Missing channel -> 400 Bad Request
	req = httptest.NewRequest("GET", "/chat/history", nil)
	rec = httptest.NewRecorder()
	c.GetHistory(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("Expected 400 Bad Request, got %d", rec.Code)
	}

	// 3. Missing token -> 400 Bad Request
	req = httptest.NewRequest("GET", "/chat/history?channel=job:123", nil)
	rec = httptest.NewRecorder()
	c.GetHistory(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("Expected 400 Bad Request, got %d", rec.Code)
	}

	// 4. Invalid JWT token -> 403 Forbidden
	req = httptest.NewRequest("GET", "/chat/history?channel=job:123&token=invalid-jwt", nil)
	rec = httptest.NewRecorder()
	c.GetHistory(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Errorf("Expected 403 Forbidden, got %d", rec.Code)
	}

	// 5. Auth service unavailable -> 503 ServiceUnavailable
	badAuthServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer badAuthServer.Close()
	c.authServiceURL = badAuthServer.URL

	token, _ := jwtutil.GenerateToken("user-unauth-svc", "user", "tenant-1", "user@example.com")
	req = httptest.NewRequest("GET", "/chat/history?channel=job:valid-job-123&token="+token, nil)
	rec = httptest.NewRecorder()
	c.GetHistory(rec, req)
	if rec.Code != http.StatusServiceUnavailable {
		t.Errorf("Expected 503 ServiceUnavailable on auth service failure, got %d", rec.Code)
	}
}

func TestVerifyToken_ExtraCoverage(t *testing.T) {
	c, _, cleanup := setupTestChat(t)
	if c == nil {
		return
	}
	defer cleanup()

	// 1. Empty ID -> returns false, "", nil
	active, username, err := c.verifyToken("")
	if err != nil || active || username != "" {
		t.Errorf("Expected false, '', nil for empty ID, got active=%v, username=%q, err=%v", active, username, err)
	}

	// 2. Auth service unreachable -> returns false, "", error
	c.authServiceURL = "http://127.0.0.1:59999" // unreachable port
	active, username, err = c.verifyToken("user-unreachable-123")
	if err == nil || active {
		t.Errorf("Expected error and active=false for unreachable auth service, got active=%v, err=%v", active, err)
	}
}

func TestNewChat_Coverage(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	jwtutil.Init("z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")

	cfg := &config.Config{
		AuthServiceURL:       "http://localhost:3002",
		UserServiceURL:       "http://localhost:3003",
		InternalServiceToken: "test-internal-token",
		TLSCertPath:          "",
		TLSKeyPath:           "",
		TLSCAPath:            "",
	}

	c := NewChat(nil, nil, cfg, nil)
	if c == nil {
		t.Fatalf("Expected NewChat to return non-nil instance")
	}
}

func TestCanAccessChannel_ExtraCoverage(t *testing.T) {
	c, mongoStore, cleanup := setupTestChat(t)
	if c == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	// Add support agent
	agent := &store.SupportAgent{
		ID:     "agent-access-1",
		Status: "available",
		Token:  "token-access-1",
	}
	_ = mongoStore.AddSupportAgent(ctx, agent)

	ticket, err := mongoStore.CreateTicketAndAssign(ctx, "cust-access-1", "job-100")
	if err != nil {
		t.Fatalf("CreateTicketAndAssign failed: %v", err)
	}

	// 1. Ticket channel access by assigned support agent -> true
	ok, err := c.canAccessChannel(ticket.AssignedAgentID, "ticket:"+ticket.ID)
	if err != nil || !ok {
		t.Errorf("Expected support agent to have access to ticket channel, got ok=%v, err=%v", ok, err)
	}

	// 2. Non-ticket/non-job channel -> false
	ok, err = c.canAccessChannel("usr-A", "general-channel")
	if err != nil || ok {
		t.Errorf("Expected non-job channel to return false, got ok=%v, err=%v", ok, err)
	}
}

func TestHandleCreateTicket_ExtraCoverage(t *testing.T) {
	c, _, cleanup := setupTestChat(t)
	if c == nil {
		return
	}
	defer cleanup()

	// 1. Non-POST method -> 405 MethodNotAllowed
	req := httptest.NewRequest("GET", "/chat/support/ticket", nil)
	rec := httptest.NewRecorder()
	c.HandleCreateTicket(rec, req)
	if rec.Code != http.StatusMethodNotAllowed {
		t.Errorf("Expected 405 MethodNotAllowed, got %d", rec.Code)
	}

	// 2. Missing customer token -> 401 Unauthorized
	req = httptest.NewRequest("POST", "/chat/support/ticket", strings.NewReader(`{"context_id":"job-100"}`))
	rec = httptest.NewRecorder()
	c.HandleCreateTicket(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Errorf("Expected 401 Unauthorized, got %d", rec.Code)
	}

	// 3. Malformed JSON -> 400 Bad Request
	token, _ := jwtutil.GenerateToken("cust-create-tkt", "user", "tenant-1", "cust@example.com")
	req = httptest.NewRequest("POST", "/chat/support/ticket?token="+token, strings.NewReader(`{"context_id":`))
	rec = httptest.NewRecorder()
	c.HandleCreateTicket(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("Expected 400 Bad Request for malformed JSON, got %d", rec.Code)
	}
}

func TestHandleWebSocket_RateLimiting(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")

	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	cfg := &config.Config{}
	hub := chat.NewHub()
	c := NewChat(hub, nil, cfg, rdb)

	ip := "192.168.1.150:12345"

	// 30 requests within 1 minute should be allowed by wsLimiter (returns 401 for missing token, not 429)
	for i := 0; i < 30; i++ {
		req := httptest.NewRequest("GET", "/chat/ws", nil)
		req.RemoteAddr = ip
		rec := httptest.NewRecorder()
		c.HandleWebSocket(rec, req)
		if rec.Code == http.StatusTooManyRequests {
			t.Fatalf("Request %d was unexpectedly rate limited (429)", i+1)
		}
	}

	// 31st request from same IP should be rate limited (429 Too Many Requests)
	req31 := httptest.NewRequest("GET", "/chat/ws", nil)
	req31.RemoteAddr = ip
	rec31 := httptest.NewRecorder()
	c.HandleWebSocket(rec31, req31)

	if rec31.Code != http.StatusTooManyRequests {
		t.Fatalf("Expected 429 Too Many Requests on 31st call, got %d. Body: %s", rec31.Code, rec31.Body.String())
	}
}

// TestWebSocket_MessageRateLimiting verifies the post-handshake per-client
// flood guard: beyond the per-minute message budget the server replies with
// a rate_limited error frame, stops persisting/broadcasting further messages,
// and leaves already-accepted messages intact.
func TestWebSocket_MessageRateLimiting(t *testing.T) {
	c, mongoStore, cleanup := setupTestChat(t)
	if c == nil {
		return
	}
	defer cleanup()

	mux := http.NewServeMux()
	mux.HandleFunc("/chat/ws", c.HandleWebSocket)
	server := httptest.NewServer(mux)
	defer server.Close()

	wsURL := "ws" + strings.TrimPrefix(server.URL, "http") + "/chat/ws"

	tokenOwner, _ := jwtutil.GenerateToken("owner-1", "owner", "tenant-1", "owner@test.com")

	dialer := websocket.Dialer{}
	header := http.Header{}
	header.Set("Origin", "http://localhost:3000")
	conn, _, err := dialer.Dial(wsURL+"?token="+tokenOwner, header)
	if err != nil {
		t.Fatalf("Failed to dial ws: %v", err)
	}
	defer conn.Close()

	// Subscribe to an authorized channel.
	if err := conn.WriteJSON(map[string]string{"action": "subscribe", "channel": "job:123"}); err != nil {
		t.Fatalf("subscribe write failed: %v", err)
	}
	subDeadline := time.Now().Add(3 * time.Second)
	for {
		_, raw, err := conn.ReadMessage()
		if err != nil {
			t.Fatalf("read during subscribe failed: %v", err)
		}
		if strings.Contains(string(raw), `"subscribed"`) {
			break
		}
		if time.Now().After(subDeadline) {
			t.Fatalf("never received subscribed confirmation")
		}
	}

	// Drain server frames in the background while flooding.
	const totalMessages = 70
	var mu sync.Mutex
	accepted := 0
	rateLimitedErrs := 0
	done := make(chan struct{})
	go func() {
		defer close(done)
		deadline := time.Now().Add(3 * time.Second)
		for time.Now().Before(deadline) {
			conn.SetReadDeadline(time.Now().Add(500 * time.Millisecond))
			_, raw, err := conn.ReadMessage()
			if err != nil {
				return
			}
			// Frames may be newline-batched; evaluate each line.
			for _, line := range strings.Split(string(raw), "\n") {
				var frame map[string]any
				if json.Unmarshal([]byte(line), &frame) != nil {
					continue
				}
				mu.Lock()
				if frame["error"] == "rate_limited" {
					rateLimitedErrs++
				} else if _, ok := frame["content"].(string); ok && strings.HasPrefix(frame["content"].(string), "flood-") {
					accepted++
				}
				mu.Unlock()
			}
		}
	}()

	for i := 0; i < totalMessages; i++ {
		if err := conn.WriteJSON(map[string]string{
			"action":  "message",
			"channel": "job:123",
			"content": fmt.Sprintf("flood-%d", i),
		}); err != nil {
			t.Fatalf("message write %d failed: %v", i+1, err)
		}
	}

	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("drain goroutine did not finish")
	}

	mu.Lock()
	a, rl := accepted, rateLimitedErrs
	mu.Unlock()

	if rl == 0 {
		t.Errorf("Expected at least one rate_limited error frame when sending %d messages, got none", totalMessages)
	}
	if a >= totalMessages {
		t.Errorf("Expected some messages to be rejected by the flood guard, but all %d were accepted", totalMessages)
	}

	// Persisted history must match the accepted (pre-limit) count only.
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	history, err := mongoStore.GetHistory(ctx, "job:123", 200)
	if err != nil {
		t.Fatalf("GetHistory failed: %v", err)
	}
	if len(history) != a {
		t.Errorf("Expected %d persisted messages (accepted count), got %d", a, len(history))
	}
	if len(history) >= totalMessages {
		t.Errorf("Flood guard failed: all %d messages were persisted", totalMessages)
	}
}

// WS Origin policy regression guards: non-browser clients (dart:io WebSocket
// on mobile, CLI tooling) send NO Origin header and must be admitted, while a
// PRESENT Origin must still match the configured allow-list entry exactly.
func TestIsOriginAllowed(t *testing.T) {
	c := &Chat{allowedOrigin: "http://localhost:3000"}

	cases := []struct {
		origin string
		want   bool
	}{
		{"", true},                                // non-browser client (no Origin)
		{"http://localhost:3000", true},           // exact match
		{"https://localhost:3000", false},         // scheme mismatch
		{"http://localhost:3000.evil.com", false}, // suffix spoof
		{"http://evil.com", false},                // foreign origin
	}
	for _, tc := range cases {
		if got := c.isOriginAllowed(tc.origin); got != tc.want {
			t.Errorf("isOriginAllowed(%q) = %v, want %v", tc.origin, got, tc.want)
		}
	}
}

func TestGetCustomerTickets_IsolationAndPagination(t *testing.T) {
	c, mongoStore, cleanup := setupTestChat(t)
	if c == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()

	// Create tickets for Alice (customer-alice)
	t1, err := mongoStore.CreateTicketAndAssign(ctx, "customer-alice", "job-alice-1")
	if err != nil {
		t.Fatalf("failed to create ticket: %v", err)
	}
	t2, err := mongoStore.CreateTicketAndAssign(ctx, "customer-alice", "job-alice-2")
	if err != nil {
		t.Fatalf("failed to create ticket: %v", err)
	}
	t3, err := mongoStore.CreateTicketAndAssign(ctx, "customer-alice", "job-alice-3")
	if err != nil {
		t.Fatalf("failed to create ticket: %v", err)
	}

	// Create tickets for Bob (customer-bob)
	tb1, err := mongoStore.CreateTicketAndAssign(ctx, "customer-bob", "job-bob-1")
	if err != nil {
		t.Fatalf("failed to create ticket: %v", err)
	}
	tb2, err := mongoStore.CreateTicketAndAssign(ctx, "customer-bob", "job-bob-2")
	if err != nil {
		t.Fatalf("failed to create ticket: %v", err)
	}

	tokenAlice, _ := jwtutil.GenerateToken("customer-alice", "user", "tenant-1", "alice@example.com")
	tokenBob, _ := jwtutil.GenerateToken("customer-bob", "user", "tenant-1", "bob@example.com")

	// 1. Wrong method -> 405 Method Not Allowed
	reqPost := httptest.NewRequest("POST", "/chat/tickets/mine", nil)
	reqPost.Header.Set("Authorization", "Bearer "+tokenAlice)
	recPost := httptest.NewRecorder()
	c.GetCustomerTickets(recPost, reqPost)
	if recPost.Code != http.StatusMethodNotAllowed {
		t.Errorf("Expected 405 for POST, got %d", recPost.Code)
	}

	// 2. Unauthenticated -> 401 Unauthorized
	reqUnauth := httptest.NewRequest("GET", "/chat/tickets/mine", nil)
	recUnauth := httptest.NewRecorder()
	c.GetCustomerTickets(recUnauth, reqUnauth)
	if recUnauth.Code != http.StatusUnauthorized {
		t.Errorf("Expected 401 for unauthenticated, got %d", recUnauth.Code)
	}

	// 3. Customer Isolation: Alice only sees Alice's tickets, not Bob's
	reqAlice := httptest.NewRequest("GET", "/chat/tickets/mine", nil)
	reqAlice.Header.Set("Authorization", "Bearer "+tokenAlice)
	recAlice := httptest.NewRecorder()
	c.GetCustomerTickets(recAlice, reqAlice)
	if recAlice.Code != http.StatusOK {
		t.Fatalf("Expected 200 for Alice, got %d: %s", recAlice.Code, recAlice.Body.String())
	}
	var respAlice CustomerListTicketsResponse
	if err := json.NewDecoder(recAlice.Body).Decode(&respAlice); err != nil {
		t.Fatalf("failed to decode Alice response: %v", err)
	}
	if respAlice.Total != 3 {
		t.Errorf("Expected Total=3 for Alice, got %d", respAlice.Total)
	}
	if len(respAlice.Tickets) != 3 {
		t.Errorf("Expected 3 tickets for Alice, got %d", len(respAlice.Tickets))
	}
	for _, tkt := range respAlice.Tickets {
		if tkt.CustomerID != "customer-alice" {
			t.Errorf("Data leak! Found ticket with CustomerID=%s in Alice's list (ticket ID: %s)", tkt.CustomerID, tkt.ID)
		}
		if tkt.ID == tb1.ID || tkt.ID == tb2.ID {
			t.Errorf("Data leak! Bob's ticket %s visible in Alice's list", tkt.ID)
		}
	}

	// 4. Customer Isolation: Bob only sees Bob's tickets, via query param token
	reqBob := httptest.NewRequest("GET", "/chat/tickets/mine?token="+tokenBob, nil)
	recBob := httptest.NewRecorder()
	c.GetCustomerTickets(recBob, reqBob)
	if recBob.Code != http.StatusOK {
		t.Fatalf("Expected 200 for Bob, got %d: %s", recBob.Code, recBob.Body.String())
	}
	var respBob CustomerListTicketsResponse
	if err := json.NewDecoder(recBob.Body).Decode(&respBob); err != nil {
		t.Fatalf("failed to decode Bob response: %v", err)
	}
	if respBob.Total != 2 {
		t.Errorf("Expected Total=2 for Bob, got %d", respBob.Total)
	}
	if len(respBob.Tickets) != 2 {
		t.Errorf("Expected 2 tickets for Bob, got %d", len(respBob.Tickets))
	}
	for _, tkt := range respBob.Tickets {
		if tkt.CustomerID != "customer-bob" {
			t.Errorf("Data leak! Found ticket with CustomerID=%s in Bob's list", tkt.CustomerID)
		}
		if tkt.ID == t1.ID || tkt.ID == t2.ID || tkt.ID == t3.ID {
			t.Errorf("Data leak! Alice's ticket %s visible in Bob's list", tkt.ID)
		}
	}

	// 5. Pagination: Alice page=1&limit=2 -> 2 tickets, page=2&limit=2 -> 1 ticket
	reqP1 := httptest.NewRequest("GET", "/chat/tickets/mine?page=1&limit=2", nil)
	reqP1.Header.Set("Authorization", "Bearer "+tokenAlice)
	recP1 := httptest.NewRecorder()
	c.GetCustomerTickets(recP1, reqP1)
	var respP1 CustomerListTicketsResponse
	_ = json.NewDecoder(recP1.Body).Decode(&respP1)
	if len(respP1.Tickets) != 2 || respP1.Total != 3 || respP1.Page != 1 || respP1.Limit != 2 {
		t.Errorf("Page 1 unexpected: len=%d, total=%d, page=%d, limit=%d", len(respP1.Tickets), respP1.Total, respP1.Page, respP1.Limit)
	}

	reqP2 := httptest.NewRequest("GET", "/chat/tickets/mine?page=2&limit=2", nil)
	reqP2.Header.Set("Authorization", "Bearer "+tokenAlice)
	recP2 := httptest.NewRecorder()
	c.GetCustomerTickets(recP2, reqP2)
	var respP2 CustomerListTicketsResponse
	_ = json.NewDecoder(recP2.Body).Decode(&respP2)
	if len(respP2.Tickets) != 1 || respP2.Total != 3 || respP2.Page != 2 || respP2.Limit != 2 {
		t.Errorf("Page 2 unexpected: len=%d, total=%d, page=%d, limit=%d", len(respP2.Tickets), respP2.Total, respP2.Page, respP2.Limit)
	}

	// 6. Pagination Clamping: page=-5, limit=500 -> page=1, limit=20
	reqClamp := httptest.NewRequest("GET", "/chat/tickets/mine?page=-5&limit=500", nil)
	reqClamp.Header.Set("Authorization", "Bearer "+tokenAlice)
	recClamp := httptest.NewRecorder()
	c.GetCustomerTickets(recClamp, reqClamp)
	var respClamp CustomerListTicketsResponse
	_ = json.NewDecoder(recClamp.Body).Decode(&respClamp)
	if respClamp.Page != 1 || respClamp.Limit != 20 {
		t.Errorf("Expected clamped page=1, limit=20, got page=%d, limit=%d", respClamp.Page, respClamp.Limit)
	}

	// 7. Empty customer tickets: Charlie has 0 tickets
	tokenCharlie, _ := jwtutil.GenerateToken("customer-charlie", "user", "tenant-1", "charlie@example.com")
	reqCharlie := httptest.NewRequest("GET", "/chat/tickets/mine", nil)
	reqCharlie.Header.Set("Authorization", "Bearer "+tokenCharlie)
	recCharlie := httptest.NewRecorder()
	c.GetCustomerTickets(recCharlie, reqCharlie)
	var respCharlie CustomerListTicketsResponse
	_ = json.NewDecoder(recCharlie.Body).Decode(&respCharlie)
	if respCharlie.Total != 0 || len(respCharlie.Tickets) != 0 || respCharlie.Tickets == nil {
		t.Errorf("Expected empty slice for Charlie, got total=%d, len=%d, tickets=%v", respCharlie.Total, len(respCharlie.Tickets), respCharlie.Tickets)
	}
}
