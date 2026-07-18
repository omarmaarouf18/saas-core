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

		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(map[string]string{"error": "job not found"})
	}))
	defer mockUserServer.Close()

	// Instantiate Chat handler group (we can pass nil hub and store as they aren't used in canAccessChannel)
	cfg := &config.Config{
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
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	dbName := fmt.Sprintf("chat_platform_test_%d", time.Now().UnixNano())
	mongoStore, err := store.NewMongoDB(ctx, mongoURI, dbName)
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
	chatHandler.tokenCache["job-owner-id"] = time.Now().Add(60 * time.Second)
	chatHandler.tokenCache["stranger-id"] = time.Now().Add(60 * time.Second)

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
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	dbName := fmt.Sprintf("chat_platform_test_%d", time.Now().UnixNano())
	mongoStore, err := store.NewMongoDB(ctx, mongoURI, dbName)
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
			ticket, err := mongoStore.CreateTicketAndAssign(context.Background(), fmt.Sprintf("customer-%d", idx), "context-xyz")
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
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	dbName := fmt.Sprintf("chat_platform_test_%d", time.Now().UnixNano())
	mongoStore, err := store.NewMongoDB(ctx, mongoURI, dbName)
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
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	dbName := fmt.Sprintf("chat_platform_test_%d", time.Now().UnixNano())
	mongoStore, err := store.NewMongoDB(ctx, mongoURI, dbName)
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

	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	dbName := fmt.Sprintf("saas_chat_test_%d", time.Now().UnixNano())
	s, err := store.NewMongoDB(ctx, mongoURI, dbName)
	if err != nil {
		t.Skipf("Skipping chat-service store integration tests: MongoDB not available at %s (%v)", mongoURI, err)
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
	c.tokenCache["owner-1"] = time.Now().Add(60 * time.Second)
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
