package contracts

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// TestContract_NotifToAuth_GetUser_DeviceTokens verifies the contract between:
// Consumer: notification-service (HTTPDeviceTokenFetcher.GetUserDeviceTokens in services/notification-service/internal/hub/fetcher.go:33)
// Provider: auth-service (GetUser in services/auth-service/internal/handlers/auth.go:1050)
//
// NOTE: During the Phase 4 contract test audit, a REAL UNDETECTED SCHEMA DRIFT was discovered:
// Consumer expects "device_tokens": [{"token": "..."}], but Provider's GetUser handler
// currently constructs an explicit response map that omits "device_tokens".
func TestContract_NotifToAuth_GetUser_DeviceTokens(t *testing.T) {
	rootDir := FindProjectRoot(t)

	// 1. Audit Drift Detection: Check if auth-service GetUser populates device_tokens
	t.Run("Audit: Detect real schema drift in Provider GetUser response map", func(t *testing.T) {
		mapKeysList := InspectMapKeysInFunction(t, rootDir, "services/auth-service/internal/handlers/auth.go", "GetUser")
		hasDeviceTokensKey := false
		for _, keys := range mapKeysList {
			for _, k := range keys {
				if k == "device_tokens" {
					hasDeviceTokensKey = true
					break
				}
			}
		}

		if !hasDeviceTokensKey {
			t.Errorf("REAL SCHEMA DRIFT DETECTED: auth-service GetUser response map omits 'device_tokens', though notification-service HTTPDeviceTokenFetcher explicitly decodes 'device_tokens' (fetcher.go:51)")
		}
	})

	// 2. Behavioral Consumer Deserialization Contract Test
	t.Run("Round-Trip: Consumer DeviceToken Extraction from Provider Payload", func(t *testing.T) {
		const testInternalToken = "internal-secret-token-xyz"
		const testUserID = "usr-driver-fcm-123"

		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.Method != http.MethodGet {
				w.WriteHeader(http.StatusMethodNotAllowed)
				return
			}
			if r.Header.Get("X-Internal-Token") != testInternalToken {
				w.WriteHeader(http.StatusUnauthorized)
				return
			}

			// Contract-compliant payload with device_tokens
			resp := map[string]any{
				"id":        testUserID,
				"email":     "driver@example.com",
				"role":      "employee",
				"is_active": true,
				"device_tokens": []map[string]string{
					{"token": "fcm-device-token-alpha"},
					{"token": "fcm-device-token-beta"},
					{"token": ""}, // empty token should be ignored
				},
			}
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusOK)
			_ = json.NewEncoder(w).Encode(resp)
		}))
		defer server.Close()

		req, _ := http.NewRequest(http.MethodGet, server.URL+"/auth/user?id="+testUserID, nil)
		req.Header.Set("X-Internal-Token", testInternalToken)

		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatalf("Failed to execute request: %v", err)
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			t.Fatalf("Expected HTTP 200, got %d", resp.StatusCode)
		}

		// Consumer decoding logic verbatim from notification-service fetcher.go:51-67
		var user struct {
			DeviceTokens []struct {
				Token string `json:"token"`
			} `json:"device_tokens"`
		}

		if err := json.NewDecoder(resp.Body).Decode(&user); err != nil {
			t.Fatalf("Consumer failed to decode device_tokens: %v", err)
		}

		tokens := make([]string, 0, len(user.DeviceTokens))
		for _, dt := range user.DeviceTokens {
			if strings.TrimSpace(dt.Token) != "" {
				tokens = append(tokens, dt.Token)
			}
		}

		if len(tokens) != 2 {
			t.Fatalf("Expected 2 non-empty tokens, got %d: %+v", len(tokens), tokens)
		}
		if tokens[0] != "fcm-device-token-alpha" || tokens[1] != "fcm-device-token-beta" {
			t.Errorf("Unexpected extracted tokens: %+v", tokens)
		}
	})
}

// TestContract_NotifToAuth_UnregisterStaleToken verifies the contract between:
// Consumer: notification-service (HTTPDeviceTokenFetcher.UnregisterStaleToken in services/notification-service/internal/hub/fetcher.go)
// Provider: auth-service (UnregisterStaleDeviceToken in services/auth-service/internal/handlers/internal_device_token.go)
//
// BE-HARDEN item 3: the cleanup used to POST /auth/device-token with only the
// X-Internal-Token header, but that endpoint requires a user JWT — every
// stale-token cleanup was answered with 401 and the consumer ignored the
// status code, so the stale token was never removed.
func TestContract_NotifToAuth_UnregisterStaleToken(t *testing.T) {
	rootDir := FindProjectRoot(t)

	const providerRoute = "/auth/internal/device-token/unregister"
	const consumerFile = "services/notification-service/internal/hub/fetcher.go"
	const providerFile = "services/auth-service/internal/handlers/internal_device_token.go"
	const providerRoutesFile = "services/auth-service/internal/handlers/auth.go"

	// 1. The provider registers the internal route on the auth-service mux.
	t.Run("Provider registers the internal unregister route", func(t *testing.T) {
		routes := InspectRouteRegistrations(t, rootDir, providerRoutesFile, "RegisterRoutes")
		handler, ok := routes[providerRoute]
		if !ok {
			t.Fatalf("auth-service does not register %s", providerRoute)
		}
		if handler != "UnregisterStaleDeviceToken" {
			t.Errorf("expected %s to be served by UnregisterStaleDeviceToken, got %q", providerRoute, handler)
		}
	})

	// 2. The provider authenticates the caller with the internal token and
	// only accepts POST.
	t.Run("Provider requires the internal token and only accepts POST", func(t *testing.T) {
		literals := InspectFunctionStringLiterals(t, rootDir, providerFile, "UnregisterStaleDeviceToken")
		if !ContainsString(literals, "X-Internal-Token") {
			t.Errorf("expected the provider to read the X-Internal-Token header, literals: %v", literals)
		}
		selectors := InspectFunctionSelectorNames(t, rootDir, providerFile, "UnregisterStaleDeviceToken")
		if !ContainsString(selectors, "MethodPost") {
			t.Errorf("expected the provider to accept POST only, selectors: %v", selectors)
		}
	})

	// 3. The consumer calls that route with the internal token and the token
	// in the body.
	t.Run("Consumer posts the token to the provider route", func(t *testing.T) {
		literals := InspectFunctionStringLiterals(t, rootDir, consumerFile, "UnregisterStaleToken")
		// The consumer builds the URL with fmt.Sprintf, so the route is part
		// of the format string.
		callsProviderRoute := false
		for _, lit := range literals {
			if strings.Contains(lit, providerRoute) {
				callsProviderRoute = true
				break
			}
		}
		if !callsProviderRoute {
			t.Errorf("expected the consumer to call %s, literals: %v", providerRoute, literals)
		}
		if !ContainsString(literals, "X-Internal-Token") {
			t.Errorf("expected the consumer to send the X-Internal-Token header, literals: %v", literals)
		}
		if !ContainsString(literals, "token") {
			t.Errorf("expected the consumer to send the token field, literals: %v", literals)
		}
		selectors := InspectFunctionSelectorNames(t, rootDir, consumerFile, "UnregisterStaleToken")
		if !ContainsString(selectors, "MethodPost") {
			t.Errorf("expected the consumer to use POST, selectors: %v", selectors)
		}
	})

	// 4. Strict Deserialization Contract Test
	t.Run("Strict Round-Trip: Provider Deserialization of Unregister Payload", func(t *testing.T) {
		reqFields := InspectStructInFile(t, rootDir, providerFile, "DeviceTokenUnregisterRequest")

		if reqFields["Token"].JSONTag != "token" {
			t.Errorf("DeviceTokenUnregisterRequest.Token expected 'token', got %q", reqFields["Token"].JSONTag)
		}

		// Verbatim payload generated by the consumer (fetcher.go):
		// json.Marshal(map[string]string{"token": token})
		consumerPayload := []byte(`{"token":"stale-fcm-tok-999"}`)

		type providerRequest struct {
			Token string `json:"token"`
		}

		var providerReq providerRequest
		if err := StrictUnmarshal(consumerPayload, &providerReq); err != nil {
			t.Fatalf("Provider failed strict unmarshaling of consumer payload: %v", err)
		}

		if providerReq.Token != "stale-fcm-tok-999" {
			t.Errorf("Provider received unexpected request values: %+v", providerReq)
		}
	})
}
