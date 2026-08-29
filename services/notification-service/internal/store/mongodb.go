// Package store provides the MongoDB-backed persistent data store for the notification-service.
package store

import (
	"context"
	"errors"
	"fmt"
	"log"
	"time"

	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
	"go.mongodb.org/mongo-driver/v2/mongo/options"
)

// ErrNotFound is returned when a requested notification does not exist or is not accessible to the user.
var ErrNotFound = errors.New("notification not found")

// Notification represents a persistent notification document.
type Notification struct {
	ID        string    `json:"id" bson:"_id"`
	Type      string    `json:"type" bson:"type"`
	TenantID  string    `json:"tenant_id" bson:"tenant_id"`
	UserID    string    `json:"user_id,omitempty" bson:"user_id,omitempty"`
	UserIDs   []string  `json:"user_ids,omitempty" bson:"user_ids,omitempty"`
	Global    bool      `json:"global" bson:"global"`
	Title     string    `json:"title" bson:"title"`
	Body      string    `json:"body" bson:"body"`
	Roles     []string  `json:"roles,omitempty" bson:"roles,omitempty"`
	Timestamp time.Time `json:"timestamp" bson:"timestamp"`
	IsRead    bool      `json:"is_read" bson:"is_read"`
}

// Store defines persistence operations for notifications.
type Store interface {
	InsertNotification(ctx context.Context, notif *Notification) error
	ListForUser(ctx context.Context, tenantID, userID string, roles []string, limit int, before *time.Time) ([]Notification, error)
	MarkRead(ctx context.Context, tenantID, userID, notificationID string) error
	MarkAllRead(ctx context.Context, tenantID, userID string) error
	Delete(ctx context.Context, tenantID, userID, notificationID string) error
	DeleteAll(ctx context.Context, tenantID, userID string) error
	Close(ctx context.Context) error
}

// MongoDB implements Store backed by a MongoDB collection.
type MongoDB struct {
	client        *mongo.Client
	db            *mongo.Database
	notifications *mongo.Collection
}

// NewMongoDB connects to MongoDB and ensures indexes.
func NewMongoDB(ctx context.Context, uri, dbName string) (*MongoDB, error) {
	client, err := mongo.Connect(options.Client().ApplyURI(uri))
	if err != nil {
		return nil, fmt.Errorf("store: mongo connect: %w", err)
	}
	pingCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	if err := client.Ping(pingCtx, nil); err != nil {
		return nil, fmt.Errorf("store: mongo ping: %w", err)
	}

	db := client.Database(dbName)
	s := &MongoDB{
		client:        client,
		db:            db,
		notifications: db.Collection("notifications"),
	}

	if err := s.ensureIndexes(ctx); err != nil {
		return nil, err
	}

	log.Printf("[NOTIF-STORE] Connected to MongoDB: %s/%s", uri, dbName)
	return s, nil
}

func (s *MongoDB) Close(ctx context.Context) error {
	return s.client.Disconnect(ctx)
}

func (s *MongoDB) DropDatabase(ctx context.Context) error {
	return s.db.Drop(ctx)
}

func (s *MongoDB) ensureIndexes(ctx context.Context) error {
	// Compound index on (tenant_id, user_id, timestamp desc)
	if _, err := s.notifications.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{
			{Key: "tenant_id", Value: 1},
			{Key: "user_id", Value: 1},
			{Key: "timestamp", Value: -1},
		},
	}); err != nil {
		return fmt.Errorf("notifications tenant_user_timestamp index: %w", err)
	}

	// Compound index on (tenant_id, roles, timestamp desc)
	if _, err := s.notifications.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{
			{Key: "tenant_id", Value: 1},
			{Key: "roles", Value: 1},
			{Key: "timestamp", Value: -1},
		},
	}); err != nil {
		return fmt.Errorf("notifications tenant_roles_timestamp index: %w", err)
	}

	return nil
}

// InsertNotification stores a notification.
func (s *MongoDB) InsertNotification(ctx context.Context, notif *Notification) error {
	if notif == nil {
		return errors.New("notification cannot be nil")
	}
	if notif.ID == "" {
		notif.ID = fmt.Sprintf("notif-%d", time.Now().UnixNano())
	}
	if notif.Timestamp.IsZero() {
		notif.Timestamp = time.Now().UTC()
	}
	_, err := s.notifications.InsertOne(ctx, notif)
	return err
}

// ListForUser retrieves paginated notifications targeted directly to userID or to any of roles within tenantID.
func (s *MongoDB) ListForUser(ctx context.Context, tenantID, userID string, roles []string, limit int, before *time.Time) ([]Notification, error) {
	if limit <= 0 {
		limit = 30
	} else if limit > 100 {
		limit = 100
	}

	tenantFilter := bson.M{
		"$or": []bson.M{
			{"tenant_id": tenantID},
			{"global": true},
		},
	}

	var orClauses []bson.M
	if userID != "" {
		orClauses = append(orClauses, bson.M{"user_id": userID})
		orClauses = append(orClauses, bson.M{"user_ids": userID})
	}

	if len(roles) > 0 {
		orClauses = append(orClauses, bson.M{"roles": bson.M{"$in": roles}})
	}

	// Broadcast notification with no role restrictions and no specific user target
	orClauses = append(orClauses, bson.M{
		"$and": []bson.M{
			{"$or": []bson.M{
				{"user_id": ""},
				{"user_id": bson.M{"$exists": false}},
			}},
			{"$or": []bson.M{
				{"user_ids": bson.M{"$size": 0}},
				{"user_ids": bson.M{"$exists": false}},
			}},
			{"$or": []bson.M{
				{"roles": bson.M{"$size": 0}},
				{"roles": bson.M{"$exists": false}},
			}},
		},
	})

	andClauses := []bson.M{
		tenantFilter,
		{"$or": orClauses},
	}

	if before != nil && !before.IsZero() {
		andClauses = append(andClauses, bson.M{
			"timestamp": bson.M{"$lt": *before},
		})
	}

	filter := bson.M{"$and": andClauses}

	findOpts := options.Find().
		SetSort(bson.D{{Key: "timestamp", Value: -1}}).
		SetLimit(int64(limit))

	cursor, err := s.notifications.Find(ctx, filter, findOpts)
	if err != nil {
		return nil, fmt.Errorf("list notifications: %w", err)
	}
	defer cursor.Close(ctx)

	var results []Notification
	if err := cursor.All(ctx, &results); err != nil {
		return nil, fmt.Errorf("decode notifications: %w", err)
	}
	if results == nil {
		results = []Notification{}
	}
	return results, nil
}

func userMutationFilter(tenantID, userID, notificationID string) bson.M {
	baseFilter := bson.M{
		"$and": []bson.M{
			{"$or": []bson.M{
				{"tenant_id": tenantID},
				{"global": true},
			}},
			{"$or": []bson.M{
				{"user_id": userID},
				{"user_ids": userID},
				{"$and": []bson.M{
					{"$or": []bson.M{
						{"user_id": ""},
						{"user_id": bson.M{"$exists": false}},
					}},
					{"$or": []bson.M{
						{"user_ids": bson.M{"$size": 0}},
						{"user_ids": bson.M{"$exists": false}},
					}},
				}},
			}},
		},
	}

	if notificationID != "" {
		baseFilter["_id"] = notificationID
	}

	return baseFilter
}

// MarkRead marks a single notification as read, scoped strictly to the tenant and user.
func (s *MongoDB) MarkRead(ctx context.Context, tenantID, userID, notificationID string) error {
	filter := userMutationFilter(tenantID, userID, notificationID)
	res, err := s.notifications.UpdateOne(ctx, filter, bson.M{"$set": bson.M{"is_read": true}})
	if err != nil {
		return err
	}
	if res.MatchedCount == 0 {
		return ErrNotFound
	}
	return nil
}

// MarkAllRead marks all matching notifications as read for the user.
func (s *MongoDB) MarkAllRead(ctx context.Context, tenantID, userID string) error {
	filter := userMutationFilter(tenantID, userID, "")
	filter["$and"] = append(filter["$and"].([]bson.M), bson.M{"is_read": false})
	_, err := s.notifications.UpdateMany(ctx, filter, bson.M{"$set": bson.M{"is_read": true}})
	return err
}

// Delete removes a single notification, scoped strictly to the tenant and user.
func (s *MongoDB) Delete(ctx context.Context, tenantID, userID, notificationID string) error {
	filter := userMutationFilter(tenantID, userID, notificationID)
	res, err := s.notifications.DeleteOne(ctx, filter)
	if err != nil {
		return err
	}
	if res.DeletedCount == 0 {
		return ErrNotFound
	}
	return nil
}

// DeleteAll clears all matching notifications for the user.
func (s *MongoDB) DeleteAll(ctx context.Context, tenantID, userID string) error {
	filter := userMutationFilter(tenantID, userID, "")
	_, err := s.notifications.DeleteMany(ctx, filter)
	return err
}
