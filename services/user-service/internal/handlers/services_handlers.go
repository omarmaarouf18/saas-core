package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"image"
	"image/jpeg"
	_ "image/jpeg"
	"image/png"
	_ "image/png"
	"io"
	"log"
	"net/http"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"

	"github.com/project/shared/infra/handlerutil"
	"github.com/project/shared/infra/storage"
	"github.com/project/user-service/internal/models"
	"github.com/project/user-service/internal/store"
	"go.mongodb.org/mongo-driver/v2/bson"
)

// ---------------------------------------------------------------------------
// GET /users/services
// ---------------------------------------------------------------------------

func (u *UserService) ListServices(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	ctx := r.Context()

	if id := q.Get("id"); id != "" || q.Get("service_id") != "" {
		if id == "" {
			id = q.Get("service_id")
		}
		svc := u.store.GetServiceByID(ctx, id)
		if svc == nil {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "service not found"})
			return
		}
		if isLocalPath(svc.PhotoURL) {
			svc.PhotoURL = ""
		}
		writeJSON(w, http.StatusOK, map[string]any{
			"count":    1,
			"service":  svc,
			"services": []*models.Service{svc},
		})
		return
	}

	sortBy := q.Get("sort_by")
	nearBy := q.Get("near_by") == "true"
	hasLat := q.Get("lat") != ""
	hasLon := q.Get("lon") != ""
	refLat := parseFloat(q.Get("lat"), 30.0444)
	refLon := parseFloat(q.Get("lon"), 31.2357)
	radius := parseFloat(q.Get("radius"), 50)

	var limit, offset int64
	if lStr := q.Get("limit"); lStr != "" {
		if l, err := strconv.ParseInt(lStr, 10, 64); err == nil {
			limit = l
		}
	}
	if oStr := q.Get("offset"); oStr != "" {
		if o, err := strconv.ParseInt(oStr, 10, 64); err == nil {
			offset = o
		}
	}

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

	// ADR-0024: the public listing excludes closed tenants' services server-side
	// (missing/unpaid/expired subscription); customers need no client-side logic.
	services := u.store.ListServicesOpenOnly(ctx, sortBy, nearBy, refLat, refLon, radius, limit, offset)
	for i := range services {
		if isLocalPath(services[i].PhotoURL) {
			services[i].PhotoURL = ""
		}
	}
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
		handlerutil.WriteSafeError(w, r, http.StatusBadRequest, handlerutil.ErrCodeInvalidJSON, "invalid request body", err)
		return
	}

	if req.PhotoURL == "" && req.Photo != "" {
		req.PhotoURL = req.Photo
	}
	if req.CoverageRadiusKM == 0 && req.CoverageRadius > 0 {
		req.CoverageRadiusKM = req.CoverageRadius
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
	if req.CoverageRadiusKM < 0 {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "coverage_radius_km must be non-negative",
		})
		return
	}
	// ADR-0025: validate the structured schedule before auth/KYC work, like
	// the other malformed-input checks above. Never silently coerce or drop.
	if err := models.ValidateServiceSchedule(req.ScheduleMode, req.OpenTime, req.CloseTime, req.PerDaySchedule); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error":   "invalid_schedule",
			"message": err.Error(),
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
		if strings.Contains(err.Error(), "role mismatch") {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": err.Error()})
			return
		}
		handlerutil.WriteSafeError(w, r, http.StatusUnauthorized, handlerutil.ErrCodeInvalidToken, "invalid or expired token", err)
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

	// Paid tier membership check
	if !u.enforcePaidTier(w, r, req.OwnerID, req.OwnerID, "create_service", "Service catalog creation") {
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

	if !isOwnPhotoKey(req.PhotoURL, req.OwnerID) {
		writeInvalidPhotoURL(w, r, req.OwnerID)
		return
	}

	svc := &models.Service{
		ID: generateID(), TenantID: req.OwnerID, Name: req.Name, Category: req.Category,
		BasePrice: req.TenantBasePrice, TenantBasePrice: req.TenantBasePrice,
		TenantPricePerKM: req.TenantPricePerKM, Latitude: req.Latitude, Longitude: req.Longitude,
		Location: models.NewGeoJSONPoint(req.Latitude, req.Longitude),
		PhotoURL: req.PhotoURL, Address: req.Address, WorkingHours: req.WorkingHours,
		CoverageRadiusKM: req.CoverageRadiusKM,
		ScheduleMode:     req.ScheduleMode, OpenTime: req.OpenTime, CloseTime: req.CloseTime,
		PerDaySchedule: req.PerDaySchedule, Timezone: req.Timezone,
	}

	if err := u.store.CreateService(r.Context(), svc); err != nil {
		if errors.Is(err, store.ErrServiceExists) {
			handlerutil.WriteSafeError(w, r, http.StatusConflict, handlerutil.ErrCodeConflict, "service already exists", err)
			return
		}
		handlerutil.WriteSafeError(w, r, http.StatusInternalServerError, handlerutil.ErrCodeInternal, "failed to create service", err)
		return
	}
	log.Printf("[USER] Service created: id=%s name=%s", svc.ID, svc.Name)
	if isLocalPath(svc.PhotoURL) {
		svc.PhotoURL = ""
	}
	writeJSON(w, http.StatusCreated, map[string]any{"message": "service created", "service": svc})
}

// ---------------------------------------------------------------------------
// PUT /users/services or POST /users/services/update
// ---------------------------------------------------------------------------

func (u *UserService) UpdateService(w http.ResponseWriter, r *http.Request) {
	var req models.UpdateServiceRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		handlerutil.WriteSafeError(w, r, http.StatusBadRequest, handlerutil.ErrCodeInvalidJSON, "invalid request body", err)
		return
	}

	if req.PhotoURL == nil && req.Photo != nil {
		req.PhotoURL = req.Photo
	}
	if req.CoverageRadiusKM == nil && req.CoverageRadius != nil {
		req.CoverageRadiusKM = req.CoverageRadius
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
		if strings.Contains(err.Error(), "role mismatch") {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": err.Error()})
			return
		}
		handlerutil.WriteSafeError(w, r, http.StatusUnauthorized, handlerutil.ErrCodeInvalidToken, "invalid or expired token", err)
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

	// Paid tier membership check
	if !u.enforcePaidTier(w, r, req.OwnerID, req.OwnerID, "update_service", "Service catalog updates") {
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

	updateFields := bson.M{}

	if req.Category != "" {
		if req.Category != "shipping" && req.Category != "delivery" && req.Category != "transport" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid category, must be: shipping, delivery, transport"})
			return
		}
		updateFields["category"] = req.Category
	}

	if req.Name != "" {
		updateFields["name"] = req.Name
	}
	if req.TenantBasePrice != nil {
		if *req.TenantBasePrice < 0 {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "tenant_base_price cannot be negative"})
			return
		}
		updateFields["tenant_base_price"] = *req.TenantBasePrice
		updateFields["base_price"] = *req.TenantBasePrice
	}
	if req.TenantPricePerKM != nil {
		if *req.TenantPricePerKM < 0 {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "tenant_price_per_km cannot be negative"})
			return
		}
		updateFields["tenant_price_per_km"] = *req.TenantPricePerKM
	}
	if req.Latitude != nil {
		updateFields["latitude"] = *req.Latitude
	}
	if req.Longitude != nil {
		updateFields["longitude"] = *req.Longitude
	}
	if req.Latitude != nil || req.Longitude != nil {
		newLat := existing.Latitude
		if req.Latitude != nil {
			newLat = *req.Latitude
		}
		newLon := existing.Longitude
		if req.Longitude != nil {
			newLon = *req.Longitude
		}
		updateFields["location"] = models.NewGeoJSONPoint(newLat, newLon)
	}
	if req.PhotoURL != nil {
		// Resending the stored value unchanged is always fine (it may be a
		// legacy value written before this guard).
		if *req.PhotoURL != existing.PhotoURL && !isOwnPhotoKey(*req.PhotoURL, existing.ID, existing.TenantID) {
			writeInvalidPhotoURL(w, r, req.OwnerID)
			return
		}
		updateFields["photo_url"] = *req.PhotoURL
	}
	if req.Address != nil {
		updateFields["address"] = *req.Address
	}
	if req.WorkingHours != nil {
		updateFields["working_hours"] = *req.WorkingHours
	}
	if req.CoverageRadiusKM != nil {
		if *req.CoverageRadiusKM < 0 {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "coverage_radius_km cannot be negative"})
			return
		}
		updateFields["coverage_radius_km"] = *req.CoverageRadiusKM
	}

	// ADR-0025: validate the effective schedule (stored values overridden by
	// provided ones) so partial updates cannot leave a malformed schedule
	// behind. Clearing schedule_mode to "" returns the service to "unknown"
	// (always open); stale schedule fields left stored alongside it are inert
	// because evaluation is governed by the mode.
	effMode, effOpen, effClose, effPerDay := existing.ScheduleMode, existing.OpenTime, existing.CloseTime, existing.PerDaySchedule
	if req.ScheduleMode != nil {
		effMode = *req.ScheduleMode
	}
	if req.OpenTime != nil {
		effOpen = *req.OpenTime
	}
	if req.CloseTime != nil {
		effClose = *req.CloseTime
	}
	if req.PerDaySchedule != nil {
		effPerDay = *req.PerDaySchedule
	}
	if effMode == "" {
		// Explicit (or continuing) unknown schedule: companion fields are
		// inert because evaluation is governed by the mode, so validation
		// considers them cleared rather than stray.
		effOpen, effClose, effPerDay = "", "", nil
	}
	if err := models.ValidateServiceSchedule(effMode, effOpen, effClose, effPerDay); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error":   "invalid_schedule",
			"message": err.Error(),
		})
		return
	}
	if req.ScheduleMode != nil {
		updateFields["schedule_mode"] = *req.ScheduleMode
		if *req.ScheduleMode == "" {
			// Explicit clear: drop the now-inert companion fields too.
			updateFields["open_time"] = ""
			updateFields["close_time"] = ""
			updateFields["per_day_schedule"] = bson.A{}
		}
	}
	if req.OpenTime != nil {
		updateFields["open_time"] = *req.OpenTime
	}
	if req.CloseTime != nil {
		updateFields["close_time"] = *req.CloseTime
	}
	if req.PerDaySchedule != nil {
		updateFields["per_day_schedule"] = *req.PerDaySchedule
	}
	if req.Timezone != nil {
		// Stored as-is; unloadable values fall back to Africa/Cairo at
		// evaluation time (ADR-0025), so no write-time rejection here.
		updateFields["timezone"] = *req.Timezone
	}

	updated, err := u.store.UpdateServiceFields(r.Context(), existing.ID, existing.TenantID, updateFields)
	if err != nil {
		handlerutil.WriteSafeError(w, r, http.StatusInternalServerError, handlerutil.ErrCodeInternal, "failed to update service", err)
		return
	}

	if req.PhotoURL != nil && *req.PhotoURL != existing.PhotoURL {
		// Removed (photo_url: "") or replaced: the old object goes too.
		u.deleteServicePhotoObject(r.Context(), existing, existing.PhotoURL)
	}

	log.Printf("[USER] Service updated: id=%s name=%s owner=%s", updated.ID, updated.Name, updated.TenantID) // #nosec G706 -- updated.Name is owner-controlled service metadata, not attacker-controlled external input path
	writeJSON(w, http.StatusOK, map[string]any{"message": "service updated", "service": updated})
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
	// PAY-COD-ONLY: the app reads digital_payments_enabled to decide whether
	// to offer anything but cash on delivery.
	writeJSON(w, http.StatusOK, struct {
		*models.PlatformConfig
		DigitalPaymentsEnabled bool `json:"digital_payments_enabled"`
	}{cfg, u.digitalPaymentsAvailable()})
}

func isValidCoordinate(lat, lon float64) bool {
	return lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180
}

// ---------------------------------------------------------------------------
// POST /users/services/photo or POST /users/services/photo/upload or POST /users/services/{id}/photo
// ---------------------------------------------------------------------------

func (u *UserService) UploadServicePhoto(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use POST"})
		return
	}

	if u.storage == nil {
		writePhotoStorageUnavailable(w, r, nil)
		return
	}

	authToken := resolveOwnerAuthToken(r, r.FormValue("owner_token"), r.FormValue("owner_id"))
	if authToken == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "owner authorization required"})
		return
	}
	ownerID, err := resolveTokenWithRole(authToken, "owner")
	if err != nil {
		if strings.Contains(err.Error(), "role mismatch") {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": err.Error()})
			return
		}
		handlerutil.WriteSafeError(w, r, http.StatusUnauthorized, handlerutil.ErrCodeInvalidToken, "invalid or expired token", err)
		return
	}

	// Verify owner exists and has approved KYC
	kycStatus, err := u.checkKYC(ownerID)
	if err != nil {
		if errors.Is(err, ErrServiceUnavailable) {
			writeJSON(w, http.StatusServiceUnavailable, map[string]string{
				"error":   "service_unavailable",
				"message": "Authentication service is temporarily unavailable. Please try again later.",
			})
			return
		}
		writeJSON(w, http.StatusForbidden, map[string]string{
			"error": "action blocked: unable to verify owner KYC status",
		})
		return
	}
	if kycStatus != "approved" {
		writeJSON(w, http.StatusForbidden, map[string]string{
			"error": "action blocked: owner KYC approval is pending",
		})
		return
	}

	// Paid tier membership check
	if !u.enforcePaidTier(w, r, ownerID, ownerID, "upload_service_photo", "Service photo upload") {
		return
	}

	serviceID := r.URL.Query().Get("id")
	if serviceID == "" {
		serviceID = r.URL.Query().Get("service_id")
	}
	if serviceID == "" {
		serviceID = r.FormValue("service_id")
	}
	if serviceID == "" {
		serviceID = r.FormValue("id")
	}
	if serviceID == "" {
		serviceID = extractServiceIDFromPhotoPath(r.URL.Path)
	}

	var existingService *models.Service
	if serviceID != "" {
		existingService = u.store.GetServiceByID(r.Context(), serviceID)
		if existingService == nil {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "service not found"})
			return
		}
		if existingService.TenantID != ownerID {
			handlerutil.ShipSecurityEvent(r.Context(), "IDOR_SERVICE_PHOTO_ATTEMPT", "user-service", ownerID, serviceID, "owner attempted to upload photo for service belonging to another tenant", handlerutil.GetClientIP(r))
			writeJSON(w, http.StatusForbidden, map[string]string{"error": "access denied: service belongs to another tenant"})
			return
		}
	}

	r.Body = http.MaxBytesReader(w, r.Body, 5<<20)

	var fileData []byte
	contentType := r.Header.Get("Content-Type")

	if strings.HasPrefix(contentType, "multipart/form-data") {
		// #nosec G120 //nolint:gosec -- body is bounded by http.MaxBytesReader, preventing memory exhaustion
		if err := r.ParseMultipartForm(5 << 20); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "photo exceeds maximum size of 5MB or invalid multipart body"})
			return
		}
		file, header, err := r.FormFile("photo")
		if err != nil {
			file, header, err = r.FormFile("file")
		}
		if err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "photo file is required"})
			return
		}
		defer file.Close()
		if header.Size > 5<<20 {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "photo exceeds maximum size of 5MB"})
			return
		}
		fileData, err = io.ReadAll(file)
		if err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "failed to read photo file"})
			return
		}
	} else {
		var err error
		fileData, err = io.ReadAll(r.Body)
		if err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "photo exceeds maximum size of 5MB or read failed"})
			return
		}
	}

	if len(fileData) == 0 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "photo file is empty"})
		return
	}
	if len(fileData) > 5<<20 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "photo exceeds maximum size of 5MB"})
		return
	}

	// Magic-byte check
	// JPEG: FF D8 FF
	// PNG: 89 50 4E 47 0D 0A 1A 0A
	isJPEG := len(fileData) >= 3 && fileData[0] == 0xFF && fileData[1] == 0xD8 && fileData[2] == 0xFF
	isPNG := len(fileData) >= 8 && bytes.Equal(fileData[:8], []byte{0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A})

	if !isJPEG && !isPNG {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "invalid image format: only JPEG and PNG are allowed",
		})
		return
	}

	img, format, err := image.Decode(bytes.NewReader(fileData))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "corrupt or invalid image"})
		return
	}

	var cleanBuf bytes.Buffer
	var ext string
	var mimeType string

	switch format {
	case "png":
		ext = "png"
		mimeType = "image/png"
		if err := png.Encode(&cleanBuf, img); err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to process image"})
			return
		}
	case "jpeg":
		ext = "jpg"
		mimeType = "image/jpeg"
		if err := jpeg.Encode(&cleanBuf, img, &jpeg.Options{Quality: 85}); err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to process image"})
			return
		}
	default:
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "unsupported image format"})
		return
	}

	// Every upload gets a new random key (PROD-PHOTO-STORAGE item 7): a
	// replaced photo never reuses the old key, so clients and caches that
	// key on photo_url always see the new image.
	scope := ownerID
	if existingService != nil {
		scope = existingService.ID
	}
	key := fmt.Sprintf("services/%s/photo_%s.%s", scope, generateID(), ext)

	if err := u.storage.Upload(r.Context(), key, bytes.NewReader(cleanBuf.Bytes()), mimeType); err != nil {
		writePhotoStorageUnavailable(w, r, err)
		return
	}

	if existingService != nil {
		if _, err := u.store.UpdateServiceFields(r.Context(), existingService.ID, ownerID, bson.M{"photo_url": key}); err != nil {
			handlerutil.WriteSafeError(w, r, http.StatusInternalServerError, handlerutil.ErrCodeInternal, "failed to update service photo", err)
			return
		}
		// The key is always new, so a previous photo is always replaced:
		// drop its object (BE-GAPS-FIX delete path, this tenant's keys only).
		u.deleteServicePhotoObject(r.Context(), existingService, existingService.PhotoURL)
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"message":   "photo uploaded",
		"photo_url": key,
		"key":       key,
	})
}

// ErrCodeInvalidPhotoURL: photo_url on POST/PUT /users/services is neither
// empty nor a key this tenant's photo upload produced. Always 400.
const ErrCodeInvalidPhotoURL = "invalid_photo_url"

// photoKeyName is the file part of a key the photo upload writes:
// photo.<ext> / photo_<n>.<ext> (older uploads) and photo_<hex>.<ext>.
var photoKeyName = regexp.MustCompile(`^photo(_[0-9A-Za-z]+)?\.(jpg|png)$`)

// isOwnPhotoKey reports whether photoURL may be written to a service's
// photo_url: empty (no photo), or services/<scope>/<photo file> for one of
// the given scopes (the service ID and/or its tenant ID) — the same prefix
// rule deleteServicePhotoObject uses. Anything else (another tenant's key,
// a URL, a device path, a traversal) is rejected, so photo_url can never
// point at an object this tenant did not upload.
func isOwnPhotoKey(photoURL string, scopes ...string) bool {
	if photoURL == "" {
		return true
	}
	for _, scope := range scopes {
		if scope == "" {
			continue
		}
		name, ok := strings.CutPrefix(photoURL, "services/"+scope+"/")
		if ok && photoKeyName.MatchString(name) {
			return true
		}
	}
	return false
}

// writeInvalidPhotoURL answers 400 invalid_photo_url and records the
// attempt as a security event (it may be probing another tenant's key).
func writeInvalidPhotoURL(w http.ResponseWriter, r *http.Request, ownerID string) {
	handlerutil.ShipSecurityEvent(r.Context(), "INVALID_PHOTO_URL", "user-service", ownerID, "", "photo_url is not a key of this tenant's photo upload", handlerutil.GetClientIP(r))
	handlerutil.WriteSafeError(w, r, http.StatusBadRequest, ErrCodeInvalidPhotoURL, "photo_url must be empty or a key returned by the photo upload", nil)
}

// ErrCodePhotoStorageUnavailable is the one stable code for "service photo
// storage cannot be used right now": storage was never initialized, or
// writing the object failed (BE-GAPS-FIX item 3). Always 503.
const ErrCodePhotoStorageUnavailable = "photo_storage_unavailable"

// writePhotoStorageUnavailable answers 503 photo_storage_unavailable. The
// underlying error (paths, I/O detail) is logged, never returned.
func writePhotoStorageUnavailable(w http.ResponseWriter, r *http.Request, err error) {
	if err == nil {
		err = errors.New("storage not initialized")
	}
	handlerutil.WriteSafeError(w, r, http.StatusServiceUnavailable, ErrCodePhotoStorageUnavailable, "photo storage unavailable", err)
}

// deleteServicePhotoObject removes a service photo object that the service
// no longer references (BE-GAPS-FIX item 4). Only keys this tenant wrote are
// touched: services/<service id>/... (upload for an existing service) or
// services/<owner id>/... (upload before the service existed). Any other
// key — another tenant's, a legacy device path — is left alone, so an
// owner cannot delete objects by pointing photo_url at them. Best effort:
// the field is already updated, a failed delete is only logged.
func (u *UserService) deleteServicePhotoObject(ctx context.Context, svc *models.Service, key string) {
	if svc == nil || key == "" || isLocalPath(key) {
		return
	}
	if !strings.HasPrefix(key, "services/"+svc.ID+"/") && !strings.HasPrefix(key, "services/"+svc.TenantID+"/") {
		return
	}
	deleter, ok := u.storage.(storage.Deleter)
	if !ok {
		return
	}
	if err := deleter.Delete(ctx, key); err != nil {
		log.Printf("[USER] Failed to delete old photo of service %s: %v", svc.ID, err) // #nosec G706 -- service ID is server-generated
	}
}

// ---------------------------------------------------------------------------
// GET /users/services/photo or GET /users/services/{id}/photo
// ---------------------------------------------------------------------------

func (u *UserService) GetServicePhoto(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use GET"})
		return
	}

	if u.storage == nil {
		writePhotoStorageUnavailable(w, r, nil)
		return
	}

	tokenStr := r.Header.Get("Authorization")
	if strings.HasPrefix(tokenStr, "Bearer ") || strings.HasPrefix(tokenStr, "bearer ") {
		tokenStr = strings.TrimSpace(tokenStr[7:])
	}
	if tokenStr == "" {
		tokenStr = r.URL.Query().Get("token")
	}
	if tokenStr == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "authentication required"})
		return
	}

	_, err := resolveTokenWithRole(tokenStr, "user", "customer", "owner", "employee", "admin")
	if err != nil {
		handlerutil.WriteSafeError(w, r, http.StatusUnauthorized, handlerutil.ErrCodeInvalidToken, "invalid or expired token", err)
		return
	}

	key := r.URL.Query().Get("key")
	if key == "" {
		serviceID := r.URL.Query().Get("id")
		if serviceID == "" {
			serviceID = r.URL.Query().Get("service_id")
		}
		if serviceID == "" {
			serviceID = extractServiceIDFromPhotoPath(r.URL.Path)
		}
		if serviceID != "" {
			svc := u.store.GetServiceByID(r.Context(), serviceID)
			if svc != nil {
				key = svc.PhotoURL
			}
		}
	}

	if key == "" || isLocalPath(key) {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "service photo not found"})
		return
	}

	fileRC, err := u.storage.OpenFile(key)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "service photo not found"})
		return
	}
	defer fileRC.Close()

	ext := strings.ToLower(filepath.Ext(key))
	contentType := "application/octet-stream"
	switch ext {
	case ".jpg", ".jpeg":
		contentType = "image/jpeg"
	case ".png":
		contentType = "image/png"
	}

	w.Header().Set("Content-Type", contentType)
	w.Header().Set("Cache-Control", "private, max-age=86400")
	w.WriteHeader(http.StatusOK)
	_, _ = io.Copy(w, fileRC)
}

func extractServiceIDFromPhotoPath(p string) string {
	clean := strings.TrimPrefix(p, "/users/services/")
	clean = strings.TrimPrefix(clean, "/api/v1/users/services/")
	parts := strings.Split(clean, "/")
	if len(parts) >= 2 && (parts[1] == "photo" || parts[1] == "photo/upload") {
		return parts[0]
	}
	return ""
}

func isLocalPath(p string) bool {
	p = strings.TrimSpace(p)
	if p == "" {
		return false
	}
	if strings.HasPrefix(p, "file://") ||
		strings.HasPrefix(p, "/") ||
		strings.HasPrefix(p, "\\") ||
		strings.HasPrefix(p, "./") ||
		strings.HasPrefix(p, "../") ||
		(len(p) > 2 && p[1] == ':' && (p[2] == '/' || p[2] == '\\')) {
		return true
	}
	return false
}
