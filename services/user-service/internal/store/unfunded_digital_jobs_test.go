package store

import (
	"context"
	"testing"
	"time"

	"go.mongodb.org/mongo-driver/v2/bson"

	"github.com/project/user-service/internal/models"
)

// TestCountUnfundedDigitalJobs: PAY-COD-ONLY read-only check. Only non-COD
// jobs with no escrow lock (no positive locked amount and no escrow_lock
// ledger entry) are counted, and the query writes nothing.
func TestCountUnfundedDigitalJobs(t *testing.T) {
	db, _ := beErrRawDB(t)
	ctx := context.Background()
	now := time.Now().UTC()
	jobs := bson.A{
		bson.M{"_id": "cod-1", "payment_method": "cod", "status": "active"},
		bson.M{"_id": "legacy-empty", "payment_method": "", "status": "active"},
		bson.M{"_id": "wallet-unfunded", "payment_method": "wallet", "status": "pending"},
		bson.M{"_id": "wallet-unfunded-2", "payment_method": "wallet", "status": "pending", "locked_escrow_amount": 0},
		bson.M{"_id": "wallet-cancelled", "payment_method": "wallet", "status": "cancelled"},
		bson.M{"_id": "wallet-locked", "payment_method": "wallet", "status": "active", "locked_escrow_amount": 50},
		bson.M{"_id": "wallet-completed", "payment_method": "wallet", "status": "completed", "locked_escrow_amount": 0},
	}
	if _, err := db.Collection("jobs").InsertMany(ctx, jobs); err != nil {
		t.Fatalf("seed jobs: %v", err)
	}
	if _, err := db.Collection("transaction_ledger").InsertOne(ctx, models.TransactionLedger{
		ID: "tx-lock-1", TenantID: "t", JobID: "wallet-completed", Type: models.TxEscrowLock, Amount: 50, Timestamp: now,
	}); err != nil {
		t.Fatalf("seed ledger: %v", err)
	}

	report, err := CountUnfundedDigitalJobs(ctx, db)
	if err != nil {
		t.Fatalf("CountUnfundedDigitalJobs: %v", err)
	}
	if report.Total != 3 || report.ByStatus["pending"] != 2 || report.ByStatus["cancelled"] != 1 {
		t.Errorf("expected 3 unfunded (2 pending, 1 cancelled), got %+v", report)
	}

	n, err := db.Collection("jobs").CountDocuments(ctx, bson.M{})
	if err != nil || n != int64(len(jobs)) {
		t.Errorf("expected the query to leave %d jobs untouched, got %d (%v)", len(jobs), n, err)
	}
}
