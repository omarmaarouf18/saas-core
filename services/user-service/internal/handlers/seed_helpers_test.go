package handlers

import (
	"context"
	"testing"

	"github.com/project/user-service/internal/models"
	"github.com/project/user-service/internal/store"
)

// mustCreateService seeds svc and fails the test if it was not written
// (for example an expired ctx), instead of later failing with a misleading
// "service not found" (TST-02).
func mustCreateService(t testing.TB, s *store.MongoDB, ctx context.Context, svc *models.Service) {
	t.Helper()
	if err := s.CreateService(ctx, svc); err != nil {
		t.Fatalf("seed CreateService %q: %v (ctx err: %v)", svc.ID, err, ctx.Err())
	}
}
