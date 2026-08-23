package handlers

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/project/user-service/internal/models"
)

// Regression test for QA audit finding Q23 (representative worst site).
//
// Defect class: eight X-Internal-Token comparators lacked the empty-secret
// guard. subtle.ConstantTimeCompare("", "") == 1, so any handler constructed
// with an EMPTY configured internal token authenticated every bearerless
// request as "internal service" — for CompleteJob that means skipping role
// checks entirely and proceeding to escrow release / COD settlement.
// Config loaders fail-fast today; this pins the defense-in-depth invariant
// so a harness/refactor bypassing config.Load() cannot reopen the hole.
func TestCompleteJob_EmptyInternalTokenNeverAuthenticates(t *testing.T) {
	harness := newRatingsRoleHarness(t)
	h := harness.handler
	// Simulate loader-bypass: blank out the configured secret AFTER construction.
	h.internalServiceToken = ""

	svc := seedCompletedWalletJob(t, harness)

	req := httptest.NewRequest("POST", "/users/jobs/complete", bytes.NewReader([]byte(`{"job_id":"`+svc+`"}`)))
	w := httptest.NewRecorder()
	h.CompleteJob(w, req)

	if w.Code == http.StatusOK {
		t.Fatalf("EMPTY-SECRET INTERNAL AUTH ACCEPTED: CompleteJob settled job %q with no token and no requester identity when the configured secret is empty (want rejection)", svc)
	}
	t.Logf("rejected with status %d: %s", w.Code, w.Body.String())
}

// CancelJob twin of the CompleteJob invariant above (QA audit Q23 follow-up:
// the 804c390 batch claimed this site but its diff never touched it — the
// comparator at the "Resolve requester" step stayed unguarded).
//
// Honesty note on exploitability: unlike CompleteJob, a bearerless request
// against an empty-config CancelJob could not move funds even pre-guard,
// because the internal path still routes requester_id through JWT
// resolution and pair-equality against server-stored job parties — a raw
// attacker-chosen ID fails resolution with 401 before any state change.
// This test therefore pins the fail-closed CONTRACT (bearerless request
// must never be classified internal; job and escrow untouched) rather than
// discriminating a pre-fix fund loss. Its value is against future refactors
// that might drop the downstream validation while keeping the loose
// comparator — exactly the defense-in-depth rationale documented for the
// other seven sites.
func TestCancelJob_EmptyInternalTokenNeverAuthenticates(t *testing.T) {
	harness := newRatingsRoleHarness(t)
	h := harness.handler
	// Simulate loader-bypass: blank out the configured secret AFTER construction.
	h.internalServiceToken = ""

	jobID := seedCompletedWalletJob(t, harness)

	req := httptest.NewRequest("POST", "/users/jobs/cancel",
		bytes.NewReader([]byte(`{"job_id":"`+jobID+`","requester_id":"q23-escrow-owner","reason":"q23 invariant probe"}`)))
	w := httptest.NewRecorder()
	h.CancelJob(w, req)

	if w.Code == http.StatusOK {
		t.Fatalf("EMPTY-SECRET INTERNAL AUTH ACCEPTED: CancelJob processed bearerless request for job %q when the configured secret is empty (want rejection)", jobID)
	}
	if job := h.store.GetJob(harness.ctx, jobID); job == nil || job.Status != models.JobStatusActive {
		t.Fatalf("job %q state changed under empty-secret bearerless request: want active, got %+v", jobID, job)
	}
	t.Logf("rejected with status %d: %s", w.Code, w.Body.String())
}

// seedCompletedWalletJob funds and activates a non-COD escrow job, returning its ID.
func seedCompletedWalletJob(t *testing.T, h *ratingsRoleHarness) string {
	t.Helper()
	owner := "q23-escrow-owner"
	h.store.CreateService(h.ctx, &models.Service{
		ID: "svc-q23", TenantID: owner, Name: "T", Category: "delivery",
		TenantBasePrice: 40, Latitude: 30.0444, Longitude: 31.2357,
	})
	if _, err := h.store.GetOrCreateWallet(h.ctx, owner); err != nil {
		t.Fatalf("wallet: %v", err)
	}
	if err := h.store.Deposit(h.ctx, owner, 100); err != nil {
		t.Fatalf("deposit: %v", err)
	}
	jobID := "job-q23-complete"
	if err := h.store.CreateJob(h.ctx, &models.Job{
		ID: jobID, OwnerID: owner, UserID: "cust-q23", ServiceID: "svc-q23",
		Status: models.JobStatusPending, PaymentMethod: "wallet",
		Location:  models.Location{Latitude: 30.0444, Longitude: 31.2357},
		CreatedAt: time.Now().UTC(), UpdatedAt: time.Now().UTC(),
	}); err != nil {
		t.Fatalf("create job: %v", err)
	}
	if err := h.store.LockEscrow(h.ctx, owner, jobID, 40); err != nil {
		t.Fatalf("lock: %v", err)
	}
	if err := h.store.UpdateJobLockedEscrow(h.ctx, jobID, 40); err != nil {
		t.Fatalf("persist lock: %v", err)
	}
	if err := h.store.UpdateJobStatus(h.ctx, jobID, models.JobStatusActive); err != nil {
		t.Fatalf("activate: %v", err)
	}
	return jobID
}
