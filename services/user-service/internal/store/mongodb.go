// Package store provides the MongoDB-backed persistent data store for the user-service.
package store

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"log"
	"math"
	"strings"
	"time"

	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
	"go.mongodb.org/mongo-driver/v2/mongo/options"

	"github.com/project/user-service/internal/models"
)

// MongoDB is a persistent store for services, jobs, wallets, and the transaction ledger.
type MongoDB struct {
	client         *mongo.Client
	db             *mongo.Database
	services       *mongo.Collection
	jobs           *mongo.Collection
	wallets        *mongo.Collection
	ledger         *mongo.Collection
	platConfig     *mongo.Collection
	subscriptions  *mongo.Collection
	ratings        *mongo.Collection
	payoutRequests *mongo.Collection

	releaseEscrowBeforePlatformWalletHook func(ctx context.Context) error
}

// NewMongoDB connects to MongoDB and ensures all indexes.
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
		client:         client,
		db:             db,
		services:       db.Collection("services"),
		jobs:           db.Collection("jobs"),
		wallets:        db.Collection("wallets"),
		ledger:         db.Collection("transaction_ledger"),
		platConfig:     db.Collection("platform_config"),
		subscriptions:  db.Collection("subscriptions"),
		ratings:        db.Collection("ratings"),
		payoutRequests: db.Collection("payout_requests"),
	}
	if err := s.ensureIndexes(ctx); err != nil {
		return nil, err
	}
	s.ensureSeedData(ctx)
	log.Printf("[USER-STORE] Connected to MongoDB: %s/%s", uri, dbName)
	return s, nil
}

func (s *MongoDB) Close(ctx context.Context) error { return s.client.Disconnect(ctx) }

func (s *MongoDB) DropDatabase(ctx context.Context) error {
	return s.db.Drop(ctx)
}

func (s *MongoDB) ensureIndexes(ctx context.Context) error {
	// 2dsphere spatial index on services.location
	if _, err := s.services.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{{Key: "location", Value: "2dsphere"}},
	}); err != nil {
		return fmt.Errorf("services 2dsphere index: %w", err)
	}
	if _, err := s.services.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{{Key: "tenant_id", Value: 1}},
	}); err != nil {
		return fmt.Errorf("services tenant_id index: %w", err)
	}
	if _, err := s.jobs.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{{Key: "owner_id", Value: 1}},
	}); err != nil {
		return fmt.Errorf("jobs owner_id index: %w", err)
	}
	if _, err := s.jobs.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{{Key: "user_id", Value: 1}},
	}); err != nil {
		return fmt.Errorf("jobs user_id index: %w", err)
	}
	if _, err := s.jobs.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{{Key: "employee_id", Value: 1}},
	}); err != nil {
		return fmt.Errorf("jobs employee_id index: %w", err)
	}
	if _, err := s.jobs.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{{Key: "service_id", Value: 1}},
	}); err != nil {
		return fmt.Errorf("jobs service_id index: %w", err)
	}
	if _, err := s.jobs.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{{Key: "owner_id", Value: 1}, {Key: "status", Value: 1}},
	}); err != nil {
		return fmt.Errorf("jobs owner_id_status index: %w", err)
	}
	if _, err := s.wallets.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{{Key: "tenant_id", Value: 1}}, Options: options.Index().SetUnique(true),
	}); err != nil {
		return fmt.Errorf("wallets tenant_id index: %w", err)
	}
	if _, err := s.ledger.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{{Key: "tenant_id", Value: 1}, {Key: "timestamp", Value: -1}},
	}); err != nil {
		return fmt.Errorf("ledger composite index: %w", err)
	}
	if _, err := s.subscriptions.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{{Key: "tenant_id", Value: 1}}, Options: options.Index().SetUnique(true),
	}); err != nil {
		return fmt.Errorf("subscriptions tenant_id index: %w", err)
	}
	if _, err := s.ratings.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{{Key: "rated_user", Value: 1}},
	}); err != nil {
		return fmt.Errorf("ratings rated_user index: %w", err)
	}
	if _, err := s.ratings.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys:    bson.D{{Key: "job_id", Value: 1}, {Key: "rated_by", Value: 1}},
		Options: options.Index().SetUnique(true),
	}); err != nil {
		return fmt.Errorf("ratings compound unique index: %w", err)
	}
	if _, err := s.payoutRequests.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{{Key: "tenant_id", Value: 1}, {Key: "created_at", Value: -1}},
	}); err != nil {
		return fmt.Errorf("payoutRequests composite index: %w", err)
	}
	log.Println("[USER-STORE] All indexes ensured")
	return nil
}

func (s *MongoDB) ensureSeedData(ctx context.Context) {
	count, _ := s.services.CountDocuments(ctx, bson.M{})
	if count > 0 {
		return
	}
	seeds := seedServices()
	docs := make([]interface{}, len(seeds))
	for i := range seeds {
		docs[i] = seeds[i]
	}
	if _, err := s.services.InsertMany(ctx, docs); err != nil {
		log.Printf("[USER-STORE] Seed insert error: %v", err)
	} else {
		log.Printf("[USER-STORE] Seeded %d services", len(seeds))
	}
	// Seed platform config (0% fee — SaaS subscription revenue model per ADR-0017).
	var cfg models.PlatformConfig
	err := s.platConfig.FindOne(ctx, bson.M{"_id": "global"}).Decode(&cfg)
	if err != nil {
		if _, err := s.platConfig.InsertOne(ctx, models.PlatformConfig{
			ID: "global", PlatformFeePercentage: 0.0, PlatformWalletID: "platform-central",
		}); err != nil {
			log.Printf("[ERROR] failed to seed platform config: %v", err)
		}
		// Create platform central wallet.
		if _, err := s.wallets.InsertOne(ctx, models.Wallet{
			ID: "platform-central", TenantID: "platform", UpdatedAt: time.Now().UTC(),
		}); err != nil {
			log.Printf("[ERROR] failed to seed platform wallet: %v", err)
		}
		log.Println("[USER-STORE] Platform config seeded (15% fee)")
	}
}

// ---------------------------------------------------------------------------
// Service operations — with 2dsphere spatial queries
// ---------------------------------------------------------------------------

func (s *MongoDB) CreateService(ctx context.Context, svc *models.Service) {
	svc.Location = models.NewGeoJSONPoint(svc.Latitude, svc.Longitude)
	if _, err := s.services.InsertOne(ctx, svc); err != nil {
		log.Printf("[USER-STORE] CreateService error: %v", err)
	}
}

// UpdateService updates an existing service record in MongoDB.
func (s *MongoDB) UpdateService(ctx context.Context, svc *models.Service) error {
	svc.Location = models.NewGeoJSONPoint(svc.Latitude, svc.Longitude)
	filter := bson.M{"_id": svc.ID, "tenant_id": svc.TenantID}
	update := bson.M{"$set": svc}
	res, err := s.services.UpdateOne(ctx, filter, update)
	if err != nil {
		log.Printf("[USER-STORE] UpdateService error: %v", err)
		return err
	}
	if res.MatchedCount == 0 {
		return fmt.Errorf("service not found or tenant mismatch")
	}
	return nil
}

// ListServices uses MongoDB $nearSphere for proximity filtering instead of linear Haversine scan.
func (s *MongoDB) ListServices(ctx context.Context, sortBy string, nearBy bool, refLat, refLon, maxDistKm float64) []models.ServiceWithPrice {
	var filter bson.M
	if nearBy {
		if maxDistKm <= 0 {
			maxDistKm = 50
		}
		filter = bson.M{
			"location": bson.M{
				"$nearSphere": bson.M{
					"$geometry":    bson.M{"type": "Point", "coordinates": bson.A{refLon, refLat}},
					"$maxDistance": maxDistKm * 1000, // meters
				},
			},
		}
	} else {
		filter = bson.M{}
	}

	cursor, err := s.services.Find(ctx, filter)
	if err != nil {
		log.Printf("[USER-STORE] ListServices error: %v", err)
		return nil
	}
	defer cursor.Close(ctx)

	var svcs []models.Service
	if err := cursor.All(ctx, &svcs); err != nil {
		log.Printf("[USER-STORE] ListServices decode: %v", err)
		return nil
	}

	var result []models.ServiceWithPrice
	for _, svc := range svcs {
		dist := haversineKm(refLat, refLon, svc.Latitude, svc.Longitude)
		finalPrice := svc.TenantBasePrice + (dist * svc.TenantPricePerKM)
		finalPrice = math.Round(finalPrice*100) / 100
		dist = math.Round(dist*100) / 100
		result = append(result, models.ServiceWithPrice{
			Service: svc, DistanceKM: dist, FinalPrice: finalPrice,
		})
	}

	if sortBy == "price" {
		// Sort by FinalPrice ascending.
		for i := 0; i < len(result)-1; i++ {
			for j := i + 1; j < len(result); j++ {
				if result[j].FinalPrice < result[i].FinalPrice {
					result[i], result[j] = result[j], result[i]
				}
			}
		}
	}
	return result
}

// ---------------------------------------------------------------------------
// Job operations
// ---------------------------------------------------------------------------

func (s *MongoDB) CreateJob(ctx context.Context, job *models.Job) error {
	_, err := s.jobs.InsertOne(ctx, job)
	if err != nil {
		if mongo.IsDuplicateKeyError(err) {
			return fmt.Errorf("job %q already exists", job.ID)
		}
		return fmt.Errorf("store: create job: %w", err)
	}
	return nil
}

func (s *MongoDB) GetJob(ctx context.Context, id string) *models.Job {
	var job models.Job
	if err := s.jobs.FindOne(ctx, bson.M{"_id": id}).Decode(&job); err != nil {
		return nil
	}
	return &job
}

func (s *MongoDB) GetJobsByEmployee(ctx context.Context, employeeID string) ([]*models.Job, error) {
	var jobs []*models.Job
	cursor, err := s.jobs.Find(ctx, bson.M{"employee_id": employeeID})
	if err != nil {
		return nil, fmt.Errorf("store: get jobs by employee: %w", err)
	}
	defer cursor.Close(ctx)
	if err := cursor.All(ctx, &jobs); err != nil {
		return nil, fmt.Errorf("store: decode jobs by employee: %w", err)
	}
	if jobs == nil {
		jobs = make([]*models.Job, 0)
	}
	return jobs, nil
}

func (s *MongoDB) GetJobsByOwner(ctx context.Context, ownerID string) ([]*models.Job, error) {
	if s == nil || s.jobs == nil {
		return []*models.Job{}, nil
	}
	var jobs []*models.Job
	opts := options.Find().SetSort(bson.D{{Key: "created_at", Value: -1}}).SetLimit(100)
	cursor, err := s.jobs.Find(ctx, bson.M{"owner_id": ownerID}, opts)
	if err != nil {
		return nil, fmt.Errorf("store: get jobs by owner: %w", err)
	}
	defer cursor.Close(ctx)
	if err := cursor.All(ctx, &jobs); err != nil {
		return nil, fmt.Errorf("store: decode jobs by owner: %w", err)
	}
	if jobs == nil {
		jobs = make([]*models.Job, 0)
	}
	return jobs, nil
}

func (s *MongoDB) GetJobsByCustomer(ctx context.Context, customerID string) ([]*models.Job, error) {
	if s == nil || s.jobs == nil {
		return []*models.Job{}, nil
	}
	var jobs []*models.Job
	opts := options.Find().SetSort(bson.D{{Key: "created_at", Value: -1}}).SetLimit(100)
	cursor, err := s.jobs.Find(ctx, bson.M{"user_id": customerID}, opts)
	if err != nil {
		return nil, fmt.Errorf("store: get jobs by customer: %w", err)
	}
	defer cursor.Close(ctx)
	if err := cursor.All(ctx, &jobs); err != nil {
		return nil, fmt.Errorf("store: decode jobs by customer: %w", err)
	}
	if jobs == nil {
		jobs = make([]*models.Job, 0)
	}
	return jobs, nil
}

func (s *MongoDB) UpdateJobStatus(ctx context.Context, id string, status models.JobStatus) error {
	res, err := s.jobs.UpdateOne(ctx, bson.M{"_id": id},
		bson.M{"$set": bson.M{"status": status, "updated_at": time.Now().UTC()}})
	if err != nil {
		return fmt.Errorf("store: update job: %w", err)
	}
	if res.MatchedCount == 0 {
		return fmt.Errorf("job %q not found", id)
	}
	return nil
}

func (s *MongoDB) UpdateJobLockedEscrow(ctx context.Context, id string, amount float64) error {
	res, err := s.jobs.UpdateOne(ctx, bson.M{"_id": id},
		bson.M{"$set": bson.M{"locked_escrow_amount": amount, "updated_at": time.Now().UTC()}})
	if err != nil {
		return fmt.Errorf("store: update job locked escrow: %w", err)
	}
	if res.MatchedCount == 0 {
		return fmt.Errorf("job %q not found", id)
	}
	return nil
}

func (s *MongoDB) UpdateJobReconciliation(ctx context.Context, id string, status models.JobStatus, note string, failureReason string, lockedEscrow float64) error {
	res, err := s.jobs.UpdateOne(ctx, bson.M{"_id": id},
		bson.M{"$set": bson.M{
			"status":                status,
			"reconciliation_note":   note,
			"escrow_failure_reason": failureReason,
			"locked_escrow_amount":  lockedEscrow,
			"updated_at":            time.Now().UTC(),
		}})
	if err != nil {
		return fmt.Errorf("store: update job reconciliation: %w", err)
	}
	if res.MatchedCount == 0 {
		return fmt.Errorf("job %q not found", id)
	}
	return nil
}

func (s *MongoDB) UpdateJobPriceProposal(ctx context.Context, id string, proposedPrice *float64, proposedBy string, expiresAt *time.Time) error {
	var priceMatch any = nil
	if proposedPrice != nil {
		priceMatch = bson.M{"$in": []any{nil, *proposedPrice}}
	}
	filter := bson.M{
		"_id":            id,
		"status":         models.JobStatusAwaitingPriceResponse,
		"proposed_price": priceMatch,
	}
	res, err := s.jobs.UpdateOne(ctx, filter,
		bson.M{"$set": bson.M{
			"proposed_price":            proposedPrice,
			"proposed_by":               proposedBy,
			"price_proposal_expires_at": expiresAt,
			"updated_at":                time.Now().UTC(),
		}})
	if err != nil {
		return fmt.Errorf("store: update job price proposal: %w", err)
	}
	if res.MatchedCount == 0 {
		return fmt.Errorf("job_state_changed: job %q not in status awaiting_price_response or price proposal already exists", id)
	}
	return nil
}

func (s *MongoDB) UpdateJobAgreedPrice(ctx context.Context, id string, agreedPrice *float64, status models.JobStatus) error {
	filter := bson.M{
		"_id":    id,
		"status": models.JobStatusAwaitingPriceResponse,
	}
	res, err := s.jobs.UpdateOne(ctx, filter,
		bson.M{"$set": bson.M{
			"agreed_price": agreedPrice,
			"status":       status,
			"updated_at":   time.Now().UTC(),
		}})
	if err != nil {
		return fmt.Errorf("store: update job agreed price: %w", err)
	}
	if res.MatchedCount == 0 {
		return fmt.Errorf("job_state_changed: job %q not in status awaiting_price_response", id)
	}
	return nil
}

func (s *MongoDB) UpdateJobCancellation(ctx context.Context, id string, status models.JobStatus, reason string) error {
	filter := bson.M{
		"_id":    id,
		"status": models.JobStatusAwaitingPriceResponse,
	}
	res, err := s.jobs.UpdateOne(ctx, filter,
		bson.M{"$set": bson.M{
			"status":              status,
			"cancellation_reason": reason,
			"updated_at":          time.Now().UTC(),
		}})
	if err != nil {
		return fmt.Errorf("store: update job cancellation: %w", err)
	}
	if res.MatchedCount == 0 {
		return fmt.Errorf("job_state_changed: job %q not in status awaiting_price_response", id)
	}
	return nil
}

func (s *MongoDB) GetServiceByID(ctx context.Context, id string) *models.Service {
	var svc models.Service
	if err := s.services.FindOne(ctx, bson.M{"_id": id}).Decode(&svc); err != nil {
		return nil
	}
	return &svc
}

// ---------------------------------------------------------------------------
// Financial: Wallet & Ledger
// ---------------------------------------------------------------------------

func (s *MongoDB) GetOrCreateWallet(ctx context.Context, tenantID string) (*models.Wallet, error) {
	var w models.Wallet
	err := s.wallets.FindOne(ctx, bson.M{"tenant_id": tenantID}).Decode(&w)
	if err == nil {
		return &w, nil
	}
	w = models.Wallet{
		ID: fmt.Sprintf("wallet-%s", tenantID), TenantID: tenantID, UpdatedAt: time.Now().UTC(),
	}
	if _, err := s.wallets.InsertOne(ctx, w); err != nil {
		if mongo.IsDuplicateKeyError(err) {
			_ = s.wallets.FindOne(ctx, bson.M{"tenant_id": tenantID}).Decode(&w)
			return &w, nil
		}
		return nil, err
	}
	return &w, nil
}

func (s *MongoDB) GetWallet(ctx context.Context, tenantID string) *models.Wallet {
	var w models.Wallet
	if err := s.wallets.FindOne(ctx, bson.M{"tenant_id": tenantID}).Decode(&w); err != nil {
		return nil
	}
	return &w
}

// ---------------------------------------------------------------------------
// Collision-proof record ID generation
// ---------------------------------------------------------------------------

// newRecordID generates a collision-proof unique ID for persisted records
// (ledger entries, payout requests) as "<prefix>-<16 hex chars><suffix>".
//
// The previous scheme, fmt.Sprintf("tx-%d", time.Now().UnixNano()), collides
// whenever two concurrent operations read the clock in the same nanosecond;
// since TransactionLedger.ID maps to _id, the loser's InsertOne fails with a
// duplicate-key error and several write paths only log it — silently dropping
// the immutable audit entry for a real money movement. 8 random bytes give a
// 2^-64 per-pair collision probability, matching handlers.generateID.
func newRecordID(prefix, suffix string) string {
	b := make([]byte, 8)
	if _, err := rand.Read(b); err != nil {
		// Last-resort fallback; crypto/rand does not fail on supported platforms.
		return fmt.Sprintf("%s-fallback-%d%s", prefix, time.Now().UnixNano(), suffix)
	}
	return prefix + "-" + hex.EncodeToString(b) + suffix
}

func (s *MongoDB) Deposit(ctx context.Context, tenantID string, amount float64) error {
	w, err := s.GetOrCreateWallet(ctx, tenantID)
	if err != nil {
		return err
	}
	// Atomic increment.
	_, err = s.wallets.UpdateOne(ctx, bson.M{"tenant_id": tenantID},
		bson.M{"$inc": bson.M{"total_balance": amount, "withdrawable_balance": amount},
			"$set": bson.M{"updated_at": time.Now().UTC()}})
	if err != nil {
		return err
	}
	if _, err := s.ledger.InsertOne(ctx, models.TransactionLedger{
		ID: newRecordID("tx", ""), TenantID: tenantID, Type: models.TxDeposit,
		Amount: amount, BalanceBefore: w.TotalBalance, BalanceAfter: w.TotalBalance + amount,
		Description: "wallet deposit", Timestamp: time.Now().UTC(),
	}); err != nil {
		log.Printf("[ERROR] failed to insert transaction ledger: %v", err)
	}
	return nil
}

// LockEscrow atomically moves funds from WithdrawableBalance to EscrowBalance.
func (s *MongoDB) LockEscrow(ctx context.Context, tenantID, jobID string, amount float64) error {
	w, err := s.GetOrCreateWallet(ctx, tenantID)
	if err != nil {
		return err
	}
	if w.WithdrawableBalance < amount {
		return fmt.Errorf("insufficient withdrawable balance: have %.2f, need %.2f", w.WithdrawableBalance, amount)
	}
	res, err := s.wallets.UpdateOne(ctx,
		bson.M{"tenant_id": tenantID, "withdrawable_balance": bson.M{"$gte": amount}},
		bson.M{
			"$inc": bson.M{"escrow_balance": amount, "withdrawable_balance": -amount},
			"$set": bson.M{"updated_at": time.Now().UTC()},
		})
	if err != nil {
		return err
	}
	if res.MatchedCount == 0 {
		return fmt.Errorf("escrow lock failed: race condition or insufficient funds")
	}
	if _, err := s.ledger.InsertOne(ctx, models.TransactionLedger{
		ID: newRecordID("tx", ""), TenantID: tenantID, JobID: jobID,
		Type: models.TxEscrowLock, Amount: amount,
		BalanceBefore: w.WithdrawableBalance, BalanceAfter: w.WithdrawableBalance - amount,
		Description: fmt.Sprintf("escrow lock for job %s", jobID), Timestamp: time.Now().UTC(),
	}); err != nil {
		log.Printf("[ERROR] failed to insert transaction ledger: %v", err)
	}
	return nil
}

// ReleaseEscrowWithSplit handles job completion for electronic payments: releases 100% of escrow to owner withdrawable_balance (0% platform commission per ADR-0017).
func (s *MongoDB) ReleaseEscrowWithSplit(ctx context.Context, tenantID, jobID string, amount float64) error {
	netAmount := amount
	now := time.Now().UTC()

	runTx := func(sc context.Context, isFallback bool) error {
		if isFallback {
			log.Printf("[ESCROW] ⚠ non-transactional fallback in use — mid-sequence failure risk for job %s", jobID)
		}

		// Atomic check and deduct against that job's own locked amount by updating the job document.
		// status must be JobStatusActive and locked_escrow_amount >= amount.
		resJob, err := s.jobs.UpdateOne(sc,
			bson.M{
				"_id":                  jobID,
				"status":               bson.M{"$in": []models.JobStatus{models.JobStatusActive, models.JobStatusEscrowReconciliationRequired}},
				"locked_escrow_amount": bson.M{"$gte": amount},
			},
			bson.M{
				"$inc": bson.M{"locked_escrow_amount": -amount},
				"$set": bson.M{"status": models.JobStatusCompleted, "updated_at": now},
			})
		if err != nil {
			return fmt.Errorf("failed to update job escrow/status: %w", err)
		}
		if resJob.MatchedCount == 0 {
			return fmt.Errorf("escrow release failed: job %s is not active or has insufficient locked escrow", jobID)
		}

		revertJob := func() {
			if isFallback {
				_, _ = s.jobs.UpdateOne(sc, bson.M{"_id": jobID}, bson.M{
					"$inc": bson.M{"locked_escrow_amount": amount},
					"$set": bson.M{"status": models.JobStatusActive, "updated_at": time.Now().UTC()},
				})
			}
		}

		// Atomic: deduct escrow, credit withdrawable with 100% net amount (0% fee).
		res, err := s.wallets.UpdateOne(sc,
			bson.M{"tenant_id": tenantID, "escrow_balance": bson.M{"$gte": amount}},
			bson.M{
				"$inc": bson.M{"escrow_balance": -amount, "withdrawable_balance": netAmount},
				"$set": bson.M{"updated_at": now},
			})
		if err != nil || res.MatchedCount == 0 {
			revertJob()
			if err != nil {
				return err
			}
			return fmt.Errorf("escrow release failed: insufficient escrow balance")
		}

		revertTenantWallet := func() {
			if isFallback {
				_, _ = s.wallets.UpdateOne(sc, bson.M{"tenant_id": tenantID}, bson.M{
					"$inc": bson.M{"escrow_balance": amount, "withdrawable_balance": -netAmount},
					"$set": bson.M{"updated_at": time.Now().UTC()},
				})
				revertJob()
			}
		}

		if isFallback && s.releaseEscrowBeforePlatformWalletHook != nil {
			if err := s.releaseEscrowBeforePlatformWalletHook(sc); err != nil {
				revertTenantWallet()
				return err
			}
		}

		// Ledger entries.
		entries := []interface{}{
			models.TransactionLedger{
				ID: newRecordID("tx", "-release"), TenantID: tenantID, JobID: jobID,
				Type: models.TxEscrowRelease, Amount: amount, Description: "escrow released (0% platform commission)", Timestamp: now,
			},
			models.TransactionLedger{
				ID: newRecordID("tx", "-payout"), TenantID: tenantID, JobID: jobID,
				Type: models.TxPayout, Amount: netAmount, Description: "100% net payout to tenant owner", Timestamp: now,
			},
		}
		_, err = s.ledger.InsertMany(sc, entries)
		if err != nil {
			revertTenantWallet()
			return err
		}
		return nil
	}

	session, err := s.client.StartSession()
	if err != nil {
		return runTx(ctx, true)
	}
	defer session.EndSession(ctx)

	err = mongo.WithSession(ctx, session, func(sc context.Context) error {
		if err := session.StartTransaction(); err != nil {
			return err
		}
		if err := runTx(sc, false); err != nil {
			_ = session.AbortTransaction(sc)
			return err
		}
		return session.CommitTransaction(sc)
	})

	if err != nil && (strings.Contains(err.Error(), "Transaction numbers") || strings.Contains(err.Error(), "replica set")) {
		return runTx(ctx, true)
	}
	return err
}

// CompleteCODJob updates job status to completed for Cash-on-Delivery jobs
// with zero wallet mutation, persisting the actually-collected cash amount in
// the same atomic status flip so the collection record can never diverge from
// the completion event.
func (s *MongoDB) CompleteCODJob(ctx context.Context, jobID string, cashAmount float64) error {
	resJob, err := s.jobs.UpdateOne(ctx,
		bson.M{
			"_id":    jobID,
			"status": bson.M{"$in": []models.JobStatus{models.JobStatusActive, models.JobStatusEscrowReconciliationRequired}},
		},
		bson.M{
			"$set": bson.M{"status": models.JobStatusCompleted, "actual_cash_amount": cashAmount, "updated_at": time.Now().UTC()},
		})
	if err != nil {
		return fmt.Errorf("failed to update COD job status: %w", err)
	}
	if resJob.MatchedCount == 0 {
		return fmt.Errorf("COD job completion failed: job %s is not active or reconciliation required", jobID)
	}
	return nil
}

// CreatePayoutRequest creates a new payout/withdrawal request for an owner, deducting the requested amount from withdrawable_balance.
func (s *MongoDB) CreatePayoutRequest(ctx context.Context, tenantID string, input models.CreatePayoutRequestInput) (*models.PayoutRequest, error) {
	if input.Amount <= 0 {
		return nil, fmt.Errorf("invalid payout amount: must be greater than 0")
	}
	if strings.TrimSpace(input.PayoutMethod) == "" {
		return nil, fmt.Errorf("payout_method is required")
	}

	w, err := s.GetOrCreateWallet(ctx, tenantID)
	if err != nil {
		return nil, err
	}
	if w.WithdrawableBalance < input.Amount {
		return nil, fmt.Errorf("insufficient withdrawable balance: have %.2f, need %.2f", w.WithdrawableBalance, input.Amount)
	}

	now := time.Now().UTC()
	payoutID := newRecordID("payout", "")

	// Atomically deduct amount from withdrawable_balance and total_balance
	res, err := s.wallets.UpdateOne(ctx,
		bson.M{"tenant_id": tenantID, "withdrawable_balance": bson.M{"$gte": input.Amount}},
		bson.M{
			"$inc": bson.M{"withdrawable_balance": -input.Amount, "total_balance": -input.Amount},
			"$set": bson.M{"updated_at": now},
		})
	if err != nil {
		return nil, fmt.Errorf("failed to update wallet balance for payout: %w", err)
	}
	if res.MatchedCount == 0 {
		return nil, fmt.Errorf("payout request failed: insufficient withdrawable balance")
	}

	payoutReq := &models.PayoutRequest{
		ID:             payoutID,
		TenantID:       tenantID,
		Amount:         input.Amount,
		Status:         models.PayoutStatusRequested,
		PayoutMethod:   input.PayoutMethod,
		AccountDetails: input.AccountDetails,
		CreatedAt:      now,
		UpdatedAt:      now,
	}

	if _, err := s.payoutRequests.InsertOne(ctx, payoutReq); err != nil {
		// Revert wallet deduction if insert fails
		_, _ = s.wallets.UpdateOne(ctx, bson.M{"tenant_id": tenantID}, bson.M{
			"$inc": bson.M{"withdrawable_balance": input.Amount, "total_balance": input.Amount},
			"$set": bson.M{"updated_at": time.Now().UTC()},
		})
		return nil, fmt.Errorf("failed to record payout request: %w", err)
	}

	// Insert transaction ledger record
	if _, err := s.ledger.InsertOne(ctx, models.TransactionLedger{
		ID:            newRecordID("tx", "-payout-req"),
		TenantID:      tenantID,
		Type:          models.TxPayout,
		Amount:        input.Amount,
		BalanceBefore: w.WithdrawableBalance,
		BalanceAfter:  w.WithdrawableBalance - input.Amount,
		Description:   fmt.Sprintf("payout request %s (%s)", payoutID, input.PayoutMethod),
		Timestamp:     now,
	}); err != nil {
		log.Printf("[ERROR] failed to insert transaction ledger for payout request: %v", err)
	}

	return payoutReq, nil
}

// GetPayoutRequests returns all payout requests for a tenant owner ordered by creation time descending.
func (s *MongoDB) GetPayoutRequests(ctx context.Context, tenantID string) ([]*models.PayoutRequest, error) {
	opts := options.Find().SetSort(bson.D{{Key: "created_at", Value: -1}})
	cursor, err := s.payoutRequests.Find(ctx, bson.M{"tenant_id": tenantID}, opts)
	if err != nil {
		return nil, fmt.Errorf("failed to query payout requests: %w", err)
	}
	defer cursor.Close(ctx)

	var requests []*models.PayoutRequest
	if err := cursor.All(ctx, &requests); err != nil {
		return nil, fmt.Errorf("failed to decode payout requests: %w", err)
	}
	return requests, nil
}

func (s *MongoDB) GetLedger(ctx context.Context, tenantID string) []models.TransactionLedger {
	if s == nil || s.ledger == nil {
		return nil
	}
	opts := options.Find().SetSort(bson.D{{Key: "timestamp", Value: -1}})
	cursor, err := s.ledger.Find(ctx, bson.M{"tenant_id": tenantID}, opts)
	if err != nil {
		return nil
	}
	defer cursor.Close(ctx)
	var entries []models.TransactionLedger
	if err := cursor.All(ctx, &entries); err != nil {
		log.Printf("[ERROR] failed to decode ledger entries: %v", err)
	}
	return entries
}

func (s *MongoDB) GetPlatformConfig(ctx context.Context) *models.PlatformConfig {
	var cfg models.PlatformConfig
	if err := s.platConfig.FindOne(ctx, bson.M{"_id": "global"}).Decode(&cfg); err != nil {
		return nil
	}
	return &cfg
}

// UpsertPlatformConfig replaces the global platform configuration document.
// Mirrors UpsertSubscription: upsert on the fixed "global" document ID.
func (s *MongoDB) UpsertPlatformConfig(ctx context.Context, cfg *models.PlatformConfig) error {
	if cfg.ID == "" {
		cfg.ID = "global"
	}
	opts := options.Replace().SetUpsert(true)
	_, err := s.platConfig.ReplaceOne(ctx, bson.M{"_id": cfg.ID}, cfg, opts)
	return err
}

// ---------------------------------------------------------------------------
// Seed data
// ---------------------------------------------------------------------------

func seedServices() []models.Service {
	raw := []struct {
		id, name, cat string
		bp, tbp, tppk float64
		lat, lon      float64
	}{
		{"svc-001", "Home Cleaning", "Cleaning", 45, 40, 2.5, 30.0444, 31.2357},
		{"svc-002", "Office Deep Clean", "Cleaning", 120, 100, 5.0, 30.0500, 31.2400},
		{"svc-003", "Plumbing Repair", "Maintenance", 75, 65, 3.0, 30.0600, 31.2200},
		{"svc-004", "Electrical Wiring", "Maintenance", 90, 80, 4.0, 30.0800, 31.2100},
		{"svc-005", "Lawn Mowing", "Gardening", 35, 30, 1.5, 30.1000, 31.3000},
		{"svc-006", "Tree Trimming", "Gardening", 60, 50, 2.0, 30.1200, 31.3200},
		{"svc-007", "AC Maintenance", "HVAC", 110, 95, 3.5, 31.2001, 29.9187},
		{"svc-008", "Pest Control", "Cleaning", 55, 45, 2.0, 31.2100, 29.9250},
		{"svc-009", "Painting", "Renovation", 200, 180, 6.0, 29.9792, 31.1342},
		{"svc-010", "Furniture Assembly", "Maintenance", 40, 35, 1.0, 30.0444, 31.2360},
	}
	svcs := make([]models.Service, len(raw))
	for i, r := range raw {
		svcs[i] = models.Service{
			ID: r.id, Name: r.name, Category: r.cat, BasePrice: r.bp,
			TenantBasePrice: r.tbp, TenantPricePerKM: r.tppk,
			Latitude: r.lat, Longitude: r.lon, TenantID: "seed",
			Location: models.NewGeoJSONPoint(r.lat, r.lon),
		}
	}
	return svcs
}

// ---------------------------------------------------------------------------
// Haversine (used for distance in results, filtering done by MongoDB)
// ---------------------------------------------------------------------------

func haversineKm(lat1, lon1, lat2, lon2 float64) float64 {
	const R = 6371.0
	dLat := (lat2 - lat1) * math.Pi / 180
	dLon := (lon2 - lon1) * math.Pi / 180
	a := math.Sin(dLat/2)*math.Sin(dLat/2) +
		math.Cos(lat1*math.Pi/180)*math.Cos(lat2*math.Pi/180)*
			math.Sin(dLon/2)*math.Sin(dLon/2)
	return R * 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))
}

// GetSubscription returns the subscription for a tenant.
func (s *MongoDB) GetSubscription(ctx context.Context, tenantID string) *models.Subscription {
	var sub models.Subscription
	err := s.subscriptions.FindOne(ctx, bson.M{"tenant_id": tenantID}).Decode(&sub)
	if err != nil {
		return nil
	}
	return &sub
}

// UpsertSubscription inserts or updates a subscription.
func (s *MongoDB) UpsertSubscription(ctx context.Context, sub *models.Subscription) error {
	opts := options.Replace().SetUpsert(true)
	_, err := s.subscriptions.ReplaceOne(ctx, bson.M{"tenant_id": sub.TenantID}, sub, opts)
	return err
}

// CreateRating stores a new rating in MongoDB.
func (s *MongoDB) CreateRating(ctx context.Context, r *models.Rating) error {
	_, err := s.ratings.InsertOne(ctx, r)
	return err
}

// GetRatingsForUser returns all ratings received by a user.
func (s *MongoDB) GetRatingsForUser(ctx context.Context, userID string) ([]*models.Rating, error) {
	if s == nil || s.ratings == nil {
		return []*models.Rating{}, nil
	}
	cursor, err := s.ratings.Find(ctx, bson.M{"rated_user": userID})
	if err != nil {
		return nil, err
	}
	defer cursor.Close(ctx)

	var ratings []*models.Rating
	if err := cursor.All(ctx, &ratings); err != nil {
		return nil, err
	}
	return ratings, nil
}

// UpdateJobLocation updates the current live location of the employee for a job and appends to waypoints.
func (s *MongoDB) UpdateJobLocation(ctx context.Context, id string, lat, lon float64) error {
	res, err := s.jobs.UpdateOne(ctx, bson.M{"_id": id},
		bson.M{
			"$set": bson.M{
				"current_location": models.Location{Latitude: lat, Longitude: lon},
				"updated_at":       time.Now().UTC(),
			},
			"$push": bson.M{
				"waypoints": models.Location{Latitude: lat, Longitude: lon},
			},
		})
	if err != nil {
		return fmt.Errorf("store: update job location: %w", err)
	}
	if res.MatchedCount == 0 {
		return fmt.Errorf("job %q not found", id)
	}
	return nil
}

// CancelJob updates a job's status to cancelled and stores the reason.
// Enforces CAS status guard allowing cancellation only from active, pending, awaiting_price_response, escrow_reconciliation_required, or cancelled (from RefundEscrow) states.
func (s *MongoDB) CancelJob(ctx context.Context, id string, reason string) error {
	res, err := s.jobs.UpdateOne(ctx,
		bson.M{
			"_id": id,
			"status": bson.M{"$in": []models.JobStatus{
				models.JobStatusActive,
				models.JobStatusPending,
				models.JobStatusAwaitingPriceResponse,
				models.JobStatusEscrowReconciliationRequired,
				models.JobStatusCancelled,
			}},
		},
		bson.M{"$set": bson.M{
			"status":              models.JobStatusCancelled,
			"cancellation_reason": reason,
			"updated_at":          time.Now().UTC(),
		}})
	if err != nil {
		return fmt.Errorf("store: cancel job: %w", err)
	}
	if res.MatchedCount == 0 {
		var job models.Job
		if findErr := s.jobs.FindOne(ctx, bson.M{"_id": id}).Decode(&job); findErr != nil {
			return fmt.Errorf("job %q not found", id)
		}
		return fmt.Errorf("cancel job failed: job %s is not in a cancellable state (currently %s)", id, job.Status)
	}
	return nil
}

// RefundEscrow returns locked escrow back to WithdrawableBalance.
func (s *MongoDB) RefundEscrow(ctx context.Context, tenantID, jobID string, amount float64) error {
	w, err := s.GetOrCreateWallet(ctx, tenantID)
	if err != nil {
		return err
	}
	if w.EscrowBalance < amount {
		return fmt.Errorf("insufficient escrow balance to refund: have %.2f, need %.2f", w.EscrowBalance, amount)
	}

	runTx := func(sc context.Context, isFallback bool) error {
		// Capture the job's prior state so a compensating revert can restore
		// it if a later step fails. The revert closures are no-ops inside a
		// real multi-document transaction (abort handles it); they only act
		// in the non-transactional fallback where each step commits
		// immediately and a mid-sequence failure would otherwise strand
		// mutated state — mirroring ReleaseEscrowWithSplit.
		prevJobStatus := models.JobStatusCancelled
		var prev models.Job
		if err := s.jobs.FindOne(sc, bson.M{"_id": jobID}).Decode(&prev); err == nil && prev.Status != "" {
			prevJobStatus = prev.Status
		}

		revertJob := func() {
			if isFallback {
				_, _ = s.jobs.UpdateOne(sc, bson.M{"_id": jobID}, bson.M{
					"$inc": bson.M{"locked_escrow_amount": amount},
					"$set": bson.M{"status": prevJobStatus, "updated_at": time.Now().UTC()},
				})
			}
		}

		// Atomic check and deduct against that job's own locked amount by updating the job document.
		// status must be Active or Pending, and locked_escrow_amount >= amount.
		resJob, err := s.jobs.UpdateOne(sc,
			bson.M{
				"_id":                  jobID,
				"status":               bson.M{"$in": []models.JobStatus{models.JobStatusActive, models.JobStatusPending, models.JobStatusEscrowReconciliationRequired}},
				"locked_escrow_amount": bson.M{"$gte": amount},
			},
			bson.M{
				"$inc": bson.M{"locked_escrow_amount": -amount},
				"$set": bson.M{"status": models.JobStatusCancelled, "updated_at": time.Now().UTC()},
			})
		if err != nil {
			return fmt.Errorf("failed to update job escrow/status: %w", err)
		}
		if resJob.MatchedCount == 0 {
			return fmt.Errorf("escrow refund failed: job %s is not active/pending or has insufficient locked escrow", jobID)
		}

		res, err := s.wallets.UpdateOne(sc,
			bson.M{"tenant_id": tenantID, "escrow_balance": bson.M{"$gte": amount}},
			bson.M{
				"$inc": bson.M{"escrow_balance": -amount, "withdrawable_balance": amount},
				"$set": bson.M{"updated_at": time.Now().UTC()},
			})
		if err != nil {
			revertJob()
			return err
		}
		if res.MatchedCount == 0 {
			revertJob()
			return fmt.Errorf("escrow refund failed: insufficient escrow balance")
		}

		revertWalletAndJob := func() {
			if isFallback {
				_, _ = s.wallets.UpdateOne(sc, bson.M{"tenant_id": tenantID}, bson.M{
					"$inc": bson.M{"escrow_balance": amount, "withdrawable_balance": -amount},
					"$set": bson.M{"updated_at": time.Now().UTC()},
				})
				revertJob()
			}
		}

		_, err = s.ledger.InsertOne(sc, models.TransactionLedger{
			ID: newRecordID("tx", "-refund"), TenantID: tenantID, JobID: jobID,
			Type: models.TxEscrowRelease, Amount: amount,
			BalanceBefore: w.WithdrawableBalance, BalanceAfter: w.WithdrawableBalance + amount,
			Description: fmt.Sprintf("escrow refund for cancelled job %s", jobID), Timestamp: time.Now().UTC(),
		})
		if err != nil {
			revertWalletAndJob()
			return err
		}
		return nil
	}

	session, err := s.client.StartSession()
	if err != nil {
		return runTx(ctx, true)
	}
	defer session.EndSession(ctx)

	err = mongo.WithSession(ctx, session, func(sc context.Context) error {
		if err := session.StartTransaction(); err != nil {
			return err
		}
		if err := runTx(sc, false); err != nil {
			_ = session.AbortTransaction(sc)
			return err
		}
		return session.CommitTransaction(sc)
	})

	if err != nil && (strings.Contains(err.Error(), "Transaction numbers") || strings.Contains(err.Error(), "replica set")) {
		log.Printf("[USER-STORE] Standalone MongoDB detected. Falling back to sequential execution for RefundEscrow.")
		return runTx(ctx, true)
	}
	return err
}

func (s *MongoDB) RollbackEscrow(ctx context.Context, tenantID string, amount float64) error {
	w, err := s.GetOrCreateWallet(ctx, tenantID)
	if err != nil {
		return err
	}
	res, err := s.wallets.UpdateOne(ctx,
		bson.M{"tenant_id": tenantID, "escrow_balance": bson.M{"$gte": amount}},
		bson.M{
			"$inc": bson.M{"escrow_balance": -amount, "withdrawable_balance": amount},
			"$set": bson.M{"updated_at": time.Now().UTC()},
		})
	if err != nil {
		return err
	}
	if res.MatchedCount == 0 {
		return fmt.Errorf("escrow rollback failed: insufficient escrow balance")
	}
	_, err = s.ledger.InsertOne(ctx, models.TransactionLedger{
		ID: newRecordID("tx", "-rollback"), TenantID: tenantID,
		Type: models.TxEscrowRelease, Amount: amount,
		BalanceBefore: w.WithdrawableBalance, BalanceAfter: w.WithdrawableBalance + amount,
		Description: "escrow lock rollback due to persistence failure", Timestamp: time.Now().UTC(),
	})
	return err
}

func (s *MongoDB) DeleteJob(ctx context.Context, id string) error {
	_, err := s.jobs.DeleteOne(ctx, bson.M{"_id": id})
	return err
}

func (s *MongoDB) CountJobsByOwner(ctx context.Context, ownerID string) (int, error) {
	count, err := s.jobs.CountDocuments(ctx, bson.M{"owner_id": ownerID})
	return int(count), err
}

// GetReconciliationQueueByOwner returns all jobs for an owner currently in status escrow_reconciliation_required.
func (s *MongoDB) GetReconciliationQueueByOwner(ctx context.Context, ownerID string) ([]*models.Job, error) {
	var jobs []*models.Job
	filter := bson.M{
		"owner_id": ownerID,
		"status":   models.JobStatusEscrowReconciliationRequired,
	}
	opts := options.Find().SetSort(bson.D{{Key: "updated_at", Value: -1}}).SetLimit(100)
	cursor, err := s.jobs.Find(ctx, filter, opts)
	if err != nil {
		return nil, fmt.Errorf("store: get reconciliation queue by owner: %w", err)
	}
	defer cursor.Close(ctx)
	if err := cursor.All(ctx, &jobs); err != nil {
		return nil, fmt.Errorf("store: decode reconciliation queue by owner: %w", err)
	}
	if jobs == nil {
		jobs = make([]*models.Job, 0)
	}
	return jobs, nil
}

// RejectPayoutRequest flips a payout request from "requested" to "rejected"
// (CAS-guarded so an approved/paid/rejected request can never be mutated),
// restores the previously deducted funds to the owner's withdrawable and
// total balances, and records a payout_refund ledger entry. This is the
// store capability backing the admin rejection flow, which remains deferred
// to the Support Agent Console per ADR-0018.
func (s *MongoDB) RejectPayoutRequest(ctx context.Context, payoutID, reason string) error {
	now := time.Now().UTC()

	// CAS: only a request still in "requested" state can be rejected.
	res := s.payoutRequests.FindOneAndUpdate(ctx,
		bson.M{"_id": payoutID, "status": models.PayoutStatusRequested},
		bson.M{"$set": bson.M{
			"status":           models.PayoutStatusRejected,
			"rejection_reason": reason,
			"updated_at":       now,
		}},
	)
	if res.Err() != nil {
		if res.Err() == mongo.ErrNoDocuments {
			return fmt.Errorf("payout request %s not found or not in requested state", payoutID)
		}
		return fmt.Errorf("failed to reject payout request: %w", res.Err())
	}

	var pr models.PayoutRequest
	if err := res.Decode(&pr); err != nil {
		return fmt.Errorf("failed to decode rejected payout request: %w", err)
	}

	// Restore the deducted funds.
	wres, err := s.wallets.UpdateOne(ctx,
		bson.M{"tenant_id": pr.TenantID},
		bson.M{
			"$inc": bson.M{"withdrawable_balance": pr.Amount, "total_balance": pr.Amount},
			"$set": bson.M{"updated_at": now},
		})
	if err != nil {
		return fmt.Errorf("failed to restore wallet balance for rejected payout: %w", err)
	}
	if wres.MatchedCount == 0 {
		return fmt.Errorf("wallet for tenant %s not found while restoring rejected payout", pr.TenantID)
	}

	if _, err := s.ledger.InsertOne(ctx, models.TransactionLedger{
		ID: newRecordID("tx", ""), TenantID: pr.TenantID,
		Type: models.TxPayoutRefund, Amount: pr.Amount,
		Description: fmt.Sprintf("payout %s rejected: %s", payoutID, reason),
		Timestamp:   now,
	}); err != nil {
		log.Printf("[ERROR] failed to insert payout_refund ledger entry: %v", err)
	}

	return nil
}
