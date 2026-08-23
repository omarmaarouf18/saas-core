package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/project/user-service/internal/models"
	"github.com/redis/go-redis/v9"
)

// countingHook counts Redis commands whose name matches any of the given
// names (e.g. "eval"), letting tests assert whether the throttle Lua script
// ran at all.
type countingHook struct {
	evalCalls atomic.Int64
}

func (h *countingHook) DialHook(next redis.DialHook) redis.DialHook { return next }

func (h *countingHook) ProcessHook(next redis.ProcessHook) redis.ProcessHook {
	return func(ctx context.Context, cmd redis.Cmder) error {
		if strings.EqualFold(cmd.Name(), "eval") || strings.EqualFold(cmd.Name(), "evalsha") {
			h.evalCalls.Add(1)
		}
		return next(ctx, cmd)
	}
}

func (h *countingHook) ProcessPipelineHook(next redis.ProcessPipelineHook) redis.ProcessPipelineHook {
	return func(ctx context.Context, cmds []redis.Cmder) error {
		for _, cmd := range cmds {
			if strings.EqualFold(cmd.Name(), "eval") || strings.EqualFold(cmd.Name(), "evalsha") {
				h.evalCalls.Add(1)
			}
		}
		return next(ctx, cmds)
	}
}

// TestUpdateJobLocation_NoThrottleReservationBeforeAuth reproduces the
// ordering defect: the Redis throttle reservation (Lua EVAL reserving the
// per-job in-flight slot and consuming the minimum-interval budget) executed
// BEFORE requester authentication. Any unauthenticated caller who knows a job
// ID could continuously claim the reservation window, starving the assigned
// employee's legitimate updates with 429s and burning Redis EVAL capacity.
//
// Pre-fix expectation: an unauthenticated request touches the throttle script
// (evalCalls >= 1) before failing auth.
// Post-fix expectation: authentication happens first — zero EVALs on the
// unauthenticated path.
func TestUpdateJobLocation_NoThrottleReservationBeforeAuth(t *testing.T) {
	h, s, ctx := setupCODFeeHarness(t)
	if h == nil {
		return
	}

	// Swap in a hooked Redis client so throttle-script invocations are countable.
	hook := &countingHook{}
	oldRDB := h.rdb
	opts := oldRDB.Options()
	hookedClient := redis.NewClient(&redis.Options{
		Addr:     opts.Addr,
		Username: opts.Username,
		Password: opts.Password,
		DB:       opts.DB,
	})
	hookedClient.AddHook(hook)
	h.rdb = hookedClient
	t.Cleanup(func() { _ = hookedClient.Close(); h.rdb = oldRDB })

	ownerID := "owner-throttle-order"
	s.CreateService(ctx, &models.Service{
		ID: "svc-throttle", TenantID: ownerID, Name: "T", Category: "delivery",
		TenantBasePrice: 10, Latitude: 30.0444, Longitude: 31.2357,
	})
	jobID := "job-throttle-order"
	if err := s.CreateJob(ctx, &models.Job{
		ID: jobID, OwnerID: ownerID, UserID: "cust-throttle", ServiceID: "svc-throttle",
		EmployeeID: "emp-throttle", Status: models.JobStatusActive, PaymentMethod: "cod",
		Location:  models.Location{Latitude: 30.0444, Longitude: 31.2357},
		CreatedAt: time.Now().UTC(), UpdatedAt: time.Now().UTC(),
	}); err != nil {
		t.Fatalf("create job: %v", err)
	}

	body, _ := json.Marshal(map[string]any{
		"job_id":       jobID,
		"requester_id": "not-a-valid-jwt",
		"latitude":     30.05,
		"longitude":    31.24,
	})
	req := httptest.NewRequest("POST", "/users/jobs/location/update", bytes.NewReader(body))
	w := httptest.NewRecorder()
	h.UpdateJobLocation(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 for invalid token, got %d %s", w.Code, w.Body.String())
	}

	if got := hook.evalCalls.Load(); got != 0 {
		t.Fatalf("THROTTLE RESERVATION BEFORE AUTH: unauthenticated request triggered %d throttle EVAL call(s); authentication must precede the reservation", got)
	}
}
