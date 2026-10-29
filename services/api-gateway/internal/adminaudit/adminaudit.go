// Package adminaudit stores the gateway's reviewer (admin console) action
// records in gateway_db.admin_audit. auth-service's GET /admin/audit merges
// them with the other services' records over GET /admin/internal/audit
// (ADMIN-API-FIX). Without MongoDB (local/test) records live in memory.
package adminaudit

import (
	"context"
	"crypto/subtle"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/project/shared/infra/handlerutil"

	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
	"go.mongodb.org/mongo-driver/v2/mongo/options"
)

// ActionVersionUpdate is the gateway's only admin audit action. Names follow
// the one scheme used by every service: "<resource>.<verb>".
const ActionVersionUpdate = "version.update"

// MaxLimit caps how many records one List call returns.
const MaxLimit = 1000

// Record is one reviewer mutation. Same JSON shape in every service.
type Record struct {
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

// Filter narrows List. Empty fields match everything.
type Filter struct {
	ActorID  string
	Action   string
	TargetID string
	From     *time.Time
	To       *time.Time
}

// Store persists records in MongoDB, or in memory when coll is nil.
type Store struct {
	coll *mongo.Collection
	mu   sync.Mutex
	mem  []Record
}

// NewStore returns a MongoDB-backed store (client non-nil) or an in-memory one.
func NewStore(client *mongo.Client, dbName string) *Store {
	if client == nil {
		return &Store{}
	}
	return &Store{coll: client.Database(dbName).Collection("admin_audit")}
}

// Append stores one record.
func (s *Store) Append(ctx context.Context, rec Record) error {
	if s.coll == nil {
		s.mu.Lock()
		s.mem = append(s.mem, rec)
		s.mu.Unlock()
		return nil
	}
	if _, err := s.coll.InsertOne(ctx, rec); err != nil {
		return fmt.Errorf("adminaudit: insert: %w", err)
	}
	return nil
}

func (f Filter) matches(r Record) bool {
	return (f.ActorID == "" || r.ActorID == f.ActorID) &&
		(f.Action == "" || r.Action == f.Action) &&
		(f.TargetID == "" || r.TargetID == f.TargetID) &&
		(f.From == nil || !r.CreatedAt.Before(*f.From)) &&
		(f.To == nil || !r.CreatedAt.After(*f.To))
}

// List returns up to limit matching records, newest first, and the total
// number of matches.
func (s *Store) List(ctx context.Context, f Filter, limit int64) ([]Record, int64, error) {
	if s.coll == nil {
		s.mu.Lock()
		defer s.mu.Unlock()
		out := []Record{}
		for i := len(s.mem) - 1; i >= 0; i-- {
			if f.matches(s.mem[i]) {
				out = append(out, s.mem[i])
			}
		}
		total := int64(len(out))
		if int64(len(out)) > limit {
			out = out[:limit]
		}
		return out, total, nil
	}
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
	total, err := s.coll.CountDocuments(ctx, filter)
	if err != nil {
		return nil, 0, fmt.Errorf("adminaudit: count: %w", err)
	}
	cur, err := s.coll.Find(ctx, filter, options.Find().SetSort(bson.D{{Key: "created_at", Value: -1}, {Key: "_id", Value: -1}}).SetLimit(limit))
	if err != nil {
		return nil, 0, fmt.Errorf("adminaudit: find: %w", err)
	}
	out := []Record{}
	if err := cur.All(ctx, &out); err != nil {
		return nil, 0, fmt.Errorf("adminaudit: decode: %w", err)
	}
	return out, total, nil
}

// ListHandler serves the gateway's records to auth-service's merged
// GET /admin/audit. X-Internal-Token only; the edge answers 404 for /admin/*.
// GET /admin/internal/audit?actor_id=&action=&target_id=&from=&to=&limit=
func ListHandler(internalToken string, s *Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			handlerutil.WriteJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed, use GET"})
			return
		}
		if internalToken == "" || subtle.ConstantTimeCompare([]byte(r.Header.Get("X-Internal-Token")), []byte(internalToken)) != 1 {
			handlerutil.WriteJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
			return
		}
		q := r.URL.Query()
		f := Filter{
			ActorID:  strings.TrimSpace(q.Get("actor_id")),
			Action:   strings.TrimSpace(q.Get("action")),
			TargetID: strings.TrimSpace(q.Get("target_id")),
		}
		for key, dst := range map[string]**time.Time{"from": &f.From, "to": &f.To} {
			if v := strings.TrimSpace(q.Get(key)); v != "" {
				t, err := time.Parse(time.RFC3339Nano, v)
				if err != nil {
					handlerutil.WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid filter: from/to must be RFC 3339, limit 1-1000"})
					return
				}
				t = t.UTC()
				*dst = &t
			}
		}
		limit := int64(100)
		if v := q.Get("limit"); v != "" {
			l, err := strconv.ParseInt(v, 10, 64)
			if err != nil || l < 1 || l > MaxLimit {
				handlerutil.WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid filter: from/to must be RFC 3339, limit 1-1000"})
				return
			}
			limit = l
		}
		records, total, err := s.List(r.Context(), f, limit)
		if err != nil {
			handlerutil.WriteSafeError(w, r, http.StatusInternalServerError, handlerutil.ErrCodeInternal, "failed to query admin audit records", err)
			return
		}
		handlerutil.WriteJSON(w, http.StatusOK, map[string]any{"entries": records, "total": total})
	}
}
