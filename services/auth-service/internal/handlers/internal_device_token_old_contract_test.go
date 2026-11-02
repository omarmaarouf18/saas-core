package handlers

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// TestDeviceTokenEndpointRejectsInternalServiceCaller documents the
// BE-HARDEN item 3 bug: before the internal unregister endpoint existed,
// the only device-token endpoint was POST /auth/device-token, and it
// authenticates the caller with a user JWT. The notification-service called
// it with its X-Internal-Token header only, so every stale-token cleanup
// was answered with 401 — and the caller ignored the status code, so the
// stale token was never removed and kept failing every following push.
//
// The test uses only the pre-existing handler, so it compiles and runs
// against the code as it was before item 3.
func TestDeviceTokenEndpointRejectsInternalServiceCaller(t *testing.T) {
	a := &Auth{}

	mux := http.NewServeMux()
	mux.HandleFunc("/auth/device-token", a.DeviceToken)

	req := httptest.NewRequest(http.MethodPost, "/auth/device-token",
		strings.NewReader(`{"token":"stale-fcm-token","action":"unregister"}`))
	req.Header.Set("X-Internal-Token", "internal-token-test")
	rec := httptest.NewRecorder()

	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 Unauthorized for the internal-service caller, got %d (body: %s)", rec.Code, rec.Body.String())
	}
}
