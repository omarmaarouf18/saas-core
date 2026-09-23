package handlers

// Regression tests for ADR-0024 (expired-subscription closed status):
//  - requireTier rejects paid-but-expired tenants via Subscription.IsClosed.
//  - ListServices (public handler) excludes closed tenants' services.
//  - TrackJob rejects closed-tenant bookings with 402 + customer-safe copy
//    before any employee/KYC/escrow work, and lets open tenants through.

import (
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

func setupClosedStatusHarness(t *testing.T) (*store.MongoDB, *UserService, context.Context, func()) {
	t.Helper()
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	dbName := fmt.Sprintf("saas_platform_closed_%d", time.Now().UnixNano())
	s, err := store.NewMongoDB(ctx, mongoURI, dbName)
	if err != nil {
		cancel()
		t.Skipf("Skipping closed-status test: MongoDB not available at %s (%v)", mongoURI, err)
	}
	mr, err := miniredis.Run()
	if err != nil {
		cancel()
		t.Fatalf("failed to start miniredis: %v", err)
	}
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	cfg := &config.Config{}
	u := NewUserService(s, cfg, rdb)
	cleanup := func() {
		_ = s.DropDatabase(context.Background())
		s.Close(context.Background())
		mr.Close()
		rdb.Close()
		cancel()
	}
	return s, u, ctx, cleanup
}

func seedClosedStatusSub(t *testing.T, s *store.MongoDB, ctx context.Context, tenantID string, tier models.PlanTier, expiresAt time.Time) {
	t.Helper()
	sub := &models.Subscription{
		ID:        "sub-closed-test-" + tenantID,
		TenantID:  tenantID,
		Tier:      tier,
		StartedAt: time.Now().UTC().Add(-time.Hour),
		ExpiresAt: expiresAt,
	}
	if err := s.UpsertSubscription(ctx, sub); err != nil {
		t.Fatalf("failed to seed subscription for %s: %v", tenantID, err)
	}
}

func TestRequireTier_SubscriptionExpiry(t *testing.T) {
	s, u, ctx, cleanup := setupClosedStatusHarness(t)
	defer cleanup()

	future := time.Now().UTC().Add(time.Hour)
	past := time.Now().UTC().Add(-time.Hour)

	seedClosedStatusSub(t, s, ctx, "t-open-future", models.PlanPaid, future)
	seedClosedStatusSub(t, s, ctx, "t-open-noexpiry", models.PlanPaid, time.Time{})
	seedClosedStatusSub(t, s, ctx, "t-expired", models.PlanPaid, past)
	seedClosedStatusSub(t, s, ctx, "t-free", models.PlanFree, time.Time{})
	seedClosedStatusSub(t, s, ctx, "t-pending", models.PlanPendingPayment, future)
	seedClosedStatusSub(t, s, ctx, "t-cancelled", models.PlanCancelled, future)
	// t-missing: no subscription seeded at all.

	cases := []struct {
		tenant  string
		wantErr bool
	}{
		{"t-open-future", false},
		{"t-open-noexpiry", false},
		{"t-expired", true},
		{"t-free", true},
		{"t-pending", true},
		{"t-cancelled", true},
		{"t-missing", true},
	}
	for _, tc := range cases {
		t.Run(tc.tenant, func(t *testing.T) {
			err := u.requireTier(ctx, tc.tenant, models.PlanPaid)
			if !tc.wantErr && err != nil {
				t.Fatalf("expected open tenant %s, got error: %v", tc.tenant, err)
			}
			if tc.wantErr && err != ErrUpgradeRequired {
				t.Fatalf("expected ErrUpgradeRequired for %s, got: %v", tc.tenant, err)
			}
		})
	}
}

func TestSubscription_IsClosed_Predicate(t *testing.T) {
	now := time.Now().UTC()
	var nilSub *models.Subscription
	if !nilSub.IsClosed(now) {
		t.Errorf("nil subscription must be closed")
	}
	cases := []struct {
		name string
		sub  models.Subscription
		want bool
	}{
		{"paid+future", models.Subscription{Tier: models.PlanPaid, ExpiresAt: now.Add(time.Hour)}, false},
		{"paid+zero-expiry", models.Subscription{Tier: models.PlanPaid}, false},
		{"paid+past", models.Subscription{Tier: models.PlanPaid, ExpiresAt: now.Add(-time.Hour)}, true},
		{"free", models.Subscription{Tier: models.PlanFree}, true},
		{"pending", models.Subscription{Tier: models.PlanPendingPayment, ExpiresAt: now.Add(time.Hour)}, true},
		{"cancelled+future", models.Subscription{Tier: models.PlanCancelled, ExpiresAt: now.Add(time.Hour)}, true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := tc.sub.IsClosed(now); got != tc.want {
				t.Errorf("IsClosed() = %v, want %v", got, tc.want)
			}
		})
	}
}

func TestListServices_ExcludesClosedTenants(t *testing.T) {
	s, u, ctx, cleanup := setupClosedStatusHarness(t)
	defer cleanup()

	future := time.Now().UTC().Add(time.Hour)
	past := time.Now().UTC().Add(-time.Hour)

	tenants := map[string]struct {
		tier    models.PlanTier
		expires time.Time
		seedSub bool
	}{
		"tenant-open":    {models.PlanPaid, future, true},
		"tenant-expired": {models.PlanPaid, past, true},
		"tenant-free":    {models.PlanFree, time.Time{}, true},
		"tenant-nosub":   {models.PlanFree, time.Time{}, false},
	}
	for tenant, tc := range tenants {
		if tc.seedSub {
			seedClosedStatusSub(t, s, ctx, tenant, tc.tier, tc.expires)
		}
		s.CreateService(ctx, &models.Service{
			ID:               "svc-" + tenant,
			TenantID:         tenant,
			Name:             "Service " + tenant,
			Category:         "delivery",
			TenantBasePrice:  10.0,
			TenantPricePerKM: 1.0,
			Latitude:         30.0444,
			Longitude:        31.2357,
		})
	}

	// Unfiltered store path still returns all four (kept for owner/debug use).
	if got := s.ListServices(ctx, "none", false, 30.0444, 31.2357, 50, 50, 0); len(got) != 4 {
		t.Fatalf("expected unfiltered ListServices to return 4, got %d", len(got))
	}

	req := httptest.NewRequest("GET", "/users/services", nil)
	rec := httptest.NewRecorder()
	u.ListServices(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK, got %d: %s", rec.Code, rec.Body.String())
	}
	var resp struct {
		Count    int                       `json:"count"`
		Services []models.ServiceWithPrice `json:"services"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to parse response JSON: %v", err)
	}
	if resp.Count != 1 || len(resp.Services) != 1 {
		t.Fatalf("expected exactly 1 open-tenant service, got count=%d: %s", resp.Count, rec.Body.String())
	}
	if resp.Services[0].TenantID != "tenant-open" {
		t.Errorf("expected surviving service to belong to tenant-open, got %s", resp.Services[0].TenantID)
	}
}

// trackJobClosedStatusHarness builds a TrackJob-capable service with a mock
// auth server that approves KYC for every owner.
func trackJobClosedStatusHarness(t *testing.T, s *store.MongoDB) (*UserService, string) {
	t.Helper()
	mockAuthServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		id := r.URL.Query().Get("id")
		w.WriteHeader(http.StatusOK)
		_ = json.NewEncoder(w).Encode(map[string]any{
			"id": id, "role": "owner", "kyc_status": "approved",
			"is_active": true, "tenant_id": id,
		})
	}))
	t.Cleanup(mockAuthServer.Close)
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	t.Cleanup(func() { mr.Close() })
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	t.Cleanup(func() { rdb.Close() })
	cfg := &config.Config{
		AuthServiceURL:       mockAuthServer.URL,
		InternalServiceToken: "mock-internal-token",
		AppEnv:               "test",
	}
	return NewUserService(s, cfg, rdb), mockAuthServer.URL
}

func postClosedStatusTrack(t *testing.T, u *UserService, body map[string]any) *httptest.ResponseRecorder {
	t.Helper()
	raw, _ := json.Marshal(body)
	req := httptest.NewRequest("POST", "/users/jobs/track", strings.NewReader(string(raw)))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	u.TrackJob(rec, req)
	return rec
}

func TestTrackJob_ClosedTenantRejected(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	s, _, ctx, cleanup := setupClosedStatusHarness(t)
	defer cleanup()
	u, _ := trackJobClosedStatusHarness(t, s)

	seedClosedStatusSub(t, s, ctx, "closed-owner", models.PlanPaid, time.Now().UTC().Add(-time.Hour))
	s.CreateService(ctx, &models.Service{
		ID: "svc-closed", TenantID: "closed-owner", Name: "Closed Shop",
		Category: "delivery", TenantBasePrice: 10.0, TenantPricePerKM: 1.0,
		Latitude: 30.0444, Longitude: 31.2357,
	})

	tokenOwner, _ := jwtutil.GenerateToken("closed-owner", "owner", "closed-owner", "owner@example.com")
	tokenUser, _ := jwtutil.GenerateToken("cust-1", "user", "closed-owner", "cust@example.com")
	loc := map[string]any{"latitude": 30.0444, "longitude": 31.2357}
	dest := map[string]any{"latitude": 30.05, "longitude": 31.24}

	// Lookup path (no owner token): service resolves the closed tenant.
	rec := postClosedStatusTrack(t, u, map[string]any{
		"service_id": "svc-closed", "user_id": tokenUser, "payment_method": "cod",
		"location": loc, "destination": dest,
	})
	if rec.Code != http.StatusPaymentRequired {
		t.Fatalf("expected 402 for closed tenant (lookup path), got %d: %s", rec.Code, rec.Body.String())
	}
	assertClosedCopy(t, rec.Body.String())

	// Owner-token path: closed owner JWT supplied explicitly.
	rec = postClosedStatusTrack(t, u, map[string]any{
		"owner_id": tokenOwner, "service_id": "svc-closed", "user_id": tokenUser,
		"payment_method": "cod", "location": loc, "destination": dest,
	})
	if rec.Code != http.StatusPaymentRequired {
		t.Fatalf("expected 402 for closed tenant (owner-token path), got %d: %s", rec.Code, rec.Body.String())
	}
	assertClosedCopy(t, rec.Body.String())

	// No job record may be created for a rejected booking.
	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("failed to parse rejection body: %v", err)
	}
	if _, hasJob := body["job"]; hasJob {
		t.Errorf("rejected booking must not include a job record: %s", rec.Body.String())
	}
}

func assertClosedCopy(t *testing.T, body string) {
	t.Helper()
	var decoded map[string]any
	if err := json.Unmarshal([]byte(body), &decoded); err != nil {
		t.Fatalf("rejection body is not JSON: %v", err)
	}
	if decoded["error"] != "service_unavailable" {
		t.Errorf("expected error=service_unavailable, got body: %s", body)
	}
	msg, _ := decoded["message"].(string)
	if !strings.Contains(msg, "temporarily closed") {
		t.Errorf("expected customer-safe closed message, got: %s", body)
	}
	lowered := strings.ToLower(body)
	if strings.Contains(lowered, "upgrade_required") || strings.Contains(lowered, "subscription") {
		t.Errorf("rejection must not leak subscription-tier language to customers: %s", body)
	}
}

func TestTrackJob_OpenTenantProceeds(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	s, _, ctx, cleanup := setupClosedStatusHarness(t)
	defer cleanup()
	u, _ := trackJobClosedStatusHarness(t, s)

	seedClosedStatusSub(t, s, ctx, "open-owner", models.PlanPaid, time.Now().UTC().Add(time.Hour))
	s.CreateService(ctx, &models.Service{
		ID: "svc-open", TenantID: "open-owner", Name: "Open Shop",
		Category: "delivery", TenantBasePrice: 10.0, TenantPricePerKM: 1.0,
		Latitude: 30.0444, Longitude: 31.2357,
	})

	tokenUser, _ := jwtutil.GenerateToken("cust-1", "user", "open-owner", "cust@example.com")
	rec := postClosedStatusTrack(t, u, map[string]any{
		"service_id": "svc-open", "user_id": tokenUser, "payment_method": "cod",
		"location":    map[string]any{"latitude": 30.0444, "longitude": 31.2357},
		"destination": map[string]any{"latitude": 30.05, "longitude": 31.24},
	})
	// No couriers seeded: cascade path yields 201 "unavailable", proving the
	// closed-gate let a healthy booking through instead of rejecting it.
	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201 for open tenant, got %d: %s", rec.Code, rec.Body.String())
	}
}
