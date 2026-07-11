package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"sync"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
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
