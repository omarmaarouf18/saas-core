package store

import (
	"context"
	"fmt"
	"log"
	"time"

	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
	"go.mongodb.org/mongo-driver/v2/mongo/options"

	"github.com/project/chat-service/internal/chat"
)

type SupportAgent struct {
	ID              string `bson:"_id" json:"agent_id"`
	Status          string `bson:"status" json:"status"` // "available", "busy", "offline"
	Token           string `bson:"token" json:"token"`
	CurrentTicketID string `bson:"current_ticket_id,omitempty" json:"current_ticket_id,omitempty"`
}

type ComplaintTicket struct {
	ID              string    `bson:"_id" json:"ticket_id"`
	CustomerID      string    `bson:"customer_id" json:"customer_id"`
	ContextID       string    `bson:"context_id" json:"context_id"` // job_id or owner_id/employee_id context
	Status          string    `bson:"status" json:"status"`         // "pending", "assigned", "resolved", "closed"
	AssignedAgentID string    `bson:"assigned_agent_id" json:"assigned_agent_id"`
	CreatedAt       time.Time `bson:"created_at" json:"created_at"`
	AssignedAt      time.Time `bson:"assigned_at,omitempty" json:"assigned_at,omitempty"`
}

type MongoDB struct {
	client   *mongo.Client
	db       *mongo.Database
	messages *mongo.Collection
	tickets  *mongo.Collection
	agents   *mongo.Collection
}

func NewMongoDB(ctx context.Context, uri, dbName string) (*MongoDB, error) {
	client, err := mongo.Connect(options.Client().ApplyURI(uri))
	if err != nil {
		return nil, fmt.Errorf("store: failed to connect to MongoDB: %w", err)
	}

	pingCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	if err := client.Ping(pingCtx, nil); err != nil {
		return nil, fmt.Errorf("store: MongoDB ping failed: %w", err)
	}

	db := client.Database(dbName)
	s := &MongoDB{
		client:   client,
		db:       db,
		messages: db.Collection("chat_messages"),
		tickets:  db.Collection("complaint_tickets"),
		agents:   db.Collection("support_agents"),
	}

	if err := s.ensureIndexes(ctx); err != nil {
		return nil, fmt.Errorf("store: failed to create indexes: %w", err)
	}

	log.Printf("[CHAT-STORE] Connected to MongoDB: %s/%s", uri, dbName)
	return s, nil
}

func (s *MongoDB) Close(ctx context.Context) error {
	return s.client.Disconnect(ctx)
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
	doc := bson.M{
		"_id":       fmt.Sprintf("msg-%d", time.Now().UnixNano()),
		"channel":   msg.Channel,
		"sender_id": msg.SenderID,
		"content":   msg.Content,
		"type":      msg.Type,
		"timestamp": time.Now().UTC(),
	}

	_, err := s.messages.InsertOne(ctx, doc)
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
		Channel  string `bson:"channel"`
		SenderID string `bson:"sender_id"`
		Content  string `bson:"content"`
		Type     string `bson:"type"`
	}
	if err := cursor.All(ctx, &dbMsgs); err != nil {
		return nil, fmt.Errorf("store: failed to decode messages: %w", err)
	}

	// Reverse them to be sorted oldest-to-newest
	n := len(dbMsgs)
	res := make([]chat.Message, n)
	for i, m := range dbMsgs {
		res[n-1-i] = chat.Message{
			Channel:  m.Channel,
			SenderID: m.SenderID,
			Content:  m.Content,
			Type:     m.Type,
		}
	}

	return res, nil
}
