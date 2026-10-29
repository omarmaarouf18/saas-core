package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/project/gateway/internal/adminaudit"
	"github.com/project/gateway/internal/version"
)

// TestReviewerVersionUpdate_WritesAdminAuditRecord checks that a reviewer
// version policy update persists a version.update admin audit record, that
// a rejected update writes none, and that GET /admin/internal/audit serves the
// records to internal-token callers only (ADMIN-API-FIX).
func TestReviewerVersionUpdate_WritesAdminAuditRecord(t *testing.T) {
	internalToken := "mock-internal-token-audit"
	reviewerToken := "mock-reviewer-token-audit"
	mockAuth := setupMockAuthServer(t, internalToken, reviewerToken)
	defer mockAuth.Close()

	auditStore := adminaudit.NewStore(nil, "")
	handler := ReviewerVersionConfigHandler(internalToken, mockAuth.URL, mockAuth.Client(), version.NewStore(nil, ""), auditStore)

	put := func(reason, downloadURL string) int {
		body, _ := json.Marshal(ReviewerVersionUpdateRequest{
			LatestVersion: "1.3.0", MinimumSupportedVersion: "1.1.0", DownloadURL: downloadURL, Reason: reason,
		})
		req := httptest.NewRequest(http.MethodPut, "/admin/version", bytes.NewReader(body))
		req.Header.Set("X-Internal-Token", internalToken)
		req.Header.Set("X-Reviewer-Token", reviewerToken)
		req.Header.Set("X-Request-ID", "req-version-1")
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)
		return rec.Code
	}
	if code := put("bad host", "https://malicious-site.example.com/app.apk"); code != http.StatusBadRequest {
		t.Fatalf("invalid URL: expected 400, got %d", code)
	}
	if code := put("raise minimum after 1.1 release", "https://github.com/omarmaarouf18/quick-delivery-mobile/releases/latest/download/app.apk"); code != http.StatusOK {
		t.Fatalf("valid update: expected 200, got %d", code)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/admin/internal/audit", adminaudit.ListHandler(internalToken, auditStore))
	noTok := httptest.NewRecorder()
	mux.ServeHTTP(noTok, httptest.NewRequest(http.MethodGet, "/admin/internal/audit", nil))
	if noTok.Code != http.StatusUnauthorized {
		t.Fatalf("internal audit without token: expected 401, got %d", noTok.Code)
	}
	req := httptest.NewRequest(http.MethodGet, "/admin/internal/audit?action=version.update", nil)
	req.Header.Set("X-Internal-Token", internalToken)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	var resp struct {
		Entries []adminaudit.Record `json:"entries"`
		Total   int64               `json:"total"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil || rec.Code != http.StatusOK {
		t.Fatalf("internal audit: %d %s (%v)", rec.Code, rec.Body.String(), err)
	}
	if resp.Total != 1 {
		t.Fatalf("expected exactly 1 record (rejected update writes none), got %d", resp.Total)
	}
	got := resp.Entries[0]
	if got.Source != "api-gateway" || got.ActorID != "rev-ver-123" || got.Action != "version.update" || got.TargetType != "version_policy" ||
		got.TargetID != "global" || got.Reason != "raise minimum after 1.1 release" || got.RequestID != "req-version-1" || got.CreatedAt.IsZero() {
		t.Fatalf("unexpected record: %+v", got)
	}
}
