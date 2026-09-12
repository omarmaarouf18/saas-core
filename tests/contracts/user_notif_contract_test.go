package contracts

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

// TestContract_UserToNotif_Send verifies the contract between:
// Consumer: user-service (sendJobOfferNotification in jobs_handlers.go:2190)
// Provider: notification-service (Send in services/notification-service/internal/handlers/handlers.go:346)
func TestContract_UserToNotif_Send(t *testing.T) {
	rootDir := FindProjectRoot(t)

	// 1. Source AST Verification (Provider sendRequest tags vs Consumer map keys)
	t.Run("AST: Provider sendRequest struct tags match Consumer sendJobOfferNotification keys", func(t *testing.T) {
		providerFields := InspectStructInFile(t, rootDir, "services/notification-service/internal/handlers/handlers.go", "sendRequest")

		expectedContractTags := map[string]string{
			"Type":     "type",
			"TenantID": "tenant_id",
			"UserID":   "user_id",
			"Title":    "title",
			"Body":     "body",
			"Roles":    "roles",
		}

		for fieldName, expectedTag := range expectedContractTags {
			info, exists := providerFields[fieldName]
			if !exists {
				t.Fatalf("Contract violation: sendRequest struct is missing field %q", fieldName)
			}
			if info.JSONTag != expectedTag {
				t.Errorf("Contract drift: sendRequest.%s JSON tag is %q, expected %q", fieldName, info.JSONTag, expectedTag)
			}
		}

		// Verify Consumer map keys in sendJobOfferNotification (jobs_handlers.go:2190)
		consumerMapKeys := InspectMapKeysInFunction(t, rootDir, "services/user-service/internal/handlers/jobs_handlers.go", "sendJobOfferNotification")
		foundMatchingMap := false
		for _, keys := range consumerMapKeys {
			hasType, hasTenant, hasUser, hasTitle, hasBody := false, false, false, false, false
			for _, k := range keys {
				switch k {
				case "type":
					hasType = true
				case "tenant_id":
					hasTenant = true
				case "user_id":
					hasUser = true
				case "title":
					hasTitle = true
				case "body":
					hasBody = true
				}
			}
			if hasType && hasTenant && hasUser && hasTitle && hasBody {
				foundMatchingMap = true
				break
			}
		}

		if !foundMatchingMap {
			t.Fatalf("Contract drift detected: user-service sendJobOfferNotification payload map missing required contract keys")
		}
	})

	// 2. Behavioral Round-Trip Contract Test
	t.Run("Round-Trip: Consumer Payload Serialization and Provider Validation", func(t *testing.T) {
		const testInternalToken = "internal-service-secret-token"

		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.Method != http.MethodPost {
				w.WriteHeader(http.StatusMethodNotAllowed)
				return
			}
			if r.Header.Get("X-Internal-Token") != testInternalToken {
				w.WriteHeader(http.StatusUnauthorized)
				_ = json.NewEncoder(w).Encode(map[string]string{"error": "unauthorized: internal token required"})
				return
			}

			type sendRequest struct {
				Type     string   `json:"type"`
				TenantID string   `json:"tenant_id"`
				UserID   string   `json:"user_id,omitempty"`
				UserIDs  []string `json:"user_ids,omitempty"`
				Global   bool     `json:"global,omitempty"`
				Title    string   `json:"title"`
				Body     string   `json:"body"`
				Roles    []string `json:"roles,omitempty"`
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
			if req.TenantID == "" && !req.Global {
				w.WriteHeader(http.StatusBadRequest)
				_ = json.NewEncoder(w).Encode(map[string]string{"error": "tenant_id is required unless global is true"})
				return
			}

			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusOK)
			_ = json.NewEncoder(w).Encode(map[string]any{
				"message": "notification dispatched",
				"notification": map[string]any{
					"id":        "notif-test-101",
					"type":      req.Type,
					"tenant_id": req.TenantID,
					"user_id":   req.UserID,
					"title":     req.Title,
					"body":      req.Body,
				},
				"active_clients": 1,
			})
		}))
		defer server.Close()

		// Valid Consumer payload (jobs_handlers.go:2190)
		consumerPayload := map[string]any{
			"type":      "job_offer",
			"tenant_id": "tenant-contract-test",
			"user_id":   "emp-courier-42",
			"title":     "New Job Offer",
			"body":      "You have an incoming job offer for job-contract-test. Respond within 60 seconds.",
			"roles":     []string{"employee"},
		}
		bodyBytes, _ := json.Marshal(consumerPayload)

		req, err := http.NewRequest(http.MethodPost, server.URL+"/notifications/send", bytes.NewReader(bodyBytes))
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

		var providerResp map[string]any
		if err := json.NewDecoder(resp.Body).Decode(&providerResp); err != nil {
			t.Fatalf("Failed to decode response: %v", err)
		}
		if providerResp["message"] != "notification dispatched" {
			t.Errorf("Unexpected response message: %v", providerResp["message"])
		}

		// Negative Case: Missing TenantID when Global is false
		noTenantPayload := map[string]any{
			"type":    "job_offer",
			"title":   "New Job Offer",
			"body":    "Job offer without tenant",
			"user_id": "emp-courier-42",
		}
		badBytes, _ := json.Marshal(noTenantPayload)
		reqNoTenant, _ := http.NewRequest(http.MethodPost, server.URL+"/notifications/send", bytes.NewReader(badBytes))
		reqNoTenant.Header.Set("Content-Type", "application/json")
		reqNoTenant.Header.Set("X-Internal-Token", testInternalToken)
		respNoTenant, _ := http.DefaultClient.Do(reqNoTenant)
		defer respNoTenant.Body.Close()
		if respNoTenant.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected HTTP 400 for missing tenant_id, got %d", respNoTenant.StatusCode)
		}
	})
}

// TestContract_UserToNotif_BroadcastJobAlert verifies the contract between:
// Consumer: user-service (broadcastJobAlert in jobs_handlers.go:2500)
// Provider: notification-service (BroadcastJobAlert in services/notification-service/internal/handlers/handlers.go:441)
func TestContract_UserToNotif_BroadcastJobAlert(t *testing.T) {
	rootDir := FindProjectRoot(t)

	// 1. Source AST Verification
	t.Run("AST: Provider jobAlertRequest struct tags match Consumer broadcastJobAlert payload keys", func(t *testing.T) {
		providerFields := InspectStructInFile(t, rootDir, "services/notification-service/internal/handlers/handlers.go", "jobAlertRequest")

		expectedContractTags := map[string]string{
			"TenantID":    "tenant_id",
			"JobID":       "job_id",
			"EmployeeID":  "employee_id",
			"ServiceName": "service_name",
			"Description": "description",
		}

		for fieldName, expectedTag := range expectedContractTags {
			info, exists := providerFields[fieldName]
			if !exists {
				t.Fatalf("Contract violation: jobAlertRequest struct is missing field %q", fieldName)
			}
			if info.JSONTag != expectedTag {
				t.Errorf("Contract drift: jobAlertRequest.%s JSON tag is %q, expected %q", fieldName, info.JSONTag, expectedTag)
			}
		}

		// Verify Consumer map keys in broadcastJobAlert (jobs_handlers.go:2500)
		consumerMapKeys := InspectMapKeysInFunction(t, rootDir, "services/user-service/internal/handlers/jobs_handlers.go", "broadcastJobAlert")
		foundMatchingMap := false
		for _, keys := range consumerMapKeys {
			hasTenant, hasJob, hasEmp, hasSvc, hasDesc := false, false, false, false, false
			for _, k := range keys {
				switch k {
				case "tenant_id":
					hasTenant = true
				case "job_id":
					hasJob = true
				case "employee_id":
					hasEmp = true
				case "service_name":
					hasSvc = true
				case "description":
					hasDesc = true
				}
			}
			if hasTenant && hasJob && hasEmp && hasSvc && hasDesc {
				foundMatchingMap = true
				break
			}
		}

		if !foundMatchingMap {
			t.Fatalf("Contract drift detected: user-service broadcastJobAlert map payload missing required contract keys")
		}
	})

	// 2. Behavioral Round-Trip Contract Test
	t.Run("Round-Trip: Consumer Payload Serialization and Provider Validation", func(t *testing.T) {
		const testInternalToken = "internal-service-secret-token"

		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.Method != http.MethodPost {
				w.WriteHeader(http.StatusMethodNotAllowed)
				return
			}
			if r.Header.Get("X-Internal-Token") != testInternalToken {
				w.WriteHeader(http.StatusUnauthorized)
				_ = json.NewEncoder(w).Encode(map[string]string{"error": "unauthorized: internal token required"})
				return
			}

			type jobAlertRequest struct {
				TenantID    string `json:"tenant_id"`
				JobID       string `json:"job_id"`
				EmployeeID  string `json:"employee_id,omitempty"`
				ServiceName string `json:"service_name"`
				Description string `json:"description"`
			}

			var req jobAlertRequest
			dec := json.NewDecoder(r.Body)
			dec.DisallowUnknownFields()
			if err := dec.Decode(&req); err != nil {
				w.WriteHeader(http.StatusBadRequest)
				_ = json.NewEncoder(w).Encode(map[string]string{"error": "invalid JSON: " + err.Error()})
				return
			}

			if req.TenantID == "" || req.JobID == "" {
				w.WriteHeader(http.StatusBadRequest)
				_ = json.NewEncoder(w).Encode(map[string]string{"error": "tenant_id and job_id required"})
				return
			}

			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusOK)
			_ = json.NewEncoder(w).Encode(map[string]string{
				"message": "job alert broadcast dispatched",
				"job_id":  req.JobID,
			})
		}))
		defer server.Close()

		// Consumer payload (jobs_handlers.go:2518)
		consumerPayload := map[string]any{
			"tenant_id":    "tenant-xyz-777",
			"job_id":       "job-alert-contract-1",
			"employee_id":  "emp-alert-target",
			"service_name": "Ultra Fast Delivery",
			"description":  "Lat: 30.0444, Lon: 31.2357",
		}
		bodyBytes, _ := json.Marshal(consumerPayload)

		req, err := http.NewRequest(http.MethodPost, server.URL+"/notifications/broadcast/job-alert", bytes.NewReader(bodyBytes))
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

		// Negative Case: Missing JobID
		badPayload := map[string]any{
			"tenant_id":    "tenant-xyz-777",
			"service_name": "Ultra Fast Delivery",
			"description":  "Lat: 30.0444, Lon: 31.2357",
		}
		badBytes, _ := json.Marshal(badPayload)
		reqBad, _ := http.NewRequest(http.MethodPost, server.URL+"/notifications/broadcast/job-alert", bytes.NewReader(badBytes))
		reqBad.Header.Set("Content-Type", "application/json")
		reqBad.Header.Set("X-Internal-Token", testInternalToken)
		respBad, _ := http.DefaultClient.Do(reqBad)
		defer respBad.Body.Close()
		if respBad.StatusCode != http.StatusBadRequest {
			t.Errorf("Expected HTTP 400 for missing job_id, got %d", respBad.StatusCode)
		}
	})
}
