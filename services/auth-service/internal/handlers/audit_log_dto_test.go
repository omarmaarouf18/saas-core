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

	"github.com/project/auth-service/internal/models"
	"github.com/project/shared/infra/jwtutil"
)

// A1: GET /auth/audit-log must serve the client-safe DTO — the response
// JSON must not contain a client_ip key anywhere, while keeping every
// field the owner UI consumes.
func TestGetAuditLog_NoClientIPLeak(t *testing.T) {
	a, s, cleanup := setupTestAuth(t)
	if a == nil {
		t.Skip("setup failed")
		return
	}
	defer cleanup()

	ctx := context.Background()
	owner := &models.User{
		ID:        "owner-noclientip",
		Email:     "owner-noclientip@example.com",
		Username:  "owner_noclientip",
		Role:      models.RoleOwner,
		TenantID:  "owner-noclientip",
		IsActive:  true,
		CreatedAt: time.Now(),
	}
	if err := s.CreateUser(ctx, owner); err != nil {
		t.Fatalf("CreateUser owner failed: %v", err)
	}
	if err := s.AppendAudit(ctx, models.AuditEntry{
		EmployeeID: "emp-noclientip",
		TenantID:   owner.ID,
		Action:     "check_in",
		Timestamp:  time.Now().UTC(),
	}); err != nil {
		t.Fatalf("AppendAudit failed: %v", err)
	}

	token, err := jwtutil.GenerateToken(owner.ID, string(models.RoleOwner), owner.ID, owner.Email)
	if err != nil {
		t.Fatalf("GenerateToken failed: %v", err)
	}

	req := httptest.NewRequest("GET", "/auth/audit-log?tenant_id="+owner.ID+"&requester_id="+token, nil)
	rec := httptest.NewRecorder()
	a.GetAuditLog(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("GetAuditLog: expected 200 OK, got %d. Body: %s", rec.Code, rec.Body.String())
	}
	body := rec.Body.String()
	if strings.Contains(body, "client_ip") {
		t.Errorf("GetAuditLog response leaks client_ip: %s", body)
	}

	var resp struct {
		Count   int              `json:"count"`
		Entries []map[string]any `json:"entries"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode audit-log response: %v", err)
	}
	if resp.Count != 1 || len(resp.Entries) != 1 {
		t.Fatalf("expected exactly 1 entry, got %+v", resp)
	}
	entry := resp.Entries[0]
	for _, key := range []string{"id", "employee_id", "tenant_id", "action", "timestamp"} {
		if _, ok := entry[key]; !ok {
			t.Errorf("DTO missing UI-consumed field %q: %v", key, entry)
		}
	}
	if _, ok := entry["client_ip"]; ok {
		t.Errorf("DTO contains client_ip key: %v", entry)
	}
	if entry["action"] != "check_in" {
		t.Errorf("expected action check_in, got %v", entry["action"])
	}
}

// A1: POST /auth/employee/action echoes the stored entry — the echo must
// likewise carry no client_ip.
func TestSimulateEmployeeAction_NoClientIPLeak(t *testing.T) {
	a, s, cleanup := setupTestAuth(t)
	if a == nil {
		t.Skip("setup failed")
		return
	}
	defer cleanup()

	ctx := context.Background()
	owner := &models.User{
		ID:        "owner-noip",
		Email:     "owner-noip@example.com",
		Username:  "owner_noip",
		Role:      models.RoleOwner,
		TenantID:  "owner-noip",
		IsActive:  true,
		KYCStatus: models.KYCApproved,
		CreatedAt: time.Now(),
	}
	if err := s.CreateUser(ctx, owner); err != nil {
		t.Fatalf("CreateUser owner failed: %v", err)
	}
	emp := &models.User{
		ID:        "emp-noip",
		Email:     "emp-noip@example.com",
		Username:  "emp_noip",
		Role:      models.RoleEmployee,
		TenantID:  owner.ID,
		OwnerID:   owner.ID,
		IsActive:  true,
		CreatedAt: time.Now(),
	}
	if err := s.CreateUser(ctx, emp); err != nil {
		t.Fatalf("CreateUser employee failed: %v", err)
	}

	empToken, err := jwtutil.GenerateToken(emp.ID, string(models.RoleEmployee), owner.ID, emp.Email)
	if err != nil {
		t.Fatalf("GenerateToken failed: %v", err)
	}
	actionBody, _ := json.Marshal(map[string]string{
		"email":  emp.Email,
		"action": "view-jobs",
	})
	req := httptest.NewRequest("POST", "/auth/employee/action", bytes.NewReader(actionBody))
	req.Header.Set("Authorization", "Bearer "+empToken)
	// Simulate a device IP on the wire: it must not come back in the echo.
	req.RemoteAddr = "203.0.113.7:4321"
	rec := httptest.NewRecorder()
	a.SimulateEmployeeAction(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("SimulateEmployeeAction: expected 200 OK, got %d. Body: %s", rec.Code, rec.Body.String())
	}
	body := rec.Body.String()
	if strings.Contains(body, "client_ip") {
		t.Errorf("action echo leaks client_ip: %s", body)
	}
	if strings.Contains(body, "203.0.113.7") {
		t.Errorf("action echo leaks request IP: %s", body)
	}

	// And the persisted entry carries no IP either (nothing reads it).
	logs := s.GetAuditLog(ctx, owner.ID)
	if len(logs) != 1 {
		t.Fatalf("expected 1 stored entry, got %d", len(logs))
	}
	raw, _ := json.Marshal(logs[0])
	if strings.Contains(string(raw), "203.0.113.7") {
		t.Errorf("stored audit entry persists client IP: %s", raw)
	}
}

// A4: GET /auth/audit-log accepts the session JWT via Authorization
// header with no query token. Query fallback keeps working (covered by
// existing tests); this pins the header path.
func TestGetAuditLog_AuthHeader(t *testing.T) {
	a, s, cleanup := setupTestAuth(t)
	if a == nil {
		t.Skip("setup failed")
		return
	}
	defer cleanup()

	ctx := context.Background()
	owner := &models.User{
		ID:        "owner-hdr",
		Email:     "owner-hdr@example.com",
		Username:  "owner_hdr",
		Role:      models.RoleOwner,
		TenantID:  "owner-hdr",
		IsActive:  true,
		CreatedAt: time.Now(),
	}
	if err := s.CreateUser(ctx, owner); err != nil {
		t.Fatalf("CreateUser owner failed: %v", err)
	}
	token, err := jwtutil.GenerateToken(owner.ID, string(models.RoleOwner), owner.ID, owner.Email)
	if err != nil {
		t.Fatalf("GenerateToken failed: %v", err)
	}

	req := httptest.NewRequest("GET", "/auth/audit-log?tenant_id="+owner.ID, nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	a.GetAuditLog(rec, req)
	if rec.Code != http.StatusOK {
		t.Errorf("expected 200 via Authorization header, got %d (%s)", rec.Code, rec.Body.String())
	}
	if strings.Contains(rec.Body.String(), "client_ip") {
		t.Errorf("header-path response leaks client_ip: %s", rec.Body.String())
	}
}

// A4: GET /auth/user accepts the session JWT via Authorization header.
func TestGetUser_AuthHeader(t *testing.T) {
	a, s, cleanup := setupTestAuth(t)
	if a == nil {
		t.Skip("setup failed")
		return
	}
	defer cleanup()

	ctx := context.Background()
	user := &models.User{
		ID:        "user-hdr",
		Email:     "user-hdr@example.com",
		Username:  "user_hdr",
		Role:      models.RoleUser,
		TenantID:  "tenant-hdr",
		IsActive:  true,
		CreatedAt: time.Now(),
	}
	if err := s.CreateUser(ctx, user); err != nil {
		t.Fatalf("CreateUser failed: %v", err)
	}
	token, err := jwtutil.GenerateToken(user.ID, string(models.RoleUser), user.TenantID, user.Email)
	if err != nil {
		t.Fatalf("GenerateToken failed: %v", err)
	}

	req := httptest.NewRequest("GET", "/auth/user", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	a.GetUser(rec, req)
	if rec.Code != http.StatusOK {
		t.Errorf("expected 200 via Authorization header, got %d (%s)", rec.Code, rec.Body.String())
	}
}
func TestAuditEntryResponse_ProjectionShape(t *testing.T) {
	entry := models.AuditEntry{
		ID:         "audit-1",
		EmployeeID: "emp-1",
		TenantID:   "owner-1",
		Action:     "KYC_REVIEWED",
		Timestamp:  time.Date(2026, 9, 28, 12, 0, 0, 0, time.UTC),
	}
	raw, err := json.Marshal(entry.ToResponse())
	if err != nil {
		t.Fatalf("marshal DTO: %v", err)
	}
	var decoded map[string]any
	if err := json.Unmarshal(raw, &decoded); err != nil {
		t.Fatalf("decode DTO: %v", err)
	}
	if len(decoded) != 5 {
		t.Errorf("DTO must expose exactly 5 keys, got %v", decoded)
	}
	for _, key := range []string{"id", "employee_id", "tenant_id", "action", "timestamp"} {
		if _, ok := decoded[key]; !ok {
			t.Errorf("DTO missing %q", key)
		}
	}
}
