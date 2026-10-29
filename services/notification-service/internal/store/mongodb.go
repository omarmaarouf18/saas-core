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

	"github.com/project/shared/infra/redact"
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
	JobID     string    `json:"job_id,omitempty" bson:"job_id,omitempty"`
	Global    bool      `json:"global" bson:"global"`
	Title     string    `json:"title" bson:"title"`
	Body      string    `json:"body" bson:"body"`
	Roles     []string  `json:"roles,omitempty" bson:"roles,omitempty"`
	Timestamp time.Time `json:"timestamp" bson:"timestamp"`
	// Params are the sender's template parameters (PUSH-L10N), kept so
	// the history can be rendered in the app's current language.
	Params      map[string]string `json:"params,omitempty" bson:"params,omitempty"`
	IsRead      bool              `json:"is_read" bson:"-"`
	ReadBy      []string          `json:"-" bson:"read_by,omitempty"`
	DismissedBy []string          `json:"-" bson:"dismissed_by,omitempty"`
	CreatedAt   time.Time         `json:"created_at,omitempty" bson:"created_at"`
}

// AdminNotificationSendStatus represents lifecycle states of an admin announcement send job.
type AdminNotificationSendStatus string

const (
	SendStatusQueued  AdminNotificationSendStatus = "queued"
	SendStatusSending AdminNotificationSendStatus = "sending"
	SendStatusDone    AdminNotificationSendStatus = "done"
	SendStatusFailed  AdminNotificationSendStatus = "failed"
)

// AdminAudience captures targeting parameters for admin announcements.
type AdminAudience struct {
	Kind     string `json:"kind" bson:"kind"` // "user", "role", "tenant", "everyone"
	UserID   string `json:"user_id,omitempty" bson:"user_id,omitempty"`
	Email    string `json:"email,omitempty" bson:"email,omitempty"`
	Phone    string `json:"phone,omitempty" bson:"phone,omitempty"`
	Role     string `json:"role,omitempty" bson:"role,omitempty"`
	TenantID string `json:"tenant_id,omitempty" bson:"tenant_id,omitempty"`
}

// AdminNotificationSend records an admin broadcast job and its delivery status.
type AdminNotificationSend struct {
	ID             string                      `json:"id" bson:"_id"`
	IdempotencyKey string                      `json:"idempotency_key,omitempty" bson:"idempotency_key,omitempty"`
	ReviewerID     string                      `json:"reviewer_id" bson:"reviewer_id"`
	ReviewerName   string                      `json:"reviewer_name,omitempty" bson:"reviewer_name,omitempty"`
	Reason         string                      `json:"reason" bson:"reason"`
	Audience       AdminAudience               `json:"audience" bson:"audience"`
	TitleAR        string                      `json:"title_ar" bson:"title_ar"`
	TitleEN        string                      `json:"title_en" bson:"title_en"`
	BodyAR         string                      `json:"body_ar" bson:"body_ar"`
	BodyEN         string                      `json:"body_en" bson:"body_en"`
	DeepLink       string                      `json:"deep_link,omitempty" bson:"deep_link,omitempty"`
	Status         AdminNotificationSendStatus `json:"status" bson:"status"`
	AudienceSize   int                         `json:"audience_size" bson:"audience_size"`
	SentCount      int                         `json:"sent_count" bson:"sent_count"`
	FailedCount    int                         `json:"failed_count" bson:"failed_count"`
	ErrorMessage   string                      `json:"error_message,omitempty" bson:"error_message,omitempty"`
	CreatedAt      time.Time                   `json:"created_at" bson:"created_at"`
	UpdatedAt      time.Time                   `json:"updated_at" bson:"updated_at"`
	CompletedAt    *time.Time                  `json:"completed_at,omitempty" bson:"completed_at,omitempty"`
}

// Store defines persistence operations for notifications.
type Store interface {
	InsertNotification(ctx context.Context, notif *Notification) error
	ListForUser(ctx context.Context, tenantID, userID string, roles []string, limit int, before *time.Time) ([]Notification, error)
	ListByJobID(ctx context.Context, jobID string, limit int) ([]Notification, error)
	MarkRead(ctx context.Context, tenantID, userID string, roles []string, notificationID string) error
	MarkAllRead(ctx context.Context, tenantID, userID string, roles []string) error
	Delete(ctx context.Context, tenantID, userID string, roles []string, notificationID string) error
	DeleteAll(ctx context.Context, tenantID, userID string, roles []string) error
	CreateAdminNotificationSend(ctx context.Context, send *AdminNotificationSend) error
	GetAdminNotificationSendByID(ctx context.Context, id string) (*AdminNotificationSend, error)
	GetAdminNotificationSendByIdempotencyKey(ctx context.Context, key string) (*AdminNotificationSend, error)
	ListAdminNotificationSends(ctx context.Context, page, limit int) ([]AdminNotificationSend, int, error)
	UpdateAdminNotificationSendProgress(ctx context.Context, id string, status AdminNotificationSendStatus, sentCount, failedCount int, errMsg string) error
	AppendAdminAudit(ctx context.Context, rec *AdminAuditRecord) error
	ListAdminAudit(ctx context.Context, f AdminAuditFilter, limit int64) ([]AdminAuditRecord, int64, error)
	Close(ctx context.Context) error
}

// MongoDB implements Store backed by a MongoDB collection.
type MongoDB struct {
	client        *mongo.Client
	db            *mongo.Database
	notifications *mongo.Collection
	adminSends    *mongo.Collection
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
		adminSends:    db.Collection("admin_notification_sends"),
	}

	if err := s.ensureIndexes(ctx); err != nil {
		return nil, err
	}
	if err := s.ensureAdminAuditIndexes(ctx); err != nil {
		return nil, err
	}

	log.Printf("[NOTIF-STORE] Connected to MongoDB: %s/%s", redact.RedactURI(uri), dbName)
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

	// Index on created_at desc for adminSends
	if _, err := s.adminSends.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{{Key: "created_at", Value: -1}},
	}); err != nil {
		return fmt.Errorf("admin_notification_sends created_at index: %w", err)
	}

	// Partial unique index on idempotency_key
	if _, err := s.adminSends.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{{Key: "idempotency_key", Value: 1}},
		Options: options.Index().SetUnique(true).SetPartialFilterExpression(bson.M{
			"idempotency_key": bson.M{"$type": "string", "$gt": ""},
		}),
	}); err != nil {
		return fmt.Errorf("admin_notification_sends idempotency_key index: %w", err)
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
		orClauses = append(orClauses, bson.M{
			"roles": bson.M{"$in": roles},
			"$or": []bson.M{
				{"user_id": ""},
				{"user_id": bson.M{"$exists": false}},
			},
			"$and": []bson.M{
				{"$or": []bson.M{
					{"user_ids": bson.M{"$size": 0}},
					{"user_ids": bson.M{"$exists": false}},
				}},
			},
		})
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
		recipientOr = append(recipientOr, bson.M{
			"roles": bson.M{"$in": roles},
			"$or": []bson.M{
				{"user_id": ""},
				{"user_id": bson.M{"$exists": false}},
			},
			"$and": []bson.M{
				{"$or": []bson.M{
					{"user_ids": bson.M{"$size": 0}},
					{"user_ids": bson.M{"$exists": false}},
				}},
			},
		})
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

// ListByJobID returns notifications associated with a given job ID.
func (s *MongoDB) ListByJobID(ctx context.Context, jobID string, limit int) ([]Notification, error) {
	if s == nil || s.notifications == nil || jobID == "" {
		return []Notification{}, nil
	}
	if limit <= 0 || limit > 50 {
		limit = 50
	}
	opts := options.Find().SetSort(bson.D{{Key: "timestamp", Value: 1}}).SetLimit(int64(limit))
	cursor, err := s.notifications.Find(ctx, bson.M{"job_id": jobID}, opts)
	if err != nil {
		return nil, err
	}
	defer cursor.Close(ctx)

	var items []Notification
	if err := cursor.All(ctx, &items); err != nil {
		return nil, err
	}
	if items == nil {
		items = []Notification{}
	}
	return items, nil
}

// CreateAdminNotificationSend persists a new admin broadcast send job.
func (s *MongoDB) CreateAdminNotificationSend(ctx context.Context, send *AdminNotificationSend) error {
	if s == nil || s.adminSends == nil || send == nil {
		return errors.New("invalid store or send job")
	}
	if send.CreatedAt.IsZero() {
		send.CreatedAt = time.Now().UTC()
	}
	send.UpdatedAt = send.CreatedAt
	_, err := s.adminSends.InsertOne(ctx, send)
	return err
}

// GetAdminNotificationSendByID fetches an admin send job by ID.
func (s *MongoDB) GetAdminNotificationSendByID(ctx context.Context, id string) (*AdminNotificationSend, error) {
	if s == nil || s.adminSends == nil || id == "" {
		return nil, ErrNotFound
	}
	var send AdminNotificationSend
	err := s.adminSends.FindOne(ctx, bson.M{"_id": id}).Decode(&send)
	if err != nil {
		if errors.Is(err, mongo.ErrNoDocuments) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	return &send, nil
}

// GetAdminNotificationSendByIdempotencyKey fetches an existing send job by idempotency key.
func (s *MongoDB) GetAdminNotificationSendByIdempotencyKey(ctx context.Context, key string) (*AdminNotificationSend, error) {
	if s == nil || s.adminSends == nil || key == "" {
		return nil, nil
	}
	var send AdminNotificationSend
	err := s.adminSends.FindOne(ctx, bson.M{"idempotency_key": key}).Decode(&send)
	if err != nil {
		if errors.Is(err, mongo.ErrNoDocuments) {
			return nil, nil
		}
		return nil, err
	}
	return &send, nil
}

// ListAdminNotificationSends lists send jobs sorted newest first with pagination.
func (s *MongoDB) ListAdminNotificationSends(ctx context.Context, page, limit int) ([]AdminNotificationSend, int, error) {
	if s == nil || s.adminSends == nil {
		return []AdminNotificationSend{}, 0, nil
	}
	if page < 1 {
		page = 1
	}
	if limit <= 0 || limit > 100 {
		limit = 20
	}

	total, err := s.adminSends.CountDocuments(ctx, bson.M{})
	if err != nil {
		return nil, 0, err
	}

	opts := options.Find().
		SetSort(bson.D{{Key: "created_at", Value: -1}}).
		SetSkip(int64((page - 1) * limit)).
		SetLimit(int64(limit))

	cursor, err := s.adminSends.Find(ctx, bson.M{}, opts)
	if err != nil {
		return nil, 0, err
	}
	defer cursor.Close(ctx)

	var items []AdminNotificationSend
	if err := cursor.All(ctx, &items); err != nil {
		return nil, 0, err
	}
	if items == nil {
		items = []AdminNotificationSend{}
	}
	return items, int(total), nil
}

// UpdateAdminNotificationSendProgress updates status, counters and completion timestamp.
func (s *MongoDB) UpdateAdminNotificationSendProgress(ctx context.Context, id string, status AdminNotificationSendStatus, sentCount, failedCount int, errMsg string) error {
	if s == nil || s.adminSends == nil || id == "" {
		return errors.New("invalid store or id")
	}

	now := time.Now().UTC()
	update := bson.M{
		"status":       status,
		"sent_count":   sentCount,
		"failed_count": failedCount,
		"updated_at":   now,
	}
	if errMsg != "" {
		update["error_message"] = errMsg
	}
	if status == SendStatusDone || status == SendStatusFailed {
		update["completed_at"] = now
	}

	_, err := s.adminSends.UpdateOne(ctx, bson.M{"_id": id}, bson.M{"$set": update})
	return err
}
