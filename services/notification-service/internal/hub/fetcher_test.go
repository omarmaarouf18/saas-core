package hub

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// TestHTTPDeviceTokenFetcher_UnregisterStaleToken_PostsToInternalEndpoint
// covers BE-HARDEN item 3: the notification-service asks the internal
// auth-service endpoint to drop the stale token.
func TestHTTPDeviceTokenFetcher_UnregisterStaleToken_PostsToInternalEndpoint(t *testing.T) {
	var (
		gotPath   string
		gotMethod string
		gotHeader string
		gotBody   map[string]string
	)

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotPath = r.URL.Path
		gotMethod = r.Method
		gotHeader = r.Header.Get("X-Internal-Token")
		raw, _ := io.ReadAll(r.Body)
		_ = json.Unmarshal(raw, &gotBody)
		w.WriteHeader(http.StatusNoContent)
	}))
	defer srv.Close()

	f := NewHTTPDeviceTokenFetcher(srv.URL, "internal-secret", srv.Client())

	if err := f.UnregisterStaleToken(context.Background(), "user-1", "stale-fcm-token"); err != nil {
		t.Fatalf("expected no error, got %v", err)
	}

	if gotPath != "/auth/internal/device-token/unregister" {
		t.Errorf("expected the cleanup to POST to /auth/internal/device-token/unregister, got %q", gotPath)
	}
	if gotMethod != http.MethodPost {
		t.Errorf("expected POST, got %q", gotMethod)
	}
	if gotHeader != "internal-secret" {
		t.Errorf("expected the internal token header, got %q", gotHeader)
	}
	if gotBody["token"] != "stale-fcm-token" {
		t.Errorf("expected the body to carry the token, got %v", gotBody)
	}
}

// TestHTTPDeviceTokenFetcher_UnregisterStaleToken_ReportsRejectedCleanup
// covers BE-HARDEN item 3: a rejected cleanup is an error. The old code
// ignored the status code, so a refused cleanup looked successful and the
// stale token was pushed again on every following notification.
func TestHTTPDeviceTokenFetcher_UnregisterStaleToken_ReportsRejectedCleanup(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
	}))
	defer srv.Close()

	f := NewHTTPDeviceTokenFetcher(srv.URL, "wrong-token", srv.Client())

	err := f.UnregisterStaleToken(context.Background(), "user-1", "stale-fcm-token")
	if err == nil {
		t.Fatal("expected an error when auth-service rejects the cleanup, got nil")
	}
	if !strings.Contains(err.Error(), "401") {
		t.Errorf("expected the error to mention the upstream status, got %v", err)
	}
}
