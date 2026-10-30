package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/project/auth-service/internal/store"
	"github.com/project/shared/infra/handlerutil"
)

// AdminGetAuditLogs handles GET /admin/audit and GET /auth/admin/audit (ADR-0023).
// It merges the admin audit records of every service (auth-service's own
// admin_audit collection plus user, chat, notification and gateway over
// their internal admin-audit endpoints), newest first, with filtering by
// actor reviewer, action, target id and date, and page/limit pagination. A
// source that fails or times out is reported as "unavailable" in `sources`
// and left out of the page and the total (ADMIN-API-FIX).
func (a *Auth) AdminGetAuditLogs(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed, use GET"})
		return
	}

	reviewer, err := a.authenticateReviewer(r)
	if err != nil {
		writeReviewerAuthError(w, err)
		return
	}

	ctx := r.Context()
	q := r.URL.Query()

	actor := strings.TrimSpace(q.Get("actor"))
	if actor == "" {
		actor = strings.TrimSpace(q.Get("actor_id"))
	}
	if actor == "" {
		actor = strings.TrimSpace(q.Get("reviewer_id"))
	}
	if actor == "" {
		actor = strings.TrimSpace(q.Get("employee_id"))
	}

	action := strings.TrimSpace(q.Get("action"))

	targetID := strings.TrimSpace(q.Get("target_id"))
	if targetID == "" {
		targetID = strings.TrimSpace(q.Get("target"))
	}
	if targetID == "" {
		targetID = strings.TrimSpace(q.Get("user_id"))
	}
	if targetID == "" {
		targetID = strings.TrimSpace(q.Get("tenant_id"))
	}

	var startDate, endDate *time.Time
	if dStr := strings.TrimSpace(q.Get("date")); dStr != "" {
		if t, err := time.Parse("2006-01-02", dStr); err == nil {
			s := t.UTC()
			e := s.Add(24*time.Hour - time.Nanosecond)
			startDate = &s
			endDate = &e
		} else if t, err := time.Parse(time.RFC3339, dStr); err == nil {
			s := t.UTC()
			startDate = &s
		}
	}

	if sStr := strings.TrimSpace(q.Get("start_date")); sStr != "" {
		if t, err := time.Parse(time.RFC3339, sStr); err == nil {
			s := t.UTC()
			startDate = &s
		} else if t, err := time.Parse("2006-01-02", sStr); err == nil {
			s := t.UTC()
			startDate = &s
		}
	} else if sStr := strings.TrimSpace(q.Get("from")); sStr != "" {
		if t, err := time.Parse(time.RFC3339, sStr); err == nil {
			s := t.UTC()
			startDate = &s
		} else if t, err := time.Parse("2006-01-02", sStr); err == nil {
			s := t.UTC()
			startDate = &s
		}
	}

	if eStr := strings.TrimSpace(q.Get("end_date")); eStr != "" {
		if t, err := time.Parse(time.RFC3339, eStr); err == nil {
			e := t.UTC()
			endDate = &e
		} else if t, err := time.Parse("2006-01-02", eStr); err == nil {
			e := t.UTC().Add(24*time.Hour - time.Nanosecond)
			endDate = &e
		}
	} else if eStr := strings.TrimSpace(q.Get("to")); eStr != "" {
		if t, err := time.Parse(time.RFC3339, eStr); err == nil {
			e := t.UTC()
			endDate = &e
		} else if t, err := time.Parse("2006-01-02", eStr); err == nil {
			e := t.UTC().Add(24*time.Hour - time.Nanosecond)
			endDate = &e
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

	window := page * limit
	if window > adminAuditMaxLimit {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": fmt.Sprintf("page too deep: page*limit must be at most %d, narrow the filters instead", adminAuditMaxLimit)})
		return
	}

	filter := store.AdminAuditFilter{
		ActorID:  actor,
		Action:   action,
		TargetID: targetID,
		From:     startDate,
		To:       endDate,
	}

	results := a.collectAdminAudit(ctx, filter, window)

	sources := make(map[string]string, len(results))
	merged := []store.AdminAuditRecord{}
	var total int64
	for _, res := range results {
		if res.err != nil {
			sources[res.name] = adminAuditSourceUnavailable
			log.Printf("[ADMIN-AUDIT] source %s unavailable: %v", res.name, res.err)
			continue
		}
		sources[res.name] = adminAuditSourceOK
		total += res.total
		merged = append(merged, res.entries...)
	}
	sort.SliceStable(merged, func(i, j int) bool {
		if !merged[i].CreatedAt.Equal(merged[j].CreatedAt) {
			return merged[i].CreatedAt.After(merged[j].CreatedAt)
		}
		return merged[i].ID > merged[j].ID
	})
	start := (page - 1) * limit
	if start > int64(len(merged)) {
		start = int64(len(merged))
	}
	end := start + limit
	if end > int64(len(merged)) {
		end = int64(len(merged))
	}
	entries := merged[start:end]

	handlerutil.ShipSecurityEvent(ctx, "ADMIN_AUDIT_VIEWED", "auth-service", reviewer.ID, "", fmt.Sprintf("viewed audit logs page=%d limit=%d total=%d", page, limit, total), handlerutil.GetClientIP(r))

	writeJSON(w, http.StatusOK, AdminAuditResponse{
		Entries: entries,
		Total:   total,
		Page:    page,
		Limit:   limit,
		Sources: sources,
	})
}

const (
	adminAuditSourceOK          = "ok"
	adminAuditSourceUnavailable = "unavailable"
)

// adminAuditSourceTimeout bounds each source call of the GET /admin/audit
// fan-out, so one slow service cannot stall the viewer.
var adminAuditSourceTimeout = 3 * time.Second

// AdminAuditResponse is the payload of GET /admin/audit.
type AdminAuditResponse struct {
	Entries []store.AdminAuditRecord `json:"entries"`
	// Total counts matching records in the sources that answered.
	Total int64 `json:"total"`
	Page  int64 `json:"page"`
	Limit int64 `json:"limit"`
	// Sources maps each service to "ok" or "unavailable".
	Sources map[string]string `json:"sources"`
}

type adminAuditSourceResult struct {
	name    string
	entries []store.AdminAuditRecord
	total   int64
	err     error
}

// collectAdminAudit queries every source in parallel for its newest `window`
// matching records.
func (a *Auth) collectAdminAudit(ctx context.Context, f store.AdminAuditFilter, window int64) []adminAuditSourceResult {
	remotes := []struct{ name, url string }{
		{"user-service", a.userServiceURL + "/users/internal/admin-audit"},
		{"chat-service", a.chatServiceURL + "/chat/internal/admin-audit"},
		{"notification-service", a.notificationURL + "/notifications/internal/admin-audit"},
		{"api-gateway", a.gatewayInternalURL + "/admin/internal/audit"},
	}
	results := make([]adminAuditSourceResult, len(remotes)+1)
	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		lctx, cancel := context.WithTimeout(ctx, adminAuditSourceTimeout)
		defer cancel()
		entries, total, err := a.store.ListAdminAudit(lctx, f, window)
		results[0] = adminAuditSourceResult{name: "auth-service", entries: entries, total: total, err: err}
	}()
	for i, src := range remotes {
		wg.Add(1)
		go func(i int, name, base string) {
			defer wg.Done()
			entries, total, err := a.fetchAdminAuditSource(ctx, base, f, window)
			results[i+1] = adminAuditSourceResult{name: name, entries: entries, total: total, err: err}
		}(i, src.name, src.url)
	}
	wg.Wait()
	return results
}

func (a *Auth) fetchAdminAuditSource(ctx context.Context, endpoint string, f store.AdminAuditFilter, window int64) ([]store.AdminAuditRecord, int64, error) {
	ctx, cancel := context.WithTimeout(ctx, adminAuditSourceTimeout)
	defer cancel()
	q := url.Values{}
	q.Set("limit", strconv.FormatInt(window, 10))
	if f.ActorID != "" {
		q.Set("actor_id", f.ActorID)
	}
	if f.Action != "" {
		q.Set("action", f.Action)
	}
	if f.TargetID != "" {
		q.Set("target_id", f.TargetID)
	}
	if f.From != nil {
		q.Set("from", f.From.Format(time.RFC3339Nano))
	}
	if f.To != nil {
		q.Set("to", f.To.Format(time.RFC3339Nano))
	}
	// #nosec G704 //nolint:gosec -- endpoint is built from trusted internal config (service URLs)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint+"?"+q.Encode(), nil)
	if err != nil {
		return nil, 0, err
	}
	req.Header.Set("X-Internal-Token", a.internalServiceToken)
	client := a.auditClient
	if client == nil {
		client = http.DefaultClient
	}
	// #nosec G704 //nolint:gosec -- endpoint is trusted internal config
	resp, err := client.Do(req)
	if err != nil {
		return nil, 0, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, 0, fmt.Errorf("status %d", resp.StatusCode)
	}
	var body struct {
		Entries []store.AdminAuditRecord `json:"entries"`
		Total   int64                    `json:"total"`
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, 8<<20)).Decode(&body); err != nil {
		return nil, 0, fmt.Errorf("decode: %w", err)
	}
	return body.Entries, body.Total, nil
}
