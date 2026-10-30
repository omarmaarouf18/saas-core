package handlers

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"log"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/project/auth-service/internal/store"
	"github.com/project/shared/infra/handlerutil"
)

// Admin audit action names. One scheme across every service:
// "<resource>.<verb>", lower snake case. The full list is in
// docs/api/ADMIN_API.md section 10 (ADMIN-API-FIX).
const (
	auditKYCReview         = "kyc.review"
	auditAccountSuspend    = "account.suspend"
	auditAccountReactivate = "account.reactivate"
	auditUserDocumentsView = "user_documents.view"
	auditDocumentView      = "document.view"
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
func (a *Auth) recordAdminAudit(r *http.Request, actorID, action, targetType, targetID, reason, details string) {
	if a.store == nil {
		return
	}
	rec := &store.AdminAuditRecord{
		ID:         newAdminAuditID(),
		Source:     "auth-service",
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
	if err := a.store.AppendAdminAudit(ctx, rec); err != nil {
		log.Printf("[ADMIN-AUDIT] failed to persist %s record: %v", action, err)
		handlerutil.ShipSecurityEvent(ctx, "ADMIN_AUDIT_WRITE_FAILED", "auth-service", actorID, "", "action="+action+" target="+targetType+":"+targetID, handlerutil.GetClientIP(r))
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
