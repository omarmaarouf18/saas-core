package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/project/shared/infra/jwtutil"
	"github.com/project/user-service/internal/config"
	"github.com/project/user-service/internal/models"
	"github.com/project/user-service/internal/store"
	"github.com/redis/go-redis/v9"
)

// Money-precision boundary tests: client-supplied monetary values must be
// cent-rounded (half-away-from-zero) at ingestion so no sub-cent residue can
// enter price proposals, wallet balances, or payouts. The full
// integer-minor-units migration is explicitly deferred (see changelog);
// these are the highest-traffic boundaries defended until then.

func setupMoneyPrecisionHarness(t *testing.T) (*UserService, *store.MongoDB, context.Context) {
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

	dbName := fmt.Sprintf("saas_platform_test_money_%d", time.Now().UnixNano())
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
		role := "owner"
		tenantID := id
		if strings.Contains(id, "emp") {
			role = "employee"
			if strings.HasPrefix(id, "emp-") {
				tenantID = strings.TrimPrefix(id, "emp-")
			}
		}
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]any{
			"id": id, "role": role, "kyc_status": "approved", "is_active": true, "tenant_id": tenantID,
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

func mustJSONResponse(t *testing.T, w *httptest.ResponseRecorder) map[string]any {
	t.Helper()
	var res map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &res); err != nil {
		t.Fatalf("non-JSON response (%d): %s", w.Code, w.Body.String())
	}
	return res
}

// TestTrackJob_ProposedPriceCentRounded: a sub-cent transport fare proposal
// must be rounded to cents before persistence.
func TestTrackJob_ProposedPriceCentRounded(t *testing.T) {
	h, s, ctx := setupMoneyPrecisionHarness(t)
	if h == nil {
		return
	}
	ownerID := "owner-money-track"
	custID := "cust-money-track"
	s.CreateService(ctx, &models.Service{
		ID: "svc-money", TenantID: ownerID, Name: "Transport Svc", Category: "transport",
		TenantBasePrice: 66.66, Latitude: 30.0444, Longitude: 31.2357,
	})
	_ = s.UpsertEmployeeLocation(ctx, &models.EmployeeLocation{
		TenantID:   ownerID,
		EmployeeID: "emp-owner-money-track",
		Latitude:   30.0444,
		Longitude:  31.2357,
		UpdatedAt:  time.Now().UTC(),
	})
	ownerToken, _ := jwtutil.GenerateToken(ownerID, "owner", ownerID, "o@m.test")
	custToken, _ := jwtutil.GenerateToken(custID, "customer", custID, "c@m.test")

	body, _ := json.Marshal(map[string]any{
		"service_id":     "svc-money",
		"user_token":     custToken,
		"payment_method": "cod",
		"proposed_price": 40.123456789, // within [0.5x, 1.5x] of 66.66 but carries sub-cent residue
		"location":       map[string]any{"latitude": 30.0444, "longitude": 31.2357},
	})
	req := httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+ownerToken)
	w := httptest.NewRecorder()
	h.TrackJob(w, req)
	if w.Code != http.StatusCreated {
		t.Fatalf("TrackJob failed: %d %s", w.Code, w.Body.String())
	}
	res := mustJSONResponse(t, w)
	jobObj := res["job"].(map[string]any)
	got := jobObj["proposed_price"].(float64)
	if got != 40.12 {
		t.Errorf("UNROUNDED PROPOSAL PERSISTED: proposed_price = %v, want 40.12 (sub-cent residue entered the pricing pipeline)", got)
	}
}

// TestProposePrice_CentRounded: the standalone proposal endpoint must round too.
func TestProposePrice_CentRounded(t *testing.T) {
	h, s, ctx := setupMoneyPrecisionHarness(t)
	if h == nil {
		return
	}
	ownerID := "owner-prop-round"
	custID := "cust-prop-round"
	jobID := "job-prop-round"
	exp := time.Now().UTC().Add(5 * time.Minute)
	s.CreateService(ctx, &models.Service{
		ID: "svc-prop", TenantID: ownerID, Name: "T", Category: "transport",
		TenantBasePrice: 66.66, Latitude: 30.0444, Longitude: 31.2357,
	})
	if err := s.CreateJob(ctx, &models.Job{
		ID: jobID, OwnerID: ownerID, UserID: custID, ServiceID: "svc-prop",
		Status: models.JobStatusAwaitingPriceResponse, PaymentMethod: "cod",
		SuggestedPrice: 66.66,
		Location:       models.Location{Latitude: 30.0444, Longitude: 31.2357},
		CreatedAt:      time.Now().UTC(), UpdatedAt: time.Now().UTC(),
		PriceProposalExpiresAt: &exp,
	}); err != nil {
		t.Fatalf("create job: %v", err)
	}
	custToken, _ := jwtutil.GenerateToken(custID, "customer", custID, "c@p.test")

	body, _ := json.Marshal(map[string]any{
		"job_id":         jobID,
		"proposed_price": 51.987654321,
		"requester_id":   custToken,
	})
	req := httptest.NewRequest("POST", "/users/jobs/propose-price", bytes.NewReader(body))
	w := httptest.NewRecorder()
	h.ProposePrice(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("ProposePrice failed: %d %s", w.Code, w.Body.String())
	}
	job := s.GetJob(ctx, jobID)
	if job.ProposedPrice == nil || *job.ProposedPrice != 51.99 {
		t.Errorf("UNROUNDED PROPOSAL PERSISTED: proposed_price = %.10f, want 51.99", *job.ProposedPrice)
	}
}

// TestRespondPrice_AgreedPriceCentRounded: acceptance locks escrow against the
// agreed price — it must never carry sub-cent residue into wallet balances.
func TestRespondPrice_AgreedPriceCentRounded(t *testing.T) {
	h, s, ctx := setupMoneyPrecisionHarness(t)
	if h == nil {
		return
	}
	ownerID := "owner-resp-round"
	custID := "cust-resp-round"
	jobID := "job-resp-round"
	exp := time.Now().UTC().Add(5 * time.Minute)
	proposal := 44.44444444
	s.CreateService(ctx, &models.Service{
		ID: "svc-resp", TenantID: ownerID, Name: "T2", Category: "transport",
		TenantBasePrice: 66.66, Latitude: 30.0444, Longitude: 31.2357,
	})
	if err := s.CreateJob(ctx, &models.Job{
		ID: jobID, OwnerID: ownerID, UserID: custID, ServiceID: "svc-resp", EmployeeID: "emp-resp-round",
		Status: models.JobStatusAwaitingPriceResponse, PaymentMethod: "cod",
		SuggestedPrice: 66.66, ProposedPrice: &proposal, ProposedBy: "employee",
		Location:  models.Location{Latitude: 30.0444, Longitude: 31.2357},
		CreatedAt: time.Now().UTC(), UpdatedAt: time.Now().UTC(),
		PriceProposalExpiresAt: &exp,
	}); err != nil {
		t.Fatalf("create job: %v", err)
	}
	custToken2, _ := jwtutil.GenerateToken(custID, "customer", custID, "c@r.test")

	body, _ := json.Marshal(map[string]any{
		"job_id":       jobID,
		"decision":     "accept",
		"requester_id": custToken2,
	})
	req := httptest.NewRequest("POST", "/users/jobs/respond-price", bytes.NewReader(body))
	w := httptest.NewRecorder()
	h.RespondPrice(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("RespondPrice failed: %d %s", w.Code, w.Body.String())
	}
	job := s.GetJob(ctx, jobID)
	if job.AgreedPrice == nil || *job.AgreedPrice != 44.44 {
		t.Errorf("UNROUNDED AGREED PRICE: agreed_price = %v, want 44.44", job.AgreedPrice)
	}
}

// TestWalletDeposit_CentRoundsAmount: deposits must not carry sub-cent
// residue into wallet balances.
func TestWalletDeposit_CentRoundsAmount(t *testing.T) {
	h, s, ctx := setupMoneyPrecisionHarness(t)
	if h == nil {
		return
	}
	ownerID := "owner-dep-round"
	if _, err := s.GetOrCreateWallet(ctx, ownerID); err != nil {
		t.Fatalf("wallet: %v", err)
	}
	ownerToken, _ := jwtutil.GenerateToken(ownerID, "owner", ownerID, "o@d.test")

	body, _ := json.Marshal(map[string]any{
		"tenant_token": ownerToken,
		"amount":       10.99999999,
	})
	req := httptest.NewRequest("POST", "/users/wallet/deposit", bytes.NewReader(body))
	w := httptest.NewRecorder()
	h.WalletDeposit(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("WalletDeposit failed: %d %s", w.Code, w.Body.String())
	}
	wallet := s.GetWallet(ctx, ownerID)
	if wallet.TotalBalance != 11.00 {
		t.Errorf("SUB-CENT DEPOSIT RESIDUE: total_balance = %.10f, want 11.00", wallet.TotalBalance)
	}
}

// TestRequestPayout_CentRoundsAmount: payout deductions must be exact cents.
func TestRequestPayout_CentRoundsAmount(t *testing.T) {
	h, s, ctx := setupMoneyPrecisionHarness(t)
	if h == nil {
		return
	}
	ownerID := "owner-pay-round"
	if _, err := s.GetOrCreateWallet(ctx, ownerID); err != nil {
		t.Fatalf("wallet: %v", err)
	}
	if err := s.Deposit(ctx, ownerID, 500); err != nil {
		t.Fatalf("deposit: %v", err)
	}
	ownerToken, _ := jwtutil.GenerateToken(ownerID, "owner", ownerID, "o@pr.test")

	body, _ := json.Marshal(map[string]any{
		"amount":        20.0055555,
		"payout_method": "instapay",
	})
	req := httptest.NewRequest("POST", "/users/wallet/payout/request", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+ownerToken)
	w := httptest.NewRecorder()
	h.RequestPayout(w, req)
	if w.Code != http.StatusCreated {
		t.Fatalf("RequestPayout failed: %d %s", w.Code, w.Body.String())
	}
	var pr models.PayoutRequest
	_ = json.Unmarshal(w.Body.Bytes(), &pr)
	if pr.Amount != 20.01 {
		t.Errorf("SUB-CENT PAYOUT RESIDUE: payout amount = %.10f, want 20.01", pr.Amount)
	}
	wallet := s.GetWallet(ctx, ownerID)
	if wallet.WithdrawableBalance != 479.99 {
		t.Errorf("SUB-CENT PAYOUT DEDUCTION DRIFT: withdrawable = %.10f, want 479.99", wallet.WithdrawableBalance)
	}
}
