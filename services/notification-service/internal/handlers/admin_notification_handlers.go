package handlers

import (
	"bytes"
	"context"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/project/notification-service/internal/hub"
	"github.com/project/notification-service/internal/store"
	"github.com/project/shared/infra/handlerutil"
)

// Allowed in-app deep link patterns (orders, plans, verification, tickets)
var (
	validOrderDeepLinkRegex  = regexp.MustCompile(`^/(orders|jobs)/[a-zA-Z0-9_\-\.:]{1,64}$`)
	validTicketDeepLinkRegex = regexp.MustCompile(`^/tickets(/[a-zA-Z0-9_\-\.:]{1,64})?$`)
	validPlanDeepLinkRegex   = regexp.MustCompile(`^/(plan|plans|subscriptions|subscription)$`)
	validVerifyDeepLinkRegex = regexp.MustCompile(`^/(verification|kyc|kyb|kye)$`)
)

func validateDeepLink(link string) bool {
	link = strings.TrimSpace(link)
	if link == "" {
		return true // optional
	}
	// Disallow free URLs and scheme injection
	if strings.Contains(link, "://") || strings.HasPrefix(link, "//") || strings.HasPrefix(strings.ToLower(link), "javascript:") {
		return false
	}
	if !strings.HasPrefix(link, "/") {
		return false
	}
	return validOrderDeepLinkRegex.MatchString(link) ||
		validTicketDeepLinkRegex.MatchString(link) ||
		validPlanDeepLinkRegex.MatchString(link) ||
		validVerifyDeepLinkRegex.MatchString(link)
}

type ReviewerIdentity struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

func (n *Notification) authenticateReviewer(r *http.Request) (*ReviewerIdentity, error) {
	internalToken := r.Header.Get("X-Internal-Token")
	if n.internalServiceToken == "" || subtle.ConstantTimeCompare([]byte(internalToken), []byte(n.internalServiceToken)) != 1 {
		return nil, errors.New("unauthorized internal token")
	}

	reviewerToken := r.Header.Get("X-Reviewer-Token")
	if reviewerToken == "" {
		return nil, errors.New("missing reviewer token")
	}

	verifyURL := fmt.Sprintf("%s/auth/reviewer/verify", n.authServiceURL)
	req, err := http.NewRequestWithContext(r.Context(), http.MethodGet, verifyURL, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create verify request: %w", err)
	}
	req.Header.Set("X-Internal-Token", n.internalServiceToken)
	req.Header.Set("X-Reviewer-Token", reviewerToken)

	client := n.httpClient
	if client == nil {
		client = http.DefaultClient
	}
	resp, err := client.Do(req)
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

type TextBilingual struct {
	AR string `json:"ar"`
	EN string `json:"en"`
}

type AdminSendNotificationRequest struct {
	IdempotencyKey      string              `json:"idempotency_key,omitempty"`
	Reason              string              `json:"reason"`
	Audience            store.AdminAudience `json:"audience"`
	Title               TextBilingual       `json:"title"`
	TitleAR             string              `json:"title_ar,omitempty"`
	TitleEN             string              `json:"title_en,omitempty"`
	Body                TextBilingual       `json:"body"`
	BodyAR              string              `json:"body_ar,omitempty"`
	BodyEN              string              `json:"body_en,omitempty"`
	DeepLink            string              `json:"deep_link,omitempty"`
	DryRun              bool                `json:"dry_run,omitempty"`
	TestUserID          string              `json:"test_user_id,omitempty"`
	ConfirmAudienceSize int                 `json:"confirm_audience_size,omitempty"`
}

type AudienceLookupResult struct {
	UserIDs []string `json:"user_ids"`
	Total   int      `json:"total"`
	Page    int      `json:"page"`
	Limit   int      `json:"limit"`
}

func (n *Notification) lookupAudience(ctx context.Context, aud store.AdminAudience, page, limit int) (*AudienceLookupResult, error) {
	lookupURL := fmt.Sprintf("%s/auth/internal/audience-lookup", n.authServiceURL)
	payload, _ := json.Marshal(map[string]any{
		"kind":      aud.Kind,
		"user_id":   aud.UserID,
		"email":     aud.Email,
		"phone":     aud.Phone,
		"role":      aud.Role,
		"tenant_id": aud.TenantID,
		"page":      page,
		"limit":     limit,
	})

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, lookupURL, bytes.NewReader(payload))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Internal-Token", n.internalServiceToken)

	client := n.httpClient
	if client == nil {
		client = http.DefaultClient
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("audience lookup failed with status %d: %s", resp.StatusCode, string(body))
	}

	var res AudienceLookupResult
	if err := json.NewDecoder(resp.Body).Decode(&res); err != nil {
		return nil, err
	}
	return &res, nil
}

// AdminSendNotification handles POST /admin/notifications/send.
func (n *Notification) AdminSendNotification(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use POST"})
		return
	}

	reviewer, err := n.authenticateReviewer(r)
	if err != nil {
		handlerutil.WriteSafeError(w, r, http.StatusUnauthorized, handlerutil.ErrCodeUnauthorized, "unauthorized", err)
		return
	}

	var req AdminSendNotificationRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		handlerutil.WriteSafeError(w, r, http.StatusBadRequest, handlerutil.ErrCodeInvalidJSON, "invalid JSON body", err)
		return
	}

	// 1. Mandatory reason (1-1000 chars)
	reason := strings.TrimSpace(req.Reason)
	if len(reason) < 1 || len(reason) > 1000 {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error":   "invalid_reason",
			"code":    "invalid_reason",
			"message": "reason is required and must be between 1 and 1000 characters",
		})
		return
	}

	// 2. Titles and bodies in AR and EN
	titleAR := strings.TrimSpace(req.Title.AR)
	if titleAR == "" {
		titleAR = strings.TrimSpace(req.TitleAR)
	}
	titleEN := strings.TrimSpace(req.Title.EN)
	if titleEN == "" {
		titleEN = strings.TrimSpace(req.TitleEN)
	}
	if titleAR == "" || titleEN == "" || len(titleAR) > 120 || len(titleEN) > 120 {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error":   "invalid_title",
			"code":    "invalid_title",
			"message": "both Arabic and English titles are required (max 120 chars)",
		})
		return
	}

	bodyAR := strings.TrimSpace(req.Body.AR)
	if bodyAR == "" {
		bodyAR = strings.TrimSpace(req.BodyAR)
	}
	bodyEN := strings.TrimSpace(req.Body.EN)
	if bodyEN == "" {
		bodyEN = strings.TrimSpace(req.BodyEN)
	}
	if bodyAR == "" || bodyEN == "" || len(bodyAR) > 1000 || len(bodyEN) > 1000 {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error":   "invalid_body",
			"code":    "invalid_body",
			"message": "both Arabic and English bodies are required (max 1000 chars)",
		})
		return
	}

	// 3. Deep link validation
	deepLink := strings.TrimSpace(req.DeepLink)
	if deepLink != "" && !validateDeepLink(deepLink) {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error":   "invalid_deep_link",
			"code":    "invalid_deep_link",
			"message": "deep link must be an allowed internal route (e.g. /orders/{id}, /plan, /verification)",
		})
		return
	}

	// 4. Audience validation
	kind := strings.ToLower(strings.TrimSpace(req.Audience.Kind))
	if kind != "user" && kind != "role" && kind != "tenant" && kind != "everyone" {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error":   "invalid_audience",
			"code":    "invalid_audience",
			"message": "audience kind must be one of: user, role, tenant, everyone",
		})
		return
	}
	req.Audience.Kind = kind

	// 5. Idempotency key check
	if req.IdempotencyKey != "" && n.store != nil {
		existing, err := n.store.GetAdminNotificationSendByIdempotencyKey(r.Context(), req.IdempotencyKey)
		if err == nil && existing != nil {
			writeJSON(w, http.StatusOK, map[string]any{
				"job_id":        existing.ID,
				"status":        existing.Status,
				"audience_size": existing.AudienceSize,
				"message":       "idempotent replay of existing send job",
				"send":          existing,
			})
			return
		}
	}

	// 6. Audience lookup via auth-service
	ctx := r.Context()
	lookupRes, err := n.lookupAudience(ctx, req.Audience, 1, 1)
	if err != nil {
		handlerutil.WriteSafeError(w, r, http.StatusInternalServerError, handlerutil.ErrCodeInternal, "failed to resolve audience", err)
		return
	}
	resolvedSize := lookupRes.Total

	// Send test to me override
	isTestSend := false
	if req.TestUserID != "" {
		isTestSend = true
		resolvedSize = 1
	}

	// 7. Dry run
	if req.DryRun {
		writeJSON(w, http.StatusOK, map[string]any{
			"dry_run":       true,
			"audience_size": resolvedSize,
			"audience":      req.Audience,
		})
		return
	}

	// 8. Safety confirmation for "everyone" or audience >= 1000
	if !isTestSend && (kind == "everyone" || resolvedSize >= 1000) {
		if req.ConfirmAudienceSize <= 0 || req.ConfirmAudienceSize != resolvedSize {
			writeJSON(w, http.StatusBadRequest, map[string]any{
				"error":                  "confirmation_required",
				"code":                   "confirmation_required",
				"message":                fmt.Sprintf("confirmation required: confirm_audience_size (%d) must match resolved audience size (%d)", req.ConfirmAudienceSize, resolvedSize),
				"resolved_audience_size": resolvedSize,
			})
			return
		}
	}

	// 9. Rate limit per reviewer (5 sends / hour)
	if n.adminSendLimiter != nil {
		rateKey := "admin_notif_send:" + reviewer.ID
		if limited, remaining := n.adminSendLimiter.CheckAndRecord(rateKey); limited {
			writeJSON(w, http.StatusTooManyRequests, map[string]string{
				"error":   "rate_limit_exceeded",
				"code":    "rate_limit_exceeded",
				"message": fmt.Sprintf("rate limit exceeded: max 5 sends per hour, retry in %.0f seconds", remaining.Seconds()),
			})
			return
		}
	}

	// 10. Audit log
	clientIP := handlerutil.GetClientIP(r)
	handlerutil.ShipSecurityEvent(ctx, "ADMIN_NOTIFICATION_SENT", "notification-service", reviewer.ID, "",
		fmt.Sprintf("sent admin notification to audience kind=%s size=%d test=%v reason=%q", kind, resolvedSize, isTestSend, reason),
		clientIP)

	// 11. Create send record
	jobID := fmt.Sprintf("send-%d", time.Now().UnixNano())
	sendJob := &store.AdminNotificationSend{
		ID:             jobID,
		IdempotencyKey: req.IdempotencyKey,
		ReviewerID:     reviewer.ID,
		ReviewerName:   reviewer.Name,
		Reason:         reason,
		Audience:       req.Audience,
		TitleAR:        titleAR,
		TitleEN:        titleEN,
		BodyAR:         bodyAR,
		BodyEN:         bodyEN,
		DeepLink:       deepLink,
		Status:         store.SendStatusQueued,
		AudienceSize:   resolvedSize,
		CreatedAt:      time.Now().UTC(),
		UpdatedAt:      time.Now().UTC(),
	}

	if n.store != nil {
		if err := n.store.CreateAdminNotificationSend(ctx, sendJob); err != nil {
			handlerutil.WriteSafeError(w, r, http.StatusInternalServerError, handlerutil.ErrCodeInternal, "failed to record send job", err)
			return
		}
		n.recordAdminAudit(r, reviewer.ID, auditNotificationSend, "notification_send", jobID, reason,
			fmt.Sprintf("audience=%s size=%d test=%t", kind, resolvedSize, isTestSend))
	}

	// 12. Asynchronous background fan-out
	// #nosec G118 //nolint:gosec -- background notification fan-out outlives HTTP request lifecycle
	go n.fanOutAdminNotification(sendJob, isTestSend, req.TestUserID)

	writeJSON(w, http.StatusAccepted, map[string]any{
		"job_id":        jobID,
		"status":        string(store.SendStatusQueued),
		"audience_size": resolvedSize,
		"message":       "admin notification queued for delivery",
	})
}

func (n *Notification) fanOutAdminNotification(job *store.AdminNotificationSend, isTestSend bool, testUserID string) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
	defer cancel()

	if n.store != nil {
		_ = n.store.UpdateAdminNotificationSendProgress(ctx, job.ID, store.SendStatusSending, 0, 0, "")
	}

	sentCount := 0
	failedCount := 0

	dispatchToUser := func(uid string) {
		if uid == "" {
			return
		}
		notif := hub.Notification{
			ID:        fmt.Sprintf("notif-%d-%s", time.Now().UnixNano(), uid),
			Type:      "admin_announcement",
			UserID:    uid,
			Title:     job.TitleEN,
			Body:      job.BodyEN,
			Timestamp: time.Now().UTC(),
			Params: map[string]string{
				"title_ar":  job.TitleAR,
				"body_ar":   job.BodyAR,
				"title_en":  job.TitleEN,
				"body_en":   job.BodyEN,
				"deep_link": job.DeepLink,
			},
		}

		if n.store != nil {
			storeDoc := &store.Notification{
				ID:        notif.ID,
				Type:      notif.Type,
				UserID:    notif.UserID,
				Title:     notif.Title,
				Body:      notif.Body,
				Params:    notif.Params,
				Timestamp: notif.Timestamp,
				CreatedAt: notif.Timestamp,
			}
			if err := n.store.InsertNotification(ctx, storeDoc); err != nil {
				log.Printf("[ADMIN-NOTIF] Failed to persist announcement for user %s: %v", uid, err)
			}
		}

		if n.hub != nil {
			n.hub.Broadcast(notif)
		}
		sentCount++
	}

	if isTestSend {
		dispatchToUser(testUserID)
	} else {
		page := 1
		limit := 500
		for {
			res, err := n.lookupAudience(ctx, job.Audience, page, limit)
			if err != nil {
				log.Printf("[ADMIN-NOTIF] Batch lookup failed page=%d: %v", page, err)
				failedCount += limit
				break
			}
			if len(res.UserIDs) == 0 {
				break
			}
			for _, uid := range res.UserIDs {
				dispatchToUser(uid)
			}
			if len(res.UserIDs) < limit || sentCount >= res.Total {
				break
			}
			page++
		}
	}

	status := store.SendStatusDone
	if sentCount == 0 && failedCount > 0 {
		status = store.SendStatusFailed
	}
	if n.store != nil {
		_ = n.store.UpdateAdminNotificationSendProgress(ctx, job.ID, status, sentCount, failedCount, "")
	}
}

// AdminListNotificationSends handles GET /admin/notifications/sends.
func (n *Notification) AdminListNotificationSends(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use GET"})
		return
	}

	reviewer, err := n.authenticateReviewer(r)
	if err != nil {
		handlerutil.WriteSafeError(w, r, http.StatusUnauthorized, handlerutil.ErrCodeUnauthorized, "unauthorized", err)
		return
	}

	page := 1
	if pStr := r.URL.Query().Get("page"); pStr != "" {
		if p, err := strconv.Atoi(pStr); err == nil && p > 0 {
			page = p
		}
	}
	limit := 20
	if lStr := r.URL.Query().Get("limit"); lStr != "" {
		if l, err := strconv.Atoi(lStr); err == nil && l > 0 {
			limit = l
			if limit > 100 {
				limit = 100
			}
		}
	}

	if n.store == nil {
		writeJSON(w, http.StatusOK, map[string]any{"sends": []any{}, "total": 0, "page": page, "limit": limit})
		return
	}

	sends, total, err := n.store.ListAdminNotificationSends(r.Context(), page, limit)
	if err != nil {
		handlerutil.WriteSafeError(w, r, http.StatusInternalServerError, handlerutil.ErrCodeInternal, "failed to list send jobs", err)
		return
	}

	handlerutil.ShipSecurityEvent(r.Context(), "ADMIN_NOTIFICATION_SENDS_LISTED", "notification-service", reviewer.ID, "",
		fmt.Sprintf("listed admin notification sends page=%d limit=%d total=%d", page, limit, total),
		handlerutil.GetClientIP(r))

	writeJSON(w, http.StatusOK, map[string]any{
		"sends": sends,
		"total": total,
		"page":  page,
		"limit": limit,
	})
}

// AdminGetNotificationSend handles GET /admin/notifications/sends/{id}.
func (n *Notification) AdminGetNotificationSend(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use GET"})
		return
	}

	reviewer, err := n.authenticateReviewer(r)
	if err != nil {
		handlerutil.WriteSafeError(w, r, http.StatusUnauthorized, handlerutil.ErrCodeUnauthorized, "unauthorized", err)
		return
	}

	id := r.PathValue("id")
	if id == "" {
		trimmed := strings.TrimPrefix(r.URL.Path, "/admin/notifications/sends/")
		trimmed = strings.TrimPrefix(trimmed, "/notifications/admin/sends/")
		id = strings.Trim(trimmed, "/")
	}
	if id == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "send job id is required"})
		return
	}

	if n.store == nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "send job not found"})
		return
	}

	send, err := n.store.GetAdminNotificationSendByID(r.Context(), id)
	if err != nil {
		if errors.Is(err, store.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "send job not found"})
			return
		}
		handlerutil.WriteSafeError(w, r, http.StatusInternalServerError, handlerutil.ErrCodeInternal, "failed to fetch send job", err)
		return
	}

	handlerutil.ShipSecurityEvent(r.Context(), "ADMIN_NOTIFICATION_SEND_VIEWED", "notification-service", reviewer.ID, "",
		fmt.Sprintf("viewed admin notification send job %s", id),
		handlerutil.GetClientIP(r))

	writeJSON(w, http.StatusOK, send)
}
