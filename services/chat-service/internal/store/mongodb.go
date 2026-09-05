package store

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"log"
	"regexp"
	"time"

	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
	"go.mongodb.org/mongo-driver/v2/mongo/options"

	"github.com/project/chat-service/internal/chat"
	"github.com/project/shared/infra/jwtutil"
)

type SupportAgent struct {
	ID              string `bson:"_id" json:"agent_id"`
	Status          string `bson:"status" json:"status"` // "available", "busy", "offline"
	AssignedTickets int    `bson:"assigned_tickets" json:"assigned_tickets"`
	// Token is the agent's bearer credential: stored as a SHA-256 digest and
	// never serialized (json:"-") so it cannot leak through any response.
	Token string `bson:"token" json:"-"`
}

type ComplaintTicket struct {
	ID              string     `bson:"_id" json:"ticket_id"`
	CustomerID      string     `bson:"customer_id" json:"customer_id"`
	AssignedAgentID string     `bson:"assigned_agent_id,omitempty" json:"assigned_agent_id,omitempty"`
	ContextID       string     `bson:"context_id,omitempty" json:"context_id,omitempty"`
	Subject         string     `bson:"subject,omitempty" json:"subject,omitempty"`
	Status          string     `bson:"status" json:"status"` // "pending", "assigned", "resolved"
	ResolutionNote  string     `bson:"resolution_note,omitempty" json:"resolution_note,omitempty"`
	ResolvedBy      string     `bson:"resolved_by,omitempty" json:"resolved_by,omitempty"`
	ResolvedAt      *time.Time `bson:"resolved_at,omitempty" json:"resolved_at,omitempty"`
	CreatedAt       time.Time  `bson:"created_at" json:"created_at"`
	UpdatedAt       time.Time  `bson:"updated_at,omitempty" json:"updated_at,omitempty"`
}

type MongoDB struct {
	client   *mongo.Client
	db       *mongo.Database
	messages *mongo.Collection
	agents   *mongo.Collection
	tickets  *mongo.Collection
}

// NewMongoDB connects to MongoDB and initializes collections.
func NewMongoDB(ctx context.Context, uri, dbName string) (*MongoDB, error) {
	client, err := mongo.Connect(options.Client().ApplyURI(uri))
	if err != nil {
		return nil, fmt.Errorf("store: failed to connect to MongoDB: %w", err)
	}

	if err := client.Ping(ctx, nil); err != nil {
		return nil, fmt.Errorf("store: failed to ping MongoDB: %w", err)
	}

	db := client.Database(dbName)
	store := &MongoDB{
		client:   client,
		db:       db,
		messages: db.Collection("messages"),
		agents:   db.Collection("support_agents"),
		tickets:  db.Collection("complaint_tickets"),
	}

	log.Printf("[CHAT-STORE] Connected to MongoDB: %s/%s", uri, dbName)
	return store, nil
}

func (s *MongoDB) Close(ctx context.Context) error {
	return s.client.Disconnect(ctx)
}

func (s *MongoDB) DropDatabase(ctx context.Context) error {
	return s.db.Drop(ctx)
}

func (s *MongoDB) ensureIndexes(ctx context.Context) error {
	// Index on (channel, timestamp)
	_, err := s.messages.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{
			{Key: "channel", Value: 1},
			{Key: "timestamp", Value: 1},
		},
	})
	if err != nil {
		return fmt.Errorf("chat_messages channel-timestamp index: %w", err)
	}

	// Index on support_agents.status
	_, err = s.agents.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{
			{Key: "status", Value: 1},
		},
	})
	if err != nil {
		return fmt.Errorf("support_agents status index: %w", err)
	}

	// Unique index on support_agents.token
	_, err = s.agents.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{
			{Key: "token", Value: 1},
		},
		Options: options.Index().SetUnique(true),
	})
	if err != nil {
		return fmt.Errorf("support_agents token index: %w", err)
	}

	// Index on complaint_tickets.customer_id
	_, err = s.tickets.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{
			{Key: "customer_id", Value: 1},
		},
	})
	if err != nil {
		return fmt.Errorf("complaint_tickets customer_id index: %w", err)
	}

	// Index on complaint_tickets.assigned_agent_id
	_, err = s.tickets.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{
			{Key: "assigned_agent_id", Value: 1},
		},
	})
	if err != nil {
		return fmt.Errorf("complaint_tickets assigned_agent_id index: %w", err)
	}

	return nil
}

// PersistMessage stores a chat message in MongoDB
func (s *MongoDB) PersistMessage(ctx context.Context, msg *chat.Message) error {
	msgUUID, err := jwtutil.GenerateUUID()
	if err != nil {
		b := make([]byte, 8)
		_, _ = rand.Read(b)
		msgUUID = fmt.Sprintf("%d-%s", time.Now().UnixNano(), hex.EncodeToString(b))
	}

	doc := bson.M{
		"_id":             fmt.Sprintf("msg-%s", msgUUID),
		"channel":         msg.Channel,
		"sender_id":       msg.SenderID,
		"sender_username": msg.SenderUsername,
		"content":         msg.Content,
		"type":            msg.Type,
		"timestamp":       time.Now().UTC(),
	}

	_, err = s.messages.InsertOne(ctx, doc)
	if err != nil {
		return fmt.Errorf("store: failed to insert message: %w", err)
	}
	return nil
}

// GetHistory returns the most recent persisted messages for a channel, sorted oldest-to-newest
func (s *MongoDB) GetHistory(ctx context.Context, channel string, limit int64) ([]chat.Message, error) {
	if limit <= 0 {
		limit = 50
	}

	// First find the most recent messages, sorted by timestamp descending
	opts := options.Find().
		SetSort(bson.D{{Key: "timestamp", Value: -1}}).
		SetLimit(limit)

	cursor, err := s.messages.Find(ctx, bson.M{"channel": channel}, opts)
	if err != nil {
		return nil, fmt.Errorf("store: failed to find messages: %w", err)
	}
	defer cursor.Close(ctx)

	var dbMsgs []struct {
		Channel        string `bson:"channel"`
		SenderID       string `bson:"sender_id"`
		SenderUsername string `bson:"sender_username"`
		Content        string `bson:"content"`
		Type           string `bson:"type"`
	}
	if err := cursor.All(ctx, &dbMsgs); err != nil {
		return nil, fmt.Errorf("store: failed to decode messages: %w", err)
	}

	// Reverse them to be sorted oldest-to-newest
	n := len(dbMsgs)
	res := make([]chat.Message, n)
	for i, m := range dbMsgs {
		res[n-1-i] = chat.Message{
			Channel:        m.Channel,
			SenderID:       m.SenderID,
			SenderUsername: m.SenderUsername,
			Content:        m.Content,
			Type:           m.Type,
		}
	}

	return res, nil
}

// hashAgentToken returns the SHA-256 hex digest used for bearer-token storage
// at rest. Raw tokens are never persisted; lookups hash before querying, with
// a plaintext fallback for rows written before this hardening.
func hashAgentToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

// AddSupportAgent inserts a new support agent. The token is stored as a
// SHA-256 digest, never plaintext.
func (s *MongoDB) AddSupportAgent(ctx context.Context, agent *SupportAgent) error {
	agent.Token = hashAgentToken(agent.Token)
	_, err := s.agents.InsertOne(ctx, agent)
	return err
}

// GetAgent retrieves an agent by ID.
func (s *MongoDB) GetAgent(ctx context.Context, agentID string) (*SupportAgent, error) {
	var agent SupportAgent
	err := s.agents.FindOne(ctx, bson.M{"_id": agentID}).Decode(&agent)
	if err != nil {
		return nil, err
	}
	return &agent, nil
}

// GetAgentByToken retrieves an agent by their unique token, hashing the
// presented credential first with a legacy plaintext fallback (migration
// window for pre-hardening rows).
func (s *MongoDB) GetAgentByToken(ctx context.Context, token string) (*SupportAgent, error) {
	var agent SupportAgent
	err := s.agents.FindOne(ctx, bson.M{"token": hashAgentToken(token)}).Decode(&agent)
	if err != nil {
		err = s.agents.FindOne(ctx, bson.M{"token": token}).Decode(&agent)
	}
	if err != nil {
		return nil, err
	}
	return &agent, nil
}

// GetTicket retrieves a ticket by ID.
func (s *MongoDB) GetTicket(ctx context.Context, ticketID string) (*ComplaintTicket, error) {
	var ticket ComplaintTicket
	err := s.tickets.FindOne(ctx, bson.M{"_id": ticketID}).Decode(&ticket)
	if err != nil {
		return nil, err
	}
	return &ticket, nil
}

// CreateTicketAndAssign attempts to atomically assign an available support agent to a new ticket.
// If no agent is available, the ticket is created with "pending" status (queued).
func (s *MongoDB) CreateTicketAndAssign(ctx context.Context, customerID, contextID string) (*ComplaintTicket, error) {
	tktUUID, err := jwtutil.GenerateUUID()
	if err != nil {
		b := make([]byte, 8)
		_, _ = rand.Read(b)
		tktUUID = fmt.Sprintf("%d-%s", time.Now().UnixNano(), hex.EncodeToString(b))
	}
	ticket := &ComplaintTicket{
		ID:         fmt.Sprintf("tkt-%s", tktUUID),
		CustomerID: customerID,
		ContextID:  contextID,
		Status:     "pending",
		CreatedAt:  time.Now().UTC(),
	}

	// Atomic Compare-And-Swap (CAS): FindOneAndUpdate claims an available support agent single-document atomically.
	filter := bson.M{"status": "available"}
	update := bson.M{
		"$set": bson.M{
			"status":            "busy",
			"current_ticket_id": ticket.ID,
		},
	}
	var agent SupportAgent
	err = s.agents.FindOneAndUpdate(ctx, filter, update, options.FindOneAndUpdate().SetReturnDocument(options.After)).Decode(&agent)
	if err == nil {
		ticket.Status = "assigned"
		ticket.AssignedAgentID = agent.ID
	} else if err != mongo.ErrNoDocuments {
		return nil, err
	}

	_, err = s.tickets.InsertOne(ctx, ticket)
	if err != nil {
		if ticket.Status == "assigned" {
			// Rollback agent assignment
			_, _ = s.agents.UpdateOne(ctx, bson.M{"_id": agent.ID}, bson.M{"$set": bson.M{"status": "available", "current_ticket_id": ""}})
		}
		return nil, fmt.Errorf("failed to insert ticket: %w", err)
	}

	return ticket, nil
}

// ResolveTicket marks a ticket as resolved and sets the assigned agent to available.
func (s *MongoDB) ResolveTicket(ctx context.Context, ticketID string) error {
	var ticket ComplaintTicket
	err := s.tickets.FindOne(ctx, bson.M{"_id": ticketID}).Decode(&ticket)
	if err != nil {
		return err
	}

	_, err = s.tickets.UpdateOne(ctx, bson.M{"_id": ticketID}, bson.M{"$set": bson.M{"status": "resolved"}})
	if err != nil {
		return err
	}

	if ticket.AssignedAgentID != "" {
		_, _ = s.agents.UpdateOne(ctx,
			bson.M{"_id": ticket.AssignedAgentID, "current_ticket_id": ticketID},
			bson.M{"$set": bson.M{"status": "available", "current_ticket_id": ""}},
		)
	}

	return nil
}

// ListTickets returns paginated complaint tickets, optionally filtered by status and search (ADR-0023).
func (s *MongoDB) ListTickets(ctx context.Context, status, search string, page, limit int64) ([]ComplaintTicket, int64, error) {
	if page < 1 {
		page = 1
	}
	if limit < 1 || limit > 100 {
		limit = 20
	}
	skip := (page - 1) * limit

	filter := bson.M{}
	if status != "" {
		filter["status"] = status
	}
	if search != "" {
		escaped := regexp.QuoteMeta(search)
		filter["$or"] = []bson.M{
			{"_id": bson.M{"$regex": escaped, "$options": "i"}},
			{"customer_id": bson.M{"$regex": escaped, "$options": "i"}},
			{"context_id": bson.M{"$regex": escaped, "$options": "i"}},
			{"subject": bson.M{"$regex": escaped, "$options": "i"}},
			{"assigned_agent_id": bson.M{"$regex": escaped, "$options": "i"}},
		}
	}

	total, err := s.tickets.CountDocuments(ctx, filter)
	if err != nil {
		return nil, 0, fmt.Errorf("failed to count tickets: %w", err)
	}

	opts := options.Find().
		SetSort(bson.D{{Key: "created_at", Value: -1}}).
		SetSkip(skip).
		SetLimit(limit)

	cursor, err := s.tickets.Find(ctx, filter, opts)
	if err != nil {
		return nil, 0, fmt.Errorf("failed to find tickets: %w", err)
	}
	defer cursor.Close(ctx)

	var tickets []ComplaintTicket
	if err := cursor.All(ctx, &tickets); err != nil {
		return nil, 0, fmt.Errorf("failed to decode tickets: %w", err)
	}
	if tickets == nil {
		tickets = []ComplaintTicket{}
	}
	return tickets, total, nil
}

// ListCustomerTickets returns paginated complaint tickets belonging to a specific customer, sorted newest first.
func (s *MongoDB) ListCustomerTickets(ctx context.Context, customerID string, page, limit int64) ([]ComplaintTicket, int64, error) {
	if customerID == "" {
		return []ComplaintTicket{}, 0, nil
	}
	if page < 1 {
		page = 1
	}
	if limit < 1 || limit > 100 {
		limit = 20
	}
	skip := (page - 1) * limit

	filter := bson.M{"customer_id": customerID}

	total, err := s.tickets.CountDocuments(ctx, filter)
	if err != nil {
		return nil, 0, fmt.Errorf("failed to count customer tickets: %w", err)
	}

	opts := options.Find().
		SetSort(bson.D{{Key: "created_at", Value: -1}}).
		SetSkip(skip).
		SetLimit(limit)

	cursor, err := s.tickets.Find(ctx, filter, opts)
	if err != nil {
		return nil, 0, fmt.Errorf("failed to find customer tickets: %w", err)
	}
	defer cursor.Close(ctx)

	var tickets []ComplaintTicket
	if err := cursor.All(ctx, &tickets); err != nil {
		return nil, 0, fmt.Errorf("failed to decode customer tickets: %w", err)
	}
	if tickets == nil {
		tickets = []ComplaintTicket{}
	}
	return tickets, total, nil
}

// AdminResolveTicket atomically marks a ticket as resolved with mandatory notes and releases agent (ADR-0023).
func (s *MongoDB) AdminResolveTicket(ctx context.Context, ticketID, resolutionNote, reviewerID string) (*ComplaintTicket, error) {
	now := time.Now().UTC()

	// CAS: only tickets not already resolved can be resolved
	filter := bson.M{
		"_id":    ticketID,
		"status": bson.M{"$ne": "resolved"},
	}
	update := bson.M{
		"$set": bson.M{
			"status":          "resolved",
			"resolution_note": resolutionNote,
			"resolved_by":     reviewerID,
			"resolved_at":     now,
			"updated_at":      now,
		},
	}

	opts := options.FindOneAndUpdate().SetReturnDocument(options.After)
	res := s.tickets.FindOneAndUpdate(ctx, filter, update, opts)
	if res.Err() != nil {
		if res.Err() == mongo.ErrNoDocuments {
			var existing ComplaintTicket
			if err := s.tickets.FindOne(ctx, bson.M{"_id": ticketID}).Decode(&existing); err == nil {
				if existing.Status == "resolved" {
					return nil, fmt.Errorf("ticket %s is already resolved", ticketID)
				}
			}
			return nil, fmt.Errorf("ticket %s not found or was concurrently modified", ticketID)
		}
		return nil, fmt.Errorf("failed to resolve ticket: %w", res.Err())
	}

	var updated ComplaintTicket
	if err := res.Decode(&updated); err != nil {
		return nil, fmt.Errorf("failed to decode resolved ticket: %w", err)
	}

	// Release assigned support agent if one was assigned
	if updated.AssignedAgentID != "" {
		_, _ = s.agents.UpdateOne(ctx,
			bson.M{"_id": updated.AssignedAgentID, "current_ticket_id": ticketID},
			bson.M{"$set": bson.M{"status": "available", "current_ticket_id": ""}},
		)
	}

	return &updated, nil
}
