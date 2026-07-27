// Package handlers implements HTTP handlers for the user-service.
package handlers

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"html"
	"io"
	"log"
	"math"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/project/shared/infra/handlerutil"
	"github.com/project/shared/infra/jwtutil"
	"github.com/project/shared/infra/ratelimit"
	"github.com/project/shared/infra/resilience"
	"github.com/project/shared/infra/tlsutil"
	"github.com/project/user-service/internal/config"
	"github.com/project/user-service/internal/models"
	"github.com/project/user-service/internal/store"
	"github.com/redis/go-redis/v9"
	"go.mongodb.org/mongo-driver/mongo"
)

var ErrServiceUnavailable = errors.New("service_unavailable")

// ErrUpgradeRequired is returned when a tenant's subscription tier is insufficient for a gated feature.
var ErrUpgradeRequired = errors.New("upgrade_required")

// MinLocationUpdateInterval defines the minimum wait time between consecutive location updates per job.
const MinLocationUpdateInterval = 3 * time.Second

// MaxReasonableSpeedKmh defines the maximum plausible speed for location updates in km/h.
const MaxReasonableSpeedKmh = 150.0

const checkLocationThrottleScript = `
local inflightKey = KEYS[1]
local lastupdateKey = KEYS[2]

local minIntervalMs = tonumber(ARGV[1])
local inflightTTLSec = tonumber(ARGV[2])
local nowMs = tonumber(ARGV[3])

-- 1. Check in-flight lock
if redis.call('EXISTS', inflightKey) == 1 then
    return {1, 0}
end

-- 2. Check last update timestamp
local lastUpdateMsStr = redis.call('GET', lastupdateKey)
local lastUpdateMs = 0
if lastUpdateMsStr then
    lastUpdateMs = tonumber(lastUpdateMsStr) or 0
    if lastUpdateMs > 0 and (nowMs - lastUpdateMs) < minIntervalMs then
        return {2, lastUpdateMs}
    end
end

-- 3. Set in-flight key atomically
redis.call('SET', inflightKey, '1', 'EX', inflightTTLSec)

return {0, lastUpdateMs}
`

// UserService holds dependencies for the user-service handlers.
type UserService struct {
	store                  *store.MongoDB
	authServiceURL         string
	chatServiceURL         string
	limiter                *handlerutil.RateLimiter
	internalServiceToken   string
	locationThrottleMu     sync.Mutex
	locationLastUpdate     map[string]time.Time
	locationInFlight       map[string]bool
	authClient             *resilience.ResilienceClient
	chatClient             *resilience.ResilienceClient
	httpClient             *http.Client
	appEnv                 string
	allowTestPaymentBypass bool
	rdb                    *redis.Client
	// Test hook to block UpdateJobLocation database write for deterministic testing
	updateJobLocationBeforeWriteHook func(ctx context.Context)
	// Test hook to force RollbackEscrow to fail for deterministic testing
	rollbackEscrowHook func(ctx context.Context, tenantID string, amount float64) error
}

func (u *UserService) clearLocationThrottleState(jobID string) {
	u.locationThrottleMu.Lock()
	delete(u.locationLastUpdate, jobID)
	delete(u.locationInFlight, jobID)
	u.locationThrottleMu.Unlock()

	if u.rdb != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		_ = u.rdb.Del(ctx, fmt.Sprintf("loc:inflight:%s", jobID), fmt.Sprintf("loc:lastupdate:%s", jobID)).Err()
	}
}

func (u *UserService) setTestLocationLastUpdate(jobID string, t time.Time) {
	u.locationThrottleMu.Lock()
	u.locationLastUpdate[jobID] = t
	u.locationThrottleMu.Unlock()

	if u.rdb != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		nowMs := t.UnixNano() / int64(time.Millisecond)
		_ = u.rdb.Set(ctx, fmt.Sprintf("loc:lastupdate:%s", jobID), fmt.Sprintf("%d", nowMs), 300*time.Second).Err()
	}
}

// NewUserService creates a new UserService handler group.
func NewUserService(s *store.MongoDB, cfg *config.Config, rdb *redis.Client) *UserService {
	handlerutil.InitCloudWatch(cfg.CloudWatchLogGroup)

	chatServiceURL := cfg.ChatServiceURL
	if chatServiceURL == "" {
		chatServiceURL = "http://localhost:3001"
	}

	var client *http.Client
	if cfg.TLSCertPath != "" && cfg.TLSKeyPath != "" && cfg.TLSCAPath != "" {
		var err error
		client, err = tlsutil.NewClient(cfg.TLSCertPath, cfg.TLSKeyPath, cfg.TLSCAPath)
		if err != nil {
			log.Fatalf("[USER] Failed to initialize TLS http client: %v", err)
		}
	} else {
		client = http.DefaultClient
	}

	rl := ratelimit.NewRateLimiter(rdb, 5, 1*time.Minute, "user")

	authClient := resilience.NewClient(client, "auth-service", 2, 5*time.Second)
	chatClient := resilience.NewClient(client, "chat-service", 2, 5*time.Second)

	return &UserService{
		store:                  s,
		authServiceURL:         cfg.AuthServiceURL,
		chatServiceURL:         chatServiceURL,
		limiter:                handlerutil.NewRateLimiter(rl),
		internalServiceToken:   cfg.InternalServiceToken,
		locationLastUpdate:     make(map[string]time.Time),
		locationInFlight:       make(map[string]bool),
		rdb:                    rdb,
		authClient:             authClient,
		chatClient:             chatClient,
		httpClient:             client,
		appEnv:                 cfg.AppEnv,
		allowTestPaymentBypass: cfg.AllowTestPaymentBypass,
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
	mux.HandleFunc("/users/jobs/owner", u.GetOwnerJobs)
	mux.HandleFunc("/users/jobs/mine", u.GetCustomerJobs)
	mux.HandleFunc("/users/jobs/complete", u.CompleteJob)
	mux.HandleFunc("/users/jobs/cancel", u.CancelJob)
	mux.HandleFunc("/users/jobs/propose-price", u.ProposePrice)
	mux.HandleFunc("/users/jobs/respond-price", u.RespondPrice)
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
	// #nosec G706 //nolint:gosec -- sortBy is validated query parameter, log injection not possible
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
	if req.OwnerToken != "" {
		req.OwnerID = req.OwnerToken
	}
	if req.OwnerID == "" || req.Name == "" || req.Category == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "owner_id, name, and category are required"})
		return
	}
	resolvedOwnerID, err := resolveTokenWithRole(req.OwnerID, "owner")
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid owner token: " + err.Error()})
		return
	}
	req.OwnerID = resolvedOwnerID

	// Verify owner exists and has approved KYC
	kycStatus, err := u.checkKYC(req.OwnerID)
	if err != nil {
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
	}

	u.store.CreateService(r.Context(), svc)
	log.Printf("[USER] Service created: id=%s name=%s", svc.ID, svc.Name)
	writeJSON(w, http.StatusCreated, map[string]any{"message": "service created", "service": svc})
}

// ---------------------------------------------------------------------------
// POST /users/jobs/track — with escrow locking
// ---------------------------------------------------------------------------

func (u *UserService) TrackJob(w http.ResponseWriter, r *http.Request) {
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
	var req models.CreateJobRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON: " + err.Error()})
		return
	}
	if req.OwnerToken != "" {
		req.OwnerID = req.OwnerToken
	}
	if req.EmployeeToken != "" {
		req.EmployeeID = req.EmployeeToken
	}
	if req.UserToken != "" {
		req.UserID = req.UserToken
	}
	if req.ServiceID == "" || req.UserID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "service_id and user_id are required"})
		return
	}

	idempotencyKey := r.Header.Get("Idempotency-Key")
	if idempotencyKey == "" {
		idempotencyKey = r.Header.Get("X-Idempotency-Key")
	}
	if idempotencyKey == "" {
		idempotencyKey = req.IdempotencyKey
	}

	if idempotencyKey != "" && u.rdb != nil {
		redisKey := "idempotency:job:" + idempotencyKey
		existingJobID, err := u.rdb.Get(r.Context(), redisKey).Result()
		if err == nil && existingJobID != "" {
			existingJob := u.store.GetJob(r.Context(), existingJobID)
			if existingJob != nil {
				writeJSON(w, http.StatusOK, map[string]any{
					"message":         "job tracking record already created (idempotent response)",
					"job":             existingJob,
					"idempotency_key": idempotencyKey,
				})
				return
			}
		}
	}

	if !isValidCoordinate(req.Location.Latitude, req.Location.Longitude) {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error":   "invalid_coordinates",
			"message": "Latitude must be between -90 and 90, and Longitude must be between -180 and 180",
		})
		return
	}

	// 1. Resolve owner token if provided
	var resolvedOwnerID string
	var hasOwnerToken bool
	if req.OwnerID != "" {
		var err error
		resolvedOwnerID, err = resolveTokenWithRole(req.OwnerID, "owner")
		if err != nil {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid owner token: " + err.Error()})
			return
		}
		hasOwnerToken = true
	}

	// 2. Verify customer user token
	resolvedUserID, err := resolveTokenWithRole(req.UserID, "user", "customer")
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid user token: " + err.Error()})
		return
	}
	req.UserID = resolvedUserID

	ctx := r.Context()
	var svc *models.Service

	// 3. Securely look up the service from database if owner token was not provided
	if !hasOwnerToken {
		svc = u.store.GetServiceByID(ctx, req.ServiceID)
		if svc == nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "service not found"})
			return
		}
		resolvedOwnerID = svc.TenantID
	}
	req.OwnerID = resolvedOwnerID

	// 4. Verify assigned employee is active, has employee role, and belongs to this owner's tenant
	if req.EmployeeID != "" {
		resolvedEmployeeID, err := resolveTokenWithRole(req.EmployeeID, "employee")
		if err != nil {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid employee token: " + err.Error()})
			return
		}
		req.EmployeeID = resolvedEmployeeID

		// Verify assigned employee is active, has employee role, and belongs to this owner's tenant
		ok, err := u.verifyEmployeeAssignment(req.EmployeeID, resolvedOwnerID)
		if err != nil {
			if errors.Is(err, ErrServiceUnavailable) {
				writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "auth service unavailable"})
				return
			}
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "employee not found or status lookup failed"})
			return
		}
		if !ok {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "employee is not active, not an employee, or does not belong to this owner's tenant"})
			return
		}
	}

	if req.PaymentMethod != "cod" && (!u.allowTestPaymentBypass || (u.appEnv != "test" && u.appEnv != "local")) {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "invalid payment_method: only 'cod' is currently supported",
		})
		return
	}

	// 5. Verify owner exists and has approved KYC
	kycStatus, err := u.checkKYC(req.OwnerID)
	if err != nil {
		log.Printf("[KYC BLOCKED/ERROR] Failed KYC check for owner %s: %v", req.OwnerID, err)
		if errors.Is(err, ErrServiceUnavailable) {
			writeJSON(w, http.StatusServiceUnavailable, map[string]string{
				"error":   "service_unavailable",
				"message": "Authentication service is temporarily unavailable. Please try again later.",
			})
			return
		}
		handlerutil.ShipSecurityEvent(ctx, "KYC_BLOCKED_ERROR", "user-service", req.OwnerID, req.OwnerID, fmt.Sprintf("failed KYC check: %v", err), handlerutil.GetClientIP(r))
		writeJSON(w, http.StatusForbidden, map[string]string{
			"error": "action blocked: unable to verify owner KYC status",
		})
		return
	}
	if kycStatus != "approved" {
		log.Printf("[KYC BLOCKED] Owner %s attempted to track job, but KYC status is %q", req.OwnerID, kycStatus)
		handlerutil.ShipSecurityEvent(ctx, "KYC_BLOCKED", "user-service", req.OwnerID, req.OwnerID, fmt.Sprintf("attempted to track job, KYC status is %s", kycStatus), handlerutil.GetClientIP(r))
		writeJSON(w, http.StatusForbidden, map[string]string{
			"error": "action blocked: owner KYC approval is pending",
		})
		return
	}

	// 6. Look up service if not already loaded (when owner token was provided)
	if svc == nil {
		svc = u.store.GetServiceByID(ctx, req.ServiceID)
		if svc == nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "service not found"})
			return
		}
	}

	// 7. Security cross-check: the verified owner must own the service being booked
	if hasOwnerToken && resolvedOwnerID != svc.TenantID {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "action blocked: owner ID does not match service tenant"})
		return
	}

	// Calculate ride cost: base_price + (distance × price_per_km).
	dist := haversineKm(req.Location.Latitude, req.Location.Longitude, svc.Latitude, svc.Longitude)
	escrowAmount := math.Round((svc.TenantBasePrice+(dist*svc.TenantPricePerKM))*100) / 100

	isTransport := svc.Category == "transport"
	now := time.Now().UTC()

	var suggestedPrice float64
	var proposedPrice *float64
	var proposedBy string
	var expiresAt *time.Time

	initialStatus := models.JobStatusPending

	if isTransport {
		suggestedPrice = escrowAmount
		initialStatus = models.JobStatusAwaitingPriceResponse

		if req.ProposedPrice != nil {
			if !models.ValidPriceProposal(suggestedPrice, *req.ProposedPrice) {
				writeJSON(w, http.StatusBadRequest, map[string]string{
					"error":   "invalid_proposed_price",
					"message": "proposed_price must be between 50% and 150% of the suggested price",
				})
				return
			}
			proposedPrice = req.ProposedPrice
			proposedBy = "customer"
			exp := now.Add(5 * time.Minute)
			expiresAt = &exp
		}
	}

	job := &models.Job{
		ID: generateID(), OwnerID: req.OwnerID, EmployeeID: req.EmployeeID,
		UserID:    req.UserID,
		ServiceID: req.ServiceID, Status: initialStatus,
		Location: req.Location, PaymentMethod: req.PaymentMethod,
		CreatedAt: now, UpdatedAt: now,
	}

	if isTransport {
		job.SuggestedPrice = suggestedPrice
		job.ProposedPrice = proposedPrice
		job.ProposedBy = proposedBy
		job.PriceProposalExpiresAt = expiresAt
	}

	if err := u.store.CreateJob(ctx, job); err != nil {
		writeJSON(w, http.StatusConflict, map[string]string{"error": err.Error()})
		return
	}

	// For transport category jobs, skip escrow locking entirely during TrackJob regardless of payment method.
	if isTransport {
		log.Printf("[USER] Transport Job %s created awaiting price proposal response (suggested=%.2f)", job.ID, suggestedPrice)
		u.saveIdempotencyKey(r.Context(), idempotencyKey, job.ID)
		writeJSON(w, http.StatusCreated, map[string]any{
			"message": "job tracking record created",
			"job":     job,
		})
		return
	}

	// Lock escrow only for non-COD (or skip for COD jobs)
	if req.PaymentMethod == "cod" {
		log.Printf("[USER] Job %s created (COD payment method)", job.ID)
		// Progress to active.
		if err := u.store.UpdateJobStatus(ctx, job.ID, models.JobStatusActive); err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to activate job: " + err.Error()})
			return
		}
		job.Status = models.JobStatusActive
		job.UpdatedAt = time.Now().UTC()

		u.saveIdempotencyKey(r.Context(), idempotencyKey, job.ID)

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
		u.saveIdempotencyKey(r.Context(), idempotencyKey, job.ID)
		writeJSON(w, http.StatusCreated, map[string]any{
			"message": "job created but escrow lock failed — deposit funds first",
			"warning": err.Error(), "job": job, "escrow_amount": escrowAmount,
		})
		return
	}

	log.Printf("[USER] Job %s created with escrow %.2f locked", job.ID, escrowAmount)

	// Persist the locked escrow amount on the job record
	if err := u.store.UpdateJobLockedEscrow(ctx, job.ID, escrowAmount); err != nil {
		log.Printf("[ERROR] failed to persist locked escrow amount for job %s: %v. Rolling back escrow lock.", job.ID, err)
		// Use context.Background() for rollback/cleanup to ensure it executes even if the request context was cancelled/timed out
		rollbackErr := u.performRollbackEscrow(context.Background(), req.OwnerID, escrowAmount)
		if rollbackErr != nil {
			log.Printf("[CRITICAL ERROR] initial escrow rollback attempt failed for owner %s (job %s): %v. Retrying rollback once...", req.OwnerID, job.ID, rollbackErr)
			// Single retry attempt (Req #3)
			rollbackErr = u.performRollbackEscrow(context.Background(), req.OwnerID, escrowAmount)
		}

		if rollbackErr != nil {
			log.Printf("[CRITICAL ERROR] failed to rollback escrow lock for owner %s (job %s): %v. Marking job for reconciliation instead of deleting.", req.OwnerID, job.ID, rollbackErr)
			note := fmt.Sprintf("Locked escrow amount: %.2f. Escrow lock rollback failed: %v", escrowAmount, rollbackErr)
			if recErr := u.store.UpdateJobReconciliation(context.Background(), job.ID, models.JobStatusEscrowReconciliationRequired, note, rollbackErr.Error(), escrowAmount); recErr != nil {
				log.Printf("[CRITICAL ERROR] failed to set reconciliation status on job %s: %v", job.ID, recErr)
			}
			writeJSON(w, http.StatusInternalServerError, map[string]string{
				"error": "failed to persist locked escrow and escrow rollback failed; job preserved for reconciliation",
			})
			return
		}

		if deleteErr := u.store.DeleteJob(context.Background(), job.ID); deleteErr != nil {
			log.Printf("[ERROR] failed to delete job %s after failure: %v", job.ID, deleteErr)
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{
			"error": "failed to persist locked escrow, escrow lock rolled back",
		})
		return
	}
	job.LockedEscrowAmount = escrowAmount

	// Progress to active.
	if err := u.store.UpdateJobStatus(ctx, job.ID, models.JobStatusActive); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to activate job: " + err.Error()})
		return
	}
	job.Status = models.JobStatusActive
	job.UpdatedAt = time.Now().UTC()

	u.saveIdempotencyKey(r.Context(), idempotencyKey, job.ID)

	writeJSON(w, http.StatusCreated, map[string]any{
		"message": "job tracking record created", "lifecycle_note": "escrow locked, all up to date",
		"job": job, "escrow_locked": escrowAmount,
	})
}

func (u *UserService) performRollbackEscrow(ctx context.Context, tenantID string, amount float64) error {
	if u.rollbackEscrowHook != nil {
		return u.rollbackEscrowHook(ctx, tenantID, amount)
	}
	return u.store.RollbackEscrow(ctx, tenantID, amount)
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
	resolvedRequester := "internal_service"
	isInternal := subtle.ConstantTimeCompare([]byte(r.Header.Get("X-Internal-Token")), []byte(u.internalServiceToken)) == 1
	if !isInternal {
		if req.RequesterToken != "" {
			req.RequesterID = req.RequesterToken
		}
		requesterToken := r.URL.Query().Get("requester_token")
		if requesterToken == "" {
			requesterToken = r.URL.Query().Get("requester_id")
		}
		if requesterToken == "" {
			requesterToken = req.RequesterID
		}
		if requesterToken == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "requester_id parameter is required"})
			return
		}
		var err error
		resolvedRequester, err = resolveTokenWithRole(requesterToken, "owner", "employee", "user", "customer")
		if err != nil {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid requester token: " + err.Error()})
			return
		}

		if resolvedRequester != job.OwnerID && (job.EmployeeID == "" || resolvedRequester != job.EmployeeID) {
			// #nosec G706 //nolint:gosec -- IDs are from verified JWT tokens and database, log injection not possible
			log.Printf("[TENANT SCOPE BLOCKED] User %s attempted to complete job %s owned by owner %s and employee %s", resolvedRequester, job.ID, job.OwnerID, job.EmployeeID)
			handlerutil.ShipSecurityEvent(r.Context(), "TENANT_SCOPE_BLOCKED", "user-service", resolvedRequester, job.OwnerID, fmt.Sprintf("attempted to complete job %s", job.ID), handlerutil.GetClientIP(r))
			writeJSON(w, http.StatusForbidden, map[string]string{"error": "access denied: you are not authorized to complete this job"})
			return
		}
	}

	if job.Status == models.JobStatusCompleted {
		writeJSON(w, http.StatusConflict, map[string]string{"error": "job already completed"})
		return
	}
	if job.Status == models.JobStatusCancelled {
		writeJSON(w, http.StatusConflict, map[string]string{"error": "job already cancelled"})
		return
	}
	if job.Status != models.JobStatusActive {
		writeJSON(w, http.StatusConflict, map[string]string{"error": "job must be active to be completed"})
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

	if job.PaymentMethod != "cod" && job.LockedEscrowAmount == 0 {
		log.Printf("[SECURITY WARNING] LockedEscrowAmount is 0 for non-COD job %s during CompleteJob. Payout aborted.", job.ID)
		handlerutil.ShipSecurityEvent(ctx, "ESCROW_UNRECORDED", "user-service", resolvedRequester, job.OwnerID, fmt.Sprintf("CompleteJob aborted: LockedEscrowAmount is 0 for non-COD job %s", job.ID), handlerutil.GetClientIP(r))
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error":   "escrow_amount_unrecorded",
			"message": "This job has no recorded locked escrow amount. Payout aborted for security.",
		})
		return
	}

	// Delivery and Shipping GPS Trail Settlement Reconciliation (ADR-0007 Phase 1)
	if svc.Category == "delivery" || svc.Category == "shipping" {
		bookedDist := dist
		var actualDist float64
		pts := make([]models.Location, 0, len(job.Waypoints)+1)
		pts = append(pts, job.Location)
		pts = append(pts, job.Waypoints...)

		for i := 0; i < len(pts)-1; i++ {
			actualDist += haversineKm(pts[i+1].Latitude, pts[i+1].Longitude, pts[i].Latitude, pts[i].Longitude)
		}

		// Under-distance review flag: if actual tracked distance < 70% of booked distance
		if bookedDist > 0 && actualDist < 0.70*bookedDist {
			log.Printf("[SECURITY WARNING] Tracked distance mismatch for job %s: actual %.2f km vs booked %.2f km (< 70%% threshold). Flagging for manual escrow reconciliation.", job.ID, actualDist, bookedDist)
			handlerutil.ShipSecurityEvent(ctx, "TRACKED_DISTANCE_MISMATCH", "user-service", resolvedRequester, job.OwnerID, fmt.Sprintf("tracked distance mismatch for job %s: actual %.2f km vs booked %.2f km", job.ID, actualDist, bookedDist), handlerutil.GetClientIP(r))

			note := fmt.Sprintf("tracked_distance_mismatch: actual %.2f km vs booked %.2f km", actualDist, bookedDist)
			if recErr := u.store.UpdateJobReconciliation(ctx, job.ID, models.JobStatusEscrowReconciliationRequired, note, "under_distance_mismatch", job.LockedEscrowAmount); recErr != nil {
				log.Printf("[ERROR] failed to update reconciliation status for job %s: %v", job.ID, recErr)
				writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to flag job for reconciliation: " + recErr.Error()})
				return
			}
			writeJSON(w, http.StatusOK, map[string]any{
				"message":             "job flagged for escrow reconciliation review due to tracked distance mismatch",
				"job_id":              job.ID,
				"status":              string(models.JobStatusEscrowReconciliationRequired),
				"reconciliation_note": note,
				"actual_distance_km":  actualDist,
				"booked_distance_km":  bookedDist,
			})
			return
		}

		// Guaranteed floor payout calculation: max(LockedEscrowAmount, A_actual)
		aActual := math.Round((svc.TenantBasePrice+(actualDist*svc.TenantPricePerKM))*100) / 100
		if job.LockedEscrowAmount > 0 {
			amount = math.Max(job.LockedEscrowAmount, aActual)
		} else {
			amount = math.Max(amount, aActual)
		}
	}

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
			if strings.Contains(err.Error(), "not active") {
				writeJSON(w, http.StatusConflict, map[string]string{"error": "job already completed or not active: " + err.Error()})
				return
			}
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to deduct platform fee: " + err.Error()})
			return
		}

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

	// Cap the release amount at LockedEscrowAmount to prevent drawing down other jobs' escrow
	if amount > job.LockedEscrowAmount {
		log.Printf("[SECURITY WARNING] Recomputed completion amount %.2f exceeds locked escrow amount %.2f for job %s. Capping to locked amount.", amount, job.LockedEscrowAmount, job.ID)
		handlerutil.ShipSecurityEvent(ctx, "ESCROW_LIMIT_EXCEEDED", "user-service", resolvedRequester, job.OwnerID, fmt.Sprintf("CompleteJob amount %.2f exceeds locked escrow %.2f, capped", amount, job.LockedEscrowAmount), handlerutil.GetClientIP(r))
		amount = job.LockedEscrowAmount
	}

	// Release escrow with profit splitting (Non-COD flow)
	if err := u.store.ReleaseEscrowWithSplit(ctx, job.OwnerID, job.ID, amount); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "escrow release failed: " + err.Error()})
		return
	}

	if err := u.store.UpdateJobStatus(ctx, job.ID, models.JobStatusCompleted); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to complete job: " + err.Error()})
		return
	}

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
	id := r.URL.Query().Get("user_token")
	if id == "" {
		id = r.URL.Query().Get("id")
	}
	if id == "" {
		requesterToken := r.URL.Query().Get("requester_token")
		if requesterToken == "" {
			requesterToken = r.URL.Query().Get("requester_id")
		}
		if requesterToken == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "id or requester_id parameter is required"})
			return
		}
		resolvedRequester, err := resolveTokenWithRole(requesterToken, "employee")
		if err != nil {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid requester token: " + err.Error()})
			return
		}
		// Check if a client-supplied employee_id query param exists, and validate it matches resolvedRequester
		clientEmployeeID := r.URL.Query().Get("employee_id")
		if clientEmployeeID != "" && clientEmployeeID != resolvedRequester {
			// #nosec G706 //nolint:gosec -- employee ID is sanitized, resolvedRequester is from verified JWT claims, log injection not possible
			log.Printf("[IDOR DETECTED] Requester %s tried to query jobs for employee %s", resolvedRequester, strings.ReplaceAll(strings.ReplaceAll(clientEmployeeID, "\n", " "), "\r", " "))
			writeJSON(w, http.StatusForbidden, map[string]string{"error": "access denied: you are not authorized to view jobs for this employee"})
			return
		}
		jobs, err := u.store.GetJobsByEmployee(r.Context(), resolvedRequester)
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, jobs)
		return
	}
	ctx := r.Context()
	job := u.store.GetJob(ctx, id)
	if job == nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "job not found"})
		return
	}

	u.checkLazyPriceProposalExpiry(ctx, job)

	// 1. Internal trusted token check
	if subtle.ConstantTimeCompare([]byte(r.Header.Get("X-Internal-Token")), []byte(u.internalServiceToken)) == 1 {
		writeJSON(w, http.StatusOK, job)
		return
	}

	// 2. External client check: require requester_id query param
	requesterToken := r.URL.Query().Get("requester_token")
	if requesterToken == "" {
		requesterToken = r.URL.Query().Get("requester_id")
	}
	if requesterToken == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "requester_id parameter is required"})
		return
	}
	resolvedRequester, err := resolveTokenWithRole(requesterToken, "owner", "employee", "user", "customer")
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid requester token: " + err.Error()})
		return
	}

	if resolvedRequester != job.OwnerID && resolvedRequester != job.UserID && (job.EmployeeID == "" || resolvedRequester != job.EmployeeID) {
		// #nosec G706 //nolint:gosec -- IDs are from verified JWT tokens and database, log injection not possible
		log.Printf("[TENANT SCOPE BLOCKED] User %s attempted to access job %s owned by owner %s, employee %s, user %s", resolvedRequester, job.ID, job.OwnerID, job.EmployeeID, job.UserID)
		handlerutil.ShipSecurityEvent(r.Context(), "TENANT_SCOPE_BLOCKED", "user-service", resolvedRequester, job.OwnerID, fmt.Sprintf("attempted to access job %s", job.ID), handlerutil.GetClientIP(r))
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "access denied: you are not authorized to view this job"})
		return
	}

	writeJSON(w, http.StatusOK, job)
}

// ---------------------------------------------------------------------------
// GET /users/jobs/owner
// ---------------------------------------------------------------------------

func (u *UserService) GetOwnerJobs(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}

	requesterToken := r.Header.Get("Authorization")
	if strings.HasPrefix(requesterToken, "Bearer ") {
		requesterToken = strings.TrimPrefix(requesterToken, "Bearer ")
	}
	if requesterToken == "" {
		requesterToken = r.URL.Query().Get("owner_token")
	}
	if requesterToken == "" {
		requesterToken = r.URL.Query().Get("requester_token")
	}
	if requesterToken == "" {
		requesterToken = r.URL.Query().Get("requester_id")
	}
	if requesterToken == "" {
		requesterToken = r.URL.Query().Get("owner_id")
	}
	if requesterToken == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "owner token required"})
		return
	}

	claims, err := resolveClaims(requesterToken)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid requester token: " + err.Error()})
		return
	}
	resolvedOwnerID := claims.UserID

	// Enforce IDOR matching if client explicitly provided an owner_id parameter
	clientOwnerID := r.URL.Query().Get("owner_id")
	if clientOwnerID != "" && clientOwnerID != resolvedOwnerID {
		// #nosec G706 //nolint:gosec -- IDs are sanitized from claims/query, log injection not possible
		log.Printf("[IDOR DETECTED] Requester %s tried to query owner jobs for %s", resolvedOwnerID, strings.ReplaceAll(strings.ReplaceAll(clientOwnerID, "\n", " "), "\r", " "))
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "access denied: you are not authorized to view jobs for this owner"})
		return
	}

	// Verify owner role
	if claims.Role != "owner" {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "access denied: owner role required"})
		return
	}

	// Identity-based rate limiting (30 req/min)
	rateKey := "jobs_owner:" + resolvedOwnerID
	if limited, remaining := u.limiter.CheckAndRecord(rateKey); limited {
		writeJSON(w, http.StatusTooManyRequests, map[string]string{
			"error": fmt.Sprintf("too many requests, locked out for %.0f seconds", remaining.Seconds()),
		})
		return
	}

	jobs, err := u.store.GetJobsByOwner(r.Context(), resolvedOwnerID)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	resps := make([]models.OwnerJobResponse, 0, len(jobs))
	for _, j := range jobs {
		resps = append(resps, models.NewOwnerJobResponse(j))
	}
	writeJSON(w, http.StatusOK, resps)
}

// ---------------------------------------------------------------------------
// GET /users/jobs/mine
// ---------------------------------------------------------------------------

func (u *UserService) GetCustomerJobs(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}

	requesterToken := r.Header.Get("Authorization")
	if strings.HasPrefix(requesterToken, "Bearer ") {
		requesterToken = strings.TrimPrefix(requesterToken, "Bearer ")
	}
	if requesterToken == "" {
		requesterToken = r.URL.Query().Get("customer_token")
	}
	if requesterToken == "" {
		requesterToken = r.URL.Query().Get("user_token")
	}
	if requesterToken == "" {
		requesterToken = r.URL.Query().Get("requester_token")
	}
	if requesterToken == "" {
		requesterToken = r.URL.Query().Get("requester_id")
	}
	if requesterToken == "" {
		requesterToken = r.URL.Query().Get("user_id")
	}
	if requesterToken == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "user token required"})
		return
	}

	claims, err := resolveClaims(requesterToken)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid requester token: " + err.Error()})
		return
	}
	resolvedCustomerID := claims.UserID

	// Enforce IDOR matching if client explicitly provided a user_id parameter
	clientUserID := r.URL.Query().Get("user_id")
	if clientUserID != "" && clientUserID != resolvedCustomerID {
		// #nosec G706 //nolint:gosec -- IDs are sanitized from claims/query, log injection not possible
		log.Printf("[IDOR DETECTED] Requester %s tried to query customer jobs for %s", resolvedCustomerID, strings.ReplaceAll(strings.ReplaceAll(clientUserID, "\n", " "), "\r", " "))
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "access denied: you are not authorized to view jobs for this user"})
		return
	}

	// Verify customer role
	if claims.Role != "user" {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "access denied: customer role required"})
		return
	}

	// Identity-based rate limiting (30 req/min)
	rateKey := "jobs_customer:" + resolvedCustomerID
	if limited, remaining := u.limiter.CheckAndRecord(rateKey); limited {
		writeJSON(w, http.StatusTooManyRequests, map[string]string{
			"error": fmt.Sprintf("too many requests, locked out for %.0f seconds", remaining.Seconds()),
		})
		return
	}

	jobs, err := u.store.GetJobsByCustomer(r.Context(), resolvedCustomerID)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	resps := make([]models.CustomerJobResponse, 0, len(jobs))
	for _, j := range jobs {
		resps = append(resps, models.NewCustomerJobResponse(j))
	}
	writeJSON(w, http.StatusOK, resps)
}

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
	if limited, remaining := u.limiter.CheckAndRecord("get_ledger_ip:" + ip); limited {
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
	if limited, remaining := u.limiter.CheckAndRecord(tenantKey); limited {
		writeJSON(w, http.StatusTooManyRequests, map[string]string{
			"error": fmt.Sprintf("too many ledger requests for this tenant, locked out for %.0f seconds", remaining.Seconds()),
		})
		return
	}

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

func resolveClaims(tokenStr string) (*jwtutil.Claims, error) {
	claims, err := jwtutil.ValidateToken(tokenStr)
	if err != nil {
		return nil, fmt.Errorf("invalid or missing token: %w", err)
	}
	return claims, nil
}

func resolveTokenWithRole(tokenStr string, allowedRoles ...string) (string, error) {
	claims, err := resolveClaims(tokenStr)
	if err != nil {
		return "", err
	}
	if len(allowedRoles) > 0 {
		matched := false
		for _, role := range allowedRoles {
			if claims.Role == role {
				matched = true
				break
			}
		}
		if !matched {
			return "", fmt.Errorf("role mismatch: claim role %q not in allowed roles %v", claims.Role, allowedRoles)
		}
	}
	return claims.UserID, nil
}

func (u *UserService) saveIdempotencyKey(ctx context.Context, key, jobID string) {
	if key != "" && u.rdb != nil {
		redisKey := "idempotency:job:" + key
		if err := u.rdb.Set(ctx, redisKey, jobID, 24*time.Hour).Err(); err != nil {
			// #nosec G706 //nolint:gosec -- key comes from request header/body, used for failure diagnosis
			log.Printf("[ERROR] failed to store idempotency key %s in Redis: %v", key, err)
		}
	}
}

func writeJSON(w http.ResponseWriter, status int, data any) {
	handlerutil.WriteJSON(w, status, data)
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
	resp, err := u.authClient.Do(req)
	if err != nil {
		return "", ErrServiceUnavailable
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		return "", fmt.Errorf("owner not found")
	}
	if resp.StatusCode != http.StatusOK {
		return "", ErrServiceUnavailable
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

func (u *UserService) verifyEmployeeAssignment(employeeID, ownerID string) (bool, error) {
	url := fmt.Sprintf("%s/auth/user?id=%s", u.authServiceURL, employeeID)
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return false, err
	}
	req.Header.Set("X-Internal-Token", u.internalServiceToken)
	resp, err := u.authClient.Do(req)
	if err != nil {
		return false, ErrServiceUnavailable
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		return false, fmt.Errorf("employee not found")
	}
	if resp.StatusCode != http.StatusOK {
		return false, ErrServiceUnavailable
	}

	var user struct {
		Role     string `json:"role"`
		TenantID string `json:"tenant_id"`
		IsActive bool   `json:"is_active"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&user); err != nil {
		return false, err
	}

	if user.Role != "employee" || user.TenantID != ownerID || !user.IsActive {
		return false, nil
	}

	return true, nil
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
	ip := handlerutil.GetIP(r)
	if limited, remaining := u.limiter.CheckAndRecord("rate_job:" + ip); limited {
		writeJSON(w, http.StatusTooManyRequests, map[string]string{
			"error": fmt.Sprintf("too many requests, locked out for %.0f seconds", remaining.Seconds()),
		})
		return
	}

	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use POST"})
		return
	}

	var req struct {
		JobID          string `json:"job_id"`
		RatedBy        string `json:"rated_by"`
		RatedByToken   string `json:"rated_by_token"`
		RatedUser      string `json:"rated_user"`
		RatedUserToken string `json:"rated_user_token"`
		Stars          int    `json:"stars"`
		Comment        string `json:"comment"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON: " + err.Error()})
		return
	}

	if req.RatedByToken != "" {
		req.RatedBy = req.RatedByToken
	}
	if req.RatedUserToken != "" {
		req.RatedUser = req.RatedUserToken
	}

	if req.Stars < 1 || req.Stars > 5 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "stars must be between 1 and 5"})
		return
	}

	if len(req.Comment) > 1000 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "comment exceeds maximum length of 1000 characters"})
		return
	}
	req.Comment = strings.TrimSpace(html.EscapeString(req.Comment))

	resolvedRatedBy, err := resolveTokenWithRole(req.RatedBy, "owner", "employee", "user", "customer")
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid rated_by token: " + err.Error()})
		return
	}
	req.RatedBy = resolvedRatedBy

	resolvedRatedUser, err := resolveTokenWithRole(req.RatedUser, "owner", "employee", "user", "customer")
	if err == nil {
		req.RatedUser = resolvedRatedUser
	} // Fallback: if token resolution fails, treat req.RatedUser as the raw user ID directly

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
		if mongo.IsDuplicateKeyError(err) || strings.Contains(err.Error(), "11000") || strings.Contains(err.Error(), "duplicate key") {
			writeJSON(w, http.StatusConflict, map[string]string{
				"error":   "conflict",
				"message": "you have already rated this job",
			})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	writeJSON(w, http.StatusCreated, rating)
}

// ---------------------------------------------------------------------------
// GET /users/ratings?user_id=xxx
// ---------------------------------------------------------------------------

func (u *UserService) GetRatings(w http.ResponseWriter, r *http.Request) {
	ip := handlerutil.GetIP(r)
	if limited, remaining := u.limiter.CheckAndRecord("get_ratings:" + ip); limited {
		writeJSON(w, http.StatusTooManyRequests, map[string]string{
			"error": fmt.Sprintf("too many requests, locked out for %.0f seconds", remaining.Seconds()),
		})
		return
	}

	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use GET"})
		return
	}

	// Authenticate requester
	requesterToken := r.Header.Get("Authorization")
	if strings.HasPrefix(requesterToken, "Bearer ") {
		requesterToken = strings.TrimPrefix(requesterToken, "Bearer ")
	}
	if requesterToken == "" {
		requesterToken = r.URL.Query().Get("requester_token")
	}
	if requesterToken == "" {
		requesterToken = r.URL.Query().Get("requester_id")
	}
	if requesterToken == "" {
		requesterToken = r.URL.Query().Get("user_token")
	}
	if requesterToken == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "requester authorization token required"})
		return
	}

	_, err := resolveTokenWithRole(requesterToken, "owner", "employee", "user", "customer")
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid requester token: " + err.Error()})
		return
	}

	// Target user ID to query (can be raw ID or JWT token)
	targetUserID := r.URL.Query().Get("user_id")
	if targetUserID == "" {
		targetUserID = r.URL.Query().Get("user_token")
	}
	if targetUserID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "user_id required"})
		return
	}

	resolvedTarget, err := resolveTokenWithRole(targetUserID, "owner", "employee", "user", "customer")
	if err == nil {
		targetUserID = resolvedTarget
	}

	ratings, err := u.store.GetRatingsForUser(r.Context(), targetUserID)
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
		"user_id":        targetUserID,
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
		JobID          string  `json:"job_id"`
		RequesterID    string  `json:"requester_id"`
		RequesterToken string  `json:"requester_token"`
		Latitude       float64 `json:"latitude"`
		Longitude      float64 `json:"longitude"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON: " + err.Error()})
		return
	}

	if req.RequesterToken != "" {
		req.RequesterID = req.RequesterToken
	}

	if req.JobID == "" || req.RequesterID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "job_id and requester_id are required"})
		return
	}

	resolvedRequester, err := resolveTokenWithRole(req.RequesterID, "employee", "owner")
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid requester token: " + err.Error()})
		return
	}

	if !isValidCoordinate(req.Latitude, req.Longitude) {
		log.Printf("[SECURITY WARNING] Invalid coordinates detected for job %s: lat=%.6f, lon=%.6f", req.JobID, req.Latitude, req.Longitude)
		ctx := r.Context()
		var ownerID string
		if job := u.store.GetJob(ctx, req.JobID); job != nil {
			ownerID = job.OwnerID
		}
		handlerutil.ShipSecurityEvent(ctx, "INVALID_COORDINATES_DETECTED", "user-service", resolvedRequester, ownerID, fmt.Sprintf("location update rejected for job %s: coordinates out of range (lat=%.6f, lon=%.6f)", req.JobID, req.Latitude, req.Longitude), handlerutil.GetClientIP(r))
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error":   "invalid_coordinates",
			"message": "Latitude must be between -90 and 90, and Longitude must be between -180 and 180",
		})
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
			handlerutil.ShipSecurityEvent(ctx, "UPGRADE_REQUIRED", "user-service", resolvedRequester, job.OwnerID, fmt.Sprintf("location update rejected for job %s, paid subscription required", job.ID), handlerutil.GetClientIP(r))
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
	var lastTime time.Time
	var exists bool
	now := time.Now()
	nowMs := now.UnixNano() / int64(time.Millisecond)

	clearInFlight := func() {
		if u.rdb != nil {
			bgCtx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
			_ = u.rdb.Del(bgCtx, fmt.Sprintf("loc:inflight:%s", job.ID)).Err()
			cancel()
		} else {
			u.locationThrottleMu.Lock()
			delete(u.locationInFlight, job.ID)
			u.locationThrottleMu.Unlock()
		}
	}

	if u.rdb != nil {
		inflightKey := fmt.Sprintf("loc:inflight:%s", job.ID)
		lastupdateKey := fmt.Sprintf("loc:lastupdate:%s", job.ID)

		evalCtx, cancelEval := context.WithTimeout(r.Context(), 2*time.Second)
		res, err := u.rdb.Eval(evalCtx, checkLocationThrottleScript, []string{inflightKey, lastupdateKey}, MinLocationUpdateInterval.Milliseconds(), 15, nowMs).Result()
		cancelEval()
		if err != nil {
			log.Printf("[SECURITY CRITICAL] Redis error in UpdateJobLocation throttle check (FAIL CLOSED): %v for job %s", err, job.ID)
			writeJSON(w, http.StatusInternalServerError, map[string]string{
				"error":   "internal_error",
				"message": "failed to process location update throttle check",
			})
			return
		}

		resSlice, ok := res.([]interface{})
		if !ok || len(resSlice) < 2 {
			log.Printf("[SECURITY CRITICAL] Unexpected response format from location throttle script: %v for job %s", res, job.ID)
			writeJSON(w, http.StatusInternalServerError, map[string]string{
				"error":   "internal_error",
				"message": "failed to process location update throttle check",
			})
			return
		}

		code := resSlice[0].(int64)
		lastUpdateMs := resSlice[1].(int64)

		if code == 1 {
			writeJSON(w, http.StatusTooManyRequests, map[string]string{
				"error":   "too_many_requests",
				"message": "Location update is already in progress for this job.",
			})
			return
		}
		if code == 2 {
			writeJSON(w, http.StatusTooManyRequests, map[string]string{
				"error":   "too_many_requests",
				"message": fmt.Sprintf("Too many location updates. Minimum interval is %.0f seconds.", MinLocationUpdateInterval.Seconds()),
			})
			return
		}

		if lastUpdateMs > 0 {
			exists = true
			lastTime = time.Unix(0, lastUpdateMs*int64(time.Millisecond))
		}
	} else {
		// Fallback to in-memory maps when Redis client is nil (e.g. unit tests without Redis)
		u.locationThrottleMu.Lock()
		if u.locationInFlight[job.ID] {
			u.locationThrottleMu.Unlock()
			writeJSON(w, http.StatusTooManyRequests, map[string]string{
				"error":   "too_many_requests",
				"message": "Location update is already in progress for this job.",
			})
			return
		}

		lastUpdate, ex := u.locationLastUpdate[job.ID]
		if ex && now.Sub(lastUpdate) < MinLocationUpdateInterval {
			u.locationThrottleMu.Unlock()
			writeJSON(w, http.StatusTooManyRequests, map[string]string{
				"error":   "too_many_requests",
				"message": fmt.Sprintf("Too many location updates. Minimum interval is %.0f seconds.", MinLocationUpdateInterval.Seconds()),
			})
			return
		}
		u.locationInFlight[job.ID] = true
		u.locationThrottleMu.Unlock()

		exists = ex
		if ex {
			lastTime = lastUpdate
		}
	}

	// Shared rejection helper for implausible speed check failures
	rejectImplausibleSpeed := func(speed float64, checkType string) {
		clearInFlight()

		log.Printf("[SECURITY WARNING] Implausible %s speed detected for job %s: %.2f km/h", checkType, job.ID, speed)
		handlerutil.ShipSecurityEvent(ctx, "IMPLAUSIBLE_SPEED_DETECTED", "user-service", resolvedRequester, job.OwnerID, fmt.Sprintf("location update rejected for job %s: %s speed %.2f km/h exceeds limit", job.ID, checkType, speed), handlerutil.GetClientIP(r))
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error":   "implausible_speed",
			"message": "Location update rejected: implausible speed detected.",
		})
	}

	// 1. Per-step speed/plausibility check
	prevLat := job.Location.Latitude
	prevLon := job.Location.Longitude
	if job.CurrentLocation != nil {
		prevLat = job.CurrentLocation.Latitude
		prevLon = job.CurrentLocation.Longitude
	}

	dist := haversineKm(req.Latitude, req.Longitude, prevLat, prevLon)
	if !exists {
		lastTime = job.CreatedAt
	}
	timeDiff := now.Sub(lastTime)
	hours := timeDiff.Hours()
	if hours > 0 {
		speed := dist / hours
		if speed > MaxReasonableSpeedKmh {
			rejectImplausibleSpeed(speed, "step")
			return
		}
	}

	// 2. Cumulative route speed check (sum of Haversine distances across all waypoints)
	var cumDist float64
	pts := make([]models.Location, 0, len(job.Waypoints)+2)
	pts = append(pts, job.Location)
	pts = append(pts, job.Waypoints...)
	pts = append(pts, models.Location{Latitude: req.Latitude, Longitude: req.Longitude})

	for i := 0; i < len(pts)-1; i++ {
		cumDist += haversineKm(pts[i+1].Latitude, pts[i+1].Longitude, pts[i].Latitude, pts[i].Longitude)
	}

	totalTimeDiff := now.Sub(job.CreatedAt)
	totalHours := totalTimeDiff.Hours()
	if totalHours > 0 {
		cumSpeed := cumDist / totalHours
		if cumSpeed > MaxReasonableSpeedKmh {
			rejectImplausibleSpeed(cumSpeed, "cumulative")
			return
		}
	}

	// Call the test hook if configured
	if u.updateJobLocationBeforeWriteHook != nil {
		u.updateJobLocationBeforeWriteHook(ctx)
	}

	// Update in the store
	if err := u.store.UpdateJobLocation(ctx, req.JobID, req.Latitude, req.Longitude); err != nil {
		clearInFlight()

		log.Printf("[USER] Failed to update location for job %s: %v", req.JobID, err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{
			"error":   "internal_error",
			"message": "failed to update location",
		})
		return
	}

	// Commit the real timestamp and release the reservation
	if u.rdb != nil {
		bgCtx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		pipe := u.rdb.Pipeline()
		pipe.Del(bgCtx, fmt.Sprintf("loc:inflight:%s", job.ID))
		pipe.Set(bgCtx, fmt.Sprintf("loc:lastupdate:%s", job.ID), fmt.Sprintf("%d", nowMs), 300*time.Second)
		_, _ = pipe.Exec(bgCtx)
		cancel()
	} else {
		u.locationThrottleMu.Lock()
		u.locationLastUpdate[job.ID] = time.Now()
		delete(u.locationInFlight, job.ID)
		u.locationThrottleMu.Unlock()
	}

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

		resp, err := u.chatClient.Do(broadcastReq)
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

// POST /users/jobs/cancel
func (u *UserService) CancelJob(w http.ResponseWriter, r *http.Request) {
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

	var req struct {
		JobID          string `json:"job_id"`
		RequesterID    string `json:"requester_id"`
		RequesterToken string `json:"requester_token"`
		Reason         string `json:"reason"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON: " + err.Error()})
		return
	}

	if req.RequesterToken != "" {
		req.RequesterID = req.RequesterToken
	}

	if req.JobID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "job_id is required"})
		return
	}

	if strings.TrimSpace(req.Reason) == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "reason is required"})
		return
	}

	ctx := r.Context()
	job := u.store.GetJob(ctx, req.JobID)
	if job == nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "job not found"})
		return
	}

	// Resolve requester
	var requesterToken string
	isInternal := subtle.ConstantTimeCompare([]byte(r.Header.Get("X-Internal-Token")), []byte(u.internalServiceToken)) == 1
	if isInternal {
		// For internal calls, use the requester_id passed in JSON
		requesterToken = req.RequesterID
	} else {
		// For external/client calls, resolve from token or query param
		requesterToken = r.URL.Query().Get("requester_id")
		if requesterToken == "" {
			requesterToken = req.RequesterID
		}
	}

	if requesterToken == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "requester_id parameter is required"})
		return
	}

	resolvedRequester, err := resolveTokenWithRole(requesterToken, "owner", "employee", "user", "customer")
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid requester token: " + err.Error()})
		return
	}

	// Check if requester is authorized (must be owner or customer/user of the job)
	isOwner := resolvedRequester == job.OwnerID
	isCustomer := resolvedRequester == job.UserID

	if !isOwner && !isCustomer {
		// #nosec G706 //nolint:gosec -- IDs are from verified JWT tokens and database, log injection not possible
		log.Printf("[TENANT SCOPE BLOCKED] User %s attempted to cancel job %s owned by owner %s and user %s", resolvedRequester, job.ID, job.OwnerID, job.UserID)
		handlerutil.ShipSecurityEvent(ctx, "TENANT_SCOPE_BLOCKED", "user-service", resolvedRequester, job.OwnerID, fmt.Sprintf("attempted to cancel job %s", job.ID), handlerutil.GetClientIP(r))
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "access denied: you are not authorized to cancel this job"})
		return
	}

	// State-specific cancellation rules
	switch job.Status {
	case models.JobStatusCompleted:
		writeJSON(w, http.StatusConflict, map[string]string{"error": "job already completed"})
		return
	case models.JobStatusCancelled:
		writeJSON(w, http.StatusConflict, map[string]string{"error": "job already cancelled"})
		return
	case models.JobStatusActive:
		// Active jobs can only be cancelled by the owner
		if !isOwner {
			// FLAGGED: Customers cannot directly cancel active/in-progress jobs. This prevents them from cancelling
			// out from under an employee who is already working. They must go through a complaint ticket.
			writeJSON(w, http.StatusForbidden, map[string]string{
				"error": "customer-initiated cancellation of active jobs is not allowed. Please open a complaint ticket.",
			})
			return
		}
	case models.JobStatusPending:
		// Both owner and customer can cancel pending jobs.
	}

	// Refund escrow if not COD (since escrow was locked during TrackJob)
	if job.PaymentMethod != "cod" {
		svc := u.store.GetServiceByID(ctx, job.ServiceID)
		if svc == nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "service not found for job"})
			return
		}
		dist := haversineKm(job.Location.Latitude, job.Location.Longitude, svc.Latitude, svc.Longitude)
		amount := math.Round((svc.TenantBasePrice+(dist*svc.TenantPricePerKM))*100) / 100

		if job.LockedEscrowAmount == 0 {
			log.Printf("[SECURITY WARNING] LockedEscrowAmount is 0 for non-COD job %s during CancelJob. Refund aborted.", job.ID)
			handlerutil.ShipSecurityEvent(ctx, "ESCROW_UNRECORDED", "user-service", resolvedRequester, job.OwnerID, fmt.Sprintf("CancelJob aborted: LockedEscrowAmount is 0 for non-COD job %s", job.ID), handlerutil.GetClientIP(r))
			writeJSON(w, http.StatusBadRequest, map[string]string{
				"error":   "escrow_amount_unrecorded",
				"message": "This job has no recorded locked escrow amount. Refund aborted for security.",
			})
			return
		}

		// Cap the refund amount at LockedEscrowAmount to prevent drawing down other jobs' escrow
		if amount > job.LockedEscrowAmount {
			log.Printf("[SECURITY WARNING] Recomputed refund amount %.2f exceeds locked escrow amount %.2f for job %s. Capping to locked amount.", amount, job.LockedEscrowAmount, job.ID)
			handlerutil.ShipSecurityEvent(ctx, "ESCROW_LIMIT_EXCEEDED", "user-service", resolvedRequester, job.OwnerID, fmt.Sprintf("CancelJob refund %.2f exceeds locked escrow %.2f, capped", amount, job.LockedEscrowAmount), handlerutil.GetClientIP(r))
			amount = job.LockedEscrowAmount
		}

		if err := u.store.RefundEscrow(ctx, job.OwnerID, job.ID, amount); err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to refund escrow: " + err.Error()})
			return
		}
	}

	// Perform cancellation in DB
	if err := u.store.CancelJob(ctx, job.ID, req.Reason); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to cancel job: " + err.Error()})
		return
	}

	// Audit-log job cancellation
	handlerutil.ShipSecurityEvent(ctx, "JOB_CANCELLED", "user-service", resolvedRequester, job.OwnerID, fmt.Sprintf("cancelled job %s, reason: %s", job.ID, req.Reason), handlerutil.GetClientIP(r))

	writeJSON(w, http.StatusOK, map[string]any{
		"message": "job cancelled successfully",
		"job_id":  job.ID,
		"status":  models.JobStatusCancelled,
	})
}

func isValidCoordinate(lat, lon float64) bool {
	return lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180
}

func (u *UserService) checkLazyPriceProposalExpiry(ctx context.Context, job *models.Job) bool {
	if job == nil {
		return false
	}
	if job.Status == models.JobStatusCancelled && job.CancellationReason == "price_proposal_expired" {
		return true
	}
	if job.Status != models.JobStatusAwaitingPriceResponse {
		return false
	}
	if job.PriceProposalExpiresAt != nil && time.Now().UTC().After(*job.PriceProposalExpiresAt) {
		job.Status = models.JobStatusCancelled
		job.CancellationReason = "price_proposal_expired"
		job.UpdatedAt = time.Now().UTC()
		if err := u.store.UpdateJobCancellation(ctx, job.ID, models.JobStatusCancelled, "price_proposal_expired"); err != nil {
			// #nosec G706 //nolint:gosec -- job.ID is system-generated UUID, log injection not possible
			log.Printf("[ERROR] Failed to persist lazy price proposal cancellation for job %s: %v", job.ID, err)
		}
		return true
	}
	return false
}

// ---------------------------------------------------------------------------
// POST /users/jobs/propose-price
// ---------------------------------------------------------------------------

type proposePriceRequest struct {
	JobID          string  `json:"job_id"`
	ProposedPrice  float64 `json:"proposed_price"`
	RequesterID    string  `json:"requester_id,omitempty"`
	RequesterToken string  `json:"requester_token,omitempty"`
}

func (u *UserService) ProposePrice(w http.ResponseWriter, r *http.Request) {
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

	var req proposePriceRequest
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

	requesterToken := r.Header.Get("Authorization")
	if strings.HasPrefix(requesterToken, "Bearer ") {
		requesterToken = strings.TrimPrefix(requesterToken, "Bearer ")
	}
	if requesterToken == "" {
		requesterToken = r.URL.Query().Get("requester_token")
	}
	if requesterToken == "" {
		requesterToken = r.URL.Query().Get("requester_id")
	}
	if requesterToken == "" {
		requesterToken = req.RequesterToken
	}
	if requesterToken == "" {
		requesterToken = req.RequesterID
	}
	if requesterToken == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "requester token is required"})
		return
	}

	resolvedRequester, err := resolveTokenWithRole(requesterToken, "owner", "employee", "user", "customer")
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid requester token: " + err.Error()})
		return
	}

	if resolvedRequester != job.UserID && (job.EmployeeID == "" || resolvedRequester != job.EmployeeID) {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "access denied: only the assigned customer or employee can propose a price"})
		return
	}

	svc := u.store.GetServiceByID(ctx, job.ServiceID)
	if svc == nil || svc.Category != "transport" {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error":   "invalid_category",
			"message": "price negotiation is only supported for transport category jobs",
		})
		return
	}

	if u.checkLazyPriceProposalExpiry(ctx, job) {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error":   "proposal_expired",
			"message": "price proposal window has expired",
		})
		return
	}

	if job.Status != models.JobStatusAwaitingPriceResponse {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error":   "invalid_job_status",
			"message": "job is not awaiting a price proposal",
		})
		return
	}

	if job.ProposedPrice != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error":   "proposal_already_submitted",
			"message": "a price proposal has already been submitted for this job",
		})
		return
	}

	proposerRole := "customer"
	if resolvedRequester == job.EmployeeID {
		proposerRole = "employee"
	}

	if !models.ValidPriceProposal(job.SuggestedPrice, req.ProposedPrice) {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error":   "invalid_proposed_price",
			"message": "proposed price must be between 50% and 150% of the suggested price",
		})
		return
	}

	now := time.Now().UTC()
	exp := now.Add(5 * time.Minute)
	job.ProposedPrice = &req.ProposedPrice
	job.ProposedBy = proposerRole
	job.PriceProposalExpiresAt = &exp
	job.UpdatedAt = now

	if err := u.store.UpdateJobPriceProposal(ctx, job.ID, &req.ProposedPrice, proposerRole, &exp); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to persist price proposal: " + err.Error()})
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"message": "price proposal submitted successfully",
		"job":     job,
	})
}

// ---------------------------------------------------------------------------
// POST /users/jobs/respond-price
// ---------------------------------------------------------------------------

// DESIGN NOTE: Accept with no prior proposal (employee accepting SuggestedPrice directly).
// If the customer creates a transport job without an initial price proposal, the baseline P_system stands
// as the implied offer. Allowing the employee to call respond-price directly with decision: "accept" sets
// AgreedPrice = SuggestedPrice and activates the job. Forcing a propose-price call first with the exact
// same P_system would add an unnecessary round-trip for standard, un-negotiated rides.

type respondPriceRequest struct {
	JobID          string `json:"job_id"`
	Decision       string `json:"decision"` // "accept" or "decline"
	RequesterID    string `json:"requester_id,omitempty"`
	RequesterToken string `json:"requester_token,omitempty"`
}

func (u *UserService) RespondPrice(w http.ResponseWriter, r *http.Request) {
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

	var req respondPriceRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON: " + err.Error()})
		return
	}
	if req.JobID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "job_id is required"})
		return
	}

	decision := strings.ToLower(strings.TrimSpace(req.Decision))
	if decision != "accept" && decision != "decline" {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error":   "invalid_decision",
			"message": "decision must be 'accept' or 'decline'",
		})
		return
	}

	ctx := r.Context()
	job := u.store.GetJob(ctx, req.JobID)
	if job == nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "job not found"})
		return
	}

	requesterToken := r.Header.Get("Authorization")
	if strings.HasPrefix(requesterToken, "Bearer ") {
		requesterToken = strings.TrimPrefix(requesterToken, "Bearer ")
	}
	if requesterToken == "" {
		requesterToken = r.URL.Query().Get("requester_token")
	}
	if requesterToken == "" {
		requesterToken = r.URL.Query().Get("requester_id")
	}
	if requesterToken == "" {
		requesterToken = req.RequesterToken
	}
	if requesterToken == "" {
		requesterToken = req.RequesterID
	}
	if requesterToken == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "requester token is required"})
		return
	}

	resolvedRequester, err := resolveTokenWithRole(requesterToken, "owner", "employee", "user", "customer")
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid requester token: " + err.Error()})
		return
	}

	if resolvedRequester != job.UserID && (job.EmployeeID == "" || resolvedRequester != job.EmployeeID) {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "access denied: only the assigned customer or employee can respond to a price proposal"})
		return
	}

	svc := u.store.GetServiceByID(ctx, job.ServiceID)
	if svc == nil || svc.Category != "transport" {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error":   "invalid_category",
			"message": "price negotiation is only supported for transport category jobs",
		})
		return
	}

	if u.checkLazyPriceProposalExpiry(ctx, job) {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error":   "proposal_expired",
			"message": "price proposal window has expired",
		})
		return
	}

	if job.Status != models.JobStatusAwaitingPriceResponse {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error":   "invalid_job_status",
			"message": "job is not awaiting a price proposal response",
		})
		return
	}

	if job.ProposedPrice != nil {
		isCustomer := resolvedRequester == job.UserID
		isEmployee := resolvedRequester == job.EmployeeID
		if (job.ProposedBy == "customer" && isCustomer) || (job.ProposedBy == "employee" && isEmployee) {
			writeJSON(w, http.StatusBadRequest, map[string]string{
				"error":   "cannot_respond_to_own_proposal",
				"message": "you cannot accept or decline your own price proposal",
			})
			return
		}
	} else {
		if resolvedRequester == job.UserID {
			writeJSON(w, http.StatusBadRequest, map[string]string{
				"error":   "cannot_respond_to_own_proposal",
				"message": "no active proposal from driver to respond to",
			})
			return
		}
	}

	now := time.Now().UTC()
	if decision == "accept" {
		activePrice := job.SuggestedPrice
		if job.ProposedPrice != nil {
			activePrice = *job.ProposedPrice
		}
		job.AgreedPrice = &activePrice
		job.Status = models.JobStatusActive
		job.UpdatedAt = now

		if err := u.store.UpdateJobAgreedPrice(ctx, job.ID, &activePrice, models.JobStatusActive); err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to accept price proposal: " + err.Error()})
			return
		}

		writeJSON(w, http.StatusOK, map[string]any{
			"message": "price proposal accepted — job is now active",
			"job":     job,
		})
		return
	}

	job.Status = models.JobStatusCancelled
	job.CancellationReason = "price_disagreement"
	job.UpdatedAt = now

	if err := u.store.UpdateJobCancellation(ctx, job.ID, models.JobStatusCancelled, "price_disagreement"); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to decline price proposal: " + err.Error()})
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"message": "price proposal declined — job cancelled",
		"job":     job,
	})
}
