package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/project/user-service/internal/models"
	"github.com/project/user-service/internal/store"
)

// TestAdminAudit_UserServiceActionsPersistAndServeInternally checks the
// ADMIN-API-FIX audit trail in user-service: an unmasked job view, a job
// cancel and a service hide each write an admin_audit record (actor, action,
// target, reason, request id), and GET /users/internal/admin-audit serves
// them, filtered, to callers with the internal token only.
func TestAdminAudit_UserServiceActionsPersistAndServeInternally(t *testing.T) {
	svc, mongoStore, validToken := setupAdminJobsTestEnv(t)
	if svc == nil {
		return
	}
	ctx := context.Background()
	mux := http.NewServeMux()
	svc.RegisterRoutes(mux)

	testSvc := models.Service{ID: "svc-audit-test", TenantID: "tenant-audit-1", Name: "Audit Delivery", TenantBasePrice: 20, TenantPricePerKM: 5}
	if err := mongoStore.CreateService(ctx, &testSvc); err != nil {
		t.Fatalf("create service: %v", err)
	}
	job := models.Job{ID: "job-audit-test", OwnerID: "tenant-audit-1", UserID: "user-audit-1", ServiceID: testSvc.ID,
		Status: models.JobStatusActive, PaymentMethod: "cod", CreatedAt: time.Now().UTC(), UpdatedAt: time.Now().UTC()}
	if err := mongoStore.CreateJob(ctx, &job); err != nil {
		t.Fatalf("create job: %v", err)
	}

	do := func(method, path, requestID string, body any) *httptest.ResponseRecorder {
		var buf bytes.Buffer
		if body != nil {
			_ = json.NewEncoder(&buf).Encode(body)
		}
		req := httptest.NewRequest(method, path, &buf)
		req.Header.Set("X-Internal-Token", "test-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		if requestID != "" {
			req.Header.Set("X-Request-ID", requestID)
		}
		rec := httptest.NewRecorder()
		mux.ServeHTTP(rec, req)
		return rec
	}

	if rec := do(http.MethodGet, "/admin/jobs/job-audit-test", "req-view-1", nil); rec.Code != http.StatusOK {
		t.Fatalf("job detail: %d %s", rec.Code, rec.Body.String())
	}
	if rec := do(http.MethodPost, "/admin/jobs/job-audit-test/cancel", "req-cancel-1", map[string]string{"reason": "customer asked support to cancel"}); rec.Code != http.StatusOK {
		t.Fatalf("cancel: %d %s", rec.Code, rec.Body.String())
	}
	if rec := do(http.MethodPost, "/admin/services/svc-audit-test/hide", "", map[string]string{"reason": "misleading listing"}); rec.Code != http.StatusOK {
		t.Fatalf("hide: %d %s", rec.Code, rec.Body.String())
	}

	records, total, err := mongoStore.ListAdminAudit(ctx, store.AdminAuditFilter{}, 10)
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if total != 3 {
		t.Fatalf("expected 3 admin audit records, got %d: %+v", total, records)
	}
	byAction := map[string]store.AdminAuditRecord{}
	for _, r := range records {
		byAction[r.Action] = r
		if r.Source != "user-service" || r.ActorID != "reviewer-jobs-admin" || r.RequestID == "" || r.CreatedAt.IsZero() {
			t.Fatalf("incomplete record: %+v", r)
		}
	}
	if r := byAction["job.view"]; r.TargetType != "job" || r.TargetID != "job-audit-test" || r.RequestID != "req-view-1" {
		t.Fatalf("job.view record: %+v", r)
	}
	if r := byAction["job.cancel"]; r.TargetID != "job-audit-test" || r.Reason != "customer asked support to cancel" || r.RequestID != "req-cancel-1" {
		t.Fatalf("job.cancel record: %+v", r)
	}
	if r := byAction["service.hide"]; r.TargetType != "service" || r.TargetID != "svc-audit-test" || r.Reason != "misleading listing" {
		t.Fatalf("service.hide record: %+v", r)
	}

	// A list page that returns an unmasked recipient phone is audited too.
	if err := mongoStore.CreateJob(ctx, &models.Job{ID: "job-audit-phone", OwnerID: "tenant-audit-1", UserID: "user-audit-1", ServiceID: testSvc.ID,
		Status: models.JobStatusActive, PaymentMethod: "cod", Recipient: &models.JobRecipient{Name: "R", Phone: "+201055554444"},
		CreatedAt: time.Now().UTC(), UpdatedAt: time.Now().UTC()}); err != nil {
		t.Fatalf("create job with recipient: %v", err)
	}
	if rec := do(http.MethodGet, "/admin/jobs?job_id=job-audit-phone", "req-search-1", nil); rec.Code != http.StatusOK {
		t.Fatalf("list: %d %s", rec.Code, rec.Body.String())
	}
	searches, _, err := mongoStore.ListAdminAudit(ctx, store.AdminAuditFilter{Action: "job.search"}, 10)
	if err != nil || len(searches) != 1 || searches[0].TargetID != "job-audit-phone" || searches[0].RequestID != "req-search-1" ||
		!strings.Contains(searches[0].Details, "unmasked_phone_jobs=job-audit-phone") {
		t.Fatalf("job.search record: %+v (err %v)", searches, err)
	}

	// Internal endpoint: internal token required; filters apply.
	req := httptest.NewRequest(http.MethodGet, "/users/internal/admin-audit?action=job.cancel", nil)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("internal endpoint without token: expected 401, got %d", rec.Code)
	}
	req = httptest.NewRequest(http.MethodGet, "/users/internal/admin-audit?action=job.cancel&limit=5", nil)
	req.Header.Set("X-Internal-Token", "test-internal-token")
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("internal endpoint: expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	var resp struct {
		Entries []store.AdminAuditRecord `json:"entries"`
		Total   int64                    `json:"total"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if resp.Total != 1 || len(resp.Entries) != 1 || resp.Entries[0].Action != "job.cancel" {
		t.Fatalf("filtered internal list: %+v", resp)
	}
	req = httptest.NewRequest(http.MethodGet, "/users/internal/admin-audit?limit=5000", nil)
	req.Header.Set("X-Internal-Token", "test-internal-token")
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("limit above 1000: expected 400, got %d", rec.Code)
	}
}
