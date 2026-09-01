package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/project/user-service/internal/config"
	"github.com/project/user-service/internal/models"
	"github.com/project/user-service/internal/store"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

// setupAdminReconciliationTestEnvironment prepares an isolated test environment with
// a mock auth-service (for reviewer verification) and a mock notification-service.
func setupAdminReconciliationTestEnvironment(t *testing.T) (*UserService, *store.MongoDB, string, *httptest.Server) {
	t.Helper()

	mongoURI := "mongodb://root:devpassword123@localhost:27017/saas_platform?authSource=admin"
	dbName := fmt.Sprintf("saas_recon_test_%d", time.Now().UnixNano())
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	mongoStore, err := store.NewMongoDB(ctx, mongoURI, dbName)
	if err != nil {
		t.Fatalf("failed to connect to mongodb for test: %v", err)
	}

	validReviewerToken := "valid-reviewer-secret-token"

	// Mock Auth and Notification Service
	mockServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
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
				_, _ = w.Write([]byte(`{"id":"reviewer-admin-1","name":"Ops Admin"}`))
				return
			}
			w.WriteHeader(http.StatusUnauthorized)
			_, _ = w.Write([]byte(`{"error":"invalid reviewer token"}`))
			return
		}

		if r.URL.Path == "/notifications/send" {
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte(`{"status":"sent"}`))
			return
		}

		w.WriteHeader(http.StatusNotFound)
	}))

	t.Cleanup(func() {
		mockServer.Close()
		dropCtx, dropCancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer dropCancel()
		client, err := mongo.Connect(dropCtx, options.Client().ApplyURI(mongoURI))
		if err == nil {
			_ = client.Database(dbName).Drop(dropCtx)
			_ = client.Disconnect(dropCtx)
		}
	})

	cfg := &config.Config{
		InternalServiceToken:   "test-internal-token",
		AuthServiceURL:         mockServer.URL,
		NotificationServiceURL: mockServer.URL,
	}

	svc := NewUserService(mongoStore, cfg, nil)
	return svc, mongoStore, validReviewerToken, mockServer
}

func TestAdminReconciliation_AuthenticationAndAuthorization(t *testing.T) {
	svc, _, validToken, _ := setupAdminReconciliationTestEnvironment(t)

	t.Run("Missing Internal Token", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/users/admin/reconciliation/queue", nil)
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		svc.AdminGetReconciliationQueue(rec, req)

		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("expected 401 Unauthorized for missing internal token, got %d", rec.Code)
		}
	})

	t.Run("Missing Reviewer Token", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/users/admin/reconciliation/queue", nil)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		rec := httptest.NewRecorder()
		svc.AdminGetReconciliationQueue(rec, req)

		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("expected 401 Unauthorized for missing reviewer token, got %d", rec.Code)
		}
	})

	t.Run("Invalid Reviewer Token", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/users/admin/reconciliation/queue", nil)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", "invalid-token-xyz")
		rec := httptest.NewRecorder()
		svc.AdminGetReconciliationQueue(rec, req)

		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("expected 401 Unauthorized for invalid reviewer token, got %d", rec.Code)
		}
	})

	t.Run("Valid Tokens Succeed", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/users/admin/reconciliation/queue", nil)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		svc.AdminGetReconciliationQueue(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 OK with valid tokens, got %d: %s", rec.Code, rec.Body.String())
		}
	})
}

func TestAdminReconciliation_GlobalQueueListing(t *testing.T) {
	svc, mongoStore, validToken, _ := setupAdminReconciliationTestEnvironment(t)
	ctx := context.Background()

	// Seed disputed jobs across two different tenants
	job1 := &models.Job{
		ID:                  "job-dispute-tenant-1",
		OwnerID:             "owner-alpha",
		EmployeeID:          "courier-alpha",
		UserID:              "customer-1",
		ServiceID:           "service-delivery-1",
		BookedDistance:      15.0,
		Location:            models.Location{Latitude: 30.0, Longitude: 31.0},
		Waypoints:           []models.Location{{Latitude: 30.05, Longitude: 31.05}},
		LockedEscrowAmount:  75.0,
		PaymentMethod:       "wallet",
		Status:              models.JobStatusEscrowReconciliationRequired,
		EscrowFailureReason: "under_distance_mismatch",
		ReconciliationNote:  "actual distance 6.0km < 70% of booked 15.0km",
		CreatedAt:           time.Now().UTC().Add(-2 * time.Hour),
		UpdatedAt:           time.Now().UTC().Add(-1 * time.Hour),
	}
	job2 := &models.Job{
		ID:                  "job-dispute-tenant-2",
		OwnerID:             "owner-beta",
		EmployeeID:          "courier-beta",
		UserID:              "customer-2",
		ServiceID:           "service-shipping-1",
		BookedDistance:      20.0,
		Location:            models.Location{Latitude: 30.1, Longitude: 31.2},
		Waypoints:           []models.Location{{Latitude: 30.15, Longitude: 31.25}},
		LockedEscrowAmount:  100.0,
		PaymentMethod:       "cod",
		Status:              models.JobStatusEscrowReconciliationRequired,
		EscrowFailureReason: "under_distance_mismatch",
		ReconciliationNote:  "actual distance 8.0km < 70% of booked 20.0km",
		CreatedAt:           time.Now().UTC().Add(-1 * time.Hour),
		UpdatedAt:           time.Now().UTC(),
	}
	// Non-disputed job (should be filtered out)
	jobNormal := &models.Job{
		ID:             "job-active-normal",
		OwnerID:        "owner-alpha",
		UserID:         "customer-1",
		ServiceID:      "service-delivery-1",
		Status:         models.JobStatusActive,
		BookedDistance: 10.0,
		CreatedAt:      time.Now().UTC(),
		UpdatedAt:      time.Now().UTC(),
	}

	if err := mongoStore.CreateJob(ctx, job1); err != nil {
		t.Fatalf("failed to seed job1: %v", err)
	}
	if err := mongoStore.CreateJob(ctx, job2); err != nil {
		t.Fatalf("failed to seed job2: %v", err)
	}
	if err := mongoStore.CreateJob(ctx, jobNormal); err != nil {
		t.Fatalf("failed to seed jobNormal: %v", err)
	}

	req := httptest.NewRequest(http.MethodGet, "/users/admin/reconciliation/queue?page=1&limit=10", nil)
	req.Header.Set("X-Internal-Token", "test-internal-token")
	req.Header.Set("X-Reviewer-Token", validToken)
	rec := httptest.NewRecorder()
	svc.AdminGetReconciliationQueue(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK, got %d: %s", rec.Code, rec.Body.String())
	}

	var resp models.AdminReconciliationQueueResponse
	if err := json.NewDecoder(rec.Body).Decode(&resp); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}

	if resp.Total != 2 {
		t.Fatalf("expected total 2 disputes globally, got %d", resp.Total)
	}
	if len(resp.Disputes) != 2 {
		t.Fatalf("expected 2 dispute items, got %d", len(resp.Disputes))
	}

	// Verify cross-tenant data completeness
	foundAlpha := false
	foundBeta := false
	for _, d := range resp.Disputes {
		if d.TenantID == "owner-alpha" && d.ID == "job-dispute-tenant-1" {
			foundAlpha = true
			if d.BookedDistance != 15.0 || d.LockedEscrowAmount != 75.0 {
				t.Errorf("dispute alpha fields mismatch: %+v", d)
			}
		}
		if d.TenantID == "owner-beta" && d.ID == "job-dispute-tenant-2" {
			foundBeta = true
			if d.PaymentMethod != "cod" || d.ServiceID != "service-shipping-1" {
				t.Errorf("dispute beta fields mismatch: %+v", d)
			}
		}
	}
	if !foundAlpha || !foundBeta {
		t.Errorf("failed to retrieve disputes from both tenants globally: alpha=%v beta=%v", foundAlpha, foundBeta)
	}
}

func TestAdminReconciliation_ValidationAndResolutionLifecycle(t *testing.T) {
	svc, mongoStore, validToken, _ := setupAdminReconciliationTestEnvironment(t)
	ctx := context.Background()

	// Seed tenant owner wallet with escrow locked
	ownerID := "owner-lifecycle"
	if err := mongoStore.Deposit(ctx, ownerID, 200.0); err != nil {
		t.Fatalf("failed to fund owner wallet: %v", err)
	}
	// Seed customer wallet
	customerID := "customer-lifecycle"
	if err := mongoStore.Deposit(ctx, customerID, 150.0); err != nil {
		t.Fatalf("failed to fund customer wallet: %v", err)
	}

	// Lock escrow of 60.0 on owner
	if err := mongoStore.LockEscrow(ctx, ownerID, "job-release-test", 60.0); err != nil {
		t.Fatalf("failed to lock escrow: %v", err)
	}

	jobRelease := &models.Job{
		ID:                  "job-release-test",
		OwnerID:             ownerID,
		EmployeeID:          "courier-123",
		UserID:              customerID,
		ServiceID:           "service-1",
		BookedDistance:      10.0,
		LockedEscrowAmount:  60.0,
		PaymentMethod:       "wallet",
		Status:              models.JobStatusEscrowReconciliationRequired,
		EscrowFailureReason: "under_distance_mismatch",
		CreatedAt:           time.Now().UTC(),
		UpdatedAt:           time.Now().UTC(),
	}
	if err := mongoStore.CreateJob(ctx, jobRelease); err != nil {
		t.Fatalf("failed to create jobRelease: %v", err)
	}

	t.Run("Mandatory Reason Validation", func(t *testing.T) {
		cases := []struct {
			name     string
			decision string
			reason   string
		}{
			{"Empty Reason", "release_to_employee", ""},
			{"Whitespace Reason", "release_to_employee", "   "},
			{"Oversized Reason", "release_to_employee", strings.Repeat("a", 1001)},
			{"Invalid Decision", "invalid_decision", "Reasonable note"},
		}

		for _, tc := range cases {
			t.Run(tc.name, func(t *testing.T) {
				body, _ := json.Marshal(models.AdminResolveReconciliationRequest{
					JobID:    "job-release-test",
					Decision: tc.decision,
					Reason:   tc.reason,
				})
				req := httptest.NewRequest(http.MethodPost, "/users/admin/reconciliation/resolve", bytes.NewReader(body))
				req.Header.Set("X-Internal-Token", "test-internal-token")
				req.Header.Set("X-Reviewer-Token", validToken)
				rec := httptest.NewRecorder()
				svc.AdminResolveReconciliation(rec, req)

				if rec.Code != http.StatusBadRequest {
					t.Fatalf("expected 400 Bad Request, got %d: %s", rec.Code, rec.Body.String())
				}
			})
		}
	})

	t.Run("Resolve to Courier / Tenant", func(t *testing.T) {
		body, _ := json.Marshal(models.AdminResolveReconciliationRequest{
			JobID:    "job-release-test",
			Decision: "release_to_employee",
			Reason:   "Delivery waypoint GPS trail verified manually by operator",
		})
		req := httptest.NewRequest(http.MethodPost, "/users/admin/reconciliation/resolve", bytes.NewReader(body))
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		svc.AdminResolveReconciliation(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 OK, got %d: %s", rec.Code, rec.Body.String())
		}

		// Verify job status changed in DB
		updatedJob := mongoStore.GetJob(ctx, "job-release-test")
		if updatedJob.Status != models.JobStatusCompleted {
			t.Fatalf("expected status completed, got %s", updatedJob.Status)
		}
		if !strings.Contains(updatedJob.ReconciliationNote, "reviewer-admin-1") {
			t.Errorf("reconciliation note does not contain reviewer id: %s", updatedJob.ReconciliationNote)
		}

		// Verify escrow balance on owner wallet was cleared
		w := mongoStore.GetWallet(ctx, ownerID)
		if w.EscrowBalance != 0.0 {
			t.Errorf("expected locked escrow to be 0, got %.2f", w.EscrowBalance)
		}
	})

	t.Run("Resolve to Customer Refund", func(t *testing.T) {
		// Seed another job for refund
		if err := mongoStore.LockEscrow(ctx, ownerID, "job-refund-test", 50.0); err != nil {
			t.Fatalf("failed to lock escrow: %v", err)
		}
		jobRefund := &models.Job{
			ID:                  "job-refund-test",
			OwnerID:             ownerID,
			UserID:              customerID,
			ServiceID:           "service-1",
			BookedDistance:      10.0,
			LockedEscrowAmount:  50.0,
			PaymentMethod:       "wallet",
			Status:              models.JobStatusEscrowReconciliationRequired,
			EscrowFailureReason: "under_distance_mismatch",
			CreatedAt:           time.Now().UTC(),
			UpdatedAt:           time.Now().UTC(),
		}
		if err := mongoStore.CreateJob(ctx, jobRefund); err != nil {
			t.Fatalf("failed to create jobRefund: %v", err)
		}

		body, _ := json.Marshal(models.AdminResolveReconciliationRequest{
			JobID:    "job-refund-test",
			Decision: "refund_to_customer",
			Reason:   "Under-distance trip unfulfilled; refunded to customer",
		})
		req := httptest.NewRequest(http.MethodPost, "/users/admin/reconciliation/resolve", bytes.NewReader(body))
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		svc.AdminResolveReconciliation(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 OK, got %d: %s", rec.Code, rec.Body.String())
		}

		updatedJob := mongoStore.GetJob(ctx, "job-refund-test")
		if updatedJob.Status != models.JobStatusCancelled {
			t.Fatalf("expected status cancelled, got %s", updatedJob.Status)
		}

		// Verify owner wallet received restored withdrawable balance
		ownerWalletAfter := mongoStore.GetWallet(ctx, ownerID)
		if ownerWalletAfter.WithdrawableBalance < 200.0 || ownerWalletAfter.EscrowBalance != 0.0 {
			t.Errorf("owner wallet balance mismatch: withdrawable %.2f, escrow %.2f", ownerWalletAfter.WithdrawableBalance, ownerWalletAfter.EscrowBalance)
		}
	})
}

// TestAdminReconciliation_CASConcurrencyRace verifies that two concurrent resolution attempts on the same dispute
// are protected by the Compare-and-Swap status transition: exactly one succeeds (200 OK), and the second fails (409 Conflict).
func TestAdminReconciliation_CASConcurrencyRace(t *testing.T) {
	svc, mongoStore, validToken, _ := setupAdminReconciliationTestEnvironment(t)
	ctx := context.Background()

	ownerID := "owner-race"
	_ = mongoStore.Deposit(ctx, ownerID, 500.0)
	_ = mongoStore.LockEscrow(ctx, ownerID, "job-race-target", 100.0)

	jobRace := &models.Job{
		ID:                  "job-race-target",
		OwnerID:             ownerID,
		UserID:              "customer-race",
		ServiceID:           "service-1",
		BookedDistance:      20.0,
		LockedEscrowAmount:  100.0,
		PaymentMethod:       "wallet",
		Status:              models.JobStatusEscrowReconciliationRequired,
		EscrowFailureReason: "under_distance_mismatch",
		CreatedAt:           time.Now().UTC(),
		UpdatedAt:           time.Now().UTC(),
	}
	if err := mongoStore.CreateJob(ctx, jobRace); err != nil {
		t.Fatalf("failed to seed jobRace: %v", err)
	}

	var wg sync.WaitGroup
	results := make([]int, 2)

	// Launch two concurrent resolution requests with different decisions
	for i := 0; i < 2; i++ {
		wg.Add(1)
		idx := i
		go func() {
			defer wg.Done()
			decision := "release_to_employee"
			if idx == 1 {
				decision = "refund_to_customer"
			}
			body, _ := json.Marshal(models.AdminResolveReconciliationRequest{
				JobID:    "job-race-target",
				Decision: decision,
				Reason:   fmt.Sprintf("Concurrent attempt #%d", idx),
			})
			req := httptest.NewRequest(http.MethodPost, "/users/admin/reconciliation/resolve", bytes.NewReader(body))
			req.Header.Set("X-Internal-Token", "test-internal-token")
			req.Header.Set("X-Reviewer-Token", validToken)
			rec := httptest.NewRecorder()
			svc.AdminResolveReconciliation(rec, req)
			results[idx] = rec.Code
		}()
	}

	wg.Wait()

	count200 := 0
	count409 := 0
	for _, code := range results {
		if code == http.StatusOK {
			count200++
		} else if code == http.StatusConflict {
			count409++
		}
	}

	if count200 != 1 || count409 != 1 {
		t.Fatalf("CAS concurrency failure: expected exactly 1 200 OK and 1 409 Conflict, got results: %+v", results)
	}
}
