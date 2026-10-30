package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/project/user-service/internal/models"
)

func TestAdminJobActions_Cancel_ValidationAndAuth(t *testing.T) {
	svc, _, validToken := setupAdminJobsTestEnv(t)
	if svc == nil {
		return
	}

	mux := http.NewServeMux()
	svc.RegisterRoutes(mux)

	// 1. Missing auth
	reqBody, _ := json.Marshal(map[string]any{
		"job_id": "job-1",
		"reason": "Customer called to cancel",
	})
	req := httptest.NewRequest(http.MethodPost, "/admin/jobs/cancel", bytes.NewReader(reqBody))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 without auth, got %d", rec.Code)
	}

	// 2. Invalid method
	req = httptest.NewRequest(http.MethodGet, "/admin/jobs/cancel", nil)
	req.Header.Set("X-Internal-Token", "test-internal-token")
	req.Header.Set("X-Reviewer-Token", validToken)
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("expected 405 for GET on cancel, got %d", rec.Code)
	}

	// 3. Missing reason
	reqBody, _ = json.Marshal(map[string]any{
		"job_id": "job-1",
		"reason": "",
	})
	req = httptest.NewRequest(http.MethodPost, "/admin/jobs/cancel", bytes.NewReader(reqBody))
	req.Header.Set("X-Internal-Token", "test-internal-token")
	req.Header.Set("X-Reviewer-Token", validToken)
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for empty reason, got %d", rec.Code)
	}

	// 4. Reason > 1000 characters
	longReason := strings.Repeat("A", 1001)
	reqBody, _ = json.Marshal(map[string]any{
		"job_id": "job-1",
		"reason": longReason,
	})
	req = httptest.NewRequest(http.MethodPost, "/admin/jobs/cancel", bytes.NewReader(reqBody))
	req.Header.Set("X-Internal-Token", "test-internal-token")
	req.Header.Set("X-Reviewer-Token", validToken)
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for >1000 chars reason, got %d", rec.Code)
	}

	// 5. Attempting to edit price or address
	reqBody, _ = json.Marshal(map[string]any{
		"job_id": "job-1",
		"reason": "Legitimate reason",
		"price":  150.0,
	})
	req = httptest.NewRequest(http.MethodPost, "/admin/jobs/cancel", bytes.NewReader(reqBody))
	req.Header.Set("X-Internal-Token", "test-internal-token")
	req.Header.Set("X-Reviewer-Token", validToken)
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 when attempting to edit price, got %d", rec.Code)
	}

	// 6. Job not found
	reqBody, _ = json.Marshal(map[string]any{
		"job_id": "non-existent-job-id",
		"reason": "Customer cancellation",
	})
	req = httptest.NewRequest(http.MethodPost, "/admin/jobs/cancel", bytes.NewReader(reqBody))
	req.Header.Set("X-Internal-Token", "test-internal-token")
	req.Header.Set("X-Reviewer-Token", validToken)
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404 for non-existent job, got %d", rec.Code)
	}
}

func TestAdminJobActions_Cancel_Execution(t *testing.T) {
	svc, mongoStore, validToken := setupAdminJobsTestEnv(t)
	if svc == nil {
		return
	}

	ctx := context.Background()
	mux := http.NewServeMux()
	svc.RegisterRoutes(mux)

	// Create test service
	testSvc := models.Service{
		ID:               "svc-cancel-test",
		TenantID:         "tenant-owner-1",
		Name:             "Express Delivery",
		TenantBasePrice:  20.0,
		TenantPricePerKM: 5.0,
	}
	if err := mongoStore.CreateService(ctx, &testSvc); err != nil {
		t.Fatalf("failed to create service: %v", err)
	}

	// 1. Create a completed job and verify 409 conflict
	completedJob := models.Job{
		ID:            "job-completed-test",
		OwnerID:       "tenant-owner-1",
		UserID:        "user-cust-1",
		ServiceID:     testSvc.ID,
		Status:        models.JobStatusCompleted,
		PaymentMethod: "cod",
		CreatedAt:     time.Now().UTC(),
		UpdatedAt:     time.Now().UTC(),
	}
	if err := mongoStore.CreateJob(ctx, &completedJob); err != nil {
		t.Fatalf("failed to create job: %v", err)
	}

	reqBody, _ := json.Marshal(map[string]any{
		"reason": "Admin cancel attempt on completed job",
	})
	req := httptest.NewRequest(http.MethodPost, "/admin/jobs/job-completed-test/cancel", bytes.NewReader(reqBody))
	req.Header.Set("X-Internal-Token", "test-internal-token")
	req.Header.Set("X-Reviewer-Token", validToken)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusConflict {
		t.Fatalf("expected 409 conflict when cancelling completed job, got %d", rec.Code)
	}

	// 2. Create an active COD job and cancel it
	activeCODJob := models.Job{
		ID:            "job-active-cod-test",
		OwnerID:       "tenant-owner-1",
		UserID:        "user-cust-1",
		EmployeeID:    "driver-emp-1",
		ServiceID:     testSvc.ID,
		Status:        models.JobStatusActive,
		PaymentMethod: "cod",
		CreatedAt:     time.Now().UTC(),
		UpdatedAt:     time.Now().UTC(),
	}
	if err := mongoStore.CreateJob(ctx, &activeCODJob); err != nil {
		t.Fatalf("failed to create job: %v", err)
	}

	reqBody, _ = json.Marshal(map[string]any{
		"reason": "Driver vehicle broke down, requested cancel",
	})
	req = httptest.NewRequest(http.MethodPost, "/admin/jobs/job-active-cod-test/cancel", bytes.NewReader(reqBody))
	req.Header.Set("X-Internal-Token", "test-internal-token")
	req.Header.Set("X-Reviewer-Token", validToken)
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 on cancel active COD job, got %d: %s", rec.Code, rec.Body.String())
	}

	// Verify job status in DB
	updatedJob := mongoStore.GetJob(ctx, "job-active-cod-test")
	if updatedJob.Status != models.JobStatusCancelled {
		t.Fatalf("expected job status cancelled, got %s", updatedJob.Status)
	}
	if len(updatedJob.StatusHistory) == 0 {
		t.Fatalf("expected status history entry to be appended")
	}
	lastHistory := updatedJob.StatusHistory[len(updatedJob.StatusHistory)-1]
	if lastHistory.ActorRole != models.ActorRoleAdmin {
		t.Errorf("expected actor role admin, got %s", lastHistory.ActorRole)
	}
	if lastHistory.Reason != "Driver vehicle broke down, requested cancel" {
		t.Errorf("unexpected history reason: %s", lastHistory.Reason)
	}

	// 3. Create a funded job with locked escrow and cancel it
	// Seed wallet with withdrawable and escrow balance
	ownerWallet, err := mongoStore.GetOrCreateWallet(ctx, "tenant-owner-funded")
	if err != nil {
		t.Fatalf("failed to get wallet: %v", err)
	}
	_ = ownerWallet
	// Credit and lock escrow for job
	if err := mongoStore.Deposit(ctx, "tenant-owner-funded", 100.0); err != nil {
		t.Fatalf("failed to credit wallet: %v", err)
	}
	if err := mongoStore.LockEscrow(ctx, "tenant-owner-funded", "job-funded-test", 50.0); err != nil {
		t.Fatalf("failed to lock escrow: %v", err)
	}

	fundedJob := models.Job{
		ID:                 "job-funded-test",
		OwnerID:            "tenant-owner-funded",
		UserID:             "user-cust-2",
		ServiceID:          testSvc.ID,
		Status:             models.JobStatusActive,
		PaymentMethod:      "wallet",
		LockedEscrowAmount: 50.0,
		CreatedAt:          time.Now().UTC(),
		UpdatedAt:          time.Now().UTC(),
	}
	if err := mongoStore.CreateJob(ctx, &fundedJob); err != nil {
		t.Fatalf("failed to create job: %v", err)
	}

	reqBody, _ = json.Marshal(map[string]any{
		"reason": "Escrow refund test by admin",
	})
	req = httptest.NewRequest(http.MethodPost, "/users/admin/jobs/job-funded-test/cancel", bytes.NewReader(reqBody))
	req.Header.Set("X-Internal-Token", "test-internal-token")
	req.Header.Set("X-Reviewer-Token", validToken)
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 on cancel funded job, got %d: %s", rec.Code, rec.Body.String())
	}

	// Verify escrow was refunded back to wallet
	walletAfter, err := mongoStore.GetOrCreateWallet(ctx, "tenant-owner-funded")
	if err != nil {
		t.Fatalf("failed to get wallet after: %v", err)
	}
	if walletAfter.EscrowBalance != 0.0 {
		t.Errorf("expected escrow balance 0 after refund, got %.2f", walletAfter.EscrowBalance)
	}
	if walletAfter.WithdrawableBalance != 100.0 {
		t.Errorf("expected withdrawable balance 100 after refund, got %.2f", walletAfter.WithdrawableBalance)
	}
}

func TestAdminJobActions_CompleteStuckCOD(t *testing.T) {
	svc, mongoStore, validToken := setupAdminJobsTestEnv(t)
	if svc == nil {
		return
	}

	ctx := context.Background()
	mux := http.NewServeMux()
	svc.RegisterRoutes(mux)

	// Create test service
	testSvc := models.Service{
		ID:               "svc-stuck-cod",
		TenantID:         "tenant-owner-stuck",
		Name:             "COD Transport",
		TenantBasePrice:  25.0,
		TenantPricePerKM: 2.0,
	}
	if err := mongoStore.CreateService(ctx, &testSvc); err != nil {
		t.Fatalf("failed to create service: %v", err)
	}

	// 1. Non-COD job -> 409 conflict
	nonCODJob := models.Job{
		ID:            "job-non-cod-reconcile",
		OwnerID:       "tenant-owner-stuck",
		UserID:        "user-cust-1",
		ServiceID:     testSvc.ID,
		Status:        models.JobStatusEscrowReconciliationRequired,
		PaymentMethod: "wallet",
		CreatedAt:     time.Now().UTC(),
		UpdatedAt:     time.Now().UTC(),
	}
	if err := mongoStore.CreateJob(ctx, &nonCODJob); err != nil {
		t.Fatalf("failed to create job: %v", err)
	}

	reqBody, _ := json.Marshal(map[string]any{
		"reason": "Complete stuck COD attempt on non-COD job",
	})
	req := httptest.NewRequest(http.MethodPost, "/admin/jobs/job-non-cod-reconcile/complete-stuck-cod", bytes.NewReader(reqBody))
	req.Header.Set("X-Internal-Token", "test-internal-token")
	req.Header.Set("X-Reviewer-Token", validToken)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusConflict {
		t.Fatalf("expected 409 conflict for non-COD job, got %d", rec.Code)
	}

	// 2. COD job not in escrow_reconciliation_required -> 409 conflict
	activeCOD := models.Job{
		ID:            "job-active-cod-not-stuck",
		OwnerID:       "tenant-owner-stuck",
		UserID:        "user-cust-1",
		ServiceID:     testSvc.ID,
		Status:        models.JobStatusActive,
		PaymentMethod: "cod",
		CreatedAt:     time.Now().UTC(),
		UpdatedAt:     time.Now().UTC(),
	}
	if err := mongoStore.CreateJob(ctx, &activeCOD); err != nil {
		t.Fatalf("failed to create job: %v", err)
	}

	req = httptest.NewRequest(http.MethodPost, "/admin/jobs/job-active-cod-not-stuck/complete-stuck-cod", bytes.NewReader(reqBody))
	req.Header.Set("X-Internal-Token", "test-internal-token")
	req.Header.Set("X-Reviewer-Token", validToken)
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusConflict {
		t.Fatalf("expected 409 conflict for job not in escrow_reconciliation_required, got %d", rec.Code)
	}

	// 3. Genuine stuck COD job (FIX-COD-RECON scenario)
	agreedPrice := 45.0
	stuckCODJob := models.Job{
		ID:                  "job-stuck-cod-legit",
		OwnerID:             "tenant-owner-stuck",
		UserID:              "user-cust-1",
		EmployeeID:          "emp-driver-99",
		ServiceID:           testSvc.ID,
		Status:              models.JobStatusEscrowReconciliationRequired,
		PaymentMethod:       "cod",
		EscrowFailureReason: "under_distance_mismatch",
		ReconciliationNote:  "tracked_distance_mismatch: actual 2.50 km vs booked 10.00 km",
		BookedDistance:      10.0,
		AgreedPrice:         &agreedPrice,
		CreatedAt:           time.Now().UTC(),
		UpdatedAt:           time.Now().UTC(),
	}
	if err := mongoStore.CreateJob(ctx, &stuckCODJob); err != nil {
		t.Fatalf("failed to create job: %v", err)
	}

	reqBody, _ = json.Marshal(map[string]any{
		"reason": "Reviewed courier tracking and confirmed COD cash collection with recipient",
	})
	req = httptest.NewRequest(http.MethodPost, "/users/admin/jobs/job-stuck-cod-legit/complete-stuck-cod", bytes.NewReader(reqBody))
	req.Header.Set("X-Internal-Token", "test-internal-token")
	req.Header.Set("X-Reviewer-Token", validToken)
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 on complete stuck COD job, got %d: %s", rec.Code, rec.Body.String())
	}

	var resp struct {
		Success          bool    `json:"success"`
		JobID            string  `json:"job_id"`
		Status           string  `json:"status"`
		ActualCashAmount float64 `json:"actual_cash_amount"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to parse response JSON: %v", err)
	}
	if !resp.Success || resp.Status != "completed" || resp.ActualCashAmount != 45.0 {
		t.Errorf("unexpected response: %+v", resp)
	}

	// Verify in database
	dbJob := mongoStore.GetJob(ctx, "job-stuck-cod-legit")
	if dbJob.Status != models.JobStatusCompleted {
		t.Errorf("expected job status completed, got %s", dbJob.Status)
	}
	if dbJob.ActualCashAmount == nil || *dbJob.ActualCashAmount != 45.0 {
		t.Errorf("expected actual_cash_amount 45.0, got %v", dbJob.ActualCashAmount)
	}
	if dbJob.DistanceReview == nil || dbJob.DistanceReview.Source != models.DistanceReviewSourceRepair {
		t.Errorf("expected distance_review source repair, got %v", dbJob.DistanceReview)
	}
	if len(dbJob.StatusHistory) == 0 {
		t.Fatalf("expected status history")
	}
	lastHist := dbJob.StatusHistory[len(dbJob.StatusHistory)-1]
	if lastHist.Status != models.JobStatusCompleted || lastHist.ActorRole != models.ActorRoleAdmin {
		t.Errorf("unexpected history entry: %+v", lastHist)
	}
}
