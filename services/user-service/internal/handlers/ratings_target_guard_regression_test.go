package handlers

import (
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

// Regression tests for the GetRatings target fall-through (independent QA
// audit finding Q24) — same alias-shadowing class as the fixed GetJob bug.
//
// Defect: GetRatings validated the requester's JWT then DISCARDED the claims;
// the target `user_id` that failed JWT resolution was silently used as the
// raw lookup key. Any authenticated principal could fetch ANY user's rating
// history (including reviewer identities and comment text) by supplying a raw
// victim ID.
//
// Contract under test (hybrid model, QA decision C'):
//   - Business reputation stays publicly queryable by raw ID: owner/employee
//     targets are served to any authenticated requester — this preserves the
//     ADR-0014 directory/marketplace contract (frontend passes widget.tenantId).
//   - CUSTOMER rating histories are private blind-feedback data: a raw
//     customer ID that fails JWT resolution is rejected with 403; the
//     customer's own resolvable token continues to work.
//
// Pre-fix literal failure (repro): "RAW CUSTOMER TARGET LEAKED: status=200,
// ratings=2 for unresolved target 'cust-victim-raw' (reviewer identities and
// comments disclosed without any relationship check)".
func TestGetRatings_RawCustomerTargetRejected_BusinessTargetsStayPublic(t *testing.T) {
	harness := newRatingsRoleHarness(t)
	h, s, ctx := harness.handler, harness.store, harness.ctx

	// Seed ratings against two different targets.
	for _, tc := range []struct{ target, rater string }{
		{"cust-victim-raw", "emp-a"},
		{"cust-victim-raw", "emp-b"},
		{"own-biz-owner", "cust-x"},
	} {
		if err := s.CreateRating(ctx, ratingSeed(harness, tc.target, tc.rater)); err != nil {
			t.Fatalf("seed rating: %v", err)
		}
	}

	requesterToken := harness.tokenFor("cust-requester", "customer")

	get := func(target string) *httptest.ResponseRecorder {
		req := httptest.NewRequest("GET", "/users/ratings?user_id="+target, nil)
		req.Header.Set("Authorization", "Bearer "+requesterToken)
		w := httptest.NewRecorder()
		h.GetRatings(w, req)
		return w
	}

	// 1. Raw business owner target: public reputation, still served.
	if w := get("own-biz-owner"); w.Code != http.StatusOK {
		t.Errorf("business raw target broke: got %d %s, want 200 (ADR-0014 marketplace contract)", w.Code, w.Body.String())
	}

	// 2. Raw customer target: private history must NOT be disclosed.
	var leakedCount int
	if w := get("cust-victim-raw"); w.Code == http.StatusOK {
		var res struct {
			Ratings []map[string]any `json:"ratings"`
		}
		_ = json.Unmarshal(w.Body.Bytes(), &res)
		leakedCount = len(res.Ratings)
		t.Errorf("RAW CUSTOMER TARGET LEAKED: status=%d, ratings=%d for unresolved target 'cust-victim-raw' (reviewer identities and comments disclosed without any relationship check)", w.Code, leakedCount)
	} else if w.Code != http.StatusForbidden {
		t.Errorf("unexpected rejection status for raw customer target: %d, want 403", w.Code)
	}

	// 3. The customer's own JWT-resolvable token still works for their own history.
	ownToken := harness.tokenFor("cust-victim-raw", "customer")
	req := httptest.NewRequest("GET", "/users/ratings?requester_token="+ownToken+"&user_token="+ownToken, nil)
	w := httptest.NewRecorder()
	h.GetRatings(w, req)
	if w.Code != http.StatusOK {
		t.Errorf("own-token access broken: got %d %s, want 200", w.Code, w.Body.String())
	}
}

// --- minimal role-aware harness: mock auth maps cust-* -> customer, emp-* ->
// employee, anything else -> owner (kyc approved) ---

type ratingsRoleHarness struct {
	handler *UserService
	store   *store.MongoDB
	ctx     context.Context
}

func newRatingsRoleHarness(t *testing.T) *ratingsRoleHarness {
	t.Helper()
	secret := "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2"
	os.Setenv("JWT_SECRET", secret)
	jwtutil.Init(secret)
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	t.Cleanup(cancel)

	dbName := fmt.Sprintf("saas_platform_test_q24_%d", time.Now().UnixNano())
	s, err := store.NewMongoDB(ctx, mongoURI, dbName)
	if err != nil {
		t.Skipf("Skipping test: MongoDB not available (%v)", err)
		return nil
	}
	t.Cleanup(func() {
		_ = s.DropDatabase(context.Background())
		s.Close(context.Background())
	})

	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("miniredis: %v", err)
	}
	t.Cleanup(mr.Close)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	t.Cleanup(func() { _ = rdb.Close() })

	mockAuthServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		id := r.URL.Query().Get("id")
		role := "owner"
		switch {
		case strings.HasPrefix(id, "cust-"):
			role = "customer"
		case strings.HasPrefix(id, "emp-"):
			role = "employee"
		}
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]any{
			"id": id, "role": role, "kyc_status": "approved", "is_active": true, "tenant_id": id,
		})
	}))
	t.Cleanup(mockAuthServer.Close)

	cfg := &config.Config{
		AuthServiceURL:         mockAuthServer.URL,
		InternalServiceToken:   "mock-token",
		AllowTestPaymentBypass: true,
		AppEnv:                 "test",
	}
	return &ratingsRoleHarness{handler: NewUserService(s, cfg, rdb), store: s, ctx: ctx}
}

func (h *ratingsRoleHarness) tokenFor(userID, role string) string {
	tok, _ := jwtutil.GenerateToken(userID, role, userID, userID+"@q24.test")
	return tok
}

func ratingSeed(h *ratingsRoleHarness, target, rater string) *models.Rating {
	return &models.Rating{
		ID: "rate-seed-" + rater + "-" + target, JobID: "job-" + rater + target,
		RatedBy: rater, RatedUser: target, Stars: 5,
		CreatedAt: time.Now().UTC(),
	}
}

func TestRateJob_RoleAuthorizationMatrix(t *testing.T) {
	harness := newRatingsRoleHarness(t)
	h, s, ctx := harness.handler, harness.store, harness.ctx

	ownerID := "own-boss-1"
	employeeID := "emp-courier-1"
	customerID := "cust-client-1"
	outsiderID := "cust-outsider-9"

	newJob := func(id, status string) *models.Job {
		return &models.Job{
			ID:         id,
			OwnerID:    ownerID,
			EmployeeID: employeeID,
			UserID:     customerID,
			ServiceID:  "svc-test-1",
			Status:     models.JobStatus(status),
			CreatedAt:  time.Now().UTC(),
			UpdatedAt:  time.Now().UTC(),
		}
	}

	completedJob := newJob("job-completed-matrix", string(models.JobStatusCompleted))
	if err := s.CreateJob(ctx, completedJob); err != nil {
		t.Fatalf("seed completed job: %v", err)
	}

	activeJob := newJob("job-active-matrix", string(models.JobStatusActive))
	if err := s.CreateJob(ctx, activeJob); err != nil {
		t.Fatalf("seed active job: %v", err)
	}

	postRate := func(jobID, raterID, raterRole, targetID string) *httptest.ResponseRecorder {
		token := harness.tokenFor(raterID, raterRole)
		body := fmt.Sprintf(`{"job_id":"%s","rated_by_token":"%s","rated_user":"%s","stars":5,"comment":"Role matrix test"}`,
			jobID, token, targetID)
		req := httptest.NewRequest("POST", "/users/jobs/rate", strings.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		w := httptest.NewRecorder()
		h.RateJob(w, req)
		return w
	}

	// 1. Customer rates Courier (Primary bug: was 403 Forbidden)
	t.Run("Customer rates Courier (201 Created)", func(t *testing.T) {
		job := newJob("job-c-rates-e", string(models.JobStatusCompleted))
		_ = s.CreateJob(ctx, job)
		w := postRate(job.ID, customerID, "customer", employeeID)
		if w.Code != http.StatusCreated {
			t.Errorf("customer rating courier: got %d %s, want 201 Created", w.Code, w.Body.String())
		}
	})

	// 2. Courier rates Customer (was 403 Forbidden)
	t.Run("Courier rates Customer (201 Created)", func(t *testing.T) {
		job := newJob("job-e-rates-c", string(models.JobStatusCompleted))
		_ = s.CreateJob(ctx, job)
		w := postRate(job.ID, employeeID, "employee", customerID)
		if w.Code != http.StatusCreated {
			t.Errorf("courier rating customer: got %d %s, want 201 Created", w.Code, w.Body.String())
		}
	})

	// 3. Customer rates Owner (was 403 Forbidden)
	t.Run("Customer rates Owner (201 Created)", func(t *testing.T) {
		job := newJob("job-c-rates-o", string(models.JobStatusCompleted))
		_ = s.CreateJob(ctx, job)
		w := postRate(job.ID, customerID, "customer", ownerID)
		if w.Code != http.StatusCreated {
			t.Errorf("customer rating owner: got %d %s, want 201 Created", w.Code, w.Body.String())
		}
	})

	// 4. Owner rates Courier (pre-existing authorized path)
	t.Run("Owner rates Courier (201 Created)", func(t *testing.T) {
		job := newJob("job-o-rates-e", string(models.JobStatusCompleted))
		_ = s.CreateJob(ctx, job)
		w := postRate(job.ID, ownerID, "owner", employeeID)
		if w.Code != http.StatusCreated {
			t.Errorf("owner rating courier: got %d %s, want 201 Created", w.Code, w.Body.String())
		}
	})

	// 5. Courier rates Owner (pre-existing authorized path)
	t.Run("Courier rates Owner (201 Created)", func(t *testing.T) {
		job := newJob("job-e-rates-o", string(models.JobStatusCompleted))
		_ = s.CreateJob(ctx, job)
		w := postRate(job.ID, employeeID, "employee", ownerID)
		if w.Code != http.StatusCreated {
			t.Errorf("courier rating owner: got %d %s, want 201 Created", w.Code, w.Body.String())
		}
	})

	// 6. Owner rates Customer (201 Created)
	t.Run("Owner rates Customer (201 Created)", func(t *testing.T) {
		job := newJob("job-o-rates-c", string(models.JobStatusCompleted))
		_ = s.CreateJob(ctx, job)
		w := postRate(job.ID, ownerID, "owner", customerID)
		if w.Code != http.StatusCreated {
			t.Errorf("owner rating customer: got %d %s, want 201 Created", w.Code, w.Body.String())
		}
	})

	// 7. Unauthorized third party (403 Forbidden)
	t.Run("Outsider rates Courier (403 Forbidden)", func(t *testing.T) {
		w := postRate(completedJob.ID, outsiderID, "customer", employeeID)
		if w.Code != http.StatusForbidden {
			t.Errorf("outsider rating courier: got %d %s, want 403 Forbidden", w.Code, w.Body.String())
		}
	})

	// 8. Self-rating attempt (400 Bad Request)
	t.Run("Self-rating rejected (400 Bad Request)", func(t *testing.T) {
		w := postRate(completedJob.ID, employeeID, "employee", employeeID)
		if w.Code != http.StatusBadRequest {
			t.Errorf("self-rating: got %d %s, want 400 Bad Request", w.Code, w.Body.String())
		}
	})

	// 9. Rating non-completed job (400 Bad Request)
	t.Run("Active job rating rejected (400 Bad Request)", func(t *testing.T) {
		w := postRate(activeJob.ID, customerID, "customer", employeeID)
		if w.Code != http.StatusBadRequest {
			t.Errorf("active job rating: got %d %s, want 400 Bad Request", w.Code, w.Body.String())
		}
	})
}
