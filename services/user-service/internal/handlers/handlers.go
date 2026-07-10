// Package handlers implements HTTP handlers for the user-service.
package handlers

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"math"
	"net/http"
	"os"
	"strconv"
	"sync"
	"time"

	"github.com/project/user-service/internal/jwtutil"
	"github.com/project/user-service/internal/models"
	"github.com/project/user-service/internal/store"
)

// ErrUpgradeRequired is returned when a tenant's subscription tier is insufficient for a gated feature.
var ErrUpgradeRequired = errors.New("upgrade_required")

// MinLocationUpdateInterval defines the minimum wait time between consecutive location updates per job.
const MinLocationUpdateInterval = 3 * time.Second

// UserService holds dependencies for the user-service handlers.
type UserService struct {
	store                *store.MongoDB
	authServiceURL       string
	chatServiceURL       string
	limiter              *RateLimiter
	internalServiceToken string
	locationThrottleMu   sync.Mutex
	locationLastUpdate   map[string]time.Time
	locationInFlight     map[string]bool
}

// NewUserService creates a new handler group.
func NewUserService(s *store.MongoDB, authServiceURL string, internalServiceToken string) *UserService {
	chatServiceURL := os.Getenv("CHAT_SERVICE_URL")
	if chatServiceURL == "" {
		chatServiceURL = "http://localhost:3001"
	}
	InitCloudWatch()
	return &UserService{
		store:                s,
		authServiceURL:       authServiceURL,
		chatServiceURL:       chatServiceURL,
		limiter:              NewRateLimiter(5, 1*time.Minute),
		internalServiceToken: internalServiceToken,
		locationLastUpdate:   make(map[string]time.Time),
		locationInFlight:     make(map[string]bool),
	}
}

// RegisterRoutes mounts all user-service endpoints on the given ServeMux.
func (u *UserService) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/users/services", func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		case http.MethodGet:
			u.ListServices(w, r)
		case http.MethodPost:
			u.CreateService(w, r)
		default:
			writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		}
	})
	mux.HandleFunc("/users/jobs/track", u.TrackJob)
	mux.HandleFunc("/users/jobs/get", u.GetJob)
	mux.HandleFunc("/users/jobs/complete", u.CompleteJob)
	mux.HandleFunc("/users/wallet", u.GetWallet)
	mux.HandleFunc("/users/wallet/deposit", u.WalletDeposit)
	mux.HandleFunc("/users/ledger", u.GetLedger)
	mux.HandleFunc("/users/platform/config", u.GetPlatformConfig)
	mux.HandleFunc("/users/subscription", u.Subscription)
	mux.HandleFunc("/users/jobs/rate", u.RateJob)
	mux.HandleFunc("/users/ratings", u.GetRatings)
	mux.HandleFunc("/users/jobs/location/update", u.UpdateJobLocation)
}

// ---------------------------------------------------------------------------
// GET /users/services
// ---------------------------------------------------------------------------

func (u *UserService) ListServices(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	sortBy := q.Get("sort_by")
	nearBy := q.Get("near_by") == "true"
	refLat := parseFloat(q.Get("lat"), 30.0444)
	refLon := parseFloat(q.Get("lon"), 31.2357)
	radius := parseFloat(q.Get("radius"), 50)

	ctx := r.Context()
	services := u.store.ListServices(ctx, sortBy, nearBy, refLat, refLon, radius)
	log.Printf("[USER] ListServices: sort_by=%s near_by=%v results=%d", sortBy, nearBy, len(services))

	writeJSON(w, http.StatusOK, map[string]any{
		"count": len(services), "sort_by": sortBy, "near_by": nearBy, "services": services,
	})
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
	if req.OwnerID == "" || req.Name == "" || req.Category == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "owner_id, name, and category are required"})
		return
	}

	resolvedOwnerID, err := resolveToken(req.OwnerID)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid owner token: " + err.Error()})
		return
	}
	req.OwnerID = resolvedOwnerID

	// Verify owner exists and has approved KYC
	kycStatus, err := u.checkKYC(req.OwnerID)
	if err != nil {
		log.Printf("[KYC BLOCKED/ERROR] Failed KYC check for owner %s: %v", req.OwnerID, err)
		ShipSecurityEvent(r.Context(), "KYC_BLOCKED_ERROR", "user-service", req.OwnerID, req.OwnerID, fmt.Sprintf("failed KYC check: %v", err), getClientIP(r))
		writeJSON(w, http.StatusForbidden, map[string]string{
			"error": "action blocked: unable to verify owner KYC status",
		})
		return
	}
	if kycStatus != "approved" {
		log.Printf("[KYC BLOCKED] Owner %s attempted to create service, but KYC status is %q", req.OwnerID, kycStatus)
		ShipSecurityEvent(r.Context(), "KYC_BLOCKED", "user-service", req.OwnerID, req.OwnerID, fmt.Sprintf("attempted to create service, KYC status is %s", kycStatus), getClientIP(r))
		writeJSON(w, http.StatusForbidden, map[string]string{
			"error": "action blocked: owner KYC approval is pending",
		})
		return
	}
	if req.Category != "shipping" && req.Category != "delivery" && req.Category != "transport" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid category, must be: shipping, delivery, transport"})
		return
	}

	svc := &models.Service{
		ID: generateID(), TenantID: req.OwnerID, Name: req.Name, Category: req.Category,
		BasePrice: req.TenantBasePrice, TenantBasePrice: req.TenantBasePrice,
		TenantPricePerKM: req.TenantPricePerKM, Latitude: req.Latitude, Longitude: req.Longitude,
	}

	u.store.CreateService(r.Context(), svc)
	log.Printf("[USER] Service created: id=%s name=%s", svc.ID, svc.Name)
	writeJSON(w, http.StatusCreated, map[string]any{"message": "service created", "service": svc})
}

// ---------------------------------------------------------------------------
// POST /users/jobs/track — with escrow locking
// ---------------------------------------------------------------------------

func (u *UserService) TrackJob(w http.ResponseWriter, r *http.Request) {
	ip := getIP(r)
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
	var req models.CreateJobRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON: " + err.Error()})
		return
	}
	if req.OwnerID == "" || req.ServiceID == "" || req.UserID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "owner_id, service_id, and user_id are required"})
		return
	}

	resolvedOwnerID, err := resolveToken(req.OwnerID)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid owner token: " + err.Error()})
		return
	}
	req.OwnerID = resolvedOwnerID

	resolvedUserID, err := resolveToken(req.UserID)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid user token: " + err.Error()})
		return
	}
	req.UserID = resolvedUserID

	if req.EmployeeID != "" {
		resolvedEmployeeID, err := resolveToken(req.EmployeeID)
		if err != nil {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid employee token: " + err.Error()})
			return
		}
		req.EmployeeID = resolvedEmployeeID
	}

	if req.PaymentMethod != "cod" {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "invalid payment_method: only 'cod' is currently supported",
		})
		return
	}

	// Verify owner exists and has approved KYC
	kycStatus, err := u.checkKYC(req.OwnerID)
	if err != nil {
		log.Printf("[KYC BLOCKED/ERROR] Failed KYC check for owner %s: %v", req.OwnerID, err)
		ShipSecurityEvent(r.Context(), "KYC_BLOCKED_ERROR", "user-service", req.OwnerID, req.OwnerID, fmt.Sprintf("failed KYC check: %v", err), getClientIP(r))
		writeJSON(w, http.StatusForbidden, map[string]string{
			"error": "action blocked: unable to verify owner KYC status",
		})
		return
	}
	if kycStatus != "approved" {
		log.Printf("[KYC BLOCKED] Owner %s attempted to track job, but KYC status is %q", req.OwnerID, kycStatus)
		ShipSecurityEvent(r.Context(), "KYC_BLOCKED", "user-service", req.OwnerID, req.OwnerID, fmt.Sprintf("attempted to track job, KYC status is %s", kycStatus), getClientIP(r))
		writeJSON(w, http.StatusForbidden, map[string]string{
			"error": "action blocked: owner KYC approval is pending",
		})
		return
	}

	ctx := r.Context()

	// Look up service to calculate escrow amount.
	svc := u.store.GetServiceByID(ctx, req.ServiceID)
	if svc == nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "service not found"})
		return
	}

	// Calculate ride cost: base_price + (distance × price_per_km).
	dist := haversineKm(req.Location.Latitude, req.Location.Longitude, svc.Latitude, svc.Longitude)
	escrowAmount := math.Round((svc.TenantBasePrice+(dist*svc.TenantPricePerKM))*100) / 100

	now := time.Now().UTC()
	job := &models.Job{
		ID: generateID(), OwnerID: req.OwnerID, EmployeeID: req.EmployeeID,
		UserID:    req.UserID,
		ServiceID: req.ServiceID, Status: models.JobStatusPending,
		Location: req.Location, PaymentMethod: req.PaymentMethod,
		CreatedAt: now, UpdatedAt: now,
	}

	if err := u.store.CreateJob(ctx, job); err != nil {
		writeJSON(w, http.StatusConflict, map[string]string{"error": err.Error()})
		return
	}

	// Lock escrow only for non-COD (or skip for COD jobs)
	if req.PaymentMethod == "cod" {
		log.Printf("[USER] Job %s created (COD payment method)", job.ID)
		// Progress to active.
		u.store.UpdateJobStatus(ctx, job.ID, models.JobStatusActive)
		job.Status = models.JobStatusActive
		job.UpdatedAt = time.Now().UTC()

		writeJSON(w, http.StatusCreated, map[string]any{
			"message":        "job tracking record created",
			"lifecycle_note": "COD, all up to date",
			"job":            job,
		})
		return
	}

	// Lock escrow for this job (e-wallet/bank card flow)
	if err := u.store.LockEscrow(ctx, req.OwnerID, job.ID, escrowAmount); err != nil {
		log.Printf("[USER] Escrow lock failed for job %s: %v", job.ID, err)
		// Job created but unfunded — still report it.
		writeJSON(w, http.StatusCreated, map[string]any{
			"message": "job created but escrow lock failed — deposit funds first",
			"warning": err.Error(), "job": job, "escrow_amount": escrowAmount,
		})
		return
	}

	log.Printf("[USER] Job %s created with escrow %.2f locked", job.ID, escrowAmount)

	// Progress to active.
	u.store.UpdateJobStatus(ctx, job.ID, models.JobStatusActive)
	job.Status = models.JobStatusActive
	job.UpdatedAt = time.Now().UTC()

	writeJSON(w, http.StatusCreated, map[string]any{
		"message": "job tracking record created", "lifecycle_note": "escrow locked, all up to date",
		"job": job, "escrow_locked": escrowAmount,
	})
}

// ---------------------------------------------------------------------------
// POST /users/jobs/complete — escrow release with profit split
// ---------------------------------------------------------------------------

func (u *UserService) CompleteJob(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use POST"})
		return
	}
	var req models.CompleteJobRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON: " + err.Error()})
		return
	}
	if req.JobID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "job_id is required"})
		return
	}

	ctx := r.Context()
	job := u.store.GetJob(ctx, req.JobID)
	if job == nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "job not found"})
		return
	}

	// Authorization check
	isInternal := r.Header.Get("X-Internal-Token") == u.internalServiceToken
	if !isInternal {
		requesterToken := r.URL.Query().Get("requester_id")
		if requesterToken == "" {
			requesterToken = req.RequesterID
		}
		if requesterToken == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "requester_id parameter is required"})
			return
		}
		resolvedRequester, err := resolveToken(requesterToken)
		if err != nil {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid requester token: " + err.Error()})
			return
		}

		if resolvedRequester != job.OwnerID && (job.EmployeeID == "" || resolvedRequester != job.EmployeeID) {
			log.Printf("[TENANT SCOPE BLOCKED] User %s attempted to complete job %s owned by owner %s and employee %s", resolvedRequester, job.ID, job.OwnerID, job.EmployeeID)
			ShipSecurityEvent(r.Context(), "TENANT_SCOPE_BLOCKED", "user-service", resolvedRequester, job.OwnerID, fmt.Sprintf("attempted to complete job %s", job.ID), getClientIP(r))
			writeJSON(w, http.StatusForbidden, map[string]string{"error": "access denied: you are not authorized to complete this job"})
			return
		}
	}

	if job.Status == models.JobStatusCompleted {
		writeJSON(w, http.StatusConflict, map[string]string{"error": "job already completed"})
		return
	}

	// Recalculate the amount to release.
	svc := u.store.GetServiceByID(ctx, job.ServiceID)
	if svc == nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "service not found for job"})
		return
	}
	dist := haversineKm(job.Location.Latitude, job.Location.Longitude, svc.Latitude, svc.Longitude)
	amount := math.Round((svc.TenantBasePrice+(dist*svc.TenantPricePerKM))*100) / 100

	// Handle COD payment method
	if job.PaymentMethod == "cod" {
		if !req.CashCollected {
			writeJSON(w, http.StatusBadRequest, map[string]string{
				"error": "action blocked: cash collection must be confirmed (cash_collected: true) for COD jobs",
			})
			return
		}

		// Deduct platform fee directly from owner's wallet (allows negative balance)
		if err := u.store.DeductCODFee(ctx, job.OwnerID, job.ID, amount); err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to deduct platform fee: " + err.Error()})
			return
		}

		u.store.UpdateJobStatus(ctx, job.ID, models.JobStatusCompleted)
		job.Status = models.JobStatusCompleted
		job.UpdatedAt = time.Now().UTC()

		cfg := u.store.GetPlatformConfig(ctx)
		feePercent := 15.0
		if cfg != nil {
			feePercent = cfg.PlatformFeePercentage
		}
		fee := math.Round(amount*feePercent) / 100

		log.Printf("[USER] COD Job %s completed: cash_collected=%.2f fee=%.2f deducted from owner wallet", job.ID, amount, fee)
		writeJSON(w, http.StatusOK, map[string]any{
			"message":          "COD job completed and platform fee deducted",
			"job_id":           job.ID,
			"total_amount":     amount,
			"platform_fee":     fee,
			"platform_fee_pct": feePercent,
		})
		return
	}

	// Release escrow with profit splitting (Non-COD flow)
	if err := u.store.ReleaseEscrowWithSplit(ctx, job.OwnerID, job.ID, amount); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "escrow release failed: " + err.Error()})
		return
	}

	u.store.UpdateJobStatus(ctx, job.ID, models.JobStatusCompleted)

	cfg := u.store.GetPlatformConfig(ctx)
	feePercent := 15.0
	if cfg != nil {
		feePercent = cfg.PlatformFeePercentage
	}
	fee := math.Round(amount*feePercent) / 100
	net := amount - fee

	log.Printf("[USER] Job %s completed: total=%.2f fee=%.2f net=%.2f", job.ID, amount, fee, net)
	writeJSON(w, http.StatusOK, map[string]any{
		"message": "job completed — profit split executed",
		"job_id":  job.ID, "total_amount": amount,
		"platform_fee": fee, "platform_fee_pct": feePercent,
		"net_to_tenant": net,
	})
}

// ---------------------------------------------------------------------------
// GET /users/jobs/get?id=xxx
// ---------------------------------------------------------------------------

func (u *UserService) GetJob(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}
	id := r.URL.Query().Get("id")
	if id == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "id parameter is required"})
		return
	}
	ctx := r.Context()
	job := u.store.GetJob(ctx, id)
	if job == nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "job not found"})
		return
	}

	// 1. Internal trusted token check
	if r.Header.Get("X-Internal-Token") == u.internalServiceToken {
		writeJSON(w, http.StatusOK, job)
		return
	}

	// 2. External client check: require requester_id query param
	requesterToken := r.URL.Query().Get("requester_id")
	if requesterToken == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "requester_id parameter is required"})
		return
	}
	resolvedRequester, err := resolveToken(requesterToken)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid requester token: " + err.Error()})
		return
	}

	if resolvedRequester != job.OwnerID && resolvedRequester != job.UserID && (job.EmployeeID == "" || resolvedRequester != job.EmployeeID) {
		log.Printf("[TENANT SCOPE BLOCKED] User %s attempted to access job %s owned by owner %s, employee %s, user %s", resolvedRequester, job.ID, job.OwnerID, job.EmployeeID, job.UserID)
		ShipSecurityEvent(r.Context(), "TENANT_SCOPE_BLOCKED", "user-service", resolvedRequester, job.OwnerID, fmt.Sprintf("attempted to access job %s", job.ID), getClientIP(r))
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "access denied: you are not authorized to view this job"})
		return
	}

	writeJSON(w, http.StatusOK, job)
}

// ---------------------------------------------------------------------------
// GET /users/wallet?tenant_id=xxx
// ---------------------------------------------------------------------------

func (u *UserService) GetWallet(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use GET"})
		return
	}
	tenantID := r.URL.Query().Get("tenant_id")
	if tenantID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "tenant_id required"})
		return
	}
	resolvedTenantID, err := resolveToken(tenantID)
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
	ip := getIP(r)
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
	const maxDepositAmount = 1_000_000
	if req.TenantID == "" || req.Amount <= 0 || req.Amount > maxDepositAmount {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": fmt.Sprintf("tenant_id and positive amount up to %d required", maxDepositAmount),
		})
		return
	}

	resolvedTenantID, err := resolveToken(req.TenantID)
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
		ShipSecurityEvent(r.Context(), "KYC_BLOCKED_ERROR", "user-service", req.TenantID, req.TenantID, fmt.Sprintf("failed KYC check: %v", err), getClientIP(r))
		writeJSON(w, http.StatusForbidden, map[string]string{
			"error": "action blocked: unable to verify owner KYC status",
		})
		return
	}
	if kycStatus != "approved" {
		log.Printf("[KYC BLOCKED] Owner %s attempted to deposit to wallet, but KYC status is %q", req.TenantID, kycStatus)
		ShipSecurityEvent(r.Context(), "KYC_BLOCKED", "user-service", req.TenantID, req.TenantID, fmt.Sprintf("attempted to deposit, KYC status is %s", kycStatus), getClientIP(r))
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
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use GET"})
		return
	}
	tenantID := r.URL.Query().Get("tenant_id")
	if tenantID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "tenant_id required"})
		return
	}
	resolvedTenantID, err := resolveToken(tenantID)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid tenant token: " + err.Error()})
		return
	}
	tenantID = resolvedTenantID
	entries := u.store.GetLedger(r.Context(), tenantID)
	writeJSON(w, http.StatusOK, map[string]any{"count": len(entries), "entries": entries})
}

// GET /users/platform/config
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

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

func resolveToken(tokenStr string) (string, error) {
	claims, err := jwtutil.ValidateToken(tokenStr)
	if err != nil {
		return "", fmt.Errorf("invalid or missing token: %w", err)
	}
	return claims.UserID, nil
}

func writeJSON(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}

func generateID() string {
	b := make([]byte, 8)
	if _, err := rand.Read(b); err != nil {
		return fmt.Sprintf("fallback-%d", time.Now().UnixNano())
	}
	return hex.EncodeToString(b)
}

func parseFloat(s string, fallback float64) float64 {
	if s == "" {
		return fallback
	}
	v, err := strconv.ParseFloat(s, 64)
	if err != nil {
		return fallback
	}
	return v
}

func haversineKm(lat1, lon1, lat2, lon2 float64) float64 {
	const R = 6371.0
	dLat := (lat2 - lat1) * math.Pi / 180
	dLon := (lon2 - lon1) * math.Pi / 180
	a := math.Sin(dLat/2)*math.Sin(dLat/2) +
		math.Cos(lat1*math.Pi/180)*math.Cos(lat2*math.Pi/180)*
			math.Sin(dLon/2)*math.Sin(dLon/2)
	return R * 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))
}

func (u *UserService) checkKYC(ownerID string) (string, error) {
	url := fmt.Sprintf("%s/auth/user?id=%s", u.authServiceURL, ownerID)
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("X-Internal-Token", u.internalServiceToken)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		return "", fmt.Errorf("owner not found")
	}
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("unexpected auth service status: %d", resp.StatusCode)
	}

	var user struct {
		Role      string `json:"role"`
		KYCStatus string `json:"kyc_status"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&user); err != nil {
		return "", err
	}

	if user.Role != "owner" {
		return "", fmt.Errorf("specified user is not an owner")
	}

	return user.KYCStatus, nil
}

// requireTier enforces that a tenant has at least the minimum subscription tier.
func (u *UserService) requireTier(ctx context.Context, tenantID string, min models.PlanTier) error {
	sub := u.store.GetSubscription(ctx, tenantID)
	var currentTier models.PlanTier = models.PlanFree
	if sub != nil {
		currentTier = sub.Tier
	}

	if min == models.PlanPaid {
		if currentTier != models.PlanPaid {
			return ErrUpgradeRequired
		}
	}
	return nil
}

// ---------------------------------------------------------------------------
// GET /users/subscription?tenant_id=xxx
// POST /users/subscription
// ---------------------------------------------------------------------------

func (u *UserService) Subscription(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		tenantID := r.URL.Query().Get("tenant_id")
		if tenantID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "tenant_id required"})
			return
		}
		resolvedTenantID, err := resolveToken(tenantID)
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
			TenantID    string          `json:"tenant_id"`
			Tier        models.PlanTier `json:"tier"`
			RequesterID string          `json:"requester_id"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON: " + err.Error()})
			return
		}
		if req.TenantID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "tenant_id is required"})
			return
		}
		if req.RequesterID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "requester_id is required"})
			return
		}

		resolvedTenantID, err := resolveToken(req.TenantID)
		if err != nil {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid tenant token: " + err.Error()})
			return
		}
		req.TenantID = resolvedTenantID

		resolvedRequesterID, err := resolveToken(req.RequesterID)
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
		resp, err := http.DefaultClient.Do(authReq)
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "auth service connection error: " + err.Error()})
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
				ID:        fmt.Sprintf("sub-%d", time.Now().UnixNano()),
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
			ID:        fmt.Sprintf("sub-%d", time.Now().UnixNano()),
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

// ---------------------------------------------------------------------------
// POST /users/jobs/rate
// ---------------------------------------------------------------------------

func (u *UserService) RateJob(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use POST"})
		return
	}

	var req struct {
		JobID     string `json:"job_id"`
		RatedBy   string `json:"rated_by"`
		RatedUser string `json:"rated_user"`
		Stars     int    `json:"stars"`
		Comment   string `json:"comment"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON: " + err.Error()})
		return
	}

	if req.Stars < 1 || req.Stars > 5 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "stars must be between 1 and 5"})
		return
	}

	resolvedRatedBy, err := resolveToken(req.RatedBy)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid rated_by token: " + err.Error()})
		return
	}
	req.RatedBy = resolvedRatedBy

	resolvedRatedUser, err := resolveToken(req.RatedUser)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid rated_user token: " + err.Error()})
		return
	}
	req.RatedUser = resolvedRatedUser

	ctx := r.Context()
	job := u.store.GetJob(ctx, req.JobID)
	if job == nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "job not found"})
		return
	}

	isOwnerRating := req.RatedBy == job.OwnerID && req.RatedUser == job.EmployeeID
	isEmployeeRating := req.RatedBy == job.EmployeeID && req.RatedUser == job.OwnerID

	if !isOwnerRating && !isEmployeeRating {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "not authorized to rate this job/user"})
		return
	}

	if job.Status != models.JobStatusCompleted {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "cannot rate a job that is not completed"})
		return
	}

	rating := &models.Rating{
		ID:        fmt.Sprintf("rate-%d", time.Now().UnixNano()),
		JobID:     req.JobID,
		RatedBy:   req.RatedBy,
		RatedUser: req.RatedUser,
		Stars:     req.Stars,
		Comment:   req.Comment,
		CreatedAt: time.Now().UTC(),
	}

	if err := u.store.CreateRating(ctx, rating); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	writeJSON(w, http.StatusCreated, rating)
}

// ---------------------------------------------------------------------------
// GET /users/ratings?user_id=xxx
// ---------------------------------------------------------------------------

func (u *UserService) GetRatings(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use GET"})
		return
	}

	userID := r.URL.Query().Get("user_id")
	if userID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "user_id required"})
		return
	}

	resolvedUserID, err := resolveToken(userID)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid user token: " + err.Error()})
		return
	}
	userID = resolvedUserID

	ratings, err := u.store.GetRatingsForUser(r.Context(), userID)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	totalStars := 0
	for _, r := range ratings {
		totalStars += r.Stars
	}

	avg := 0.0
	if len(ratings) > 0 {
		avg = float64(totalStars) / float64(len(ratings))
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"user_id":        userID,
		"ratings":        ratings,
		"average_rating": avg,
		"count":          len(ratings),
	})
}

// POST /users/jobs/location/update
// ---------------------------------------------------------------------------

func (u *UserService) UpdateJobLocation(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use POST"})
		return
	}

	var req struct {
		JobID       string  `json:"job_id"`
		RequesterID string  `json:"requester_id"`
		Latitude    float64 `json:"latitude"`
		Longitude   float64 `json:"longitude"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON: " + err.Error()})
		return
	}

	if req.JobID == "" || req.RequesterID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "job_id and requester_id are required"})
		return
	}

	resolvedRequester, err := resolveToken(req.RequesterID)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid requester token: " + err.Error()})
		return
	}

	ctx := r.Context()
	job := u.store.GetJob(ctx, req.JobID)
	if job == nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "job not found"})
		return
	}

	if job.EmployeeID == "" || resolvedRequester != job.EmployeeID {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "access denied: only the assigned employee can push location updates"})
		return
	}

	if job.Status != models.JobStatusActive {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "action blocked: job is not active"})
		return
	}

	// Membership tier gating
	if err := u.requireTier(ctx, job.OwnerID, models.PlanPaid); err != nil {
		if errors.Is(err, ErrUpgradeRequired) {
			ShipSecurityEvent(ctx, "UPGRADE_REQUIRED", "user-service", resolvedRequester, job.OwnerID, fmt.Sprintf("location update rejected for job %s, paid subscription required", job.ID), getClientIP(r))
			writeJSON(w, http.StatusPaymentRequired, map[string]string{
				"error":   "upgrade_required",
				"message": "Live location tracking requires a paid subscription.",
			})
			return
		}
		log.Printf("[USER] Subscription verification failed for owner %s: %v", job.OwnerID, err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{
			"error":   "internal_error",
			"message": "could not verify subscription status",
		})
		return
	}

	// Per-job minimum interval throttling
	u.locationThrottleMu.Lock()
	if u.locationInFlight[job.ID] {
		u.locationThrottleMu.Unlock()
		writeJSON(w, http.StatusTooManyRequests, map[string]string{
			"error":   "too_many_requests",
			"message": "Location update is already in progress for this job.",
		})
		return
	}

	lastUpdate, exists := u.locationLastUpdate[job.ID]
	now := time.Now()
	if exists && now.Sub(lastUpdate) < MinLocationUpdateInterval {
		u.locationThrottleMu.Unlock()
		writeJSON(w, http.StatusTooManyRequests, map[string]string{
			"error":   "too_many_requests",
			"message": fmt.Sprintf("Too many location updates. Minimum interval is %.0f seconds.", MinLocationUpdateInterval.Seconds()),
		})
		return
	}
	u.locationInFlight[job.ID] = true
	u.locationThrottleMu.Unlock()

	// Update in the store
	if err := u.store.UpdateJobLocation(ctx, req.JobID, req.Latitude, req.Longitude); err != nil {
		u.locationThrottleMu.Lock()
		delete(u.locationInFlight, job.ID)
		u.locationThrottleMu.Unlock()

		log.Printf("[USER] Failed to update location for job %s: %v", req.JobID, err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{
			"error":   "internal_error",
			"message": "failed to update location",
		})
		return
	}

	// Commit the real timestamp and release the reservation
	u.locationThrottleMu.Lock()
	u.locationLastUpdate[job.ID] = time.Now()
	delete(u.locationInFlight, job.ID)
	u.locationThrottleMu.Unlock()

	// Call chat-service to broadcast
	go func() {
		payload := map[string]any{
			"channel":     "job:" + job.ID,
			"latitude":    req.Latitude,
			"longitude":   req.Longitude,
			"employee_id": job.EmployeeID,
		}
		bodyBytes, err := json.Marshal(payload)
		if err != nil {
			log.Printf("[USER] Location broadcast error (marshal): %v", err)
			return
		}

		broadcastURL := fmt.Sprintf("%s/chat/internal/broadcast-location", u.chatServiceURL)
		broadcastReq, err := http.NewRequest("POST", broadcastURL, bytes.NewReader(bodyBytes))
		if err != nil {
			log.Printf("[USER] Location broadcast error (request build): %v", err)
			return
		}
		broadcastReq.Header.Set("Content-Type", "application/json")
		broadcastReq.Header.Set("X-Internal-Token", u.internalServiceToken)

		resp, err := http.DefaultClient.Do(broadcastReq)
		if err != nil {
			log.Printf("[USER] Location broadcast error (call chat-service): %v", err)
			return
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			log.Printf("[USER] Location broadcast failed with status %d", resp.StatusCode)
		}
	}()

	writeJSON(w, http.StatusOK, map[string]string{"status": "success", "message": "location updated"})
}
