package handlers

import (
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/project/user-service/internal/models"
)

// ---------------------------------------------------------------------------
// GET/POST /users/subscription
// ---------------------------------------------------------------------------

func (u *UserService) Subscription(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
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
		sub := u.store.GetSubscription(r.Context(), tenantID)
		if sub == nil {
			sub = &models.Subscription{
				ID:        "sub-default-" + tenantID,
				TenantID:  tenantID,
				Tier:      models.PlanFree,
				StartedAt: time.Now().UTC(),
			}
		}
		writeJSON(w, http.StatusOK, sub)
	case http.MethodPost:
		var req struct {
			TenantID       string          `json:"tenant_id"`
			TenantToken    string          `json:"tenant_token"`
			Tier           models.PlanTier `json:"tier"`
			RequesterID    string          `json:"requester_id"`
			RequesterToken string          `json:"requester_token"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON: " + err.Error()})
			return
		}
		if req.TenantToken != "" {
			req.TenantID = req.TenantToken
		}
		if req.RequesterToken != "" {
			req.RequesterID = req.RequesterToken
		}
		if req.TenantID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "tenant_id is required"})
			return
		}
		if req.RequesterID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "requester_id is required"})
			return
		}

		resolvedTenantID, err := resolveTokenWithRole(req.TenantID, "owner")
		if err != nil {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid tenant token: " + err.Error()})
			return
		}
		req.TenantID = resolvedTenantID

		resolvedRequesterID, err := resolveTokenWithRole(req.RequesterID, "owner")
		if err != nil {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid requester token: " + err.Error()})
			return
		}
		req.RequesterID = resolvedRequesterID

		if req.RequesterID != req.TenantID {
			writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden: requester_id must match tenant_id"})
			return
		}

		// Verify requester_id resolves to a real user via auth-service (internal call)
		authURL := fmt.Sprintf("%s/auth/user?id=%s", u.authServiceURL, req.RequesterID)
		authReq, err := http.NewRequest("GET", authURL, nil)
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "auth service request error: " + err.Error()})
			return
		}
		authReq.Header.Set("X-Internal-Token", u.internalServiceToken)
		resp, err := u.authClient.Do(authReq)
		if err != nil {
			writeJSON(w, http.StatusServiceUnavailable, map[string]string{
				"error":   "service_unavailable",
				"message": "Authentication service is temporarily unavailable. Please try again later.",
			})
			return
		}
		defer resp.Body.Close()

		if resp.StatusCode == http.StatusNotFound {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "user not found"})
			return
		}
		if resp.StatusCode != http.StatusOK {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": fmt.Sprintf("unexpected auth service status: %d", resp.StatusCode)})
			return
		}

		// Validate tier
		if req.Tier != models.PlanFree && req.Tier != models.PlanPaid {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "tier must be 'free' or 'paid'"})
			return
		}

		if req.Tier == models.PlanPaid {
			sub := &models.Subscription{
				ID:        "sub-" + generateID(),
				TenantID:  req.TenantID,
				Tier:      models.PlanPendingPayment,
				StartedAt: time.Now().UTC(),
			}
			if err := u.store.UpsertSubscription(r.Context(), sub); err != nil {
				writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
				return
			}
			writeJSON(w, http.StatusAccepted, map[string]string{
				"status":  "pending_payment",
				"message": "Paid tier requires manual activation. Contact support to complete payment.",
			})
			return
		}

		sub := &models.Subscription{
			ID:        "sub-" + generateID(),
			TenantID:  req.TenantID,
			Tier:      models.PlanFree,
			StartedAt: time.Now().UTC(),
		}
		if err := u.store.UpsertSubscription(r.Context(), sub); err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, sub)
	default:
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
	}
}
