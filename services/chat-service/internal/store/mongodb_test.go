package store

import (
	"context"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/project/chat-service/internal/chat"
	"go.mongodb.org/mongo-driver/v2/bson"
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
	if err != nil && os.Getenv("MONGO_URI") == "" {
		mongoURI = "mongodb://root:devpassword123@localhost:27017/?authSource=admin"
		s, err = NewMongoDB(ctx, mongoURI, dbName)
		if err != nil {
			mongoURI = "mongodb://admin:adminpassword@localhost:27017"
			s, err = NewMongoDB(ctx, mongoURI, dbName)
		}
	}
	if err != nil {
		t.Skipf("Skipping MongoDB store tests: MongoDB unreachable at %s (%v)", mongoURI, err)
		return nil, nil
	}

	// Verify write permission (fallback to authenticated URI if unauthenticated ping succeeded but writes require auth)
	testMsg := &chat.Message{Channel: "test", Content: "ping"}
	if err := s.PersistMessage(ctx, testMsg); err != nil {
		if os.Getenv("MONGO_URI") == "" {
			_ = s.Close(ctx)
			mongoURI = "mongodb://root:devpassword123@localhost:27017/?authSource=admin"
			s, err = NewMongoDB(ctx, mongoURI, dbName)
			if err != nil {
				mongoURI = "mongodb://admin:adminpassword@localhost:27017"
				s, err = NewMongoDB(ctx, mongoURI, dbName)
			}
			if err == nil {
				err = s.PersistMessage(ctx, testMsg)
			}
		}
		if err != nil {
			t.Skipf("Skipping MongoDB store tests: MongoDB write failed (%v)", err)
			return nil, nil
		}
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
	if msg1.ID == "" || msg2.ID == "" {
		t.Errorf("Expected PersistMessage to populate ID, got msg1.ID=%q, msg2.ID=%q", msg1.ID, msg2.ID)
	}
	if msg1.CreatedAt == nil || msg2.CreatedAt == nil {
		t.Errorf("Expected PersistMessage to populate CreatedAt, got msg1.CreatedAt=%v, msg2.CreatedAt=%v", msg1.CreatedAt, msg2.CreatedAt)
	}
	if history[0].ID != msg1.ID || history[1].ID != msg2.ID {
		t.Errorf("Expected history to include message IDs: got [0].ID=%q want %q, [1].ID=%q want %q", history[0].ID, msg1.ID, history[1].ID, msg2.ID)
	}
	if history[0].CreatedAt == nil || history[1].CreatedAt == nil {
		t.Errorf("Expected history to decode non-nil CreatedAt timestamps")
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

	// 2. GetAgent — token is now stored as a SHA-256 digest, never plaintext
	gotAgent, err := s.GetAgent(ctx, "agent-1")
	if err != nil || gotAgent == nil || gotAgent.Token == "agent-token-123" || len(gotAgent.Token) != 64 {
		t.Errorf("GetAgent failed or token not hashed at rest: %v, err=%v", gotAgent, err)
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

	// 1. CreateTicketAndAssign creates ticket with "pending" status (unassigned)
	ticketPending, err := s.CreateTicketAndAssign(ctx, "cust-1", "job-100")
	if err != nil || ticketPending.Status != "pending" || ticketPending.AssignedAgentID != "" {
		t.Fatalf("Expected ticket pending and unassigned: %v, err=%v", ticketPending, err)
	}

	// 2. GetTicket verifies pending ticket
	gotTicket, err := s.GetTicket(ctx, ticketPending.ID)
	if err != nil || gotTicket.CustomerID != "cust-1" || gotTicket.Status != "pending" {
		t.Errorf("GetTicket failed: %v, err=%v", gotTicket, err)
	}

	// 3. AdminAcceptTicket transitions ticket from "pending" to "assigned"
	acceptedTicket, err := s.AdminAcceptTicket(ctx, ticketPending.ID, "rev-001")
	if err != nil || acceptedTicket.Status != "assigned" || acceptedTicket.AssignedReviewer != "rev-001" {
		t.Fatalf("AdminAcceptTicket failed: %v, err=%v", acceptedTicket, err)
	}

	// 4. Duplicate AdminAcceptTicket returns conflict error
	_, err = s.AdminAcceptTicket(ctx, ticketPending.ID, "rev-002")
	if err == nil {
		t.Fatalf("expected error on duplicate accept, got nil")
	}

	// 5. AdminResolveTicket marks ticket as resolved
	resolvedTicket, err := s.AdminResolveTicket(ctx, ticketPending.ID, "Resolved properly", "rev-001")
	if err != nil || resolvedTicket.Status != "resolved" {
		t.Fatalf("AdminResolveTicket failed: %v, err=%v", resolvedTicket, err)
	}

	// 6. AdminAcceptTicket on resolved ticket returns error
	_, err = s.AdminAcceptTicket(ctx, ticketPending.ID, "rev-003")
	if err == nil {
		t.Fatalf("expected error on accept of resolved ticket, got nil")
	}
}

func TestMongoDB_ConcurrentPersistMessageNoCollision(t *testing.T) {
	s, cleanup := setupTestMongoDB(t)
	if s == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	channel := "concurrent-test-channel"

	const numMsgs = 500
	const numGoroutines = 10
	errCh := make(chan error, numMsgs)
	sem := make(chan struct{}, numGoroutines)

	for i := 0; i < numMsgs; i++ {
		sem <- struct{}{}
		go func(idx int) {
			defer func() { <-sem }()
			msg := &chat.Message{
				Channel:        channel,
				SenderID:       fmt.Sprintf("user-%d", idx%numGoroutines),
				SenderUsername: fmt.Sprintf("user%d", idx%numGoroutines),
				Content:        fmt.Sprintf("Concurrent message %d", idx),
				Type:           "chat",
			}
			errCh <- s.PersistMessage(ctx, msg)
		}(i)
	}

	for i := 0; i < numMsgs; i++ {
		if err := <-errCh; err != nil {
			t.Errorf("Concurrent PersistMessage failed: %v", err)
		}
	}

	history, err := s.GetHistory(ctx, channel, 1000)
	if err != nil || len(history) != numMsgs {
		t.Fatalf("Expected %d persisted messages in history, got %d (err: %v)", numMsgs, len(history), err)
	}

	// Verify all raw documents in MongoDB have valid msg- UUID IDs, not UnixNano timestamps
	cursor, err := s.messages.Find(ctx, map[string]interface{}{"channel": channel})
	if err != nil {
		t.Fatalf("Failed to query messages collection: %v", err)
	}
	defer cursor.Close(ctx)

	var docs []struct {
		ID string `bson:"_id"`
	}
	if err := cursor.All(ctx, &docs); err != nil {
		t.Fatalf("Failed to decode message docs: %v", err)
	}

	idMap := make(map[string]bool)
	for _, doc := range docs {
		if idMap[doc.ID] {
			t.Errorf("Duplicate message ID found: %s", doc.ID)
		}
		idMap[doc.ID] = true

		// Assert ID format is msg-<uuid> (where UUID has hyphenated RFC4122 pattern, e.g. length > 30)
		if len(doc.ID) < 30 || doc.ID[:4] != "msg-" {
			t.Errorf("Message ID %q does not match collision-resistant msg-<uuid> format", doc.ID)
		}
	}

	if len(idMap) != numMsgs {
		t.Errorf("Expected %d unique message IDs, got %d", numMsgs, len(idMap))
	}
}

func TestMongoDB_EnsureIndexes(t *testing.T) {
	s, cleanup := setupTestMongoDB(t)
	if s == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()

	// Assert channel-timestamp index exists on messages collection
	curM, err := s.messages.Indexes().List(ctx)
	if err != nil {
		t.Fatalf("failed to list messages indexes: %v", err)
	}
	var msgIndexes []bson.M
	if err := curM.All(ctx, &msgIndexes); err != nil {
		t.Fatalf("failed to decode messages indexes: %v", err)
	}
	var foundMsgIndex bool
	for _, idx := range msgIndexes {
		if idx["name"] == "channel_1_timestamp_1" {
			foundMsgIndex = true
			break
		}
	}
	if !foundMsgIndex {
		t.Errorf("expected channel_1_timestamp_1 index on messages collection, found: %+v", msgIndexes)
	}

	// Assert indexes exist on complaint_tickets collection (customer_id, assigned_agent_id)
	curT, err := s.tickets.Indexes().List(ctx)
	if err != nil {
		t.Fatalf("failed to list tickets indexes: %v", err)
	}
	var ticketIndexes []bson.M
	if err := curT.All(ctx, &ticketIndexes); err != nil {
		t.Fatalf("failed to decode tickets indexes: %v", err)
	}
	var foundCustIndex, foundAgentIndex bool
	for _, idx := range ticketIndexes {
		if idx["name"] == "customer_id_1" {
			foundCustIndex = true
		}
		if idx["name"] == "assigned_agent_id_1" {
			foundAgentIndex = true
		}
	}
	if !foundCustIndex {
		t.Errorf("expected customer_id_1 index on tickets collection, found: %+v", ticketIndexes)
	}
	if !foundAgentIndex {
		t.Errorf("expected assigned_agent_id_1 index on tickets collection, found: %+v", ticketIndexes)
	}

	// Assert unique token index and status index exist on support_agents collection
	curA, err := s.agents.Indexes().List(ctx)
	if err != nil {
		t.Fatalf("failed to list agents indexes: %v", err)
	}
	var agentIndexes []bson.M
	if err := curA.All(ctx, &agentIndexes); err != nil {
		t.Fatalf("failed to decode agents indexes: %v", err)
	}
	var foundTokenIndex, foundStatusIndex bool
	for _, idx := range agentIndexes {
		if idx["name"] == "token_1" && idx["unique"] == true {
			foundTokenIndex = true
		}
		if idx["name"] == "status_1" {
			foundStatusIndex = true
		}
	}
	if !foundTokenIndex {
		t.Errorf("expected unique token_1 index on support_agents collection, found: %+v", agentIndexes)
	}
	if !foundStatusIndex {
		t.Errorf("expected status_1 index on support_agents collection, found: %+v", agentIndexes)
	}
}
