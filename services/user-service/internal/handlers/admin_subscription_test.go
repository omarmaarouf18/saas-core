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
	"sync"
	"testing"
	"time"

	"github.com/project/user-service/internal/config"
	"github.com/project/user-service/internal/models"
	"github.com/project/user-service/internal/store"
)

func setupAdminSubscriptionTestEnvironment(t *testing.T) (*UserService, *store.MongoDB, string, *httptest.Server) {
	t.Helper()

	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://root:devpassword123@localhost:27017/saas_platform?authSource=admin"
	}
	dbName := fmt.Sprintf("saas_sub_test_%d", time.Now().UnixNano())
	var mongoStore *store.MongoDB
	var err error
	for attempt := 0; attempt < 3; attempt++ {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		mongoStore, err = store.NewMongoDB(ctx, mongoURI, dbName)
		cancel()
		if err == nil {
			break
		}
		time.Sleep(200 * time.Millisecond)
	}
	if err != nil {
		t.Skipf("Skipping admin subscription integration test: MongoDB not available (%v)", err)
		return nil, nil, "", nil
	}

	validReviewerToken := "valid-reviewer-sub-token"

	// Mock Auth Service for reviewer verification
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
				_, _ = w.Write([]byte(`{"id":"reviewer-sub-admin","name":"Sub Ops Admin"}`))
				return
			}
			w.WriteHeader(http.StatusUnauthorized)
			_, _ = w.Write([]byte(`{"error":"invalid reviewer token"}`))
			return
		}

		if r.URL.Path == "/auth/user" {
			id := r.URL.Query().Get("id")
			isActive := true
			accountStatus := "active"
			if strings.Contains(id, "suspended") {
				isActive = false
				accountStatus = "suspended"
			}
			w.WriteHeader(http.StatusOK)
			_ = json.NewEncoder(w).Encode(map[string]any{
				"id":             id,
				"is_active":      isActive,
				"account_status": accountStatus,
			})
			return
		}

		w.WriteHeader(http.StatusNotFound)
	}))

	t.Cleanup(func() {
		mockServer.Close()
		dropCtx, dropCancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer dropCancel()
		_ = mongoStore.DropDatabase(dropCtx)
		_ = mongoStore.Close(dropCtx)
	})

	cfg := &config.Config{
		InternalServiceToken: "test-internal-token",
		AuthServiceURL:       mockServer.URL,
	}

	svc := NewUserService(mongoStore, cfg, nil)
	return svc, mongoStore, validReviewerToken, mockServer
}

func TestAdminSubscription_Authentication(t *testing.T) {
	svc, _, validToken, _ := setupAdminSubscriptionTestEnvironment(t)
	if svc == nil {
		return
	}

	t.Run("Missing Internal Token Rejected", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/users/admin/subscriptions", nil)
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		svc.AdminListSubscriptions(rec, req)

		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("expected 401 Unauthorized, got %d", rec.Code)
		}
	})

	t.Run("Missing Reviewer Token Rejected", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/users/admin/subscriptions", nil)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		rec := httptest.NewRecorder()
		svc.AdminListSubscriptions(rec, req)

		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("expected 401 Unauthorized, got %d", rec.Code)
		}
	})

	t.Run("Invalid Reviewer Token Rejected", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/users/admin/subscriptions", nil)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", "wrong-reviewer-token")
		rec := httptest.NewRecorder()
		svc.AdminListSubscriptions(rec, req)

		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("expected 401 Unauthorized, got %d", rec.Code)
		}
	})

	t.Run("Valid Reviewer Token Succeeded", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/users/admin/subscriptions", nil)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		svc.AdminListSubscriptions(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 OK, got %d: %s", rec.Code, rec.Body.String())
		}
	})
}

func TestAdminSubscription_ListingAndFiltering(t *testing.T) {
	svc, mongoStore, validToken, _ := setupAdminSubscriptionTestEnvironment(t)
	if svc == nil {
		return
	}
	ctx := context.Background()

	// Seed subscriptions in various statuses
	sub1 := &models.Subscription{
		ID:        "sub-pending-1",
		TenantID:  "tenant-alpha",
		Tier:      models.PlanPendingPayment,
		StartedAt: time.Now().UTC().Add(-2 * time.Hour),
	}
	sub2 := &models.Subscription{
		ID:        "sub-paid-1",
		TenantID:  "tenant-beta",
		Tier:      models.PlanPaid,
		StartedAt: time.Now().UTC().Add(-24 * time.Hour),
		ExpiresAt: time.Now().UTC().Add(29 * 24 * time.Hour),
	}
	sub3 := &models.Subscription{
		ID:        "sub-free-1",
		TenantID:  "tenant-gamma",
		Tier:      models.PlanFree,
		StartedAt: time.Now().UTC().Add(-48 * time.Hour),
	}

	_ = mongoStore.UpsertSubscription(ctx, sub1)
	_ = mongoStore.UpsertSubscription(ctx, sub2)
	_ = mongoStore.UpsertSubscription(ctx, sub3)

	t.Run("List All Subscriptions", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/users/admin/subscriptions", nil)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		svc.AdminListSubscriptions(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 OK, got %d: %s", rec.Code, rec.Body.String())
		}

		var resp models.AdminSubscriptionListResponse
		_ = json.NewDecoder(rec.Body).Decode(&resp)
		if resp.Total != 3 {
			t.Fatalf("expected 3 total subscriptions, got %d", resp.Total)
		}
	})

	t.Run("Filter By Status Pending Payment", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/users/admin/subscriptions?status=pending_payment", nil)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		svc.AdminListSubscriptions(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 OK, got %d: %s", rec.Code, rec.Body.String())
		}

		var resp models.AdminSubscriptionListResponse
		_ = json.NewDecoder(rec.Body).Decode(&resp)
		if resp.Total != 1 || len(resp.Subscriptions) != 1 {
			t.Fatalf("expected 1 pending subscription, got total=%d len=%d", resp.Total, len(resp.Subscriptions))
		}
		if resp.Subscriptions[0].TenantID != "tenant-alpha" {
			t.Errorf("expected tenant-alpha, got %s", resp.Subscriptions[0].TenantID)
		}
	})

	t.Run("Search By Tenant ID", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/users/admin/subscriptions?search=beta", nil)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		svc.AdminListSubscriptions(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 OK, got %d: %s", rec.Code, rec.Body.String())
		}

		var resp models.AdminSubscriptionListResponse
		_ = json.NewDecoder(rec.Body).Decode(&resp)
		if resp.Total != 1 || resp.Subscriptions[0].TenantID != "tenant-beta" {
			t.Fatalf("search filter failed: %+v", resp)
		}
	})
}

func TestAdminSubscription_ActivationAndRevocationLifecycle(t *testing.T) {
	svc, mongoStore, validToken, _ := setupAdminSubscriptionTestEnvironment(t)
	if svc == nil {
		return
	}
	ctx := context.Background()

	sub := &models.Subscription{
		ID:        "sub-activate-test",
		TenantID:  "tenant-activate-1",
		Tier:      models.PlanPendingPayment,
		StartedAt: time.Now().UTC(),
	}
	_ = mongoStore.UpsertSubscription(ctx, sub)

	t.Run("Activate Pending Subscription", func(t *testing.T) {
		body, _ := json.Marshal(models.AdminActivateSubscriptionRequest{
			TenantID:     "tenant-activate-1",
			DurationDays: 60,
		})
		req := httptest.NewRequest(http.MethodPost, "/users/admin/subscriptions/activate", bytes.NewReader(body))
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		svc.AdminActivateSubscription(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 OK, got %d: %s", rec.Code, rec.Body.String())
		}

		updated := mongoStore.GetSubscription(ctx, "tenant-activate-1")
		if updated == nil || updated.Tier != models.PlanPaid {
			t.Fatalf("expected tier paid, got %+v", updated)
		}
		if updated.ActivatedBy != "reviewer-sub-admin" {
			t.Errorf("expected activated_by reviewer-sub-admin, got %s", updated.ActivatedBy)
		}
		if updated.ExpiresAt.IsZero() {
			t.Errorf("expected non-zero expires_at")
		}
	})

	t.Run("Activate Already Active Subscription Rejection", func(t *testing.T) {
		body, _ := json.Marshal(models.AdminActivateSubscriptionRequest{
			TenantID: "tenant-activate-1",
		})
		req := httptest.NewRequest(http.MethodPost, "/users/admin/subscriptions/activate", bytes.NewReader(body))
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		svc.AdminActivateSubscription(rec, req)

		if rec.Code != http.StatusConflict {
			t.Fatalf("expected 409 Conflict on double activation, got %d", rec.Code)
		}
	})

	t.Run("Revoke Subscription Reason Validations", func(t *testing.T) {
		cases := []struct {
			name   string
			reason string
		}{
			{"Empty reason", ""},
			{"Whitespace reason", "   "},
			{"Oversized reason", strings.Repeat("x", 1001)},
		}

		for _, tc := range cases {
			t.Run(tc.name, func(t *testing.T) {
				body, _ := json.Marshal(models.AdminRevokeSubscriptionRequest{
					TenantID: "tenant-activate-1",
					Reason:   tc.reason,
				})
				req := httptest.NewRequest(http.MethodPost, "/users/admin/subscriptions/revoke", bytes.NewReader(body))
				req.Header.Set("X-Internal-Token", "test-internal-token")
				req.Header.Set("X-Reviewer-Token", validToken)
				rec := httptest.NewRecorder()
				svc.AdminRevokeSubscription(rec, req)

				if rec.Code != http.StatusBadRequest {
					t.Fatalf("expected 400 Bad Request, got %d: %s", rec.Code, rec.Body.String())
				}
			})
		}
	})

	t.Run("Revoke Active Subscription", func(t *testing.T) {
		body, _ := json.Marshal(models.AdminRevokeSubscriptionRequest{
			TenantID: "tenant-activate-1",
			Reason:   "Failed offline bank transfer payment verification",
		})
		req := httptest.NewRequest(http.MethodPost, "/users/admin/subscriptions/revoke", bytes.NewReader(body))
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		svc.AdminRevokeSubscription(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 OK, got %d: %s", rec.Code, rec.Body.String())
		}

		updated := mongoStore.GetSubscription(ctx, "tenant-activate-1")
		if updated == nil || updated.Tier != models.PlanCancelled {
			t.Fatalf("expected tier cancelled, got %+v", updated)
		}
		if updated.RevokedBy != "reviewer-sub-admin" {
			t.Errorf("expected revoked_by reviewer-sub-admin, got %s", updated.RevokedBy)
		}
		if updated.Reason != "Failed offline bank transfer payment verification" {
			t.Errorf("reason mismatch: %s", updated.Reason)
		}
	})

	t.Run("Revoke Non-Active Subscription Rejection", func(t *testing.T) {
		body, _ := json.Marshal(models.AdminRevokeSubscriptionRequest{
			TenantID: "tenant-activate-1",
			Reason:   "Another revocation attempt",
		})
		req := httptest.NewRequest(http.MethodPost, "/users/admin/subscriptions/revoke", bytes.NewReader(body))
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		svc.AdminRevokeSubscription(rec, req)

		if rec.Code != http.StatusConflict {
			t.Fatalf("expected 409 Conflict when revoking already cancelled subscription, got %d", rec.Code)
		}
	})
}

func TestAdminSubscription_CASConcurrencyRace(t *testing.T) {
	svc, mongoStore, validToken, _ := setupAdminSubscriptionTestEnvironment(t)
	if svc == nil {
		return
	}
	ctx := context.Background()

	sub := &models.Subscription{
		ID:        "sub-race-target",
		TenantID:  "tenant-race-target",
		Tier:      models.PlanPendingPayment,
		StartedAt: time.Now().UTC(),
	}
	_ = mongoStore.UpsertSubscription(ctx, sub)

	var wg sync.WaitGroup
	results := make([]int, 2)

	for i := 0; i < 2; i++ {
		wg.Add(1)
		idx := i
		go func() {
			defer wg.Done()
			body, _ := json.Marshal(models.AdminActivateSubscriptionRequest{
				TenantID:     "tenant-race-target",
				DurationDays: 30,
			})
			req := httptest.NewRequest(http.MethodPost, "/users/admin/subscriptions/activate", bytes.NewReader(body))
			req.Header.Set("X-Internal-Token", "test-internal-token")
			req.Header.Set("X-Reviewer-Token", validToken)
			rec := httptest.NewRecorder()
			svc.AdminActivateSubscription(rec, req)
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
		t.Fatalf("CAS concurrency race failure: expected exactly 1 200 OK and 1 409 Conflict, got: %+v", results)
	}
}

func TestAdminActivateSubscription_SuspendedTenantRejected_F07(t *testing.T) {
	svc, store, validToken, _ := setupAdminSubscriptionTestEnvironment(t)
	if svc == nil {
		return
	}
	ctx := context.Background()

	suspendedTenantID := "tenant-suspended-sub-target"
	_ = store.UpsertSubscription(ctx, &models.Subscription{
		ID:        "sub-suspended-123",
		TenantID:  suspendedTenantID,
		Tier:      models.PlanPendingPayment,
		StartedAt: time.Now().UTC(),
	})

	body, _ := json.Marshal(models.AdminActivateSubscriptionRequest{
		TenantID:     suspendedTenantID,
		DurationDays: 30,
	})
	req := httptest.NewRequest(http.MethodPost, "/users/admin/subscriptions/activate", bytes.NewReader(body))
	req.Header.Set("X-Internal-Token", "test-internal-token")
	req.Header.Set("X-Reviewer-Token", validToken)
	rec := httptest.NewRecorder()
	svc.AdminActivateSubscription(rec, req)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("F-07 Repro failure: expected 403 Forbidden for suspended tenant activation, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	var resp map[string]string
	_ = json.Unmarshal(rec.Body.Bytes(), &resp)
	if resp["error"] != "tenant_suspended" {
		t.Errorf("expected error 'tenant_suspended', got %q", resp["error"])
	}
}

func TestAdminSubscription_OversizedBodyRejected_F06(t *testing.T) {
	svc, _, validToken, _ := setupAdminSubscriptionTestEnvironment(t)
	if svc == nil {
		return
	}

	// 2 MB payload exceeding 1 MB LimitReader
	oversizedBody := strings.Repeat(" ", 2*1024*1024)

	t.Run("AdminActivateSubscription rejects oversized payload", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodPost, "/users/admin/subscriptions/activate", strings.NewReader(oversizedBody))
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		svc.AdminActivateSubscription(rec, req)

		if rec.Code != http.StatusBadRequest {
			t.Errorf("expected 400 Bad Request for oversized body, got %d", rec.Code)
		}
	})

	t.Run("AdminRevokeSubscription rejects oversized payload", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodPost, "/users/admin/subscriptions/revoke", strings.NewReader(oversizedBody))
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		svc.AdminRevokeSubscription(rec, req)

		if rec.Code != http.StatusBadRequest {
			t.Errorf("expected 400 Bad Request for oversized body, got %d", rec.Code)
		}
	})
}
