package hub

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"
)

// PUSH-L10N item 1: the fetcher reads each token's locale from auth-service
// GET /auth/user (internal), and the hub prefers it over plain tokens.
func TestHTTPDeviceTokenFetcher_ReadsLocales(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("X-Internal-Token") != "itok" || r.URL.Query().Get("id") != "u1" {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]any{
			"id": "u1",
			"device_tokens": []map[string]any{
				{"token": "phone", "platform": "android", "locale": "ar"},
				{"token": "tablet", "platform": "android", "locale": "en"},
				{"token": "old-app", "platform": "android"},
				{"token": " "},
			},
		})
	}))
	defer srv.Close()

	f := NewHTTPDeviceTokenFetcher(srv.URL, "itok", nil)
	got, err := f.GetUserPushTargets(context.Background(), "u1")
	if err != nil {
		t.Fatalf("GetUserPushTargets: %v", err)
	}
	want := []PushTarget{{"phone", "ar"}, {"tablet", "en"}, {"old-app", ""}}
	if len(got) != len(want) {
		t.Fatalf("got %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("target %d: got %v, want %v", i, got[i], want[i])
		}
	}

	tokens, err := f.GetUserDeviceTokens(context.Background(), "u1")
	if err != nil || len(tokens) != 3 || tokens[0] != "phone" || tokens[2] != "old-app" {
		t.Errorf("GetUserDeviceTokens: got %v, %v", tokens, err)
	}
}

type localeFetcher struct {
	mockDeviceTokenFetcher
	targets []PushTarget
}

func (f *localeFetcher) GetUserPushTargets(context.Context, string) ([]PushTarget, error) {
	return f.targets, nil
}

func TestUserPushTargets_PrefersLocaleFetcher(t *testing.T) {
	plain := &mockDeviceTokenFetcher{tokensFunc: func(context.Context, string) ([]string, error) {
		return []string{"a", "b"}, nil
	}}
	got, err := userPushTargets(context.Background(), plain, "u")
	if err != nil || len(got) != 2 || got[0] != (PushTarget{Token: "a"}) {
		t.Fatalf("plain fetcher: got %v, %v", got, err)
	}

	lf := &localeFetcher{targets: []PushTarget{{"x", "ar"}}}
	lf.tokensFunc = func(context.Context, string) ([]string, error) {
		t.Error("GetUserDeviceTokens called although GetUserPushTargets exists")
		return nil, nil
	}
	got, err = userPushTargets(context.Background(), lf, "u")
	if err != nil || len(got) != 1 || got[0] != (PushTarget{"x", "ar"}) {
		t.Fatalf("locale fetcher: got %v, %v", got, err)
	}

	// Through the hub: every target token is pushed.
	var mu sync.Mutex
	var sent []string
	done := make(chan struct{}, 4)
	h := NewSSEHub()
	h.SetPushDispatcher(&mockFCMDispatcher{enabled: true, sendPushFunc: func(_ context.Context, token, _, _ string, _ map[string]string) (bool, error) {
		mu.Lock()
		sent = append(sent, token)
		mu.Unlock()
		done <- struct{}{}
		return false, nil
	}}, &localeFetcher{targets: []PushTarget{{"x", "ar"}, {"y", ""}}})
	h.Broadcast(Notification{Type: "popup", TenantID: "t", UserID: "u", Title: "T", Body: "B"})
	for i := 0; i < 2; i++ {
		select {
		case <-done:
		case <-time.After(2 * time.Second):
			t.Fatalf("push %d not sent", i+1)
		}
	}
	mu.Lock()
	defer mu.Unlock()
	if len(sent) != 2 || sent[0] != "x" || sent[1] != "y" {
		t.Errorf("sent tokens: got %v", sent)
	}
}
