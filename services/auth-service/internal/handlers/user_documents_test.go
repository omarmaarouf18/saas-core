package handlers

import (
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

func TestGetUserDocuments_ApprovedAndRejectedUsers(t *testing.T) {
	auth, s, cleanup := setupTestAuth(t)
	if auth == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()

	// 1. Seed reviewer
	rawReviewerToken := "reviewer-secret-token-xyz"
	if err := s.AddReviewer(ctx, &models.Reviewer{
		ID:    "rev-test-1",
		Token: rawReviewerToken,
		Name:  "Test Compliance Officer",
	}); err != nil {
		t.Fatalf("failed to add reviewer: %v", err)
	}

	// 2. Upload actual dummy document files into storage so signed URLs can be generated
	docContent := "dummy document content for testing"
	keyApprovedFront := "kyb/approved-owner/id_front.jpg"
	keyApprovedBack := "kyb/approved-owner/id_back.jpg"
	keyApprovedSelfie := "kyb/approved-owner/selfie.jpg"
	keyApprovedProof := "kyb/approved-owner/business_proof.pdf"

	_ = auth.storage.Upload(ctx, keyApprovedFront, strings.NewReader(docContent), "image/jpeg")
	_ = auth.storage.Upload(ctx, keyApprovedBack, strings.NewReader(docContent), "image/jpeg")
	_ = auth.storage.Upload(ctx, keyApprovedSelfie, strings.NewReader(docContent), "image/jpeg")
	_ = auth.storage.Upload(ctx, keyApprovedProof, strings.NewReader(docContent), "application/pdf")

	// Seed approved owner (dropped out of pending queue)
	approvedOwner := &models.User{
		ID:               "approved-owner",
		Email:            "approved@example.com",
		Username:         "approved_owner",
		Role:             models.RoleOwner,
		IsActive:         true,
		KYCStatus:        models.KYCApproved,
		IDFrontDoc:       keyApprovedFront,
		IDBackDoc:        keyApprovedBack,
		SelfieDoc:        keyApprovedSelfie,
		BusinessProofDoc: keyApprovedProof,
		CreatedAt:        time.Now().UTC(),
	}
	if err := s.CreateUser(ctx, approvedOwner); err != nil {
		t.Fatalf("failed to create approved user: %v", err)
	}

	// Seed rejected employee (dropped out of pending queue)
	keyRejectedFront := "kye/rejected-employee/id_front.jpg"
	keyRejectedBack := "kye/rejected-employee/id_back.jpg"
	keyRejectedSelfie := "kye/rejected-employee/selfie.jpg"
	_ = auth.storage.Upload(ctx, keyRejectedFront, strings.NewReader(docContent), "image/jpeg")
	_ = auth.storage.Upload(ctx, keyRejectedBack, strings.NewReader(docContent), "image/jpeg")
	_ = auth.storage.Upload(ctx, keyRejectedSelfie, strings.NewReader(docContent), "image/jpeg")

	rejectedEmployee := &models.User{
		ID:              "rejected-employee",
		Email:           "rejected@example.com",
		Username:        "rejected_employee",
		Role:            models.RoleEmployee,
		IsActive:        true,
		KYEStatus:       models.KYCRejected,
		IDFrontDoc:      keyRejectedFront,
		IDBackDoc:       keyRejectedBack,
		SelfieDoc:       keyRejectedSelfie,
		RejectionReason: "ID blurry",
		CreatedAt:       time.Now().UTC(),
	}
	if err := s.CreateUser(ctx, rejectedEmployee); err != nil {
		t.Fatalf("failed to create rejected user: %v", err)
	}

	// Confirm that the old pending query does NOT return either user (the confirmed root cause)
	pendingUsers, err := s.GetPendingKYBKYE(ctx)
	if err != nil {
		t.Fatalf("failed to query pending KYB/KYE: %v", err)
	}
	for _, pu := range pendingUsers {
		if pu.ID == "approved-owner" || pu.ID == "rejected-employee" {
			t.Fatalf("expected approved/rejected users to drop out of pending query, but found %s", pu.ID)
		}
	}

	// 3. Test: Reviewer retrieves approved user's documents via new endpoint
	req := httptest.NewRequest("GET", "/auth/reviewer/user-documents?user_id=approved-owner&reason=Dispute%20audit%20ticket%20#99", nil)
	req.Header.Set("X-Internal-Token", auth.internalServiceToken)
	req.Header.Set("X-Reviewer-Token", rawReviewerToken)
	rec := httptest.NewRecorder()

	auth.GetUserDocuments(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK for approved user documents, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	var resp struct {
		UserID           string   `json:"user_id"`
		Email            string   `json:"email"`
		Role             string   `json:"role"`
		KYCStatus        string   `json:"kyc_status"`
		IDFrontURL       string   `json:"id_front_url"`
		IDBackURL        string   `json:"id_back_url"`
		SelfieURL        string   `json:"selfie_url"`
		BusinessProofURL string   `json:"business_proof_url"`
		DocumentErrors   []string `json:"document_errors"`
	}
	if err := json.NewDecoder(rec.Body).Decode(&resp); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}

	if resp.UserID != "approved-owner" || resp.KYCStatus != "approved" {
		t.Errorf("unexpected user_id or kyc_status: got %s, %s", resp.UserID, resp.KYCStatus)
	}
	if resp.IDFrontURL == "" || !strings.Contains(resp.IDFrontURL, "token=") {
		t.Errorf("expected valid signed URL for IDFrontURL, got %q", resp.IDFrontURL)
	}
	if resp.IDBackURL == "" || !strings.Contains(resp.IDBackURL, "token=") {
		t.Errorf("expected valid signed URL for IDBackURL, got %q", resp.IDBackURL)
	}
	if resp.SelfieURL == "" || !strings.Contains(resp.SelfieURL, "token=") {
		t.Errorf("expected valid signed URL for SelfieURL, got %q", resp.SelfieURL)
	}
	if resp.BusinessProofURL == "" || !strings.Contains(resp.BusinessProofURL, "token=") {
		t.Errorf("expected valid signed URL for BusinessProofURL, got %q", resp.BusinessProofURL)
	}
	if len(resp.DocumentErrors) > 0 {
		t.Errorf("expected 0 document errors, got %v", resp.DocumentErrors)
	}

	// 4. Test: Reviewer retrieves rejected employee's documents via email lookup
	reqRej := httptest.NewRequest("GET", "/auth/reviewer/user-documents?email=rejected@example.com&reason=Appeal%20re-verification", nil)
	reqRej.Header.Set("X-Internal-Token", auth.internalServiceToken)
	reqRej.Header.Set("X-Reviewer-Token", rawReviewerToken)
	recRej := httptest.NewRecorder()

	auth.GetUserDocuments(recRej, reqRej)
	if recRej.Code != http.StatusOK {
		t.Fatalf("expected 200 OK for rejected user documents, got %d. Body: %s", recRej.Code, recRej.Body.String())
	}

	var respRej struct {
		UserID     string `json:"user_id"`
		KYEStatus  string `json:"kye_status"`
		IDFrontURL string `json:"id_front_url"`
		SelfieURL  string `json:"selfie_url"`
	}
	if err := json.NewDecoder(recRej.Body).Decode(&respRej); err != nil {
		t.Fatalf("failed to decode rejected response: %v", err)
	}
	if respRej.UserID != "rejected-employee" || respRej.KYEStatus != "rejected" {
		t.Errorf("unexpected rejected user response: %+v", respRej)
	}
	if respRej.IDFrontURL == "" || respRej.SelfieURL == "" {
		t.Errorf("expected signed URLs for rejected employee, got %+v", respRej)
	}
}

func TestGetUserDocuments_NonReviewerRejected(t *testing.T) {
	auth, _, cleanup := setupTestAuth(t)
	if auth == nil {
		return
	}
	defer cleanup()

	// 1. Missing reviewer token
	req := httptest.NewRequest("GET", "/auth/reviewer/user-documents?user_id=some-user&reason=testing", nil)
	req.Header.Set("X-Internal-Token", auth.internalServiceToken)
	rec := httptest.NewRecorder()

	auth.GetUserDocuments(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Errorf("expected 401 Unauthorized for missing reviewer token, got %d", rec.Code)
	}

	// 2. Regular user JWT token passed instead of reviewer credentials
	userToken, _ := jwtutil.GenerateToken("regular-user", "customer", "customer", "customer@example.com")
	reqUser := httptest.NewRequest("GET", "/auth/reviewer/user-documents?user_id=some-user&reason=testing", nil)
	reqUser.Header.Set("Authorization", "Bearer "+userToken)
	recUser := httptest.NewRecorder()

	auth.GetUserDocuments(recUser, reqUser)
	if recUser.Code != http.StatusUnauthorized && recUser.Code != http.StatusForbidden {
		t.Errorf("expected 401/403 for customer caller, got %d", recUser.Code)
	}

	// 3. Invalid reviewer token
	reqInv := httptest.NewRequest("GET", "/auth/reviewer/user-documents?user_id=some-user&reason=testing", nil)
	reqInv.Header.Set("X-Internal-Token", auth.internalServiceToken)
	reqInv.Header.Set("X-Reviewer-Token", "fake-token-1234")
	recInv := httptest.NewRecorder()

	auth.GetUserDocuments(recInv, reqInv)
	if recInv.Code != http.StatusUnauthorized {
		t.Errorf("expected 401 Unauthorized for fake reviewer token, got %d", recInv.Code)
	}
}

func TestGetUserDocuments_ValidationAndNotFound(t *testing.T) {
	auth, s, cleanup := setupTestAuth(t)
	if auth == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	rawReviewerToken := "reviewer-token-val"
	_ = s.AddReviewer(ctx, &models.Reviewer{
		ID:    "rev-val-1",
		Token: rawReviewerToken,
		Name:  "Validator Reviewer",
	})

	setAuth := func(r *http.Request) {
		r.Header.Set("X-Internal-Token", auth.internalServiceToken)
		r.Header.Set("X-Reviewer-Token", rawReviewerToken)
	}

	// 1. Missing user_id and email
	req1 := httptest.NewRequest("GET", "/auth/reviewer/user-documents?reason=audit", nil)
	setAuth(req1)
	rec1 := httptest.NewRecorder()
	auth.GetUserDocuments(rec1, req1)
	if rec1.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for missing user_id/email, got %d", rec1.Code)
	}

	// 2. Missing reason
	req2 := httptest.NewRequest("GET", "/auth/reviewer/user-documents?user_id=some-user", nil)
	setAuth(req2)
	rec2 := httptest.NewRecorder()
	auth.GetUserDocuments(rec2, req2)
	if rec2.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for missing reason, got %d", rec2.Code)
	}
	if !strings.Contains(rec2.Body.String(), "reason is required") {
		t.Errorf("expected 'reason is required' error, got %s", rec2.Body.String())
	}

	// 3. Reason too long (>1000 chars)
	longReason := strings.Repeat("x", 1001)
	req3 := httptest.NewRequest("GET", "/auth/reviewer/user-documents?user_id=some-user&reason="+longReason, nil)
	setAuth(req3)
	rec3 := httptest.NewRecorder()
	auth.GetUserDocuments(rec3, req3)
	if rec3.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for reason > 1000 chars, got %d", rec3.Code)
	}

	// 4. Non-existent user -> 404
	req4 := httptest.NewRequest("GET", "/auth/reviewer/user-documents?user_id=non-existent-id&reason=fraud%20check", nil)
	setAuth(req4)
	rec4 := httptest.NewRecorder()
	auth.GetUserDocuments(rec4, req4)
	if rec4.Code != http.StatusNotFound {
		t.Errorf("expected 404 for non-existent user, got %d", rec4.Code)
	}
}
