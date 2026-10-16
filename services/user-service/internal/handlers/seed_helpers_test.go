package handlers

import (
	"context"
	"testing"

	"github.com/project/user-service/internal/models"
	"github.com/project/user-service/internal/store"
)

// mustCreateService seeds svc and fails the test if it was not written.
// store.CreateService only logs insert errors, so reading the document back is
// the only way a test can notice a failed seed (for example an expired ctx)
// instead of later failing with a misleading "service not found" (TST-02).
func mustCreateService(t testing.TB, s *store.MongoDB, ctx context.Context, svc *models.Service) {
	t.Helper()
	s.CreateService(ctx, svc)
	if s.GetServiceByID(ctx, svc.ID) == nil {
		t.Fatalf("seed CreateService %q: not written (ctx err: %v)", svc.ID, ctx.Err())
	}
}
