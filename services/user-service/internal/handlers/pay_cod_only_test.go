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

// PAY-COD-ONLY: with DIGITAL_PAYMENTS_ENABLED=false (the default) every
// endpoint that creates a job with a payment method, or requests a payout,
// refuses anything but COD with 400 payment_method_unavailable.

const (
	payCODOwner   = "paycod-owner"
	payCODCourier = "emp-paycod"
)

type payCODEnv struct {
	s        *store.MongoDB
	authURL  string
	rdb      *redis.Client
	ownerTok string
	custTok  string
}

func setupPayCOD(t *testing.T) *payCODEnv {
	t.Helper()
	secret := "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2"
	os.Setenv("JWT_SECRET", secret)
	jwtutil.Init(secret)
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://root:devpassword123@localhost:27017/saas_platform?authSource=admin"
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	s, err := store.NewMongoDB(ctx, mongoURI, fmt.Sprintf("saas_paycod_test_%d", time.Now().UnixNano()))
	if err != nil {
		t.Skipf("Skipping: MongoDB not available (%v)", err)
	}
	t.Cleanup(func() {
		_ = s.DropDatabase(context.Background())
		_ = s.Close(context.Background())
	})
	auth := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		id := r.URL.Query().Get("id")
		role, tenant := "owner", id
		if id == payCODCourier {
			role, tenant = "employee", payCODOwner
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"id": id, "role": role, "kyc_status": "approved", "is_active": true, "tenant_id": tenant})
	}))
	t.Cleanup(auth.Close)
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	t.Cleanup(func() { _ = rdb.Close() })

	if err := s.UpsertSubscription(ctx, &models.Subscription{TenantID: payCODOwner, Tier: models.PlanPaid, ExpiresAt: time.Now().Add(24 * time.Hour)}); err != nil {
		t.Fatalf("seed subscription: %v", err)
	}
	mustCreateService(t, s, ctx, &models.Service{
		ID: "paycod-svc", TenantID: payCODOwner, Name: "PayCOD", Category: "delivery",
		TenantBasePrice: 50, TenantPricePerKM: 0, Latitude: 30.0444, Longitude: 31.2357,
	})
	if err := s.UpsertEmployeeLocation(ctx, &models.EmployeeLocation{
		TenantID: payCODOwner, EmployeeID: payCODCourier, Latitude: 30.0444, Longitude: 31.2357, UpdatedAt: time.Now().UTC(),
	}); err != nil {
		t.Fatalf("seed courier location: %v", err)
	}
	ownerTok, _ := jwtutil.GenerateToken(payCODOwner, "owner", payCODOwner, "o@paycod.test")
	custTok, _ := jwtutil.GenerateToken("paycod-cust", "customer", "paycod-cust", "c@paycod.test")
	return &payCODEnv{s: s, authURL: auth.URL, rdb: rdb, ownerTok: ownerTok, custTok: custTok}
}

// service builds a UserService. appEnv "production" with no bypass is the
// real production shape; the bypass only exists in local/test.
func (e *payCODEnv) service(digital bool) *UserService {
	return NewUserService(e.s, &config.Config{
		AuthServiceURL: e.authURL, InternalServiceToken: "mock-token",
		AppEnv: "production", DigitalPaymentsEnabled: digital,
	}, e.rdb)
}

func (e *payCODEnv) trackJob(u *UserService, method, idemKey, employeeID string) *httptest.ResponseRecorder {
	fields := map[string]any{
		"owner_id": payCODOwner, "owner_token": e.ownerTok,
		"user_id": "paycod-cust", "user_token": e.custTok,
		"service_id": "paycod-svc", "payment_method": method, "idempotency_key": idemKey,
		"location":    models.Location{Latitude: 30.0444, Longitude: 31.2357},
		"destination": models.Location{Latitude: 30.0500, Longitude: 31.2400},
	}
	if employeeID != "" {
		empTok, _ := jwtutil.GenerateToken(employeeID, "employee", payCODOwner, "e@paycod.test")
		fields["employee_id"] = empTok
	}
	body, _ := json.Marshal(fields)
	req := httptest.NewRequest("POST", "/users/jobs/track", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+e.ownerTok)
	rec := httptest.NewRecorder()
	u.TrackJob(rec, req)
	return rec
}

func (e *payCODEnv) jobCount(t *testing.T) int {
	t.Helper()
	jobs, err := e.s.GetJobsByOwner(context.Background(), payCODOwner)
	if err != nil {
		t.Fatalf("GetJobsByOwner: %v", err)
	}
	return len(jobs)
}

func assertPaymentMethodUnavailable(t *testing.T, rec *httptest.ResponseRecorder) {
	t.Helper()
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d. Body: %s", rec.Code, rec.Body.String())
	}
	var resp map[string]string
	_ = json.Unmarshal(rec.Body.Bytes(), &resp)
	if resp["code"] != "payment_method_unavailable" || resp["error"] != "payment_method_unavailable" {
		t.Errorf("expected stable code payment_method_unavailable, got %s", rec.Body.String())
	}
}

func TestTrackJob_DigitalPaymentsOff_OnlyCOD(t *testing.T) {
	e := setupPayCOD(t)
	u := e.service(false)

	for i, method := range []string{"wallet", "WALLET", "card", "instapay"} {
		rec := e.trackJob(u, method, fmt.Sprintf("paycod-off-%d", i), "")
		assertPaymentMethodUnavailable(t, rec)
	}
	if n := e.jobCount(t); n != 0 {
		t.Fatalf("expected no job to be created for refused payment methods, found %d", n)
	}

	rec := e.trackJob(u, "cod", "paycod-off-cod", "")
	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201 for cod, got %d. Body: %s", rec.Code, rec.Body.String())
	}
	if rec := e.trackJob(u, "", "paycod-off-empty", ""); rec.Code != http.StatusCreated {
		t.Fatalf("expected 201 for an empty payment_method (defaults to cod), got %d. Body: %s", rec.Code, rec.Body.String())
	}
}

func TestTrackJob_DigitalPaymentsOn_KeepsWalletFlow(t *testing.T) {
	e := setupPayCOD(t)
	u := e.service(true)

	// Cascade dispatch: the wallet job is created (escrow is locked when a
	// courier accepts), exactly as before.
	rec := e.trackJob(u, "wallet", "paycod-on-cascade", "")
	if rec.Code != http.StatusCreated || !strings.Contains(rec.Body.String(), `"payment_method":"wallet"`) {
		t.Fatalf("expected 201 wallet job, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// Direct assignment with an empty wallet: today's 201 "created but escrow
	// lock failed" is kept when digital payments are on.
	rec = e.trackJob(u, "wallet", "paycod-on-direct", payCODCourier)
	if rec.Code != http.StatusCreated || !strings.Contains(rec.Body.String(), "escrow lock failed") {
		t.Fatalf("expected today's 201 unfunded wallet job, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// Unknown methods keep the old validation error, not the new code.
	rec = e.trackJob(u, "card", "paycod-on-card", "")
	if rec.Code != http.StatusBadRequest || !strings.Contains(rec.Body.String(), "invalid payment_method") {
		t.Fatalf("expected 400 invalid payment_method for card, got %d. Body: %s", rec.Code, rec.Body.String())
	}
}

func (e *payCODEnv) requestPayout(u *UserService) *httptest.ResponseRecorder {
	body, _ := json.Marshal(map[string]any{"amount": 100, "payout_method": "instapay"})
	req := httptest.NewRequest("POST", "/users/wallet/payout/request", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+e.ownerTok)
	rec := httptest.NewRecorder()
	u.RequestPayout(rec, req)
	return rec
}

func TestRequestPayout_DigitalPaymentsFlag(t *testing.T) {
	e := setupPayCOD(t)
	ctx := context.Background()
	if err := e.s.Deposit(ctx, payCODOwner, 500); err != nil {
		t.Fatalf("deposit: %v", err)
	}

	assertPaymentMethodUnavailable(t, e.requestPayout(e.service(false)))
	if w := e.s.GetWallet(ctx, payCODOwner); w == nil || w.WithdrawableBalance != 500 {
		t.Fatalf("expected the refused payout to leave the wallet untouched, got %+v", w)
	}

	if rec := e.requestPayout(e.service(true)); rec.Code != http.StatusCreated {
		t.Fatalf("expected 201 payout when digital payments are on, got %d. Body: %s", rec.Code, rec.Body.String())
	}
}

func TestGetPlatformConfig_ExposesDigitalPaymentsFlag(t *testing.T) {
	e := setupPayCOD(t)
	for _, want := range []bool{false, true} {
		rec := httptest.NewRecorder()
		e.service(want).GetPlatformConfig(rec, httptest.NewRequest("GET", "/users/platform/config", nil))
		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200, got %d. Body: %s", rec.Code, rec.Body.String())
		}
		var resp map[string]any
		if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if got, ok := resp["digital_payments_enabled"].(bool); !ok || got != want {
			t.Errorf("expected digital_payments_enabled=%v, got %v (body %s)", want, resp["digital_payments_enabled"], rec.Body.String())
		}
		if _, ok := resp["platform_fee_percentage"]; !ok {
			t.Errorf("expected the existing platform config fields to stay, got %s", rec.Body.String())
		}
	}
}
