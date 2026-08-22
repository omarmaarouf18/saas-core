package store

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"strings"
	"testing"
)

// TestSupportAgentTokenHashedAtRest reproduces the plaintext-token defect in
// chat-service: support-agent bearer tokens were stored verbatim AND
// serialized with a json:"token" tag, so a database compromise yielded every
// agent credential and any accidental marshal leaked them.
//
// Pre-fix expectation: raw token found at rest and present in JSON.
// Post-fix expectation: only the SHA-256 digest stored; token never
// serialized; raw-token lookup still resolves.
func TestSupportAgentTokenHashedAtRest(t *testing.T) {
	s, cleanup := setupTestMongoDB(t)
	if s == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	rawToken := "agt-plaintext-secret-0123456789abcdef"

	if err := s.AddSupportAgent(ctx, &SupportAgent{
		ID:              "agent-hash-1",
		Status:          "available",
		AssignedTickets: 0,
		Token:           rawToken,
	}); err != nil {
		t.Fatalf("AddSupportAgent: %v", err)
	}

	var doc struct {
		Token string `bson:"token"`
	}
	if err := s.db.Collection("support_agents").
		FindOne(ctx, map[string]any{"_id": "agent-hash-1"}).Decode(&doc); err != nil {
		t.Fatalf("raw read: %v", err)
	}

	sum := sha256.Sum256([]byte(rawToken))
	wantDigest := hex.EncodeToString(sum[:])

	if doc.Token == rawToken || strings.Contains(doc.Token, rawToken) {
		t.Errorf("PLAINTEXT TOKEN AT REST: support_agents collection stores the raw bearer token; want digest %q...", wantDigest[:12])
	}
	if doc.Token != wantDigest {
		t.Errorf("stored token %q is not the SHA-256 digest of the presented credential", doc.Token)
	}

	got, err := s.GetAgentByToken(ctx, rawToken)
	if err != nil || got == nil {
		t.Fatalf("GetAgentByToken with raw token failed: %v (lookup must hash before querying)", err)
	}
	if got.ID != "agent-hash-1" {
		t.Errorf("wrong agent resolved: %s", got.ID)
	}

	// Serialization-leak guard: the credential must never be marshalled.
	out, _ := json.Marshal(got)
	if strings.Contains(string(out), `"token"`) || strings.Contains(string(out), wantDigest) {
		t.Errorf("TOKEN SERIALIZATION LEAK: marshalled agent contains token material: %s", out)
	}
}
