package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/project/notification-service/internal/config"
	"github.com/project/notification-service/internal/hub"
	"github.com/redis/go-redis/v9"
)

type capturedPush struct{ token, title, body string }

type capturingDispatcher struct {
	mu   sync.Mutex
	sent []capturedPush
	ch   chan struct{}
}

func (d *capturingDispatcher) SendPush(_ context.Context, token, title, body string, _ map[string]string) (bool, error) {
	d.mu.Lock()
	d.sent = append(d.sent, capturedPush{token, title, body})
	d.mu.Unlock()
	d.ch <- struct{}{}
	return false, nil
}
func (d *capturingDispatcher) IsEnabled() bool { return true }

func (d *capturingDispatcher) wait(t *testing.T, n int) map[string]capturedPush {
	t.Helper()
	for i := 0; i < n; i++ {
		select {
		case <-d.ch:
		case <-time.After(2 * time.Second):
			t.Fatalf("push %d of %d not sent", i+1, n)
		}
	}
	d.mu.Lock()
	defer d.mu.Unlock()
	out := map[string]capturedPush{}
	for _, s := range d.sent {
		out[s.token] = s
	}
	d.sent = nil
	return out
}

type localeTargets []hub.PushTarget

func (l localeTargets) GetUserDeviceTokens(context.Context, string) ([]string, error) {
	return nil, fmt.Errorf("GetUserPushTargets must be used")
}
func (l localeTargets) UnregisterStaleToken(context.Context, string, string) error { return nil }
func (l localeTargets) GetUserPushTargets(context.Context, string) ([]hub.PushTarget, error) {
	return l, nil
}

func newPushTestServer(t *testing.T) (*http.ServeMux, *capturingDispatcher) {
	t.Helper()
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("miniredis: %v", err)
	}
	t.Cleanup(mr.Close)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	t.Cleanup(func() { _ = rdb.Close() })

	h := hub.NewSSEHub()
	disp := &capturingDispatcher{ch: make(chan struct{}, 16)}
	h.SetPushDispatcher(disp, localeTargets{{Token: "phone", Locale: "ar"}, {Token: "tablet", Locale: "en"}, {Token: "old-app"}})
	n := NewNotification(h, newMemoryStore(), &config.Config{InternalServiceToken: "itok", AllowedOrigin: "*"}, rdb)
	mux := http.NewServeMux()
	n.RegisterRoutes(mux)
	return mux, disp
}

func postInternal(mux *http.ServeMux, path string, payload any) *httptest.ResponseRecorder {
	b, _ := json.Marshal(payload)
	req := httptest.NewRequest(http.MethodPost, path, bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Internal-Token", "itok")
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	return rec
}

// PUSH-L10N item 2: POST /notifications/send takes the sender's params and
// each device gets the push in its language; the old app the English text.
func TestSend_ParamsRenderPushPerLocale(t *testing.T) {
	mux, disp := newPushTestServer(t)

	rec := postInternal(mux, "/notifications/send", map[string]any{
		"type": "cancellation_requested", "tenant_id": "owner-1", "user_id": "owner-1", "job_id": "job-9",
		"title":  "Cancellation Requested",
		"body":   "Courier emp-1 requested cancellation of job job-9: flat tyre. Respond within 15 minutes.",
		"roles":  []string{"owner"},
		"params": map[string]string{"reason": "flat tyre"},
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("send: %d %s", rec.Code, rec.Body.String())
	}
	got := disp.wait(t, 3)
	want := map[string]capturedPush{
		"phone":   {"phone", "مندوب طالب يلغي مهمة", "السبب: flat tyre. رد خلال 15 دقيقة."},
		"tablet":  {"tablet", "A courier asked to cancel a job", "Reason: flat tyre. Answer within 15 minutes."},
		"old-app": {"old-app", "Cancellation Requested", "Courier emp-1 requested cancellation of job job-9: flat tyre. Respond within 15 minutes."},
	}
	for tok, w := range want {
		if got[tok] != w {
			t.Errorf("%s: got %+v, want %+v", tok, got[tok], w)
		}
	}
}

// The job alert notification-service builds itself carries service_name.
func TestJobAlert_PushPerLocale(t *testing.T) {
	mux, disp := newPushTestServer(t)
	rec := postInternal(mux, "/notifications/broadcast/job-alert", map[string]any{
		"tenant_id": "owner-1", "job_id": "job-9", "employee_id": "emp-1",
		"service_name": "Fast Bikes", "description": "Category: delivery",
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("job-alert: %d %s", rec.Code, rec.Body.String())
	}
	got := disp.wait(t, 3)
	if got["phone"].body != "مهمة جديدة لخدمة Fast Bikes." || got["tablet"].body != "New job for Fast Bikes." {
		t.Errorf("localized job alert: got %+v", got)
	}
	if got["old-app"].title != "🆕 New Job Alert" {
		t.Errorf("legacy job alert title: got %q", got["old-app"].title)
	}
}

func TestSend_TooManyParams(t *testing.T) {
	mux, _ := newPushTestServer(t)
	params := map[string]string{}
	for i := 0; i <= maxNotificationParams; i++ {
		params[fmt.Sprintf("k%d", i)] = "v"
	}
	rec := postInternal(mux, "/notifications/send", map[string]any{
		"type": "popup", "tenant_id": "t", "user_id": "u", "title": "T", "body": "B", "params": params,
	})
	if rec.Code != http.StatusBadRequest {
		t.Errorf("got %d, want 400", rec.Code)
	}
}
