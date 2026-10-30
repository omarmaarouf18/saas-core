package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"github.com/project/user-service/internal/config"
	"github.com/project/user-service/internal/models"
	"github.com/project/user-service/internal/store"
)

func setupAdminOverviewTestEnv(t *testing.T, authFail, chatFail bool) (*UserService, *store.MongoDB, string) {
	t.Helper()

	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://root:devpassword123@localhost:27017/saas_platform?authSource=admin"
	}
	dbName := fmt.Sprintf("saas_user_overview_test_%d", time.Now().UnixNano())
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	mongoStore, err := store.NewMongoDB(ctx, mongoURI, dbName)
	if err != nil {
		t.Skipf("Skipping admin overview test: MongoDB not available (%v)", err)
		return nil, nil, ""
	}

	validReviewerToken := "valid-reviewer-token"

	// Mock Auth Service
	mockAuthServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		internalTok := r.Header.Get("X-Internal-Token")
		if internalTok != "test-internal-token" {
			w.WriteHeader(http.StatusForbidden)
			_, _ = w.Write([]byte(`{"error":"invalid internal token"}`))
			return
		}

		if r.URL.Path == "/auth/reviewer/verify" {
			revTok := r.Header.Get("X-Reviewer-Token")
			if revTok == validReviewerToken {
				w.WriteHeader(http.StatusOK)
				_, _ = w.Write([]byte(`{"id":"reviewer-overview-admin","name":"Overview Admin"}`))
				return
			}
			w.WriteHeader(http.StatusUnauthorized)
			_, _ = w.Write([]byte(`{"error":"invalid reviewer token"}`))
			return
		}

		if r.URL.Path == "/auth/internal/overview-stats" {
			if authFail {
				w.WriteHeader(http.StatusInternalServerError)
				_, _ = w.Write([]byte(`{"error":"upstream db failure"}`))
				return
			}
			w.WriteHeader(http.StatusOK)
			_ = json.NewEncoder(w).Encode(map[string]int64{
				"pending_kyb_kye":    7,
				"new_accounts_today": 3,
				"new_accounts_7d":    14,
				"suspended_accounts": 2,
			})
			return
		}

		w.WriteHeader(http.StatusNotFound)
	}))

	// Mock Chat Service
	mockChatServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		internalTok := r.Header.Get("X-Internal-Token")
		if internalTok != "test-internal-token" {
			w.WriteHeader(http.StatusForbidden)
			_, _ = w.Write([]byte(`{"error":"invalid internal token"}`))
			return
		}

		if r.URL.Path == "/chat/internal/overview-stats" {
			if chatFail {
				w.WriteHeader(http.StatusServiceUnavailable)
				_, _ = w.Write([]byte(`{"error":"service unavailable"}`))
				return
			}
			w.WriteHeader(http.StatusOK)
			_ = json.NewEncoder(w).Encode(map[string]int64{
				"open_tickets":     5,
				"assigned_tickets": 2,
			})
			return
		}

		w.WriteHeader(http.StatusNotFound)
	}))

	t.Cleanup(func() {
		mockAuthServer.Close()
		mockChatServer.Close()
		dropCtx, dropCancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer dropCancel()
		_ = mongoStore.DropDatabase(dropCtx)
		_ = mongoStore.Close(dropCtx)
	})

	cfg := &config.Config{
		InternalServiceToken: "test-internal-token",
		AuthServiceURL:       mockAuthServer.URL,
		ChatServiceURL:       mockChatServer.URL,
	}

	svc := NewUserService(mongoStore, cfg, nil)
	return svc, mongoStore, validReviewerToken
}

func TestAdminOverview_Authentication(t *testing.T) {
	svc, _, validToken := setupAdminOverviewTestEnv(t, false, false)
	if svc == nil {
		return
	}

	t.Run("Missing Internal Token", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/admin/overview", nil)
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		svc.AdminOverview(rec, req)
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("expected 401 Unauthorized, got %d", rec.Code)
		}
	})

	t.Run("Missing Reviewer Token", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/admin/overview", nil)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		rec := httptest.NewRecorder()
		svc.AdminOverview(rec, req)
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("expected 401 Unauthorized, got %d", rec.Code)
		}
	})

	t.Run("Invalid Reviewer Token", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/admin/overview", nil)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", "invalid-token")
		rec := httptest.NewRecorder()
		svc.AdminOverview(rec, req)
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("expected 401 Unauthorized, got %d", rec.Code)
		}
	})

	t.Run("Method Not Allowed", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodPost, "/admin/overview", nil)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		svc.AdminOverview(rec, req)
		if rec.Code != http.StatusMethodNotAllowed {
			t.Errorf("expected 405 Method Not Allowed, got %d", rec.Code)
		}
	})
}

func TestAdminOverview_Aggregation_Success(t *testing.T) {
	svc, mongoStore, validToken := setupAdminOverviewTestEnv(t, false, false)
	if svc == nil {
		return
	}
	ctx := context.Background()
	now := time.Now().UTC()

	// 1. Seed pending_payment subscriptions
	_ = mongoStore.UpsertSubscription(ctx, &models.Subscription{
		ID:        "sub-pending-1",
		TenantID:  "tenant-alpha",
		Tier:      models.PlanPendingPayment,
		StartedAt: now,
	})
	_ = mongoStore.UpsertSubscription(ctx, &models.Subscription{
		ID:        "sub-pending-2",
		TenantID:  "tenant-beta",
		Tier:      models.PlanPendingPayment,
		StartedAt: now,
	})
	_ = mongoStore.UpsertSubscription(ctx, &models.Subscription{
		ID:        "sub-paid",
		TenantID:  "tenant-gamma",
		Tier:      models.PlanPaid,
		StartedAt: now,
	})

	// 2. Seed GPS disputes & stuck COD jobs
	// Normal GPS dispute with escrow
	_ = mongoStore.CreateJob(ctx, &models.Job{
		ID:                 "job-dispute-1",
		OwnerID:            "tenant-alpha",
		UserID:             "cust-1",
		Status:             models.JobStatusEscrowReconciliationRequired,
		PaymentMethod:      "wallet",
		LockedEscrowAmount: 150.0,
		CreatedAt:          now,
	})
	// Stuck COD jobs (FIX-COD-RECON definition: payment_method=cod, status=escrow_reconciliation_required, locked_escrow<=0)
	_ = mongoStore.CreateJob(ctx, &models.Job{
		ID:                  "job-stuck-cod-1",
		OwnerID:             "tenant-alpha",
		UserID:              "cust-2",
		Status:              models.JobStatusEscrowReconciliationRequired,
		PaymentMethod:       "cod",
		LockedEscrowAmount:  0,
		EscrowFailureReason: "under_distance_mismatch",
		CreatedAt:           now,
	})
	_ = mongoStore.CreateJob(ctx, &models.Job{
		ID:                  "job-stuck-cod-2",
		OwnerID:             "tenant-beta",
		UserID:              "cust-3",
		Status:              models.JobStatusEscrowReconciliationRequired,
		PaymentMethod:       "cod",
		LockedEscrowAmount:  0,
		EscrowFailureReason: "under_distance_mismatch",
		CreatedAt:           now,
	})

	// 3. Seed other jobs today by status
	_ = mongoStore.CreateJob(ctx, &models.Job{
		ID:            "job-comp-1",
		OwnerID:       "tenant-alpha",
		UserID:        "cust-1",
		Status:        models.JobStatusCompleted,
		PaymentMethod: "cod",
		CreatedAt:     now,
	})
	_ = mongoStore.CreateJob(ctx, &models.Job{
		ID:            "job-comp-2",
		OwnerID:       "tenant-beta",
		UserID:        "cust-2",
		Status:        models.JobStatusCompleted,
		PaymentMethod: "cod",
		CreatedAt:     now,
	})
	_ = mongoStore.CreateJob(ctx, &models.Job{
		ID:            "job-active-1",
		OwnerID:       "tenant-alpha",
		UserID:        "cust-1",
		Status:        models.JobStatusActive,
		PaymentMethod: "cod",
		CreatedAt:     now,
	})

	req := httptest.NewRequest(http.MethodGet, "/admin/overview", nil)
	req.Header.Set("X-Internal-Token", "test-internal-token")
	req.Header.Set("X-Reviewer-Token", validToken)
	rec := httptest.NewRecorder()
	svc.AdminOverview(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK, got %d: %s", rec.Code, rec.Body.String())
	}

	var resp AdminOverviewResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}

	// Verify user-service metrics
	if resp.PendingPaymentSubscriptions != 2 {
		t.Errorf("expected 2 pending_payment_subscriptions, got %d", resp.PendingPaymentSubscriptions)
	}
	if resp.GPSDisputes != 3 { // 1 normal + 2 stuck cod
		t.Errorf("expected 3 gps_disputes, got %d", resp.GPSDisputes)
	}
	if resp.StuckCODJobs != 2 {
		t.Errorf("expected 2 stuck_cod_jobs, got %d", resp.StuckCODJobs)
	}
	if resp.JobsToday[string(models.JobStatusCompleted)] != 2 {
		t.Errorf("expected 2 completed jobs today, got %d", resp.JobsToday[string(models.JobStatusCompleted)])
	}
	if resp.JobsToday[string(models.JobStatusActive)] != 1 {
		t.Errorf("expected 1 active job today, got %d", resp.JobsToday[string(models.JobStatusActive)])
	}

	// Verify auth-service metrics
	if resp.PendingKYBKYE != float64(7) {
		t.Errorf("expected pending_kyb_kye 7, got %v", resp.PendingKYBKYE)
	}
	if resp.NewAccountsToday != float64(3) {
		t.Errorf("expected new_accounts_today 3, got %v", resp.NewAccountsToday)
	}
	if resp.NewAccounts7d != float64(14) {
		t.Errorf("expected new_accounts_7d 14, got %v", resp.NewAccounts7d)
	}
	if resp.SuspendedAccounts != float64(2) {
		t.Errorf("expected suspended_accounts 2, got %v", resp.SuspendedAccounts)
	}

	// Verify chat-service metrics
	if resp.OpenTickets != float64(5) {
		t.Errorf("expected open_tickets 5, got %v", resp.OpenTickets)
	}
	if resp.AssignedTickets != float64(2) {
		t.Errorf("expected assigned_tickets 2, got %v", resp.AssignedTickets)
	}
}

func TestAdminOverview_Fallback_WhenAuthOrChatUnavailable(t *testing.T) {
	// Auth fails, chat fails
	svc, mongoStore, validToken := setupAdminOverviewTestEnv(t, true, true)
	if svc == nil {
		return
	}
	ctx := context.Background()
	now := time.Now().UTC()

	_ = mongoStore.UpsertSubscription(ctx, &models.Subscription{
		ID:        "sub-p1",
		TenantID:  "tenant-1",
		Tier:      models.PlanPendingPayment,
		StartedAt: now,
	})

	req := httptest.NewRequest(http.MethodGet, "/admin/overview", nil)
	req.Header.Set("X-Internal-Token", "test-internal-token")
	req.Header.Set("X-Reviewer-Token", validToken)
	rec := httptest.NewRecorder()
	svc.AdminOverview(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK even when upstreams fail, got %d: %s", rec.Code, rec.Body.String())
	}

	var resp AdminOverviewResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}

	// Local user-service data must be intact
	if resp.PendingPaymentSubscriptions != 1 {
		t.Errorf("expected 1 pending_payment_subscriptions, got %d", resp.PendingPaymentSubscriptions)
	}

	// Upstream auth-service fields must fallback to "unavailable"
	if resp.PendingKYBKYE != "unavailable" {
		t.Errorf("expected pending_kyb_kye 'unavailable', got %v", resp.PendingKYBKYE)
	}
	if resp.NewAccountsToday != "unavailable" {
		t.Errorf("expected new_accounts_today 'unavailable', got %v", resp.NewAccountsToday)
	}
	if resp.NewAccounts7d != "unavailable" {
		t.Errorf("expected new_accounts_7d 'unavailable', got %v", resp.NewAccounts7d)
	}
	if resp.SuspendedAccounts != "unavailable" {
		t.Errorf("expected suspended_accounts 'unavailable', got %v", resp.SuspendedAccounts)
	}

	// Upstream chat-service fields must fallback to "unavailable"
	if resp.OpenTickets != "unavailable" {
		t.Errorf("expected open_tickets 'unavailable', got %v", resp.OpenTickets)
	}
	if resp.AssignedTickets != "unavailable" {
		t.Errorf("expected assigned_tickets 'unavailable', got %v", resp.AssignedTickets)
	}
}
