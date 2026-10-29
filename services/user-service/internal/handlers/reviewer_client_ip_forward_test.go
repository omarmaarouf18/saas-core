package handlers

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

// TestAuthenticateReviewer_ForwardsOnlyConsoleClientIP pins that
// user-service never passes a caller's X-Forwarded-For / X-Real-IP to
// auth-service's reviewer verify (rotating them reset the per-IP reviewer
// rate limit). It forwards the console's X-Console-Client-IP, and only after
// its own internal token check has passed.
func TestAuthenticateReviewer_ForwardsOnlyConsoleClientIP(t *testing.T) {
	var gotXFF, gotXRI, gotConsole string
	calls := 0
	auth := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		gotXFF = r.Header.Get("X-Forwarded-For")
		gotXRI = r.Header.Get("X-Real-IP")
		gotConsole = r.Header.Get("X-Console-Client-IP")
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"id":"rev-1","name":"Reviewer"}`))
	}))
	defer auth.Close()

	u := &UserService{authServiceURL: auth.URL, internalServiceToken: "internal-tok"}

	req := httptest.NewRequest(http.MethodGet, "/users/admin/jobs", nil)
	req.RemoteAddr = "172.20.0.9:50000"
	req.Header.Set("X-Internal-Token", "internal-tok")
	req.Header.Set("X-Reviewer-Token", "rev-token")
	req.Header.Set("X-Forwarded-For", "198.51.100.7")
	req.Header.Set("X-Real-IP", "198.51.100.8")
	req.Header.Set("X-Console-Client-IP", "203.0.113.10")
	if _, err := u.authenticateReviewer(req); err != nil {
		t.Fatalf("authenticateReviewer: %v", err)
	}
	if gotXFF != "" || gotXRI != "" {
		t.Fatalf("forwarded client X-Forwarded-For=%q X-Real-IP=%q to auth-service", gotXFF, gotXRI)
	}
	if gotConsole != "203.0.113.10" {
		t.Fatalf("X-Console-Client-IP = %q, want 203.0.113.10", gotConsole)
	}

	bad := httptest.NewRequest(http.MethodGet, "/users/admin/jobs", nil)
	bad.Header.Set("X-Internal-Token", "wrong")
	bad.Header.Set("X-Reviewer-Token", "rev-token")
	bad.Header.Set("X-Console-Client-IP", "203.0.113.10")
	calls = 0
	if _, err := u.authenticateReviewer(bad); err == nil || calls != 0 {
		t.Fatalf("expected rejection before any auth-service call without the internal token (err=%v calls=%d)", err, calls)
	}
}
