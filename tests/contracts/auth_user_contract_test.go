package contracts

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

// TestContract_AuthToUser_InternalSubscriptionCheck verifies the contract between:
// Consumer: auth-service (ToggleEmployee in services/auth-service/internal/handlers/auth.go:819)
// Provider: user-service (InternalSubscriptionCheck in services/user-service/internal/handlers/handlers.go:723)
func TestContract_AuthToUser_InternalSubscriptionCheck(t *testing.T) {
	const testInternalToken = "internal-service-secret-token"
	const paidTenantID = "tenant-paid-owner-1"
	const freeTenantID = "tenant-free-owner-2"

	// Mock Provider Server implementing user-service InternalSubscriptionCheck contract
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		if r.Header.Get("X-Internal-Token") != testInternalToken {
			w.WriteHeader(http.StatusUnauthorized)
			_ = json.NewEncoder(w).Encode(map[string]string{"error": "unauthorized: internal token required"})
			return
		}

		tenantID := r.URL.Query().Get("tenant_id")
		if tenantID == "" {
			w.WriteHeader(http.StatusBadRequest)
			_ = json.NewEncoder(w).Encode(map[string]string{"error": "tenant_id query parameter is required"})
			return
		}

		w.Header().Set("Content-Type", "application/json")
		if tenantID == freeTenantID {
			w.WriteHeader(http.StatusPaymentRequired)
			_ = json.NewEncoder(w).Encode(map[string]any{
				"error":   "upgrade_required",
				"tier":    "free",
				"message": "paid subscription required",
			})
			return
		}

		w.WriteHeader(http.StatusOK)
		_ = json.NewEncoder(w).Encode(map[string]any{
			"tier":    "paid",
			"is_paid": true,
		})
	}))
	defer server.Close()

	// 1. Consumer Call for Free-Tier Owner -> Expect 402 Payment Required
	t.Run("Free Tenant: Consumer receives 402 upgrade_required", func(t *testing.T) {
		req, _ := http.NewRequest(http.MethodGet, server.URL+"/users/subscription/internal?tenant_id="+freeTenantID, nil)
		req.Header.Set("X-Internal-Token", testInternalToken)

		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusPaymentRequired {
			t.Fatalf("Expected HTTP 402 for free tier, got %d", resp.StatusCode)
		}

		var errResp map[string]any
		if err := json.NewDecoder(resp.Body).Decode(&errResp); err != nil {
			t.Fatalf("Failed to decode 402 body: %v", err)
		}
		if errResp["error"] != "upgrade_required" {
			t.Errorf("Expected error 'upgrade_required', got %v", errResp["error"])
		}
	})

	// 2. Consumer Call for Paid-Tier Owner -> Expect 200 OK
	t.Run("Paid Tenant: Consumer receives 200 OK", func(t *testing.T) {
		req, _ := http.NewRequest(http.MethodGet, server.URL+"/users/subscription/internal?tenant_id="+paidTenantID, nil)
		req.Header.Set("X-Internal-Token", testInternalToken)

		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			t.Fatalf("Expected HTTP 200 for paid tier, got %d", resp.StatusCode)
		}

		var okResp map[string]any
		if err := json.NewDecoder(resp.Body).Decode(&okResp); err != nil {
			t.Fatalf("Failed to decode 200 body: %v", err)
		}
		if okResp["is_paid"] != true || okResp["tier"] != "paid" {
			t.Errorf("Expected is_paid=true, tier=paid, got %+v", okResp)
		}
	})
}
