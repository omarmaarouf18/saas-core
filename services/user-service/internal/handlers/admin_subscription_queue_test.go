package handlers

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

	"github.com/project/user-service/internal/config"
	"github.com/project/user-service/internal/models"
	"github.com/project/user-service/internal/store"
)

func setupSubscriptionQueueTestEnv(t *testing.T) (*UserService, *store.MongoDB, string) {
	t.Helper()
	mongoURI := os.Getenv("MONGODB_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://root:devpassword123@localhost:27017/saas_platform?authSource=admin"
	}
	dbName := fmt.Sprintf("saas_sub_queue_test_%d", time.Now().UnixNano())
	var mongoStore *store.MongoDB
	var err error
	for attempt := 0; attempt < 3; attempt++ {
		c, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		mongoStore, err = store.NewMongoDB(c, mongoURI, dbName)
		cancel()
		if err == nil {
			break
		}
		time.Sleep(200 * time.Millisecond)
	}
	if err != nil {
		t.Skipf("skipping test; MongoDB not available: %v", err)
		return nil, nil, ""
	}

	validReviewerToken := "valid-reviewer-token-" + generateID()

	mockAuthServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		internalTok := r.Header.Get("X-Internal-Token")
		if internalTok != "test-internal-token" {
			w.WriteHeader(http.StatusForbidden)
			_, _ = w.Write([]byte(`{"error":"invalid internal token"}`))
			return
		}

		if r.URL.Path == "/auth/reviewer/verify" {
			if r.Header.Get("X-Reviewer-Token") == validReviewerToken {
				w.WriteHeader(http.StatusOK)
				_, _ = w.Write([]byte(`{"id":"reviewer-sub-admin","name":"Sub Reviewer"}`))
				return
			}
			w.WriteHeader(http.StatusUnauthorized)
			_, _ = w.Write([]byte(`{"error":"invalid reviewer token"}`))
			return
		}

		if r.URL.Path == "/auth/user" {
			id := r.URL.Query().Get("id")
			w.WriteHeader(http.StatusOK)
			switch id {
			case "tenant-old":
				_ = json.NewEncoder(w).Encode(map[string]any{
					"id":             id,
					"username":       "Alpha Logistics LLC",
					"email":          "alpha@example.com",
					"phone":          "+201001112222",
					"is_active":      true,
					"account_status": "active",
				})
			case "tenant-new":
				_ = json.NewEncoder(w).Encode(map[string]any{
					"id":             id,
					"username":       "Beta Express Inc",
					"email":          "beta@example.com",
					"phone":          "+201003334444",
					"is_active":      true,
					"account_status": "active",
				})
			default:
				_ = json.NewEncoder(w).Encode(map[string]any{
					"id":             id,
					"username":       "Generic Tenant " + id,
					"email":          id + "@example.com",
					"phone":          "+201009998888",
					"is_active":      true,
					"account_status": "active",
				})
			}
			return
		}

		w.WriteHeader(http.StatusNotFound)
	}))

	t.Cleanup(func() {
		mockAuthServer.Close()
		dropCtx, dropCancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer dropCancel()
		_ = mongoStore.DropDatabase(dropCtx)
		_ = mongoStore.Close(dropCtx)
	})

	cfg := &config.Config{
		InternalServiceToken: "test-internal-token",
		AuthServiceURL:       mockAuthServer.URL,
	}

	svc := NewUserService(mongoStore, cfg, nil)
	return svc, mongoStore, validReviewerToken
}

func TestAdminSubscriptionQueue_PendingPaymentOldestFirst(t *testing.T) {
	svc, mongoStore, validReviewerToken := setupSubscriptionQueueTestEnv(t)
	if svc == nil {
		return
	}

	ctx := context.Background()
	now := time.Now().UTC()

	// Seed 4 subscriptions with different tiers and creation times
	subOld := &models.Subscription{
		ID:        "sub-old-1",
		TenantID:  "tenant-old",
		Tier:      models.PlanPendingPayment,
		StartedAt: now.Add(-3 * time.Hour),
		Reason:    "Requested upgrade to paid",
	}
	subNew := &models.Subscription{
		ID:        "sub-new-2",
		TenantID:  "tenant-new",
		Tier:      models.PlanPendingPayment,
		StartedAt: now.Add(-1 * time.Hour),
		Reason:    "Upgrade requested",
	}
	subPaid := &models.Subscription{
		ID:        "sub-paid-3",
		TenantID:  "tenant-paid",
		Tier:      models.PlanPaid,
		StartedAt: now.Add(-5 * time.Hour),
	}
	subFree := &models.Subscription{
		ID:        "sub-free-4",
		TenantID:  "tenant-free",
		Tier:      models.PlanFree,
		StartedAt: now.Add(-4 * time.Hour),
	}

	for _, s := range []*models.Subscription{subOld, subNew, subPaid, subFree} {
		if err := mongoStore.UpsertSubscription(ctx, s); err != nil {
			t.Fatalf("failed to seed subscription: %v", err)
		}
	}

	req := httptest.NewRequest(http.MethodGet, "/admin/subscriptions/queue", nil)
	req.Header.Set("X-Internal-Token", "test-internal-token")
	req.Header.Set("X-Reviewer-Token", validReviewerToken)
	rec := httptest.NewRecorder()

	svc.AdminSubscriptionQueue(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK, got %d: %s", rec.Code, rec.Body.String())
	}

	var resp models.AdminSubscriptionQueueResponse
	if err := json.NewDecoder(rec.Body).Decode(&resp); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}

	if resp.Total != 2 {
		t.Fatalf("expected total 2, got %d", resp.Total)
	}
	if len(resp.Queue) != 2 {
		t.Fatalf("expected 2 queue items, got %d", len(resp.Queue))
	}

	// Verify oldest first ordering: subOld (3h ago) before subNew (1h ago)
	item1 := resp.Queue[0]
	if item1.ID != "sub-old-1" || item1.TenantID != "tenant-old" {
		t.Fatalf("expected first item to be sub-old-1, got %+v", item1)
	}
	if item1.TenantName != "Alpha Logistics LLC" {
		t.Fatalf("expected tenant_name 'Alpha Logistics LLC', got '%s'", item1.TenantName)
	}
	if item1.RequestedPlan != "paid" {
		t.Fatalf("expected requested_plan 'paid', got '%s'", item1.RequestedPlan)
	}
	if item1.OwnerContact.Email != "alpha@example.com" || item1.OwnerContact.Phone != "+201001112222" {
		t.Fatalf("unexpected owner_contact: %+v", item1.OwnerContact)
	}
	if item1.Status != "pending_payment" || item1.Tier != models.PlanPendingPayment {
		t.Fatalf("unexpected tier/status: %s / %s", item1.Tier, item1.Status)
	}

	item2 := resp.Queue[1]
	if item2.ID != "sub-new-2" || item2.TenantID != "tenant-new" {
		t.Fatalf("expected second item to be sub-new-2, got %+v", item2)
	}
	if item2.TenantName != "Beta Express Inc" {
		t.Fatalf("expected tenant_name 'Beta Express Inc', got '%s'", item2.TenantName)
	}
	if item2.OwnerContact.Email != "beta@example.com" {
		t.Fatalf("unexpected owner_contact: %+v", item2.OwnerContact)
	}
}

func TestAdminSubscriptionQueue_ActivateFlow(t *testing.T) {
	svc, mongoStore, validReviewerToken := setupSubscriptionQueueTestEnv(t)
	if svc == nil {
		return
	}

	ctx := context.Background()
	now := time.Now().UTC()

	sub := &models.Subscription{
		ID:        "sub-activate-test",
		TenantID:  "tenant-old",
		Tier:      models.PlanPendingPayment,
		StartedAt: now.Add(-2 * time.Hour),
	}
	if err := mongoStore.UpsertSubscription(ctx, sub); err != nil {
		t.Fatalf("failed to seed subscription: %v", err)
	}

	// 1. Confirm it appears in the queue
	getReq := httptest.NewRequest(http.MethodGet, "/admin/subscriptions/queue", nil)
	getReq.Header.Set("X-Internal-Token", "test-internal-token")
	getReq.Header.Set("X-Reviewer-Token", validReviewerToken)
	getRec := httptest.NewRecorder()
	svc.AdminSubscriptionQueue(getRec, getReq)
	if getRec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", getRec.Code)
	}
	var queueResp models.AdminSubscriptionQueueResponse
	_ = json.NewDecoder(getRec.Body).Decode(&queueResp)
	if queueResp.Total != 1 || queueResp.Queue[0].ID != "sub-activate-test" {
		t.Fatalf("expected 1 queue item, got %+v", queueResp)
	}

	// 2. Perform activate flow like the reviewer console does
	actPayload := `{"tenant_id":"tenant-old","subscription_id":"sub-activate-test","duration_days":45}`
	actReq := httptest.NewRequest(http.MethodPost, "/admin/subscriptions/activate", strings.NewReader(actPayload))
	actReq.Header.Set("Content-Type", "application/json")
	actReq.Header.Set("X-Internal-Token", "test-internal-token")
	actReq.Header.Set("X-Reviewer-Token", validReviewerToken)
	actRec := httptest.NewRecorder()
	svc.AdminActivateSubscription(actRec, actReq)

	if actRec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK from activate, got %d: %s", actRec.Code, actRec.Body.String())
	}

	var actResp struct {
		Message      string              `json:"message"`
		Subscription models.Subscription `json:"subscription"`
	}
	if err := json.NewDecoder(actRec.Body).Decode(&actResp); err != nil {
		t.Fatalf("failed to decode activate response: %v", err)
	}
	if actResp.Subscription.Tier != models.PlanPaid {
		t.Fatalf("expected subscription tier 'paid', got '%s'", actResp.Subscription.Tier)
	}
	if actResp.Subscription.ActivatedBy != "reviewer-sub-admin" {
		t.Fatalf("expected activated_by 'reviewer-sub-admin', got '%s'", actResp.Subscription.ActivatedBy)
	}

	// 3. Confirm it is now gone from the queue
	getRec2 := httptest.NewRecorder()
	getReq2 := httptest.NewRequest(http.MethodGet, "/admin/subscriptions/queue", nil)
	getReq2.Header.Set("X-Internal-Token", "test-internal-token")
	getReq2.Header.Set("X-Reviewer-Token", validReviewerToken)
	svc.AdminSubscriptionQueue(getRec2, getReq2)

	var queueResp2 models.AdminSubscriptionQueueResponse
	_ = json.NewDecoder(getRec2.Body).Decode(&queueResp2)
	if queueResp2.Total != 0 || len(queueResp2.Queue) != 0 {
		t.Fatalf("expected queue to be empty after activation, got total=%d", queueResp2.Total)
	}
}

func TestAdminSubscriptionQueue_AuthAndMethodValidation(t *testing.T) {
	svc, _, validReviewerToken := setupSubscriptionQueueTestEnv(t)
	if svc == nil {
		return
	}

	t.Run("Missing Internal Token", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/admin/subscriptions/queue", nil)
		req.Header.Set("X-Reviewer-Token", validReviewerToken)
		rec := httptest.NewRecorder()
		svc.AdminSubscriptionQueue(rec, req)
		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("expected 401, got %d", rec.Code)
		}
	})

	t.Run("Missing Reviewer Token", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/admin/subscriptions/queue", nil)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		rec := httptest.NewRecorder()
		svc.AdminSubscriptionQueue(rec, req)
		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("expected 401, got %d", rec.Code)
		}
	})

	t.Run("Invalid Reviewer Token", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/admin/subscriptions/queue", nil)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", "bogus-token")
		rec := httptest.NewRecorder()
		svc.AdminSubscriptionQueue(rec, req)
		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("expected 401, got %d", rec.Code)
		}
	})

	t.Run("Method Not Allowed", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodPost, "/admin/subscriptions/queue", nil)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validReviewerToken)
		rec := httptest.NewRecorder()
		svc.AdminSubscriptionQueue(rec, req)
		if rec.Code != http.StatusMethodNotAllowed {
			t.Fatalf("expected 405, got %d", rec.Code)
		}
	})
}

func TestAdminSubscriptionQueue_Pagination(t *testing.T) {
	svc, mongoStore, validReviewerToken := setupSubscriptionQueueTestEnv(t)
	if svc == nil {
		return
	}

	ctx := context.Background()
	now := time.Now().UTC()

	// Seed 5 pending subscriptions with increasing started_at (oldest to newest)
	for i := 1; i <= 5; i++ {
		sub := &models.Subscription{
			ID:        fmt.Sprintf("sub-page-%d", i),
			TenantID:  fmt.Sprintf("tenant-%d", i),
			Tier:      models.PlanPendingPayment,
			StartedAt: now.Add(time.Duration(i-10) * time.Hour), // i=1: -9h, i=2: -8h, etc.
		}
		if err := mongoStore.UpsertSubscription(ctx, sub); err != nil {
			t.Fatalf("failed to seed: %v", err)
		}
	}

	// Page 1, limit 2 -> should return sub-page-1, sub-page-2
	req1 := httptest.NewRequest(http.MethodGet, "/admin/subscriptions/queue?page=1&limit=2", nil)
	req1.Header.Set("X-Internal-Token", "test-internal-token")
	req1.Header.Set("X-Reviewer-Token", validReviewerToken)
	rec1 := httptest.NewRecorder()
	svc.AdminSubscriptionQueue(rec1, req1)
	if rec1.Code != http.StatusOK {
		t.Fatalf("page 1 failed with %d: %s", rec1.Code, rec1.Body.String())
	}
	var resp1 models.AdminSubscriptionQueueResponse
	_ = json.NewDecoder(rec1.Body).Decode(&resp1)
	if resp1.Total != 5 || len(resp1.Queue) != 2 {
		t.Fatalf("expected total 5, len 2, got total=%d len=%d", resp1.Total, len(resp1.Queue))
	}
	if resp1.Queue[0].ID != "sub-page-1" || resp1.Queue[1].ID != "sub-page-2" {
		t.Fatalf("unexpected items on page 1: %+v", resp1.Queue)
	}

	// Page 2, limit 2 -> should return sub-page-3, sub-page-4
	req2 := httptest.NewRequest(http.MethodGet, "/admin/subscriptions/queue?page=2&limit=2", nil)
	req2.Header.Set("X-Internal-Token", "test-internal-token")
	req2.Header.Set("X-Reviewer-Token", validReviewerToken)
	rec2 := httptest.NewRecorder()
	svc.AdminSubscriptionQueue(rec2, req2)
	var resp2 models.AdminSubscriptionQueueResponse
	_ = json.NewDecoder(rec2.Body).Decode(&resp2)
	if len(resp2.Queue) != 2 || resp2.Queue[0].ID != "sub-page-3" || resp2.Queue[1].ID != "sub-page-4" {
		t.Fatalf("unexpected items on page 2: %+v", resp2.Queue)
	}
}
