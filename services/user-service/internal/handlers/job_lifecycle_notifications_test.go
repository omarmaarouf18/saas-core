package handlers

// BE-GAPS-FIX item 1: every job lifecycle step sends one notification whose
// `type` is the stable event and whose payload carries job_id, to the same
// recipients as before plus job_booked to the owner. There is no in-transit
// step (picked_up is the on-the-way state), so job_in_transit is never sent.

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/project/shared/infra/jwtutil"
	"github.com/project/user-service/internal/models"
)

type capturedNotif struct {
	Type   string   `json:"type"`
	UserID string   `json:"user_id"`
	JobID  string   `json:"job_id"`
	Roles  []string `json:"roles"`
}

type notifCapture struct {
	mu    sync.Mutex
	items []capturedNotif
}

func (c *notifCapture) server(t *testing.T) *httptest.Server {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/notifications/send" {
			raw, _ := io.ReadAll(r.Body)
			var n capturedNotif
			_ = json.Unmarshal(raw, &n)
			c.mu.Lock()
			c.items = append(c.items, n)
			c.mu.Unlock()
		}
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{}`))
	}))
	t.Cleanup(srv.Close)
	return srv
}

// waitFor returns the notifications of type typ for job jobID once count
// of them arrived (the senders are fire-and-forget goroutines).
func (c *notifCapture) waitFor(t *testing.T, jobID, typ string, count int) []capturedNotif {
	t.Helper()
	deadline := time.Now().Add(3 * time.Second)
	for {
		got := c.of(jobID, typ)
		if len(got) >= count || time.Now().After(deadline) {
			return got
		}
		time.Sleep(10 * time.Millisecond)
	}
}

func (c *notifCapture) of(jobID, typ string) []capturedNotif {
	c.mu.Lock()
	defer c.mu.Unlock()
	var out []capturedNotif
	for _, n := range c.items {
		if n.JobID == jobID && n.Type == typ {
			out = append(out, n)
		}
	}
	return out
}

func assertOneNotif(t *testing.T, got []capturedNotif, typ, userID, role string) {
	t.Helper()
	if len(got) != 1 {
		t.Fatalf("%s: expected exactly 1 notification, got %d: %+v", typ, len(got), got)
	}
	if got[0].UserID != userID {
		t.Errorf("%s: user_id = %q, want %q", typ, got[0].UserID, userID)
	}
	found := false
	for _, r := range got[0].Roles {
		if r == role {
			found = true
		}
	}
	if !found {
		t.Errorf("%s: roles %v lack %q", typ, got[0].Roles, role)
	}
}

func TestJobLifecycleNotifications_StableEventsWithJobID(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	s, _, ctx, cleanup := setupClosedStatusHarness(t)
	defer cleanup()

	ownerID, custID, empID := "evt-owner-1", "evt-cust-1", "evt-emp-1"
	u := v2UserServiceWithRoles(t, s, ownerID, empID)
	capture := &notifCapture{}
	u.notificationServiceURL = capture.server(t).URL

	seedClosedStatusSub(t, s, ctx, ownerID, models.PlanPaid, time.Now().UTC().Add(time.Hour))
	mustCreateService(t, s, ctx, &models.Service{
		ID: "svc-evt-1", TenantID: ownerID, Name: "Evt Delivery",
		Category: "delivery", TenantBasePrice: 10.0, TenantPricePerKM: 2.0,
		Latitude: 30.0444, Longitude: 31.2357,
	})
	seedEmp := func() {
		if err := s.UpsertEmployeeLocation(ctx, &models.EmployeeLocation{
			TenantID: ownerID, EmployeeID: empID,
			Latitude: 30.0444, Longitude: 31.2357, UpdatedAt: time.Now().UTC(),
		}); err != nil {
			t.Fatalf("seed UpsertEmployeeLocation: %v", err)
		}
	}
	seedEmp()

	tokenUser, _ := jwtutil.GenerateToken(custID, "user", ownerID, "evt-cust@x.com")
	tokenEmp, _ := jwtutil.GenerateToken(empID, "employee", ownerID, "evt-emp@x.com")
	tokenOwner, _ := jwtutil.GenerateToken(ownerID, "owner", ownerID, "evt-owner@x.com")

	book := func() string {
		t.Helper()
		rec := postClosedStatusTrack(t, u, map[string]any{
			"service_id": "svc-evt-1", "user_id": tokenUser, "payment_method": "cod",
			"location":    map[string]any{"latitude": 30.0444, "longitude": 31.2357},
			"destination": map[string]any{"latitude": 30.05, "longitude": 31.24},
		})
		if rec.Code != http.StatusCreated {
			t.Fatalf("track: expected 201, got %d: %s", rec.Code, rec.Body.String())
		}
		return v2JobID(t, rec, "track")
	}
	post := func(h http.HandlerFunc, path, token string, body map[string]any) {
		t.Helper()
		raw, _ := json.Marshal(body)
		req := httptest.NewRequest("POST", path, strings.NewReader(string(raw)))
		req.Header.Set("Content-Type", "application/json")
		if token != "" {
			req.Header.Set("Authorization", "Bearer "+token)
		}
		rec := httptest.NewRecorder()
		h(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("%s: expected 200, got %d: %s", path, rec.Code, rec.Body.String())
		}
	}

	// 1. Delivery walk: booked -> accepted -> picked up -> delivered.
	jobID := book()
	assertOneNotif(t, capture.waitFor(t, jobID, JobEventBooked, 1), JobEventBooked, ownerID, "owner")

	acceptReq := httptest.NewRequest("POST", fmt.Sprintf("/users/employee/jobs/%s/accept", jobID), nil)
	acceptReq.Header.Set("Authorization", "Bearer "+tokenEmp)
	acceptRec := httptest.NewRecorder()
	u.AcceptJobOffer(acceptRec, acceptReq)
	if acceptRec.Code != http.StatusOK {
		t.Fatalf("accept: expected 200, got %d: %s", acceptRec.Code, acceptRec.Body.String())
	}
	assertOneNotif(t, capture.waitFor(t, jobID, JobEventAccepted, 1), JobEventAccepted, custID, "client")

	post(u.PickupJob, "/users/jobs/pickup", tokenEmp, map[string]any{"job_id": jobID})
	// "client" is the pool notification-service puts customers in.
	assertOneNotif(t, capture.waitFor(t, jobID, JobEventPickedUp, 1), JobEventPickedUp, custID, "client")

	post(u.CompleteJob, "/users/jobs/complete", tokenEmp, map[string]any{"job_id": jobID, "cash_collected": true})
	assertOneNotif(t, capture.waitFor(t, jobID, JobEventDelivered, 1), JobEventDelivered, custID, "client")

	if got := capture.of(jobID, "job_in_transit"); len(got) != 0 {
		t.Errorf("job_in_transit must not be invented: %+v", got)
	}
	if got := capture.of(jobID, JobEventCancelled); len(got) != 0 {
		t.Errorf("a delivered job must not send job_cancelled: %+v", got)
	}

	// 2. Owner cancels a booked job: the customer is told.
	seedEmp()
	jobOwnerCancel := book()
	post(u.CancelJob, "/users/jobs/cancel", tokenOwner, map[string]any{"job_id": jobOwnerCancel, "reason": "closing early"})
	assertOneNotif(t, capture.waitFor(t, jobOwnerCancel, JobEventCancelled, 1), JobEventCancelled, custID, "client")

	// 3. The customer cancels their own job: no notification back to them.
	seedEmp()
	jobCustCancel := book()
	post(u.CancelJob, "/users/jobs/cancel", tokenUser, map[string]any{"job_id": jobCustCancel, "reason": "changed my mind"})
	time.Sleep(200 * time.Millisecond)
	if got := capture.of(jobCustCancel, JobEventCancelled); len(got) != 0 {
		t.Errorf("customer's own cancel must not notify them: %+v", got)
	}
	assertOneNotif(t, capture.waitFor(t, jobCustCancel, JobEventBooked, 1), JobEventBooked, ownerID, "owner")
}
