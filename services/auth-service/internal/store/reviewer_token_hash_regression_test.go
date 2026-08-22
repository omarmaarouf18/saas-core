package store

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"strings"
	"testing"

	"github.com/project/auth-service/internal/models"
)

// TestReviewerTokenHashedAtRest reproduces the plaintext-token defect:
// reviewer bearer tokens were stored verbatim in MongoDB, so any database
// dump/compromise yielded every reviewer credential. Tokens must be stored
// as SHA-256 digests while lookups keep accepting the raw token.
//
// Pre-fix expectation: the raw token is found in the persisted document.
// Post-fix expectation: only the digest is stored; raw lookup still works.
func TestReviewerTokenHashedAtRest(t *testing.T) {
	s, cleanup := setupTestStore(t)
	if s == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	rawToken := "rvw-plaintext-secret-0123456789abcdef"

	if err := s.AddReviewer(ctx, &models.Reviewer{
		ID:    "rev-hash-1",
		Token: rawToken,
		Name:  "Regression Reviewer",
	}); err != nil {
		t.Fatalf("AddReviewer: %v", err)
	}

	var doc struct {
		Token string `bson:"token"`
	}
	if err := s.DatabaseForTesting().Collection("reviewers").
		FindOne(ctx, map[string]any{"_id": "rev-hash-1"}).Decode(&doc); err != nil {
		t.Fatalf("raw read: %v", err)
	}

	sum := sha256.Sum256([]byte(rawToken))
	wantDigest := hex.EncodeToString(sum[:])

	if strings.Contains(doc.Token, rawToken) || doc.Token == rawToken {
		t.Errorf("PLAINTEXT TOKEN AT REST: reviewers collection stores the raw bearer token %q; want digest %q", doc.Token, wantDigest[:12]+"...")
	}
	if doc.Token != wantDigest {
		t.Errorf("stored token %q is not the SHA-256 digest %q of the presented credential", doc.Token, wantDigest)
	}

	got, err := s.GetReviewerByToken(ctx, rawToken)
	if err != nil || got == nil {
		t.Fatalf("GetReviewerByToken with raw token failed: %v (lookup must hash before querying)", err)
	}
	if got.ID != "rev-hash-1" {
		t.Errorf("wrong reviewer resolved: %s", got.ID)
	}
}
