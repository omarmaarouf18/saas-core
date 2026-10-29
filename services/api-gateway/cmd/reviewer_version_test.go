package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"github.com/project/gateway/internal/version"
	"go.mongodb.org/mongo-driver/v2/mongo"
	"go.mongodb.org/mongo-driver/v2/mongo/options"
)

func setupMockAuthServer(t *testing.T, validInternalToken, validReviewerToken string) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/auth/reviewer/verify" {
			internalTok := r.Header.Get("X-Internal-Token")
			if internalTok != validInternalToken {
				w.WriteHeader(http.StatusForbidden)
				_, _ = w.Write([]byte(`{"error":"invalid internal token"}`))
				return
			}
			revTok := r.Header.Get("X-Reviewer-Token")
			if revTok == "rate-limited-token" {
				w.Header().Set("Retry-After", "60")
				w.WriteHeader(http.StatusTooManyRequests)
				_, _ = w.Write([]byte(`{"error":"too many requests"}`))
				return
			}
			if revTok != validReviewerToken {
				w.WriteHeader(http.StatusUnauthorized)
				_, _ = w.Write([]byte(`{"error":"invalid reviewer token"}`))
				return
			}
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte(`{"id":"rev-ver-123","name":"Version Reviewer"}`))
			return
		}
		w.WriteHeader(http.StatusNotFound)
	}))
}

func TestReviewerVersionConfigHandler_Authentication(t *testing.T) {
	internalToken := "mock-internal-token-xyz"
	reviewerToken := "mock-reviewer-token-xyz"
	mockAuth := setupMockAuthServer(t, internalToken, reviewerToken)
	defer mockAuth.Close()

	store := version.NewStore(nil, "")
	handler := ReviewerVersionConfigHandler(internalToken, mockAuth.URL, mockAuth.Client(), store)

	t.Run("Missing Internal Token Rejected", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/admin/version", nil)
		req.Header.Set("X-Reviewer-Token", reviewerToken)
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)
		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("expected 401, got %d", rec.Code)
		}
	})

	t.Run("Missing Reviewer Token Rejected", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/admin/version", nil)
		req.Header.Set("X-Internal-Token", internalToken)
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)
		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("expected 401, got %d", rec.Code)
		}
	})

	t.Run("Invalid Reviewer Token Rejected", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/admin/version", nil)
		req.Header.Set("X-Internal-Token", internalToken)
		req.Header.Set("X-Reviewer-Token", "wrong-reviewer-token")
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)
		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("expected 401, got %d", rec.Code)
		}
	})

	t.Run("Rate Limited Reviewer Propagates 429", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/admin/version", nil)
		req.Header.Set("X-Internal-Token", internalToken)
		req.Header.Set("X-Reviewer-Token", "rate-limited-token")
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)
		if rec.Code != http.StatusTooManyRequests {
			t.Fatalf("expected 429, got %d", rec.Code)
		}
		if rec.Header().Get("Retry-After") != "60" {
			t.Fatalf("expected Retry-After: 60, got %s", rec.Header().Get("Retry-After"))
		}
	})

	t.Run("Valid Reviewer Authenticated", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/admin/version", nil)
		req.Header.Set("X-Internal-Token", internalToken)
		req.Header.Set("X-Reviewer-Token", reviewerToken)
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 OK, got %d: %s", rec.Code, rec.Body.String())
		}
	})
}

func TestReviewerVersionConfigHandler_GetAndPut(t *testing.T) {
	internalToken := "mock-internal-token-abc"
	reviewerToken := "mock-reviewer-token-abc"
	mockAuth := setupMockAuthServer(t, internalToken, reviewerToken)
	defer mockAuth.Close()

	store := version.NewStore(nil, "")
	handler := ReviewerVersionConfigHandler(internalToken, mockAuth.URL, mockAuth.Client(), store)

	t.Run("GET Returns Current Config", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/admin/version", nil)
		req.Header.Set("X-Internal-Token", internalToken)
		req.Header.Set("X-Reviewer-Token", reviewerToken)
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
		}
		var cfg version.PlatformVersions
		if err := json.Unmarshal(rec.Body.Bytes(), &cfg); err != nil {
			t.Fatalf("failed to parse: %v", err)
		}
		if cfg.LatestVersion != "1.0.0" {
			t.Fatalf("expected default latest 1.0.0, got %s", cfg.LatestVersion)
		}
	})

	t.Run("PUT Without Reason Fails", func(t *testing.T) {
		payload := ReviewerVersionUpdateRequest{
			LatestVersion:           "1.2.0",
			MinimumSupportedVersion: "1.1.0",
			DownloadURL:             "https://github.com/omarmaarouf18/quick-delivery-mobile/releases/latest/download/app.apk",
			Reason:                  "", // Missing reason
		}
		body, _ := json.Marshal(payload)
		req := httptest.NewRequest(http.MethodPut, "/admin/version", bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("X-Internal-Token", internalToken)
		req.Header.Set("X-Reviewer-Token", reviewerToken)
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("expected 400 Bad Request, got %d", rec.Code)
		}
	})

	t.Run("PUT With Invalid Download URL Fails", func(t *testing.T) {
		payload := ReviewerVersionUpdateRequest{
			LatestVersion:           "1.2.0",
			MinimumSupportedVersion: "1.1.0",
			DownloadURL:             "https://malicious-site.example.com/app.apk",
			Reason:                  "Legit update",
		}
		body, _ := json.Marshal(payload)
		req := httptest.NewRequest(http.MethodPut, "/admin/version", bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("X-Internal-Token", internalToken)
		req.Header.Set("X-Reviewer-Token", reviewerToken)
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("expected 400 Bad Request, got %d", rec.Code)
		}
	})

	t.Run("PUT Valid Updates Version Policy", func(t *testing.T) {
		enforce := true
		payload := ReviewerVersionUpdateRequest{
			LatestVersion:           "2.0.0",
			MinimumSupportedVersion: "1.5.0",
			EnforceMinimumVersion:   &enforce,
			DownloadURL:             "https://github.com/omarmaarouf18/quick-delivery-mobile/releases/latest/download/app-v2.apk",
			Reason:                  "Major release v2 with breaking API changes",
		}
		body, _ := json.Marshal(payload)
		req := httptest.NewRequest(http.MethodPut, "/admin/version", bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("X-Internal-Token", internalToken)
		req.Header.Set("X-Reviewer-Token", reviewerToken)
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 OK, got %d: %s", rec.Code, rec.Body.String())
		}

		// Verify GET returns new config
		getReq := httptest.NewRequest(http.MethodGet, "/admin/version", nil)
		getReq.Header.Set("X-Internal-Token", internalToken)
		getReq.Header.Set("X-Reviewer-Token", reviewerToken)
		getRec := httptest.NewRecorder()
		handler.ServeHTTP(getRec, getReq)
		var cfg version.PlatformVersions
		_ = json.Unmarshal(getRec.Body.Bytes(), &cfg)
		if cfg.LatestVersion != "2.0.0" || cfg.MinimumSupportedVersion != "1.5.0" || !cfg.EnforceMinimumVersion {
			t.Fatalf("unexpected config after update: %+v", cfg)
		}
	})
}

func TestReviewerVersionConfigHandler_MongoPersistence(t *testing.T) {
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://root:devpassword123@localhost:27017/?authSource=admin"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	client, err := mongo.Connect(options.Client().ApplyURI(mongoURI))
	if err != nil || client.Ping(ctx, nil) != nil {
		t.Skipf("skipping MongoDB persistence test; mongo not reachable: %v", err)
		return
	}
	defer client.Disconnect(context.Background())

	dbName := fmt.Sprintf("gateway_test_%d", time.Now().UnixNano())
	defer client.Database(dbName).Drop(context.Background())

	// Store 1: writes version config
	store1 := version.NewStore(client, dbName)
	newCfg := version.PlatformVersions{
		LatestVersion:           "3.1.4",
		MinimumSupportedVersion: "3.0.0",
		EnforceMinimumVersion:   true,
		DownloadURL:             "https://github.com/omarmaarouf18/quick-delivery-mobile/releases/latest/download/app.apk",
	}
	if _, err := store1.UpdateConfig(context.Background(), newCfg); err != nil {
		t.Fatalf("store1 UpdateConfig failed: %v", err)
	}

	// Store 2: simulates gateway restart with fresh store instance against the same database
	store2 := version.NewStore(client, dbName)
	recovered, err := store2.GetConfig(context.Background())
	if err != nil {
		t.Fatalf("store2 GetConfig failed: %v", err)
	}

	if recovered.LatestVersion != "3.1.4" || recovered.MinimumSupportedVersion != "3.0.0" {
		t.Fatalf("expected version config to persist across restarts, got latest=%s min=%s", recovered.LatestVersion, recovered.MinimumSupportedVersion)
	}
}

// TestReviewerVersionHandler_NeverForwardsClientForwardedFor pins that the
// gateway's reviewer version handler does not pass a client X-Forwarded-For
// (or X-Real-IP) to auth-service: rotating it reset the per-IP reviewer rate
// limit. auth-service only receives X-Console-Client-IP, taken from the
// console header (trusted after the internal token check) or RemoteAddr.
func TestReviewerVersionHandler_NeverForwardsClientForwardedFor(t *testing.T) {
	internalToken := "mock-internal-token-xff"
	type seen struct{ xff, xri, console string }
	var got []seen
	mockAuth := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		got = append(got, seen{r.Header.Get("X-Forwarded-For"), r.Header.Get("X-Real-IP"), r.Header.Get("X-Console-Client-IP")})
		w.WriteHeader(http.StatusUnauthorized)
		_, _ = w.Write([]byte(`{"error":"invalid reviewer token"}`))
	}))
	defer mockAuth.Close()

	handler := ReviewerVersionConfigHandler(internalToken, mockAuth.URL, mockAuth.Client(), version.NewStore(nil, ""))

	for i := 0; i < 3; i++ {
		req := httptest.NewRequest(http.MethodGet, "/admin/version", nil)
		req.RemoteAddr = "172.20.0.9:50000"
		req.Header.Set("X-Internal-Token", internalToken)
		req.Header.Set("X-Reviewer-Token", fmt.Sprintf("bad-%d", i))
		req.Header.Set("X-Forwarded-For", fmt.Sprintf("198.51.100.%d", i))
		req.Header.Set("X-Real-IP", fmt.Sprintf("198.51.101.%d", i))
		handler.ServeHTTP(httptest.NewRecorder(), req)
	}
	if len(got) != 3 {
		t.Fatalf("expected 3 verify calls, got %d", len(got))
	}
	for i, g := range got {
		if g.xff != "" || g.xri != "" {
			t.Fatalf("call %d forwarded client X-Forwarded-For=%q X-Real-IP=%q to auth-service", i, g.xff, g.xri)
		}
		if g.console != "172.20.0.9" {
			t.Fatalf("call %d: X-Console-Client-IP = %q, want RemoteAddr IP 172.20.0.9", i, g.console)
		}
	}

	// The console header is honoured (after the internal token check) when it is an IP.
	got = nil
	req := httptest.NewRequest(http.MethodGet, "/admin/version", nil)
	req.RemoteAddr = "172.20.0.9:50000"
	req.Header.Set("X-Internal-Token", internalToken)
	req.Header.Set("X-Reviewer-Token", "bad")
	req.Header.Set("X-Console-Client-IP", "203.0.113.10")
	handler.ServeHTTP(httptest.NewRecorder(), req)
	if len(got) != 1 || got[0].console != "203.0.113.10" {
		t.Fatalf("expected console client IP 203.0.113.10 forwarded, got %+v", got)
	}

	// Without the internal token nothing reaches auth-service.
	got = nil
	req = httptest.NewRequest(http.MethodGet, "/admin/version", nil)
	req.Header.Set("X-Internal-Token", "wrong")
	req.Header.Set("X-Reviewer-Token", "bad")
	req.Header.Set("X-Console-Client-IP", "203.0.113.10")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized || len(got) != 0 {
		t.Fatalf("expected 401 and no auth call without internal token, got %d and %d calls", rec.Code, len(got))
	}
}
