package handlers

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
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
			if err := u.store.CompleteCODJob(ctx, job.ID); err != nil && !strings.Contains(err.Error(), "not active") {
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
