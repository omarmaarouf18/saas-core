package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/project/shared/infra/handlerutil"
	"github.com/project/user-service/internal/models"
	"github.com/project/user-service/internal/store"
)

// AdminJobSummary represents a job in the admin jobs list view with unmasked phones.
type AdminJobSummary struct {
	ID                 string                 `json:"id"`
	Status             models.JobStatus       `json:"status"`
	SubStatus          string                 `json:"sub_status,omitempty"`
	OwnerID            string                 `json:"owner_id"`
	UserID             string                 `json:"user_id"`
	EmployeeID         string                 `json:"employee_id,omitempty"`
	ServiceID          string                 `json:"service_id"`
	Location           models.Location        `json:"location"`
	Destination        models.Location        `json:"destination"`
	PaymentMethod      string                 `json:"payment_method"`
	SuggestedPrice     float64                `json:"suggested_price"`
	AgreedPrice        *float64               `json:"agreed_price,omitempty"`
	ActualCashAmount   *float64               `json:"actual_cash_amount,omitempty"`
	LockedEscrowAmount float64                `json:"locked_escrow_amount,omitempty"`
	CustomerName       string                 `json:"customer_name,omitempty"`
	Recipient          *models.JobRecipient   `json:"recipient,omitempty"`
	PackageDetails     *models.PackageDetails `json:"package_details,omitempty"`
	DistanceReview     *models.DistanceReview `json:"distance_review,omitempty"`
	CreatedAt          time.Time              `json:"created_at"`
	UpdatedAt          time.Time              `json:"updated_at"`
}

// AdminJobListResponse is the response for GET /admin/jobs.
type AdminJobListResponse struct {
	Jobs  []AdminJobSummary `json:"jobs"`
	Total int64             `json:"total"`
	Page  int64             `json:"page"`
	Limit int64             `json:"limit"`
}

// AdminJobNotificationItem represents a notification sent for a job.
type AdminJobNotificationItem struct {
	ID        string            `json:"id"`
	Type      string            `json:"type"`
	Title     string            `json:"title"`
	Body      string            `json:"body"`
	UserID    string            `json:"user_id,omitempty"`
	Timestamp time.Time         `json:"timestamp"`
	Params    map[string]string `json:"params,omitempty"`
}

// AdminJobDetailResponse is the full v2 view for GET /admin/jobs/{id}.
type AdminJobDetailResponse struct {
	ID                  string                         `json:"id"`
	Status              models.JobStatus               `json:"status"`
	SubStatus           string                         `json:"sub_status,omitempty"`
	StatusHistory       []models.JobStatusHistoryEntry `json:"status_history"`
	Location            models.Location                `json:"location"`
	Destination         models.Location                `json:"destination"`
	CurrentLocation     *models.Location               `json:"current_location,omitempty"`
	Waypoints           []models.Location              `json:"waypoints,omitempty"`
	Recipient           *models.JobRecipient           `json:"recipient,omitempty"`
	PackageDetails      *models.PackageDetails         `json:"package_details,omitempty"`
	Package             *models.PackageDetails         `json:"package,omitempty"`
	Price               map[string]any                 `json:"price"`
	SuggestedPrice      float64                        `json:"suggested_price"`
	AgreedPrice         *float64                       `json:"agreed_price,omitempty"`
	ActualCashAmount    *float64                       `json:"actual_cash_amount,omitempty"`
	LockedEscrowAmount  float64                        `json:"locked_escrow_amount,omitempty"`
	PaymentMethod       string                         `json:"payment_method"`
	Tenant              string                         `json:"tenant"`
	OwnerID             string                         `json:"owner_id"`
	Courier             string                         `json:"courier,omitempty"`
	EmployeeID          string                         `json:"employee_id,omitempty"`
	CourierPhone        string                         `json:"courier_phone,omitempty"`
	CustomerID          string                         `json:"customer_id"`
	UserID              string                         `json:"user_id"`
	CustomerName        string                         `json:"customer_name,omitempty"`
	CustomerPhone       string                         `json:"customer_phone,omitempty"`
	Ratings             []*models.Rating               `json:"ratings"`
	ReconciliationFlags map[string]any                 `json:"reconciliation_flags"`
	Notifications       []AdminJobNotificationItem     `json:"notifications"`
	CreatedAt           time.Time                      `json:"created_at"`
	UpdatedAt           time.Time                      `json:"updated_at"`
}

func parseAdminDate(raw string, isEnd bool) *time.Time {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return nil
	}
	if t, err := time.Parse(time.RFC3339, raw); err == nil {
		return &t
	}
	if t, err := time.Parse("2006-01-02", raw); err == nil {
		if isEnd {
			endOfDay := time.Date(t.Year(), t.Month(), t.Day(), 23, 59, 59, 999999999, time.UTC)
			return &endOfDay
		}
		startOfDay := time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, time.UTC)
		return &startOfDay
	}
	return nil
}

func (u *UserService) lookupUserByPhone(ctx context.Context, phone string) string {
	if phone == "" || u.authServiceURL == "" || u.internalServiceToken == "" {
		return ""
	}
	url := fmt.Sprintf("%s/auth/internal/user-by-phone?phone=%s", strings.TrimSuffix(u.authServiceURL, "/"), url.QueryEscape(phone))
	reqCtx, cancel := context.WithTimeout(ctx, 1*time.Second)
	defer cancel()

	// #nosec G704 //nolint:gosec -- authServiceURL is trusted internal config and phone is url.QueryEscape'd
	req, err := http.NewRequestWithContext(reqCtx, http.MethodGet, url, nil)
	if err != nil {
		return ""
	}
	req.Header.Set("X-Internal-Token", u.internalServiceToken)

	var resp *http.Response
	if u.authClient != nil {
		// #nosec G704 //nolint:gosec -- authClient is internal HTTP client
		resp, err = u.authClient.Do(req)
	} else {
		// #nosec G704 //nolint:gosec -- DefaultClient is internal fallback
		resp, err = http.DefaultClient.Do(req)
	}
	if err != nil {
		return ""
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return ""
	}

	var user struct {
		ID string `json:"id"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&user); err != nil {
		return ""
	}
	return strings.TrimSpace(user.ID)
}

func (u *UserService) fetchJobNotifications(ctx context.Context, jobID string) []AdminJobNotificationItem {
	if jobID == "" || u.notificationServiceURL == "" || u.internalServiceToken == "" {
		return []AdminJobNotificationItem{}
	}
	url := fmt.Sprintf("%s/notifications/internal/by-job?job_id=%s", strings.TrimSuffix(u.notificationServiceURL, "/"), url.QueryEscape(jobID))
	reqCtx, cancel := context.WithTimeout(ctx, 1*time.Second)
	defer cancel()

	// #nosec G704 //nolint:gosec -- notificationServiceURL is trusted internal config and jobID is url.QueryEscape'd
	req, err := http.NewRequestWithContext(reqCtx, http.MethodGet, url, nil)
	if err != nil {
		return []AdminJobNotificationItem{}
	}
	req.Header.Set("X-Internal-Token", u.internalServiceToken)

	var resp *http.Response
	if u.notificationClient != nil {
		// #nosec G704 //nolint:gosec -- notificationClient is internal HTTP client
		resp, err = u.notificationClient.Do(req)
	} else {
		// #nosec G704 //nolint:gosec -- DefaultClient is internal fallback
		resp, err = http.DefaultClient.Do(req)
	}
	if err != nil {
		return []AdminJobNotificationItem{}
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return []AdminJobNotificationItem{}
	}

	var result struct {
		Notifications []AdminJobNotificationItem `json:"notifications"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return []AdminJobNotificationItem{}
	}
	if result.Notifications == nil {
		return []AdminJobNotificationItem{}
	}
	return result.Notifications
}

// AdminListJobs handles GET /admin/jobs & GET /users/admin/jobs.
// Filters by job id, customer/owner/courier id, phone exact match, status, and date range.
// Phones are visible unmasked for support operations and every listing is audit-logged.
func (u *UserService) AdminListJobs(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}

	reviewer, err := u.authenticateReviewer(r)
	if err != nil {
		handlerutil.WriteSafeError(w, r, http.StatusUnauthorized, handlerutil.ErrCodeUnauthorized, "unauthorized", err)
		return
	}

	ctx := r.Context()
	q := r.URL.Query()

	jobID := strings.TrimSpace(q.Get("job_id"))
	if jobID == "" {
		jobID = strings.TrimSpace(q.Get("id"))
	}
	if jobID == "" {
		jobID = strings.TrimSpace(q.Get("search"))
	}

	customerID := strings.TrimSpace(q.Get("customer_id"))
	if customerID == "" {
		customerID = strings.TrimSpace(q.Get("user_id"))
	}

	ownerID := strings.TrimSpace(q.Get("owner_id"))
	if ownerID == "" {
		ownerID = strings.TrimSpace(q.Get("tenant_id"))
	}

	courierID := strings.TrimSpace(q.Get("courier_id"))
	if courierID == "" {
		courierID = strings.TrimSpace(q.Get("employee_id"))
	}

	phone := strings.TrimSpace(q.Get("phone"))
	status := strings.TrimSpace(q.Get("status"))

	fromStr := strings.TrimSpace(q.Get("from"))
	if fromStr == "" {
		fromStr = strings.TrimSpace(q.Get("start_date"))
	}
	toStr := strings.TrimSpace(q.Get("to"))
	if toStr == "" {
		toStr = strings.TrimSpace(q.Get("end_date"))
	}

	dateFrom := parseAdminDate(fromStr, false)
	dateTo := parseAdminDate(toStr, true)

	var resolvedUserIDs []string
	if phone != "" {
		if uid := u.lookupUserByPhone(ctx, phone); uid != "" {
			resolvedUserIDs = append(resolvedUserIDs, uid)
		}
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

	filter := store.AdminJobFilter{
		JobID:                   jobID,
		CustomerID:              customerID,
		OwnerID:                 ownerID,
		CourierID:               courierID,
		Phone:                   phone,
		ResolvedUserIDsForPhone: resolvedUserIDs,
		Status:                  status,
		DateFrom:                dateFrom,
		DateTo:                  dateTo,
	}

	jobs, total, err := u.store.AdminListJobs(ctx, filter, page, limit)
	if err != nil {
		handlerutil.WriteSafeError(w, r, http.StatusInternalServerError, handlerutil.ErrCodeInternal, "failed to query jobs", err)
		return
	}

	items := make([]AdminJobSummary, 0, len(jobs))
	for _, j := range jobs {
		items = append(items, AdminJobSummary{
			ID:                 j.ID,
			Status:             j.Status,
			SubStatus:          j.SubStatus,
			OwnerID:            j.OwnerID,
			UserID:             j.UserID,
			EmployeeID:         j.EmployeeID,
			ServiceID:          j.ServiceID,
			Location:           j.Location,
			Destination:        j.Destination,
			PaymentMethod:      j.PaymentMethod,
			SuggestedPrice:     j.SuggestedPrice,
			AgreedPrice:        j.AgreedPrice,
			ActualCashAmount:   j.ActualCashAmount,
			LockedEscrowAmount: j.LockedEscrowAmount,
			CustomerName:       j.CustomerName,
			Recipient:          j.Recipient,
			PackageDetails:     j.PackageDetails,
			DistanceReview:     j.DistanceReview,
			CreatedAt:          j.CreatedAt,
			UpdatedAt:          j.UpdatedAt,
		})
	}

	handlerutil.ShipSecurityEvent(ctx, "ADMIN_JOBS_LISTED", "user-service", reviewer.ID, "", fmt.Sprintf("listed %d jobs (total=%d, page=%d)", len(items), total, page), handlerutil.GetClientIP(r))

	writeJSON(w, http.StatusOK, AdminJobListResponse{
		Jobs:  items,
		Total: total,
		Page:  page,
		Limit: limit,
	})
}

// AdminJobDetail handles GET /admin/jobs/{id} & GET /users/admin/jobs/{id}.
// Returns full v2 view with status, sub_status, status_history, addresses, recipient, package,
// price, payment method, tenant, courier, customer_name, ratings, reconciliation flags, and notifications.
// Phones are unmasked for support operations and every view is audit-logged with the job id.
func (u *UserService) AdminJobDetail(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}

	reviewer, err := u.authenticateReviewer(r)
	if err != nil {
		handlerutil.WriteSafeError(w, r, http.StatusUnauthorized, handlerutil.ErrCodeUnauthorized, "unauthorized", err)
		return
	}

	ctx := r.Context()
	jobID := r.PathValue("id")
	if jobID == "" {
		// Fallback for custom routing
		path := strings.TrimPrefix(r.URL.Path, "/users/admin/jobs/")
		path = strings.TrimPrefix(path, "/admin/jobs/")
		jobID = strings.TrimSpace(path)
	}

	if jobID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "job id is required"})
		return
	}

	job := u.store.GetJob(ctx, jobID)
	if job == nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "job not found"})
		return
	}

	// Fetch ratings
	ratings, err := u.store.GetRatingsForJob(ctx, job.ID)
	if err != nil {
		ratings = []*models.Rating{}
	}

	// Fetch notifications
	notifications := u.fetchJobNotifications(ctx, job.ID)

	// Fetch contact phones
	var courierPhone string
	if job.EmployeeID != "" {
		courierPhone = u.fetchUserPhone(ctx, job.EmployeeID)
	}
	customerPhone := u.fetchUserPhone(ctx, job.UserID)

	// Build reconciliation flags map
	reconFlags := map[string]any{}
	if job.DistanceReview != nil {
		reconFlags["distance_review"] = job.DistanceReview
	}
	if job.EscrowFailureReason != "" {
		reconFlags["escrow_failure_reason"] = job.EscrowFailureReason
	}
	if job.ReconciliationNote != "" {
		reconFlags["reconciliation_note"] = job.ReconciliationNote
	}
	if job.CancellationReason != "" {
		reconFlags["cancellation_reason"] = job.CancellationReason
	}
	if job.CancellationRequestReason != "" {
		reconFlags["cancellation_request_reason"] = job.CancellationRequestReason
		reconFlags["cancellation_request_status"] = job.CancellationRequestStatus
		reconFlags["cancellation_requested_at"] = job.CancellationRequestedAt
	}

	priceMap := map[string]any{
		"suggested_price":      job.SuggestedPrice,
		"agreed_price":         job.AgreedPrice,
		"actual_cash_amount":   job.ActualCashAmount,
		"locked_escrow_amount": job.LockedEscrowAmount,
		"payment_method":       job.PaymentMethod,
	}

	statusHistory := job.StatusHistory
	if statusHistory == nil {
		statusHistory = []models.JobStatusHistoryEntry{}
	}

	handlerutil.ShipSecurityEvent(ctx, "ADMIN_JOB_VIEWED", "user-service", reviewer.ID, job.OwnerID, fmt.Sprintf("viewed full details for job %s", job.ID), handlerutil.GetClientIP(r))
	u.recordAdminAudit(r, reviewer.ID, auditJobView, "job", job.ID, "", "full detail with unmasked recipient and courier phones")

	writeJSON(w, http.StatusOK, AdminJobDetailResponse{
		ID:                  job.ID,
		Status:              job.Status,
		SubStatus:           job.SubStatus,
		StatusHistory:       statusHistory,
		Location:            job.Location,
		Destination:         job.Destination,
		CurrentLocation:     job.CurrentLocation,
		Waypoints:           job.Waypoints,
		Recipient:           job.Recipient,
		PackageDetails:      job.PackageDetails,
		Package:             job.PackageDetails,
		Price:               priceMap,
		SuggestedPrice:      job.SuggestedPrice,
		AgreedPrice:         job.AgreedPrice,
		ActualCashAmount:    job.ActualCashAmount,
		LockedEscrowAmount:  job.LockedEscrowAmount,
		PaymentMethod:       job.PaymentMethod,
		Tenant:              job.OwnerID,
		OwnerID:             job.OwnerID,
		Courier:             job.EmployeeID,
		EmployeeID:          job.EmployeeID,
		CourierPhone:        courierPhone,
		CustomerID:          job.UserID,
		UserID:              job.UserID,
		CustomerName:        job.CustomerName,
		CustomerPhone:       customerPhone,
		Ratings:             ratings,
		ReconciliationFlags: reconFlags,
		Notifications:       notifications,
		CreatedAt:           job.CreatedAt,
		UpdatedAt:           job.UpdatedAt,
	})
}

// AdminJobActionPayload is the request payload for admin job mutations.
// Only reason and job_id are permitted. Editing prices or addresses is rejected.
type AdminJobActionPayload struct {
	JobID   string          `json:"job_id,omitempty"`
	Reason  string          `json:"reason"`
	Price   json.RawMessage `json:"price,omitempty"`
	Address json.RawMessage `json:"address,omitempty"`
}

// AdminCancelJob cancels a non-terminal job on behalf of reviewer/admin.
// Mutations require a reason (1–1000 chars), perform CAS, audit log + ShipSecurityEvent,
// and notify the parties like the normal flow.
func (u *UserService) AdminCancelJob(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use POST"})
		return
	}

	reviewer, err := u.authenticateReviewer(r)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return
	}

	var req AdminJobActionPayload
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}

	if len(req.Price) > 0 || len(req.Address) > 0 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "editing prices or addresses is not allowed"})
		return
	}

	jobID := strings.TrimSpace(r.PathValue("id"))
	if jobID == "" {
		jobID = strings.TrimSpace(req.JobID)
	}
	if jobID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "job_id is required"})
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

	clientIP := handlerutil.GetClientIP(r)
	ctx := r.Context()

	cancelledJob, err := u.store.AdminCancelJob(ctx, jobID, reviewer.ID, reason)
	if err != nil {
		if errors.Is(err, store.ErrJobNotFound) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "job not found"})
			return
		}
		if errors.Is(err, store.ErrJobAlreadyTerminal) || errors.Is(err, store.ErrJobStateConflict) {
			writeJSON(w, http.StatusConflict, map[string]string{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to cancel job: " + err.Error()})
		return
	}

	// Audit log + ShipSecurityEvent
	handlerutil.ShipSecurityEvent(ctx, "ADMIN_JOB_CANCELLED", "user-service", reviewer.ID, cancelledJob.OwnerID, fmt.Sprintf("cancelled job %s: %s", jobID, reason), clientIP)
	u.recordAdminAudit(r, reviewer.ID, auditJobCancel, "job", jobID, reason, "owner="+cancelledJob.OwnerID)

	// Notify parties like normal flow
	u.notifyCustomerJobCancelled(cancelledJob, reviewer.ID)
	if cancelledJob.EmployeeID != "" {
		u.notifyJobEvent(cancelledJob, cancelledJob.EmployeeID, []string{"employee"}, JobEventCancelled, "Booking Cancelled", fmt.Sprintf("Job %s was cancelled by support: %s", jobID, reason), map[string]string{"reason": reason})
	}
	u.notifyJobEvent(cancelledJob, cancelledJob.OwnerID, []string{"owner"}, JobEventCancelled, "Booking Cancelled", fmt.Sprintf("Job %s was cancelled by support: %s", jobID, reason), map[string]string{"reason": reason})

	writeJSON(w, http.StatusOK, map[string]any{
		"success": true,
		"message": "job cancelled successfully",
		"job_id":  jobID,
		"status":  models.JobStatusCancelled,
	})
}

// AdminCompleteStuckCODJob marks a stuck COD job completed using the FIX-COD-RECON path.
// Mutations require a reason (1–1000 chars), perform CAS, audit log + ShipSecurityEvent,
// and notify the parties like the normal flow.
func (u *UserService) AdminCompleteStuckCODJob(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use POST"})
		return
	}

	reviewer, err := u.authenticateReviewer(r)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return
	}

	var req AdminJobActionPayload
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}

	if len(req.Price) > 0 || len(req.Address) > 0 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "editing prices or addresses is not allowed"})
		return
	}

	jobID := strings.TrimSpace(r.PathValue("id"))
	if jobID == "" {
		jobID = strings.TrimSpace(req.JobID)
	}
	if jobID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "job_id is required"})
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

	clientIP := handlerutil.GetClientIP(r)
	ctx := r.Context()

	repaired, err := u.store.RepairSingleStuckCODJob(ctx, jobID, reviewer.ID, reason)
	if err != nil {
		if errors.Is(err, store.ErrJobNotFound) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "job not found"})
			return
		}
		if errors.Is(err, store.ErrNotStuckCODJob) || errors.Is(err, store.ErrJobStateConflict) {
			writeJSON(w, http.StatusConflict, map[string]string{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to complete stuck COD job: " + err.Error()})
		return
	}

	// Audit log + ShipSecurityEvent
	handlerutil.ShipSecurityEvent(ctx, "ADMIN_JOB_COMPLETED_STUCK_COD", "user-service", reviewer.ID, repaired.OwnerID, fmt.Sprintf("completed stuck COD job %s, cash: %.2f, reason: %s", jobID, repaired.CashAmount, reason), clientIP)
	u.recordAdminAudit(r, reviewer.ID, auditJobCompleteStuckCOD, "job", jobID, reason, fmt.Sprintf("owner=%s cash=%.2f", repaired.OwnerID, repaired.CashAmount))

	// Fetch job to notify parties like normal delivery flow
	job := u.store.GetJob(ctx, jobID)
	if job != nil {
		u.notifyCustomerJobDelivered(job)
		u.notifyJobEvent(job, job.OwnerID, []string{"owner"}, JobEventDelivered, "Job Completed", fmt.Sprintf("Stuck COD job %s completed by support.", jobID), nil)
		if job.EmployeeID != "" {
			u.notifyJobEvent(job, job.EmployeeID, []string{"employee"}, JobEventDelivered, "Job Completed", fmt.Sprintf("Job %s marked completed by support.", jobID), nil)
		}
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"success":            true,
		"message":            "stuck COD job completed successfully",
		"job_id":             jobID,
		"status":             models.JobStatusCompleted,
		"actual_cash_amount": repaired.CashAmount,
	})
}
