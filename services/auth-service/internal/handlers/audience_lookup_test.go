package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/project/auth-service/internal/models"
)

func TestAudienceLookup(t *testing.T) {
	auth, s, cleanup := setupTestAuth(t)
	if auth == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()

	// 1. Seed active client
	client1 := &models.User{
		ID:            "cust-1",
		Email:         "cust1@example.com",
		Username:      "customer_one",
		Phone:         "+201011112222",
		Role:          models.RoleUser,
		IsActive:      true,
		AccountStatus: models.AccountStatusActive,
		CreatedAt:     time.Now().UTC(),
	}
	if err := s.CreateUser(ctx, client1); err != nil {
		t.Fatalf("failed to create client1: %v", err)
	}

	// 2. Seed active owner
	owner1 := &models.User{
		ID:            "tenant-alpha",
		Email:         "owner1@example.com",
		Username:      "owner_alpha",
		Phone:         "+201033334444",
		Role:          models.RoleOwner,
		TenantID:      "tenant-alpha",
		IsActive:      true,
		AccountStatus: models.AccountStatusActive,
		CreatedAt:     time.Now().UTC(),
	}
	if err := s.CreateUser(ctx, owner1); err != nil {
		t.Fatalf("failed to create owner1: %v", err)
	}

	// 3. Seed active courier belonging to tenant-alpha
	courier1 := &models.User{
		ID:            "courier-1",
		Email:         "courier1@example.com",
		Username:      "courier_one",
		Phone:         "+201055556666",
		Role:          models.RoleEmployee,
		OwnerID:       "tenant-alpha",
		TenantID:      "tenant-alpha",
		IsActive:      true,
		AccountStatus: models.AccountStatusActive,
		CreatedAt:     time.Now().UTC(),
	}
	if err := s.CreateUser(ctx, courier1); err != nil {
		t.Fatalf("failed to create courier1: %v", err)
	}

	// 4. Seed suspended courier (MUST BE SKIPPED)
	courierSuspended := &models.User{
		ID:            "courier-suspended",
		Email:         "courier_bad@example.com",
		Username:      "courier_suspended",
		Phone:         "+201077778888",
		Role:          models.RoleEmployee,
		OwnerID:       "tenant-alpha",
		TenantID:      "tenant-alpha",
		IsActive:      false,
		AccountStatus: models.AccountStatusSuspended,
		CreatedAt:     time.Now().UTC(),
	}
	if err := s.CreateUser(ctx, courierSuspended); err != nil {
		t.Fatalf("failed to create courierSuspended: %v", err)
	}

	callLookup := func(body map[string]any) *httptest.ResponseRecorder {
		b, _ := json.Marshal(body)
		req := httptest.NewRequest(http.MethodPost, "/auth/internal/audience-lookup", bytes.NewReader(b))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("X-Internal-Token", auth.internalServiceToken)
		rec := httptest.NewRecorder()
		auth.AudienceLookup(rec, req)
		return rec
	}

	// Test 1: Single user by ID
	t.Run("User by ID", func(t *testing.T) {
		rec := callLookup(map[string]any{"kind": "user", "user_id": "cust-1"})
		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 OK, got %d: %s", rec.Code, rec.Body.String())
		}
		var resp map[string]any
		_ = json.NewDecoder(rec.Body).Decode(&resp)
		if resp["total"].(float64) != 1 {
			t.Errorf("expected total 1, got %v", resp["total"])
		}
	})

	// Test 2: Single user by phone
	t.Run("User by Phone", func(t *testing.T) {
		rec := callLookup(map[string]any{"kind": "user", "phone": "+201011112222"})
		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 OK, got %d", rec.Code)
		}
		var resp map[string]any
		_ = json.NewDecoder(rec.Body).Decode(&resp)
		if resp["total"].(float64) != 1 {
			t.Errorf("expected total 1, got %v", resp["total"])
		}
	})

	// Test 3: Suspended user is skipped
	t.Run("Suspended user skipped", func(t *testing.T) {
		rec := callLookup(map[string]any{"kind": "user", "user_id": "courier-suspended"})
		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 OK, got %d", rec.Code)
		}
		var resp map[string]any
		_ = json.NewDecoder(rec.Body).Decode(&resp)
		if resp["total"].(float64) != 0 {
			t.Errorf("expected total 0 for suspended user, got %v", resp["total"])
		}
	})

	// Test 4: Role customers
	t.Run("Role customers", func(t *testing.T) {
		rec := callLookup(map[string]any{"kind": "role", "role": "customers"})
		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 OK, got %d", rec.Code)
		}
		var resp map[string]any
		_ = json.NewDecoder(rec.Body).Decode(&resp)
		if resp["total"].(float64) < 1 {
			t.Errorf("expected at least 1 customer, got %v", resp["total"])
		}
	})

	// Test 5: Role couriers (only active courier, skipping suspended)
	t.Run("Role couriers skips suspended", func(t *testing.T) {
		rec := callLookup(map[string]any{"kind": "role", "role": "couriers"})
		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 OK, got %d", rec.Code)
		}
		var resp struct {
			UserIDs []string `json:"user_ids"`
			Total   int      `json:"total"`
		}
		_ = json.NewDecoder(rec.Body).Decode(&resp)
		for _, uid := range resp.UserIDs {
			if uid == "courier-suspended" {
				t.Fatalf("suspended courier found in couriers role audience: %v", resp.UserIDs)
			}
		}
	})

	// Test 6: Tenant audience (owner + couriers)
	t.Run("Tenant audience", func(t *testing.T) {
		rec := callLookup(map[string]any{"kind": "tenant", "tenant_id": "tenant-alpha"})
		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 OK, got %d", rec.Code)
		}
		var resp struct {
			UserIDs []string `json:"user_ids"`
			Total   int      `json:"total"`
		}
		_ = json.NewDecoder(rec.Body).Decode(&resp)
		if resp.Total != 2 {
			t.Errorf("expected 2 active members (owner + 1 courier), got %d (%v)", resp.Total, resp.UserIDs)
		}
	})

	// Test 7: Everyone audience (all active users across roles, excluding suspended)
	t.Run("Everyone audience", func(t *testing.T) {
		rec := callLookup(map[string]any{"kind": "everyone"})
		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 OK, got %d", rec.Code)
		}
		var resp struct {
			UserIDs []string `json:"user_ids"`
			Total   int      `json:"total"`
		}
		_ = json.NewDecoder(rec.Body).Decode(&resp)
		for _, uid := range resp.UserIDs {
			if uid == "courier-suspended" {
				t.Fatalf("suspended courier found in everyone audience: %v", resp.UserIDs)
			}
		}
	})

	// Test 8: Missing internal token -> 401
	t.Run("Missing internal token", func(t *testing.T) {
		b, _ := json.Marshal(map[string]any{"kind": "everyone"})
		req := httptest.NewRequest(http.MethodPost, "/auth/internal/audience-lookup", bytes.NewReader(b))
		rec := httptest.NewRecorder()
		auth.AudienceLookup(rec, req)
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("expected 401 Unauthorized, got %d", rec.Code)
		}
	})
}
