package handlers

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/project/auth-service/internal/models"
)

// TestAuthenticateReviewer_RawTokenAgainstDigestRow reproduces the production
// onboarding flow end-to-end: a reviewer is issued a RAW token once (printed
// by cmd/onboard-reviewer), AddReviewer stores only its SHA-256 digest, and
// the reviewer later presents the RAW value in X-Reviewer-Token. The stored
// digest must be re-hashed from the presented credential before comparison —
// comparing the stored digest against the raw presentation can never match.
// Existing suites masked this by feeding the post-hash reviewer.Token (the
// digest) back as the header.
func TestAuthenticateReviewer_RawTokenAgainstDigestRow(t *testing.T) {
	a, s, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	rawToken := "raw-reviewer-credential-real-world-flow-0123456789abcdef"
	reviewer := &models.Reviewer{ID: "rev-raw-flow", Name: "Raw Flow Reviewer", Token: rawToken}
	if err := s.AddReviewer(ctx, reviewer); err != nil {
		t.Fatalf("AddReviewer failed: %v", err)
	}

	if reviewer.Token == rawToken {
		t.Fatalf("precondition violated: AddReviewer stored the token in plaintext form")
	}

	req := httptest.NewRequest(http.MethodGet, "/auth/kyb-kye/pending", nil)
	req.Header.Set("X-Internal-Token", a.internalServiceToken)
	req.Header.Set("X-Reviewer-Token", rawToken)
	rec := httptest.NewRecorder()
	a.GetPendingKYBKYESubmissions(rec, req)

	if rec.Code == http.StatusUnauthorized {
		t.Fatalf("RAW credential rejected against digest-at-rest row (HTTP 401): %s", rec.Body.String())
	}
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 for valid raw credential, got %d: %s", rec.Code, rec.Body.String())
	}
}

// Legacy rows written before the at-rest hashing migration store the raw
// token; they must keep authenticating via the plaintext fallback path.
func TestAuthenticateReviewer_LegacyPlaintextRowStillAuthenticates(t *testing.T) {
	a, s, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	legacyRaw := "legacy-plaintext-reviewer-token-pre-migration"
	if _, err := s.DatabaseForTesting().Collection("reviewers").
		InsertOne(context.Background(), &models.Reviewer{ID: "rev-legacy", Name: "Legacy", Token: legacyRaw}); err != nil {
		t.Fatalf("failed to insert legacy plaintext row: %v", err)
	}

	req := httptest.NewRequest(http.MethodGet, "/auth/kyb-kye/pending", nil)
	req.Header.Set("X-Internal-Token", a.internalServiceToken)
	req.Header.Set("X-Reviewer-Token", legacyRaw)
	rec := httptest.NewRecorder()
	a.GetPendingKYBKYESubmissions(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("legacy plaintext credential broke: expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
}
