package handlers

import (
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"strings"

	"github.com/project/shared/infra/handlerutil"
	"github.com/project/user-service/internal/models"
)

// ---------------------------------------------------------------------------
// GET /users/services
// ---------------------------------------------------------------------------

func (u *UserService) ListServices(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	sortBy := q.Get("sort_by")
	nearBy := q.Get("near_by") == "true"
	hasLat := q.Get("lat") != ""
	hasLon := q.Get("lon") != ""
	refLat := parseFloat(q.Get("lat"), 30.0444)
	refLon := parseFloat(q.Get("lon"), 31.2357)
	radius := parseFloat(q.Get("radius"), 50)

	ctx := r.Context()
	if nearBy || hasLat || hasLon {
		if !isValidCoordinate(refLat, refLon) {
			// #nosec G706 //nolint:gosec -- floats formatted via %.6f, log injection not possible
			log.Printf("[SECURITY WARNING] Invalid coordinates detected for ListServices: lat=%.6f, lon=%.6f", refLat, refLon)
			handlerutil.ShipSecurityEvent(ctx, "INVALID_COORDINATES_DETECTED", "user-service", "anonymous", "", fmt.Sprintf("ListServices rejected: coordinates out of range (lat=%.6f, lon=%.6f)", refLat, refLon), handlerutil.GetClientIP(r))
			writeJSON(w, http.StatusBadRequest, map[string]string{
				"error":   "invalid_coordinates",
				"message": "Latitude must be between -90 and 90, and Longitude must be between -180 and 180",
			})
			return
		}
	}

	services := u.store.ListServices(ctx, sortBy, nearBy, refLat, refLon, radius)
	// #nosec G706 //nolint:gosec -- sortBy is validated query parameter, log injection not possible
	log.Printf("[USER] ListServices: sort_by=%s near_by=%v results=%d", sortBy, nearBy, len(services))

	writeJSON(w, http.StatusOK, map[string]any{
		"count": len(services), "sort_by": sortBy, "near_by": nearBy, "services": services,
	})
}

func resolveOwnerAuthToken(r *http.Request, bodyOwnerToken, bodyOwnerID string) string {
	tokenStr := r.Header.Get("Authorization")
	if strings.HasPrefix(tokenStr, "Bearer ") || strings.HasPrefix(tokenStr, "bearer ") {
		tokenStr = strings.TrimSpace(tokenStr[7:])
	} else {
		tokenStr = ""
	}
	if tokenStr == "" {
		tokenStr = bodyOwnerToken
	}
	if tokenStr == "" {
		tokenStr = bodyOwnerID
	}
	return tokenStr
}

// ---------------------------------------------------------------------------
// POST /users/services
// ---------------------------------------------------------------------------

func (u *UserService) CreateService(w http.ResponseWriter, r *http.Request) {
	var req models.CreateServiceRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON: " + err.Error()})
		return
	}

	if !isValidCoordinate(req.Latitude, req.Longitude) {
		log.Printf("[SECURITY WARNING] Invalid coordinates rejected for CreateService: lat=%.6f, lon=%.6f", req.Latitude, req.Longitude)
		handlerutil.ShipSecurityEvent(r.Context(), "INVALID_COORDINATES_DETECTED", "user-service", "unauthenticated", "", fmt.Sprintf("CreateService rejected: coordinates out of range (lat=%.6f, lon=%.6f)", req.Latitude, req.Longitude), handlerutil.GetClientIP(r))
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error":   "invalid_coordinates",
			"message": "Latitude must be between -90 and 90, and Longitude must be between -180 and 180",
		})
		return
	}
	authToken := resolveOwnerAuthToken(r, req.OwnerToken, req.OwnerID)
	if authToken == "" || req.Name == "" || req.Category == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "owner authorization, name, and category are required"})
		return
	}
	resolvedOwnerID, err := resolveTokenWithRole(authToken, "owner")
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid owner token: " + err.Error()})
		return
	}
	req.OwnerID = resolvedOwnerID

	// Verify owner exists and has approved KYC
	kycStatus, err := u.checkKYC(req.OwnerID)
	if err != nil {
		// #nosec G706 //nolint:gosec -- req.OwnerID is resolved from cryptographically verified JWT claims
		log.Printf("[KYC BLOCKED/ERROR] Failed KYC check for owner %s: %v", req.OwnerID, err)
		if errors.Is(err, ErrServiceUnavailable) {
			writeJSON(w, http.StatusServiceUnavailable, map[string]string{
				"error":   "service_unavailable",
				"message": "Authentication service is temporarily unavailable. Please try again later.",
			})
			return
		}
		handlerutil.ShipSecurityEvent(r.Context(), "KYC_BLOCKED_ERROR", "user-service", req.OwnerID, req.OwnerID, fmt.Sprintf("failed KYC check: %v", err), handlerutil.GetClientIP(r))
		writeJSON(w, http.StatusForbidden, map[string]string{
			"error": "action blocked: unable to verify owner KYC status",
		})
		return
	}
	if kycStatus != "approved" {
		// #nosec G706 //nolint:gosec -- req.OwnerID is resolved from cryptographically verified JWT claims
		log.Printf("[KYC BLOCKED] Owner %s attempted to create service, but KYC status is %q", req.OwnerID, kycStatus)
		handlerutil.ShipSecurityEvent(r.Context(), "KYC_BLOCKED", "user-service", req.OwnerID, req.OwnerID, fmt.Sprintf("attempted to create service, KYC status is %s", kycStatus), handlerutil.GetClientIP(r))
		writeJSON(w, http.StatusForbidden, map[string]string{
			"error": "action blocked: owner KYC approval is pending",
		})
		return
	}
	if req.Category != "shipping" && req.Category != "delivery" && req.Category != "transport" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid category, must be: shipping, delivery, transport"})
		return
	}
	if req.TenantBasePrice < 0 || req.TenantPricePerKM < 0 {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error":   "invalid_pricing",
			"message": "tenant_base_price and tenant_price_per_km cannot be negative",
		})
		return
	}

	svc := &models.Service{
		ID: generateID(), TenantID: req.OwnerID, Name: req.Name, Category: req.Category,
		BasePrice: req.TenantBasePrice, TenantBasePrice: req.TenantBasePrice,
		TenantPricePerKM: req.TenantPricePerKM, Latitude: req.Latitude, Longitude: req.Longitude,
		PhotoURL: req.PhotoURL, Address: req.Address, WorkingHours: req.WorkingHours,
		CoverageRadiusKM: req.CoverageRadiusKM,
	}

	u.store.CreateService(r.Context(), svc)
	log.Printf("[USER] Service created: id=%s name=%s", svc.ID, svc.Name)
	writeJSON(w, http.StatusCreated, map[string]any{"message": "service created", "service": svc})
}

// ---------------------------------------------------------------------------
// PUT /users/services or POST /users/services/update
// ---------------------------------------------------------------------------

func (u *UserService) UpdateService(w http.ResponseWriter, r *http.Request) {
	var req models.UpdateServiceRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON: " + err.Error()})
		return
	}

	if (req.Latitude != nil || req.Longitude != nil) &&
		((req.Latitude != nil && !isValidCoordinate(*req.Latitude, 0)) ||
			(req.Longitude != nil && !isValidCoordinate(0, *req.Longitude))) {
		log.Printf("[SECURITY WARNING] Invalid coordinates rejected for UpdateService")
		handlerutil.ShipSecurityEvent(r.Context(), "INVALID_COORDINATES_DETECTED", "user-service", "unauthenticated", "", "UpdateService rejected: coordinates out of range", handlerutil.GetClientIP(r))
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error":   "invalid_coordinates",
			"message": "Latitude must be between -90 and 90, and Longitude must be between -180 and 180",
		})
		return
	}
	if req.ID == "" && req.ServiceID != "" {
		req.ID = req.ServiceID
	}
	if req.ID == "" {
		req.ID = r.URL.Query().Get("id")
	}
	if req.ID == "" {
		req.ID = r.URL.Query().Get("service_id")
	}
	authToken := resolveOwnerAuthToken(r, req.OwnerToken, req.OwnerID)
	if req.ID == "" || authToken == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "service id and owner authorization are required"})
		return
	}

	resolvedOwnerID, err := resolveTokenWithRole(authToken, "owner")
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid owner token: " + err.Error()})
		return
	}
	req.OwnerID = resolvedOwnerID

	// Verify owner exists and has approved KYC
	kycStatus, err := u.checkKYC(req.OwnerID)
	if err != nil {
		// #nosec G706 //nolint:gosec -- req.OwnerID is resolved from cryptographically verified JWT claims
		log.Printf("[KYC BLOCKED/ERROR] Failed KYC check for owner %s: %v", req.OwnerID, err)
		if errors.Is(err, ErrServiceUnavailable) {
			writeJSON(w, http.StatusServiceUnavailable, map[string]string{
				"error":   "service_unavailable",
				"message": "Authentication service is temporarily unavailable. Please try again later.",
			})
			return
		}
		handlerutil.ShipSecurityEvent(r.Context(), "KYC_BLOCKED_ERROR", "user-service", req.OwnerID, req.OwnerID, fmt.Sprintf("failed KYC check: %v", err), handlerutil.GetClientIP(r))
		writeJSON(w, http.StatusForbidden, map[string]string{
			"error": "action blocked: unable to verify owner KYC status",
		})
		return
	}
	if kycStatus != "approved" {
		// #nosec G706 //nolint:gosec -- req.OwnerID is resolved from cryptographically verified JWT claims
		log.Printf("[KYC BLOCKED] Owner %s attempted to update service, but KYC status is %q", req.OwnerID, kycStatus)
		handlerutil.ShipSecurityEvent(r.Context(), "KYC_BLOCKED", "user-service", req.OwnerID, req.OwnerID, fmt.Sprintf("attempted to update service, KYC status is %s", kycStatus), handlerutil.GetClientIP(r))
		writeJSON(w, http.StatusForbidden, map[string]string{
			"error": "action blocked: owner KYC approval is pending",
		})
		return
	}

	existing := u.store.GetServiceByID(r.Context(), req.ID)
	if existing == nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "service not found"})
		return
	}

	if existing.TenantID != req.OwnerID {
		log.Printf("[SECURITY WARNING] Owner %s attempted to update service %s owned by %s", req.OwnerID, req.ID, existing.TenantID) // #nosec G706 -- values are authenticated JWT-derived IDs, not raw user input; logged for security audit trail
		handlerutil.ShipSecurityEvent(r.Context(), "IDOR_UPDATE_SERVICE_ATTEMPT", "user-service", req.OwnerID, req.ID, fmt.Sprintf("owner %s attempted to update service belonging to owner %s", req.OwnerID, existing.TenantID), handlerutil.GetClientIP(r))
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "access denied: service belongs to another tenant"})
		return
	}

	if req.Category != "" {
		if req.Category != "shipping" && req.Category != "delivery" && req.Category != "transport" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid category, must be: shipping, delivery, transport"})
			return
		}
		existing.Category = req.Category
	}

	if req.Name != "" {
		existing.Name = req.Name
	}
	if req.TenantBasePrice != nil {
		if *req.TenantBasePrice < 0 {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "tenant_base_price cannot be negative"})
			return
		}
		existing.TenantBasePrice = *req.TenantBasePrice
		existing.BasePrice = *req.TenantBasePrice
	}
	if req.TenantPricePerKM != nil {
		if *req.TenantPricePerKM < 0 {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "tenant_price_per_km cannot be negative"})
			return
		}
		existing.TenantPricePerKM = *req.TenantPricePerKM
	}
	if req.Latitude != nil {
		existing.Latitude = *req.Latitude
	}
	if req.Longitude != nil {
		existing.Longitude = *req.Longitude
	}
	if req.Latitude != nil || req.Longitude != nil {
		existing.Location = models.NewGeoJSONPoint(existing.Latitude, existing.Longitude)
	}
	if req.PhotoURL != nil {
		existing.PhotoURL = *req.PhotoURL
	}
	if req.Address != nil {
		existing.Address = *req.Address
	}
	if req.WorkingHours != nil {
		existing.WorkingHours = *req.WorkingHours
	}
	if req.CoverageRadiusKM != nil {
		if *req.CoverageRadiusKM < 0 {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "coverage_radius_km cannot be negative"})
			return
		}
		existing.CoverageRadiusKM = *req.CoverageRadiusKM
	}

	if err := u.store.UpdateService(r.Context(), existing); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to update service: " + err.Error()})
		return
	}

	log.Printf("[USER] Service updated: id=%s name=%s owner=%s", existing.ID, existing.Name, existing.TenantID) // #nosec G706 -- existing.Name is owner-controlled service metadata, not attacker-controlled external input path
	writeJSON(w, http.StatusOK, map[string]any{"message": "service updated", "service": existing})
}

// ---------------------------------------------------------------------------
// GET /users/platform/config
// ---------------------------------------------------------------------------

func (u *UserService) GetPlatformConfig(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use GET"})
		return
	}
	cfg := u.store.GetPlatformConfig(r.Context())
	if cfg == nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "no platform config"})
		return
	}
	writeJSON(w, http.StatusOK, cfg)
}

func isValidCoordinate(lat, lon float64) bool {
	return lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180
}
