package handlers

// ADR-0021 regression tests:
//   1. Rejecting without a reason returns 400 ("reason is required for
//      rejection") — enforced server-side, not just in the reviewer console.
//   2. A whitespace-only reason is treated as empty.
//   3. A reason over 1000 characters returns 400 (RateJob-parity bound).
//   4. Approving without a reason still succeeds (reason not meaningful there).
//   5. A successful review dispatches an outcome notification to
//      notification-service's POST /notifications/send with the internal token,
//      correct type, tenant_id and user_id targeting.
//   6. A failed dispatch does NOT fail the already-persisted review.

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/project/auth-service/internal/models"
)

func TestReviewKYBKY_RejectRequiresReason(t *testing.T) {
	a, s, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	reviewer := &models.Reviewer{ID: "rev-1", Name: "Reviewer One", Token: "secret-reviewer-token-adr21"}
	if err := s.AddReviewer(ctx, reviewer); err != nil {
		t.Fatalf("AddReviewer failed: %v", err)
	}

	owner := &models.User{
		ID:        "owner-adr21",
		Email:     "adr21-owner@example.com",
		Username:  "adr21_owner",
		Role:      models.RoleOwner,
		TenantID:  "owner-adr21",
		KYCStatus: models.KYCPendingApproval,
	}
	if err := s.CreateUser(ctx, owner); err != nil {
		t.Fatalf("CreateUser(owner) failed: %v", err)
	}

	postReview := func(body map[string]string) *httptest.ResponseRecorder {
		b, _ := json.Marshal(body)
		req := httptest.NewRequest("POST", "/auth/kyb-kye/review", bytes.NewReader(b))
		req.Header.Set("X-Internal-Token", a.internalServiceToken)
		req.Header.Set("X-Reviewer-Token", reviewer.Token)
		rec := httptest.NewRecorder()
		a.ReviewKYBKYESubmissions(rec, req)
		return rec
	}

	// Negative: reject without reason -> 400
	rec := postReview(map[string]string{"user_id": owner.ID, "action": "reject"})
	if rec.Code != http.StatusBadRequest {
		t.Errorf("Expected 400 for reject without reason, got %d. Body: %s", rec.Code, rec.Body.String())
	}
	var errResp map[string]string
	_ = json.NewDecoder(rec.Body).Decode(&errResp)
	if errResp["error"] != "reason is required for rejection" {
		t.Errorf("Expected error %q, got %q", "reason is required for rejection", errResp["error"])
	}

	// Negative: whitespace-only reason -> 400
	rec = postReview(map[string]string{"user_id": owner.ID, "action": "reject", "reason": "   \n\t  "})
	if rec.Code != http.StatusBadRequest {
		t.Errorf("Expected 400 for whitespace-only rejection reason, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// Negative: reason over 1000 chars -> 400
	rec = postReview(map[string]string{"user_id": owner.ID, "action": "reject", "reason": strings.Repeat("x", 1001)})
	if rec.Code != http.StatusBadRequest {
		t.Errorf("Expected 400 for oversized rejection reason, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// The user must still be pending after all rejected validation failures.
	if u := s.GetByID(ctx, owner.ID); u == nil || u.KYCStatus != models.KYCPendingApproval {
		t.Errorf("Expected user to remain pending_super_admin_approval after invalid rejects")
	}

	// Positive: reject WITH reason -> 200 and persisted state.
	rec = postReview(map[string]string{"user_id": owner.ID, "action": "reject", "reason": "documents unreadable"})
	if rec.Code != http.StatusOK {
		t.Errorf("Expected 200 for reject with reason, got %d. Body: %s", rec.Code, rec.Body.String())
	}
	u := s.GetByID(ctx, owner.ID)
	if u == nil || u.KYCStatus != models.KYCRejected || u.RejectionReason != "documents unreadable" {
		t.Errorf("Expected rejected status with persisted reason, got %+v", u)
	}
}

func TestReviewKYBKY_ApproveWithoutReasonStillSucceeds(t *testing.T) {
	a, s, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	reviewer := &models.Reviewer{ID: "rev-2", Name: "Reviewer Two", Token: "secret-reviewer-token-adr21b"}
	if err := s.AddReviewer(ctx, reviewer); err != nil {
		t.Fatalf("AddReviewer failed: %v", err)
	}

	owner := &models.User{
		ID:        "owner-adr21b",
		Email:     "adr21b-owner@example.com",
		Username:  "adr21b_owner",
		Role:      models.RoleOwner,
		TenantID:  "owner-adr21b",
		KYCStatus: models.KYCPendingApproval,
	}
	if err := s.CreateUser(ctx, owner); err != nil {
		t.Fatalf("CreateUser(owner) failed: %v", err)
	}

	b, _ := json.Marshal(map[string]string{"user_id": owner.ID, "action": "approve"})
	req := httptest.NewRequest("POST", "/auth/kyb-kye/review", bytes.NewReader(b))
	req.Header.Set("X-Internal-Token", a.internalServiceToken)
	req.Header.Set("X-Reviewer-Token", reviewer.Token)
	rec := httptest.NewRecorder()
	a.ReviewKYBKYESubmissions(rec, req)

	if rec.Code != http.StatusOK {
		t.Errorf("Expected 200 for approve without reason, got %d. Body: %s", rec.Code, rec.Body.String())
	}
	if u := s.GetByID(ctx, owner.ID); u == nil || u.KYCStatus != models.KYCApproved {
		t.Errorf("Expected approved status, got %+v", u)
	}
}

func TestReviewKYBKY_OutcomeNotificationDispatch(t *testing.T) {
	a, s, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	type capturedRequest struct {
		internalToken string
		payload       map[string]any
	}

	var mu sync.Mutex
	var captured []capturedRequest
	gotToken := make(chan struct{}, 8)

	notifSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/notifications/send" {
			http.NotFound(w, r)
			return
		}
		var payload map[string]any
		_ = json.NewDecoder(r.Body).Decode(&payload)
		mu.Lock()
		captured = append(captured, capturedRequest{
			internalToken: r.Header.Get("X-Internal-Token"),
			payload:       payload,
		})
		mu.Unlock()
		gotToken <- struct{}{}
		w.WriteHeader(http.StatusOK)
		_ = json.NewEncoder(w).Encode(map[string]any{"message": "notification dispatched"})
	}))
	defer notifSrv.Close()
	a.notificationURL = notifSrv.URL

	ctx := context.Background()
	reviewer := &models.Reviewer{ID: "rev-3", Name: "Reviewer Three", Token: "secret-reviewer-token-adr21c"}
	if err := s.AddReviewer(ctx, reviewer); err != nil {
		t.Fatalf("AddReviewer failed: %v", err)
	}

	employee := &models.User{
		ID:        "emp-adr21c",
		Email:     "adr21c-emp@example.com",
		Username:  "adr21c_emp",
		Role:      models.RoleEmployee,
		TenantID:  "tenant-adr21c",
		KYEStatus: models.KYCPendingApproval,
	}
	if err := s.CreateUser(ctx, employee); err != nil {
		t.Fatalf("CreateUser(employee) failed: %v", err)
	}

	b, _ := json.Marshal(map[string]string{"user_id": employee.ID, "action": "reject", "reason": "selfie mismatch"})
	req := httptest.NewRequest("POST", "/auth/kyb-kye/review", bytes.NewReader(b))
	req.Header.Set("X-Internal-Token", a.internalServiceToken)
	req.Header.Set("X-Reviewer-Token", reviewer.Token)
	rec := httptest.NewRecorder()
	a.ReviewKYBKYESubmissions(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("Expected 200 for review, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	select {
	case <-gotToken:
	case <-time.After(3 * time.Second):
		t.Fatalf("notification dispatch never arrived at notification-service stub")
	}

	mu.Lock()
	defer mu.Unlock()
	if len(captured) != 1 {
		t.Fatalf("Expected exactly 1 dispatched notification, got %d", len(captured))
	}
	capReq := captured[0]

	if capReq.internalToken != a.internalServiceToken {
		t.Errorf("Expected X-Internal-Token %q on outbound call, got %q", a.internalServiceToken, capReq.internalToken)
	}
	if capReq.payload["type"] != "kyc_rejected" {
		t.Errorf("Expected notification type kyc_rejected, got %v", capReq.payload["type"])
	}
	if capReq.payload["user_id"] != employee.ID {
		t.Errorf("Expected user_id %q, got %v", employee.ID, capReq.payload["user_id"])
	}
	if capReq.payload["tenant_id"] != employee.TenantID {
		t.Errorf("Expected tenant_id %q, got %v", employee.TenantID, capReq.payload["tenant_id"])
	}
	bodyStr, _ := capReq.payload["body"].(string)
	if bodyStr == "" || !bytes.Contains([]byte(bodyStr), []byte("selfie mismatch")) {
		t.Errorf("Expected notification body to contain the rejection reason, got %q", bodyStr)
	}
}

func TestReviewKYBKY_NotificationFailureDoesNotFailReview(t *testing.T) {
	a, s, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	// Point at a server that always fails: dispatch must be swallowed.
	failSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer failSrv.Close()
	a.notificationURL = failSrv.URL

	ctx := context.Background()
	reviewer := &models.Reviewer{ID: "rev-4", Name: "Reviewer Four", Token: "secret-reviewer-token-adr21d"}
	if err := s.AddReviewer(ctx, reviewer); err != nil {
		t.Fatalf("AddReviewer failed: %v", err)
	}

	owner := &models.User{
		ID:        "owner-adr21d",
		Email:     "adr21d-owner@example.com",
		Username:  "adr21d_owner",
		Role:      models.RoleOwner,
		TenantID:  "owner-adr21d",
		KYCStatus: models.KYCPendingApproval,
	}
	if err := s.CreateUser(ctx, owner); err != nil {
		t.Fatalf("CreateUser(owner) failed: %v", err)
	}

	b, _ := json.Marshal(map[string]string{"user_id": owner.ID, "action": "approve"})
	req := httptest.NewRequest("POST", "/auth/kyb-kye/review", bytes.NewReader(b))
	req.Header.Set("X-Internal-Token", a.internalServiceToken)
	req.Header.Set("X-Reviewer-Token", reviewer.Token)
	rec := httptest.NewRecorder()
	a.ReviewKYBKYESubmissions(rec, req)

	if rec.Code != http.StatusOK {
		t.Errorf("Expected 200 even when notification dispatch fails, got %d. Body: %s", rec.Code, rec.Body.String())
	}
	if u := s.GetByID(ctx, owner.ID); u == nil || u.KYCStatus != models.KYCApproved {
		t.Errorf("Expected approved status persisted despite dispatch failure, got %+v", u)
	}
}
