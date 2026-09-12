package contracts

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

// TestContract_ChatToAuth_GetUser verifies the contract between:
// Consumer: chat-service (verifyUser & canAccessChannel in services/chat-service/internal/handlers/chat.go)
// Provider: auth-service (GetUser in services/auth-service/internal/handlers/auth.go)
func TestContract_ChatToAuth_GetUser(t *testing.T) {
	rootDir := FindProjectRoot(t)

	// 1. Source AST Verification (Static Schema Alignment Guard)
	t.Run("AST: Provider GetUser response map contains id, username, and role", func(t *testing.T) {
		mapKeysList := InspectMapKeysInFunction(t, rootDir, "services/auth-service/internal/handlers/auth.go", "GetUser")

		// Look for the main user profile response map
		foundExpectedKeys := false
		for _, keys := range mapKeysList {
			hasID := false
			hasUsername := false
			hasRole := false
			for _, k := range keys {
				if k == "id" {
					hasID = true
				}
				if k == "username" {
					hasUsername = true
				}
				if k == "role" {
					hasRole = true
				}
			}
			if hasID && hasUsername && hasRole {
				foundExpectedKeys = true
				break
			}
		}

		if !foundExpectedKeys {
			t.Fatalf("Contract drift detected: auth-service GetUser response map is missing required keys ('id', 'username', 'role') needed by chat-service")
		}
	})

	// 2. Consumer Expectation & Provider Serialization In-Process Test
	t.Run("Round-Trip: Consumer Unmarshaling and Field Constraints", func(t *testing.T) {
		const testInternalToken = "internal-secret-token-xyz"
		const testUserID = "usr-chat-customer-123"

		// Mock Provider Server implementing auth-service GET /auth/user contract
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.Method != http.MethodGet {
				w.WriteHeader(http.StatusMethodNotAllowed)
				return
			}
			if r.Header.Get("X-Internal-Token") != testInternalToken {
				w.WriteHeader(http.StatusUnauthorized)
				_ = json.NewEncoder(w).Encode(map[string]string{"error": "unauthorized"})
				return
			}
			id := r.URL.Query().Get("id")
			if id == "" {
				w.WriteHeader(http.StatusBadRequest)
				_ = json.NewEncoder(w).Encode(map[string]string{"error": "missing id"})
				return
			}
			if id != testUserID {
				w.WriteHeader(http.StatusNotFound)
				_ = json.NewEncoder(w).Encode(map[string]string{"error": "user not found"})
				return
			}

			// Canonical auth-service response shape
			resp := map[string]any{
				"id":                 id,
				"email":              "chat-test@example.com",
				"role":               "customer",
				"username":           "chatuser1",
				"phone":              "+1234567890",
				"frequent_addresses": []string{},
				"tenant_id":          "tenant-xyz",
				"kyc_status":         "verified",
				"is_active":          true,
				"account_status":     "active",
			}
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusOK)
			_ = json.NewEncoder(w).Encode(resp)
		}))
		defer server.Close()

		// A. Verify Consumer 1: verifyUser struct (chat.go:174)
		req, err := http.NewRequest(http.MethodGet, server.URL+"/auth/user?id="+testUserID, nil)
		if err != nil {
			t.Fatalf("Failed to create request: %v", err)
		}
		req.Header.Set("X-Internal-Token", testInternalToken)

		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatalf("Failed to execute request: %v", err)
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			t.Fatalf("Expected HTTP 200, got %d", resp.StatusCode)
		}

		var verifyUserConsumer struct {
			ID       string `json:"id"`
			Username string `json:"username"`
		}
		if err := json.NewDecoder(resp.Body).Decode(&verifyUserConsumer); err != nil {
			t.Fatalf("Failed to decode into verifyUser consumer struct: %v", err)
		}
		if verifyUserConsumer.ID != testUserID {
			t.Errorf("Consumer expected ID %q, got %q", testUserID, verifyUserConsumer.ID)
		}
		if verifyUserConsumer.Username != "chatuser1" {
			t.Errorf("Consumer expected Username 'chatuser1', got %q", verifyUserConsumer.Username)
		}

		// B. Verify Consumer 2: canAccessChannel fleet check (chat.go:225)
		req2, _ := http.NewRequest(http.MethodGet, server.URL+"/auth/user?id="+testUserID, nil)
		req2.Header.Set("X-Internal-Token", testInternalToken)
		resp2, err := http.DefaultClient.Do(req2)
		if err != nil {
			t.Fatalf("Failed to execute request 2: %v", err)
		}
		defer resp2.Body.Close()

		var fleetChannelConsumer struct {
			ID   string `json:"id"`
			Role string `json:"role"`
		}
		if err := json.NewDecoder(resp2.Body).Decode(&fleetChannelConsumer); err != nil {
			t.Fatalf("Failed to decode into fleetChannel consumer struct: %v", err)
		}
		if fleetChannelConsumer.ID != testUserID || fleetChannelConsumer.Role != "customer" {
			t.Errorf("Consumer mismatch: got ID=%q Role=%q", fleetChannelConsumer.ID, fleetChannelConsumer.Role)
		}

		// C. Verify Negative Case: Missing/Invalid token rejected
		reqUnauthorized, _ := http.NewRequest(http.MethodGet, server.URL+"/auth/user?id="+testUserID, nil)
		respUnauth, err := http.DefaultClient.Do(reqUnauthorized)
		if err != nil {
			t.Fatalf("Failed to execute unauthorized request: %v", err)
		}
		defer respUnauth.Body.Close()
		if respUnauth.StatusCode != http.StatusUnauthorized {
			t.Errorf("Expected HTTP 401 for missing X-Internal-Token, got %d", respUnauth.StatusCode)
		}
	})
}

// TestContract_ChatToAuth_VerifyReviewer verifies the contract between:
// Consumer: chat-service (authenticateReviewer in services/chat-service/internal/handlers/admin_tickets.go:47)
// Provider: auth-service (VerifyReviewer in services/auth-service/internal/handlers/auth.go:2438)
func TestContract_ChatToAuth_VerifyReviewer(t *testing.T) {
	rootDir := FindProjectRoot(t)

	// 1. Source AST Verification
	t.Run("AST: Consumer ReviewerClaims matches Provider VerifyReviewer response fields", func(t *testing.T) {
		consumerFields := InspectStructInFile(t, rootDir, "services/chat-service/internal/handlers/admin_tickets.go", "ReviewerClaims")
		if consumerFields["ID"].JSONTag != "id" {
			t.Errorf("ReviewerClaims.ID tag mismatch: expected 'id', got %q", consumerFields["ID"].JSONTag)
		}
		if consumerFields["Name"].JSONTag != "name" {
			t.Errorf("ReviewerClaims.Name tag mismatch: expected 'name', got %q", consumerFields["Name"].JSONTag)
		}

		mapKeysList := InspectMapKeysInFunction(t, rootDir, "services/auth-service/internal/handlers/auth.go", "VerifyReviewer")
		found := false
		for _, keys := range mapKeysList {
			hasID, hasName := false, false
			for _, k := range keys {
				if k == "id" {
					hasID = true
				}
				if k == "name" {
					hasName = true
				}
			}
			if hasID && hasName {
				found = true
				break
			}
		}
		if !found {
			t.Fatalf("Contract drift detected: auth-service VerifyReviewer does not return expected keys 'id' and 'name'")
		}
	})

	// 2. Strict Deserialization Contract Test
	t.Run("Strict Round-Trip: ReviewerClaims Deserialization", func(t *testing.T) {
		providerPayload := []byte(`{"id":"rev-101","name":"Senior Reviewer Alice"}`)

		type ReviewerClaims struct {
			ID   string `json:"id"`
			Name string `json:"name"`
		}

		var claims ReviewerClaims
		if err := StrictUnmarshal(providerPayload, &claims); err != nil {
			t.Fatalf("Strict deserialization failed on provider payload: %v", err)
		}
		if claims.ID != "rev-101" || claims.Name != "Senior Reviewer Alice" {
			t.Errorf("Deserialized claims mismatch: %+v", claims)
		}
	})
}
