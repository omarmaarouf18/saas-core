package main

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/project/gateway/internal/version"
	"go.mongodb.org/mongo-driver/v2/mongo"
	"go.mongodb.org/mongo-driver/v2/mongo/options"
)

// unreachableMongo returns a client whose persist path fails with a
// driver/transport error (nothing listens on port 1).
func unreachableMongo(t *testing.T) *mongo.Client {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	client, err := mongo.Connect(options.Client().ApplyURI("mongodb://127.0.0.1:1/?serverSelectionTimeoutMS=500"))
	if err != nil {
		t.Fatalf("mongo.Connect: %v", err)
	}
	t.Cleanup(func() { _ = client.Disconnect(context.Background()) })
	_ = ctx
	return client
}

// A3: forced-failure cases must return the stable sanitized body — no
// DB/driver internals may reach the client. Curated validation copy
// stays verbatim by design.
func TestVersionConfig_SafeErrors(t *testing.T) {
	internalToken := "test-internal-token-12345"
	handler := VersionConfigHandler(internalToken, version.NewStore(nil, ""))

	t.Run("PUT persist failure sanitized", func(t *testing.T) {
		store := version.NewStore(unreachableMongo(t), "")
		handler := VersionConfigHandler(internalToken, store)
		body := bytes.NewReader([]byte(`{"latest_version":"9.9.9","minimum_supported_version":"9.0.0"}`))
		req := httptest.NewRequest(http.MethodPut, "/api/v1/admin/version-config", body)
		req.Header.Set("X-Internal-Token", internalToken)
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)

		if rec.Code != http.StatusBadRequest {
			t.Fatalf("expected 400, got %d (%s)", rec.Code, rec.Body.String())
		}
		var decoded map[string]any
		if err := json.Unmarshal(rec.Body.Bytes(), &decoded); err != nil {
			t.Fatalf("body not JSON: %s", rec.Body.String())
		}
		if decoded["code"] != "internal_error" {
			t.Errorf("expected code internal_error, got %s", rec.Body.String())
		}
		for _, leak := range []string{"MongoDB", "mongo", "BSON", "connection refused"} {
			if strings.Contains(rec.Body.String(), leak) {
				t.Errorf("internal detail %q leaked in body %s", leak, rec.Body.String())
			}
		}
	})

	t.Run("PUT validation copy kept verbatim", func(t *testing.T) {
		body := bytes.NewReader([]byte(`{"latest_version":"not-a-version","minimum_supported_version":"9.0.0"}`))
		req := httptest.NewRequest(http.MethodPut, "/api/v1/admin/version-config", body)
		req.Header.Set("X-Internal-Token", internalToken)
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)

		if rec.Code != http.StatusBadRequest {
			t.Fatalf("expected 400, got %d (%s)", rec.Code, rec.Body.String())
		}
		if !strings.Contains(rec.Body.String(), "invalid latest_version") {
			t.Errorf("expected curated validation copy, got %s", rec.Body.String())
		}
	})
}
