package handlers

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestCanAccessChannel(t *testing.T) {
	// Spin up a mock User Service to return job details
	mockUserServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		jobID := r.URL.Query().Get("id")

		if jobID == "valid-job-123" {
			w.WriteHeader(http.StatusOK)
			json.NewEncoder(w).Encode(map[string]string{
				"owner_id":    "job-owner-id",
				"employee_id": "job-employee-id",
			})
			return
		}

		if jobID == "job-no-employee" {
			w.WriteHeader(http.StatusOK)
			json.NewEncoder(w).Encode(map[string]string{
				"owner_id":    "job-owner-id",
				"employee_id": "",
			})
			return
		}

		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(map[string]string{"error": "job not found"})
	}))
	defer mockUserServer.Close()

	// Instantiate Chat handler group (we can pass nil hub and store as they aren't used in canAccessChannel)
	chatHandler := NewChat(nil, nil, "", mockUserServer.URL)

	tests := []struct {
		name       string
		userID     string
		channel    string
		expectAuth bool
	}{
		{
			name:       "Owner Authorized",
			userID:     "job-owner-id",
			channel:    "job:valid-job-123",
			expectAuth: true,
		},
		{
			name:       "Employee Authorized",
			userID:     "job-employee-id",
			channel:    "job:valid-job-123",
			expectAuth: true,
		},
		{
			name:       "Unauthorized User",
			userID:     "malicious-user-id",
			channel:    "job:valid-job-123",
			expectAuth: false,
		},
		{
			name:       "Empty Employee ID Gated",
			userID:     "",
			channel:    "job:job-no-employee",
			expectAuth: false,
		},
		{
			name:       "Job Not Found Gated",
			userID:     "job-owner-id",
			channel:    "job:non-existent-job",
			expectAuth: false,
		},
		{
			name:       "Non-Job Channel Gated",
			userID:     "job-owner-id",
			channel:    "general-channel",
			expectAuth: false,
		},
		{
			name:       "Malformed Channel Name Gated",
			userID:     "job-owner-id",
			channel:    "job:",
			expectAuth: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			allowed := chatHandler.canAccessChannel(tt.userID, tt.channel)
			if allowed != tt.expectAuth {
				t.Errorf("canAccessChannel(%q, %q) = %v; want %v", tt.userID, tt.channel, allowed, tt.expectAuth)
			}
		})
	}
}
