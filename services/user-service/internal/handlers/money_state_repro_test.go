package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"github.com/project/shared/infra/jwtutil"
	"github.com/project/user-service/internal/models"
)

// TestRepro_Q3_ReconciliationRelease_ZeroLockedEscrow verifies that resolving escrow reconciliation
// via release_to_employee writes locked_escrow_amount = 0 on the completed job, not the pre-release snapshot amount.
func TestRepro_Q3_ReconciliationRelease_ZeroLockedEscrow(t *testing.T) {
	u, s, _, cleanup := setupDispatchTestHarness(t)
	if u == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	ownerID := "owner-q3-recon"
	jobID := "job-q3-recon"
	empID := "emp-q3-courier"

	_ = s.UpsertSubscription(ctx, &models.Subscription{
		ID:        "sub-" + ownerID,
		TenantID:  ownerID,
		Tier:      models.PlanPaid,
		StartedAt: time.Now().UTC(),
	})

	// Create wallet for owner and deposit funds so escrow release can credit owner
	_ = s.Deposit(ctx, ownerID, 100.0)

	// Lock escrow for the job
	_ = s.LockEscrow(ctx, ownerID, jobID, 50.0)

	// Create a job in escrow_reconciliation_required status with 50.0 locked escrow
	s.CreateJob(ctx, &models.Job{
		ID:                 jobID,
		OwnerID:            ownerID,
		UserID:             "cust-q3",
		EmployeeID:         empID,
		ServiceID:          "svc-q3",
		Status:             models.JobStatusEscrowReconciliationRequired,
		LockedEscrowAmount: 50.0,
		PaymentMethod:      "wallet",
		CreatedAt:          time.Now().UTC(),
	})

	ownerToken, _ := jwtutil.GenerateToken(ownerID, "owner", ownerID, "owner@q3.com")

	body, _ := json.Marshal(map[string]any{
		"job_id":      jobID,
		"decision":    "release_to_employee",
		"owner_token": ownerToken,
	})
	req := httptest.NewRequest(http.MethodPost, "/users/reconciliation/resolve", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+ownerToken)
	rec := httptest.NewRecorder()

	u.ResolveReconciliation(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("ResolveReconciliation failed with status %d: %s", rec.Code, rec.Body.String())
	}

	job := s.GetJob(ctx, jobID)
	if job == nil {
		t.Fatalf("Job %s not found in DB", jobID)
	}

	// Pre-fix: line 195 of reconciliation_handlers.go passed amount (50.0) into UpdateJobReconciliation
	// so job.LockedEscrowAmount remained 50.0 despite funds having already been released.
	// Post-fix: job.LockedEscrowAmount must be 0.0.
	if job.LockedEscrowAmount > 0 {
		t.Errorf("REPRO CONFIRMED Q3: Job %s has phantom locked_escrow_amount=%.2f after reconciliation release (expected 0.0)!", job.ID, job.LockedEscrowAmount)
	} else {
		t.Logf("PASS: Job %s locked_escrow_amount is correctly 0.0 after reconciliation release", job.ID)
	}
}

// TestRepro_Q4_LedgerBalanceAtomicReturnDocument verifies that concurrent ledger writes
// compute BalanceBefore/BalanceAfter from the atomic update's ReturnDocument (After),
// so that the audit trail is strictly continuous and never records stale pre-read balances.
func TestRepro_Q4_LedgerBalanceAtomicReturnDocument(t *testing.T) {
	_, s, _, cleanup := setupDispatchTestHarness(t)
	if s == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	tenantID := "tenant-q4-ledger"

	// Initial deposit of 1000.0
	if err := s.Deposit(ctx, tenantID, 1000.0); err != nil {
		t.Fatalf("Initial deposit failed: %v", err)
	}

	// Launch 5 concurrent LockEscrow calls of 100.0 each
	var wg sync.WaitGroup
	for i := 0; i < 5; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			_ = s.LockEscrow(ctx, tenantID, fmt.Sprintf("job-q4-%d", idx), 100.0)
		}(i)
	}
	wg.Wait()

	txs := s.GetLedger(ctx, tenantID, 50, 0)
	// Sort by timestamp or verify continuity
	// With pre-read: multiple txs record BalanceBefore=1000.0 instead of chaining 1000->900, 900->800, etc.
	balanceBeforeCounts := make(map[float64]int)
	for _, tx := range txs {
		if tx.Type == models.TxEscrowLock {
			balanceBeforeCounts[tx.BalanceBefore]++
			if tx.BalanceBefore-tx.Amount != tx.BalanceAfter {
				t.Errorf("Broken arithmetic on tx %s: Before=%.2f Amount=%.2f After=%.2f", tx.ID, tx.BalanceBefore, tx.Amount, tx.BalanceAfter)
			}
		}
	}
	for bal, count := range balanceBeforeCounts {
		if count > 1 {
			t.Errorf("REPRO CONFIRMED Q4: %d concurrent lock transactions recorded identical stale BalanceBefore=%.2f (audit chain broken)!", count, bal)
		}
	}
}

// TestRepro_Q6_JobStatusCAS_GuardsBypass verifies that UpdateJobStatus and UpdateJobReconciliation
// enforce CAS status checks and reject illegal status transitions.
func TestRepro_Q6_JobStatusCAS_GuardsBypass(t *testing.T) {
	_, s, _, cleanup := setupDispatchTestHarness(t)
	if s == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	jobID := "job-q6-cas"

	s.CreateJob(ctx, &models.Job{
		ID:        jobID,
		OwnerID:   "owner-q6",
		UserID:    "cust-q6",
		ServiceID: "svc-q6",
		Status:    models.JobStatusCancelled, // Terminal status
		CreatedAt: time.Now().UTC(),
	})

	// 1. Attempt UpdateJobStatus on a cancelled job -> must fail
	errStatus := s.UpdateJobStatus(ctx, jobID, models.JobStatusCompleted)
	if errStatus == nil {
		t.Errorf("REPRO CONFIRMED Q6: UpdateJobStatus succeeded on a CANCELLED job without status CAS check!")
	} else {
		t.Logf("PASS: UpdateJobStatus rejected transition on cancelled job: %v", errStatus)
	}

	// 2. Attempt UpdateJobReconciliation (setting completed) on an active or cancelled job (not in reconciliation) -> must fail
	errRecon := s.UpdateJobReconciliation(ctx, jobID, models.JobStatusCompleted, "test note", "", 0)
	if errRecon == nil {
		t.Errorf("REPRO CONFIRMED Q6: UpdateJobReconciliation succeeded on a CANCELLED job without status CAS check!")
	} else {
		t.Logf("PASS: UpdateJobReconciliation rejected transition on non-reconciliation job: %v", errRecon)
	}
}

// TestRepro_Q9_ConcurrentUpsertSubscription_NoDuplicateKey verifies that concurrent UpsertSubscription
// calls for a new tenant do not encounter duplicate key errors or clobber each other.
func TestRepro_Q9_ConcurrentUpsertSubscription_NoDuplicateKey(t *testing.T) {
	_, s, _, cleanup := setupDispatchTestHarness(t)
	if s == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	tenantID := "tenant-q9-upsert"

	var wg sync.WaitGroup
	errCh := make(chan error, 10)

	for i := 0; i < 10; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			sub := &models.Subscription{
				TenantID: tenantID,
				Tier:     models.PlanPaid,
				Reason:   fmt.Sprintf("activation-%d", idx),
			}
			if err := s.UpsertSubscription(ctx, sub); err != nil {
				errCh <- err
			}
		}(i)
	}
	wg.Wait()
	close(errCh)

	var errs []error
	for err := range errCh {
		errs = append(errs, err)
	}

	if len(errs) > 0 {
		t.Errorf("REPRO CONFIRMED Q9: Concurrent UpsertSubscription hit %d errors (e.g. %v)", len(errs), errs[0])
	} else {
		t.Logf("PASS: All concurrent UpsertSubscription calls succeeded")
	}

	sub := s.GetSubscription(ctx, tenantID)
	if sub == nil {
		t.Fatalf("Failed to retrieve subscription: not found")
	}
	if sub.Tier != models.PlanPaid {
		t.Errorf("Expected tier %s, got %s", models.PlanPaid, sub.Tier)
	}
}

// TestRepro_Q10_UpdateService_ConcurrentFieldLevelClobber verifies that UpdateService
// updates only non-nil fields without clobbering concurrent updates to other fields.
func TestRepro_Q10_UpdateService_ConcurrentFieldLevelClobber(t *testing.T) {
	u, s, _, cleanup := setupDispatchTestHarness(t)
	if u == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	ownerID := "owner-q10"
	svcID := "svc-q10"

	_ = s.UpsertSubscription(ctx, &models.Subscription{
		ID:        "sub-" + ownerID,
		TenantID:  ownerID,
		Tier:      models.PlanPaid,
		StartedAt: time.Now().UTC(),
	})

	s.CreateService(ctx, &models.Service{
		ID:               svcID,
		TenantID:         ownerID,
		Name:             "Initial Name",
		Address:          "Initial Address",
		TenantBasePrice:  20.0,
		TenantPricePerKM: 2.0,
		Latitude:         30.0,
		Longitude:        31.0,
	})

	ownerToken, _ := jwtutil.GenerateToken(ownerID, "owner", ownerID, "owner@q10.com")

	// Simulate concurrent requests:
	// Both requests read the service concurrently before either commits.
	// Request 1 updates Address.
	// Request 2 updates TenantBasePrice.
	// In the pre-fix implementation, UpdateService does bson.M{"$set": svc} with the whole struct,
	// so whichever write finishes last overwrites the other field with its stale snapshot.
	newAddr := "New Address 123"
	newPrice := 50.0

	var wg sync.WaitGroup
	wg.Add(2)

	go func() {
		defer wg.Done()
		body1, _ := json.Marshal(models.UpdateServiceRequest{
			ID:         svcID,
			OwnerID:    ownerID,
			OwnerToken: ownerToken,
			Address:    &newAddr,
		})
		req1 := httptest.NewRequest(http.MethodPut, "/users/services", bytes.NewReader(body1))
		req1.Header.Set("Authorization", "Bearer "+ownerToken)
		rec1 := httptest.NewRecorder()
		u.UpdateService(rec1, req1)
	}()

	go func() {
		defer wg.Done()
		body2, _ := json.Marshal(models.UpdateServiceRequest{
			ID:              svcID,
			OwnerID:         ownerID,
			OwnerToken:      ownerToken,
			TenantBasePrice: &newPrice,
		})
		req2 := httptest.NewRequest(http.MethodPut, "/users/services", bytes.NewReader(body2))
		req2.Header.Set("Authorization", "Bearer "+ownerToken)
		rec2 := httptest.NewRecorder()
		u.UpdateService(rec2, req2)
	}()

	wg.Wait()

	// Verify both changes are preserved in the DB
	svc := s.GetServiceByID(ctx, svcID)
	if svc == nil {
		t.Fatalf("Service not found")
	}

	if svc.Address != newAddr || svc.TenantBasePrice != newPrice {
		t.Errorf("REPRO CONFIRMED Q10: Concurrent field update clobbered! Address=%q (want %q), TenantBasePrice=%.2f (want %.2f)", svc.Address, newAddr, svc.TenantBasePrice, newPrice)
	} else {
		t.Logf("PASS: Both Address (%s) and TenantBasePrice (%.2f) preserved", svc.Address, svc.TenantBasePrice)
	}
}
