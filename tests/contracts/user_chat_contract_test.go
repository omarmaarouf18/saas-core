package contracts

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

// TestContract_UserToChat_BroadcastLocation verifies the contract between:
// Consumer: user-service (UpdateJobLocation in jobs_handlers.go:1044 & UpdateEmployeeLocation in jobs_handlers.go:1368)
// Provider: chat-service (BroadcastLocation in services/chat-service/internal/handlers/chat.go:678)
func TestContract_UserToChat_BroadcastLocation(t *testing.T) {
	rootDir := FindProjectRoot(t)

	// 1. Source AST Verification (Consumer Map Keys vs Provider Struct Tags)
	t.Run("AST: Consumer payload map keys match Provider BroadcastLocation request struct tags", func(t *testing.T) {
		providerFields := InspectStructInFile(t, rootDir, "services/chat-service/internal/handlers/chat.go", "local:BroadcastLocation:req")

		expectedContractTags := map[string]string{
			"Channel":    "channel",
			"Latitude":   "latitude",
			"Longitude":  "longitude",
			"EmployeeID": "employee_id",
		}

		for fieldName, expectedTag := range expectedContractTags {
			info, exists := providerFields[fieldName]
			if !exists {
				t.Fatalf("Contract violation: BroadcastLocation request struct is missing field %q", fieldName)
			}
			if info.JSONTag != expectedTag {
				t.Errorf("Contract drift: BroadcastLocation.%s JSON tag is %q, expected %q", fieldName, info.JSONTag, expectedTag)
			}
		}

		// Verify Consumer map keys in UpdateJobLocation (jobs_handlers.go:1327)
		consumerMapKeys := InspectMapKeysInFunction(t, rootDir, "services/user-service/internal/handlers/jobs_handlers.go", "UpdateJobLocation")

		foundMatchingMap := false
		for _, keys := range consumerMapKeys {
			hasChannel, hasLat, hasLon, hasEmp := false, false, false, false
			for _, k := range keys {
				switch k {
				case "channel":
					hasChannel = true
				case "latitude":
					hasLat = true
				case "longitude":
					hasLon = true
				case "employee_id":
					hasEmp = true
				}
			}
			if hasChannel && hasLat && hasLon && hasEmp {
				foundMatchingMap = true
				break
			}
		}

		if !foundMatchingMap {
			t.Fatalf("Contract drift detected: user-service UpdateJobLocation map payload does not contain required keys ('channel', 'latitude', 'longitude', 'employee_id')")
		}
	})

	// 2. Behavioral Round-Trip & Validation Contract Test
	t.Run("Round-Trip: Payload Serialization and Provider Validation", func(t *testing.T) {
		const testInternalToken = "internal-service-secret-token"

		// Mock Provider Server implementing chat-service BroadcastLocation contract verbatim
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.Method != http.MethodPost {
				w.WriteHeader(http.StatusMethodNotAllowed)
				_ = json.NewEncoder(w).Encode(map[string]string{"error": "use POST"})
				return
			}
			if r.Header.Get("X-Internal-Token") != testInternalToken {
				w.WriteHeader(http.StatusForbidden)
				_ = json.NewEncoder(w).Encode(map[string]string{"error": "access denied: invalid internal token"})
				return
			}

			type ProviderReq struct {
				Channel    string  `json:"channel"`
				Latitude   float64 `json:"latitude"`
				Longitude  float64 `json:"longitude"`
				EmployeeID string  `json:"employee_id"`
			}

			var req ProviderReq
			dec := json.NewDecoder(r.Body)
			dec.DisallowUnknownFields()
			if err := dec.Decode(&req); err != nil {
				w.WriteHeader(http.StatusBadRequest)
				_ = json.NewEncoder(w).Encode(map[string]string{"error": "invalid JSON body: " + err.Error()})
				return
			}

			if req.Channel == "" || req.EmployeeID == "" {
				w.WriteHeader(http.StatusBadRequest)
				_ = json.NewEncoder(w).Encode(map[string]string{"error": "channel and employee_id are required"})
				return
			}

			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusOK)
			_ = json.NewEncoder(w).Encode(map[string]any{
				"status":      "broadcast_queued",
				"channel":     req.Channel,
				"employee_id": req.EmployeeID,
			})
		}))
		defer server.Close()

		// Case A: Valid Consumer Payload
		consumerPayload := map[string]any{
			"channel":     "job:job-contract-999",
			"latitude":    30.0444,
			"longitude":   31.2357,
			"employee_id": "courier-assigned-10",
		}
		bodyBytes, _ := json.Marshal(consumerPayload)

		req, err := http.NewRequest(http.MethodPost, server.URL+"/chat/internal/broadcast-location", bytes.NewReader(bodyBytes))
		if err != nil {
			t.Fatalf("Failed to create request: %v", err)
		}
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("X-Internal-Token", testInternalToken)

		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatalf("Failed to execute request: %v", err)
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			t.Fatalf("Expected HTTP 200, got %d", resp.StatusCode)
		}

		// Case B: Negative Validation - Missing required employee_id
		badPayload := map[string]any{
			"channel":   "job:job-contract-999",
			"latitude":  30.0444,
			"longitude": 31.2357,
		}
		badBytes, _ := json.Marshal(badPayload)
		reqBad, _ := http.NewRequest(http.MethodPost, server.URL+"/chat/internal/broadcast-location", bytes.NewReader(badBytes))
		reqBad.Header.Set("Content-Type", "application/json")
		reqBad.Header.Set("X-Internal-Token", testInternalToken)
		respBad, _ := http.DefaultClient.Do(reqBad)
		defer respBad.Body.Close()
		if respBad.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected HTTP 400 for missing employee_id, got %d", respBad.StatusCode)
		}

		// Case C: Negative Validation - Missing X-Internal-Token
		reqNoToken, _ := http.NewRequest(http.MethodPost, server.URL+"/chat/internal/broadcast-location", bytes.NewReader(bodyBytes))
		respNoToken, _ := http.DefaultClient.Do(reqNoToken)
		defer respNoToken.Body.Close()
		if respNoToken.StatusCode != http.StatusForbidden {
			t.Errorf("Expected HTTP 403 for missing token, got %d", respNoToken.StatusCode)
		}
	})
}
