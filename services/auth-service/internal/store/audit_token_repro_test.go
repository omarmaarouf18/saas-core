package store

import (
	"context"
	"regexp"
	"sync"
	"testing"
	"time"

	"github.com/project/auth-service/internal/models"
)

func TestUpsertDeviceToken_ConcurrentNoDuplicates(t *testing.T) {
	s, cleanup := setupTestStore(t)
	if s == nil {
		return
	}
	defer cleanup()

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	user := &models.User{
		ID:        "user-fcm-test",
		Email:     "fcm-test@example.com",
		Username:  "fcmuser",
		Role:      models.RoleUser,
		CreatedAt: time.Now().UTC(),
	}
	if err := s.CreateUser(ctx, user); err != nil {
		t.Fatalf("failed to create user: %v", err)
	}

	const tokenStr = "device-token-unique-xyz-123"
	const concurrency = 20
	var wg sync.WaitGroup
	errCh := make(chan error, concurrency)

	wg.Add(concurrency)
	for i := 0; i < concurrency; i++ {
		go func() {
			defer wg.Done()
			if err := s.UpsertDeviceToken(ctx, user.ID, tokenStr, "android"); err != nil {
				errCh <- err
			}
		}()
	}
	wg.Wait()
	close(errCh)

	for err := range errCh {
		t.Errorf("UpsertDeviceToken returned error during concurrency: %v", err)
	}

	refreshed := s.GetByID(ctx, user.ID)
	if refreshed == nil {
		t.Fatalf("user not found after upserts")
	}

	count := 0
	for _, dt := range refreshed.DeviceTokens {
		if dt.Token == tokenStr {
			count++
		}
	}

	if count != 1 {
		t.Fatalf("expected exactly 1 device token entry, got %d: %+v", count, refreshed.DeviceTokens)
	}
}

func TestAppendAudit_CryptoIDAndError(t *testing.T) {
	s, cleanup := setupTestStore(t)
	if s == nil {
		return
	}
	defer cleanup()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	entry := models.AuditEntry{
		EmployeeID: "emp-audit-1",
		TenantID:   "owner-1",
		Action:     "ORDER_DISPATCH",
		Timestamp:  time.Now().UTC(),
		ClientIP:   "192.168.1.50",
	}

	// Should succeed and assign a crypto-random hex ID
	err := s.AppendAudit(ctx, entry)
	if err != nil {
		t.Fatalf("AppendAudit returned error: %v", err)
	}

	logs := s.GetAuditLog(ctx, "owner-1")
	if len(logs) != 1 {
		t.Fatalf("expected 1 audit log entry, got %d", len(logs))
	}

	auditID := logs[0].ID
	matched, matchErr := regexp.MatchString(`^audit-[0-9a-f]{32}$`, auditID)
	if matchErr != nil || !matched {
		t.Errorf("expected crypto random ID format ^audit-[0-9a-f]{32}$, got %q", auditID)
	}

	// Should return error when context is cancelled
	cancelledCtx, cancelNow := context.WithCancel(context.Background())
	cancelNow()

	err = s.AppendAudit(cancelledCtx, models.AuditEntry{
		EmployeeID: "emp-audit-2",
		TenantID:   "owner-1",
		Action:     "FAIL_ACTION",
	})
	if err == nil {
		t.Errorf("expected AppendAudit to fail with cancelled context, got nil")
	}
}
