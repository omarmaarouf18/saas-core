package store

import (
	"context"
	"errors"
	"testing"
	"time"

	"go.mongodb.org/mongo-driver/v2/bson"
)

func TestResolveTicket_CAS_AlreadyResolved(t *testing.T) {
	s, cleanup := setupTestMongoDB(t)
	if s == nil {
		return
	}
	defer cleanup()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	agent := &SupportAgent{
		ID:     "agent-test-cas",
		Status: "available",
		Token:  "secret-token",
	}
	if err := s.AddSupportAgent(ctx, agent); err != nil {
		t.Fatalf("failed to insert agent: %v", err)
	}

	ticket, err := s.CreateTicketAndAssign(ctx, "cust-cas-1", "ctx-1")
	if err != nil {
		t.Fatalf("failed to create ticket: %v", err)
	}

	// First resolution should succeed
	if err := s.ResolveTicket(ctx, ticket.ID); err != nil {
		t.Fatalf("first ResolveTicket failed: %v", err)
	}

	// Second resolution on already resolved ticket must fail with ErrTicketAlreadyResolved
	err = s.ResolveTicket(ctx, ticket.ID)
	if err == nil {
		t.Fatalf("expected ErrTicketAlreadyResolved on already resolved ticket, got nil")
	}
	if !errors.Is(err, ErrTicketAlreadyResolved) {
		t.Fatalf("expected ErrTicketAlreadyResolved, got: %v", err)
	}
}

func TestSweepStrandedAgents(t *testing.T) {
	s, cleanup := setupTestMongoDB(t)
	if s == nil {
		return
	}
	defer cleanup()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	// 1. Agent stranded with non-existent ticket ID
	strandedAgent1 := &SupportAgent{
		ID:              "agent-stranded-missing-tkt",
		Status:          "busy",
		CurrentTicketID: "tkt-does-not-exist",
		Token:           "token1",
	}
	if err := s.AddSupportAgent(ctx, strandedAgent1); err != nil {
		t.Fatalf("failed to insert agent1: %v", err)
	}

	// 2. Agent stranded with empty ticket ID but status busy
	strandedAgent2 := &SupportAgent{
		ID:              "agent-stranded-empty-tkt",
		Status:          "busy",
		CurrentTicketID: "",
		Token:           "token2",
	}
	if err := s.AddSupportAgent(ctx, strandedAgent2); err != nil {
		t.Fatalf("failed to insert agent2: %v", err)
	}

	// 3. Agent stranded with already resolved ticket
	resolvedTkt := &ComplaintTicket{
		ID:              "tkt-already-resolved",
		CustomerID:      "cust-2",
		Status:          "resolved",
		AssignedAgentID: "agent-stranded-resolved-tkt",
		CreatedAt:       time.Now().UTC(),
	}
	if _, err := s.tickets.InsertOne(ctx, resolvedTkt); err != nil {
		t.Fatalf("failed to insert resolved ticket: %v", err)
	}

	strandedAgent3 := &SupportAgent{
		ID:              "agent-stranded-resolved-tkt",
		Status:          "busy",
		CurrentTicketID: resolvedTkt.ID,
		Token:           "token3",
	}
	if err := s.AddSupportAgent(ctx, strandedAgent3); err != nil {
		t.Fatalf("failed to insert agent3: %v", err)
	}

	// 4. Valid busy agent with active open ticket (should NOT be swept)
	activeTkt := &ComplaintTicket{
		ID:              "tkt-active-open",
		CustomerID:      "cust-3",
		Status:          "assigned",
		AssignedAgentID: "agent-active-valid",
		CreatedAt:       time.Now().UTC(),
	}
	if _, err := s.tickets.InsertOne(ctx, activeTkt); err != nil {
		t.Fatalf("failed to insert active ticket: %v", err)
	}

	validAgent := &SupportAgent{
		ID:              "agent-active-valid",
		Status:          "busy",
		CurrentTicketID: activeTkt.ID,
		Token:           "token4",
	}
	if err := s.AddSupportAgent(ctx, validAgent); err != nil {
		t.Fatalf("failed to insert validAgent: %v", err)
	}

	// Run sweeper
	recovered, err := s.SweepStrandedAgents(ctx)
	if err != nil {
		t.Fatalf("SweepStrandedAgents failed: %v", err)
	}

	if recovered != 3 {
		t.Fatalf("expected 3 stranded agents to be recovered, got %d", recovered)
	}

	// Verify swept agents are now available
	for _, id := range []string{"agent-stranded-missing-tkt", "agent-stranded-empty-tkt", "agent-stranded-resolved-tkt"} {
		var a SupportAgent
		if err := s.agents.FindOne(ctx, bson.M{"_id": id}).Decode(&a); err != nil {
			t.Fatalf("failed to find agent %s: %v", id, err)
		}
		if a.Status != "available" {
			t.Errorf("agent %s status expected 'available', got %q", id, a.Status)
		}
		if a.CurrentTicketID != "" {
			t.Errorf("agent %s current_ticket_id expected empty, got %q", id, a.CurrentTicketID)
		}
	}

	// Verify valid busy agent was NOT touched
	var v SupportAgent
	if err := s.agents.FindOne(ctx, bson.M{"_id": validAgent.ID}).Decode(&v); err != nil {
		t.Fatalf("failed to find valid agent: %v", err)
	}
	if v.Status != "busy" || v.CurrentTicketID != activeTkt.ID {
		t.Errorf("valid agent mutated unexpectedly: status=%q, ticketID=%q", v.Status, v.CurrentTicketID)
	}
}
