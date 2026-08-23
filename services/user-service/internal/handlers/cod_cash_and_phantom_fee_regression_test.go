package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
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

// setupCODFeeHarness wires a handler against live MongoDB + miniredis with an
// approving mock auth service. Returns the handler, store, and ctx.
func setupCODFeeHarness(t *testing.T) (*UserService, *store.MongoDB, context.Context) {
	t.Helper()
	secret := "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2"
	os.Setenv("JWT_SECRET", secret)
	jwtutil.Init(secret)
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	t.Cleanup(cancel)

	dbName := fmt.Sprintf("saas_platform_test_codfee_%d", time.Now().UnixNano())
	s, err := store.NewMongoDB(ctx, mongoURI, dbName)
	if err != nil {
		t.Skipf("Skipping test: MongoDB not available (%v)", err)
		return nil, nil, nil
	}
	t.Cleanup(func() {
		_ = s.DropDatabase(context.Background())
		s.Close(context.Background())
	})

	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("miniredis: %v", err)
	}
	t.Cleanup(mr.Close)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	t.Cleanup(func() { _ = rdb.Close() })

	mockAuthServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		id := r.URL.Query().Get("id")
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]any{
			"id": id, "role": "owner", "kyc_status": "approved", "is_active": true, "tenant_id": id,
		})
	}))
	t.Cleanup(mockAuthServer.Close)

	cfg := &config.Config{
		AuthServiceURL:         mockAuthServer.URL,
		InternalServiceToken:   "mock-token",
		AllowTestPaymentBypass: true,
		AppEnv:                 "test",
	}
	return NewUserService(s, cfg, rdb), s, ctx
}

func completeViaHTTP(t *testing.T, h *UserService, body any) (*httptest.ResponseRecorder, map[string]any) {
	t.Helper()
	raw, _ := json.Marshal(body)
	req := httptest.NewRequest("POST", "/users/jobs/complete", bytes.NewReader(raw))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	h.CompleteJob(w, req)
	var res map[string]any
	_ = json.Unmarshal(w.Body.Bytes(), &res)
	return w, res
}

// TestCompleteJob_CODCapturesActualCashCollected reproduces the data gap:
// COD completions never recorded how much cash was actually collected. The
// employee collects real money at the door; the system only logged a
// recomputed price estimate derived from CURRENT service pricing at
// completion time, so any repricing/discount/cash-shortfall was silently
// lost, and the response echoed the estimate as if it were collected.
//
// Pre-fix expectation: request field absent (ignored), no persisted
// actual_cash_amount on the job, response total_amount = estimate.
// Post-fix expectation: actual_cash_amount accepted (>0, cent-rounded),
// persisted atomically with the status flip, and echoed as total_amount.
func TestCompleteJob_CODCapturesActualCashCollected(t *testing.T) {
	h, s, ctx := setupCODFeeHarness(t)
	if h == nil {
		return
	}

	ownerID := "owner-cod-cash"
	s.CreateService(ctx, &models.Service{
		ID: "svc-cod-cash", TenantID: ownerID, Name: "Cash Svc", Category: "cleaning",
		TenantBasePrice: 100.0, Latitude: 30.0444, Longitude: 31.2357,
	})
	jobID := "job-cod-cash-1"
	if err := s.CreateJob(ctx, &models.Job{
		ID: jobID, OwnerID: ownerID, UserID: "cust-cod-cash", ServiceID: "svc-cod-cash",
		Status: models.JobStatusActive, PaymentMethod: "cod",
		Location:  models.Location{Latitude: 30.0444, Longitude: 31.2357},
		CreatedAt: time.Now().UTC(), UpdatedAt: time.Now().UTC(),
	}); err != nil {
		t.Fatalf("create job: %v", err)
	}

	ownerToken, _ := jwtutil.GenerateToken(ownerID, "owner", ownerID, "o@cash.test")
	w, res := completeViaHTTP(t, h, map[string]any{
		"job_id":             jobID,
		"cash_collected":     true,
		"actual_cash_amount": 85.5, // customer paid less than the 100.00 estimate after on-site adjustment
		"requester_id":       ownerToken,
	})
	if w.Code != http.StatusOK {
		t.Fatalf("CompleteJob failed: %d %s", w.Code, w.Body.String())
	}

	job := s.GetJob(ctx, jobID)
	if job.Status != models.JobStatusCompleted {
		t.Fatalf("job not completed: %s", job.Status)
	}

	recorded, ok := res["total_amount"].(float64)
	if !ok || recorded != 85.5 {
		t.Errorf("PHANTOM COLLECTION AMOUNT: response total_amount = %v, want 85.50 (the actually-collected cash)", res["total_amount"])
	}
	// JSON-level assertion keeps this test compiling (and failing honestly)
	// against pre-fix code where models.Job has no ActualCashAmount field.
	jobJSON, _ := json.Marshal(job)
	if !bytes.Contains(jobJSON, []byte(`"actual_cash_amount":85.5`)) {
		t.Errorf("CASH COLLECTION DATA GAP: persisted job JSON %s lacks actual_cash_amount=85.5 (real cash collected was never captured)", jobJSON)
	}
}

// TestCompleteJob_NonCODResponseMatchesRealCredit reproduces the phantom fee
// display: the handler computed a legacy percentage-based fee/net split for
// the response while ReleaseEscrowWithSplit (ADR-0017 zero-commission model)
// actually credits 100% of the released amount to the owner's withdrawable
// balance. The displayed net_to_tenant contradicted the real credit.
//
// Pre-fix expectation: wallet credited 100.00 while response reports
// net_to_tenant 85.00 / platform_fee 15.00.
// Post-fix expectation: response figures match the real movement exactly.
func TestCompleteJob_NonCODResponseMatchesRealCredit(t *testing.T) {
	h, s, ctx := setupCODFeeHarness(t)
	if h == nil {
		return
	}

	ownerID := "owner-phantom-fee"
	s.CreateService(ctx, &models.Service{
		ID: "svc-phantom", TenantID: ownerID, Name: "Phantom Svc", Category: "cleaning",
		TenantBasePrice: 100.0, Latitude: 30.0444, Longitude: 31.2357,
	})
	if err := s.Deposit(ctx, ownerID, 300); err != nil {
		t.Fatalf("deposit: %v", err)
	}
	jobID := "job-phantom-1"
	if err := s.CreateJob(ctx, &models.Job{
		ID: jobID, OwnerID: ownerID, UserID: "cust-phantom", ServiceID: "svc-phantom",
		Status: models.JobStatusPending, PaymentMethod: "wallet",
		Location:  models.Location{Latitude: 30.0444, Longitude: 31.2357},
		CreatedAt: time.Now().UTC(), UpdatedAt: time.Now().UTC(),
	}); err != nil {
		t.Fatalf("create job: %v", err)
	}
	if err := s.LockEscrow(ctx, ownerID, jobID, 100); err != nil {
		t.Fatalf("lock escrow: %v", err)
	}
	if err := s.UpdateJobLockedEscrow(ctx, jobID, 100); err != nil {
		t.Fatalf("persist locked escrow: %v", err)
	}
	if err := s.UpdateJobStatus(ctx, jobID, models.JobStatusActive); err != nil {
		t.Fatalf("activate: %v", err)
	}

	// Simulate a deployment whose platform_config still carries a legacy
	// non-zero percentage (pre-ADR-0017 data): the response split must never
	// contradict the actual zero-commission credit regardless of config.
	if err := s.UpsertPlatformConfig(ctx, &models.PlatformConfig{
		ID: "global", PlatformFeePercentage: 15.0, PlatformWalletID: "platform-central",
	}); err != nil {
		t.Fatalf("upsert legacy platform config: %v", err)
	}

	before, _ := s.GetOrCreateWallet(ctx, ownerID)

	ownerToken, _ := jwtutil.GenerateToken(ownerID, "owner", ownerID, "o@phantom.test")
	w, res := completeViaHTTP(t, h, map[string]any{
		"job_id":       jobID,
		"requester_id": ownerToken,
	})
	if w.Code != http.StatusOK {
		t.Fatalf("CompleteJob failed: %d %s", w.Code, w.Body.String())
	}

	after, _ := s.GetOrCreateWallet(ctx, ownerID)
	realCredit := after.WithdrawableBalance - before.WithdrawableBalance

	respNet, _ := res["net_to_tenant"].(float64)
	respFee, _ := res["platform_fee"].(float64)

	if realCredit != respNet {
		t.Errorf("PHANTOM FEE DISPLAY: wallet was credited %.2f but response net_to_tenant = %.2f (displayed split contradicts real fund movement)", realCredit, respNet)
	}
	if respFee != 0 {
		t.Errorf("PHANTOM FEE DISPLAY: response platform_fee = %.2f, want 0 (ADR-0017 zero-commission release credits 100%% to tenant)", respFee)
	}
}
