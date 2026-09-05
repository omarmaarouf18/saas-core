package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/project/shared/infra/jwtutil"
	"github.com/project/user-service/internal/models"
)

func TestGetAvailableEmployees(t *testing.T) {
	svc, s, cleanup := setupTestUserService(t)
	if svc == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	tenantA := "tenant-owner-A"
	tenantB := "tenant-owner-B"

	// Create JWTs
	ownerAToken, err := jwtutil.GenerateToken("owner-A-id", "owner", tenantA, "owner-a@example.com")
	if err != nil {
		t.Fatalf("failed to generate owner token: %v", err)
	}

	ownerBToken, err := jwtutil.GenerateToken("owner-B-id", "owner", tenantB, "owner-b@example.com")
	if err != nil {
		t.Fatalf("failed to generate owner B token: %v", err)
	}
	_ = ownerBToken

	customerToken, err := jwtutil.GenerateToken("cust-1-id", "customer", "", "customer@example.com")
	if err != nil {
		t.Fatalf("failed to generate customer token: %v", err)
	}

	// Seed fresh and stale employee locations
	now := time.Now().UTC()
	freshEmp1 := &models.EmployeeLocation{
		TenantID:   tenantA,
		EmployeeID: "emp-1",
		Latitude:   30.0444,
		Longitude:  31.2357,
		UpdatedAt:  now.Add(-1 * time.Minute),
	}
	freshEmp2 := &models.EmployeeLocation{
		TenantID:   tenantA,
		EmployeeID: "emp-2",
		Latitude:   30.0500,
		Longitude:  31.2400,
		UpdatedAt:  now.Add(-2 * time.Minute),
	}
	staleEmp := &models.EmployeeLocation{
		TenantID:   tenantA,
		EmployeeID: "emp-stale",
		Latitude:   30.0600,
		Longitude:  31.2500,
		UpdatedAt:  now.Add(-10 * time.Minute), // Older than 5m window
	}
	empTenantB := &models.EmployeeLocation{
		TenantID:   tenantB,
		EmployeeID: "emp-tenant-b",
		Latitude:   30.0700,
		Longitude:  31.2600,
		UpdatedAt:  now.Add(-1 * time.Minute),
	}

	if err := s.UpsertEmployeeLocation(ctx, freshEmp1); err != nil {
		t.Fatalf("failed to seed freshEmp1: %v", err)
	}
	if err := s.UpsertEmployeeLocation(ctx, freshEmp2); err != nil {
		t.Fatalf("failed to seed freshEmp2: %v", err)
	}
	if err := s.UpsertEmployeeLocation(ctx, staleEmp); err != nil {
		t.Fatalf("failed to seed staleEmp: %v", err)
	}
	if err := s.UpsertEmployeeLocation(ctx, empTenantB); err != nil {
		t.Fatalf("failed to seed empTenantB: %v", err)
	}

	t.Run("MethodNotAllowed", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodPost, "/users/employees/available", nil)
		rec := httptest.NewRecorder()
		svc.GetAvailableEmployees(rec, req)
		if rec.Code != http.StatusMethodNotAllowed {
			t.Errorf("expected 405, got %d", rec.Code)
		}
	})

	t.Run("UnauthorizedNoToken", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/users/employees/available", nil)
		rec := httptest.NewRecorder()
		svc.GetAvailableEmployees(rec, req)
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("expected 401, got %d", rec.Code)
		}
	})

	t.Run("OwnerSuccess_FiltersFreshAndTenant", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/users/employees/available", nil)
		req.Header.Set("Authorization", "Bearer "+ownerAToken)
		rec := httptest.NewRecorder()
		svc.GetAvailableEmployees(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
		}

		var res struct {
			Count     int                       `json:"count"`
			TenantID  string                    `json:"tenant_id"`
			Employees []models.EmployeeLocation `json:"employees"`
		}
		if err := json.Unmarshal(rec.Body.Bytes(), &res); err != nil {
			t.Fatalf("failed to decode response: %v", err)
		}

		if res.Count != 2 {
			t.Errorf("expected count 2, got %d", res.Count)
		}
		if res.TenantID != tenantA {
			t.Errorf("expected tenant %s, got %s", tenantA, res.TenantID)
		}
		if len(res.Employees) != 2 {
			t.Fatalf("expected 2 employees, got %d", len(res.Employees))
		}
	})

	t.Run("OwnerIDOR_Blocked", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/users/employees/available?tenant_id="+tenantB, nil)
		req.Header.Set("Authorization", "Bearer "+ownerAToken)
		rec := httptest.NewRecorder()
		svc.GetAvailableEmployees(rec, req)
		if rec.Code != http.StatusForbidden {
			t.Errorf("expected 403 Forbidden for IDOR mismatch, got %d: %s", rec.Code, rec.Body.String())
		}
	})

	t.Run("CustomerSuccessWithTenantID", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/users/employees/available?tenant_id="+tenantA, nil)
		req.Header.Set("Authorization", "Bearer "+customerToken)
		rec := httptest.NewRecorder()
		svc.GetAvailableEmployees(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
		}

		var res struct {
			Count     int                       `json:"count"`
			TenantID  string                    `json:"tenant_id"`
			Employees []models.EmployeeLocation `json:"employees"`
		}
		if err := json.Unmarshal(rec.Body.Bytes(), &res); err != nil {
			t.Fatalf("failed to decode response: %v", err)
		}
		if res.Count != 2 {
			t.Errorf("expected count 2, got %d", res.Count)
		}
	})

	t.Run("CustomerMissingTenantID", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/users/employees/available", nil)
		req.Header.Set("Authorization", "Bearer "+customerToken)
		rec := httptest.NewRecorder()
		svc.GetAvailableEmployees(rec, req)
		if rec.Code != http.StatusBadRequest {
			t.Errorf("expected 400 Bad Request, got %d: %s", rec.Code, rec.Body.String())
		}
	})

	t.Run("InternalTokenSuccess", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/users/employees/available?tenant_id="+tenantB, nil)
		req.Header.Set("X-Internal-Token", svc.internalServiceToken)
		rec := httptest.NewRecorder()
		svc.GetAvailableEmployees(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
		}

		var res struct {
			Count     int                       `json:"count"`
			TenantID  string                    `json:"tenant_id"`
			Employees []models.EmployeeLocation `json:"employees"`
		}
		if err := json.Unmarshal(rec.Body.Bytes(), &res); err != nil {
			t.Fatalf("failed to decode response: %v", err)
		}
		if res.Count != 1 {
			t.Errorf("expected count 1 for tenantB, got %d", res.Count)
		}
		if len(res.Employees) != 1 || res.Employees[0].EmployeeID != "emp-tenant-b" {
			t.Errorf("expected emp-tenant-b, got %+v", res.Employees)
		}
	})

	t.Run("InternalTokenMissingTenantID", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/users/employees/available", nil)
		req.Header.Set("X-Internal-Token", svc.internalServiceToken)
		rec := httptest.NewRecorder()
		svc.GetAvailableEmployees(rec, req)
		if rec.Code != http.StatusBadRequest {
			t.Errorf("expected 400 Bad Request, got %d: %s", rec.Code, rec.Body.String())
		}
	})
}
