package fcm

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

// TestFCMPush_Success tests successful push delivery and verifies JSON payload shape
func TestFCMPush_Success(t *testing.T) {
	var receivedPayload FCMMessagePayload

	fcmServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" {
			t.Errorf("Expected POST request, got %s", r.Method)
		}
		if r.Header.Get("Content-Type") != "application/json" {
			t.Errorf("Expected application/json header, got %s", r.Header.Get("Content-Type"))
		}

		if err := json.NewDecoder(r.Body).Decode(&receivedPayload); err != nil {
			t.Fatalf("Failed to decode FCM payload: %v", err)
		}

		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"name":"projects/test-project/messages/123456"}`))
	}))
	defer fcmServer.Close()

	client := NewClient("dummy-json", "test-project", fcmServer.URL, "http://localhost:3002", "secret", fcmServer.Client())
	if !client.IsEnabled() {
		t.Fatalf("Expected FCM client to be enabled")
	}

	ctx := context.Background()
	isStale, err := client.SendPush(ctx, "device-token-123", "Test Title", "Test Body Message", map[string]string{
		"id":   "notif-1",
		"type": "job_alert",
	})

	if err != nil {
		t.Fatalf("Expected no error, got %v", err)
	}
	if isStale {
		t.Fatalf("Expected isStale to be false for 200 OK")
	}

	// Verify payload shape
	if receivedPayload.Message.Token != "device-token-123" {
		t.Errorf("Expected token 'device-token-123', got %q", receivedPayload.Message.Token)
	}
	if receivedPayload.Message.Notification.Title != "Test Title" {
		t.Errorf("Expected title 'Test Title', got %q", receivedPayload.Message.Notification.Title)
	}
	if receivedPayload.Message.Notification.Body != "Test Body Message" {
		t.Errorf("Expected body 'Test Body Message', got %q", receivedPayload.Message.Notification.Body)
	}
	if receivedPayload.Message.Data["type"] != "job_alert" {
		t.Errorf("Expected data.type 'job_alert', got %q", receivedPayload.Message.Data["type"])
	}
}

// TestFCMPush_StaleTokenHandling tests detection of invalid/expired/unregistered device tokens
func TestFCMPush_StaleTokenHandling(t *testing.T) {
	fcmServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNotFound)
		errResp := FCMErrorResponse{}
		errResp.Error.Code = 404
		errResp.Error.Message = "Requested entity was not found."
		errResp.Error.Status = "NOT_FOUND"
		errResp.Error.Details = []struct {
			ErrorCode string `json:"errorCode"`
		}{
			{ErrorCode: "UNREGISTERED"},
		}
		_ = json.NewEncoder(w).Encode(errResp)
	}))
	defer fcmServer.Close()

	client := NewClient("dummy-json", "test-project", fcmServer.URL, "http://localhost:3002", "secret", fcmServer.Client())

	ctx := context.Background()
	isStale, err := client.SendPush(ctx, "expired-device-token", "Title", "Body", nil)

	if !isStale {
		t.Errorf("Expected isStale to be true for UNREGISTERED token response")
	}
	if err == nil {
		t.Errorf("Expected error for expired token, got nil")
	}
}

// TestFCMPush_DisabledMode tests that missing config results in graceful no-op
func TestFCMPush_DisabledMode(t *testing.T) {
	client := NewClient("", "", "", "", "", nil)

	if client.IsEnabled() {
		t.Errorf("Expected client to be disabled when credentials are empty")
	}

	ctx := context.Background()
	isStale, err := client.SendPush(ctx, "token-1", "Title", "Body", nil)

	if err != nil {
		t.Errorf("Expected no error when FCM is disabled, got %v", err)
	}
	if isStale {
		t.Errorf("Expected isStale to be false when FCM is disabled")
	}
}

// TestFCMPush_NoInternalTokenToGoogle reproduces the credential-leak defect:
// the internal service auth header was attached UNCONDITIONALLY, including on
// requests to the real FCM endpoint when no custom relay was configured.
// X-Internal-Token authenticates service-to-service calls inside our own
// network; handing it to Google (or whatever host the default endpoint points
// at) leaks an internal shared secret.
//
// Pre-fix expectation: default-mode client (no custom endpoint) still sends
// X-Internal-Token.
// Post-fix expectation: header sent ONLY for custom relay endpoints.
func TestFCMPush_NoInternalTokenToGoogle(t *testing.T) {
	var gotInternalToken string
	stub := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotInternalToken = r.Header.Get("X-Internal-Token")
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]any{"name": "projects/p/messages/1"})
	}))
	defer stub.Close()

	// Production default mode: credentials+project set, NO custom endpoint.
	c := NewClient(`{"type":"service_account"}`, "proj-1", "", "http://auth", "secret-internal-token", nil)
	if !c.IsEnabled() {
		t.Fatal("client should be enabled")
	}
	// Intercept the outbound call without changing the client's endpoint MODE.
	c.endpointURL = stub.URL

	// NOTE: SendPush's current success path returns (false, nil) on HTTP 200
	// — a pre-existing quirk outside this item's scope; only header behavior
	// is under test here.
	_, _ = c.SendPush(context.Background(), "device-token", "t", "b", nil)

	if gotInternalToken != "" {
		t.Errorf("INTERNAL TOKEN LEAKED TO EXTERNAL HOST: X-Internal-Token=%q was sent to the default (Google) endpoint", gotInternalToken)
	}
}

// Companion assertion: custom relay endpoints DO carry the internal token.
func TestFCMPush_InternalTokenPresentOnCustomRelay(t *testing.T) {
	var gotInternalToken string
	stub := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotInternalToken = r.Header.Get("X-Internal-Token")
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]any{"name": "projects/p/messages/1"})
	}))
	defer stub.Close()

	c := NewClient(`{"type":"service_account"}`, "", stub.URL, "http://auth", "secret-internal-token", nil)
	_, _ = c.SendPush(context.Background(), "device-token", "t", "b", nil)

	if gotInternalToken != "secret-internal-token" {
		t.Errorf("custom relay endpoint lost its internal auth header: got %q", gotInternalToken)
	}
}
