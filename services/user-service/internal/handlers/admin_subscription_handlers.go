package handlers

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"strings"

	"github.com/project/shared/infra/handlerutil"
	"github.com/project/user-service/internal/models"
)

// AdminListSubscriptions lists subscriptions globally with optional status/search filters and pagination (ADR-0023).
// GET /users/admin/subscriptions & GET /admin/subscriptions & GET /admin/subscriptions/queue
func (u *UserService) AdminListSubscriptions(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}

	reviewer, err := u.authenticateReviewer(r)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": err.Error()})
		return
	}

	ctx := r.Context()
	status := strings.TrimSpace(r.URL.Query().Get("status"))
	search := strings.TrimSpace(r.URL.Query().Get("search"))

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

	subs, total, err := u.store.ListSubscriptions(ctx, status, search, page, limit)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to list subscriptions: " + err.Error()})
		return
	}

	handlerutil.ShipSecurityEvent(ctx, "ADMIN_SUBSCRIPTIONS_LISTED", "user-service", reviewer.ID, "", fmt.Sprintf("listed %d subscriptions (total=%d, status=%s, page=%d)", len(subs), total, status, page), handlerutil.GetClientIP(r))

	writeJSON(w, http.StatusOK, models.AdminSubscriptionListResponse{
		Subscriptions: subs,
		Total:         int(total),
		Page:          int(page),
		Limit:         int(limit),
	})
}

// AdminActivateSubscription activates a tenant's subscription to PlanPaid with durationDays (ADR-0023).
// POST /users/admin/subscriptions/activate & POST /admin/subscriptions/activate
func (u *UserService) AdminActivateSubscription(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}

	reviewer, err := u.authenticateReviewer(r)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": err.Error()})
		return
	}

	var req models.AdminActivateSubscriptionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON: " + err.Error()})
		return
	}

	tenantID := strings.TrimSpace(req.TenantID)
	subID := strings.TrimSpace(req.SubscriptionID)
	if tenantID == "" && subID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "tenant_id or subscription_id is required"})
		return
	}

	ctx := r.Context()
	sub, err := u.store.AdminActivateSubscription(ctx, tenantID, subID, req.DurationDays, reviewer.ID)
	if err != nil {
		if strings.Contains(err.Error(), "already active") || strings.Contains(err.Error(), "concurrently modified") {
			writeJSON(w, http.StatusConflict, map[string]string{"error": err.Error()})
			return
		}
		if strings.Contains(err.Error(), "not found") {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	handlerutil.ShipSecurityEvent(ctx, "ADMIN_SUBSCRIPTION_ACTIVATED", "user-service", reviewer.ID, sub.TenantID, fmt.Sprintf("activated paid subscription %s for tenant %s (expires=%s)", sub.ID, sub.TenantID, sub.ExpiresAt.Format("2006-01-02")), handlerutil.GetClientIP(r))

	writeJSON(w, http.StatusOK, map[string]any{
		"message":      "subscription activated successfully",
		"subscription": sub,
	})
}

// AdminRevokeSubscription revokes a tenant's active or pending subscription with mandatory reason (ADR-0023).
// POST /users/admin/subscriptions/revoke & POST /admin/subscriptions/revoke
func (u *UserService) AdminRevokeSubscription(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}

	reviewer, err := u.authenticateReviewer(r)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": err.Error()})
		return
	}

	var req models.AdminRevokeSubscriptionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON: " + err.Error()})
		return
	}

	tenantID := strings.TrimSpace(req.TenantID)
	subID := strings.TrimSpace(req.SubscriptionID)
	if tenantID == "" && subID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "tenant_id or subscription_id is required"})
		return
	}

	reason := strings.TrimSpace(req.Reason)
	if len(reason) < 1 || len(reason) > 1000 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "reason is required (1-1000 characters)"})
		return
	}

	ctx := r.Context()
	sub, err := u.store.AdminRevokeSubscription(ctx, tenantID, subID, reason, reviewer.ID)
	if err != nil {
		if strings.Contains(err.Error(), "not found") || strings.Contains(err.Error(), "not active") || strings.Contains(err.Error(), "concurrently modified") {
			writeJSON(w, http.StatusConflict, map[string]string{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	handlerutil.ShipSecurityEvent(ctx, "ADMIN_SUBSCRIPTION_REVOKED", "user-service", reviewer.ID, sub.TenantID, fmt.Sprintf("revoked subscription %s for tenant %s: reason=%s", sub.ID, sub.TenantID, reason), handlerutil.GetClientIP(r))

	writeJSON(w, http.StatusOK, map[string]any{
		"message":      "subscription revoked successfully",
		"subscription": sub,
	})
}
