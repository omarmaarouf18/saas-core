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

	"github.com/project/shared/infra/jwtutil"
	"github.com/project/user-service/internal/models"
)

// TestPaidTierGatingMatrix verifies the Part A product decision:
// A Free-tier owner account can register and view the services catalog (read-only) — nothing else.
// Every functional/mutating action requires a Paid subscription (PlanPaid) returning HTTP 402 upgrade_required.
func TestPaidTierGatingMatrix(t *testing.T) {
	u, s, _, cleanup := setupDispatchTestHarness(t)
	if u == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()

	freeOwnerID := "free-owner-matrix-1"
	paidOwnerID := "paid-owner-matrix-2"

	// Seed Paid subscription for paidOwnerID
	_ = s.UpsertSubscription(ctx, &models.Subscription{
		ID:        "sub-paid-" + paidOwnerID,
		TenantID:  paidOwnerID,
		Tier:      models.PlanPaid,
		StartedAt: time.Now().UTC(),
	})

	// Seed wallet balances
	_ = s.Deposit(ctx, freeOwnerID, 1000.0)
	_ = s.Deposit(ctx, paidOwnerID, 1000.0)

	freeOwnerToken, _ := jwtutil.GenerateToken(freeOwnerID, "owner", freeOwnerID, "free@matrix.com")
	paidOwnerToken, _ := jwtutil.GenerateToken(paidOwnerID, "owner", paidOwnerID, "paid@matrix.com")
	customerToken, _ := jwtutil.GenerateToken("cust-matrix-user", "user", "", "cust@matrix.com")
	empID := "emp-under-free-owner-matrix-1"
	empToken, _ := jwtutil.GenerateToken(empID, "employee", freeOwnerID, "emp@matrix.com")

	// Pre-create services for both
	freeSvc := &models.Service{
		ID:               "svc-free-matrix",
		TenantID:         freeOwnerID,
		Name:             "Free Owner Logistics",
		Category:         "delivery",
		TenantBasePrice:  20.0,
		TenantPricePerKM: 2.0,
		Latitude:         30.0444,
		Longitude:        31.2357,
	}
	s.CreateService(ctx, freeSvc)

	paidSvc := &models.Service{
		ID:               "svc-paid-matrix",
		TenantID:         paidOwnerID,
		Name:             "Paid Owner Logistics",
		Category:         "delivery",
		TenantBasePrice:  25.0,
		TenantPricePerKM: 2.5,
		Latitude:         30.0444,
		Longitude:        31.2357,
	}
	s.CreateService(ctx, paidSvc)

	// Pre-create jobs for status tests
	activeJobID := "job-active-free-matrix"
	s.CreateJob(ctx, &models.Job{
		ID:                 activeJobID,
		OwnerID:            freeOwnerID,
		UserID:             "cust-matrix-user",
		EmployeeID:         empID,
		ServiceID:          freeSvc.ID,
		Status:             models.JobStatusActive,
		LockedEscrowAmount: 50.0,
		PaymentMethod:      "wallet",
		CreatedAt:          time.Now().UTC(),
	})

	completedJobID := "job-completed-free-matrix"
	s.CreateJob(ctx, &models.Job{
		ID:                 completedJobID,
		OwnerID:            freeOwnerID,
		UserID:             "cust-matrix-user",
		EmployeeID:         empID,
		ServiceID:          freeSvc.ID,
		Status:             models.JobStatusCompleted,
		LockedEscrowAmount: 0,
		PaymentMethod:      "wallet",
		CreatedAt:          time.Now().UTC(),
	})

	reconJobID := "job-recon-free-matrix"
	s.CreateJob(ctx, &models.Job{
		ID:                 reconJobID,
		OwnerID:            freeOwnerID,
		UserID:             "cust-matrix-user",
		EmployeeID:         empID,
		ServiceID:          freeSvc.ID,
		Status:             models.JobStatusEscrowReconciliationRequired,
		LockedEscrowAmount: 50.0,
		PaymentMethod:      "wallet",
		CreatedAt:          time.Now().UTC(),
	})

	// =========================================================================
	// PART 1: Read-Only Endpoints (Free Owner MUST succeed)
	// =========================================================================
	t.Run("Free Owner: Read Catalog GET /users/services (200 OK)", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/users/services", nil)
		rec := httptest.NewRecorder()
		u.ListServices(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK, got %d", rec.Code)
		}
	})

	t.Run("Free Owner: Read Wallet GET /users/wallet (200 OK)", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/users/wallet?tenant_token="+freeOwnerToken, nil)
		rec := httptest.NewRecorder()
		u.GetWallet(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK, got %d", rec.Code)
		}
	})

	t.Run("Free Owner: Read Ledger GET /users/ledger (200 OK)", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/users/ledger?tenant_token="+freeOwnerToken, nil)
		rec := httptest.NewRecorder()
		u.GetLedger(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK, got %d", rec.Code)
		}
	})

	t.Run("Free Owner: Read Jobs GET /users/jobs/owner (200 OK)", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/users/jobs/owner?owner_token="+freeOwnerToken, nil)
		rec := httptest.NewRecorder()
		u.GetOwnerJobs(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK, got %d", rec.Code)
		}
	})

	t.Run("Free Owner: Read Reconciliation Queue GET /users/jobs/reconciliation-queue (200 OK)", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/users/jobs/reconciliation-queue?owner_token="+freeOwnerToken, nil)
		rec := httptest.NewRecorder()
		u.GetReconciliationQueue(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK, got %d", rec.Code)
		}
	})

	t.Run("Free Owner: Read Subscription GET /users/subscription (200 OK)", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/users/subscription?tenant_token="+freeOwnerToken, nil)
		rec := httptest.NewRecorder()
		u.Subscription(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK, got %d", rec.Code)
		}
	})

	// =========================================================================
	// PART 2: Mutating Endpoints (Free Owner MUST be rejected with HTTP 402)
	// =========================================================================

	t.Run("Free Owner: CreateService POST /users/services (402)", func(t *testing.T) {
		body, _ := json.Marshal(map[string]any{
			"owner_token":       freeOwnerToken,
			"name":              "New Free Service",
			"category":          "delivery",
			"tenant_base_price": 15.0,
		})
		req := httptest.NewRequest(http.MethodPost, "/users/services", bytes.NewReader(body))
		rec := httptest.NewRecorder()
		u.CreateService(rec, req)
		if rec.Code != http.StatusPaymentRequired {
			t.Fatalf("Expected 402 Payment Required, got %d. Body: %s", rec.Code, rec.Body.String())
		}
		if !strings.Contains(rec.Body.String(), "upgrade_required") {
			t.Errorf("Expected body to contain 'upgrade_required', got: %s", rec.Body.String())
		}
	})

	t.Run("Free Owner: UpdateService PUT /users/services (402)", func(t *testing.T) {
		body, _ := json.Marshal(map[string]any{
			"id":                freeSvc.ID,
			"owner_token":       freeOwnerToken,
			"name":              "Updated Name",
			"tenant_base_price": 30.0,
		})
		req := httptest.NewRequest(http.MethodPut, "/users/services", bytes.NewReader(body))
		rec := httptest.NewRecorder()
		u.UpdateService(rec, req)
		if rec.Code != http.StatusPaymentRequired {
			t.Fatalf("Expected 402 Payment Required, got %d. Body: %s", rec.Code, rec.Body.String())
		}
		if !strings.Contains(rec.Body.String(), "upgrade_required") {
			t.Errorf("Expected body to contain 'upgrade_required', got: %s", rec.Body.String())
		}
	})

	t.Run("Free Owner: WalletDeposit POST /users/wallet/deposit (402)", func(t *testing.T) {
		body, _ := json.Marshal(map[string]any{
			"tenant_token": freeOwnerToken,
			"amount":       100.0,
		})
		req := httptest.NewRequest(http.MethodPost, "/users/wallet/deposit", bytes.NewReader(body))
		rec := httptest.NewRecorder()
		u.WalletDeposit(rec, req)
		if rec.Code != http.StatusPaymentRequired {
			t.Fatalf("Expected 402 Payment Required, got %d. Body: %s", rec.Code, rec.Body.String())
		}
		if !strings.Contains(rec.Body.String(), "upgrade_required") {
			t.Errorf("Expected body to contain 'upgrade_required', got: %s", rec.Body.String())
		}
	})

	t.Run("Free Owner: RequestPayout POST /users/wallet/payout/request (402)", func(t *testing.T) {
		body, _ := json.Marshal(map[string]any{
			"amount":          50.0,
			"payout_method":   "bank_transfer",
			"account_details": "IBAN EG1234567890",
		})
		req := httptest.NewRequest(http.MethodPost, "/users/wallet/payout/request", bytes.NewReader(body))
		req.Header.Set("Authorization", "Bearer "+freeOwnerToken)
		rec := httptest.NewRecorder()
		u.RequestPayout(rec, req)
		if rec.Code != http.StatusPaymentRequired {
			t.Fatalf("Expected 402 Payment Required, got %d. Body: %s", rec.Code, rec.Body.String())
		}
		if !strings.Contains(rec.Body.String(), "upgrade_required") {
			t.Errorf("Expected body to contain 'upgrade_required', got: %s", rec.Body.String())
		}
	})

	t.Run("Free Owner: ResolveReconciliation POST /users/jobs/reconciliation-resolve (402)", func(t *testing.T) {
		body, _ := json.Marshal(map[string]any{
			"job_id":          reconJobID,
			"decision":        "release_to_employee",
			"requester_token": freeOwnerToken,
		})
		req := httptest.NewRequest(http.MethodPost, "/users/jobs/reconciliation-resolve", bytes.NewReader(body))
		rec := httptest.NewRecorder()
		u.ResolveReconciliation(rec, req)
		if rec.Code != http.StatusPaymentRequired {
			t.Fatalf("Expected 402 Payment Required, got %d. Body: %s", rec.Code, rec.Body.String())
		}
		if !strings.Contains(rec.Body.String(), "upgrade_required") {
			t.Errorf("Expected body to contain 'upgrade_required', got: %s", rec.Body.String())
		}
	})

	t.Run("Free Owner: TrackJob with owner token POST /users/jobs/track (402)", func(t *testing.T) {
		body, _ := json.Marshal(map[string]any{
			"owner_token":    freeOwnerToken,
			"user_token":     customerToken,
			"service_id":     freeSvc.ID,
			"payment_method": "cod",
			"location":       models.Location{Latitude: 30.0, Longitude: 31.0},
		})
		req := httptest.NewRequest(http.MethodPost, "/users/jobs/track", bytes.NewReader(body))
		rec := httptest.NewRecorder()
		u.TrackJob(rec, req)
		if rec.Code != http.StatusPaymentRequired {
			t.Fatalf("Expected 402 Payment Required, got %d. Body: %s", rec.Code, rec.Body.String())
		}
		if !strings.Contains(rec.Body.String(), "upgrade_required") {
			t.Errorf("Expected body to contain 'upgrade_required', got: %s", rec.Body.String())
		}
	})

	t.Run("Free Owner: CompleteJob POST /users/jobs/complete (402)", func(t *testing.T) {
		body, _ := json.Marshal(map[string]any{
			"job_id":          activeJobID,
			"requester_token": freeOwnerToken,
		})
		req := httptest.NewRequest(http.MethodPost, "/users/jobs/complete", bytes.NewReader(body))
		rec := httptest.NewRecorder()
		u.CompleteJob(rec, req)
		if rec.Code != http.StatusPaymentRequired {
			t.Fatalf("Expected 402 Payment Required, got %d. Body: %s", rec.Code, rec.Body.String())
		}
		if !strings.Contains(rec.Body.String(), "upgrade_required") {
			t.Errorf("Expected body to contain 'upgrade_required', got: %s", rec.Body.String())
		}
	})

	t.Run("Free Owner: CancelJob POST /users/jobs/cancel (402)", func(t *testing.T) {
		body, _ := json.Marshal(map[string]any{
			"job_id":          activeJobID,
			"reason":          "Owner cancellation attempt",
			"requester_token": freeOwnerToken,
		})
		req := httptest.NewRequest(http.MethodPost, "/users/jobs/cancel", bytes.NewReader(body))
		rec := httptest.NewRecorder()
		u.CancelJob(rec, req)
		if rec.Code != http.StatusPaymentRequired {
			t.Fatalf("Expected 402 Payment Required, got %d. Body: %s", rec.Code, rec.Body.String())
		}
		if !strings.Contains(rec.Body.String(), "upgrade_required") {
			t.Errorf("Expected body to contain 'upgrade_required', got: %s", rec.Body.String())
		}
	})

	t.Run("Free Owner: RateJob POST /users/jobs/rate (402)", func(t *testing.T) {
		body, _ := json.Marshal(map[string]any{
			"job_id":           completedJobID,
			"rated_by_token":   freeOwnerToken,
			"rated_user_token": empToken,
			"stars":            5,
			"comment":          "Good job",
		})
		req := httptest.NewRequest(http.MethodPost, "/users/jobs/rate", bytes.NewReader(body))
		rec := httptest.NewRecorder()
		u.RateJob(rec, req)
		if rec.Code != http.StatusPaymentRequired {
			t.Fatalf("Expected 402 Payment Required, got %d. Body: %s", rec.Code, rec.Body.String())
		}
		if !strings.Contains(rec.Body.String(), "upgrade_required") {
			t.Errorf("Expected body to contain 'upgrade_required', got: %s", rec.Body.String())
		}
	})

	t.Run("Free Owner: Internal Subscription Check GET /users/subscription/internal (402)", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/users/subscription/internal?tenant_id="+freeOwnerID, nil)
		req.Header.Set("X-Internal-Token", "mock-internal-token")
		rec := httptest.NewRecorder()
		u.InternalSubscriptionCheck(rec, req)
		if rec.Code != http.StatusPaymentRequired {
			t.Fatalf("Expected 402 Payment Required, got %d. Body: %s", rec.Code, rec.Body.String())
		}
	})

	// =========================================================================
	// PART 3: Mutating Endpoints (Paid Owner MUST succeed)
	// =========================================================================

	t.Run("Paid Owner: CreateService POST /users/services (201 Created)", func(t *testing.T) {
		body, _ := json.Marshal(map[string]any{
			"owner_token":       paidOwnerToken,
			"name":              "Paid Logistics Service",
			"category":          "transport",
			"tenant_base_price": 50.0,
		})
		req := httptest.NewRequest(http.MethodPost, "/users/services", bytes.NewReader(body))
		rec := httptest.NewRecorder()
		u.CreateService(rec, req)
		if rec.Code != http.StatusCreated {
			t.Fatalf("Expected 201 Created for paid owner, got %d. Body: %s", rec.Code, rec.Body.String())
		}
	})

	t.Run("Paid Owner: UpdateService PUT /users/services (200 OK)", func(t *testing.T) {
		body, _ := json.Marshal(map[string]any{
			"id":                paidSvc.ID,
			"owner_token":       paidOwnerToken,
			"name":              "Paid Logistics Updated",
			"tenant_base_price": 60.0,
		})
		req := httptest.NewRequest(http.MethodPut, "/users/services", bytes.NewReader(body))
		rec := httptest.NewRecorder()
		u.UpdateService(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK for paid owner, got %d. Body: %s", rec.Code, rec.Body.String())
		}
	})

	t.Run("Paid Owner: WalletDeposit POST /users/wallet/deposit (200 OK)", func(t *testing.T) {
		body, _ := json.Marshal(map[string]any{
			"tenant_token": paidOwnerToken,
			"amount":       200.0,
		})
		req := httptest.NewRequest(http.MethodPost, "/users/wallet/deposit", bytes.NewReader(body))
		rec := httptest.NewRecorder()
		u.WalletDeposit(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK for paid owner, got %d. Body: %s", rec.Code, rec.Body.String())
		}
	})

	t.Run("Paid Owner: RequestPayout POST /users/wallet/payout/request (201 Created)", func(t *testing.T) {
		body, _ := json.Marshal(map[string]any{
			"amount":          100.0,
			"payout_method":   "bank_transfer",
			"account_details": "IBAN EG9876543210",
		})
		req := httptest.NewRequest(http.MethodPost, "/users/wallet/payout/request", bytes.NewReader(body))
		req.Header.Set("Authorization", "Bearer "+paidOwnerToken)
		rec := httptest.NewRecorder()
		u.RequestPayout(rec, req)
		if rec.Code != http.StatusCreated {
			t.Fatalf("Expected 201 Created for paid owner, got %d. Body: %s", rec.Code, rec.Body.String())
		}
	})

	t.Run("Paid Owner: Internal Subscription Check GET /users/subscription/internal (200 OK)", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/users/subscription/internal?tenant_id="+paidOwnerID, nil)
		req.Header.Set("X-Internal-Token", "mock-internal-token")
		rec := httptest.NewRecorder()
		u.InternalSubscriptionCheck(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK, got %d. Body: %s", rec.Code, rec.Body.String())
		}
		var resp map[string]any
		json.Unmarshal(rec.Body.Bytes(), &resp)
		if resp["tier"] != "paid" || resp["is_paid"] != true {
			t.Fatalf("Expected tier: paid, is_paid: true, got %v", resp)
		}
	})
}
