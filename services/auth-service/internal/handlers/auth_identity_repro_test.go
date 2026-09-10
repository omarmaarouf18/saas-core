package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"github.com/project/auth-service/internal/models"
	"github.com/project/shared/infra/jwtutil"
)

// TestRepro_Q8_ConcurrentConsumePendingSignup tests the atomic consumption of pending signup OTP.
// Pre-fix: s.pendingSignups.FindOne -> DeleteOne has a race window allowing concurrent calls to both read and succeed.
// Post-fix: atomic FindOneAndDelete ensures exactly 1 caller succeeds and the second caller fails.
func TestRepro_Q8_ConcurrentConsumePendingSignup(t *testing.T) {
	_, s, cleanup := setupAuthReproTest(t)
	if s == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	email := "q8-race@test.com"
	otpCode := "888888"
	pending := &models.PendingSignup{
		Email:        email,
		Username:     "q8user",
		Password:     "fakehash",
		Role:         models.RoleUser,
		CreatedAt:    time.Now().UTC(),
		OTPExpiresAt: time.Now().Add(5 * time.Minute),
	}

	if err := s.SetPendingSignup(ctx, email, pending, otpCode); err != nil {
		t.Fatalf("failed to seed pending signup: %v", err)
	}

	var wg sync.WaitGroup
	results := make([]error, 2)

	// Launch 2 concurrent workers attempting to consume the exact same pending signup OTP
	for i := 0; i < 2; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			_, err := s.GetAndConsumePendingSignup(ctx, email, otpCode)
			results[idx] = err
		}(i)
	}
	wg.Wait()

	successCount := 0
	for _, err := range results {
		if err == nil {
			successCount++
		}
	}

	if successCount > 1 {
		t.Errorf("REPRO CONFIRMED Q8: Both concurrent callers consumed the same pending signup OTP! (successCount=%d)", successCount)
	} else if successCount == 1 {
		t.Logf("PASS: Exactly one caller successfully consumed the pending signup OTP (other got: %v)", results)
	} else {
		t.Fatalf("Unexpected: Neither caller succeeded: %v", results)
	}
}

// TestRepro_Q25_GetPublicProfile_AliasAndHeaderHandling tests that GetPublicProfile:
// 1. Accepts requester authentication via standard Authorization: Bearer <token> header.
// 2. Accepts target user via 'user_id' query parameter in addition to 'id' / 'user_token'.
// 3. Resolves a JWT token passed as target id to the underlying UserID.
func TestRepro_Q25_GetPublicProfile_AliasAndHeaderHandling(t *testing.T) {
	a, s, cleanup := setupAuthReproTest(t)
	if a == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	targetUser := &models.User{
		ID:        "target-user-q25",
		Email:     "target@test.com",
		Username:  "PublicTargetName",
		Role:      models.RoleUser,
		IsActive:  true,
		CreatedAt: time.Now().UTC(),
	}
	_ = s.CreateUser(ctx, targetUser)

	requesterToken, _ := jwtutil.GenerateToken("req-user-q25", "user", "", "requester@test.com")

	// Case 1: Authorization Header (Bearer token) without requester_id query param
	t.Run("Requester Auth via Authorization Header", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/auth/user/public-profile?id=target-user-q25", nil)
		req.Header.Set("Authorization", "Bearer "+requesterToken)
		rec := httptest.NewRecorder()

		a.GetPublicProfile(rec, req)

		if rec.Code != http.StatusOK {
			t.Errorf("REPRO CONFIRMED Q25: GetPublicProfile rejected Authorization: Bearer header with status %d: %s", rec.Code, rec.Body.String())
		} else {
			var resp map[string]any
			_ = json.Unmarshal(rec.Body.Bytes(), &resp)
			if resp["username"] != "PublicTargetName" {
				t.Errorf("expected username 'PublicTargetName', got %v", resp["username"])
			}
		}
	})

	// Case 2: Target ID via 'user_id' query parameter
	t.Run("Target via user_id query parameter", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/auth/user/public-profile?user_id=target-user-q25&requester_id="+requesterToken, nil)
		rec := httptest.NewRecorder()

		a.GetPublicProfile(rec, req)

		if rec.Code != http.StatusOK {
			t.Errorf("REPRO CONFIRMED Q25: GetPublicProfile rejected user_id query parameter with status %d: %s", rec.Code, rec.Body.String())
		} else {
			var resp map[string]any
			_ = json.Unmarshal(rec.Body.Bytes(), &resp)
			if resp["username"] != "PublicTargetName" {
				t.Errorf("expected username 'PublicTargetName', got %v", resp["username"])
			}
		}
	})

	// Case 3: Target ID via JWT Token alias
	t.Run("Target via JWT token alias", func(t *testing.T) {
		targetToken, _ := jwtutil.GenerateToken(targetUser.ID, "user", "", targetUser.Email)
		req := httptest.NewRequest(http.MethodGet, "/auth/user/public-profile?user_token="+targetToken+"&requester_id="+requesterToken, nil)
		rec := httptest.NewRecorder()

		a.GetPublicProfile(rec, req)

		if rec.Code != http.StatusOK {
			t.Errorf("REPRO CONFIRMED Q25: GetPublicProfile rejected target JWT token alias with status %d: %s", rec.Code, rec.Body.String())
		} else {
			var resp map[string]any
			_ = json.Unmarshal(rec.Body.Bytes(), &resp)
			if resp["id"] != targetUser.ID || resp["username"] != "PublicTargetName" {
				t.Errorf("expected id %s and username PublicTargetName, got: %v", targetUser.ID, resp)
			}
		}
	})
}
