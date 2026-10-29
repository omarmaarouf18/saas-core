package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/project/user-service/internal/models"
)

func TestAdminReconciliation_EnrichedFields(t *testing.T) {
	svc, mongoStore, validToken, mockServer := setupAdminReconciliationTestEnvironment(t)
	defer mockServer.Close()
	defer func() {
		_ = mongoStore.DropDatabase(context.Background())
		_ = mongoStore.Close(context.Background())
	}()

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// Seed a service
	testSvc := models.Service{
		ID:       "service-express-1",
		TenantID: "tenant-owner-1",
		Name:     "Express Delivery",
		Category: "courier_express",
	}
	if err := mongoStore.CreateService(ctx, &testSvc); err != nil {
		t.Fatalf("failed to create service: %v", err)
	}

	// Seed a disputed job with v2 addresses, courier employee, and category
	job1 := models.Job{
		ID:                  "job-dispute-enriched-1",
		OwnerID:             "tenant-owner-1",
		EmployeeID:          "courier-emp-77",
		UserID:              "customer-user-88",
		ServiceID:           "service-express-1",
		Status:              models.JobStatusEscrowReconciliationRequired,
		PaymentMethod:       "cod",
		LockedEscrowAmount:  50.0,
		EscrowFailureReason: "disputed delivery pin",
		Location: models.Location{
			Latitude:  30.0444,
			Longitude: 31.2357,
			Address:   "123 Nile Corniche, Cairo",
		},
		Destination: models.Location{
			Latitude:  30.0500,
			Longitude: 31.2400,
			Address:   "456 Tahrir Square, Cairo",
		},
		CreatedAt: time.Now().UTC().Add(-2 * time.Hour),
		UpdatedAt: time.Now().UTC().Add(-1 * time.Hour),
	}
	if err := mongoStore.CreateJob(ctx, &job1); err != nil {
		t.Fatalf("failed to seed job1: %v", err)
	}

	// Seed a second job without employee and without address text (fallback testing)
	job2 := models.Job{
		ID:                  "job-dispute-fallback-2",
		OwnerID:             "tenant-owner-1",
		EmployeeID:          "",
		UserID:              "customer-user-99",
		ServiceID:           "service-nonexistent",
		Status:              models.JobStatusEscrowReconciliationRequired,
		PaymentMethod:       "cod",
		LockedEscrowAmount:  30.0,
		EscrowFailureReason: "cancelled by ops",
		CreatedAt:           time.Now().UTC().Add(-1 * time.Hour),
		UpdatedAt:           time.Now().UTC(),
	}
	if err := mongoStore.CreateJob(ctx, &job2); err != nil {
		t.Fatalf("failed to seed job2: %v", err)
	}

	req := httptest.NewRequest(http.MethodGet, "/admin/reconciliation/queue?page=1&limit=10", nil)
	req.Header.Set("X-Internal-Token", "test-internal-token")
	req.Header.Set("X-Reviewer-Token", validToken)
	rec := httptest.NewRecorder()

	svc.AdminGetReconciliationQueue(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK, got %d: %s", rec.Code, rec.Body.String())
	}

	rawBody := rec.Body.String()
	// Check that employee_id is rendered even when empty (not omitted via omitempty)
	if !strings.Contains(rawBody, `"employee_id":""`) && !strings.Contains(rawBody, `"employee_id": ""`) {
		t.Errorf("expected employee_id to be serialized in JSON even when empty, body was: %s", rawBody)
	}

	var resp models.AdminReconciliationQueueResponse
	if err := json.NewDecoder(strings.NewReader(rawBody)).Decode(&resp); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}

	if len(resp.Disputes) != 2 {
		t.Fatalf("expected 2 disputes, got %d", len(resp.Disputes))
	}

	var foundEnriched, foundFallback bool
	for _, d := range resp.Disputes {
		if d.ID == "job-dispute-enriched-1" {
			foundEnriched = true
			if d.EmployeeID != "courier-emp-77" {
				t.Errorf("expected employee_id 'courier-emp-77', got '%s'", d.EmployeeID)
			}
			if d.Category != "courier_express" {
				t.Errorf("expected category 'courier_express', got '%s'", d.Category)
			}
			if d.PickupAddress != "123 Nile Corniche, Cairo" {
				t.Errorf("expected pickup_address '123 Nile Corniche, Cairo', got '%s'", d.PickupAddress)
			}
			if d.DropoffAddress != "456 Tahrir Square, Cairo" {
				t.Errorf("expected dropoff_address '456 Tahrir Square, Cairo', got '%s'", d.DropoffAddress)
			}
		}
		if d.ID == "job-dispute-fallback-2" {
			foundFallback = true
			if d.EmployeeID != "" {
				t.Errorf("expected empty employee_id, got '%s'", d.EmployeeID)
			}
			if d.Category != "" {
				t.Errorf("expected empty category for missing service, got '%s'", d.Category)
			}
			if d.PickupAddress != "" {
				t.Errorf("expected empty pickup_address, got '%s'", d.PickupAddress)
			}
			if d.DropoffAddress != "" {
				t.Errorf("expected empty dropoff_address, got '%s'", d.DropoffAddress)
			}
		}
	}

	if !foundEnriched || !foundFallback {
		t.Errorf("expected to find both enriched and fallback disputes: foundEnriched=%v foundFallback=%v", foundEnriched, foundFallback)
	}
}
