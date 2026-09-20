package handlers

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"

	"github.com/project/shared/infra/handlerutil"
	"github.com/project/user-service/internal/models"
)

// AdminListPayouts lists payout requests across all tenants with optional status filter and pagination.
// GET /users/admin/payouts & GET /admin/payouts
func (u *UserService) AdminListPayouts(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}

	reviewer, err := u.authenticateReviewer(r)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": err.Error()})
		return
	}

	status := strings.TrimSpace(r.URL.Query().Get("status"))

	page := int64(1)
	if pStr := r.URL.Query().Get("page"); pStr != "" {
		if p, err := strconv.ParseInt(pStr, 10, 64); err == nil && p > 0 {
			page = p
		}
	}

	limit := int64(20)
	if lStr := r.URL.Query().Get("limit"); lStr != "" {
		if l, err := strconv.ParseInt(lStr, 10, 64); err == nil && l > 0 && l <= 100 {
			limit = l
		}
	}

	ctx := r.Context()
	payouts, total, err := u.store.AdminListPayoutRequests(ctx, status, page, limit)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	handlerutil.ShipSecurityEvent(ctx, "ADMIN_PAYOUTS_LISTED", "user-service", reviewer.ID, "", fmt.Sprintf("listed %d payouts status=%q page=%d limit=%d total=%d", len(payouts), status, page, limit, total), handlerutil.GetClientIP(r))

	writeJSON(w, http.StatusOK, models.AdminPayoutListResponse{
		Payouts: payouts,
		Total:   int(total),
		Page:    int(page),
		Limit:   int(limit),
	})
}

// AdminRejectPayoutRequest rejects a requested payout with mandatory reason, restores wallet balance, and writes refund ledger entry.
// POST /users/admin/payouts/reject & POST /admin/payouts/reject
func (u *UserService) AdminRejectPayoutRequest(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}

	reviewer, err := u.authenticateReviewer(r)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": err.Error()})
		return
	}

	var req models.AdminRejectPayoutRequest
	if err := json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON: " + err.Error()})
		return
	}

	payoutID := strings.TrimSpace(req.PayoutID)
	if payoutID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "payout_id is required"})
		return
	}

	reason := strings.TrimSpace(req.Reason)
	if len(reason) < 1 || len(reason) > 1000 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "reason is required (1-1000 characters)"})
		return
	}

	ctx := r.Context()
	err = u.store.RejectPayoutRequest(ctx, payoutID, reason)
	if err != nil {
		if strings.Contains(err.Error(), "not found") || strings.Contains(err.Error(), "not in requested state") {
			writeJSON(w, http.StatusConflict, map[string]string{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to reject payout: " + err.Error()})
		return
	}

	handlerutil.ShipSecurityEvent(ctx, "ADMIN_PAYOUT_REJECTED", "user-service", reviewer.ID, "", fmt.Sprintf("rejected payout %s: %s", payoutID, reason), handlerutil.GetClientIP(r))

	writeJSON(w, http.StatusOK, map[string]any{
		"message":   "payout request rejected",
		"payout_id": payoutID,
	})
}
