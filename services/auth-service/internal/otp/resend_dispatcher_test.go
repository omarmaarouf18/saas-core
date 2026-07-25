package otp

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestResendDispatcher_Dispatch_Success(t *testing.T) {
	apiKey := "re_123456789"
	fromEmail := "onboarding@resend.dev"
	targetEmail := "user@example.com"
	otpCode := "654321"

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Verify HTTP Method and Path
		if r.Method != http.MethodPost {
			t.Errorf("expected POST method, got %s", r.Method)
		}

		// Verify Authorization Header
		authHeader := r.Header.Get("Authorization")
		if authHeader != "Bearer "+apiKey {
			t.Errorf("expected Authorization header 'Bearer %s', got %q", apiKey, authHeader)
		}

		// Verify Content-Type Header
		if contentType := r.Header.Get("Content-Type"); contentType != "application/json" {
			t.Errorf("expected Content-Type application/json, got %q", contentType)
		}

		// Verify JSON Body
		var req ResendRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			t.Fatalf("failed to decode JSON request: %v", err)
		}

		if req.From != fromEmail {
			t.Errorf("expected From %q, got %q", fromEmail, req.From)
		}
		if len(req.To) != 1 || req.To[0] != targetEmail {
			t.Errorf("expected To [%q], got %v", targetEmail, req.To)
		}
		if !strings.Contains(req.HTML, otpCode) {
			t.Errorf("expected HTML payload to contain code %s, got %s", otpCode, req.HTML)
		}
		if !strings.Contains(req.Text, otpCode) {
			t.Errorf("expected Text payload to contain code %s, got %s", otpCode, req.Text)
		}

		// Respond with 200 OK and Resend ID
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"id":"re_msg_987654321"}`))
	}))
	defer server.Close()

	dispatcher := NewResendDispatcherWithClient(apiKey, fromEmail, server.URL, server.Client())

	if name := dispatcher.Name(); name != "Resend" {
		t.Errorf("expected Name() 'Resend', got %q", name)
	}

	err := dispatcher.Dispatch(targetEmail, otpCode)
	if err != nil {
		t.Fatalf("expected nil error on success, got: %v", err)
	}
}

func TestResendDispatcher_Dispatch_APIErrorResponse(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusUnauthorized)
		_, _ = w.Write([]byte(`{"name":"invalid_api_key","message":"API key is invalid","statusCode":401}`))
	}))
	defer server.Close()

	dispatcher := NewResendDispatcherWithClient("invalid_key", "onboarding@resend.dev", server.URL, server.Client())

	err := dispatcher.Dispatch("user@example.com", "123456")
	if err == nil {
		t.Fatalf("expected error on 401 response, got nil")
	}

	if !strings.Contains(err.Error(), "401") || !strings.Contains(err.Error(), "invalid_api_key") {
		t.Errorf("expected error message to contain status 401 and error name, got: %v", err)
	}
}

func TestResendDispatcher_Dispatch_NetworkError(t *testing.T) {
	// Point to a closed server URL to force network error
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {}))
	server.Close()

	dispatcher := NewResendDispatcherWithClient("key", "from@resend.dev", server.URL, nil)

	err := dispatcher.Dispatch("user@example.com", "123456")
	if err == nil {
		t.Fatalf("expected network error, got nil")
	}

	if !strings.Contains(err.Error(), "HTTP request failed") && !strings.Contains(err.Error(), "connection refused") && !strings.Contains(err.Error(), "connect") {
		t.Errorf("expected network failure error message, got: %v", err)
	}
}

func TestResendDispatcher_Dispatch_InputSanitizationAndValidation(t *testing.T) {
	dispatcher := NewResendDispatcher("key", "from@example.com")

	// Empty destination
	if err := dispatcher.Dispatch("", "123456"); err == nil {
		t.Errorf("expected error for empty destination, got nil")
	}

	// Empty code
	if err := dispatcher.Dispatch("user@example.com", ""); err == nil {
		t.Errorf("expected error for empty code, got nil")
	}
}
