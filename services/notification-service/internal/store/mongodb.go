// Package store provides the MongoDB-backed persistent data store for the notification-service.
package store

import (
	"context"
	"errors"
	"fmt"
	"log"
	"slices"
	"time"

	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
	"go.mongodb.org/mongo-driver/v2/mongo/options"
)

// ErrNotFound is returned when a requested notification does not exist or is not accessible to the user.
var ErrNotFound = errors.New("notification not found")

// Notification represents a persistent notification document.
type Notification struct {
	ID          string    `json:"id" bson:"_id"`
	Type        string    `json:"type" bson:"type"`
	TenantID    string    `json:"tenant_id" bson:"tenant_id"`
	UserID      string    `json:"user_id,omitempty" bson:"user_id,omitempty"`
	UserIDs     []string  `json:"user_ids,omitempty" bson:"user_ids,omitempty"`
	Global      bool      `json:"global" bson:"global"`
	Title       string    `json:"title" bson:"title"`
	Body        string    `json:"body" bson:"body"`
	Roles       []string  `json:"roles,omitempty" bson:"roles,omitempty"`
	Timestamp   time.Time `json:"timestamp" bson:"timestamp"`
	IsRead      bool      `json:"is_read" bson:"-"`
	ReadBy      []string  `json:"-" bson:"read_by,omitempty"`
	DismissedBy []string  `json:"-" bson:"dismissed_by,omitempty"`
	CreatedAt   time.Time `json:"created_at,omitempty" bson:"created_at"`
}

// Store defines persistence operations for notifications.
type Store interface {
	InsertNotification(ctx context.Context, notif *Notification) error
	ListForUser(ctx context.Context, tenantID, userID string, roles []string, limit int, before *time.Time) ([]Notification, error)
	MarkRead(ctx context.Context, tenantID, userID string, roles []string, notificationID string) error
	MarkAllRead(ctx context.Context, tenantID, userID string, roles []string) error
	Delete(ctx context.Context, tenantID, userID string, roles []string, notificationID string) error
	DeleteAll(ctx context.Context, tenantID, userID string, roles []string) error
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

	// TTL index on created_at: expire documents after 30 days (2,592,000 seconds)
	expireAfterSeconds := int32(2592000)
	if _, err := s.notifications.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{
			{Key: "created_at", Value: 1},
		},
		Options: options.Index().SetExpireAfterSeconds(expireAfterSeconds),
	}); err != nil {
		return fmt.Errorf("notifications created_at TTL index: %w", err)
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
	if notif.CreatedAt.IsZero() {
		notif.CreatedAt = time.Now().UTC()
	}
	if notif.ReadBy == nil {
		notif.ReadBy = []string{}
	}
	if notif.DismissedBy == nil {
		notif.DismissedBy = []string{}
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

	if userID != "" {
		andClauses = append(andClauses, bson.M{
			"dismissed_by": bson.M{"$ne": userID},
		})
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

	// Architectural Decision:
	// We compute IsRead in Go after cursor.All (rather than in a MongoDB aggregation $project stage)
	// for three specific reasons:
	// 1. Efficiency & Indexing: Standard Find operations preserve index usage (tenant_user_timestamp
	//    and tenant_roles_timestamp) and cursor streaming without aggregation pipeline overhead.
	// 2. Struct Schema Decoupling: Decoding the raw BSON document into the store.Notification struct
	//    keeps the MongoDB collection schema clean and avoids complex BSON-to-Go expression projections.
	// 3. Simplicity & Safety: Slices lookup (checking if ReadBy contains userID) in Go is in-memory
	//    O(N*R) where R (recipients who marked read) is small, avoiding aggregation expression complexity.
	// We also defensively filter out any notifications where DismissedBy contains userID in case of
	// any query engine edge-cases.
	finalResults := make([]Notification, 0, len(results))
	for _, notif := range results {
		if userID != "" && slices.Contains(notif.DismissedBy, userID) {
			continue
		}
		notif.IsRead = (userID != "" && slices.Contains(notif.ReadBy, userID))
		finalResults = append(finalResults, notif)
	}
	return finalResults, nil
}

func userMutationFilter(tenantID, userID string, roles []string, notificationID string) bson.M {
	tenantFilter := bson.M{
		"$or": []bson.M{
			{"tenant_id": tenantID},
			{"global": true},
		},
	}

	var recipientOr []bson.M
	if userID != "" {
		recipientOr = append(recipientOr, bson.M{"user_id": userID})
		recipientOr = append(recipientOr, bson.M{"user_ids": userID})
	}

	if len(roles) > 0 {
		recipientOr = append(recipientOr, bson.M{"roles": bson.M{"$in": roles}})
	}

	// Broadcast notification with no role restrictions and no specific user target
	recipientOr = append(recipientOr, bson.M{
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

	baseFilter := bson.M{
		"$and": []bson.M{
			tenantFilter,
			{"$or": recipientOr},
		},
	}

	if notificationID != "" {
		baseFilter["_id"] = notificationID
	}

	return baseFilter
}

func isExclusiveRecipient(notif *Notification, userID string) bool {
	if notif.Global || len(notif.Roles) > 0 {
		return false
	}
	if len(notif.UserIDs) > 1 {
		return false
	}
	if len(notif.UserIDs) == 1 && notif.UserIDs[0] != userID {
		return false
	}
	if notif.UserID != "" && notif.UserID != userID {
		return false
	}
	if notif.UserID == "" && len(notif.UserIDs) == 0 {
		return false
	}
	return notif.UserID == userID || (len(notif.UserIDs) == 1 && notif.UserIDs[0] == userID)
}

// MarkRead marks a single notification as read, scoped strictly to the tenant and user.
// Uses $addToSet on read_by so that role-broadcast and multi-recipient notifications
// track read state per-recipient without mutating other recipients' read state.
func (s *MongoDB) MarkRead(ctx context.Context, tenantID, userID string, roles []string, notificationID string) error {
	filter := userMutationFilter(tenantID, userID, roles, notificationID)
	res, err := s.notifications.UpdateOne(ctx, filter, bson.M{"$addToSet": bson.M{"read_by": userID}})
	if err != nil {
		return err
	}
	if res.MatchedCount == 0 {
		return ErrNotFound
	}
	return nil
}

// MarkAllRead marks all matching notifications as read for the user by adding userID to read_by.
func (s *MongoDB) MarkAllRead(ctx context.Context, tenantID, userID string, roles []string) error {
	filter := userMutationFilter(tenantID, userID, roles, "")
	andClauses := filter["$and"].([]bson.M)
	andClauses = append(andClauses, bson.M{
		"read_by":      bson.M{"$ne": userID},
		"dismissed_by": bson.M{"$ne": userID},
	})
	filter["$and"] = andClauses
	_, err := s.notifications.UpdateMany(ctx, filter, bson.M{"$addToSet": bson.M{"read_by": userID}})
	return err
}

// Delete removes a single notification for the user. If the notification is exclusively
// owned by this user (single direct recipient), it is hard-deleted from the store.
// If it is shared/broadcast (targeted to roles, multiple users, or all users),
// the user is added to dismissed_by so other recipients remain unaffected.
func (s *MongoDB) Delete(ctx context.Context, tenantID, userID string, roles []string, notificationID string) error {
	filter := userMutationFilter(tenantID, userID, roles, notificationID)
	var notif Notification
	err := s.notifications.FindOne(ctx, filter).Decode(&notif)
	if err != nil {
		if errors.Is(err, mongo.ErrNoDocuments) {
			return ErrNotFound
		}
		return err
	}

	if isExclusiveRecipient(&notif, userID) {
		res, err := s.notifications.DeleteOne(ctx, bson.M{"_id": notificationID})
		if err != nil {
			return err
		}
		if res.DeletedCount == 0 {
			return ErrNotFound
		}
		return nil
	}

	// Shared / broadcast notification: soft-dismiss for this user
	res, err := s.notifications.UpdateOne(ctx, bson.M{"_id": notificationID}, bson.M{"$addToSet": bson.M{"dismissed_by": userID}})
	if err != nil {
		return err
	}
	if res.MatchedCount == 0 {
		return ErrNotFound
	}
	return nil
}

// DeleteAll removes or dismisses all matching notifications for the user.
// Exclusively owned notifications are hard-deleted, while shared/broadcast
// notifications are soft-dismissed by adding userID to dismissed_by.
func (s *MongoDB) DeleteAll(ctx context.Context, tenantID, userID string, roles []string) error {
	// 1. Hard-delete exclusively owned notifications
	exclusiveFilter := bson.M{
		"$and": []bson.M{
			{"tenant_id": tenantID},
			{"global": false},
			{"$or": []bson.M{
				{"roles": bson.M{"$size": 0}},
				{"roles": bson.M{"$exists": false}},
			}},
			{"user_id": userID},
			{"$or": []bson.M{
				{"user_ids": bson.M{"$size": 0}},
				{"user_ids": bson.M{"$exists": false}},
				{"user_ids": []string{userID}},
			}},
		},
	}
	if _, err := s.notifications.DeleteMany(ctx, exclusiveFilter); err != nil {
		return err
	}

	// 2. Soft-dismiss shared / broadcast notifications for this user
	sharedFilter := userMutationFilter(tenantID, userID, roles, "")
	_, err := s.notifications.UpdateMany(ctx, sharedFilter, bson.M{"$addToSet": bson.M{"dismissed_by": userID}})
	return err
}
