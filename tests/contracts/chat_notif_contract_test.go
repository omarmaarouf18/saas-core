package contracts

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

// TestContract_ChatToNotif_TicketResolved verifies the contract between:
// Consumer: chat-service (dispatchTicketResolvedNotification in services/chat-service/internal/handlers/admin_tickets.go:135)
// Provider: notification-service (Send in services/notification-service/internal/handlers/handlers.go:346)
func TestContract_ChatToNotif_TicketResolved(t *testing.T) {
	rootDir := FindProjectRoot(t)

	// 1. Source AST Verification
	t.Run("AST: Consumer dispatchTicketResolvedNotification payload keys match Provider sendRequest", func(t *testing.T) {
		providerFields := InspectStructInFile(t, rootDir, "services/notification-service/internal/handlers/handlers.go", "sendRequest")

		requiredKeys := map[string]string{
			"Type":   "type",
			"Global": "global",
			"UserID": "user_id",
			"Title":  "title",
			"Body":   "body",
		}

		for fieldName, expectedTag := range requiredKeys {
			info, exists := providerFields[fieldName]
			if !exists {
				t.Fatalf("Contract violation: sendRequest is missing field %q", fieldName)
			}
			if info.JSONTag != expectedTag {
				t.Errorf("Contract drift: sendRequest.%s JSON tag is %q, expected %q", fieldName, info.JSONTag, expectedTag)
			}
		}

		// Verify Consumer map keys in dispatchTicketResolvedNotification
		consumerMapKeys := InspectMapKeysInFunction(t, rootDir, "services/chat-service/internal/handlers/admin_tickets.go", "dispatchTicketResolvedNotification")
		found := false
		for _, keys := range consumerMapKeys {
			hasType, hasGlobal, hasUserID, hasTitle, hasBody := false, false, false, false, false
			for _, k := range keys {
				switch k {
				case "type":
					hasType = true
				case "global":
					hasGlobal = true
				case "user_id":
					hasUserID = true
				case "title":
					hasTitle = true
				case "body":
					hasBody = true
				}
			}
			if hasType && hasGlobal && hasUserID && hasTitle && hasBody {
				found = true
				break
			}
		}

		if !found {
			t.Fatalf("Contract drift: chat-service dispatchTicketResolvedNotification payload does not contain required keys ('type', 'global', 'user_id', 'title', 'body')")
		}
	})

	// 2. Behavioral Round-Trip Contract Test: Global Flag Allows TenantID Omission
	t.Run("Round-Trip: Global flag satisfies Provider TenantID omission invariant", func(t *testing.T) {
		const testInternalToken = "internal-service-secret-token"

		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.Method != http.MethodPost {
				w.WriteHeader(http.StatusMethodNotAllowed)
				return
			}
			if r.Header.Get("X-Internal-Token") != testInternalToken {
				w.WriteHeader(http.StatusUnauthorized)
				return
			}

			type sendRequest struct {
				Type     string `json:"type"`
				TenantID string `json:"tenant_id"`
				UserID   string `json:"user_id,omitempty"`
				Global   bool   `json:"global,omitempty"`
				Title    string `json:"title"`
				Body     string `json:"body"`
			}

			var req sendRequest
			dec := json.NewDecoder(r.Body)
			dec.DisallowUnknownFields()
			if err := dec.Decode(&req); err != nil {
				w.WriteHeader(http.StatusBadRequest)
				_ = json.NewEncoder(w).Encode(map[string]string{"error": "invalid JSON: " + err.Error()})
				return
			}

			if req.Title == "" || req.Body == "" {
				w.WriteHeader(http.StatusBadRequest)
				_ = json.NewEncoder(w).Encode(map[string]string{"error": "title and body required"})
				return
			}
			// Strict Invariant: tenant_id required UNLESS global is true
			if req.TenantID == "" && !req.Global {
				w.WriteHeader(http.StatusBadRequest)
				_ = json.NewEncoder(w).Encode(map[string]string{"error": "tenant_id is required unless global is true"})
				return
			}

			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusOK)
			_ = json.NewEncoder(w).Encode(map[string]any{
				"message": "notification dispatched",
				"type":    req.Type,
				"global":  req.Global,
			})
		}))
		defer server.Close()

		// Consumer Payload (admin_tickets.go:146)
		payload := map[string]any{
			"type":    "ticket_resolved",
			"global":  true,
			"user_id": "cust-ticket-owner-7",
			"title":   "Support Ticket Resolved",
			"body":    "Your ticket (t-123) has been resolved: All good.",
		}
		bodyBytes, _ := json.Marshal(payload)

		req, err := http.NewRequest(http.MethodPost, server.URL+"/notifications/send", bytes.NewReader(bodyBytes))
		if err != nil {
			t.Fatalf("Failed to create request: %v", err)
		}
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("X-Internal-Token", testInternalToken)

		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			t.Fatalf("Expected HTTP 200, got %d", resp.StatusCode)
		}
	})
}
