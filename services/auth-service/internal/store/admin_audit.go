package store

import (
	"context"
	"fmt"
	"time"

	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
	"go.mongodb.org/mongo-driver/v2/mongo/options"
)

// adminAuditCollection holds this service's reviewer (admin console) action
// records. Every service keeps its own; auth-service's GET /admin/audit
// merges them over each service's GET /internal/admin-audit (ADMIN-API-FIX).
const adminAuditCollection = "admin_audit"

// AdminAuditRecord is one reviewer mutation or unmasked view.
type AdminAuditRecord struct {
	ID         string    `bson:"_id" json:"id"`
	Source     string    `bson:"source" json:"source"`
	ActorID    string    `bson:"actor_id" json:"actor_id"`
	Action     string    `bson:"action" json:"action"`
	TargetType string    `bson:"target_type" json:"target_type"`
	TargetID   string    `bson:"target_id" json:"target_id"`
	Reason     string    `bson:"reason,omitempty" json:"reason,omitempty"`
	Details    string    `bson:"details,omitempty" json:"details,omitempty"`
	RequestID  string    `bson:"request_id" json:"request_id"`
	CreatedAt  time.Time `bson:"created_at" json:"created_at"`
}

// AdminAuditFilter narrows ListAdminAudit. Empty fields match everything.
type AdminAuditFilter struct {
	ActorID  string
	Action   string
	TargetID string
	From     *time.Time
	To       *time.Time
}

func (s *MongoDB) ensureAdminAuditIndexes(ctx context.Context) error {
	_, err := s.db.Collection(adminAuditCollection).Indexes().CreateMany(ctx, []mongo.IndexModel{
		{Keys: bson.D{{Key: "created_at", Value: -1}}},
		{Keys: bson.D{{Key: "actor_id", Value: 1}, {Key: "created_at", Value: -1}}},
		{Keys: bson.D{{Key: "target_id", Value: 1}, {Key: "created_at", Value: -1}}},
	})
	if err != nil {
		return fmt.Errorf("store: admin_audit indexes: %w", err)
	}
	return nil
}

// AppendAdminAudit inserts one admin audit record.
func (s *MongoDB) AppendAdminAudit(ctx context.Context, rec *AdminAuditRecord) error {
	if _, err := s.db.Collection(adminAuditCollection).InsertOne(ctx, rec); err != nil {
		return fmt.Errorf("store: insert admin audit record: %w", err)
	}
	return nil
}

// ListAdminAudit returns up to limit records matching f, newest first, and
// the total number of matching records.
func (s *MongoDB) ListAdminAudit(ctx context.Context, f AdminAuditFilter, limit int64) ([]AdminAuditRecord, int64, error) {
	filter := bson.M{}
	if f.ActorID != "" {
		filter["actor_id"] = f.ActorID
	}
	if f.Action != "" {
		filter["action"] = f.Action
	}
	if f.TargetID != "" {
		filter["target_id"] = f.TargetID
	}
	if f.From != nil || f.To != nil {
		rng := bson.M{}
		if f.From != nil {
			rng["$gte"] = *f.From
		}
		if f.To != nil {
			rng["$lte"] = *f.To
		}
		filter["created_at"] = rng
	}
	coll := s.db.Collection(adminAuditCollection)
	total, err := coll.CountDocuments(ctx, filter)
	if err != nil {
		return nil, 0, fmt.Errorf("store: count admin audit records: %w", err)
	}
	opts := options.Find().SetSort(bson.D{{Key: "created_at", Value: -1}, {Key: "_id", Value: -1}}).SetLimit(limit)
	cur, err := coll.Find(ctx, filter, opts)
	if err != nil {
		return nil, 0, fmt.Errorf("store: find admin audit records: %w", err)
	}
	records := []AdminAuditRecord{}
	if err := cur.All(ctx, &records); err != nil {
		return nil, 0, fmt.Errorf("store: decode admin audit records: %w", err)
	}
	return records, total, nil
}
