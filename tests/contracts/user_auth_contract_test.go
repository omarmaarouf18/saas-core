package contracts

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

// TestContract_UserToAuth_GetUser verifies the contract between:
// Consumer: user-service (checkKYC & verifyEmployeeAssignment in services/user-service/internal/handlers/handlers.go:531,567)
// Provider: auth-service (GetUser in services/auth-service/internal/handlers/auth.go:1050)
func TestContract_UserToAuth_GetUser(t *testing.T) {
	rootDir := FindProjectRoot(t)

	// 1. Source AST Verification
	t.Run("AST: Provider GetUser response map contains role, kyc_status, tenant_id, is_active, account_status", func(t *testing.T) {
		mapKeysList := InspectMapKeysInFunction(t, rootDir, "services/auth-service/internal/handlers/auth.go", "GetUser")

		requiredConsumerKeys := []string{"role", "kyc_status", "tenant_id", "is_active", "account_status"}
		foundAll := false
		for _, keys := range mapKeysList {
			missing := false
			for _, reqKey := range requiredConsumerKeys {
				found := false
				for _, k := range keys {
					if k == reqKey {
						found = true
						break
					}
				}
				if !found {
					missing = true
					break
				}
			}
			if !missing {
				foundAll = true
				break
			}
		}

		if !foundAll {
			t.Fatalf("Contract drift detected: auth-service GetUser response map missing required keys for user-service: %v", requiredConsumerKeys)
		}
	})

	// 2. Behavioral Round-Trip Contract Test
	t.Run("Round-Trip: Consumer checkKYC and verifyEmployeeAssignment evaluation", func(t *testing.T) {
		const testInternalToken = "internal-service-secret-token"

		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.Method != http.MethodGet {
				w.WriteHeader(http.StatusMethodNotAllowed)
				return
			}
			if r.Header.Get("X-Internal-Token") != testInternalToken {
				w.WriteHeader(http.StatusUnauthorized)
				return
			}

			id := r.URL.Query().Get("id")
			w.Header().Set("Content-Type", "application/json")

			switch id {
			case "owner-verified":
				_ = json.NewEncoder(w).Encode(map[string]any{
					"id":             "owner-verified",
					"role":           "owner",
					"kyc_status":     "verified",
					"is_active":      true,
					"account_status": "active",
					"tenant_id":      "owner-verified",
				})
			case "emp-active":
				_ = json.NewEncoder(w).Encode(map[string]any{
					"id":             "emp-active",
					"role":           "employee",
					"kyc_status":     "verified",
					"tenant_id":      "owner-verified",
					"is_active":      true,
					"account_status": "active",
				})
			case "emp-suspended":
				_ = json.NewEncoder(w).Encode(map[string]any{
					"id":             "emp-suspended",
					"role":           "employee",
					"kyc_status":     "verified",
					"tenant_id":      "owner-verified",
					"is_active":      false,
					"account_status": "suspended",
				})
			default:
				w.WriteHeader(http.StatusNotFound)
				_ = json.NewEncoder(w).Encode(map[string]string{"error": "user not found"})
			}
		}))
		defer server.Close()

		// Case A: Consumer checkKYC struct decoding (handlers.go:552)
		reqOwner, _ := http.NewRequest(http.MethodGet, server.URL+"/auth/user?id=owner-verified", nil)
		reqOwner.Header.Set("X-Internal-Token", testInternalToken)
		respOwner, err := http.DefaultClient.Do(reqOwner)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		defer respOwner.Body.Close()

		var kycUser struct {
			Role      string `json:"role"`
			KYCStatus string `json:"kyc_status"`
		}
		if err := json.NewDecoder(respOwner.Body).Decode(&kycUser); err != nil {
			t.Fatalf("Failed to decode kycUser: %v", err)
		}
		if kycUser.Role != "owner" || kycUser.KYCStatus != "verified" {
			t.Errorf("Unexpected KYC evaluation result: %+v", kycUser)
		}

		// Case B: Consumer verifyEmployeeAssignment decoding (handlers.go:588)
		reqEmp, _ := http.NewRequest(http.MethodGet, server.URL+"/auth/user?id=emp-active", nil)
		reqEmp.Header.Set("X-Internal-Token", testInternalToken)
		respEmp, err := http.DefaultClient.Do(reqEmp)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		defer respEmp.Body.Close()

		var empUser struct {
			Role          string `json:"role"`
			TenantID      string `json:"tenant_id"`
			IsActive      bool   `json:"is_active"`
			AccountStatus string `json:"account_status"`
		}
		if err := json.NewDecoder(respEmp.Body).Decode(&empUser); err != nil {
			t.Fatalf("Failed to decode empUser: %v", err)
		}
		if empUser.Role != "employee" || empUser.TenantID != "owner-verified" || !empUser.IsActive || empUser.AccountStatus != "active" {
			t.Errorf("Unexpected employee evaluation result: %+v", empUser)
		}
	})
}
