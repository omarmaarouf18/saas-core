package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/project/shared/infra/jwtutil"
	"github.com/project/user-service/internal/config"
	"github.com/project/user-service/internal/store"
	"github.com/redis/go-redis/v9"
)

// A3: forced-failure cases must return the stable sanitized body — no
// DB/JWT/library internals may reach the client.
func TestSafeError_NoInternalsLeak(t *testing.T) {
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	jwtutil.Init(os.Getenv("JWT_SECRET"))
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	dbName := fmt.Sprintf("saas_safeerr_test_%d", time.Now().UnixNano())
	s, err := store.NewMongoDB(ctx, mongoURI, dbName)
	if err != nil {
		t.Skipf("MongoDB not available: %v", err)
		return
	}
	defer func() {
		_ = s.DropDatabase(context.Background())
		s.Close(context.Background())
	}()
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("miniredis: %v", err)
	}
	defer mr.Close()
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	u := NewUserService(s, &config.Config{}, rdb)

	internals := []string{
		"token has invalid", "invalid claims", "token is malformed",
		"invalid number of segments",
		"unexpected end of JSON", "cannot unmarshal", "invalid character",
		"mongo", "Mongo", "BSON", "duplicate key", "connection refused",
		"store: ",
	}

	t.Run("malformed JWT sanitized", func(t *testing.T) {
		req := httptest.NewRequest("GET", "/users/wallet?tenant_id=not-a-jwt", nil)
		rec := httptest.NewRecorder()
		u.GetWallet(rec, req)
		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("expected 401, got %d (%s)", rec.Code, rec.Body.String())
		}
		assertSanitized(t, rec.Body.String(), internals, "invalid_token")
	})

	t.Run("malformed JSON sanitized", func(t *testing.T) {
		req := httptest.NewRequest("POST", "/users/jobs/track", strings.NewReader("{bad json"))
		rec := httptest.NewRecorder()
		u.TrackJob(rec, req)
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("expected 400, got %d (%s)", rec.Code, rec.Body.String())
		}
		assertSanitized(t, rec.Body.String(), internals, "invalid_json")
	})
}

func assertSanitized(t *testing.T, body string, internals []string, wantCode string) {
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
