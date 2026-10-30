package main

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/project/gateway/internal/adminaudit"
	"github.com/project/gateway/internal/version"
	"go.mongodb.org/mongo-driver/v2/mongo"
	"go.mongodb.org/mongo-driver/v2/mongo/options"
)

// unreachableMongoURI points at a closed port with short timeouts, so every
// operation fails fast without any shared service.
const unreachableMongoURI = "mongodb://127.0.0.1:1/?serverSelectionTimeoutMS=200&connectTimeoutMS=200"

// TestOpenGatewayStores_FailsClosedOutsideLocal pins ADMIN-API-FIX item 4:
// with MONGO_URI set and MongoDB unreachable at startup the gateway refuses
// to start unless APP_ENV is local or test, where it keeps the in-memory
// fallback (with a loud warning).
func TestOpenGatewayStores_FailsClosedOutsideLocal(t *testing.T) {
	for _, env := range []string{"production", "staging", ""} {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		vs, as, err := openGatewayStores(ctx, unreachableMongoURI, "gateway_db", env)
		cancel()
		if err == nil || vs != nil || as != nil {
			t.Fatalf("APP_ENV=%q: expected startup error and no stores, got err=%v", env, err)
		}
	}
	for _, env := range []string{"local", "test", "LOCAL"} {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		vs, as, err := openGatewayStores(ctx, unreachableMongoURI, "gateway_db", env)
		cancel()
		if err != nil || vs == nil || as == nil {
			t.Fatalf("APP_ENV=%q: expected in-memory fallback, got err=%v", env, err)
		}
	}
	// No MONGO_URI: in-memory, whatever the environment.
	vs, as, err := openGatewayStores(context.Background(), "", "gateway_db", "production")
	if err != nil || vs == nil || as == nil {
		t.Fatalf("no MONGO_URI: expected in-memory stores, got err=%v", err)
	}
}

// TestVersionHandlers_PersistFailureReturns503 pins that a version update
// whose MongoDB write fails answers 503 on both version endpoints and is not
// kept in memory.
func TestVersionHandlers_PersistFailureReturns503(t *testing.T) {
	client, err := mongo.Connect(options.Client().ApplyURI(unreachableMongoURI))
	if err != nil {
		t.Fatalf("connect: %v", err)
	}
	defer func() { _ = client.Disconnect(context.Background()) }()
	store := version.NewStore(client, "gateway_db")

	internalToken, reviewerToken := "tok-int-503", "tok-rev-503"
	mockAuth := setupMockAuthServer(t, internalToken, reviewerToken)
	defer mockAuth.Close()

	body := func(reason string) []byte {
		b, _ := json.Marshal(map[string]any{
			"latest_version": "9.9.9", "minimum_supported_version": "9.0.0",
			"download_url": "https://github.com/omarmaarouf18/quick-delivery-mobile/releases/latest/download/app.apk",
			"reason":       reason,
		})
		return b
	}

	reviewer := ReviewerVersionConfigHandler(internalToken, mockAuth.URL, mockAuth.Client(), store, adminaudit.NewStore(nil, ""))
	req := httptest.NewRequest(http.MethodPut, "/admin/version", bytes.NewReader(body("raise min")))
	req.Header.Set("X-Internal-Token", internalToken)
	req.Header.Set("X-Reviewer-Token", reviewerToken)
	rec := httptest.NewRecorder()
	reviewer.ServeHTTP(rec, req)
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("reviewer PUT with failing store: expected 503, got %d: %s", rec.Code, rec.Body.String())
	}

	admin := VersionConfigHandler("admin-token-503", store)
	req = httptest.NewRequest(http.MethodPut, "/api/v1/admin/version-config", bytes.NewReader(body("")))
	req.Header.Set("X-Admin-Token", "admin-token-503")
	rec = httptest.NewRecorder()
	admin.ServeHTTP(rec, req)
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("admin PUT with failing store: expected 503, got %d: %s", rec.Code, rec.Body.String())
	}

	cfg, _ := store.GetConfig(context.Background())
	if cfg.LatestVersion == "9.9.9" {
		t.Fatalf("failed write must not be kept in memory, cached config is %+v", cfg)
	}
}
