package handlers

import (
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/project/auth-service/internal/models"
	"github.com/project/auth-service/internal/store"
	"github.com/project/shared/infra/handlerutil"
)

// AdminGetAuditLogs handles GET /admin/audit and GET /auth/admin/audit (ADR-0023).
// Returns merged, paginated audit records with filtering by actor reviewer, action, target id, and date.
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

	filter := store.AuditLogFilter{
		ActorID:   actor,
		Action:    action,
		TargetID:  targetID,
		StartDate: startDate,
		EndDate:   endDate,
	}

	entries, total, err := a.store.ListAuditLogs(ctx, filter, page, limit)
	if err != nil {
		handlerutil.WriteSafeError(w, r, http.StatusInternalServerError, handlerutil.ErrCodeInternal, "failed to query audit logs", err)
		return
	}

	items := make([]models.AdminAuditItem, 0, len(entries))
	for _, e := range entries {
		items = append(items, models.AdminAuditItem{
			ID:         e.ID,
			ActorID:    e.EmployeeID,
			EmployeeID: e.EmployeeID,
			Action:     e.Action,
			TargetID:   e.TenantID,
			TenantID:   e.TenantID,
			Timestamp:  e.Timestamp,
		})
	}

	handlerutil.ShipSecurityEvent(ctx, "ADMIN_AUDIT_VIEWED", "auth-service", reviewer.ID, "", fmt.Sprintf("viewed audit logs page=%d limit=%d total=%d", page, limit, total), handlerutil.GetClientIP(r))

	writeJSON(w, http.StatusOK, models.AdminAuditResponse{
		AuditLogs:     items,
		Entries:       items,
		Total:         total,
		Page:          page,
		Limit:         limit,
		StorageNotice: "User and chat security events are streamed to CloudWatch/logs and not stored in MongoDB; returning audit records from auth-service audit_log",
	})
}
