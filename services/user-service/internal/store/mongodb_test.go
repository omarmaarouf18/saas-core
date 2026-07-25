package store

import (
	"context"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/project/user-service/internal/models"
)

func setupTestMongoDB(t *testing.T) (*MongoDB, func()) {
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	dbName := fmt.Sprintf("saas_user_store_test_%d", time.Now().UnixNano())
	s, err := NewMongoDB(ctx, mongoURI, dbName)
	if err != nil {
		t.Skipf("Skipping MongoDB store tests: MongoDB unreachable at %s (%v)", mongoURI, err)
		return nil, nil
	}

	cleanup := func() {
		cleanupCtx, cCancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cCancel()
		_ = s.DropDatabase(cleanupCtx)
		_ = s.Close(cleanupCtx)
	}

	return s, cleanup
}

func TestMongoDB_InvalidURI(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 1*time.Second)
	defer cancel()

	_, err := NewMongoDB(ctx, "mongodb://127.0.0.1:59999", "testdb")
	if err == nil {
		t.Errorf("Expected error connecting to unreachable MongoDB URI, got nil")
	}
}

func TestMongoDB_ServiceOperations(t *testing.T) {
	s, cleanup := setupTestMongoDB(t)
	if s == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()

	svc := &models.Service{
		ID:               "svc-1",
		TenantID:         "tenant-1",
		Name:             "House Cleaning",
		Category:         "cleaning",
		TenantBasePrice:  50.0,
		TenantPricePerKM: 2.0,
		Latitude:         37.7749,
		Longitude:        -122.4194,
		Location:         models.NewGeoJSONPoint(37.7749, -122.4194),
	}

	// 1. CreateService (void return)
	s.CreateService(ctx, svc)

	// 2. GetServiceByID (returns *models.Service)
	got := s.GetServiceByID(ctx, "svc-1")
	if got == nil || got.Name != "House Cleaning" {
		t.Fatalf("GetServiceByID failed: %v", got)
	}

	// 3. ListServices (returns []models.ServiceWithPrice)
	svcs := s.ListServices(ctx, "distance", true, 37.7750, -122.4195, 10.0)
	if len(svcs) == 0 {
		t.Errorf("ListServices returned 0 items")
	}
}

func TestMongoDB_JobOperations(t *testing.T) {
	s, cleanup := setupTestMongoDB(t)
	if s == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()

	job := &models.Job{
		ID:            "job-store-1",
		OwnerID:       "owner-1",
		EmployeeID:    "emp-1",
		UserID:        "user-1",
		ServiceID:     "svc-1",
		Status:        models.JobStatusPending,
		Location:      models.Location{Latitude: 37.7749, Longitude: -122.4194},
		PaymentMethod: "cod",
		CreatedAt:     time.Now(),
		UpdatedAt:     time.Now(),
	}

	// 1. CreateJob
	if err := s.CreateJob(ctx, job); err != nil {
		t.Fatalf("CreateJob failed: %v", err)
	}

	// 2. GetJob (returns *models.Job)
	gotJob := s.GetJob(ctx, "job-store-1")
	if gotJob == nil || gotJob.OwnerID != "owner-1" {
		t.Fatalf("GetJob failed: %v", gotJob)
	}

	// 3. GetJobsByEmployee
	empJobs, err := s.GetJobsByEmployee(ctx, "emp-1")
	if err != nil || len(empJobs) != 1 {
		t.Errorf("GetJobsByEmployee failed: len=%d, err=%v", len(empJobs), err)
	}

	// 4. UpdateJobStatus
	if err := s.UpdateJobStatus(ctx, "job-store-1", models.JobStatusActive); err != nil {
		t.Fatalf("UpdateJobStatus failed: %v", err)
	}
	activeJob := s.GetJob(ctx, "job-store-1")
	if activeJob.Status != models.JobStatusActive {
		t.Errorf("Expected status active, got %s", activeJob.Status)
	}

	// 5. UpdateJobLocation
	if err := s.UpdateJobLocation(ctx, "job-store-1", 37.7800, -122.4200); err != nil {
		t.Fatalf("UpdateJobLocation failed: %v", err)
	}

	// 6. CountJobsByOwner
	cnt, err := s.CountJobsByOwner(ctx, "owner-1")
	if err != nil || cnt != 1 {
		t.Errorf("CountJobsByOwner failed: cnt=%d, err=%v", cnt, err)
	}

	// 7. DeleteJob
	if err := s.DeleteJob(ctx, "job-store-1"); err != nil {
		t.Fatalf("DeleteJob failed: %v", err)
	}
}

func TestMongoDB_WalletAndEscrow(t *testing.T) {
	s, cleanup := setupTestMongoDB(t)
	if s == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	tenantID := "tenant-wallet-1"

	// 1. GetOrCreateWallet
	w, err := s.GetOrCreateWallet(ctx, tenantID)
	if err != nil {
		t.Fatalf("GetOrCreateWallet failed: %v", err)
	}
	if w.TenantID != tenantID {
		t.Errorf("Unexpected tenant ID in wallet: %s", w.TenantID)
	}

	// 2. Deposit
	if err := s.Deposit(ctx, tenantID, 100.0); err != nil {
		t.Fatalf("Deposit failed: %v", err)
	}
	wUpdated := s.GetWallet(ctx, tenantID)
	if wUpdated.TotalBalance != 100.0 || wUpdated.WithdrawableBalance != 100.0 {
		t.Errorf("Unexpected wallet balance after deposit: %v", wUpdated)
	}

	// 3. LockEscrow
	if err := s.LockEscrow(ctx, tenantID, "job-escrow-1", 40.0); err != nil {
		t.Fatalf("LockEscrow failed: %v", err)
	}
	wLocked := s.GetWallet(ctx, tenantID)
	if wLocked.EscrowBalance != 40.0 || wLocked.WithdrawableBalance != 60.0 {
		t.Errorf("Unexpected balance after LockEscrow: %v", wLocked)
	}

	// Create active job with locked escrow for ReleaseEscrowWithSplit
	jobEscrow := &models.Job{
		ID:                 "job-escrow-1",
		OwnerID:            tenantID,
		Status:             models.JobStatusActive,
		LockedEscrowAmount: 40.0,
	}
	_ = s.CreateJob(ctx, jobEscrow)

	// 4. ReleaseEscrowWithSplit
	if err := s.ReleaseEscrowWithSplit(ctx, tenantID, "job-escrow-1", 40.0); err != nil {
		t.Fatalf("ReleaseEscrowWithSplit failed: %v", err)
	}

	// Create active job for DeductCODFee
	jobCOD := &models.Job{
		ID:      "job-cod-1",
		OwnerID: tenantID,
		Status:  models.JobStatusActive,
	}
	_ = s.CreateJob(ctx, jobCOD)

	// 5. DeductCODFee
	if err := s.DeductCODFee(ctx, tenantID, "job-cod-1", 5.0); err != nil {
		t.Fatalf("DeductCODFee failed: %v", err)
	}

	// 6. GetLedger (returns []models.TransactionLedger)
	ledger := s.GetLedger(ctx, tenantID)
	if len(ledger) == 0 {
		t.Errorf("GetLedger returned 0 items")
	}
}

func TestMongoDB_SubscriptionsAndRatings(t *testing.T) {
	s, cleanup := setupTestMongoDB(t)
	if s == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()

	// 1. Subscriptions
	sub := &models.Subscription{
		ID:        "sub-1",
		TenantID:  "tenant-sub-1",
		Tier:      models.PlanPaid,
		StartedAt: time.Now(),
		ExpiresAt: time.Now().Add(30 * 24 * time.Hour),
	}
	if err := s.UpsertSubscription(ctx, sub); err != nil {
		t.Fatalf("UpsertSubscription failed: %v", err)
	}

	gotSub := s.GetSubscription(ctx, "tenant-sub-1")
	if gotSub == nil || gotSub.Tier != models.PlanPaid {
		t.Errorf("GetSubscription failed: %v", gotSub)
	}

	// 2. Ratings
	rating := &models.Rating{
		ID:        "rate-1",
		JobID:     "job-rate-1",
		RatedBy:   "user-1",
		RatedUser: "owner-1",
		Stars:     5,
		Comment:   "Great job!",
		CreatedAt: time.Now(),
	}
	if err := s.CreateRating(ctx, rating); err != nil {
		t.Fatalf("CreateRating failed: %v", err)
	}

	gotRatings, err := s.GetRatingsForUser(ctx, "owner-1")
	if err != nil || len(gotRatings) != 1 {
		t.Errorf("GetRatingsForUser failed: len=%d, err=%v", len(gotRatings), err)
	}
}
