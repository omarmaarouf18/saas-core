package handlers

// PUSH-L10N item 2: the senders keep their English title/body (legacy apps)
// and add the named parameters of notification-service's AR/EN push
// templates; money is never "$".

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/project/shared/infra/resilience"
	"github.com/project/user-service/internal/models"
)

type sentNotif struct {
	Type   string            `json:"type"`
	UserID string            `json:"user_id"`
	Title  string            `json:"title"`
	Body   string            `json:"body"`
	Params map[string]string `json:"params"`
}

type sendCapture struct {
	mu    sync.Mutex
	items []sentNotif
}

func newSendCapture(t *testing.T) (*UserService, *sendCapture) {
	t.Helper()
	c := &sendCapture{}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		raw, _ := io.ReadAll(r.Body)
		var n sentNotif
		_ = json.Unmarshal(raw, &n)
		c.mu.Lock()
		c.items = append(c.items, n)
		c.mu.Unlock()
		_, _ = w.Write([]byte(`{}`))
	}))
	t.Cleanup(srv.Close)
	return &UserService{
		notificationServiceURL: srv.URL,
		notificationClient:     resilience.NewClient(http.DefaultClient, "notification-service", 1, 2*time.Second),
	}, c
}

func (c *sendCapture) wait(t *testing.T, n int) []sentNotif {
	t.Helper()
	deadline := time.Now().Add(3 * time.Second)
	for {
		c.mu.Lock()
		got := append([]sentNotif(nil), c.items...)
		c.mu.Unlock()
		if len(got) >= n || time.Now().After(deadline) {
			if len(got) < n {
				t.Fatalf("got %d notifications, want %d", len(got), n)
			}
			c.mu.Lock()
			c.items = nil
			c.mu.Unlock()
			return got
		}
		time.Sleep(5 * time.Millisecond)
	}
}

func TestFormatEGP(t *testing.T) {
	cases := map[float64]string{
		0: "EGP 0", 25: "EGP 25", 25.5: "EGP 25.50", 1250.756: "EGP 1,250.76",
		999.999: "EGP 1,000", 1234567: "EGP 1,234,567", -3.5: "EGP -3.50",
	}
	for in, want := range cases {
		if got := formatEGP(in); got != want {
			t.Errorf("formatEGP(%v) = %q, want %q", in, got, want)
		}
	}
	if got := moneyParam(45.5); got != "45.50" {
		t.Errorf("moneyParam(45.5) = %q", got)
	}
}

func TestSenders_AddTemplateParams(t *testing.T) {
	u, c := newSendCapture(t)
	job := &models.Job{ID: "job-1", OwnerID: "owner-1", UserID: "cust-1", EmployeeID: "emp-1"}

	u.broadcastCourierAccepted(job, 1250.5, false)
	n := c.wait(t, 1)[0]
	if n.Type != "job_accepted" || n.Params["fare"] != "1250.50" || n.Params["variant"] != "" {
		t.Errorf("job_accepted: %+v", n)
	}
	if n.Body != "Your courier has accepted! Final fare: EGP 1,250.50" || strings.Contains(n.Body, "$") {
		t.Errorf("job_accepted legacy body: %q", n.Body)
	}

	u.broadcastCourierAccepted(job, 40, true)
	n = c.wait(t, 1)[0]
	if n.Params["variant"] != "negotiable" || n.Params["fare"] != "40.00" ||
		n.Body != "Your courier has accepted! Suggested fare: EGP 40. Counter-offer review is now open." {
		t.Errorf("job_accepted negotiable: %+v", n)
	}

	u.notifyCustomerEscrowLockFailed(job)
	if n = c.wait(t, 1)[0]; n.Type != "job_cancelled" || n.Params["variant"] != "escrow_failed" {
		t.Errorf("escrow lock failed: %+v", n)
	}

	u.notifyOwnerCancellationRequested(job, "emp-1", "flat tyre")
	if n = c.wait(t, 1)[0]; n.Type != "cancellation_requested" || n.Params["reason"] != "flat tyre" {
		t.Errorf("cancellation_requested: %+v", n)
	}

	for decision, variant := range map[string]string{"approved": "accept", "declined": "decline"} {
		u.notifyEmployeeCancellationResolved(job, "emp-1", decision)
		if n = c.wait(t, 1)[0]; n.Type != "cancellation_resolved" || n.Params["variant"] != variant {
			t.Errorf("cancellation_resolved %s: %+v", decision, n)
		}
	}

	// No parameters needed: no params key at all.
	u.notifyCustomerJobDelivered(job)
	if n = c.wait(t, 1)[0]; n.Type != "job_delivered" || n.Params != nil {
		t.Errorf("job_delivered: %+v", n)
	}

	for decision, want := range map[string]map[string]string{
		"release_to_employee": {"cust-1": "customer_release", "owner-1": "provider_release", "emp-1": "provider_release"},
		"refund_to_customer":  {"cust-1": "customer_refund", "owner-1": "provider_refund", "emp-1": "provider_refund"},
	} {
		u.dispatchDisputeResolvedNotification(job, decision, "checked")
		got := map[string]string{}
		for _, n := range c.wait(t, 3) {
			got[n.UserID] = n.Params["variant"]
		}
		for uid, v := range want {
			if got[uid] != v {
				t.Errorf("dispute %s to %s: variant %q, want %q", decision, uid, got[uid], v)
			}
		}
	}
}
