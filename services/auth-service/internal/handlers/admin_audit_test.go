package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/project/auth-service/internal/models"
)

func TestAdminAudit_Authentication(t *testing.T) {
	a, s, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	validToken := "reviewer-test-audit-token"
	rev := &models.Reviewer{
		ID:    "rev-audit-admin",
		Name:  "Audit Reviewer",
		Token: validToken,
	}
	if err := s.AddReviewer(ctx, rev); err != nil {
		t.Fatalf("failed to add reviewer: %v", err)
	}

	t.Run("Missing Internal Token", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/admin/audit", nil)
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		a.AdminGetAuditLogs(rec, req)
		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("expected 401, got %d", rec.Code)
		}
	})

	t.Run("Missing Reviewer Token", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/admin/audit", nil)
		req.Header.Set("X-Internal-Token", "mock-internal-token")
		rec := httptest.NewRecorder()
		a.AdminGetAuditLogs(rec, req)
		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("expected 401, got %d", rec.Code)
		}
	})

	t.Run("Invalid Reviewer Token", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/admin/audit", nil)
		req.Header.Set("X-Internal-Token", "mock-internal-token")
		req.Header.Set("X-Reviewer-Token", "invalid-token")
		rec := httptest.NewRecorder()
		a.AdminGetAuditLogs(rec, req)
		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("expected 401, got %d", rec.Code)
		}
	})

	t.Run("Valid Reviewer Token", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/admin/audit", nil)
		req.Header.Set("X-Internal-Token", "mock-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		a.AdminGetAuditLogs(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 OK, got %d: %s", rec.Code, rec.Body.String())
		}
	})
}

func TestAdminAudit_Filtering(t *testing.T) {
	a, s, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	validToken := "reviewer-filter-token"
	rev := &models.Reviewer{
		ID:    "rev-filter-admin",
		Name:  "Filter Reviewer",
		Token: validToken,
	}
	if err := s.AddReviewer(ctx, rev); err != nil {
		t.Fatalf("failed to add reviewer: %v", err)
	}

	now := time.Now().UTC()
	todayStr := now.Format("2006-01-02")

	// Seed 4 audit entries
	e1 := models.AuditEntry{
		ID:         "audit-1",
		EmployeeID: "rev-alice",
		TenantID:   "user-100",
		Action:     "KYC_REVIEWED",
		Timestamp:  now.Add(-1 * time.Hour),
	}
	e2 := models.AuditEntry{
		ID:         "audit-2",
		EmployeeID: "rev-bob",
		TenantID:   "user-200",
		Action:     "ACCOUNT_SUSPENDED",
		Timestamp:  now.Add(-2 * time.Hour),
	}
	e3 := models.AuditEntry{
		ID:         "audit-3",
		EmployeeID: "rev-alice",
		TenantID:   "user-200",
		Action:     "ACCOUNT_REACTIVATED",
		Timestamp:  now.Add(-26 * time.Hour), // yesterday
	}
	e4 := models.AuditEntry{
		ID:         "audit-4",
		EmployeeID: "driver-joe",
		TenantID:   "tenant-org-5",
		Action:     "JOB_COMPLETED",
		Timestamp:  now.Add(-72 * time.Hour), // 3 days ago
	}

	for _, entry := range []models.AuditEntry{e1, e2, e3, e4} {
		if err := s.AppendAudit(ctx, entry); err != nil {
			t.Fatalf("failed to append audit: %v", err)
		}
	}

	callAudit := func(query string) models.AdminAuditResponse {
		url := "/admin/audit"
		if query != "" {
			url += "?" + query
		}
		req := httptest.NewRequest(http.MethodGet, url, nil)
		req.Header.Set("X-Internal-Token", "mock-internal-token")
		req.Header.Set("X-Reviewer-Token", validToken)
		rec := httptest.NewRecorder()
		a.AdminGetAuditLogs(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
		}
		var resp models.AdminAuditResponse
		if err := json.NewDecoder(rec.Body).Decode(&resp); err != nil {
			t.Fatalf("failed to decode: %v", err)
		}
		return resp
	}

	t.Run("No filters returns all", func(t *testing.T) {
		resp := callAudit("")
		if resp.Total != 4 {
			t.Fatalf("expected total 4, got %d", resp.Total)
		}
		if len(resp.AuditLogs) != 4 {
			t.Fatalf("expected 4 logs, got %d", len(resp.AuditLogs))
		}
		if resp.StorageNotice == "" {
			t.Fatalf("expected non-empty storage_notice")
		}
		// Confirm newest first ordering: e1 (-1h) should be first
		if resp.AuditLogs[0].ID != "audit-1" {
			t.Fatalf("expected first entry audit-1, got %s", resp.AuditLogs[0].ID)
		}
	})

	t.Run("Filter by actor", func(t *testing.T) {
		resp := callAudit("actor=rev-alice")
		if resp.Total != 2 {
			t.Fatalf("expected total 2 for rev-alice, got %d", resp.Total)
		}
		for _, log := range resp.AuditLogs {
			if log.ActorID != "rev-alice" {
				t.Fatalf("unexpected actor: %s", log.ActorID)
			}
		}
	})

	t.Run("Filter by action", func(t *testing.T) {
		resp := callAudit("action=ACCOUNT_SUSPENDED")
		if resp.Total != 1 {
			t.Fatalf("expected total 1, got %d", resp.Total)
		}
		if resp.AuditLogs[0].ID != "audit-2" {
			t.Fatalf("expected audit-2, got %s", resp.AuditLogs[0].ID)
		}
	})

	t.Run("Filter by target_id", func(t *testing.T) {
		resp := callAudit("target_id=user-200")
		if resp.Total != 2 {
			t.Fatalf("expected total 2 for user-200, got %d", resp.Total)
		}
		for _, log := range resp.AuditLogs {
			if log.TargetID != "user-200" {
				t.Fatalf("unexpected target: %s", log.TargetID)
			}
		}
	})

	t.Run("Filter by single date (today)", func(t *testing.T) {
		resp := callAudit("date=" + todayStr)
		if resp.Total != 2 { // e1 and e2 are from today
			t.Fatalf("expected total 2 for today, got %d", resp.Total)
		}
	})

	t.Run("Filter by date range", func(t *testing.T) {
		start := now.Add(-48 * time.Hour).Format(time.RFC3339)
		end := now.Add(-12 * time.Hour).Format(time.RFC3339)
		resp := callAudit("start_date=" + start + "&end_date=" + end)
		if resp.Total != 1 { // only e3 (-26h) fits in this window
			t.Fatalf("expected total 1 for date range, got %d", resp.Total)
		}
		if resp.AuditLogs[0].ID != "audit-3" {
			t.Fatalf("expected audit-3, got %s", resp.AuditLogs[0].ID)
		}
	})
}

func TestAdminAudit_Pagination(t *testing.T) {
	a, s, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	validToken := "reviewer-page-token"
	rev := &models.Reviewer{
		ID:    "rev-page-admin",
		Name:  "Page Reviewer",
		Token: validToken,
	}
	if err := s.AddReviewer(ctx, rev); err != nil {
		t.Fatalf("failed to add reviewer: %v", err)
	}

	now := time.Now().UTC()
	for i := 1; i <= 6; i++ {
		e := models.AuditEntry{
			ID:         string(rune('a' + i - 1)),
			EmployeeID: "rev-page-admin",
			TenantID:   "tenant-page",
			Action:     "KYC_REVIEWED",
			Timestamp:  now.Add(time.Duration(-i) * time.Hour),
		}
		if err := s.AppendAudit(ctx, e); err != nil {
			t.Fatalf("failed to append: %v", err)
		}
	}

	req1 := httptest.NewRequest(http.MethodGet, "/admin/audit?page=1&limit=2", nil)
	req1.Header.Set("X-Internal-Token", "mock-internal-token")
	req1.Header.Set("X-Reviewer-Token", validToken)
	rec1 := httptest.NewRecorder()
	a.AdminGetAuditLogs(rec1, req1)
	if rec1.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec1.Code)
	}

	var resp1 models.AdminAuditResponse
	_ = json.NewDecoder(rec1.Body).Decode(&resp1)
	if resp1.Total != 6 || len(resp1.AuditLogs) != 2 || resp1.Page != 1 || resp1.Limit != 2 {
		t.Fatalf("unexpected page 1 response: %+v", resp1)
	}

	req2 := httptest.NewRequest(http.MethodGet, "/admin/audit?page=2&limit=2", nil)
	req2.Header.Set("X-Internal-Token", "mock-internal-token")
	req2.Header.Set("X-Reviewer-Token", validToken)
	rec2 := httptest.NewRecorder()
	a.AdminGetAuditLogs(rec2, req2)
	var resp2 models.AdminAuditResponse
	_ = json.NewDecoder(rec2.Body).Decode(&resp2)
	if resp2.Total != 6 || len(resp2.AuditLogs) != 2 || resp2.Page != 2 {
		t.Fatalf("unexpected page 2 response: %+v", resp2)
	}
	if resp2.AuditLogs[0].ID == resp1.AuditLogs[0].ID {
		t.Fatalf("page 2 should not have same first item as page 1")
	}
}

func TestAdminAudit_MethodNotAllowed(t *testing.T) {
	a, _, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	req := httptest.NewRequest(http.MethodPost, "/admin/audit", nil)
	rec := httptest.NewRecorder()
	a.AdminGetAuditLogs(rec, req)
	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("expected 405, got %d", rec.Code)
	}
}
