package store

import (
	"context"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/project/chat-service/internal/chat"
)

func setupTestMongoDB(t *testing.T) (*MongoDB, func()) {
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	dbName := fmt.Sprintf("saas_chat_store_test_%d", time.Now().UnixNano())
	s, err := NewMongoDB(ctx, mongoURI, dbName)
	if err != nil {
		t.Skipf("Skipping MongoDB store tests: MongoDB unreachable at %s (%v)", mongoURI, err)
		return nil, nil
	}

	cleanup := func() {
		cleanupCtx, cCancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cCancel()
		_ = s.DropDatabase(cleanupCtx)
		_ = s.Close(cleanupCtx)
	}

	return s, cleanup
}

func TestMongoDB_InvalidURI(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 1*time.Second)
	defer cancel()

	_, err := NewMongoDB(ctx, "mongodb://127.0.0.1:59999", "testdb")
	if err == nil {
		t.Errorf("Expected error connecting to unreachable MongoDB URI, got nil")
	}
}

func TestMongoDB_MessageOperations(t *testing.T) {
	s, cleanup := setupTestMongoDB(t)
	if s == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	channel := "test-channel-1"

	msg1 := &chat.Message{
		Channel:        channel,
		SenderID:       "user-1",
		SenderUsername: "userone",
		Content:        "Hello world",
		Type:           "chat",
	}
	msg2 := &chat.Message{
		Channel:        channel,
		SenderID:       "user-2",
		SenderUsername: "usertwo",
		Content:        "Hi there",
		Type:           "chat",
	}

	// 1. PersistMessage
	if err := s.PersistMessage(ctx, msg1); err != nil {
		t.Fatalf("PersistMessage msg1 failed: %v", err)
	}
	time.Sleep(10 * time.Millisecond)
	if err := s.PersistMessage(ctx, msg2); err != nil {
		t.Fatalf("PersistMessage msg2 failed: %v", err)
	}

	// 2. GetHistory with default limit
	history, err := s.GetHistory(ctx, channel, 0)
	if err != nil || len(history) != 2 {
		t.Fatalf("GetHistory failed: len=%d, err=%v", len(history), err)
	}
	if history[0].SenderID != "user-1" || history[1].SenderID != "user-2" {
		t.Errorf("Expected oldest to newest sorting in history: got %v", history)
	}
}

func TestMongoDB_SupportAgentOperations(t *testing.T) {
	s, cleanup := setupTestMongoDB(t)
	if s == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()

	agent := &SupportAgent{
		ID:     "agent-1",
		Status: "available",
		Token:  "agent-token-123",
	}

	// 1. AddSupportAgent
	if err := s.AddSupportAgent(ctx, agent); err != nil {
		t.Fatalf("AddSupportAgent failed: %v", err)
	}

	// 2. GetAgent
	gotAgent, err := s.GetAgent(ctx, "agent-1")
	if err != nil || gotAgent.Token != "agent-token-123" {
		t.Errorf("GetAgent failed: %v, err=%v", gotAgent, err)
	}

	// 3. GetAgentByToken
	gotByTok, err := s.GetAgentByToken(ctx, "agent-token-123")
	if err != nil || gotByTok.ID != "agent-1" {
		t.Errorf("GetAgentByToken failed: %v, err=%v", gotByTok, err)
	}

	// Non-existent
	_, err = s.GetAgent(ctx, "non-existent")
	if err == nil {
		t.Errorf("Expected error for non-existent agent, got nil")
	}
}

func TestMongoDB_ComplaintTicketOperations(t *testing.T) {
	s, cleanup := setupTestMongoDB(t)
	if s == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()

	// 1. CreateTicketAndAssign when no agent is available -> ticket "pending"
	ticketPending, err := s.CreateTicketAndAssign(ctx, "cust-1", "job-100")
	if err != nil || ticketPending.Status != "pending" {
		t.Fatalf("Expected ticket pending when no agent available: %v, err=%v", ticketPending, err)
	}

	// 2. Add an available support agent
	agent := &SupportAgent{
		ID:     "agent-supp-1",
		Status: "available",
		Token:  "supp-token-1",
	}
	_ = s.AddSupportAgent(ctx, agent)

	// 3. CreateTicketAndAssign when agent is available -> ticket "assigned"
	ticketAssigned, err := s.CreateTicketAndAssign(ctx, "cust-2", "job-101")
	if err != nil || ticketAssigned.Status != "assigned" || ticketAssigned.AssignedAgentID != "agent-supp-1" {
		t.Fatalf("Expected ticket assigned: %v, err=%v", ticketAssigned, err)
	}

	// Verify agent status changed to busy
	updatedAgent, _ := s.GetAgent(ctx, "agent-supp-1")
	if updatedAgent.Status != "busy" || updatedAgent.CurrentTicketID != ticketAssigned.ID {
		t.Errorf("Expected agent to be busy with ticket ID, got %v", updatedAgent)
	}

	// 4. GetTicket
	gotTicket, err := s.GetTicket(ctx, ticketAssigned.ID)
	if err != nil || gotTicket.CustomerID != "cust-2" {
		t.Errorf("GetTicket failed: %v, err=%v", gotTicket, err)
	}

	// 5. ResolveTicket
	if err := s.ResolveTicket(ctx, ticketAssigned.ID); err != nil {
		t.Fatalf("ResolveTicket failed: %v", err)
	}

	resolvedTicket, _ := s.GetTicket(ctx, ticketAssigned.ID)
	if resolvedTicket.Status != "resolved" {
		t.Errorf("Expected status resolved, got %s", resolvedTicket.Status)
	}

	freedAgent, _ := s.GetAgent(ctx, "agent-supp-1")
	if freedAgent.Status != "available" || freedAgent.CurrentTicketID != "" {
		t.Errorf("Expected agent to be freed and available, got %v", freedAgent)
	}
}
