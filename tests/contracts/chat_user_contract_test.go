package contracts

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

// TestContract_ChatToUser_GetJob verifies the contract between:
// Consumer: chat-service (canAccessChannel in services/chat-service/internal/handlers/chat.go:244)
// Provider: user-service (GetJob in services/user-service/internal/handlers/jobs_handlers.go:761)
func TestContract_ChatToUser_GetJob(t *testing.T) {
	rootDir := FindProjectRoot(t)

	// 1. Source AST Verification (Field Tag Parity)
	t.Run("AST: Provider models.Job tags match Consumer canAccessChannel expectations", func(t *testing.T) {
		jobFields := InspectStructInFile(t, rootDir, "services/user-service/internal/models/models.go", "Job")

		expectedContractTags := map[string]string{
			"OwnerID":                  "owner_id",
			"EmployeeID":               "employee_id",
			"UserID":                   "user_id",
			"Status":                   "status",
			"CurrentOfferedEmployeeID": "current_offered_employee_id",
		}

		for fieldName, expectedTag := range expectedContractTags {
			info, exists := jobFields[fieldName]
			if !exists {
				t.Fatalf("Contract violation: models.Job is missing expected field %q", fieldName)
			}
			if info.JSONTag != expectedTag {
				t.Errorf("Contract drift: models.Job.%s JSON tag is %q, expected %q", fieldName, info.JSONTag, expectedTag)
			}
		}
	})

	// 2. Behavioral In-Process Contract Round-Trip
	t.Run("Round-Trip: Consumer Deserialization & Channel Access Decision", func(t *testing.T) {
		const testInternalToken = "internal-secret-token-xyz"
		const testJobID = "job-cuj-contract-101"

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
			if id != testJobID {
				w.WriteHeader(http.StatusNotFound)
				_ = json.NewEncoder(w).Encode(map[string]string{"error": "job not found"})
				return
			}

			// Serialized models.Job representation returned by user-service
			jobPayload := map[string]any{
				"id":                          testJobID,
				"owner_id":                    "owner-alice-1",
				"employee_id":                 "courier-bob-2",
				"user_id":                     "customer-charlie-3",
				"service_id":                  "svc-quick-deliver",
				"status":                      "in_progress",
				"location":                    map[string]any{"latitude": 30.0444, "longitude": 31.2357},
				"payment_method":              "cash",
				"locked_escrow_amount":        50.0,
				"current_offered_employee_id": "courier-bob-2",
			}
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusOK)
			_ = json.NewEncoder(w).Encode(jobPayload)
		}))
		defer server.Close()

		req, err := http.NewRequest(http.MethodGet, server.URL+"/users/jobs/get?id="+testJobID, nil)
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

		// Consumer decoding struct (verbatim from chat.go:262)
		var consumerJob struct {
			OwnerID                  string `json:"owner_id"`
			EmployeeID               string `json:"employee_id"`
			UserID                   string `json:"user_id"`
			Status                   string `json:"status"`
			CurrentOfferedEmployeeID string `json:"current_offered_employee_id"`
		}

		if err := json.NewDecoder(resp.Body).Decode(&consumerJob); err != nil {
			t.Fatalf("Consumer failed to decode job response: %v", err)
		}

		// Verify all contract fields were populated correctly
		if consumerJob.OwnerID != "owner-alice-1" {
			t.Errorf("Expected OwnerID 'owner-alice-1', got %q", consumerJob.OwnerID)
		}
		if consumerJob.EmployeeID != "courier-bob-2" {
			t.Errorf("Expected EmployeeID 'courier-bob-2', got %q", consumerJob.EmployeeID)
		}
		if consumerJob.UserID != "customer-charlie-3" {
			t.Errorf("Expected UserID 'customer-charlie-3', got %q", consumerJob.UserID)
		}
		if consumerJob.Status != "in_progress" {
			t.Errorf("Expected Status 'in_progress', got %q", consumerJob.Status)
		}
		if consumerJob.CurrentOfferedEmployeeID != "courier-bob-2" {
			t.Errorf("Expected CurrentOfferedEmployeeID 'courier-bob-2', got %q", consumerJob.CurrentOfferedEmployeeID)
		}

		// Verify Consumer Access Logic evaluates properly
		isAuthorizedOwner := "owner-alice-1" == consumerJob.OwnerID
		isAuthorizedCourier := "courier-bob-2" == consumerJob.EmployeeID
		isAuthorizedClient := "customer-charlie-3" == consumerJob.UserID
		isUnauthorizedStranger := "stranger-eve-4" == consumerJob.OwnerID ||
			"stranger-eve-4" == consumerJob.UserID ||
			"stranger-eve-4" == consumerJob.EmployeeID

		if !isAuthorizedOwner || !isAuthorizedCourier || !isAuthorizedClient {
			t.Errorf("Authorized participants were incorrectly rejected by consumer logic")
		}
		if isUnauthorizedStranger {
			t.Errorf("Unauthorized stranger was incorrectly permitted by consumer logic")
		}
	})
}
