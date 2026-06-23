// Package store provides a MongoDB-backed persistent data store for the user-service.
package store

import (
	"context"
	"fmt"
	"log"
	"math"
	"time"

	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
	"go.mongodb.org/mongo-driver/v2/mongo/options"

	"github.com/project/user-service/internal/models"
)

// MongoDB is a persistent store for services, jobs, wallets, and the transaction ledger.
type MongoDB struct {
	client     *mongo.Client
	db         *mongo.Database
	services   *mongo.Collection
	jobs       *mongo.Collection
	wallets    *mongo.Collection
	ledger     *mongo.Collection
	platConfig *mongo.Collection
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
		client:     client,
		db:         db,
		services:   db.Collection("services"),
		jobs:       db.Collection("jobs"),
		wallets:    db.Collection("wallets"),
		ledger:     db.Collection("transaction_ledger"),
		platConfig: db.Collection("platform_config"),
	}
	if err := s.ensureIndexes(ctx); err != nil {
		return nil, err
	}
	s.ensureSeedData(ctx)
	log.Printf("[USER-STORE] Connected to MongoDB: %s/%s", uri, dbName)
	return s, nil
}

func (s *MongoDB) Close(ctx context.Context) error { return s.client.Disconnect(ctx) }

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
		Keys: bson.D{{Key: "service_id", Value: 1}},
	}); err != nil {
		return fmt.Errorf("jobs service_id index: %w", err)
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
	// Seed platform config (15% fee).
	var cfg models.PlatformConfig
	err := s.platConfig.FindOne(ctx, bson.M{"_id": "global"}).Decode(&cfg)
	if err != nil {
		s.platConfig.InsertOne(ctx, models.PlatformConfig{
			ID: "global", PlatformFeePercentage: 15.0, PlatformWalletID: "platform-central",
		})
		// Create platform central wallet.
		s.wallets.InsertOne(ctx, models.Wallet{
			ID: "platform-central", TenantID: "platform", UpdatedAt: time.Now().UTC(),
		})
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
			s.wallets.FindOne(ctx, bson.M{"tenant_id": tenantID}).Decode(&w)
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
	s.ledger.InsertOne(ctx, models.TransactionLedger{
		ID: fmt.Sprintf("tx-%d", time.Now().UnixNano()), TenantID: tenantID, Type: models.TxDeposit,
		Amount: amount, BalanceBefore: w.TotalBalance, BalanceAfter: w.TotalBalance + amount,
		Description: "wallet deposit", Timestamp: time.Now().UTC(),
	})
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
	s.ledger.InsertOne(ctx, models.TransactionLedger{
		ID: fmt.Sprintf("tx-%d", time.Now().UnixNano()), TenantID: tenantID, JobID: jobID,
		Type: models.TxEscrowLock, Amount: amount,
		BalanceBefore: w.WithdrawableBalance, BalanceAfter: w.WithdrawableBalance - amount,
		Description: fmt.Sprintf("escrow lock for job %s", jobID), Timestamp: time.Now().UTC(),
	})
	return nil
}

// ReleaseEscrowWithSplit handles job completion: deducts from escrow, takes platform fee, credits net.
func (s *MongoDB) ReleaseEscrowWithSplit(ctx context.Context, tenantID, jobID string, amount float64) error {
	var cfg models.PlatformConfig
	if err := s.platConfig.FindOne(ctx, bson.M{"_id": "global"}).Decode(&cfg); err != nil {
		return fmt.Errorf("platform config not found: %w", err)
	}

	feeAmount := math.Round(amount*cfg.PlatformFeePercentage) / 100
	netAmount := amount - feeAmount
	now := time.Now().UTC()
	tsBase := now.UnixNano()

	// Atomic: deduct escrow, credit withdrawable with net amount.
	res, err := s.wallets.UpdateOne(ctx,
		bson.M{"tenant_id": tenantID, "escrow_balance": bson.M{"$gte": amount}},
		bson.M{
			"$inc": bson.M{"escrow_balance": -amount, "total_balance": -feeAmount, "withdrawable_balance": netAmount},
			"$set": bson.M{"updated_at": now},
		})
	if err != nil {
		return err
	}
	if res.MatchedCount == 0 {
		return fmt.Errorf("escrow release failed: insufficient escrow balance")
	}

	// Credit platform wallet with fee.
	s.wallets.UpdateOne(ctx, bson.M{"tenant_id": "platform"},
		bson.M{
			"$inc": bson.M{"total_balance": feeAmount, "withdrawable_balance": feeAmount},
			"$set": bson.M{"updated_at": now},
		})

	// Ledger entries.
	entries := []interface{}{
		models.TransactionLedger{
			ID: fmt.Sprintf("tx-%d-release", tsBase), TenantID: tenantID, JobID: jobID,
			Type: models.TxEscrowRelease, Amount: amount, Description: "escrow released", Timestamp: now,
		},
		models.TransactionLedger{
			ID: fmt.Sprintf("tx-%d-fee", tsBase), TenantID: tenantID, JobID: jobID,
			Type: models.TxPlatformFee, Amount: feeAmount,
			Description: fmt.Sprintf("platform fee %.1f%%", cfg.PlatformFeePercentage), Timestamp: now,
		},
		models.TransactionLedger{
			ID: fmt.Sprintf("tx-%d-payout", tsBase), TenantID: tenantID, JobID: jobID,
			Type: models.TxPayout, Amount: netAmount, Description: "net payout to tenant", Timestamp: now,
		},
	}
	s.ledger.InsertMany(ctx, entries)
	return nil
}

func (s *MongoDB) GetLedger(ctx context.Context, tenantID string) []models.TransactionLedger {
	opts := options.Find().SetSort(bson.D{{Key: "timestamp", Value: -1}})
	cursor, err := s.ledger.Find(ctx, bson.M{"tenant_id": tenantID}, opts)
	if err != nil {
		return nil
	}
	defer cursor.Close(ctx)
	var entries []models.TransactionLedger
	cursor.All(ctx, &entries)
	return entries
}

func (s *MongoDB) GetPlatformConfig(ctx context.Context) *models.PlatformConfig {
	var cfg models.PlatformConfig
	if err := s.platConfig.FindOne(ctx, bson.M{"_id": "global"}).Decode(&cfg); err != nil {
		return nil
	}
	return &cfg
}

// ---------------------------------------------------------------------------
// Seed data
// ---------------------------------------------------------------------------

func seedServices() []models.Service {
	raw := []struct {
		id, name, cat   string
		bp, tbp, tppk   float64
		lat, lon        float64
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
