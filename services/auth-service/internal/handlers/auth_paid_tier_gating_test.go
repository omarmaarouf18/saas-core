package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/project/auth-service/internal/models"
	"github.com/project/shared/infra/resilience"
	"golang.org/x/crypto/bcrypt"
)

func TestToggleEmployee_PaidTierGating(t *testing.T) {
	a, s, cleanup := setupAuthReproTest(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	pwdHash, _ := bcrypt.GenerateFromPassword([]byte("Password123!"), bcrypt.MinCost)

	// Free owner account
	freeOwnerID := "free-owner-100"
	freeOwner := &models.User{
		ID:        freeOwnerID,
		Email:     "freeowner@example.com",
		Username:  "freeowner_test",
		Password:  string(pwdHash),
		Role:      models.RoleOwner,
		KYCStatus: models.KYCApproved,
		IsActive:  true,
	}
	if err := s.CreateUser(ctx, freeOwner); err != nil {
		t.Fatalf("failed to create free owner: %v", err)
	}

	// Paid owner account
	paidOwnerID := "paid-owner-200"
	paidOwner := &models.User{
		ID:        paidOwnerID,
		Email:     "paidowner@example.com",
		Username:  "paidowner_test",
		Password:  string(pwdHash),
		Role:      models.RoleOwner,
		KYCStatus: models.KYCApproved,
		IsActive:  true,
	}
	if err := s.CreateUser(ctx, paidOwner); err != nil {
		t.Fatalf("failed to create paid owner: %v", err)
	}

	// Employee under free owner
	freeEmp := &models.User{
		ID:        "emp-free-1",
		Email:     "emp-free@example.com",
		Username:  "empfree_test",
		Password:  string(pwdHash),
		Role:      models.RoleEmployee,
		TenantID:  freeOwnerID,
		OwnerID:   freeOwnerID,
		IsActive:  true,
		KYCStatus: models.KYCApproved,
	}
	if err := s.CreateUser(ctx, freeEmp); err != nil {
		t.Fatalf("failed to create employee for free owner: %v", err)
	}

	// Employee under paid owner
	paidEmp := &models.User{
		ID:        "emp-paid-2",
		Email:     "emp-paid@example.com",
		Username:  "emppaid_test",
		Password:  string(pwdHash),
		Role:      models.RoleEmployee,
		TenantID:  paidOwnerID,
		OwnerID:   paidOwnerID,
		IsActive:  true,
		KYCStatus: models.KYCApproved,
	}
	if err := s.CreateUser(ctx, paidEmp); err != nil {
		t.Fatalf("failed to create employee for paid owner: %v", err)
	}

	// Mock user-service server responding to /users/subscription/internal
	mockUserService := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/users/subscription/internal" {
			http.NotFound(w, r)
			return
		}
		tenantID := r.URL.Query().Get("tenant_id")
		if tenantID == freeOwnerID {
			w.WriteHeader(http.StatusPaymentRequired)
			json.NewEncoder(w).Encode(map[string]any{
				"error":   "upgrade_required",
				"tier":    "free",
				"message": "paid subscription required",
			})
			return
		}
		if tenantID == paidOwnerID {
			w.WriteHeader(http.StatusOK)
			json.NewEncoder(w).Encode(map[string]any{
				"tier":    "paid",
				"is_paid": true,
			})
			return
		}
		w.WriteHeader(http.StatusNotFound)
	}))
	defer mockUserService.Close()

	// Configure auth handler with mock user-service client
	a.userServiceURL = mockUserService.URL
	a.userServiceClient = resilience.NewClient(mockUserService.Client(), "user-service", 2, 5*time.Second)
	a.internalServiceToken = "test-internal-token-123"

	// 1. Free Owner attempts to toggle employee -> MUST fail with 402 Payment Required
	t.Run("Free Owner ToggleEmployee Rejected with 402", func(t *testing.T) {
		toggleReq := models.ToggleEmployeeRequest{
			EmployeeEmail: "emp-free@example.com",
			OwnerEmail:    "freeowner@example.com",
			OwnerPassword: "Password123!",
			SetActive:     false,
		}
		b, _ := json.Marshal(toggleReq)
		req := httptest.NewRequest(http.MethodPost, "/auth/employee/toggle", bytes.NewReader(b))
		rec := httptest.NewRecorder()

		a.ToggleEmployee(rec, req)

		if rec.Code != http.StatusPaymentRequired {
			t.Fatalf("Expected 402 Payment Required for free owner ToggleEmployee, got %d. Body: %s", rec.Code, rec.Body.String())
		}
		if !strings.Contains(rec.Body.String(), "upgrade_required") {
			t.Errorf("Expected body to contain 'upgrade_required', got: %s", rec.Body.String())
		}
		if !strings.Contains(rec.Body.String(), "Staff management requires a paid subscription.") {
			t.Errorf("Expected body to contain staff management message, got: %s", rec.Body.String())
		}
	})

	// 2. Paid Owner attempts to toggle employee -> MUST succeed with 200 OK
	t.Run("Paid Owner ToggleEmployee Succeeds with 200", func(t *testing.T) {
		toggleReq := models.ToggleEmployeeRequest{
			EmployeeEmail: "emp-paid@example.com",
			OwnerEmail:    "paidowner@example.com",
			OwnerPassword: "Password123!",
			SetActive:     false,
		}
		b, _ := json.Marshal(toggleReq)
		req := httptest.NewRequest(http.MethodPost, "/auth/employee/toggle", bytes.NewReader(b))
		rec := httptest.NewRecorder()

		a.ToggleEmployee(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK for paid owner ToggleEmployee, got %d. Body: %s", rec.Code, rec.Body.String())
		}
	})
}
