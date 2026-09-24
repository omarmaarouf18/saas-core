package handlers

// Tests for the employee cancellation-request workflow (ADR-0027):
// request creates pending state without touching job.Status; owner reject
// clears and continues; owner accept cancels through the shared CancelJob
// implementation; 15-minute lazy expiry unassigns + re-dispatches via the
// real cascade; late owner responses are rejected no-ops; escrow is proven
// at the wallet record, not just the HTTP response.

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/project/shared/infra/jwtutil"
	"github.com/project/user-service/internal/config"
	"github.com/project/user-service/internal/models"
	"github.com/project/user-service/internal/store"
	"github.com/redis/go-redis/v9"
)

const cxJWTSecret = "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2"

type cxActors struct {
	owner, emp, emp2, cust, other string
	ownerTok, empTok, emp2Tok     string
}

func setupCancellationTest(t *testing.T) (*UserService, *store.MongoDB, context.Context, cxActors, func()) {
	t.Helper()
	os.Setenv("JWT_SECRET", cxJWTSecret)
	jwtutil.Init(cxJWTSecret)

	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)

	dbName := fmt.Sprintf("saas_cancel_req_test_%d", time.Now().UnixNano())
	s, err := store.NewMongoDB(ctx, mongoURI, dbName)
	if err != nil && mongoURI == "mongodb://localhost:27017" {
		mongoURI = "mongodb://root:devpassword123@localhost:27017/?authSource=admin"
		s, err = store.NewMongoDB(ctx, mongoURI, dbName)
	}
	if err != nil {
		cancel()
		t.Skipf("Skipping cancellation-request tests: MongoDB not available at %s (%v)", mongoURI, err)
		return nil, nil, nil, cxActors{}, func() {}
	}

	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})

	// Minimal mock auth-service: cascade re-dispatch verifies candidates via
	// GET /auth/user?id= (role employee, active, tenant-bound).
	mockAuthServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		id := r.URL.Query().Get("id")
		role := "user"
		if id == "cx-owner-1" {
			role = "owner"
		} else if id == "cx-emp-1" || id == "cx-emp-2" {
			role = "employee"
		}
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]any{
			"id": id, "role": role, "is_active": true, "tenant_id": "cx-owner-1",
		})
	}))

	cfg := &config.Config{
		AuthServiceURL:       mockAuthServer.URL,
		InternalServiceToken: "mock-internal-token",
		AppEnv:               "test",
	}
	u := NewUserService(s, cfg, rdb)

	a := cxActors{owner: "cx-owner-1", emp: "cx-emp-1", emp2: "cx-emp-2", cust: "cx-cust-1", other: "cx-other-1"}
	a.ownerTok, _ = jwtutil.GenerateToken(a.owner, "owner", a.owner, "cx-owner@example.com")
	a.empTok, _ = jwtutil.GenerateToken(a.emp, "employee", a.owner, "cx-emp@example.com")
	a.emp2Tok, _ = jwtutil.GenerateToken(a.emp2, "employee", a.owner, "cx-emp2@example.com")

	cleanup := func() {
		_ = s.DropDatabase(context.Background())
		s.Close(context.Background())
		mr.Close()
		rdb.Close()
		mockAuthServer.Close()
		cancel()
	}
	return u, s, context.Background(), a, cleanup
}

func cxService(t *testing.T, s *store.MongoDB, ctx context.Context, id, owner string) {
	t.Helper()
	s.CreateService(ctx, &models.Service{
		ID: id, TenantID: owner,
		TenantBasePrice: 1.0, TenantPricePerKM: 0.1,
		Latitude: 30.0, Longitude: 30.0,
	})
}

func cxJob(id, owner, cust, emp, svc, payment string, status models.JobStatus) *models.Job {
	return &models.Job{
		ID: id, OwnerID: owner, UserID: cust, EmployeeID: emp, ServiceID: svc,
		Status: status, PaymentMethod: payment,
		Location:    models.Location{Latitude: 30.05, Longitude: 30.05},
		Destination: models.Location{Latitude: 30.10, Longitude: 30.10},
		CreatedAt:   time.Now().UTC(), UpdatedAt: time.Now().UTC(),
	}
}

func cxPost(u *UserService, handler func(http.ResponseWriter, *http.Request), body map[string]any) *httptest.ResponseRecorder {
	raw, _ := json.Marshal(body)
	req := httptest.NewRequest("POST", "/x", bytes.NewReader(raw))
	rec := httptest.NewRecorder()
	handler(rec, req)
	return rec
}

func cxSubmitRequest(t *testing.T, u *UserService, jobID, empToken, reason string) *httptest.ResponseRecorder {
	t.Helper()
	return cxPost(u, u.RequestCancellation, map[string]any{
		"job_id": jobID, "requester_id": empToken, "reason": reason,
	})
}

// TestCancellationRequest_CreatesPendingWithoutStatusChange proves a request
// records pending state while the trip stays exactly as visible as before.
func TestCancellationRequest_CreatesPendingWithoutStatusChange(t *testing.T) {
	u, s, ctx, a, cleanup := setupCancellationTest(t)
	if u == nil {
		return
	}
	defer cleanup()

	_ = s.CreateJob(ctx, cxJob("cx-job-req-1", a.owner, a.cust, a.emp, "cx-svc-1", "cod", models.JobStatusActive))

	rec := cxSubmitRequest(t, u, "cx-job-req-1", a.empTok, "Vehicle broke down")
	if rec.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK for cancellation request, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	job := s.GetJob(ctx, "cx-job-req-1")
	if job == nil {
		t.Fatalf("Job vanished after request")
	}
	if job.Status != models.JobStatusActive {
		t.Errorf("Request must not change job.Status: got %q, want active", job.Status)
	}
	if job.CancellationRequestStatus != "pending" {
		t.Errorf("Expected request status pending, got %q", job.CancellationRequestStatus)
	}
	if job.CancellationRequestReason != "Vehicle broke down" {
		t.Errorf("Expected reason preserved, got %q", job.CancellationRequestReason)
	}
	if job.CancellationRequestedAt == nil {
		t.Errorf("Expected CancellationRequestedAt to be set")
	}
	if job.EmployeeID != a.emp {
		t.Errorf("Employee must stay assigned while pending, got %q", job.EmployeeID)
	}
}

// TestCancellationRequest_RejectClearsAndContinues proves owner reject ends
// the request with a queryable outcome while the job continues normally.
func TestCancellationRequest_RejectClearsAndContinues(t *testing.T) {
	u, s, ctx, a, cleanup := setupCancellationTest(t)
	if u == nil {
		return
	}
	defer cleanup()

	_ = s.CreateJob(ctx, cxJob("cx-job-rej-1", a.owner, a.cust, a.emp, "cx-svc-1", "cod", models.JobStatusActive))
	if rec := cxSubmitRequest(t, u, "cx-job-rej-1", a.empTok, "Need a break"); rec.Code != http.StatusOK {
		t.Fatalf("Setup request failed: %d %s", rec.Code, rec.Body.String())
	}

	rec := cxPost(u, u.RespondCancellation, map[string]any{
		"job_id": "cx-job-rej-1", "requester_id": a.ownerTok, "decision": "decline",
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK for decline, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	job := s.GetJob(ctx, "cx-job-rej-1")
	if job.Status != models.JobStatusActive {
		t.Errorf("Job must continue as active after decline, got %q", job.Status)
	}
	if job.EmployeeID != a.emp {
		t.Errorf("Employee must stay assigned after decline, got %q", job.EmployeeID)
	}
	// Outcome stays queryable (never silently dropped).
	if job.CancellationRequestStatus != "rejected" {
		t.Errorf("Expected queryable rejected outcome, got %q", job.CancellationRequestStatus)
	}
	if job.CancellationRequestReason != "Need a break" {
		t.Errorf("Expected reason preserved after decline, got %q", job.CancellationRequestReason)
	}
}

// TestCancellationRequest_AcceptCancelsWithRefund proves owner accept runs
// the shared CancelJob implementation: real status flip, employee reason
// recorded, and escrow refunded at the wallet record.
func TestCancellationRequest_AcceptCancelsWithRefund(t *testing.T) {
	u, s, ctx, a, cleanup := setupCancellationTest(t)
	if u == nil {
		return
	}
	defer cleanup()

	cxService(t, s, ctx, "cx-svc-2", a.owner)
	_ = s.Deposit(ctx, a.owner, 500.0)
	const locked = 80.0
	escrowJob := cxJob("cx-job-acc-1", a.owner, a.cust, a.emp, "cx-svc-2", "wallet", models.JobStatusActive)
	escrowJob.LockedEscrowAmount = locked
	_ = s.CreateJob(ctx, escrowJob)
	if err := s.LockEscrow(ctx, a.owner, "cx-job-acc-1", locked); err != nil {
		t.Fatalf("escrow lock setup failed: %v", err)
	}
	walBefore := s.GetWallet(ctx, a.owner)

	if rec := cxSubmitRequest(t, u, "cx-job-acc-1", a.empTok, "Family emergency"); rec.Code != http.StatusOK {
		t.Fatalf("Setup request failed: %d %s", rec.Code, rec.Body.String())
	}
	rec := cxPost(u, u.RespondCancellation, map[string]any{
		"job_id": "cx-job-acc-1", "requester_id": a.ownerTok, "decision": "accept",
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK for accept, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	after := s.GetJob(ctx, "cx-job-acc-1")
	if after.Status != models.JobStatusCancelled {
		t.Errorf("Expected job cancelled after accept, got %q", after.Status)
	}
	if after.CancellationReason != "Family emergency" {
		t.Errorf("Expected employee reason recorded, got %q", after.CancellationReason)
	}
	walAfter := s.GetWallet(ctx, a.owner)
	if got := walAfter.WithdrawableBalance - walBefore.WithdrawableBalance; got < locked-0.001 || got > locked+0.001 {
		t.Errorf("Expected withdrawable +%0.2f refund at wallet record, got %+.2f", locked, got)
	}
	if got := walBefore.EscrowBalance - walAfter.EscrowBalance; got < locked-0.001 || got > locked+0.001 {
		t.Errorf("Expected escrow balance -%0.2f at wallet record, got %+.2f", locked, got)
	}
}

// TestCancellationRequest_EmployeeDirectCancelRejected proves employees can
// no longer cancel through POST /users/jobs/cancel (ADR-0027 decision #1).
func TestCancellationRequest_EmployeeDirectCancelRejected(t *testing.T) {
	u, s, ctx, a, cleanup := setupCancellationTest(t)
	if u == nil {
		return
	}
	defer cleanup()

	_ = s.CreateJob(ctx, cxJob("cx-job-role-1", a.owner, a.cust, a.emp, "cx-svc-1", "cod", models.JobStatusActive))
	rec := cxPost(u, u.CancelJob, map[string]any{
		"job_id": "cx-job-role-1", "requester_id": a.empTok, "reason": "trying direct cancel",
	})
	if rec.Code != http.StatusUnauthorized {
		t.Errorf("Expected 401 role rejection for employee direct cancel, got %d. Body: %s", rec.Code, rec.Body.String())
	}
	if job := s.GetJob(ctx, "cx-job-role-1"); job.Status != models.JobStatusActive {
		t.Errorf("Job must be untouched by rejected direct cancel, got %q", job.Status)
	}
}

// cxStalePendingJob seeds a job whose request deadline already passed.
func cxStalePendingJob(t *testing.T, s *store.MongoDB, ctx context.Context, a cxActors, id, payment string, locked float64) {
	t.Helper()
	job := cxJob(id, a.owner, a.cust, a.emp, "cx-svc-3", payment, models.JobStatusActive)
	past := time.Now().UTC().Add(-16 * time.Minute)
	job.CancellationRequestReason = "stale request"
	job.CancellationRequestedAt = &past
	job.CancellationRequestStatus = "pending"
	job.LockedEscrowAmount = locked
	if err := s.CreateJob(ctx, job); err != nil {
		t.Fatalf("Failed to seed stale-pending job: %v", err)
	}
}

// TestCancellationRequest_LazyExpiryUnassignsAndRedispatches proves the
// 15-minute timeout releases the assignment and returns the job to exact
// fresh-dispatch state via the REAL cascade (emp2 gets offered, departed
// emp1 is excluded), with escrow proven at the wallet record.
func TestCancellationRequest_LazyExpiryUnassignsAndRedispatches(t *testing.T) {
	u, s, ctx, a, cleanup := setupCancellationTest(t)
	if u == nil {
		return
	}
	defer cleanup()

	cxService(t, s, ctx, "cx-svc-3", a.owner)
	_ = s.Deposit(ctx, a.owner, 500.0)
	const locked = 80.0
	cxStalePendingJob(t, s, ctx, a, "cx-job-exp-1", "wallet", locked)
	if err := s.LockEscrow(ctx, a.owner, "cx-job-exp-1", locked); err != nil {
		t.Fatalf("escrow lock setup failed: %v", err)
	}
	walBefore := s.GetWallet(ctx, a.owner)

	// Second courier, fresh location: the cascade must find THEM, not emp1.
	_ = s.UpsertEmployeeLocation(ctx, &models.EmployeeLocation{
		TenantID: a.owner, EmployeeID: a.emp2,
		Latitude: 30.051, Longitude: 30.051, UpdatedAt: time.Now().UTC(),
	})

	job := s.GetJob(ctx, "cx-job-exp-1")
	if !u.checkLazyCancellationRequestExpiry(ctx, job) {
		t.Fatalf("Expected lazy expiry to fire on a 16-minute-old pending request")
	}

	after := s.GetJob(ctx, "cx-job-exp-1")
	if after.Status != models.JobStatusPendingDispatch {
		t.Errorf("Trip must NOT cancel on timeout: want pending_dispatch, got %q", after.Status)
	}
	if after.EmployeeID != "" {
		t.Errorf("Departed employee must be unassigned, got %q", after.EmployeeID)
	}
	if after.CancellationRequestStatus != "expired" {
		t.Errorf("Expected request status expired, got %q", after.CancellationRequestStatus)
	}
	// Real cascade: emp2 offered, emp1 excluded.
	if after.CurrentOfferedEmployeeID != a.emp2 {
		t.Errorf("Expected cascade to offer %q, got %q", a.emp2, after.CurrentOfferedEmployeeID)
	}
	excluded := false
	for _, id := range after.OfferedEmployeeIDs {
		if id == a.emp {
			excluded = true
		}
		if id == a.emp2 {
			// emp2 appended by advanceCascade itself
		}
	}
	if !excluded {
		t.Errorf("Departed employee must be in the exclusion list, got %v", after.OfferedEmployeeIDs)
	}
	// Escrow proven at the WALLET record (decision #6): returned + zeroed.
	if after.LockedEscrowAmount != 0 {
		t.Errorf("Expected locked_escrow_amount zeroed, got %.2f (double-refund risk)", after.LockedEscrowAmount)
	}
	walAfter := s.GetWallet(ctx, a.owner)
	if got := walAfter.WithdrawableBalance - walBefore.WithdrawableBalance; got < locked-0.001 || got > locked+0.001 {
		t.Errorf("Expected withdrawable +%.2f at wallet record, got %+.2f", locked, got)
	}
}

// TestCancellationRequest_LateOwnerResponseRejected proves an owner response
// landing after lazy expiry is a no-op with a clear error — never re-applied
// over the reassigned job.
func TestCancellationRequest_LateOwnerResponseRejected(t *testing.T) {
	u, s, ctx, a, cleanup := setupCancellationTest(t)
	if u == nil {
		return
	}
	defer cleanup()

	cxService(t, s, ctx, "cx-svc-3", a.owner)
	cxStalePendingJob(t, s, ctx, a, "cx-job-late-1", "cod", 0)

	// Owner responds WITHOUT any prior read: the handler's own lazy check
	// expires first, so this response is definitionally late.
	rec := cxPost(u, u.RespondCancellation, map[string]any{
		"job_id": "cx-job-late-1", "requester_id": a.ownerTok, "decision": "accept",
	})
	if rec.Code != http.StatusConflict {
		t.Fatalf("Expected 409 for late owner response, got %d. Body: %s", rec.Code, rec.Body.String())
	}
	if body := rec.Body.String(); !strings.Contains(body, "already expired") {
		t.Errorf("Expected clear already-expired message, got %s", body)
	}

	job := s.GetJob(ctx, "cx-job-late-1")
	if job.Status == models.JobStatusCancelled {
		t.Errorf("Late accept must NOT cancel the reassigned job")
	}
	if job.CancellationRequestStatus != "expired" {
		t.Errorf("Expected request left expired, got %q", job.CancellationRequestStatus)
	}
}

// TestCancellationRequest_GetJobEvaluatesExpiry proves the lazy check is
// wired into the single-job read path (mirroring checkLazyPriceProposalExpiry).
func TestCancellationRequest_GetJobEvaluatesExpiry(t *testing.T) {
	u, s, ctx, a, cleanup := setupCancellationTest(t)
	if u == nil {
		return
	}
	defer cleanup()

	cxService(t, s, ctx, "cx-svc-3", a.owner)
	cxStalePendingJob(t, s, ctx, a, "cx-job-get-1", "cod", 0)

	req := httptest.NewRequest("GET", "/users/jobs/get?id=cx-job-get-1&requester_id="+a.ownerTok, nil)
	rec := httptest.NewRecorder()
	u.GetJob(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK from GetJob, got %d. Body: %s", rec.Code, rec.Body.String())
	}
	var resp map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("Failed to decode GetJob response: %v", err)
	}
	if resp["status"] != string(models.JobStatusPendingDispatch) && resp["status"] != string(models.JobStatusUnavailable) {
		t.Errorf("Expected GetJob to reflect expiry (pending_dispatch/unavailable), got %v", resp["status"])
	}
	if resp["cancellation_request_status"] != "expired" {
		t.Errorf("Expected expired request visible to owner, got %v", resp["cancellation_request_status"])
	}
}

// TestCancellationRequest_RateLimited proves the new endpoints carry
// limiters (cancelJobLimiter precedent): rapid abuse ends in 429.
func TestCancellationRequest_RateLimited(t *testing.T) {
	u, s, ctx, a, cleanup := setupCancellationTest(t)
	if u == nil {
		return
	}
	defer cleanup()

	_ = s.CreateJob(ctx, cxJob("cx-job-rl-1", a.owner, a.cust, a.emp, "cx-svc-1", "cod", models.JobStatusActive))
	var last *httptest.ResponseRecorder
	for i := 0; i < 12; i++ {
		last = cxSubmitRequest(t, u, "cx-job-rl-1", a.empTok, "spam")
	}
	if last.Code != http.StatusTooManyRequests {
		t.Errorf("Expected 429 after rapid requests, got %d. Body: %s", last.Code, last.Body.String())
	}
}
