package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"github.com/project/auth-service/internal/models"
	"github.com/project/auth-service/internal/store"
	"golang.org/x/crypto/bcrypt"
)

func TestAdminAudit_Authentication(t *testing.T) {
	a, s, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	validToken := "reviewer-test-audit-token"
	if err := s.AddReviewer(context.Background(), &models.Reviewer{ID: "rev-audit-admin", Name: "Audit Reviewer", Token: validToken}); err != nil {
		t.Fatalf("failed to add reviewer: %v", err)
	}

	cases := []struct {
		name, internal, reviewer string
		want                     int
	}{
		{"Missing Internal Token", "", validToken, http.StatusUnauthorized},
		{"Missing Reviewer Token", "mock-internal-token", "", http.StatusUnauthorized},
		{"Invalid Reviewer Token", "mock-internal-token", "invalid-token", http.StatusUnauthorized},
		{"Valid Reviewer Token", "mock-internal-token", validToken, http.StatusOK},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, "/admin/audit", nil)
			req.RemoteAddr = fmt.Sprintf("10.9.0.%d:1000", len(tc.name))
			if tc.internal != "" {
				req.Header.Set("X-Internal-Token", tc.internal)
			}
			if tc.reviewer != "" {
				req.Header.Set("X-Reviewer-Token", tc.reviewer)
			}
			rec := httptest.NewRecorder()
			a.AdminGetAuditLogs(rec, req)
			if rec.Code != tc.want {
				t.Fatalf("expected %d, got %d: %s", tc.want, rec.Code, rec.Body.String())
			}
		})
	}
}

// auditSourceServer is a fake service admin-audit endpoint that records the
// query and internal token it was called with.
type auditSourceServer struct {
	*httptest.Server
	mu       sync.Mutex
	queries  []string
	internal []string
}

func newAuditSourceServer(t *testing.T, path string, handler func(w http.ResponseWriter, r *http.Request)) *auditSourceServer {
	t.Helper()
	src := &auditSourceServer{}
	src.Server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != path {
			http.NotFound(w, r)
			return
		}
		src.mu.Lock()
		src.queries = append(src.queries, r.URL.RawQuery)
		src.internal = append(src.internal, r.Header.Get("X-Internal-Token"))
		src.mu.Unlock()
		handler(w, r)
	}))
	t.Cleanup(src.Close)
	return src
}

func auditEntriesHandler(records []store.AdminAuditRecord) func(w http.ResponseWriter, r *http.Request) {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{"entries": records, "total": len(records)})
	}
}

// TestAdminAudit_MergesSourcesWithPaginationAndUnavailable checks the
// ADMIN-API-FIX viewer: records from auth-service's own admin_audit and from
// the other services are merged newest first and paginated; a failing source
// and a source slower than the per-source timeout are reported as
// "unavailable" without failing the request; filters and the internal token
// are forwarded to every source.
func TestAdminAudit_MergesSourcesWithPaginationAndUnavailable(t *testing.T) {
	a, s, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()
	ctx := context.Background()

	validToken := "reviewer-merge-token"
	if err := s.AddReviewer(ctx, &models.Reviewer{ID: "rev-merge", Name: "Merge Reviewer", Token: validToken}); err != nil {
		t.Fatalf("failed to add reviewer: %v", err)
	}

	now := time.Now().UTC().Truncate(time.Millisecond)
	rec := func(id, source, action string, ago time.Duration) store.AdminAuditRecord {
		return store.AdminAuditRecord{ID: id, Source: source, ActorID: "rev-alice", Action: action, TargetType: "x", TargetID: "t-" + id, RequestID: "rq-" + id, CreatedAt: now.Add(-ago)}
	}
	for _, r := range []store.AdminAuditRecord{
		rec("auth-1", "auth-service", "account.suspend", 1*time.Minute),
		rec("auth-2", "auth-service", "kyc.review", 5*time.Minute),
	} {
		r := r
		if err := s.AppendAdminAudit(ctx, &r); err != nil {
			t.Fatalf("seed auth record: %v", err)
		}
	}
	user := newAuditSourceServer(t, "/users/internal/admin-audit", auditEntriesHandler([]store.AdminAuditRecord{
		rec("user-1", "user-service", "job.cancel", 2*time.Minute),
		rec("user-2", "user-service", "job.view", 4*time.Minute),
	}))
	gateway := newAuditSourceServer(t, "/admin/internal/audit", auditEntriesHandler([]store.AdminAuditRecord{
		rec("gw-1", "api-gateway", "version.update", 3*time.Minute),
	}))
	chat := newAuditSourceServer(t, "/chat/internal/admin-audit", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	})
	release := make(chan struct{})
	defer close(release)
	notif := newAuditSourceServer(t, "/notifications/internal/admin-audit", func(w http.ResponseWriter, r *http.Request) {
		select {
		case <-release:
		case <-r.Context().Done():
		}
	})
	a.userServiceURL, a.gatewayInternalURL, a.chatServiceURL, a.notificationURL = user.URL, gateway.URL, chat.URL, notif.URL
	a.auditClient = &http.Client{}
	oldTimeout := adminAuditSourceTimeout
	adminAuditSourceTimeout = 300 * time.Millisecond
	defer func() { adminAuditSourceTimeout = oldTimeout }()

	call := func(query string) (int, AdminAuditResponse) {
		req := httptest.NewRequest(http.MethodGet, "/admin/audit?"+query, nil)
		req.Header.Set("X-Internal-Token", "mock-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		w := httptest.NewRecorder()
		a.AdminGetAuditLogs(w, req)
		var resp AdminAuditResponse
		_ = json.Unmarshal(w.Body.Bytes(), &resp)
		return w.Code, resp
	}

	code, page1 := call("limit=2&page=1")
	if code != http.StatusOK {
		t.Fatalf("page 1: expected 200, got %d", code)
	}
	ids := func(r AdminAuditResponse) []string {
		out := []string{}
		for _, e := range r.Entries {
			out = append(out, e.ID)
		}
		return out
	}
	if got := fmt.Sprint(ids(page1)); got != "[auth-1 user-1]" {
		t.Fatalf("page 1 ids = %s, want [auth-1 user-1]", got)
	}
	_, page2 := call("limit=2&page=2")
	if got := fmt.Sprint(ids(page2)); got != "[gw-1 user-2]" {
		t.Fatalf("page 2 ids = %s, want [gw-1 user-2]", got)
	}
	_, page3 := call("limit=2&page=3")
	if got := fmt.Sprint(ids(page3)); got != "[auth-2]" {
		t.Fatalf("page 3 ids = %s, want [auth-2]", got)
	}
	if page1.Total != 5 {
		t.Fatalf("total = %d, want 5 (sum of answering sources)", page1.Total)
	}
	want := map[string]string{
		"auth-service": "ok", "user-service": "ok", "api-gateway": "ok",
		"chat-service": "unavailable", "notification-service": "unavailable",
	}
	for k, v := range want {
		if page1.Sources[k] != v {
			t.Fatalf("sources[%s] = %q, want %q (all: %v)", k, page1.Sources[k], v, page1.Sources)
		}
	}

	// Filters reach every source; window = page*limit.
	_, _ = call("actor_id=rev-alice&action=job.cancel&target_id=t-user-1&from=2026-01-01T00:00:00Z&to=2030-01-01T00:00:00Z&limit=5&page=2")
	user.mu.Lock()
	lastQ, lastTok := user.queries[len(user.queries)-1], user.internal[len(user.internal)-1]
	user.mu.Unlock()
	for _, part := range []string{"actor_id=rev-alice", "action=job.cancel", "target_id=t-user-1", "from=2026-01-01T00%3A00%3A00Z", "to=2030-01-01T00%3A00%3A00Z", "limit=10"} {
		if !bytes.Contains([]byte(lastQ), []byte(part)) {
			t.Fatalf("source query %q missing %q", lastQ, part)
		}
	}
	if lastTok != "mock-internal-token" {
		t.Fatalf("source got X-Internal-Token %q", lastTok)
	}

	// Pages beyond the merge window are rejected rather than silently empty.
	if code, _ := call("limit=100&page=11"); code != http.StatusBadRequest {
		t.Fatalf("deep page: expected 400, got %d", code)
	}
}

// TestAdminAudit_SuspendWritesRecordShownInViewer checks that a reviewer
// mutation in auth-service persists an admin_audit record (actor, action,
// target, reason, request id) that GET /admin/audit then returns.
func TestAdminAudit_SuspendWritesRecordShownInViewer(t *testing.T) {
	a, s, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()
	ctx := context.Background()

	notifSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusOK) }))
	defer notifSrv.Close()
	a.notificationURL = notifSrv.URL

	rawTok := "reviewer-suspend-audit-token"
	if err := s.AddReviewer(ctx, &models.Reviewer{ID: "rev-suspender", Token: rawTok, Name: "Suspender"}); err != nil {
		t.Fatalf("add reviewer: %v", err)
	}
	hash, _ := bcrypt.GenerateFromPassword([]byte("Password123!"), bcrypt.MinCost)
	user := &models.User{
		ID: "audit-target-user", Email: "audit_target@example.com", Username: "audit_target", Password: string(hash),
		Role: models.RoleUser, IsActive: true, AccountStatus: models.AccountStatusActive, CreatedAt: time.Now().UTC(),
	}
	if err := s.CreateUser(ctx, user); err != nil {
		t.Fatalf("create user: %v", err)
	}
	mux := http.NewServeMux()
	a.RegisterRoutes(mux)

	body, _ := json.Marshal(models.SuspendAccountRequest{UserID: user.ID, Reason: "fraud report #42"})
	req := httptest.NewRequest(http.MethodPost, "/auth/accounts/suspend", bytes.NewReader(body))
	req.Header.Set("X-Internal-Token", a.internalServiceToken)
	req.Header.Set("X-Reviewer-Token", rawTok)
	req.Header.Set("X-Request-ID", "req-suspend-1")
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("suspend: expected 200, got %d: %s", w.Code, w.Body.String())
	}

	req = httptest.NewRequest(http.MethodGet, "/admin/audit?action=account.suspend&target_id="+user.ID, nil)
	req.Header.Set("X-Internal-Token", a.internalServiceToken)
	req.Header.Set("X-Reviewer-Token", rawTok)
	w = httptest.NewRecorder()
	mux.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("audit: expected 200, got %d: %s", w.Code, w.Body.String())
	}
	var resp AdminAuditResponse
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(resp.Entries) != 1 {
		t.Fatalf("expected 1 account.suspend record, got %d (%s)", len(resp.Entries), w.Body.String())
	}
	got := resp.Entries[0]
	if got.Source != "auth-service" || got.ActorID != "rev-suspender" || got.Action != "account.suspend" ||
		got.TargetType != "user" || got.TargetID != user.ID || got.Reason != "fraud report #42" || got.RequestID != "req-suspend-1" || got.CreatedAt.IsZero() {
		t.Fatalf("unexpected record: %+v", got)
	}
}
