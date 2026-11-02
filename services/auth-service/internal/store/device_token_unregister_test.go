package store

import (
	"context"
	"testing"
	"time"

	"github.com/project/auth-service/internal/models"
)

// TestRemoveDeviceTokenFromAnyUser_RemovesTokenFromEveryHolder covers
// BE-HARDEN item 3: the stale push token is removed from every user record
// that holds it, and the call is idempotent.
func TestRemoveDeviceTokenFromAnyUser_RemovesTokenFromEveryHolder(t *testing.T) {
	s, cleanup := setupTestStore(t)
	if s == nil {
		return
	}
	defer cleanup()

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	users := []*models.User{
		{ID: "usr-token-holder-a", Email: "token-holder-a@example.com", Username: "tokenholdera", Role: models.RoleUser, IsActive: true, CreatedAt: time.Now().UTC()},
		{ID: "usr-token-holder-b", Email: "token-holder-b@example.com", Username: "tokenholderb", Role: models.RoleUser, IsActive: true, CreatedAt: time.Now().UTC()},
	}
	for _, u := range users {
		if err := s.CreateUser(ctx, u); err != nil {
			t.Fatalf("failed to create user %s: %v", u.ID, err)
		}
	}

	const tokenStr = "device-token-shared-by-two-users"
	if err := s.UpsertDeviceToken(ctx, users[0].ID, tokenStr, "android", ""); err != nil {
		t.Fatalf("failed to register the token for %s: %v", users[0].ID, err)
	}
	if err := s.UpsertDeviceToken(ctx, users[1].ID, tokenStr, "ios", ""); err != nil {
		t.Fatalf("failed to register the token for %s: %v", users[1].ID, err)
	}

	changed, err := s.RemoveDeviceTokenFromAnyUser(ctx, tokenStr)
	if err != nil {
		t.Fatalf("RemoveDeviceTokenFromAnyUser returned an error: %v", err)
	}
	if changed != 2 {
		t.Errorf("expected 2 changed user records, got %d", changed)
	}

	for _, u := range users {
		refreshed := s.GetByID(ctx, u.ID)
		if refreshed == nil {
			t.Fatalf("user %s not found after the token removal", u.ID)
		}
		for _, dt := range refreshed.DeviceTokens {
			if dt.Token == tokenStr {
				t.Errorf("user %s still holds the removed token", u.ID)
			}
		}
	}

	// Idempotent: a token nobody holds any more changes nothing.
	changed, err = s.RemoveDeviceTokenFromAnyUser(ctx, tokenStr)
	if err != nil {
		t.Fatalf("the second RemoveDeviceTokenFromAnyUser returned an error: %v", err)
	}
	if changed != 0 {
		t.Errorf("expected 0 changed user records on the second call, got %d", changed)
	}
}

// TestRemoveDeviceTokenFromAnyUser_RejectsEmptyToken covers BE-HARDEN item 3:
// an empty token is rejected instead of wiping every device token.
func TestRemoveDeviceTokenFromAnyUser_RejectsEmptyToken(t *testing.T) {
	s, cleanup := setupTestStore(t)
	if s == nil {
		return
	}
	defer cleanup()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if _, err := s.RemoveDeviceTokenFromAnyUser(ctx, "   "); err == nil {
		t.Error("expected an error for an empty token, got nil")
	}
}
