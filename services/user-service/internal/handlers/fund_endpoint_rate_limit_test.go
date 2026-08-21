package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/project/shared/infra/jwtutil"
	"github.com/project/user-service/internal/models"
)

// Fund-moving endpoints previously had NO rate limiting (CompleteJob,
// ResolveReconciliation, RequestPayout, GetPayoutRequests): an authenticated
// caller could hammer them without bound. Each test floods 31 times and
// asserts the 31st call is rejected with 429 while the first 30 are not.

func TestCompleteJob_RateLimiting(t *testing.T) {
	u, s, _, cleanup := idemRaceSetup(t)
	defer cleanup()

	ctx := context.Background()
	ownerID := "rlc-owner"
	empID := "rlc-emp"
	svcID := "rlc-svc"
	s.CreateService(ctx, &models.Service{ID: svcID, TenantID: ownerID, TenantBasePrice: 5.0, TenantPricePerKM: 0.0, Latitude: 30.0, Longitude: 30.0})
	_ = s.Deposit(ctx, ownerID, 500.0)
	job := &models.Job{ID: "rlc-job", OwnerID: ownerID, UserID: "rlc-cust", EmployeeID: empID,
		ServiceID: svcID, Status: models.JobStatusActive, PaymentMethod: "wallet",
		LockedEscrowAmount: 5.0, Location: models.Location{Latitude: 30.0, Longitude: 30.0},
		CreatedAt: time.Now().Add(-time.Hour)}
	_ = s.CreateJob(ctx, job)
	if err := s.LockEscrow(ctx, ownerID, job.ID, 5.0); err != nil {
		t.Fatalf("setup lock failed: %v", err)
	}

	tokenEmp, _ := jwtutil.GenerateToken(empID, "employee", ownerID, "rlc-emp@example.com")
	body, _ := json.Marshal(map[string]any{"job_id": job.ID, "requester_id": tokenEmp})

	codes := make([]int, 0, 31)
	for i := 0; i < 31; i++ {
		req := httptest.NewRequest("POST", "/users/jobs/complete", bytes.NewReader(body))
		rec := httptest.NewRecorder()
		u.CompleteJob(rec, req)
		codes = append(codes, rec.Code)
	}
	for i, c := range codes[:30] {
		if c == http.StatusTooManyRequests {
			t.Fatalf("call %d unexpectedly rate limited within budget", i+1)
		}
	}
	if codes[30] != http.StatusTooManyRequests {
		t.Errorf("expected 31st CompleteJob call to be rate limited (429), got %d (codes=%v)", codes[30], codes)
	}
}

func TestResolveReconciliation_RateLimiting(t *testing.T) {
	u, s, _, cleanup := idemRaceSetup(t)
	defer cleanup()

	ctx := context.Background()
	ownerID := "rlr-owner"
	svcID := "rlr-svc"
	s.CreateService(ctx, &models.Service{ID: svcID, TenantID: ownerID, TenantBasePrice: 5.0, TenantPricePerKM: 0.0, Latitude: 30.0, Longitude: 30.0})
	_ = s.Deposit(ctx, ownerID, 500.0)
	job := &models.Job{ID: "rlr-job", OwnerID: ownerID, UserID: "rlr-cust", ServiceID: svcID,
		Status: models.JobStatusEscrowReconciliationRequired, PaymentMethod: "wallet",
		LockedEscrowAmount: 10.0, Location: models.Location{Latitude: 30.0, Longitude: 30.0},
		CreatedAt: time.Now().Add(-time.Hour)}
	_ = s.CreateJob(ctx, job)
	if err := s.LockEscrow(ctx, ownerID, job.ID, 10.0); err != nil {
		t.Fatalf("setup lock failed: %v", err)
	}

	tokenOwner, _ := jwtutil.GenerateToken(ownerID, "owner", ownerID, "rlr-owner@example.com")
	body, _ := json.Marshal(map[string]any{"job_id": job.ID, "decision": "refund_to_customer", "requester_token": tokenOwner})

	codes := make([]int, 0, 31)
	for i := 0; i < 31; i++ {
		req := httptest.NewRequest("POST", "/users/jobs/reconciliation-resolve", bytes.NewReader(body))
		req.Header.Set("Authorization", "Bearer "+tokenOwner)
		rec := httptest.NewRecorder()
		u.ResolveReconciliation(rec, req)
		codes = append(codes, rec.Code)
	}
	for i, c := range codes[:30] {
		if c == http.StatusTooManyRequests {
			t.Fatalf("call %d unexpectedly rate limited within budget", i+1)
		}
	}
	if codes[30] != http.StatusTooManyRequests {
		t.Errorf("expected 31st ResolveReconciliation call to be rate limited (429), got %d (codes=%v)", codes[30], codes)
	}
}

func TestRequestPayout_RateLimiting(t *testing.T) {
	u, s, _, cleanup := idemRaceSetup(t)
	defer cleanup()

	ctx := context.Background()
	ownerID := "rlp-owner"
	_ = s.Deposit(ctx, ownerID, 100.0)

	tokenOwner, _ := jwtutil.GenerateToken(ownerID, "owner", ownerID, "rlp-owner@example.com")

	codes := make([]int, 0, 31)
	for i := 0; i < 31; i++ {
		body, _ := json.Marshal(map[string]any{
			"amount": 0.01, "payout_method": "bank_transfer",
			"account_details": fmt.Sprintf("acct-%d", i),
			"tenant_token":    tokenOwner,
		})
		req := httptest.NewRequest("POST", "/users/wallet/payout/request", bytes.NewReader(body))
		req.Header.Set("Authorization", "Bearer "+tokenOwner)
		rec := httptest.NewRecorder()
		u.RequestPayout(rec, req)
		codes = append(codes, rec.Code)
	}
	for i, c := range codes[:30] {
		if c == http.StatusTooManyRequests {
			t.Fatalf("call %d unexpectedly rate limited within budget", i+1)
		}
	}
	if codes[30] != http.StatusTooManyRequests {
		t.Errorf("expected 31st RequestPayout call to be rate limited (429), got %d (codes=%v)", codes[30], codes)
	}
}

func TestGetPayoutRequests_RateLimiting(t *testing.T) {
	u, s, _, cleanup := idemRaceSetup(t)
	defer cleanup()

	_ = s.Deposit(context.Background(), "rlg-owner", 10.0)
	tokenOwner, _ := jwtutil.GenerateToken("rlg-owner", "owner", "rlg-owner", "rlg@example.com")

	codes := make([]int, 0, 31)
	for i := 0; i < 31; i++ {
		req := httptest.NewRequest("GET", "/users/wallet/payout/requests", nil)
		req.Header.Set("Authorization", "Bearer "+tokenOwner)
		rec := httptest.NewRecorder()
		u.GetPayoutRequests(rec, req)
		codes = append(codes, rec.Code)
	}
	for i, c := range codes[:30] {
		if c == http.StatusTooManyRequests {
			t.Fatalf("call %d unexpectedly rate limited within budget", i+1)
		}
	}
	if codes[30] != http.StatusTooManyRequests {
		t.Errorf("expected 31st GetPayoutRequests call to be rate limited (429), got %d (codes=%v)", codes[30], codes)
	}
}
