package main

// Regression coverage for the "clear all notifications" gateway routing bug:
// the notifications route is a trailing-slash subtree registration, so the
// bare collection path (/api/v1/notifications) used to get an automatic 3xx
// redirect instead of being proxied. These tests pin the fixed behavior —
// direct proxying with no redirect — for DELETE, its OPTIONS preflight, and
// the pre-existing single-delete path.

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/project/gateway/internal/config"
	"github.com/project/gateway/internal/proxy"
)

type recordedRequest struct {
	method string
	path   string
}

func newNotificationsTestMux(t *testing.T, backend http.Handler, seen *[]recordedRequest) *http.ServeMux {
	t.Helper()
	route := config.ServiceRoute{
		Prefix:      "/api/v1/notifications/",
		Target:      "http://notification-service:3004",
		StripPrefix: "/api/v1",
		EnvKey:      "NOTIFICATION_SERVICE_URL",
	}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		*seen = append(*seen, recordedRequest{method: r.Method, path: r.URL.Path})
		backend.ServeHTTP(w, r)
	}))
	t.Cleanup(server.Close)
	route.Target = server.URL

	mux := http.NewServeMux()
	registerServiceRoutes(mux, []config.ServiceRoute{route},
		func(rt config.ServiceRoute) (http.Handler, error) {
			return proxy.New(rt, "test-secret", nil, http.DefaultTransport)
		})
	return mux
}

func assertDirectProxy(t *testing.T, rec *httptest.ResponseRecorder) {
	t.Helper()
	if rec.Code >= 300 && rec.Code < 400 {
		t.Errorf("Expected direct proxy response, got redirect %d with Location %q",
			rec.Code, rec.Header().Get("Location"))
	}
	if loc := rec.Header().Get("Location"); loc != "" {
		t.Errorf("Expected no Location header on a direct proxy response, got %q", loc)
	}
}

func TestBareNotificationsDeleteProxiedWithoutRedirect(t *testing.T) {
	var seen []recordedRequest
	backend := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"message":"all notifications deleted"}`))
	})
	mux := newNotificationsTestMux(t, backend, &seen)

	req := httptest.NewRequest(http.MethodDelete, "/api/v1/notifications", nil)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	assertDirectProxy(t, rec)
	if rec.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK from backend, got %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "all notifications deleted") {
		t.Errorf("Expected backend clear-all body, got %q", rec.Body.String())
	}
	if len(seen) != 1 || seen[0].method != http.MethodDelete || seen[0].path != "/notifications" {
		t.Errorf("Expected backend to see DELETE /notifications, got %+v", seen)
	}
}

func TestBareNotificationsOptionsProxiedWithoutRedirect(t *testing.T) {
	var seen []recordedRequest
	backend := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	})
	mux := newNotificationsTestMux(t, backend, &seen)

	req := httptest.NewRequest(http.MethodOptions, "/api/v1/notifications", nil)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	assertDirectProxy(t, rec)
	if rec.Code != http.StatusNoContent {
		t.Fatalf("Expected 204 from backend preflight, got %d", rec.Code)
	}
	if len(seen) != 1 || seen[0].method != http.MethodOptions || seen[0].path != "/notifications" {
		t.Errorf("Expected backend to see OPTIONS /notifications, got %+v", seen)
	}
}

func TestSingleNotificationDeleteUnaffected(t *testing.T) {
	var seen []recordedRequest
	backend := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"message":"notification deleted"}`))
	})
	mux := newNotificationsTestMux(t, backend, &seen)

	req := httptest.NewRequest(http.MethodDelete, "/api/v1/notifications/notif-123", nil)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	assertDirectProxy(t, rec)
	if rec.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK from backend, got %d: %s", rec.Code, rec.Body.String())
	}
	if len(seen) != 1 || seen[0].method != http.MethodDelete || seen[0].path != "/notifications/notif-123" {
		t.Errorf("Expected backend to see DELETE /notifications/notif-123, got %+v", seen)
	}
}
