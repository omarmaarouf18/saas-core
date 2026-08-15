package handlers

import (
	"bytes"
	"context"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"math"
	"net/http"
	"strings"
	"time"

	"github.com/project/shared/infra/handlerutil"
	"github.com/project/user-service/internal/models"
)

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

	if req.PaymentMethod != "cod" {
		if !u.electronicPaymentsEnabled && (!u.allowTestPaymentBypass || (u.appEnv != "test" && u.appEnv != "local")) {
			writeJSON(w, http.StatusBadRequest, map[string]string{
				"error": "electronic payments are not currently enabled; only COD (cash-on-delivery) is active",
			})
			return
		}
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

	u.broadcastJobAlert(job, svc)

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
	if job.AgreedPrice != nil && *job.AgreedPrice > 0 {
		amount = *job.AgreedPrice
	}

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

	// Handle COD payment method (pure collection logging per ADR-0017, zero wallet balance mutation)
	if job.PaymentMethod == "cod" {
		if !req.CashCollected {
			writeJSON(w, http.StatusBadRequest, map[string]string{
				"error": "action blocked: cash collection must be confirmed (cash_collected: true) for COD jobs",
			})
			return
		}

		if err := u.store.CompleteCODJob(ctx, job.ID); err != nil {
			if strings.Contains(err.Error(), "not active") {
				writeJSON(w, http.StatusConflict, map[string]string{"error": "job already completed or not active: " + err.Error()})
				return
			}
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to complete COD job: " + err.Error()})
			return
		}

		log.Printf("[USER] COD Job %s completed: cash_collected=%.2f logged (0%% platform commission)", job.ID, amount)
		writeJSON(w, http.StatusOK, map[string]any{
			"message":          "COD job completed and collection logged (0% platform commission)",
			"job_id":           job.ID,
			"total_amount":     amount,
			"platform_fee":     0.0,
			"platform_fee_pct": 0.0,
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

	// Identity-based rate limiting (60 req/min)
	rateKey := "jobs_owner:" + resolvedOwnerID
	if limited, remaining := u.ownerJobsLimiter.CheckAndRecord(rateKey); limited {
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

	activeOnly := r.URL.Query().Get("active_only") == "true" || r.URL.Query().Get("filter") == "active"
	resps := make([]models.OwnerJobResponse, 0, len(jobs))
	now := time.Now()
	for _, j := range jobs {
		if activeOnly {
			isActiveStatus := j.Status == models.JobStatusActive
			isRecentlyUpdated := !j.UpdatedAt.IsZero() && now.Sub(j.UpdatedAt) <= 15*time.Minute
			if !isActiveStatus && !isRecentlyUpdated {
				continue
			}
		}
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

	// Identity-based rate limiting (60 req/min)
	rateKey := "jobs_customer:" + resolvedCustomerID
	if limited, remaining := u.customerJobsLimiter.CheckAndRecord(rateKey); limited {
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

	// --- ATOMIC THROTTLE RESERVATION (ENTRY GUARD) ---
	now := time.Now()
	nowMs := now.UnixNano() / int64(time.Millisecond)

	clearInFlight := func() {
		if u.rdb != nil {
			bgCtx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
			_ = u.rdb.Del(bgCtx, fmt.Sprintf("loc:inflight:%s", req.JobID)).Err()
			cancel()
		} else {
			u.locationThrottleMu.Lock()
			delete(u.locationInFlight, req.JobID)
			u.locationThrottleMu.Unlock()
		}
	}

	var lastTime time.Time
	var exists bool

	if u.rdb != nil {
		inflightKey := fmt.Sprintf("loc:inflight:%s", req.JobID)
		lastupdateKey := fmt.Sprintf("loc:lastupdate:%s", req.JobID)

		evalCtx, cancelEval := context.WithTimeout(r.Context(), 2*time.Second)
		res, err := u.rdb.Eval(evalCtx, checkLocationThrottleScript, []string{inflightKey, lastupdateKey}, MinLocationUpdateInterval.Milliseconds(), 15, nowMs).Result()
		cancelEval()
		if err != nil {
			log.Printf("[SECURITY CRITICAL] Redis error in UpdateJobLocation throttle check (FAIL CLOSED): %v for job %s", err, req.JobID)
			writeJSON(w, http.StatusInternalServerError, map[string]string{
				"error":   "internal_error",
				"message": "failed to process location update throttle check",
			})
			return
		}

		resSlice, ok := res.([]interface{})
		if !ok || len(resSlice) < 2 {
			log.Printf("[SECURITY CRITICAL] Unexpected response format from location throttle script: %v for job %s", res, req.JobID)
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
		// Fallback to in-memory maps when Redis client is nil
		code, errMsg := u.tryReserveLocationThrottleInMemory(req.JobID, now)
		if code != 0 {
			writeJSON(w, http.StatusTooManyRequests, map[string]string{
				"error":   "too_many_requests",
				"message": errMsg,
			})
			return
		}

		u.locationThrottleMu.Lock()
		lastUpdate, ex := u.locationLastUpdate[req.JobID]
		exists = ex
		if ex {
			lastTime = lastUpdate
		}
		u.locationThrottleMu.Unlock()
	}

	resolvedRequester, err := resolveTokenWithRole(req.RequesterID, "employee", "owner")
	if err != nil {
		clearInFlight()
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid requester token: " + err.Error()})
		return
	}

	if !isValidCoordinate(req.Latitude, req.Longitude) {
		clearInFlight()
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
		clearInFlight()
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "job not found"})
		return
	}

	if job.EmployeeID == "" || resolvedRequester != job.EmployeeID {
		clearInFlight()
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "access denied: only the assigned employee can push location updates"})
		return
	}

	if job.Status != models.JobStatusActive {
		clearInFlight()
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "action blocked: job is not active"})
		return
	}

	// Membership tier gating
	if err := u.requireTier(ctx, job.OwnerID, models.PlanPaid); err != nil {
		clearInFlight()
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
	if hours > 0 && dist > 0.001 {
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
	if totalHours > 0 && cumDist > 0.001 {
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

	// Call chat-service to broadcast to BOTH job and fleet channels
	go func() {
		channels := []string{"job:" + job.ID}
		if job.OwnerID != "" {
			channels = append(channels, "fleet:"+job.OwnerID)
		}

		broadcastURL := fmt.Sprintf("%s/chat/internal/broadcast-location", u.chatServiceURL)
		for _, ch := range channels {
			payload := map[string]any{
				"channel":     ch,
				"latitude":    req.Latitude,
				"longitude":   req.Longitude,
				"employee_id": job.EmployeeID,
			}
			bodyBytes, err := json.Marshal(payload)
			if err != nil {
				log.Printf("[USER] Location broadcast error (marshal) for channel %s: %v", ch, err)
				continue
			}

			// #nosec G704 //nolint:gosec -- broadcastURL is constructed from internal service config
			broadcastReq, err := http.NewRequest("POST", broadcastURL, bytes.NewReader(bodyBytes))
			if err != nil {
				log.Printf("[USER] Location broadcast error (request build) for channel %s: %v", ch, err)
				continue
			}
			broadcastReq.Header.Set("Content-Type", "application/json")
			broadcastReq.Header.Set("X-Internal-Token", u.internalServiceToken)

			resp, err := u.chatClient.Do(broadcastReq)
			if err != nil {
				log.Printf("[USER] Location broadcast error (call chat-service) for channel %s: %v", ch, err)
				continue
			}
			_ = resp.Body.Close()

			if resp.StatusCode != http.StatusOK {
				log.Printf("[USER] Location broadcast failed for channel %s with status %d", ch, resp.StatusCode)
			}
		}
	}()

	writeJSON(w, http.StatusOK, map[string]string{"status": "success", "message": "location updated"})
}

func (u *UserService) broadcastJobAlert(job *models.Job, svc *models.Service) {
	if job == nil || job.EmployeeID == "" {
		return
	}

	go func() {
		defer func() {
			if r := recover(); r != nil {
				log.Printf("[USER] Recovered from panic in broadcastJobAlert: %v", r)
			}
		}()

		serviceName := "General Service"
		desc := fmt.Sprintf("Lat: %.4f, Lon: %.4f", job.Location.Latitude, job.Location.Longitude)
		if svc != nil {
			if svc.Name != "" {
				serviceName = svc.Name
			}
			if svc.Category != "" {
				desc = fmt.Sprintf("Category: %s (Lat: %.4f, Lon: %.4f)", svc.Category, job.Location.Latitude, job.Location.Longitude)
			}
		}

		payload := map[string]any{
			"tenant_id":    job.OwnerID,
			"job_id":       job.ID,
			"employee_id":  job.EmployeeID,
			"service_name": serviceName,
			"description":  desc,
		}

		bodyBytes, err := json.Marshal(payload)
		if err != nil {
			log.Printf("[USER] Job alert broadcast error (marshal) for job %s: %v", job.ID, err)
			return
		}

		broadcastURL := fmt.Sprintf("%s/notifications/broadcast/job-alert", u.notificationServiceURL)
		// #nosec G704 //nolint:gosec -- broadcastURL is constructed from internal service config
		req, err := http.NewRequest("POST", broadcastURL, bytes.NewReader(bodyBytes))
		if err != nil {
			log.Printf("[USER] Job alert broadcast error (request build) for job %s: %v", job.ID, err)
			return
		}

		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("X-Internal-Token", u.internalServiceToken)

		resp, err := u.notificationClient.Do(req)
		if err != nil {
			log.Printf("[USER] Job alert broadcast error (call notification-service) for job %s: %v", job.ID, err)
			return
		}
		_ = resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			log.Printf("[USER] Job alert broadcast failed for job %s with status %d", job.ID, resp.StatusCode)
		}
	}()
}

// ---------------------------------------------------------------------------
// POST /users/jobs/cancel
// ---------------------------------------------------------------------------

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
		if job.AgreedPrice != nil && *job.AgreedPrice > 0 {
			amount = *job.AgreedPrice
		}

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
		if strings.Contains(err.Error(), "not in a cancellable state") {
			writeJSON(w, http.StatusConflict, map[string]string{"error": err.Error()})
			return
		}
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

	// Early-exit check for non-racing callers. Note: The authoritative correctness guarantee
	// against concurrent double-proposals is enforced atomically by store.UpdateJobPriceProposal below,
	// whose CAS filter {_id, status, proposed_price: nil} ensures only one concurrent write succeeds.
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
		if strings.Contains(err.Error(), "job_state_changed") {
			writeJSON(w, http.StatusConflict, map[string]string{
				"error":   "job_state_changed",
				"message": "job status has changed or a price proposal has already been submitted",
			})
			return
		}
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

		// Lock escrow for non-COD negotiable transport jobs
		if job.PaymentMethod != "cod" {
			if err := u.store.LockEscrow(ctx, job.OwnerID, job.ID, activePrice); err != nil {
				log.Printf("[USER] Escrow lock failed for negotiable transport job %s: %v", job.ID, err)
				writeJSON(w, http.StatusBadRequest, map[string]any{
					"error":         "escrow_lock_failed",
					"message":       "price proposal acceptance failed — insufficient wallet funds for escrow lock",
					"warning":       err.Error(),
					"job":           job,
					"escrow_amount": activePrice,
				})
				return
			}

			// Persist the locked escrow amount on the job record
			if err := u.store.UpdateJobLockedEscrow(ctx, job.ID, activePrice); err != nil {
				log.Printf("[ERROR] failed to persist locked escrow amount for job %s: %v. Rolling back escrow lock.", job.ID, err)
				rollbackErr := u.performRollbackEscrow(context.Background(), job.OwnerID, activePrice)
				if rollbackErr != nil {
					log.Printf("[CRITICAL ERROR] initial escrow rollback attempt failed for owner %s (job %s): %v. Retrying rollback once...", job.OwnerID, job.ID, rollbackErr)
					rollbackErr = u.performRollbackEscrow(context.Background(), job.OwnerID, activePrice)
				}

				if rollbackErr != nil {
					log.Printf("[CRITICAL ERROR] failed to rollback escrow lock for owner %s (job %s): %v. Marking job for reconciliation instead of completing.", job.OwnerID, job.ID, rollbackErr)
					note := fmt.Sprintf("Locked escrow amount: %.2f. Escrow lock rollback failed: %v", activePrice, rollbackErr)
					if recErr := u.store.UpdateJobReconciliation(context.Background(), job.ID, models.JobStatusEscrowReconciliationRequired, note, rollbackErr.Error(), activePrice); recErr != nil {
						log.Printf("[CRITICAL ERROR] failed to set reconciliation status on job %s: %v", job.ID, recErr)
					}
					writeJSON(w, http.StatusInternalServerError, map[string]string{
						"error": "failed to persist locked escrow and escrow rollback failed; job preserved for reconciliation",
					})
					return
				}

				writeJSON(w, http.StatusInternalServerError, map[string]string{
					"error": "failed to persist locked escrow, escrow lock rolled back",
				})
				return
			}
			job.LockedEscrowAmount = activePrice
		}

		job.AgreedPrice = &activePrice
		job.Status = models.JobStatusActive
		job.UpdatedAt = now

		if u.updateJobAgreedPriceBeforeWriteHook != nil {
			u.updateJobAgreedPriceBeforeWriteHook(ctx)
		}

		if err := u.store.UpdateJobAgreedPrice(ctx, job.ID, &activePrice, models.JobStatusActive); err != nil {
			if strings.Contains(err.Error(), "job_state_changed") {
				if job.PaymentMethod != "cod" {
					log.Printf("[USER] Job state changed concurrently for job %s during RespondPrice accept. Rolling back escrow lock.", job.ID)
					rollbackErr := u.performRollbackEscrow(context.Background(), job.OwnerID, activePrice)
					if rollbackErr != nil {
						log.Printf("[CRITICAL ERROR] initial escrow rollback attempt failed on job_state_changed for owner %s (job %s): %v. Retrying rollback once...", job.OwnerID, job.ID, rollbackErr)
						rollbackErr = u.performRollbackEscrow(context.Background(), job.OwnerID, activePrice)
					}
					if rollbackErr != nil {
						log.Printf("[CRITICAL ERROR] failed to rollback escrow lock on job_state_changed for owner %s (job %s): %v. Marking job for reconciliation.", job.OwnerID, job.ID, rollbackErr)
						note := fmt.Sprintf("Job state changed concurrently during RespondPrice accept. Locked escrow amount: %.2f. Escrow lock rollback failed: %v", activePrice, rollbackErr)
						if recErr := u.store.UpdateJobReconciliation(context.Background(), job.ID, models.JobStatusEscrowReconciliationRequired, note, rollbackErr.Error(), activePrice); recErr != nil {
							log.Printf("[CRITICAL ERROR] failed to set reconciliation status on job %s: %v", job.ID, recErr)
						}
					}
				}
				writeJSON(w, http.StatusConflict, map[string]string{
					"error":   "job_state_changed",
					"message": "job status is no longer awaiting price response",
				})
				return
			}
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
		if strings.Contains(err.Error(), "job_state_changed") {
			writeJSON(w, http.StatusConflict, map[string]string{
				"error":   "job_state_changed",
				"message": "job status is no longer awaiting price response",
			})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to decline price proposal: " + err.Error()})
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"message": "price proposal declined — job cancelled",
		"job":     job,
	})
}
