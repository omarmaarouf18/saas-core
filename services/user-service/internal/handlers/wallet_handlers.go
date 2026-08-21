package handlers

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"strings"

	"github.com/project/shared/infra/handlerutil"
	"github.com/project/user-service/internal/models"
)

// ---------------------------------------------------------------------------
// GET /users/wallet?tenant_id=xxx
// ---------------------------------------------------------------------------

func (u *UserService) GetWallet(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use GET"})
		return
	}
	tenantID := r.URL.Query().Get("tenant_token")
	if tenantID == "" {
		tenantID = r.URL.Query().Get("tenant_id")
	}
	if tenantID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "tenant_id required"})
		return
	}
	resolvedTenantID, err := resolveTokenWithRole(tenantID, "owner")
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid tenant token: " + err.Error()})
		return
	}
	tenantID = resolvedTenantID
	wallet, err := u.store.GetOrCreateWallet(r.Context(), tenantID)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, wallet)
}

// ---------------------------------------------------------------------------
// POST /users/wallet/deposit
// ---------------------------------------------------------------------------

func (u *UserService) WalletDeposit(w http.ResponseWriter, r *http.Request) {
	ip := handlerutil.GetIP(r)
	if limited, remaining := u.limiter.CheckAndRecord(ip); limited {
		writeJSON(w, http.StatusTooManyRequests, map[string]string{
			"error": fmt.Sprintf("too many requests, locked out for %.0f seconds", remaining.Seconds()),
		})
		return
	}

	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use POST"})
		return
	}

	if !u.allowTestPaymentBypass || (u.appEnv != "local" && u.appEnv != "test") {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "payment gateway not yet integrated",
		})
		return
	}

	// Buffer the body so we can decode it for tenant-scoped rate limiting
	// and still have it available for the rest of the handler.
	bodyBytes, err := io.ReadAll(r.Body)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "failed to read request body"})
		return
	}
	r.Body = io.NopCloser(bytes.NewReader(bodyBytes))

	var req models.DepositRequest
	if err := json.NewDecoder(bytes.NewReader(bodyBytes)).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON: " + err.Error()})
		return
	}
	if req.TenantToken != "" {
		req.TenantID = req.TenantToken
	}
	const maxDepositAmount = 1_000_000
	if req.TenantID == "" || req.Amount <= 0 || req.Amount > maxDepositAmount {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": fmt.Sprintf("tenant_id and positive amount up to %d required", maxDepositAmount),
		})
		return
	}

	resolvedTenantID, err := resolveTokenWithRole(req.TenantID, "owner")
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid tenant token: " + err.Error()})
		return
	}
	req.TenantID = resolvedTenantID

	// Secondary rate-limit key: tenant_id. Even if IP-based limiting is
	// somehow defeated, this catches repeated abuse against the same wallet.
	// Mirrors how auth-service locks on both client IP and email independently.
	tenantKey := "tenant:" + req.TenantID
	if limited, remaining := u.limiter.CheckAndRecord(tenantKey); limited {
		writeJSON(w, http.StatusTooManyRequests, map[string]string{
			"error": fmt.Sprintf("too many deposit requests for this tenant, locked out for %.0f seconds", remaining.Seconds()),
		})
		return
	}

	// Verify owner exists and has approved KYC
	kycStatus, err := u.checkKYC(req.TenantID)
	if err != nil {
		log.Printf("[KYC BLOCKED/ERROR] Failed KYC check for owner %s: %v", req.TenantID, err)
		if errors.Is(err, ErrServiceUnavailable) {
			writeJSON(w, http.StatusServiceUnavailable, map[string]string{
				"error":   "service_unavailable",
				"message": "Authentication service is temporarily unavailable. Please try again later.",
			})
			return
		}
		handlerutil.ShipSecurityEvent(r.Context(), "KYC_BLOCKED_ERROR", "user-service", req.TenantID, req.TenantID, fmt.Sprintf("failed KYC check: %v", err), handlerutil.GetClientIP(r))
		writeJSON(w, http.StatusForbidden, map[string]string{
			"error": "action blocked: unable to verify owner KYC status",
		})
		return
	}
	if kycStatus != "approved" {
		log.Printf("[KYC BLOCKED] Owner %s attempted to deposit to wallet, but KYC status is %q", req.TenantID, kycStatus)
		handlerutil.ShipSecurityEvent(r.Context(), "KYC_BLOCKED", "user-service", req.TenantID, req.TenantID, fmt.Sprintf("attempted to deposit, KYC status is %s", kycStatus), handlerutil.GetClientIP(r))
		writeJSON(w, http.StatusForbidden, map[string]string{
			"error": "action blocked: owner KYC approval is pending",
		})
		return
	}
	if err := u.store.Deposit(r.Context(), req.TenantID, req.Amount); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	wallet := u.store.GetWallet(r.Context(), req.TenantID)
	writeJSON(w, http.StatusOK, map[string]any{"message": "deposit successful", "wallet": wallet})
}

// ---------------------------------------------------------------------------
// GET /users/ledger?tenant_id=xxx
// ---------------------------------------------------------------------------

func (u *UserService) GetLedger(w http.ResponseWriter, r *http.Request) {
	ip := handlerutil.GetIP(r)
	if limited, remaining := u.ledgerIPLimiter.CheckAndRecord("get_ledger_ip:" + ip); limited {
		writeJSON(w, http.StatusTooManyRequests, map[string]string{
			"error": fmt.Sprintf("too many requests, locked out for %.0f seconds", remaining.Seconds()),
		})
		return
	}

	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use GET"})
		return
	}
	tenantID := r.URL.Query().Get("tenant_token")
	if tenantID == "" {
		tenantID = r.URL.Query().Get("tenant_id")
	}
	if tenantID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "tenant_id required"})
		return
	}
	resolvedTenantID, err := resolveTokenWithRole(tenantID, "owner")
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid tenant token: " + err.Error()})
		return
	}
	tenantID = resolvedTenantID

	tenantKey := "ledger_tenant:" + tenantID
	if limited, remaining := u.ledgerLimiter.CheckAndRecord(tenantKey); limited {
		writeJSON(w, http.StatusTooManyRequests, map[string]string{
			"error": fmt.Sprintf("too many ledger requests for this tenant, locked out for %.0f seconds", remaining.Seconds()),
		})
		return
	}

	entries := u.store.GetLedger(r.Context(), tenantID)
	writeJSON(w, http.StatusOK, map[string]any{"count": len(entries), "entries": entries})
}

// RequestPayout processes a tenant owner's withdrawal request (POST /users/wallet/payout/request).
func (u *UserService) RequestPayout(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}

	ctx := r.Context()
	var req models.CreatePayoutRequestInput
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body: " + err.Error()})
		return
	}

	tokenStr := r.Header.Get("Authorization")
	if strings.HasPrefix(tokenStr, "Bearer ") || strings.HasPrefix(tokenStr, "bearer ") {
		tokenStr = strings.TrimSpace(tokenStr[7:])
	}
	if tokenStr == "" {
		tokenStr = req.TenantToken
	}
	if tokenStr == "" {
		tokenStr = req.TenantID
	}
	if tokenStr == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "tenant_id or authorization token is required"})
		return
	}

	resolvedTenantID, err := resolveTokenWithRole(tokenStr, "owner")
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid tenant owner token: " + err.Error()})
		return
	}
	if limited, remaining := u.payoutLimiter.CheckAndRecord(resolvedTenantID); limited {
		writeJSON(w, http.StatusTooManyRequests, map[string]string{"error": fmt.Sprintf("too many requests; retry in %.0f seconds", remaining.Seconds())})
		return
	}

	if req.Amount <= 0 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid payout amount: must be greater than 0"})
		return
	}

	if strings.TrimSpace(req.PayoutMethod) == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "payout_method is required (e.g. bank_transfer, instapay)"})
		return
	}

	payoutReq, err := u.store.CreatePayoutRequest(ctx, resolvedTenantID, req)
	if err != nil {
		if strings.Contains(err.Error(), "insufficient withdrawable balance") {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to create payout request: " + err.Error()})
		return
	}

	// #nosec G706 //nolint:gosec -- IDs are from verified JWT tokens and database, log injection not possible
	log.Printf("[USER] Payout request created: id=%s tenant=%s amount=%.2f method=%s", payoutReq.ID, resolvedTenantID, payoutReq.Amount, payoutReq.PayoutMethod)
	writeJSON(w, http.StatusCreated, payoutReq)
}

// GetPayoutRequests retrieves historical payout requests for a tenant owner (GET /users/wallet/payout/requests).
func (u *UserService) GetPayoutRequests(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}

	ctx := r.Context()
	tokenStr := r.Header.Get("Authorization")
	if strings.HasPrefix(tokenStr, "Bearer ") || strings.HasPrefix(tokenStr, "bearer ") {
		tokenStr = strings.TrimSpace(tokenStr[7:])
	}
	if tokenStr == "" {
		tokenStr = r.URL.Query().Get("tenant_id")
	}
	if tokenStr == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "tenant_id parameter or authorization token is required"})
		return
	}

	resolvedTenantID, err := resolveTokenWithRole(tokenStr, "owner")
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid tenant owner token: " + err.Error()})
		return
	}
	if limited, remaining := u.payoutLimiter.CheckAndRecord(resolvedTenantID); limited {
		writeJSON(w, http.StatusTooManyRequests, map[string]string{"error": fmt.Sprintf("too many requests; retry in %.0f seconds", remaining.Seconds())})
		return
	}

	requests, err := u.store.GetPayoutRequests(ctx, resolvedTenantID)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to fetch payout requests: " + err.Error()})
		return
	}

	if requests == nil {
		requests = []*models.PayoutRequest{}
	}

	writeJSON(w, http.StatusOK, requests)
}
