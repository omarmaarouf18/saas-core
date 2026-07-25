package otp

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"

	"github.com/resend/resend-go/v3"
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
		if r.URL.Path != "/emails" {
			t.Errorf("expected path /emails, got %s", r.URL.Path)
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
		var req resend.SendEmailRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			t.Fatalf("failed to decode JSON request: %v", err)
		}

		if req.From != fromEmail {
			t.Errorf("expected From %q, got %q", fromEmail, req.From)
		}
		if len(req.To) != 1 || req.To[0] != targetEmail {
			t.Errorf("expected To [%q], got %v", targetEmail, req.To)
		}
		if !strings.Contains(req.Html, otpCode) {
			t.Errorf("expected HTML payload to contain code %s, got %s", otpCode, req.Html)
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

	resendClient := resend.NewCustomClient(server.Client(), apiKey)
	baseURL, err := url.Parse(server.URL + "/")
	if err != nil {
		t.Fatalf("failed to parse server URL: %v", err)
	}
	resendClient.BaseURL = baseURL

	dispatcher := NewResendDispatcherWithClient(apiKey, fromEmail, resendClient)

	if name := dispatcher.Name(); name != "Resend" {
		t.Errorf("expected Name() 'Resend', got %q", name)
	}

	err = dispatcher.Dispatch(targetEmail, otpCode)
	if err != nil {
		t.Fatalf("expected nil error on success, got: %v", err)
	}
}

func TestResendDispatcher_Dispatch_APIErrorResponse(t *testing.T) {
	apiKey := "invalid_key"
	fromEmail := "onboarding@resend.dev"

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusUnauthorized)
		_, _ = w.Write([]byte(`{"name":"invalid_api_key","message":"API key is invalid","statusCode":401}`))
	}))
	defer server.Close()

	resendClient := resend.NewCustomClient(server.Client(), apiKey)
	baseURL, err := url.Parse(server.URL + "/")
	if err != nil {
		t.Fatalf("failed to parse server URL: %v", err)
	}
	resendClient.BaseURL = baseURL

	dispatcher := NewResendDispatcherWithClient(apiKey, fromEmail, resendClient)

	err = dispatcher.Dispatch("user@example.com", "123456")
	if err == nil {
		t.Fatalf("expected error on 401 response, got nil")
	}

	if !strings.Contains(err.Error(), "resend email dispatch failed") {
		t.Errorf("expected wrapped error message, got: %v", err)
	}
}

func TestResendDispatcher_Dispatch_NetworkError(t *testing.T) {
	apiKey := "key"
	fromEmail := "from@resend.dev"

	// Point to a closed server URL to force network error
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {}))
	serverURL := server.URL
	server.Close()

	resendClient := resend.NewCustomClient(nil, apiKey)
	baseURL, err := url.Parse(serverURL + "/")
	if err != nil {
		t.Fatalf("failed to parse server URL: %v", err)
	}
	resendClient.BaseURL = baseURL

	dispatcher := NewResendDispatcherWithClient(apiKey, fromEmail, resendClient)

	err = dispatcher.Dispatch("user@example.com", "123456")
	if err == nil {
		t.Fatalf("expected network error, got nil")
	}

	if !strings.Contains(err.Error(), "resend email dispatch failed") {
		t.Errorf("expected wrapped network error message, got: %v", err)
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
