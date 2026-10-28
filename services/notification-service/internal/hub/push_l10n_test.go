package hub

import (
	"context"
	"sync"
	"testing"
	"time"
)

// PUSH-L10N item 2: each device gets the push in its own language; a device
// without a locale (old app) and a type without a template keep the
// sender's English text.
func TestDispatchPush_TextPerDeviceLocale(t *testing.T) {
	type sent struct{ title, body string }
	var mu sync.Mutex
	got := map[string]sent{}
	done := make(chan struct{}, 8)

	h := NewSSEHub()
	h.SetPushDispatcher(&mockFCMDispatcher{enabled: true, sendPushFunc: func(_ context.Context, token, title, body string, _ map[string]string) (bool, error) {
		mu.Lock()
		got[token] = sent{title, body}
		mu.Unlock()
		done <- struct{}{}
		return false, nil
	}}, &localeFetcher{targets: []PushTarget{{"phone", "ar"}, {"tablet", "en"}, {"old-app", ""}}})

	wait := func(n int) {
		for i := 0; i < n; i++ {
			select {
			case <-done:
			case <-time.After(2 * time.Second):
				t.Fatalf("push %d of %d not sent", i+1, n)
			}
		}
	}

	h.Broadcast(Notification{
		Type: "job_accepted", TenantID: "t", UserID: "u", JobID: "j1",
		Title: "Courier Assigned", Body: "Your courier has accepted! Final fare: EGP 1,250.50",
		Params: map[string]string{"fare": "1250.5"},
	})
	wait(3)
	mu.Lock()
	want := map[string]sent{
		"phone":   {"مندوب قبل طلبك", "الأجرة النهائية: 1,250.50 ج.م."},
		"tablet":  {"A courier accepted your order", "Final fare: EGP 1,250.50."},
		"old-app": {"Courier Assigned", "Your courier has accepted! Final fare: EGP 1,250.50"},
	}
	for tok, w := range want {
		if got[tok] != w {
			t.Errorf("job_accepted to %s: got %q, want %q", tok, got[tok], w)
		}
	}
	got = map[string]sent{}
	mu.Unlock()

	h.Broadcast(Notification{Type: "popup", TenantID: "t", UserID: "u", Title: "Hello", Body: "World"})
	wait(3)
	mu.Lock()
	defer mu.Unlock()
	for _, tok := range []string{"phone", "tablet", "old-app"} {
		if got[tok] != (sent{"Hello", "World"}) {
			t.Errorf("popup to %s: got %q, want the sender's text", tok, got[tok])
		}
	}
}
