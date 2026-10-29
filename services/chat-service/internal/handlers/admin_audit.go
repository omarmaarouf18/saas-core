package handlers

import (
	"context"
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"log"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/project/chat-service/internal/store"
	"github.com/project/shared/infra/handlerutil"
)

// Admin audit action names. One scheme across every service:
// "<resource>.<verb>", lower snake case. The full list is in
// docs/api/ADMIN_API.md section 10 (ADMIN-API-FIX).
const (
	auditTicketAccept  = "ticket.accept"
	auditTicketResolve = "ticket.resolve"
)

// adminAuditMaxLimit caps how many records one /internal/admin-audit call
// returns; auth-service pages over the merged result.
const adminAuditMaxLimit = 1000

var adminAuditRequestIDPattern = regexp.MustCompile(`^[A-Za-z0-9._-]{1,64}$`)

// adminAuditRequestID returns the caller's X-Request-ID when it is a safe
// token, else a fresh random id, so every record carries one.
func adminAuditRequestID(r *http.Request) string {
	if rid := strings.TrimSpace(r.Header.Get("X-Request-ID")); adminAuditRequestIDPattern.MatchString(rid) {
		return rid
	}
	return newAdminAuditID()
}

func newAdminAuditID() string {
	b := make([]byte, 12)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

// recordAdminAudit stores one admin audit record in this service's own
// admin_audit collection. It runs after the action succeeded: a failed write
// is logged and shipped as ADMIN_AUDIT_WRITE_FAILED but does not undo the
// action. ShipSecurityEvent calls stay alongside it.
func (c *Chat) recordAdminAudit(r *http.Request, actorID, action, targetType, targetID, reason, details string) {
	if c.store == nil {
		return
	}
	rec := &store.AdminAuditRecord{
		ID:         newAdminAuditID(),
		Source:     "chat-service",
		ActorID:    actorID,
		Action:     action,
		TargetType: targetType,
		TargetID:   targetID,
		Reason:     reason,
		Details:    details,
		RequestID:  adminAuditRequestID(r),
		CreatedAt:  time.Now().UTC(),
	}
	ctx, cancel := context.WithTimeout(context.WithoutCancel(r.Context()), 3*time.Second)
	defer cancel()
	if err := c.store.AppendAdminAudit(ctx, rec); err != nil {
		log.Printf("[ADMIN-AUDIT] failed to persist %s record: %v", action, err)
		handlerutil.ShipSecurityEvent(ctx, "ADMIN_AUDIT_WRITE_FAILED", "chat-service", actorID, "", "action="+action+" target="+targetType+":"+targetID, handlerutil.GetClientIP(r))
	}
}

// parseAdminAuditQuery reads the filter and limit shared by every
// /internal/admin-audit endpoint: actor_id, action, target_id, from, to
// (RFC 3339) and limit (1..1000, default 100).
func parseAdminAuditQuery(r *http.Request) (store.AdminAuditFilter, int64, bool) {
	q := r.URL.Query()
	f := store.AdminAuditFilter{
		ActorID:  strings.TrimSpace(q.Get("actor_id")),
		Action:   strings.TrimSpace(q.Get("action")),
		TargetID: strings.TrimSpace(q.Get("target_id")),
	}
	for key, dst := range map[string]**time.Time{"from": &f.From, "to": &f.To} {
		if v := strings.TrimSpace(q.Get(key)); v != "" {
			t, err := time.Parse(time.RFC3339Nano, v)
			if err != nil {
				return f, 0, false
			}
			t = t.UTC()
			*dst = &t
		}
	}
	limit := int64(100)
	if v := q.Get("limit"); v != "" {
		l, err := strconv.ParseInt(v, 10, 64)
		if err != nil || l < 1 || l > adminAuditMaxLimit {
			return f, 0, false
		}
		limit = l
	}
	return f, limit, true
}

// InternalListAdminAudit serves this service's admin audit records to
// auth-service's merged GET /admin/audit. X-Internal-Token only: the reviewer
// was already authenticated by auth-service.
// GET /chat/internal/admin-audit?actor_id=&action=&target_id=&from=&to=&limit=
func (c *Chat) InternalListAdminAudit(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		handlerutil.WriteJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed, use GET"})
		return
	}
	if c.internalServiceToken == "" || subtle.ConstantTimeCompare([]byte(r.Header.Get("X-Internal-Token")), []byte(c.internalServiceToken)) != 1 {
		handlerutil.WriteJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return
	}
	f, limit, ok := parseAdminAuditQuery(r)
	if !ok {
		handlerutil.WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid filter: from/to must be RFC 3339, limit 1-1000"})
		return
	}
	records, total, err := c.store.ListAdminAudit(r.Context(), f, limit)
	if err != nil {
		handlerutil.WriteSafeError(w, r, http.StatusInternalServerError, handlerutil.ErrCodeInternal, "failed to query admin audit records", err)
		return
	}
	handlerutil.WriteJSON(w, http.StatusOK, map[string]any{"entries": records, "total": total})
}
