package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/project/gateway/internal/version"
)

func TestVersionConfigHandler(t *testing.T) {
	adminToken := "test-admin-token-12345"
	internalToken := "test-internal-token-12345"
	store := version.NewStore(nil, "")
	handler := VersionConfigHandler(adminToken, store)

	t.Run("GET_Forbidden_MissingToken", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/api/v1/admin/version-config", nil)
		rec := httptest.NewRecorder()

		handler.ServeHTTP(rec, req)

		if rec.Code != http.StatusForbidden {
			t.Errorf("Expected 403 Forbidden, got %d", rec.Code)
		}
	})

	t.Run("GET_Forbidden_WrongToken", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/api/v1/admin/version-config", nil)
		req.Header.Set("X-Admin-Token", "wrong-token")
		rec := httptest.NewRecorder()

		handler.ServeHTTP(rec, req)

		if rec.Code != http.StatusForbidden {
			t.Errorf("Expected 403 Forbidden, got %d", rec.Code)
		}
	})

	// SEC-02: the internal service token (known to every service) must NOT
	// grant access to the admin endpoint.
	t.Run("GET_Forbidden_InternalTokenRejected", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/api/v1/admin/version-config", nil)
		req.Header.Set("X-Internal-Token", internalToken)
		rec := httptest.NewRecorder()

		handler.ServeHTTP(rec, req)

		if rec.Code != http.StatusForbidden {
			t.Errorf("Expected 403 Forbidden when only X-Internal-Token is presented, got %d", rec.Code)
		}
	})

	// SEC-02: unconfigured admin credential must deny everything (fail
	// closed), even when the header happens to be empty as well.
	t.Run("GET_Forbidden_UnconfiguredAdminToken", func(t *testing.T) {
		unconfigured := VersionConfigHandler("", version.NewStore(nil, ""))
		req := httptest.NewRequest(http.MethodGet, "/api/v1/admin/version-config", nil)
		rec := httptest.NewRecorder()

		unconfigured.ServeHTTP(rec, req)

		if rec.Code != http.StatusForbidden {
			t.Errorf("Expected 403 Forbidden when admin token is unconfigured, got %d", rec.Code)
		}
	})

	t.Run("GET_Success", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/api/v1/admin/version-config", nil)
		req.Header.Set("X-Admin-Token", adminToken)
		rec := httptest.NewRecorder()

		handler.ServeHTTP(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK, got %d", rec.Code)
		}

		var cfg version.PlatformVersions
		if err := json.Unmarshal(rec.Body.Bytes(), &cfg); err != nil {
			t.Fatalf("Failed to parse response body: %v", err)
		}
		if cfg.LatestVersion == "" || cfg.MinimumSupportedVersion == "" {
			t.Errorf("Expected default platform versions, got %+v", cfg)
		}
	})

	t.Run("PUT_Forbidden_MissingToken", func(t *testing.T) {
		body := bytes.NewReader([]byte(`{}`))
		req := httptest.NewRequest(http.MethodPut, "/api/v1/admin/version-config", body)
		rec := httptest.NewRecorder()

		handler.ServeHTTP(rec, req)

		if rec.Code != http.StatusForbidden {
			t.Errorf("Expected 403 Forbidden, got %d", rec.Code)
		}
	})

	t.Run("PUT_Forbidden_InternalTokenRejected", func(t *testing.T) {
		body := bytes.NewReader([]byte(`{}`))
		req := httptest.NewRequest(http.MethodPut, "/api/v1/admin/version-config", body)
		req.Header.Set("X-Internal-Token", internalToken)
		rec := httptest.NewRecorder()

		handler.ServeHTTP(rec, req)

		if rec.Code != http.StatusForbidden {
			t.Errorf("Expected 403 Forbidden when only X-Internal-Token is presented, got %d", rec.Code)
		}
	})

	t.Run("PUT_BadRequest_MalformedJSON", func(t *testing.T) {
		body := bytes.NewReader([]byte(`{"latest_version": broken json`))
		req := httptest.NewRequest(http.MethodPut, "/api/v1/admin/version-config", body)
		req.Header.Set("X-Admin-Token", adminToken)
		rec := httptest.NewRecorder()

		handler.ServeHTTP(rec, req)

		if rec.Code != http.StatusBadRequest {
			t.Errorf("Expected 400 Bad Request, got %d", rec.Code)
		}
	})

	t.Run("PUT_BadRequest_InvalidSemver", func(t *testing.T) {
		badPayload := version.PlatformVersions{
			LatestVersion:           "not-valid-semver",
			MinimumSupportedVersion: "1.0.0",
			DownloadURL:             "https://github.com/omarmaarouf18/quick-delivery-mobile/releases/latest/download/app-release.apk",
		}
		payloadBytes, _ := json.Marshal(badPayload)
		req := httptest.NewRequest(http.MethodPut, "/api/v1/admin/version-config", bytes.NewReader(payloadBytes))
		req.Header.Set("X-Admin-Token", adminToken)
		rec := httptest.NewRecorder()

		handler.ServeHTTP(rec, req)

		if rec.Code != http.StatusBadRequest {
			t.Errorf("Expected 400 Bad Request for invalid semver, got %d", rec.Code)
		}
	})

	// SEC-02: download_url may only be https on github.com/play.google.com,
	// so an update can never point clients at an arbitrary APK host.
	t.Run("PUT_BadRequest_DownloadURLValidation", func(t *testing.T) {
		cases := []struct {
			name string
			url  string
		}{
			{"NonHttpsScheme", "http://github.com/omarmaarouf18/quick-delivery-mobile/releases/latest/download/app-release.apk"},
			{"DisallowedHost", "https://evil.example.com/app-release.apk"},
			{"LookalikeHost", "https://github.com.evil.example.com/app-release.apk"},
			{"Empty", ""},
		}
		for _, tc := range cases {
			t.Run(tc.name, func(t *testing.T) {
				payload := version.PlatformVersions{
					LatestVersion:           "2.1.0",
					MinimumSupportedVersion: "1.2.0",
					DownloadURL:             tc.url,
				}
				payloadBytes, _ := json.Marshal(payload)
				req := httptest.NewRequest(http.MethodPut, "/api/v1/admin/version-config", bytes.NewReader(payloadBytes))
				req.Header.Set("X-Admin-Token", adminToken)
				rec := httptest.NewRecorder()

				handler.ServeHTTP(rec, req)

				if rec.Code != http.StatusBadRequest {
					t.Fatalf("Expected 400 Bad Request for %s download_url %q, got %d: %s", tc.name, tc.url, rec.Code, rec.Body.String())
				}
			})
		}
	})

	t.Run("PUT_Success", func(t *testing.T) {
		validPayload := version.PlatformVersions{
			LatestVersion:           "2.1.0",
			MinimumSupportedVersion: "1.2.0",
			EnforceMinimumVersion:   true,
			DownloadURL:             "https://github.com/omarmaarouf18/quick-delivery-mobile/releases/latest/download/app-release.apk",
		}
		payloadBytes, _ := json.Marshal(validPayload)
		req := httptest.NewRequest(http.MethodPut, "/api/v1/admin/version-config", bytes.NewReader(payloadBytes))
		req.Header.Set("X-Admin-Token", adminToken)
		rec := httptest.NewRecorder()

		handler.ServeHTTP(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK, got %d: %s", rec.Code, rec.Body.String())
		}

		var resp struct {
			Message string                   `json:"message"`
			Config  version.PlatformVersions `json:"config"`
		}
		if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
			t.Fatalf("Failed to parse response body: %v", err)
		}
		if resp.Config.LatestVersion != "2.1.0" || resp.Config.MinimumSupportedVersion != "1.2.0" {
			t.Errorf("Unexpected updated config: %+v", resp.Config)
		}
	})

	t.Run("PUT_Success_PlayStoreDownloadURL", func(t *testing.T) {
		validPayload := version.PlatformVersions{
			LatestVersion:           "2.2.0",
			MinimumSupportedVersion: "1.2.0",
			DownloadURL:             "https://play.google.com/store/apps/details?id=com.project.quickdelivery",
		}
		payloadBytes, _ := json.Marshal(validPayload)
		req := httptest.NewRequest(http.MethodPut, "/api/v1/admin/version-config", bytes.NewReader(payloadBytes))
		req.Header.Set("X-Admin-Token", adminToken)
		rec := httptest.NewRecorder()

		handler.ServeHTTP(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("Expected 200 OK for play.google.com download_url, got %d: %s", rec.Code, rec.Body.String())
		}
	})

	t.Run("MethodNotAllowed", func(t *testing.T) {
		for _, method := range []string{http.MethodPost, http.MethodDelete, http.MethodPatch} {
			req := httptest.NewRequest(method, "/api/v1/admin/version-config", nil)
			req.Header.Set("X-Admin-Token", adminToken)
			rec := httptest.NewRecorder()

			handler.ServeHTTP(rec, req)

			if rec.Code != http.StatusMethodNotAllowed {
				t.Errorf("Expected 405 Method Not Allowed for %s, got %d", method, rec.Code)
			}
		}
	})
}
