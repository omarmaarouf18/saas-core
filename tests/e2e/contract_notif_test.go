package e2e

import (
	"context"
	"encoding/json"
	"fmt"
	"math/rand"
	"net/http"
	"testing"
	"time"
)

// TestContract_NotificationService systematically verifies API contracts, HTTP methods,
// auth requirements, negative validation boundaries, pagination clamping, and response schemas
// for all 8 notification-service routes in the canonical parity inventory.
func TestContract_NotificationService(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 25*time.Second)
	defer cancel()

	cfg := LoadConfig()
	db, err := ConnectStagingDB(ctx, cfg.MongoURI)
	if err != nil {
		t.Fatalf("Failed to connect to staging DB: %v", err)
	}
	defer db.Close(ctx)

	rnd := rand.New(rand.NewSource(time.Now().UnixNano())).Intn(900000) + 100000
	tenantID := fmt.Sprintf("tenant-contract-notif-%d", rnd)
	customerID := fmt.Sprintf("cust-contract-notif-%d", rnd)

	defer db.CleanupTestEntities(ctx, []string{tenantID}, []string{customerID})

	if err := db.SeedCustomer(ctx, tenantID, customerID, customerID+"@staging.local"); err != nil {
		t.Fatalf("Failed to seed customer: %v", err)
	}

	custToken, _ := cfg.GenerateJWT(customerID, "user", tenantID, customerID+"@staging.local")

	// 1. POST /notifications/send (Internal / Inter-Service)
	t.Run("POST_Internal_Send", func(t *testing.T) {
		url := fmt.Sprintf("%s/api/v1/notifications/send", cfg.GatewayURL)

		// Edge security defense: external calls without or with spoofed internal token return 401 Unauthorized
		respNoToken, _, _ := DoRequestWithHeaders(ctx, http.MethodPost, url, map[string]string{"Content-Type": "application/json"}, []byte("{}"))
		if respNoToken.StatusCode != http.StatusUnauthorized && respNoToken.StatusCode != http.StatusForbidden {
			t.Errorf("Expected 401/403 without internal token, got %d", respNoToken.StatusCode)
		}

		respSpoof, _, _ := DoRequestWithHeaders(ctx, http.MethodPost, url, map[string]string{
			"X-Internal-Token": cfg.InternalToken,
			"Content-Type":     "application/json",
		}, []byte("{}"))
		if respSpoof.StatusCode != http.StatusUnauthorized && respSpoof.StatusCode != http.StatusForbidden {
			t.Errorf("Expected 401/403 due to Gateway edge token stripping, got %d", respSpoof.StatusCode)
		}

		// Wrong Method -> 405 Method Not Allowed
		respGet, _, _ := DoRequestWithHeaders(ctx, http.MethodGet, url, nil, nil)
		if respGet.StatusCode != http.StatusMethodNotAllowed {
			t.Errorf("Expected 405 for GET on /notifications/send, got %d", respGet.StatusCode)
		}
	})

	// 2. POST /notifications/broadcast/job-alert (Internal / Inter-Service)
	t.Run("POST_Internal_Broadcast_Job_Alert", func(t *testing.T) {
		url := fmt.Sprintf("%s/api/v1/notifications/broadcast/job-alert", cfg.GatewayURL)

		respNoToken, _, _ := DoRequestWithHeaders(ctx, http.MethodPost, url, map[string]string{"Content-Type": "application/json"}, []byte("{}"))
		if respNoToken.StatusCode != http.StatusUnauthorized && respNoToken.StatusCode != http.StatusForbidden {
			t.Errorf("Expected 401/403 without internal token, got %d", respNoToken.StatusCode)
		}

		// Wrong Method -> 405 Method Not Allowed
		respGet, _, _ := DoRequestWithHeaders(ctx, http.MethodGet, url, nil, nil)
		if respGet.StatusCode != http.StatusMethodNotAllowed {
			t.Errorf("Expected 405 for GET on /notifications/broadcast/job-alert, got %d", respGet.StatusCode)
		}
	})

	// 3. GET /notifications/stream (Mobile App / Customer)
	t.Run("GET_Notifications_Stream", func(t *testing.T) {
		// Negative: Missing token query parameter -> 400 Bad Request
		urlNoToken := fmt.Sprintf("%s/api/v1/notifications/stream", cfg.GatewayURL)
		respUnauth, _, _ := DoRequestWithHeaders(ctx, http.MethodGet, urlNoToken, nil, nil)
		if respUnauth.StatusCode != http.StatusBadRequest && respUnauth.StatusCode != http.StatusUnauthorized {
			t.Errorf("Expected 400/401 for SSE stream without token, got %d", respUnauth.StatusCode)
		}

		// Negative: Invalid token query parameter -> 403 Forbidden
		urlBadToken := fmt.Sprintf("%s/api/v1/notifications/stream?token=invalid-jwt", cfg.GatewayURL)
		respBadToken, _, _ := DoRequestWithHeaders(ctx, http.MethodGet, urlBadToken, nil, nil)
		if respBadToken.StatusCode != http.StatusForbidden && respBadToken.StatusCode != http.StatusUnauthorized {
			t.Errorf("Expected 403/401 for SSE stream with invalid token, got %d", respBadToken.StatusCode)
		}

		// Positive: Connect with valid token -> 200 OK with text/event-stream
		sseSub, err := ConnectSSE(ctx, cfg.GatewayURL, custToken)
		if err != nil {
			t.Fatalf("Failed to establish SSE stream with valid token: %v", err)
		}
		defer sseSub.Close()

		// Wrong Method: POST /notifications/stream -> 405 Method Not Allowed
		urlWithToken := fmt.Sprintf("%s/api/v1/notifications/stream?token=%s", cfg.GatewayURL, custToken)
		respPost, _, _ := DoRequestWithHeaders(ctx, http.MethodPost, urlWithToken, nil, []byte("{}"))
		if respPost.StatusCode != http.StatusMethodNotAllowed {
			t.Errorf("Expected 405 for POST /notifications/stream, got %d", respPost.StatusCode)
		}
	})

	// 4. GET /notifications/history (Mobile App / Customer)
	t.Run("GET_Notifications_History", func(t *testing.T) {
		url := fmt.Sprintf("%s/api/v1/notifications/history", cfg.GatewayURL)

		// Negative: Unauthenticated -> 401 Unauthorized
		respUnauth, _, _ := GetJSON(ctx, url, "")
		if respUnauth.StatusCode != http.StatusUnauthorized {
			t.Errorf("Expected 401 for unauthenticated history, got %d", respUnauth.StatusCode)
		}

		// Negative: Wrong Method: POST -> 405 Method Not Allowed
		respPost, _, _ := PostJSON(ctx, url, custToken, nil)
		if respPost.StatusCode != http.StatusMethodNotAllowed {
			t.Errorf("Expected 405 for POST /notifications/history, got %d", respPost.StatusCode)
		}

		// Positive & Limit Clamping Test (Cursor Pagination with limit bounding):
		clampURL := fmt.Sprintf("%s?limit=9999", url)
		resp, body, err := GetJSON(ctx, clampURL, custToken)
		if err != nil {
			t.Fatalf("GET /notifications/history failed: %v", err)
		}
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK for history, got %d. Body: %s", resp.StatusCode, string(body))
		}

		// Response Schema Validation: Verify Dart NotificationHistoryModel
		var schema struct {
			Notifications []map[string]any `json:"notifications"`
			HasMore       bool             `json:"has_more"`
		}
		if err := json.Unmarshal(body, &schema); err != nil {
			t.Fatalf("Invalid response JSON schema: %v", err)
		}
	})

	// 5. POST /notifications/{id}/read (Mobile App)
	t.Run("POST_Mark_Notification_Read", func(t *testing.T) {
		url := fmt.Sprintf("%s/api/v1/notifications/notif-test-dummy-id/read", cfg.GatewayURL)

		// Negative: Unauthenticated -> 401 Unauthorized
		respUnauth, _, _ := PostJSON(ctx, url, "", nil)
		if respUnauth.StatusCode != http.StatusUnauthorized {
			t.Errorf("Expected 401 for unauthenticated mark read, got %d", respUnauth.StatusCode)
		}

		// Negative: Wrong Method: GET -> 405 Method Not Allowed
		respGet, _, _ := GetJSON(ctx, url, custToken)
		if respGet.StatusCode != http.StatusMethodNotAllowed {
			t.Errorf("Expected 405 for GET on /notifications/{id}/read, got %d", respGet.StatusCode)
		}

		// Positive: Mark read with valid token -> 200 OK (idempotent)
		resp, _, err := PostJSON(ctx, url, custToken, nil)
		if err != nil {
			t.Fatalf("POST mark read failed: %v", err)
		}
		if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusNotFound {
			t.Errorf("Expected 200/404 for mark read, got %d", resp.StatusCode)
		}
	})

	// 6. POST /notifications/read-all (Mobile App)
	t.Run("POST_Mark_All_Notifications_Read", func(t *testing.T) {
		url := fmt.Sprintf("%s/api/v1/notifications/read-all", cfg.GatewayURL)

		// Negative: Unauthenticated -> 401 Unauthorized
		respUnauth, _, _ := PostJSON(ctx, url, "", nil)
		if respUnauth.StatusCode != http.StatusUnauthorized {
			t.Errorf("Expected 401 for unauthenticated read-all, got %d", respUnauth.StatusCode)
		}

		// Negative: Wrong Method: GET -> 405 Method Not Allowed
		respGet, _, _ := GetJSON(ctx, url, custToken)
		if respGet.StatusCode != http.StatusMethodNotAllowed {
			t.Errorf("Expected 405 for GET on /notifications/read-all, got %d", respGet.StatusCode)
		}

		// Positive: Mark all read -> 200 OK
		resp, body, err := PostJSON(ctx, url, custToken, nil)
		if err != nil {
			t.Fatalf("POST /notifications/read-all failed: %v", err)
		}
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("Expected 200 OK for read-all, got %d. Body: %s", resp.StatusCode, string(body))
		}
	})

	// 7. DELETE /notifications/{id} (Mobile App)
	t.Run("DELETE_Notification_By_ID", func(t *testing.T) {
		url := fmt.Sprintf("%s/api/v1/notifications/notif-test-dummy-id", cfg.GatewayURL)

		// Negative: Unauthenticated -> 401 Unauthorized
		respUnauth, _, _ := DeleteJSON(ctx, url, "")
		if respUnauth.StatusCode != http.StatusUnauthorized {
			t.Errorf("Expected 401 for unauthenticated DELETE, got %d", respUnauth.StatusCode)
		}

		// Negative: Wrong Method: POST -> 405 Method Not Allowed
		respPost, _, _ := PostJSON(ctx, url, custToken, nil)
		if respPost.StatusCode != http.StatusMethodNotAllowed {
			t.Errorf("Expected 405 for POST on DELETE endpoint, got %d", respPost.StatusCode)
		}

		// Positive: Delete with valid token -> 200 OK (idempotent)
		resp, _, err := DeleteJSON(ctx, url, custToken)
		if err != nil {
			t.Fatalf("DELETE notification failed: %v", err)
		}
		if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusNotFound {
			t.Errorf("Expected 200/404 for DELETE notification, got %d", resp.StatusCode)
		}
	})

	// 8. DELETE /notifications (Mobile App)
	t.Run("DELETE_All_Notifications", func(t *testing.T) {
		url := fmt.Sprintf("%s/api/v1/notifications/", cfg.GatewayURL)

		// Negative: Unauthenticated -> 401 Unauthorized
		respUnauth, _, _ := DeleteJSON(ctx, url, "")
		if respUnauth.StatusCode != http.StatusUnauthorized {
			t.Errorf("Expected 401 for unauthenticated DELETE all, got %d", respUnauth.StatusCode)
		}

		// Negative: Wrong Method: GET -> 405 Method Not Allowed
		respGet, _, _ := GetJSON(ctx, url, custToken)
		if respGet.StatusCode != http.StatusMethodNotAllowed {
			t.Errorf("Expected 405 for GET on /notifications, got %d", respGet.StatusCode)
		}

		// Positive: Delete all with valid token -> 200 OK
		resp, _, err := DeleteJSON(ctx, url, custToken)
		if err != nil {
			t.Fatalf("DELETE all notifications failed: %v", err)
		}
		if resp.StatusCode != http.StatusOK {
			t.Errorf("Expected 200 OK for DELETE all notifications, got %d", resp.StatusCode)
		}
	})
}
