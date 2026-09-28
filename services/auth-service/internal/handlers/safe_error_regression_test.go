package handlers

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"

	"github.com/alicebob/miniredis/v2"
	"github.com/project/auth-service/internal/config"
	"github.com/project/auth-service/internal/storage"
	"github.com/redis/go-redis/v9"
)

func newBareAuthForSafeErrorTest(t *testing.T) *Auth {
	t.Helper()
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	cfg := &config.Config{
		AppEnv:               "local",
		GatewaySecret:        "mock-gateway-secret",
		InternalServiceToken: "mock-internal-token",
	}
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("miniredis: %v", err)
	}
	t.Cleanup(mr.Close)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	t.Cleanup(func() { _ = rdb.Close() })
	tempDir := t.TempDir()
	storeLoc, _ := storage.NewLocalStorage(tempDir, "/api/v1", os.Getenv("JWT_SECRET"), "", "test")
	return NewAuth(nil, nil, cfg, rdb, storeLoc)
}

// A3: forced-failure cases must return the stable sanitized body — no
// JWT/DB/library internals may reach the client.
func TestSafeError_NoInternalsLeak_Auth(t *testing.T) {
	if testing.Short() {
		t.Skip("needs handler harness only")
	}
	a := newBareAuthForSafeErrorTest(t)

	internals := []string{
		"token has invalid", "invalid claims", "token is malformed",
		"invalid number of segments", "signature", "jwtutil: ",
		"unexpected end of JSON", "cannot unmarshal", "invalid character",
		"mongo", "Mongo", "BSON", "duplicate key", "connection refused",
		"store: ", "bcrypt",
	}

	t.Run("malformed JWT sanitized", func(t *testing.T) {
		req := httptest.NewRequest("GET", "/auth/employees?owner_token=not-a-jwt", nil)
		rec := httptest.NewRecorder()
		a.GetEmployees(rec, req)
		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("expected 401, got %d (%s)", rec.Code, rec.Body.String())
		}
		assertAuthSanitized(t, rec.Body.String(), internals, "unauthorized")
	})

	t.Run("malformed JSON sanitized", func(t *testing.T) {
		req := httptest.NewRequest("POST", "/auth/login", strings.NewReader("{bad json"))
		rec := httptest.NewRecorder()
		a.Login(rec, req)
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("expected 400, got %d (%s)", rec.Code, rec.Body.String())
		}
		assertAuthSanitized(t, rec.Body.String(), internals, "invalid_json")
	})
}

func assertAuthSanitized(t *testing.T, body string, internals []string, wantCode string) {
	t.Helper()
	var decoded map[string]any
	if err := json.Unmarshal([]byte(body), &decoded); err != nil {
		t.Fatalf("body not JSON: %s", body)
	}
	if decoded["code"] != wantCode {
		t.Errorf("expected code %q, got body %s", wantCode, body)
	}
	rid, ok := decoded["request_id"].(string)
	if !ok || len(rid) != 16 {
		t.Errorf("request_id missing/malformed in %s", body)
	}
	for _, leak := range internals {
		if strings.Contains(body, leak) {
			t.Errorf("internal detail %q leaked in body %s", leak, body)
		}
	}
}
