package handlers

import (
	"bytes"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"

	"github.com/project/shared/infra/handlerutil"
	"github.com/project/user-service/internal/models"
)

// ---------------------------------------------------------------------------
// GET /users/jobs/reconciliation-queue
// ---------------------------------------------------------------------------

func (u *UserService) GetReconciliationQueue(w http.ResponseWriter, r *http.Request) {
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
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "owner token required"})
		return
	}

	resolvedOwnerID, err := resolveTokenWithRole(requesterToken, "owner")
	if err != nil {
		if strings.Contains(err.Error(), "role mismatch") {
			writeJSON(w, http.StatusForbidden, map[string]string{"error": "access denied: owner role required"})
			return
		}
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid requester token: " + err.Error()})
		return
	}

	// Enforce IDOR matching if client explicitly provided an owner_id parameter
	clientOwnerID := r.URL.Query().Get("owner_id")
	if clientOwnerID != "" && clientOwnerID != resolvedOwnerID {
		// #nosec G706 //nolint:gosec -- IDs are sanitized from claims/query, log injection not possible
		log.Printf("[IDOR DETECTED] Requester %s tried to query reconciliation queue for %s", resolvedOwnerID, strings.ReplaceAll(strings.ReplaceAll(clientOwnerID, "\n", " "), "\r", " "))
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "access denied: you are not authorized to view jobs for this owner"})
		return
	}

	// Identity-based rate limiting (30 req/min)
	rateKey := "jobs_reconciliation_queue:" + resolvedOwnerID
	if limited, remaining := u.reconciliationLimiter.CheckAndRecord(rateKey); limited {
		writeJSON(w, http.StatusTooManyRequests, map[string]string{
			"error": fmt.Sprintf("too many requests, locked out for %.0f seconds", remaining.Seconds()),
		})
		return
	}

	jobs, err := u.store.GetReconciliationQueueByOwner(r.Context(), resolvedOwnerID)
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
// POST /users/jobs/reconciliation-resolve
// ---------------------------------------------------------------------------

type ResolveReconciliationRequest struct {
	JobID          string `json:"job_id"`
	RequesterID    string `json:"requester_id"`
	RequesterToken string `json:"requester_token"`
	Decision       string `json:"decision"` // "release_to_employee" or "refund_to_customer"
}

func (u *UserService) ResolveReconciliation(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use POST"})
		return
	}

	var req ResolveReconciliationRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON: " + err.Error()})
		return
	}

	if req.JobID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "job_id is required"})
		return
	}

	if req.Decision != "release_to_employee" && req.Decision != "refund_to_customer" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid decision: must be 'release_to_employee' or 'refund_to_customer'"})
		return
	}

	// Resolve requester token
	requesterToken := r.Header.Get("Authorization")
	if strings.HasPrefix(requesterToken, "Bearer ") {
		requesterToken = strings.TrimPrefix(requesterToken, "Bearer ")
	}
	if requesterToken == "" {
		requesterToken = req.RequesterToken
	}
	if requesterToken == "" {
		requesterToken = req.RequesterID
	}
	if requesterToken == "" {
		requesterToken = r.URL.Query().Get("requester_token")
	}
	if requesterToken == "" {
		requesterToken = r.URL.Query().Get("owner_token")
	}
	if requesterToken == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "owner token required"})
		return
	}

	resolvedOwnerID, err := resolveTokenWithRole(requesterToken, "owner")
	if err != nil {
		if strings.Contains(err.Error(), "role mismatch") {
			writeJSON(w, http.StatusForbidden, map[string]string{"error": "access denied: owner role required"})
			return
		}
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid requester token: " + err.Error()})
		return
	}

	if u.resolveReconLimiter != nil {
		if limited, remaining := u.resolveReconLimiter.CheckAndRecord(resolvedOwnerID); limited {
			writeJSON(w, http.StatusTooManyRequests, map[string]string{"error": fmt.Sprintf("too many requests; retry in %.0f seconds", remaining.Seconds())})
			return
		}
	}

	ctx := r.Context()
	job := u.store.GetJob(ctx, req.JobID)
	if job == nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "job not found"})
		return
	}

	// Tenant isolation check
	if job.OwnerID != resolvedOwnerID {
		// #nosec G706 //nolint:gosec -- IDs are sanitized from claims/DB, log injection not possible
		log.Printf("[TENANT SCOPE BLOCKED] Requester %s attempted to resolve reconciliation for job %s owned by %s", resolvedOwnerID, job.ID, job.OwnerID)
		handlerutil.ShipSecurityEvent(ctx, "TENANT_SCOPE_BLOCKED", "user-service", resolvedOwnerID, job.OwnerID, fmt.Sprintf("attempted to resolve reconciliation for job %s", job.ID), handlerutil.GetClientIP(r))
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "access denied: you are not authorized to resolve reconciliation for this job"})
		return
	}

	// Idempotency check: job must be in escrow_reconciliation_required status
	if job.Status != models.JobStatusEscrowReconciliationRequired {
		writeJSON(w, http.StatusConflict, map[string]string{"error": "job is not pending escrow reconciliation review"})
		return
	}

	amount := job.LockedEscrowAmount

	switch req.Decision {
	case "release_to_employee":
		if job.PaymentMethod == "cod" {
			if err := u.store.CompleteCODJob(ctx, job.ID, 0); err != nil && !strings.Contains(err.Error(), "not active") {
				log.Printf("[ERROR] Failed to complete COD job on reconciliation release for job %s: %v", job.ID, err)
			}
		} else if amount > 0 {
			if err := u.store.ReleaseEscrowWithSplit(ctx, job.OwnerID, job.ID, amount); err != nil {
				writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "escrow release failed: " + err.Error()})
				return
			}
		}

		note := fmt.Sprintf("reconciliation_resolved: release_to_employee by owner %s", resolvedOwnerID)
		if err := u.store.UpdateJobReconciliation(ctx, job.ID, models.JobStatusCompleted, note, "", amount); err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to update job reconciliation status: " + err.Error()})
			return
		}

		handlerutil.ShipSecurityEvent(ctx, "ESCROW_RECONCILIATION_RESOLVED", "user-service", resolvedOwnerID, job.OwnerID, fmt.Sprintf("resolved escrow reconciliation for job %s: decision=release_to_employee, amount=%.2f", job.ID, amount), handlerutil.GetClientIP(r))

		writeJSON(w, http.StatusOK, map[string]any{
			"message":             "escrow reconciliation resolved: funds released to employee/tenant",
			"job_id":              job.ID,
			"status":              models.JobStatusCompleted,
			"decision":            "release_to_employee",
			"reconciliation_note": note,
		})

	case "refund_to_customer":
		if job.PaymentMethod != "cod" && amount > 0 {
			if err := u.store.RefundEscrow(ctx, job.OwnerID, job.ID, amount); err != nil {
				writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "escrow refund failed: " + err.Error()})
				return
			}
		}

		note := fmt.Sprintf("reconciliation_resolved: refund_to_customer by owner %s", resolvedOwnerID)
		if err := u.store.UpdateJobReconciliation(ctx, job.ID, models.JobStatusCancelled, note, "", 0); err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to update job reconciliation status: " + err.Error()})
			return
		}

		handlerutil.ShipSecurityEvent(ctx, "ESCROW_RECONCILIATION_RESOLVED", "user-service", resolvedOwnerID, job.OwnerID, fmt.Sprintf("resolved escrow reconciliation for job %s: decision=refund_to_customer, amount=%.2f", job.ID, amount), handlerutil.GetClientIP(r))

		writeJSON(w, http.StatusOK, map[string]any{
			"message":             "escrow reconciliation resolved: funds refunded to customer",
			"job_id":              job.ID,
			"status":              models.JobStatusCancelled,
			"decision":            "refund_to_customer",
			"reconciliation_note": note,
		})
	}
}

// ---------------------------------------------------------------------------
// Ops Console Admin Reconciliation Endpoints (ADR-0023)
// ---------------------------------------------------------------------------

type ReviewerIdentity struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

func (u *UserService) authenticateReviewer(r *http.Request) (*ReviewerIdentity, error) {
	// 1. Verify X-Internal-Token header
	internalToken := r.Header.Get("X-Internal-Token")
	if u.internalServiceToken == "" || subtle.ConstantTimeCompare([]byte(internalToken), []byte(u.internalServiceToken)) != 1 {
		return nil, errors.New("unauthorized internal token")
	}

	// 2. Verify X-Reviewer-Token header
	reviewerToken := r.Header.Get("X-Reviewer-Token")
	if reviewerToken == "" {
		return nil, errors.New("missing reviewer token")
	}

	// 3. Call auth-service GET /auth/reviewer/verify
	authURL := u.authServiceURL
	if authURL == "" {
		authURL = "http://localhost:3002"
	}
	reqURL := fmt.Sprintf("%s/auth/reviewer/verify", strings.TrimSuffix(authURL, "/"))
	// #nosec G704 //nolint:gosec -- reqURL is constructed from trusted internal config (AUTH_SERVICE_URL)
	req, err := http.NewRequestWithContext(r.Context(), http.MethodGet, reqURL, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create reviewer auth request: %w", err)
	}
	req.Header.Set("X-Internal-Token", u.internalServiceToken)
	req.Header.Set("X-Reviewer-Token", reviewerToken)

	var resp *http.Response
	if u.authClient != nil {
		resp, err = u.authClient.Do(req)
	} else {
		resp, err = http.DefaultClient.Do(req)
	}
	if err != nil {
		return nil, fmt.Errorf("failed to reach auth service: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, errors.New("invalid reviewer credentials")
	}

	var identity ReviewerIdentity
	if err := json.NewDecoder(resp.Body).Decode(&identity); err != nil {
		return nil, fmt.Errorf("failed to decode reviewer identity: %w", err)
	}
	if identity.ID == "" {
		return nil, errors.New("empty reviewer id returned")
	}

	return &identity, nil
}

// AdminGetReconciliationQueue returns all jobs in status escrow_reconciliation_required globally across all tenants.
// GET /users/admin/reconciliation/queue & GET /admin/reconciliation/queue
func (u *UserService) AdminGetReconciliationQueue(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}

	reviewer, err := u.authenticateReviewer(r)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": err.Error()})
		return
	}

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
	jobs, total, err := u.store.GetGlobalReconciliationQueue(ctx, page, limit)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	items := make([]models.AdminReconciliationJobItem, 0, len(jobs))
	for _, j := range jobs {
		var actualCash float64
		if j.ActualCashAmount != nil {
			actualCash = *j.ActualCashAmount
		}

		var actualDist float64
		if len(j.Waypoints) > 0 {
			pts := make([]models.Location, 0, len(j.Waypoints)+1)
			pts = append(pts, j.Location)
			pts = append(pts, j.Waypoints...)
			for i := 0; i < len(pts)-1; i++ {
				actualDist += haversineKm(pts[i+1].Latitude, pts[i+1].Longitude, pts[i].Latitude, pts[i].Longitude)
			}
		}

		items = append(items, models.AdminReconciliationJobItem{
			ID:                   j.ID,
			TenantID:             j.OwnerID,
			OwnerID:              j.OwnerID,
			EmployeeID:           j.EmployeeID,
			CustomerID:           j.UserID,
			ServiceID:            j.ServiceID,
			BookedDistance:       j.BookedDistance,
			ActualDistance:       actualDist,
			WaypointsCount:       len(j.Waypoints),
			LockedEscrowAmount:   j.LockedEscrowAmount,
			ActualAmount:         actualCash,
			PaymentMethod:        j.PaymentMethod,
			Status:               j.Status,
			ReconciliationNote:   j.ReconciliationNote,
			ReconciliationReason: j.EscrowFailureReason,
			CreatedAt:            j.CreatedAt,
			UpdatedAt:            j.UpdatedAt,
		})
	}

	handlerutil.ShipSecurityEvent(ctx, "ADMIN_RECONCILIATION_QUEUE_LISTED", "user-service", reviewer.ID, "", fmt.Sprintf("listed %d disputes page=%d limit=%d total=%d", len(items), page, limit, total), handlerutil.GetClientIP(r))

	writeJSON(w, http.StatusOK, models.AdminReconciliationQueueResponse{
		Disputes: items,
		Total:    int(total),
		Page:     int(page),
		Limit:    int(limit),
	})
}

// AdminResolveReconciliation resolves a disputed job globally via ops reviewer override with mandatory reason.
// POST /users/admin/reconciliation/resolve & POST /admin/reconciliation/resolve
func (u *UserService) AdminResolveReconciliation(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}

	reviewer, err := u.authenticateReviewer(r)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": err.Error()})
		return
	}

	var req models.AdminResolveReconciliationRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON: " + err.Error()})
		return
	}

	if strings.TrimSpace(req.JobID) == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "job_id is required"})
		return
	}

	if req.Decision != "release_to_employee" && req.Decision != "refund_to_customer" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid decision: must be 'release_to_employee' or 'refund_to_customer'"})
		return
	}

	reason := strings.TrimSpace(req.Reason)
	if len(reason) < 1 || len(reason) > 1000 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "reason is required (1-1000 characters)"})
		return
	}

	ctx := r.Context()
	updatedJob, err := u.store.AdminResolveReconciliation(ctx, req.JobID, req.Decision, reason, reviewer.ID)
	if err != nil {
		if strings.Contains(err.Error(), "not found") {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": err.Error()})
			return
		}
		if strings.Contains(err.Error(), "no longer pending") || strings.Contains(err.Error(), "not pending escrow reconciliation") {
			writeJSON(w, http.StatusConflict, map[string]string{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	handlerutil.ShipSecurityEvent(ctx, "ADMIN_ESCROW_RECONCILIATION_RESOLVED", "user-service", reviewer.ID, updatedJob.OwnerID, fmt.Sprintf("resolved dispute for job %s: decision=%s, reason=%s", updatedJob.ID, req.Decision, reason), handlerutil.GetClientIP(r))

	go u.dispatchDisputeResolvedNotification(updatedJob, req.Decision, reason)

	writeJSON(w, http.StatusOK, map[string]any{
		"message":             "dispute resolved successfully",
		"job_id":              updatedJob.ID,
		"status":              updatedJob.Status,
		"decision":            req.Decision,
		"reconciliation_note": updatedJob.ReconciliationNote,
	})
}

func (u *UserService) dispatchDisputeResolvedNotification(job *models.Job, decision, reason string) {
	if job == nil {
		return
	}
	defer func() {
		if r := recover(); r != nil {
			// #nosec G706 //nolint:gosec -- log format string does not interpolate untrusted user inputs
			log.Printf("[USER] Recovered from panic in dispatchDisputeResolvedNotification for job %s: %v", job.ID, r)
		}
	}()

	notificationURL := u.notificationServiceURL
	if notificationURL == "" {
		notificationURL = "http://notification-service:3004"
	}
	url := fmt.Sprintf("%s/notifications/send", strings.TrimSuffix(notificationURL, "/"))

	var customerMsg, courierMsg string
	if decision == "release_to_employee" {
		customerMsg = fmt.Sprintf("Dispute for job %s has been reviewed and resolved. Funds released to service provider.", job.ID)
		courierMsg = fmt.Sprintf("Dispute for job %s has been reviewed and resolved. Funds released to your wallet/tenant.", job.ID)
	} else {
		customerMsg = fmt.Sprintf("Dispute for job %s has been reviewed and resolved. Escrow funds refunded to your wallet.", job.ID)
		courierMsg = fmt.Sprintf("Dispute for job %s has been reviewed and resolved. Escrow refunded to customer.", job.ID)
	}

	targets := []struct {
		userID string
		msg    string
	}{
		{userID: job.UserID, msg: customerMsg},
		{userID: job.OwnerID, msg: courierMsg},
	}
	if job.EmployeeID != "" && job.EmployeeID != job.OwnerID {
		targets = append(targets, struct {
			userID string
			msg    string
		}{userID: job.EmployeeID, msg: courierMsg})
	}

	for _, target := range targets {
		if target.userID == "" {
			continue
		}
		payload := map[string]any{
			"tenant_id": job.OwnerID,
			"user_id":   target.userID,
			"type":      "dispute_resolved",
			"title":     "Dispute Resolution Update",
			"body":      target.msg,
			"job_id":    job.ID,
		}
		data, err := json.Marshal(payload)
		if err != nil {
			continue
		}

		// #nosec G704 //nolint:gosec -- notificationURL is trusted internal config
		req, err := http.NewRequest(http.MethodPost, url, bytes.NewBuffer(data))
		if err != nil {
			continue
		}
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("X-Internal-Token", u.internalServiceToken)

		if u.notificationClient != nil {
			resp, err := u.notificationClient.Do(req)
			if err == nil {
				_ = resp.Body.Close()
			}
		}
	}
}
