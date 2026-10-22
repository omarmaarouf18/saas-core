package handlers

// ADR-0028 item 8: the ratings duplicate-key path must use the v2 driver's
// typed mongo.IsDuplicateKeyError (covers 11000/11001/12582 and the 16460
// E11000 message shape). The handler previously imported the v1 driver
// with string-fallback containment ("11000"/"duplicate key"). The real
// unique (job_id, rated_by) index violation is exercised end-to-end here.
import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/project/shared/infra/jwtutil"
	"github.com/project/shared/infra/testutil"
	"github.com/project/user-service/internal/models"
)

func TestV2RateJob_DuplicateTypedDetection(t *testing.T) {
	ipCounter := 0
	post := func(u *UserService, body map[string]any) *httptest.ResponseRecorder {
		ipCounter++
		raw, _ := json.Marshal(body)
		req := httptest.NewRequest("POST", "/users/jobs/rate", strings.NewReader(string(raw)))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("X-Real-IP", testutil.IP("v2-rating-dup", ipCounter))
		rec := httptest.NewRecorder()
		u.RateJob(rec, req)
		return rec
	}

	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	s, _, ctx, cleanup := setupClosedStatusHarness(t)
	defer cleanup()
	u, _ := trackJobClosedStatusHarness(t, s)

	ownerID, userID := "v2-dup-owner", "v2-dup-cust"
	seedClosedStatusSub(t, s, ctx, ownerID, models.PlanPaid, time.Now().UTC().Add(time.Hour))
	mustCreateService(t, s, ctx, &models.Service{
		ID: "svc-dup", TenantID: ownerID, Name: "Dup Shop",
		Category: "delivery", TenantBasePrice: 10.0, TenantPricePerKM: 1.0,
		Latitude: 30.0444, Longitude: 31.2357,
	})
	job := &models.Job{
		ID:             "dup-job-1",
		ServiceID:      "svc-dup",
		OwnerID:        ownerID,
		UserID:         userID,
		Status:         models.JobStatusCompleted,
		Location:       models.Location{Latitude: 30.0444, Longitude: 31.2357},
		Destination:    models.Location{Latitude: 30.05, Longitude: 31.24},
		PaymentMethod:  "cod",
		BookedDistance: 1.0,
		CreatedAt:      time.Now().UTC(),
	}
	if err := s.CreateJob(ctx, job); err != nil {
		t.Fatalf("seed job: %v", err)
	}

	tokenOwner, _ := jwtutil.GenerateToken(ownerID, "owner", ownerID, "dup-owner@x.com")
	body := map[string]any{
		"job_id":     "dup-job-1",
		"rated_by":   tokenOwner,
		"rated_user": userID,
		"stars":      5,
		"comment":    "great",
	}

	first := post(u, body)
	if first.Code != http.StatusCreated {
		t.Fatalf("first rate: expected 201, got %d: %s", first.Code, first.Body.String())
	}

	second := post(u, body)
	if second.Code != http.StatusConflict {
		t.Fatalf("duplicate rate: expected 409 via typed v2 detection, got %d: %s", second.Code, second.Body.String())
	}
	var resp map[string]any
	_ = json.Unmarshal(second.Body.Bytes(), &resp)
	if resp["message"] != "you have already rated this job" {
		t.Fatalf("duplicate message mismatch: %s", second.Body.String())
	}

	// Sanity: a different job rates fine — the unique index is
	// (job_id, rated_by), not a global one-shot.
	job2 := *job
	job2.ID = "dup-job-2"
	if err := s.CreateJob(ctx, &job2); err != nil {
		t.Fatalf("seed job2: %v", err)
	}
	body2 := map[string]any{
		"job_id":     "dup-job-2",
		"rated_by":   tokenOwner,
		"rated_user": userID,
		"stars":      4,
	}
	third := post(u, body2)
	if third.Code != http.StatusCreated {
		t.Fatalf("second job rate: expected 201, got %d: %s", third.Code, third.Body.String())
	}
}
