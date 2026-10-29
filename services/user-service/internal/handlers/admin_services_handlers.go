package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/project/shared/infra/handlerutil"
	"github.com/project/user-service/internal/models"
	"github.com/project/user-service/internal/store"
)

// AdminServiceActionPayload represents a moderation request requiring a reason.
type AdminServiceActionPayload struct {
	ServiceID string `json:"service_id,omitempty"`
	Reason    string `json:"reason"`
}

func (u *UserService) notifyOwnerServiceModeration(svc *models.Service, notifType, title, body string, params map[string]string) {
	if svc == nil || svc.TenantID == "" {
		return
	}
	go func() {
		defer func() {
			if r := recover(); r != nil {
				log.Printf("[USER] Recovered from panic in notifyOwnerServiceModeration: %v", r)
			}
		}()

		notificationURL := u.notificationServiceURL
		if notificationURL == "" {
			notificationURL = "http://notification-service:3004"
		}
		url := fmt.Sprintf("%s/notifications/send", strings.TrimSuffix(notificationURL, "/"))

		payload := map[string]any{
			"tenant_id": svc.TenantID,
			"user_id":   svc.TenantID,
			"type":      notifType,
			"title":     title,
			"body":      body,
			"roles":     []string{"owner"},
		}
		if len(params) > 0 {
			payload["params"] = params
		}

		bodyBytes, err := json.Marshal(payload)
		if err != nil {
			return
		}

		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()

		// #nosec G704 //nolint:gosec -- notificationURL is trusted internal config
		req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(bodyBytes))
		if err != nil {
			return
		}
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("X-Internal-Token", u.internalServiceToken)

		var resp *http.Response
		if u.notificationClient != nil {
			// #nosec G704 //nolint:gosec -- notificationClient is internal client
			resp, err = u.notificationClient.Do(req)
		} else {
			// #nosec G704 //nolint:gosec -- DefaultClient is fallback
			resp, err = http.DefaultClient.Do(req)
		}
		if err == nil && resp != nil {
			_ = resp.Body.Close()
		}
	}()
}

// AdminListServices lists services for the reviewer console with filters for tenant, name, photo presence, and hidden state.
func (u *UserService) AdminListServices(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use GET"})
		return
	}

	reviewer, err := u.authenticateReviewer(r)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return
	}

	q := r.URL.Query()
	tenantID := strings.TrimSpace(q.Get("tenant_id"))
	if tenantID == "" {
		tenantID = strings.TrimSpace(q.Get("tenant"))
	}
	name := strings.TrimSpace(q.Get("name"))

	var hasPhoto *bool
	if hp := q.Get("has_photo"); hp != "" {
		val := strings.ToLower(hp) == "true" || hp == "1"
		hasPhoto = &val
	}

	var hidden *bool
	if h := q.Get("hidden"); h != "" {
		val := strings.ToLower(h) == "true" || h == "1"
		hidden = &val
	}

	page := int64(1)
	if pStr := q.Get("page"); pStr != "" {
		if p, err := strconv.ParseInt(pStr, 10, 64); err == nil && p > 0 {
			page = p
		}
	}

	limit := int64(20)
	if lStr := q.Get("limit"); lStr != "" {
		if l, err := strconv.ParseInt(lStr, 10, 64); err == nil && l > 0 && l <= 100 {
			limit = l
		}
	}

	ctx := r.Context()
	svcs, total, err := u.store.AdminListServices(ctx, tenantID, name, hasPhoto, hidden, page, limit)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to list services: " + err.Error()})
		return
	}

	handlerutil.ShipSecurityEvent(ctx, "ADMIN_SERVICES_LISTED", "user-service", reviewer.ID, tenantID, fmt.Sprintf("listed services page=%d limit=%d", page, limit), handlerutil.GetClientIP(r))

	writeJSON(w, http.StatusOK, map[string]any{
		"services": svcs,
		"total":    total,
		"page":     page,
		"limit":    limit,
	})
}

// AdminHideService hides a service from the public marketplace.
func (u *UserService) AdminHideService(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use POST"})
		return
	}

	reviewer, err := u.authenticateReviewer(r)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return
	}

	var req AdminServiceActionPayload
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}

	serviceID := strings.TrimSpace(r.PathValue("id"))
	if serviceID == "" {
		serviceID = strings.TrimSpace(req.ServiceID)
	}
	if serviceID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "service_id is required"})
		return
	}

	reason := strings.TrimSpace(req.Reason)
	reasonRunes := len([]rune(reason))
	if reasonRunes < 1 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "reason is required"})
		return
	}
	if reasonRunes > 1000 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "reason cannot exceed 1000 characters"})
		return
	}

	ctx := r.Context()
	clientIP := handlerutil.GetClientIP(r)

	updatedSvc, err := u.store.AdminSetServiceHidden(ctx, serviceID, true, reviewer.ID, reason)
	if err != nil {
		if errors.Is(err, store.ErrServiceNotFound) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "service not found"})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to hide service: " + err.Error()})
		return
	}

	handlerutil.ShipSecurityEvent(ctx, "ADMIN_SERVICE_HIDDEN", "user-service", reviewer.ID, updatedSvc.TenantID, fmt.Sprintf("service %s hidden by support: %s", serviceID, reason), clientIP)

	u.notifyOwnerServiceModeration(updatedSvc, "service_hidden", "Service Hidden", fmt.Sprintf("Your service %s was hidden by support: %s", updatedSvc.Name, reason), map[string]string{
		"service_id": updatedSvc.ID,
		"reason":     reason,
	})

	writeJSON(w, http.StatusOK, map[string]any{
		"success":       true,
		"service_id":    updatedSvc.ID,
		"is_hidden":     true,
		"hidden_reason": updatedSvc.HiddenReason,
		"hidden_notice": "hidden by support: " + updatedSvc.HiddenReason,
		"message":       "service hidden successfully",
	})
}

// AdminUnhideService restores a previously hidden service to the marketplace.
func (u *UserService) AdminUnhideService(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use POST"})
		return
	}

	reviewer, err := u.authenticateReviewer(r)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return
	}

	var req AdminServiceActionPayload
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}

	serviceID := strings.TrimSpace(r.PathValue("id"))
	if serviceID == "" {
		serviceID = strings.TrimSpace(req.ServiceID)
	}
	if serviceID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "service_id is required"})
		return
	}

	reason := strings.TrimSpace(req.Reason)
	reasonRunes := len([]rune(reason))
	if reasonRunes < 1 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "reason is required"})
		return
	}
	if reasonRunes > 1000 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "reason cannot exceed 1000 characters"})
		return
	}

	ctx := r.Context()
	clientIP := handlerutil.GetClientIP(r)

	updatedSvc, err := u.store.AdminSetServiceHidden(ctx, serviceID, false, reviewer.ID, reason)
	if err != nil {
		if errors.Is(err, store.ErrServiceNotFound) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "service not found"})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to unhide service: " + err.Error()})
		return
	}

	handlerutil.ShipSecurityEvent(ctx, "ADMIN_SERVICE_UNHIDDEN", "user-service", reviewer.ID, updatedSvc.TenantID, fmt.Sprintf("service %s unhidden by support: %s", serviceID, reason), clientIP)

	u.notifyOwnerServiceModeration(updatedSvc, "service_unhidden", "Service Restored", fmt.Sprintf("Your service %s is now visible in the marketplace.", updatedSvc.Name), map[string]string{
		"service_id": updatedSvc.ID,
		"reason":     reason,
	})

	writeJSON(w, http.StatusOK, map[string]any{
		"success":    true,
		"service_id": updatedSvc.ID,
		"is_hidden":  false,
		"message":    "service unhidden successfully",
	})
}

// AdminRemoveServicePhoto deletes a service's stored photo object via the existing delete path and clears its photo URL.
func (u *UserService) AdminRemoveServicePhoto(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use POST"})
		return
	}

	reviewer, err := u.authenticateReviewer(r)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return
	}

	var req AdminServiceActionPayload
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}

	serviceID := strings.TrimSpace(r.PathValue("id"))
	if serviceID == "" {
		serviceID = strings.TrimSpace(req.ServiceID)
	}
	if serviceID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "service_id is required"})
		return
	}

	reason := strings.TrimSpace(req.Reason)
	reasonRunes := len([]rune(reason))
	if reasonRunes < 1 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "reason is required"})
		return
	}
	if reasonRunes > 1000 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "reason cannot exceed 1000 characters"})
		return
	}

	ctx := r.Context()
	clientIP := handlerutil.GetClientIP(r)

	oldSvc, err := u.store.AdminRemoveServicePhoto(ctx, serviceID)
	if err != nil {
		if errors.Is(err, store.ErrServiceNotFound) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "service not found"})
			return
		}
		if strings.Contains(err.Error(), "no photo") {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "service has no photo to remove"})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to remove service photo: " + err.Error()})
		return
	}

	// Delete stored object via existing delete path
	u.deleteServicePhotoObject(ctx, oldSvc, oldSvc.PhotoURL)

	handlerutil.ShipSecurityEvent(ctx, "ADMIN_SERVICE_PHOTO_REMOVED", "user-service", reviewer.ID, oldSvc.TenantID, fmt.Sprintf("service %s photo removed by support: %s", serviceID, reason), clientIP)

	u.notifyOwnerServiceModeration(oldSvc, "service_photo_removed", "Service Photo Removed", fmt.Sprintf("Photo for service %s was removed by support: %s", oldSvc.Name, reason), map[string]string{
		"service_id": oldSvc.ID,
		"reason":     reason,
	})

	writeJSON(w, http.StatusOK, map[string]any{
		"success":    true,
		"service_id": oldSvc.ID,
		"message":    "service photo removed successfully",
	})
}
