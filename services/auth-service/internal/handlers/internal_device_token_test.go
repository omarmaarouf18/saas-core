package handlers

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// fakeDeviceTokenStore records the tokens the internal endpoint removes.
type fakeDeviceTokenStore struct {
	removed []string
	changed int64
	err     error
}

func (f *fakeDeviceTokenStore) RemoveDeviceTokenFromAnyUser(_ context.Context, token string) (int64, error) {
	f.removed = append(f.removed, token)
	if f.err != nil {
		return 0, f.err
	}
	return f.changed, nil
}

func newInternalDeviceTokenAuth(store DeviceTokenUnregisterStore) *Auth {
	return &Auth{
		internalServiceToken: "internal-token-test",
		deviceTokenStore:     store,
	}
}

// TestUnregisterStaleDeviceToken_RemovesTokenFromEveryHolder covers BE-HARDEN
// item 3: the stale push token is removed from every user that holds it, not
// from one account the caller happens to know.
func TestUnregisterStaleDeviceToken_RemovesTokenFromEveryHolder(t *testing.T) {
	store := &fakeDeviceTokenStore{changed: 2}
	a := newInternalDeviceTokenAuth(store)

	req := httptest.NewRequest(http.MethodPost, "/auth/internal/device-token/unregister",
		strings.NewReader(`{"token":"stale-fcm-token"}`))
	req.Header.Set("X-Internal-Token", "internal-token-test")
	rec := httptest.NewRecorder()

	a.UnregisterStaleDeviceToken(rec, req)

	if rec.Code != http.StatusNoContent {
		t.Fatalf("expected 204 No Content, got %d (body: %s)", rec.Code, rec.Body.String())
	}
	if rec.Body.Len() != 0 {
		t.Errorf("expected an empty body, got %q", rec.Body.String())
	}
	if len(store.removed) != 1 || store.removed[0] != "stale-fcm-token" {
		t.Fatalf("expected the token to be removed from every holder, got %v", store.removed)
	}
}

// TestUnregisterStaleDeviceToken_IsIdempotent covers BE-HARDEN item 3: a
// token nobody holds any more still answers 204, so the caller can retry.
func TestUnregisterStaleDeviceToken_IsIdempotent(t *testing.T) {
	store := &fakeDeviceTokenStore{changed: 0}
	a := newInternalDeviceTokenAuth(store)

	for i := 0; i < 2; i++ {
		req := httptest.NewRequest(http.MethodPost, "/auth/internal/device-token/unregister",
			strings.NewReader(`{"token":"stale-fcm-token"}`))
		req.Header.Set("X-Internal-Token", "internal-token-test")
		rec := httptest.NewRecorder()

		a.UnregisterStaleDeviceToken(rec, req)

		if rec.Code != http.StatusNoContent {
			t.Fatalf("call %d: expected 204 No Content, got %d (body: %s)", i+1, rec.Code, rec.Body.String())
		}
	}
	if len(store.removed) != 2 {
		t.Fatalf("expected 2 removal attempts, got %d", len(store.removed))
	}
}

// TestUnregisterStaleDeviceToken_RequiresInternalToken covers BE-HARDEN item
// 3: only another backend service may call the endpoint.
func TestUnregisterStaleDeviceToken_RequiresInternalToken(t *testing.T) {
	cases := []struct {
		name  string
		token string
	}{
		{name: "missing header", token: ""},
		{name: "wrong token", token: "not-the-internal-token"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			store := &fakeDeviceTokenStore{}
			a := newInternalDeviceTokenAuth(store)

			req := httptest.NewRequest(http.MethodPost, "/auth/internal/device-token/unregister",
				strings.NewReader(`{"token":"stale-fcm-token"}`))
			if tc.token != "" {
				req.Header.Set("X-Internal-Token", tc.token)
			}
			rec := httptest.NewRecorder()

			a.UnregisterStaleDeviceToken(rec, req)

			if rec.Code != http.StatusUnauthorized {
				t.Fatalf("expected 401 Unauthorized, got %d (body: %s)", rec.Code, rec.Body.String())
			}
			if len(store.removed) != 0 {
				t.Errorf("expected no store call without a valid internal token, got %v", store.removed)
			}
		})
	}
}

// TestUnregisterStaleDeviceToken_RejectsNonPost covers BE-HARDEN item 3: the
// endpoint only accepts POST.
func TestUnregisterStaleDeviceToken_RejectsNonPost(t *testing.T) {
	store := &fakeDeviceTokenStore{}
	a := newInternalDeviceTokenAuth(store)

	req := httptest.NewRequest(http.MethodGet, "/auth/internal/device-token/unregister", nil)
	req.Header.Set("X-Internal-Token", "internal-token-test")
	rec := httptest.NewRecorder()

	a.UnregisterStaleDeviceToken(rec, req)

	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("expected 405 Method Not Allowed, got %d (body: %s)", rec.Code, rec.Body.String())
	}
	if len(store.removed) != 0 {
		t.Errorf("expected no store call for a non-POST request, got %v", store.removed)
	}
}

// TestUnregisterStaleDeviceToken_RejectsInvalidToken covers BE-HARDEN item 3:
// an empty or oversized token is a bad request, not a silent no-op.
func TestUnregisterStaleDeviceToken_RejectsInvalidToken(t *testing.T) {
	cases := []struct {
		name  string
		token string
	}{
		{name: "empty token", token: ""},
		{name: "blank token", token: "   "},
		{name: "oversized token", token: strings.Repeat("t", maxDeviceTokenLength+1)},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			store := &fakeDeviceTokenStore{}
			a := newInternalDeviceTokenAuth(store)

			req := httptest.NewRequest(http.MethodPost, "/auth/internal/device-token/unregister",
				strings.NewReader(`{"token":"`+tc.token+`"}`))
			req.Header.Set("X-Internal-Token", "internal-token-test")
			rec := httptest.NewRecorder()

			a.UnregisterStaleDeviceToken(rec, req)

			if rec.Code != http.StatusBadRequest {
				t.Fatalf("expected 400 Bad Request, got %d (body: %s)", rec.Code, rec.Body.String())
			}
			if len(store.removed) != 0 {
				t.Errorf("expected no store call for an invalid token, got %v", store.removed)
			}
		})
	}
}

// TestUnregisterStaleDeviceToken_StoreFailureIsSanitized covers BE-HARDEN
// item 3: a store failure answers 500 with a safe body, not the raw error.
func TestUnregisterStaleDeviceToken_StoreFailureIsSanitized(t *testing.T) {
	store := &fakeDeviceTokenStore{err: errors.New("mongo exploded: users collection unavailable")}
	a := newInternalDeviceTokenAuth(store)

	req := httptest.NewRequest(http.MethodPost, "/auth/internal/device-token/unregister",
		strings.NewReader(`{"token":"stale-fcm-token"}`))
	req.Header.Set("X-Internal-Token", "internal-token-test")
	rec := httptest.NewRecorder()

	a.UnregisterStaleDeviceToken(rec, req)

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500 Internal Server Error, got %d (body: %s)", rec.Code, rec.Body.String())
	}
	if strings.Contains(rec.Body.String(), "mongo exploded") {
		t.Errorf("the store error leaked into the response body: %s", rec.Body.String())
	}
}

// TestUnregisterStaleDeviceToken_StoreUnavailable covers BE-HARDEN item 3: a
// service without a user store answers 503 instead of panicking.
func TestUnregisterStaleDeviceToken_StoreUnavailable(t *testing.T) {
	a := newInternalDeviceTokenAuth(nil)

	req := httptest.NewRequest(http.MethodPost, "/auth/internal/device-token/unregister",
		strings.NewReader(`{"token":"stale-fcm-token"}`))
	req.Header.Set("X-Internal-Token", "internal-token-test")
	rec := httptest.NewRecorder()

	a.UnregisterStaleDeviceToken(rec, req)

	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected 503 Service Unavailable, got %d (body: %s)", rec.Code, rec.Body.String())
	}
}

// TestRegisterRoutes_ExposesInternalDeviceTokenUnregister covers BE-HARDEN
// item 3: the endpoint is reachable under the documented internal path.
func TestRegisterRoutes_ExposesInternalDeviceTokenUnregister(t *testing.T) {
	store := &fakeDeviceTokenStore{changed: 1}
	a := newInternalDeviceTokenAuth(store)

	mux := http.NewServeMux()
	a.RegisterRoutes(mux)

	req := httptest.NewRequest(http.MethodPost, "/auth/internal/device-token/unregister",
		strings.NewReader(`{"token":"stale-fcm-token"}`))
	req.Header.Set("X-Internal-Token", "internal-token-test")
	rec := httptest.NewRecorder()

	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusNoContent {
		t.Fatalf("expected 204 No Content, got %d (body: %s)", rec.Code, rec.Body.String())
	}
	if len(store.removed) != 1 || store.removed[0] != "stale-fcm-token" {
		t.Fatalf("expected the token to be removed from every holder, got %v", store.removed)
	}
}
