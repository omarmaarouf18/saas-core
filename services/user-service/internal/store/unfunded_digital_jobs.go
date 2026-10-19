package store

import (
	"context"
	"fmt"
	"time"

	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
	"go.mongodb.org/mongo-driver/v2/mongo/options"

	"github.com/project/user-service/internal/models"
)

// UnfundedDigitalJobsReport counts jobs whose payment method is not COD and
// that never had escrow locked (PAY-COD-ONLY read-only check).
type UnfundedDigitalJobsReport struct {
	Total    int64            `json:"total"`
	ByStatus map[string]int64 `json:"by_status"`
}

// unfundedDigitalJobsPipeline matches jobs with a non-empty, non-COD
// payment_method, no positive locked_escrow_amount, and no escrow_lock
// ledger entry for the job. locked_escrow_amount alone is not enough: a
// completed or refunded job also ends at 0.
func unfundedDigitalJobsPipeline() mongo.Pipeline {
	return mongo.Pipeline{
		{{Key: "$match", Value: bson.M{
			"payment_method": bson.M{"$exists": true, "$nin": bson.A{"cod", ""}},
			"$or": bson.A{
				bson.M{"locked_escrow_amount": bson.M{"$exists": false}},
				bson.M{"locked_escrow_amount": bson.M{"$lte": 0}},
			},
		}}},
		{{Key: "$lookup", Value: bson.M{
			"from": "transaction_ledger",
			"let":  bson.M{"jid": "$_id"},
			"pipeline": bson.A{
				bson.M{"$match": bson.M{"$expr": bson.M{"$and": bson.A{
					bson.M{"$eq": bson.A{"$job_id", "$$jid"}},
					bson.M{"$eq": bson.A{"$type", string(models.TxEscrowLock)}},
				}}}},
				bson.M{"$limit": 1},
			},
			"as": "escrow_locks",
		}}},
		{{Key: "$match", Value: bson.M{"escrow_locks": bson.M{"$size": 0}}}},
		{{Key: "$group", Value: bson.M{"_id": "$status", "count": bson.M{"$sum": 1}}}},
	}
}

// CountUnfundedDigitalJobs runs the read-only unfunded-digital-jobs query
// against the jobs collection of db. It never writes.
func CountUnfundedDigitalJobs(ctx context.Context, db *mongo.Database) (*UnfundedDigitalJobsReport, error) {
	cur, err := db.Collection("jobs").Aggregate(ctx, unfundedDigitalJobsPipeline())
	if err != nil {
		return nil, fmt.Errorf("store: unfunded digital jobs aggregate: %w", err)
	}
	defer cur.Close(ctx)
	report := &UnfundedDigitalJobsReport{ByStatus: map[string]int64{}}
	for cur.Next(ctx) {
		var row struct {
			Status string `bson:"_id"`
			Count  int64  `bson:"count"`
		}
		if err := cur.Decode(&row); err != nil {
			return nil, fmt.Errorf("store: unfunded digital jobs decode: %w", err)
		}
		report.ByStatus[row.Status] = row.Count
		report.Total += row.Count
	}
	if err := cur.Err(); err != nil {
		return nil, fmt.Errorf("store: unfunded digital jobs cursor: %w", err)
	}
	return report, nil
}

// CountUnfundedDigitalJobsAt connects to uri with a plain client (no index
// creation, no seeding, unlike NewMongoDB) and runs CountUnfundedDigitalJobs
// against dbName. Used by `service --count-unfunded-digital-jobs`.
func CountUnfundedDigitalJobsAt(ctx context.Context, uri, dbName string) (*UnfundedDigitalJobsReport, error) {
	client, err := mongo.Connect(options.Client().ApplyURI(uri))
	if err != nil {
		return nil, fmt.Errorf("store: mongo connect: %w", err)
	}
	defer func() {
		dctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = client.Disconnect(dctx)
	}()
	return CountUnfundedDigitalJobs(ctx, client.Database(dbName))
}
