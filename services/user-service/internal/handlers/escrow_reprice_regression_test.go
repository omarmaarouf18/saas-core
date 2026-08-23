package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"math"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/project/shared/infra/jwtutil"
	"github.com/project/user-service/internal/config"
	"github.com/project/user-service/internal/models"
	"github.com/project/user-service/internal/store"
	"github.com/redis/go-redis/v9"
)

// TestEscrowRepriceDown_ReleasesAndRefundsExactLockedAmount guards against
// stranded-escrow fund entrapment: CompleteJob and CancelJob must move
// exactly job.LockedEscrowAmount, never a freshly recomputed price. If an
// owner lowers TenantBasePrice/TenantPricePerKM after booking, a recomputed
// release/refund would strand the residual (LockedEscrowAmount - amount) in
// escrow forever on a terminal-status job.
func TestEscrowRepriceDown_ReleasesAndRefundsExactLockedAmount(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	dbName := fmt.Sprintf("saas_platform_test_%d", time.Now().UnixNano())
	s, err := store.NewMongoDB(ctx, mongoURI, dbName)
	if err != nil {
		t.Skipf("Skipping integration test: MongoDB not available at %s (%v)", mongoURI, err)
		return
	}
	defer func() {
		_ = s.DropDatabase(context.Background())
		s.Close(context.Background())
	}()

	mockAuthServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		id := r.URL.Query().Get("id")
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]any{
			"id":         id,
			"role":       "owner",
			"kyc_status": "approved",
			"is_active":  true,
			"tenant_id":  id,
		})
	}))
	defer mockAuthServer.Close()

	cfg := &config.Config{
		AuthServiceURL:       mockAuthServer.URL,
		InternalServiceToken: "mock-internal-token",
		AppEnv:               "test",
	}
	mr := miniredis.RunT(t)
	if mr == nil {
		t.Fatal("miniredis unavailable")
	}
	defer mr.Close()
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	u := NewUserService(s, cfg, rdb)

	ownerID := "reprice-owner-1"
	custID := "reprice-customer-1"
	serviceID := "reprice-svc-1"

	tokenOwner, _ := jwtutil.GenerateToken(ownerID, "owner", ownerID, "reprice-owner@example.com")
	tokenEmp, _ := jwtutil.GenerateToken("reprice-employee-1", "employee", ownerID, "reprice-emp@example.com")

	s.CreateService(ctx, &models.Service{
		ID: serviceID, TenantID: ownerID,
		TenantBasePrice: 1.0, TenantPricePerKM: 0.1, // prices ALREADY lowered post-booking
		Latitude: 30.0, Longitude: 30.0,
	})
	_ = s.Deposit(ctx, ownerID, 500.0)

	lockedComplete := 155.60
	jobComplete := &models.Job{
		ID: "job-reprice-complete", OwnerID: ownerID, UserID: custID,
		EmployeeID: "reprice-employee-1", ServiceID: serviceID,
		Status: models.JobStatusActive, PaymentMethod: "wallet",
		LockedEscrowAmount: lockedComplete,
		Location:           models.Location{Latitude: 30.05, Longitude: 30.05}, // recompute would be ~1.56 << locked
		CreatedAt:          time.Now().Add(-1 * time.Hour),
	}
	_ = s.CreateJob(ctx, jobComplete)
	if err := s.LockEscrow(ctx, ownerID, jobComplete.ID, lockedComplete); err != nil {
		t.Fatalf("escrow lock setup failed: %v", err)
	}
	walAfterLock := s.GetWallet(ctx, ownerID)

	// --- CompleteJob must release exactly LockedEscrowAmount ---
	reqBody, _ := json.Marshal(map[string]any{"job_id": jobComplete.ID, "requester_id": tokenEmp})
	req := httptest.NewRequest("POST", "/users/jobs/complete", bytes.NewReader(reqBody))
	rec := httptest.NewRecorder()
	u.CompleteJob(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK for CompleteJob, got %d. Body: %s", rec.Code, rec.Body.String())
	}
	var resp map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &resp)
	totalAmt, _ := resp["total_amount"].(float64)
	if totalAmt != lockedComplete {
		t.Errorf("Expected completion payout to equal LockedEscrowAmount (%.2f), got %.2f (stranded residual bug?)", lockedComplete, totalAmt)
	}
	walAfterComplete := s.GetWallet(ctx, ownerID)
	if delta := walAfterComplete.WithdrawableBalance - walAfterLock.WithdrawableBalance; math.Abs(delta-lockedComplete) > 0.001 {
		t.Errorf("Expected withdrawable balance to increase by exactly %.2f, got %.2f", lockedComplete, delta)
	}

	lockedCancel := 80.00
	jobCancel := &models.Job{
		ID: "job-reprice-cancel", OwnerID: ownerID, UserID: custID,
		ServiceID: serviceID,
		Status:    models.JobStatusActive, PaymentMethod: "wallet",
		LockedEscrowAmount: lockedCancel,
		Location:           models.Location{Latitude: 30.05, Longitude: 30.05},
		CreatedAt:          time.Now().Add(-1 * time.Hour),
	}
	_ = s.CreateJob(ctx, jobCancel)
	_ = s.LockEscrow(ctx, ownerID, jobCancel.ID, lockedCancel)
	walMid := s.GetWallet(ctx, ownerID)

	// --- CancelJob by owner must refund exactly LockedEscrowAmount ---
	cancelBody, _ := json.Marshal(map[string]any{"job_id": jobCancel.ID, "requester_id": tokenOwner, "reason": "reprice regression cancel"})
	reqCancel := httptest.NewRequest("POST", "/users/jobs/cancel", bytes.NewReader(cancelBody))
	recCancel := httptest.NewRecorder()
	u.CancelJob(recCancel, reqCancel)
	if recCancel.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK for CancelJob, got %d. Body: %s", recCancel.Code, recCancel.Body.String())
	}
	walAfterCancel := s.GetWallet(ctx, ownerID)
	if delta := walAfterCancel.WithdrawableBalance - walMid.WithdrawableBalance; math.Abs(delta-lockedCancel) > 0.001 {
		t.Errorf("Expected refund to increase withdrawable balance by exactly %.2f, got %.2f", lockedCancel, delta)
	}
	if got := s.GetJob(ctx, jobCancel.ID); got.Status != models.JobStatusCancelled {
		t.Errorf("Expected cancelled job status, got %s", got.Status)
	}
}
