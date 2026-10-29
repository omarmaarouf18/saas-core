package store

import (
	"context"
	"errors"
	"fmt"
	"math"
	"time"

	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
	"go.mongodb.org/mongo-driver/v2/mongo/options"

	"github.com/project/user-service/internal/models"
)

var (
	ErrJobNotFound        = errors.New("job not found")
	ErrJobAlreadyTerminal = errors.New("job already in terminal state")
	ErrJobStateConflict   = errors.New("job state conflict during update")
	ErrNotStuckCODJob     = errors.New("job is not a stuck COD reconciliation job")
)

// FIX-COD-RECON: before the fix, CompleteJob parked COD delivery/shipping
// jobs with a GPS under-distance mismatch in escrow_reconciliation_required
// without recording the collected cash. These helpers back the
// --count-stuck-cod-reconciliation-jobs (read-only) and
// --repair-stuck-cod-reconciliation-jobs [--confirm] CLI flags.

// stuckCODUnderDistanceReason is the escrow_failure_reason CompleteJob wrote
// for the under-distance mismatch. Only jobs with this reason are repaired.
const stuckCODUnderDistanceReason = "under_distance_mismatch"

// StuckCODReconciliationReport counts COD jobs in escrow_reconciliation_required
// that hold no locked escrow. Repairable is the subset whose
// escrow_failure_reason is under_distance_mismatch.
type StuckCODReconciliationReport struct {
	Total      int64            `json:"total"`
	ByReason   map[string]int64 `json:"by_reason"`
	Repairable int64            `json:"repairable"`
}

// stuckCODReconciliationFilter matches COD jobs parked for escrow
// reconciliation with no positive locked_escrow_amount (none is held for COD).
func stuckCODReconciliationFilter() bson.M {
	return bson.M{
		"payment_method": "cod",
		"status":         models.JobStatusEscrowReconciliationRequired,
		"$or": bson.A{
			bson.M{"locked_escrow_amount": bson.M{"$exists": false}},
			bson.M{"locked_escrow_amount": bson.M{"$lte": 0}},
		},
	}
}

// CountStuckCODReconciliationJobs runs the read-only count against the jobs
// collection of db. It never writes.
func CountStuckCODReconciliationJobs(ctx context.Context, db *mongo.Database) (*StuckCODReconciliationReport, error) {
	cur, err := db.Collection("jobs").Aggregate(ctx, mongo.Pipeline{
		{{Key: "$match", Value: stuckCODReconciliationFilter()}},
		{{Key: "$group", Value: bson.M{
			"_id":   bson.M{"$ifNull": bson.A{"$escrow_failure_reason", ""}},
			"count": bson.M{"$sum": 1},
		}}},
	})
	if err != nil {
		return nil, fmt.Errorf("store: stuck cod reconciliation aggregate: %w", err)
	}
	defer cur.Close(ctx)
	report := &StuckCODReconciliationReport{ByReason: map[string]int64{}}
	for cur.Next(ctx) {
		var row struct {
			Reason string `bson:"_id"`
			Count  int64  `bson:"count"`
		}
		if err := cur.Decode(&row); err != nil {
			return nil, fmt.Errorf("store: stuck cod reconciliation decode: %w", err)
		}
		report.ByReason[row.Reason] = row.Count
		report.Total += row.Count
		if row.Reason == stuckCODUnderDistanceReason {
			report.Repairable += row.Count
		}
	}
	if err := cur.Err(); err != nil {
		return nil, fmt.Errorf("store: stuck cod reconciliation cursor: %w", err)
	}
	return report, nil
}

// RepairedCODJob is one job the repair moved (or, in a dry run, would move)
// to completed.
type RepairedCODJob struct {
	JobID      string  `json:"job_id"`
	OwnerID    string  `json:"owner_id"`
	CashAmount float64 `json:"actual_cash_amount"`
	ActualKm   float64 `json:"actual_km"`
	BookedKm   float64 `json:"booked_km"`
}

// SkippedCODJob is a matched job the repair left untouched, with why.
type SkippedCODJob struct {
	JobID  string `json:"job_id"`
	Reason string `json:"reason"`
}

// StuckCODRepairResult is the outcome of RepairStuckCODReconciliationJobs.
type StuckCODRepairResult struct {
	Applied  bool             `json:"applied"`
	Repaired []RepairedCODJob `json:"repaired"`
	Skipped  []SkippedCODJob  `json:"skipped"`
}

// RepairStuckCODReconciliationJobs moves COD jobs stuck in
// escrow_reconciliation_required by the under-distance check to completed,
// with a distance_review flag (source stuck_job_repair) and
// actual_cash_amount set to the booked amount (the agreed price, else
// TenantBasePrice + booked km × TenantPricePerKM, the same formula as
// CompleteJob). An actual_cash_amount already on the job is kept. The
// assigned courier's lock on the job is released, as CompleteJob does.
//
// With apply == false it only reports what it would do. It is idempotent:
// each update is guarded by the stuck filter, so a repaired job is never
// matched again. Jobs with another escrow_failure_reason, or whose service
// no longer exists, are skipped and reported.
func RepairStuckCODReconciliationJobs(ctx context.Context, db *mongo.Database, apply bool) (*StuckCODRepairResult, error) {
	jobsColl := db.Collection("jobs")
	cur, err := jobsColl.Find(ctx, stuckCODReconciliationFilter(), options.Find().SetSort(bson.D{{Key: "_id", Value: 1}}))
	if err != nil {
		return nil, fmt.Errorf("store: stuck cod reconciliation find: %w", err)
	}
	var jobs []models.Job
	if err := cur.All(ctx, &jobs); err != nil {
		return nil, fmt.Errorf("store: stuck cod reconciliation decode: %w", err)
	}

	result := &StuckCODRepairResult{Applied: apply, Repaired: []RepairedCODJob{}, Skipped: []SkippedCODJob{}}
	for i := range jobs {
		job := &jobs[i]
		if job.EscrowFailureReason != stuckCODUnderDistanceReason {
			result.Skipped = append(result.Skipped, SkippedCODJob{JobID: job.ID, Reason: fmt.Sprintf("escrow_failure_reason %q is not %q", job.EscrowFailureReason, stuckCODUnderDistanceReason)})
			continue
		}
		var svc models.Service
		if err := db.Collection("services").FindOne(ctx, bson.M{"_id": job.ServiceID}).Decode(&svc); err != nil {
			result.Skipped = append(result.Skipped, SkippedCODJob{JobID: job.ID, Reason: fmt.Sprintf("service %q not readable: %v", job.ServiceID, err)})
			continue
		}

		actualKm, bookedKm := parseDistanceMismatchNote(job.ReconciliationNote)
		if job.BookedDistance > 0 {
			bookedKm = job.BookedDistance
		}
		cash := math.Round((svc.TenantBasePrice+(bookedKm*svc.TenantPricePerKM))*100) / 100
		if job.AgreedPrice != nil && *job.AgreedPrice > 0 {
			cash = *job.AgreedPrice
		}
		if job.ActualCashAmount != nil {
			cash = *job.ActualCashAmount
		}
		entry := RepairedCODJob{JobID: job.ID, OwnerID: job.OwnerID, CashAmount: cash, ActualKm: actualKm, BookedKm: bookedKm}
		if !apply {
			result.Repaired = append(result.Repaired, entry)
			continue
		}

		now := time.Now().UTC()
		filter := stuckCODReconciliationFilter()
		filter["_id"] = job.ID
		filter["escrow_failure_reason"] = stuckCODUnderDistanceReason
		res, err := jobsColl.UpdateOne(ctx, filter, bson.M{"$set": bson.M{
			"status":             models.JobStatusCompleted,
			"actual_cash_amount": cash,
			"distance_review": models.DistanceReview{
				ActualKm: actualKm, BookedKm: bookedKm, FlaggedAt: now, Source: models.DistanceReviewSourceRepair,
			},
			"updated_at": now,
		}})
		if err != nil {
			return result, fmt.Errorf("store: repair stuck cod job %s: %w", job.ID, err)
		}
		if res.MatchedCount == 0 {
			result.Skipped = append(result.Skipped, SkippedCODJob{JobID: job.ID, Reason: "job changed state before the update"})
			continue
		}
		if job.EmployeeID != "" {
			if _, err := db.Collection("employee_locations").UpdateOne(ctx,
				bson.M{"tenant_id": job.OwnerID, "employee_id": job.EmployeeID, "active_job_id": job.ID},
				bson.M{"$set": bson.M{"active_job_id": ""}}); err != nil {
				return result, fmt.Errorf("store: release courier lock for job %s: %w", job.ID, err)
			}
		}
		result.Repaired = append(result.Repaired, entry)
	}
	return result, nil
}

// parseDistanceMismatchNote reads the km values from the note CompleteJob
// wrote ("tracked_distance_mismatch: actual %.2f km vs booked %.2f km").
// Unparseable notes yield zeros.
func parseDistanceMismatchNote(note string) (actualKm, bookedKm float64) {
	if _, err := fmt.Sscanf(note, "tracked_distance_mismatch: actual %f km vs booked %f km", &actualKm, &bookedKm); err != nil {
		return 0, 0
	}
	return actualKm, bookedKm
}

// withPlainClient connects to uri with a plain client (no index creation, no
// seeding, unlike NewMongoDB), runs fn against dbName and disconnects.
func withPlainClient[T any](ctx context.Context, uri, dbName string, fn func(*mongo.Database) (T, error)) (T, error) {
	var zero T
	client, err := mongo.Connect(options.Client().ApplyURI(uri))
	if err != nil {
		return zero, fmt.Errorf("store: mongo connect: %w", err)
	}
	defer func() {
		dctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = client.Disconnect(dctx)
	}()
	return fn(client.Database(dbName))
}

// CountStuckCODReconciliationJobsAt runs CountStuckCODReconciliationJobs
// against dbName at uri. Used by `service --count-stuck-cod-reconciliation-jobs`.
func CountStuckCODReconciliationJobsAt(ctx context.Context, uri, dbName string) (*StuckCODReconciliationReport, error) {
	return withPlainClient(ctx, uri, dbName, func(db *mongo.Database) (*StuckCODReconciliationReport, error) {
		return CountStuckCODReconciliationJobs(ctx, db)
	})
}

// RepairStuckCODReconciliationJobsAt runs RepairStuckCODReconciliationJobs
// against dbName at uri. Used by
// `service --repair-stuck-cod-reconciliation-jobs [--confirm]`.
func RepairStuckCODReconciliationJobsAt(ctx context.Context, uri, dbName string, apply bool) (*StuckCODRepairResult, error) {
	return withPlainClient(ctx, uri, dbName, func(db *mongo.Database) (*StuckCODRepairResult, error) {
		return RepairStuckCODReconciliationJobs(ctx, db, apply)
	})
}

// RepairSingleStuckCODJob moves a single COD job stuck in
// escrow_reconciliation_required to completed, reusing the FIX-COD-RECON logic.
func (s *MongoDB) RepairSingleStuckCODJob(ctx context.Context, jobID, reviewerID, reason string) (*RepairedCODJob, error) {
	jobsColl := s.jobs
	var job models.Job
	if err := jobsColl.FindOne(ctx, bson.M{"_id": jobID}).Decode(&job); err != nil {
		if errors.Is(err, mongo.ErrNoDocuments) {
			return nil, ErrJobNotFound
		}
		return nil, fmt.Errorf("store: find job: %w", err)
	}

	// CAS & eligibility check: must be COD, escrow_reconciliation_required, and locked_escrow <= 0
	if job.PaymentMethod != "cod" || job.Status != models.JobStatusEscrowReconciliationRequired || job.LockedEscrowAmount > 0 {
		return nil, ErrNotStuckCODJob
	}

	var svc models.Service
	if err := s.services.FindOne(ctx, bson.M{"_id": job.ServiceID}).Decode(&svc); err != nil {
		if job.AgreedPrice == nil && job.ActualCashAmount == nil {
			return nil, fmt.Errorf("store: service %q not readable: %w", job.ServiceID, err)
		}
	}

	actualKm, bookedKm := parseDistanceMismatchNote(job.ReconciliationNote)
	if job.BookedDistance > 0 {
		bookedKm = job.BookedDistance
	}
	cash := math.Round((svc.TenantBasePrice+(bookedKm*svc.TenantPricePerKM))*100) / 100
	if job.AgreedPrice != nil && *job.AgreedPrice > 0 {
		cash = *job.AgreedPrice
	}
	if job.ActualCashAmount != nil && *job.ActualCashAmount > 0 {
		cash = *job.ActualCashAmount
	}

	now := time.Now().UTC()
	filter := stuckCODReconciliationFilter()
	filter["_id"] = job.ID

	histEntry := models.JobStatusHistoryEntry{
		Status:    models.JobStatusCompleted,
		At:        now,
		ActorRole: models.ActorRoleAdmin,
		ActorID:   reviewerID,
		Reason:    reason,
	}

	res, err := jobsColl.UpdateOne(ctx, filter, bson.M{
		"$set": bson.M{
			"status":             models.JobStatusCompleted,
			"sub_status":         "",
			"actual_cash_amount": cash,
			"distance_review": models.DistanceReview{
				ActualKm: actualKm, BookedKm: bookedKm, FlaggedAt: now, Source: models.DistanceReviewSourceRepair,
			},
			"updated_at": now,
		},
		"$push": bson.M{
			"status_history": histEntry,
		},
	})
	if err != nil {
		return nil, fmt.Errorf("store: repair stuck cod job %s: %w", job.ID, err)
	}
	if res.MatchedCount == 0 {
		return nil, ErrJobStateConflict
	}

	if job.EmployeeID != "" {
		_, _ = s.employeeLocations.UpdateOne(ctx,
			bson.M{"tenant_id": job.OwnerID, "employee_id": job.EmployeeID, "active_job_id": job.ID},
			bson.M{"$set": bson.M{"active_job_id": ""}})
	}

	return &RepairedCODJob{
		JobID:      job.ID,
		OwnerID:    job.OwnerID,
		CashAmount: cash,
		ActualKm:   actualKm,
		BookedKm:   bookedKm,
	}, nil
}
