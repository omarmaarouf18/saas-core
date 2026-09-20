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

	"github.com/project/user-service/internal/config"
	"github.com/project/user-service/internal/models"
	"github.com/project/user-service/internal/store"
)

func setupAdminPayoutTestEnvironment(t *testing.T) (*UserService, *store.MongoDB, string, *httptest.Server) {
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}
	dbName := fmt.Sprintf("test_admin_payout_%d", time.Now().UnixNano())

	var mongoStore *store.MongoDB
	var err error
	for i := 0; i < 5; i++ {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		mongoStore, err = store.NewMongoDB(ctx, mongoURI, dbName)
		cancel()
		if err == nil {
			break
		}
		time.Sleep(200 * time.Millisecond)
	}
	if err != nil {
		t.Skipf("Skipping admin payout integration test: MongoDB not available (%v)", err)
		return nil, nil, "", nil
	}

	validReviewerToken := "valid-reviewer-payout-token"

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
				_, _ = w.Write([]byte(`{"id":"reviewer-payout-admin","name":"Payout Ops Admin"}`))
				return
			}
			w.WriteHeader(http.StatusUnauthorized)
			_, _ = w.Write([]byte(`{"error":"invalid reviewer token"}`))
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

func TestAdminPayout_Authentication(t *testing.T) {
	svc, _, validToken, _ := setupAdminPayoutTestEnvironment(t)
	if svc == nil {
		return
	}

	t.Run("Missing Reviewer Token", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/admin/payouts", nil)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		rec := httptest.NewRecorder()
		svc.AdminListPayouts(rec, req)

		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("expected 401 Unauthorized, got %d: %s", rec.Code, rec.Body.String())
		}
	})

	t.Run("Invalid Reviewer Token", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/admin/payouts", nil)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", "bad-token")
		rec := httptest.NewRecorder()
		svc.AdminListPayouts(rec, req)

		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("expected 401 Unauthorized, got %d: %s", rec.Code, rec.Body.String())
		}
	})

	t.Run("Missing Internal Token", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/admin/payouts", nil)
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		svc.AdminListPayouts(rec, req)

		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("expected 401 Unauthorized, got %d: %s", rec.Code, rec.Body.String())
		}
	})

	t.Run("Valid Credentials Succeeded", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/admin/payouts", nil)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		svc.AdminListPayouts(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 OK, got %d: %s", rec.Code, rec.Body.String())
		}
	})
}

func TestAdminPayout_RejectValidation(t *testing.T) {
	svc, _, validToken, _ := setupAdminPayoutTestEnvironment(t)
	if svc == nil {
		return
	}

	t.Run("Wrong Method GET", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/admin/payouts/reject", nil)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		svc.AdminRejectPayoutRequest(rec, req)

		if rec.Code != http.StatusMethodNotAllowed {
			t.Fatalf("expected 405 Method Not Allowed, got %d", rec.Code)
		}
	})

	t.Run("Missing PayoutID", func(t *testing.T) {
		body, _ := json.Marshal(map[string]string{
			"reason": "banking name mismatch",
		})
		req := httptest.NewRequest(http.MethodPost, "/admin/payouts/reject", bytes.NewReader(body))
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		svc.AdminRejectPayoutRequest(rec, req)

		if rec.Code != http.StatusBadRequest {
			t.Fatalf("expected 400 Bad Request, got %d: %s", rec.Code, rec.Body.String())
		}
	})

	t.Run("Missing Reason", func(t *testing.T) {
		body, _ := json.Marshal(map[string]string{
			"payout_id": "payout-001",
			"reason":    "   ",
		})
		req := httptest.NewRequest(http.MethodPost, "/admin/payouts/reject", bytes.NewReader(body))
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		svc.AdminRejectPayoutRequest(rec, req)

		if rec.Code != http.StatusBadRequest {
			t.Fatalf("expected 400 Bad Request, got %d: %s", rec.Code, rec.Body.String())
		}
	})

	t.Run("Reason Exceeds 1000 Chars", func(t *testing.T) {
		longReason := strings.Repeat("A", 1001)
		body, _ := json.Marshal(map[string]string{
			"payout_id": "payout-001",
			"reason":    longReason,
		})
		req := httptest.NewRequest(http.MethodPost, "/admin/payouts/reject", bytes.NewReader(body))
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		svc.AdminRejectPayoutRequest(rec, req)

		if rec.Code != http.StatusBadRequest {
			t.Fatalf("expected 400 Bad Request, got %d: %s", rec.Code, rec.Body.String())
		}
	})
}

func TestAdminPayout_RejectSuccessAndCASProtection(t *testing.T) {
	svc, mongoStore, validToken, _ := setupAdminPayoutTestEnvironment(t)
	if svc == nil {
		return
	}
	ctx := context.Background()
	tenantID := "tenant-payout-owner-1"

	// 1. Seed wallet with $500 balance
	if err := mongoStore.Deposit(ctx, tenantID, 500.0); err != nil {
		t.Fatalf("failed to deposit wallet: %v", err)
	}

	// 2. Create payout request for $200 (deducts $200 from wallet -> $300 balance remaining)
	pr, err := mongoStore.CreatePayoutRequest(ctx, tenantID, models.CreatePayoutRequestInput{
		TenantID:     tenantID,
		Amount:       200.0,
		PayoutMethod: "bank_transfer",
	})
	if err != nil {
		t.Fatalf("failed to create payout request: %v", err)
	}

	// Verify wallet balance is 300
	wBefore, err := mongoStore.GetOrCreateWallet(ctx, tenantID)
	if err != nil {
		t.Fatalf("failed to get wallet: %v", err)
	}
	if wBefore.WithdrawableBalance != 300.0 || wBefore.TotalBalance != 300.0 {
		t.Fatalf("expected wallet balance 300.0 after payout request, got withdrawable=%.2f total=%.2f", wBefore.WithdrawableBalance, wBefore.TotalBalance)
	}

	// 3. Admin rejects the payout request
	body, _ := json.Marshal(models.AdminRejectPayoutRequest{
		PayoutID: pr.ID,
		Reason:   "Invalid bank routing number provided",
	})
	req := httptest.NewRequest(http.MethodPost, "/admin/payouts/reject", bytes.NewReader(body))
	req.Header.Set("X-Internal-Token", "test-internal-token")
	req.Header.Set("X-Reviewer-Token", validToken)
	rec := httptest.NewRecorder()
	svc.AdminRejectPayoutRequest(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK for valid rejection, got %d: %s", rec.Code, rec.Body.String())
	}

	// 4. Verify wallet balance is restored to 500
	wAfter, err := mongoStore.GetOrCreateWallet(ctx, tenantID)
	if err != nil {
		t.Fatalf("failed to get wallet after rejection: %v", err)
	}
	if wAfter.WithdrawableBalance != 500.0 || wAfter.TotalBalance != 500.0 {
		t.Fatalf("expected wallet balance restored to 500.0, got withdrawable=%.2f total=%.2f", wAfter.WithdrawableBalance, wAfter.TotalBalance)
	}

	// 5. Verify payout request status and reason in DB
	payouts, err := mongoStore.GetPayoutRequests(ctx, tenantID)
	if err != nil {
		t.Fatalf("failed to get payout requests: %v", err)
	}
	if len(payouts) != 1 {
		t.Fatalf("expected 1 payout request, got %d", len(payouts))
	}
	if payouts[0].Status != models.PayoutStatusRejected {
		t.Fatalf("expected status 'rejected', got %s", payouts[0].Status)
	}
	if payouts[0].RejectionReason != "Invalid bank routing number provided" {
		t.Fatalf("expected rejection reason 'Invalid bank routing number provided', got %s", payouts[0].RejectionReason)
	}

	// 6. Verify ledger transaction recorded
	ledgerEntries := mongoStore.GetLedger(ctx, tenantID, 100, 0)
	var foundRefund bool
	for _, entry := range ledgerEntries {
		if entry.Type == models.TxPayoutRefund && entry.Amount == 200.0 {
			foundRefund = true
			break
		}
	}
	if !foundRefund {
		t.Fatalf("expected TxPayoutRefund of 200.0 in ledger, but not found")
	}

	// 7. CAS Protection: Second rejection attempt MUST fail with 409 Conflict
	rec2 := httptest.NewRecorder()
	req2 := httptest.NewRequest(http.MethodPost, "/admin/payouts/reject", bytes.NewReader(body))
	req2.Header.Set("X-Internal-Token", "test-internal-token")
	req2.Header.Set("X-Reviewer-Token", validToken)
	svc.AdminRejectPayoutRequest(rec2, req2)

	if rec2.Code != http.StatusConflict {
		t.Fatalf("expected 409 Conflict on duplicate rejection, got %d: %s", rec2.Code, rec2.Body.String())
	}

	// Confirm balance is NOT double-credited (must remain exactly 500.0)
	wFinal, _ := mongoStore.GetOrCreateWallet(ctx, tenantID)
	if wFinal.WithdrawableBalance != 500.0 || wFinal.TotalBalance != 500.0 {
		t.Fatalf("CAS failed: duplicate rejection altered wallet balance! withdrawable=%.2f total=%.2f", wFinal.WithdrawableBalance, wFinal.TotalBalance)
	}
}

func TestAdminPayout_List(t *testing.T) {
	svc, mongoStore, validToken, _ := setupAdminPayoutTestEnvironment(t)
	if svc == nil {
		return
	}
	ctx := context.Background()

	// Seed multiple payouts
	t1 := "tenant-list-1"
	t2 := "tenant-list-2"
	_ = mongoStore.Deposit(ctx, t1, 1000.0)
	_ = mongoStore.Deposit(ctx, t2, 1000.0)

	p1, _ := mongoStore.CreatePayoutRequest(ctx, t1, models.CreatePayoutRequestInput{TenantID: t1, Amount: 100, PayoutMethod: "instapay"})
	_, _ = mongoStore.CreatePayoutRequest(ctx, t2, models.CreatePayoutRequestInput{TenantID: t2, Amount: 200, PayoutMethod: "bank_transfer"})

	// Reject p1
	_ = mongoStore.RejectPayoutRequest(ctx, p1.ID, "rejected for test")

	t.Run("List All Payouts", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/admin/payouts", nil)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		svc.AdminListPayouts(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 OK, got %d: %s", rec.Code, rec.Body.String())
		}
		var resp models.AdminPayoutListResponse
		_ = json.NewDecoder(rec.Body).Decode(&resp)
		if resp.Total != 2 {
			t.Fatalf("expected 2 total payouts, got %d", resp.Total)
		}
		if len(resp.Payouts) != 2 {
			t.Fatalf("expected 2 payouts returned, got %d", len(resp.Payouts))
		}
	})

	t.Run("Filter By Status Requested", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/admin/payouts?status=requested", nil)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		svc.AdminListPayouts(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 OK, got %d: %s", rec.Code, rec.Body.String())
		}
		var resp models.AdminPayoutListResponse
		_ = json.NewDecoder(rec.Body).Decode(&resp)
		if resp.Total != 1 {
			t.Fatalf("expected 1 requested payout, got %d", resp.Total)
		}
		if resp.Payouts[0].Status != models.PayoutStatusRequested {
			t.Fatalf("expected status 'requested', got %s", resp.Payouts[0].Status)
		}
	})

	t.Run("Filter By Status Rejected", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/admin/payouts?status=rejected", nil)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		svc.AdminListPayouts(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 OK, got %d: %s", rec.Code, rec.Body.String())
		}
		var resp models.AdminPayoutListResponse
		_ = json.NewDecoder(rec.Body).Decode(&resp)
		if resp.Total != 1 {
			t.Fatalf("expected 1 rejected payout, got %d", resp.Total)
		}
		if resp.Payouts[0].Status != models.PayoutStatusRejected {
			t.Fatalf("expected status 'rejected', got %s", resp.Payouts[0].Status)
		}
		if resp.Payouts[0].RejectionReason != "rejected for test" {
			t.Fatalf("expected rejection reason 'rejected for test', got %s", resp.Payouts[0].RejectionReason)
		}
	})
}
