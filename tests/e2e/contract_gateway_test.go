package e2e

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"testing"
	"time"
)

// TestContract_APIGateway systematically verifies the API contracts, HTTP methods,
// auth requirements, negative validation boundaries, and response schemas for all
// 5 api-gateway routes in the canonical parity inventory.
func TestContract_APIGateway(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	cfg := LoadConfig()

	// 1. GET / (Infra / Health)
	t.Run("GET_Root_Index", func(t *testing.T) {
		url := cfg.GatewayURL + "/"
		resp, body, err := DoRequestWithHeaders(ctx, http.MethodGet, url, nil, nil)
		if err != nil {
			t.Fatalf("GET / failed: %v", err)
		}
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK, got %d", resp.StatusCode)
		}
		var schema struct {
			Service string `json:"service"`
			Version string `json:"version"`
		}
		if err := json.Unmarshal(body, &schema); err != nil {
			t.Fatalf("Invalid response JSON schema: %v", err)
		}
		if schema.Service != "api-gateway" {
			t.Errorf("Expected service 'api-gateway', got %q", schema.Service)
		}

		// Wrong Method -> 405 Method Not Allowed
		respPost, _, _ := DoRequestWithHeaders(ctx, http.MethodPost, url, nil, []byte("{}"))
		if respPost.StatusCode != http.StatusMethodNotAllowed && respPost.StatusCode != http.StatusNotFound {
			t.Errorf("Expected 405/404 for POST /, got %d", respPost.StatusCode)
		}
	})

	// 2. GET /health (Infra / Health)
	t.Run("GET_Health", func(t *testing.T) {
		url := cfg.GatewayURL + "/health"
		resp, body, err := DoRequestWithHeaders(ctx, http.MethodGet, url, nil, nil)
		if err != nil {
			t.Fatalf("GET /health failed: %v", err)
		}
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK, got %d", resp.StatusCode)
		}
		var schema struct {
			Status string `json:"status"`
		}
		if err := json.Unmarshal(body, &schema); err != nil {
			t.Fatalf("Invalid response JSON schema: %v", err)
		}
		if schema.Status != "ok" {
			t.Errorf("Expected status 'ok', got %q", schema.Status)
		}

		// Wrong Method: POST /health -> 405 Method Not Allowed
		respPost, bodyPost, _ := DoRequestWithHeaders(ctx, http.MethodPost, url, nil, []byte("{}"))
		if respPost.StatusCode != http.StatusMethodNotAllowed {
			t.Errorf("Expected 405 for POST /health, got %d. Body: %s", respPost.StatusCode, string(bodyPost))
		}
	})

	// 3. GET /health/internal (Infra / Health)
	t.Run("GET_Health_Internal", func(t *testing.T) {
		url := cfg.GatewayURL + "/health/internal"

		// Negative: Missing X-Internal-Token -> 403 Forbidden
		respNoToken, _, _ := DoRequestWithHeaders(ctx, http.MethodGet, url, nil, nil)
		if respNoToken.StatusCode != http.StatusForbidden {
			t.Errorf("Expected 403 Forbidden without internal token, got %d", respNoToken.StatusCode)
		}

		// Negative: Bad X-Internal-Token -> 403 Forbidden
		respBadToken, _, _ := DoRequestWithHeaders(ctx, http.MethodGet, url, map[string]string{"X-Internal-Token": "invalid-token"}, nil)
		if respBadToken.StatusCode != http.StatusForbidden {
			t.Errorf("Expected 403 Forbidden with bad internal token, got %d", respBadToken.StatusCode)
		}

		// Positive: Valid X-Internal-Token -> 200 OK
		headers := map[string]string{"X-Internal-Token": cfg.InternalToken}
		resp, body, err := DoRequestWithHeaders(ctx, http.MethodGet, url, headers, nil)
		if err != nil {
			t.Fatalf("GET /health/internal failed: %v", err)
		}
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK, got %d", resp.StatusCode)
		}
		var schema struct {
			Status       string `json:"status"`
			Dependencies any    `json:"dependencies"`
		}
		if err := json.Unmarshal(body, &schema); err != nil {
			t.Fatalf("Invalid response JSON: %v", err)
		}
		if schema.Status != "ok" {
			t.Errorf("Expected status 'ok', got %q", schema.Status)
		}

		// Wrong Method: POST /health/internal -> 405 Method Not Allowed
		respPost, _, _ := DoRequestWithHeaders(ctx, http.MethodPost, url, headers, []byte("{}"))
		if respPost.StatusCode != http.StatusMethodNotAllowed {
			t.Errorf("Expected 405 for POST /health/internal, got %d", respPost.StatusCode)
		}
	})

	// 4. GET /api/v1/admin/version-config (Admin / Requires X-Admin-Token) [QA-GAP-01, SEC-02]
	t.Run("GET_Admin_Version_Config", func(t *testing.T) {
		url := cfg.GatewayURL + "/api/v1/admin/version-config"

		// Negative: Missing X-Admin-Token -> 403 Forbidden
		respNoToken, _, _ := DoRequestWithHeaders(ctx, http.MethodGet, url, nil, nil)
		if respNoToken.StatusCode != http.StatusForbidden {
			t.Errorf("Expected 403 Forbidden without admin token, got %d", respNoToken.StatusCode)
		}

		// Negative: Invalid X-Admin-Token -> 403 Forbidden
		respBadToken, _, _ := DoRequestWithHeaders(ctx, http.MethodGet, url, map[string]string{"X-Admin-Token": "bad-token"}, nil)
		if respBadToken.StatusCode != http.StatusForbidden {
			t.Errorf("Expected 403 Forbidden with bad admin token, got %d", respBadToken.StatusCode)
		}

		// Negative (SEC-02 lockdown): the internal service token alone must
		// NOT grant access to the admin endpoint.
		respInternalOnly, _, _ := DoRequestWithHeaders(ctx, http.MethodGet, url, map[string]string{"X-Internal-Token": cfg.InternalToken}, nil)
		if respInternalOnly.StatusCode != http.StatusForbidden {
			t.Errorf("Expected 403 Forbidden when only X-Internal-Token is presented, got %d", respInternalOnly.StatusCode)
		}

		// Positive: Valid X-Admin-Token -> 200 OK
		headers := map[string]string{"X-Admin-Token": cfg.AdminToken}
		resp, body, err := DoRequestWithHeaders(ctx, http.MethodGet, url, headers, nil)
		if err != nil {
			t.Fatalf("GET version-config failed: %v", err)
		}
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK with valid admin token, got %d. Body: %s", resp.StatusCode, string(body))
		}

		// Response Schema Validation: Verify PlatformVersions fields
		var schema struct {
			LatestVersion           string `json:"latest_version"`
			MinimumSupportedVersion string `json:"minimum_supported_version"`
			EnforceMinimumVersion   bool   `json:"enforce_minimum_version"`
			DownloadURL             string `json:"download_url"`
		}
		if err := json.Unmarshal(body, &schema); err != nil {
			t.Fatalf("Response schema mismatch for version-config: %v", err)
		}
		if schema.LatestVersion == "" {
			t.Errorf("Expected latest_version to be populated in response")
		}

		// Wrong Method: DELETE /api/v1/admin/version-config -> 405 Method Not Allowed
		respDel, _, _ := DoRequestWithHeaders(ctx, http.MethodDelete, url, headers, nil)
		if respDel.StatusCode != http.StatusMethodNotAllowed {
			t.Errorf("Expected 405 Method Not Allowed for DELETE, got %d", respDel.StatusCode)
		}
	})

	// 5. PUT /api/v1/admin/version-config (Admin / Requires X-Admin-Token) [QA-GAP-01, SEC-02]
	t.Run("PUT_Admin_Version_Config", func(t *testing.T) {
		url := cfg.GatewayURL + "/api/v1/admin/version-config"
		headers := map[string]string{
			"X-Admin-Token": cfg.AdminToken,
			"Content-Type":  "application/json",
		}

		// Negative: Missing X-Admin-Token -> 403 Forbidden
		respNoToken, _, _ := DoRequestWithHeaders(ctx, http.MethodPut, url, map[string]string{"Content-Type": "application/json"}, []byte("{}"))
		if respNoToken.StatusCode != http.StatusForbidden {
			t.Errorf("Expected 403 Forbidden without admin token, got %d", respNoToken.StatusCode)
		}

		// Negative (SEC-02 lockdown): internal token alone -> 403 Forbidden
		respInternalOnly, _, _ := DoRequestWithHeaders(ctx, http.MethodPut, url, map[string]string{
			"X-Internal-Token": cfg.InternalToken,
			"Content-Type":     "application/json",
		}, []byte("{}"))
		if respInternalOnly.StatusCode != http.StatusForbidden {
			t.Errorf("Expected 403 Forbidden when only X-Internal-Token is presented, got %d", respInternalOnly.StatusCode)
		}

		// Negative: Malformed JSON -> 400 Bad Request
		respBadJSON, _, _ := DoRequestWithHeaders(ctx, http.MethodPut, url, headers, []byte("{not-json"))
		if respBadJSON.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 Bad Request for malformed JSON, got %d", respBadJSON.StatusCode)
		}

		// Negative: Invalid Version Format -> 400 Bad Request
		badVersionPayload := []byte(`{"latest_version": "invalid-semver", "minimum_supported_version": "1.0.0"}`)
		respBadVersion, _, _ := DoRequestWithHeaders(ctx, http.MethodPut, url, headers, badVersionPayload)
		if respBadVersion.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 Bad Request for invalid semver, got %d", respBadVersion.StatusCode)
		}

		// Negative (SEC-02): download_url outside github.com/play.google.com -> 400 Bad Request
		badURLPayload := []byte(`{
			"latest_version": "1.2.0",
			"minimum_supported_version": "1.0.0",
			"download_url": "https://example.com/app-release.apk"
		}`)
		respBadURL, _, _ := DoRequestWithHeaders(ctx, http.MethodPut, url, headers, badURLPayload)
		if respBadURL.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected 400 Bad Request for disallowed download_url host, got %d", respBadURL.StatusCode)
		}

		// Positive: Valid Version Update -> 200 OK
		validPayload := []byte(`{
			"latest_version": "1.2.0",
			"minimum_supported_version": "1.0.0",
			"enforce_minimum_version": false,
			"download_url": "https://github.com/omarmaarouf18/quick-delivery-mobile/releases/latest/download/app-release.apk"
		}`)
		resp, body, err := DoRequestWithHeaders(ctx, http.MethodPut, url, headers, validPayload)
		if err != nil {
			t.Fatalf("PUT version-config failed: %v", err)
		}
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK for valid version update, got %d. Body: %s", resp.StatusCode, string(body))
		}

		// Response schema check
		var respMap map[string]any
		if err := json.Unmarshal(body, &respMap); err != nil {
			t.Fatalf("Response is not valid JSON: %v", err)
		}
		if !strings.Contains(fmt.Sprintf("%v", respMap["message"]), "success") {
			t.Errorf("Expected success message in response, got: %s", string(body))
		}
	})
}
