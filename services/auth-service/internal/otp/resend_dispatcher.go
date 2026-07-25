package otp

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"html"
	"io"
	"log"
	"net/http"
	"strings"
	"time"
)

const defaultResendBaseURL = "https://api.resend.com/emails"

// ResendDispatcher dispatches OTP codes via the Resend REST API (https://resend.com).
type ResendDispatcher struct {
	apiKey    string
	fromEmail string
	baseURL   string
	client    *http.Client
}

// ResendRequest represents the JSON request body sent to Resend's /emails endpoint.
type ResendRequest struct {
	From    string   `json:"from"`
	To      []string `json:"to"`
	Subject string   `json:"subject"`
	HTML    string   `json:"html"`
	Text    string   `json:"text"`
}

// ResendResponse represents a successful 200/201 response from Resend.
type ResendResponse struct {
	ID string `json:"id"`
}

// ResendErrorResponse represents an error response payload returned by Resend.
type ResendErrorResponse struct {
	Name       string `json:"name"`
	Message    string `json:"message"`
	StatusCode int    `json:"statusCode"`
}

// NewResendDispatcher creates a new ResendDispatcher with default HTTP client timeout.
func NewResendDispatcher(apiKey, fromEmail string) *ResendDispatcher {
	return &ResendDispatcher{
		apiKey:    apiKey,
		fromEmail: fromEmail,
		baseURL:   defaultResendBaseURL,
		client: &http.Client{
			Timeout: 10 * time.Second,
		},
	}
}

// NewResendDispatcherWithClient creates a ResendDispatcher with a custom HTTP client and base URL (used for testing).
func NewResendDispatcherWithClient(apiKey, fromEmail, baseURL string, client *http.Client) *ResendDispatcher {
	if client == nil {
		client = &http.Client{
			Timeout: 10 * time.Second,
		}
	}
	if baseURL == "" {
		baseURL = defaultResendBaseURL
	}
	return &ResendDispatcher{
		apiKey:    apiKey,
		fromEmail: fromEmail,
		baseURL:   baseURL,
		client:    client,
	}
}

// Name returns "Resend".
func (r *ResendDispatcher) Name() string {
	return "Resend"
}

// Dispatch sends the OTP code to destination via the Resend REST API.
func (r *ResendDispatcher) Dispatch(destination, code string) error {
	// Sanitize inputs by stripping carriage return and newline characters to prevent header/log injection (G706)
	destClean := strings.ReplaceAll(strings.ReplaceAll(destination, "\n", ""), "\r", "")
	codeClean := strings.ReplaceAll(strings.ReplaceAll(code, "\n", ""), "\r", "")
	fromClean := strings.ReplaceAll(strings.ReplaceAll(r.fromEmail, "\n", ""), "\r", "")

	if destClean == "" {
		return fmt.Errorf("resend: destination email is required")
	}
	if codeClean == "" {
		return fmt.Errorf("resend: OTP code is required")
	}

	escapedCode := html.EscapeString(codeClean)

	payload := ResendRequest{
		From:    fromClean,
		To:      []string{destClean},
		Subject: "Your Quick Delivery Verification Code",
		HTML:    fmt.Sprintf("<p>Your verification code is: <strong>%s</strong>. It expires in 5 minutes.</p>", escapedCode),
		Text:    fmt.Sprintf("Your verification code is: %s. It expires in 5 minutes.", codeClean),
	}

	bodyBytes, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("resend: failed to marshal JSON payload: %w", err)
	}

	// #nosec G704 G107 //nolint:gosec -- baseURL is hardcoded to Resend API endpoint or mock httptest server
	req, err := http.NewRequestWithContext(context.Background(), http.MethodPost, r.baseURL, bytes.NewReader(bodyBytes))
	if err != nil {
		return fmt.Errorf("resend: failed to create HTTP request: %w", err)
	}

	req.Header.Set("Authorization", "Bearer "+r.apiKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := r.client.Do(req)
	if err != nil {
		// #nosec G706 //nolint:gosec -- destClean is sanitized of carriage returns and newlines
		log.Printf("[RESEND] Network error dispatching OTP email to %s: %v", destClean, err)
		return fmt.Errorf("resend: HTTP request failed: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		// #nosec G706 //nolint:gosec -- destClean is sanitized
		log.Printf("[RESEND] Failed to read response body from %s (status %d): %v", destClean, resp.StatusCode, err)
		return fmt.Errorf("resend: failed to read response body (status %d): %w", resp.StatusCode, err)
	}

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		var errResp ResendErrorResponse
		if jsonErr := json.Unmarshal(respBody, &errResp); jsonErr == nil && errResp.Message != "" {
			// #nosec G706 //nolint:gosec -- sanitized log inputs
			log.Printf("[RESEND] Failed to send OTP email to %s: status=%d, name=%s, msg=%s", destClean, resp.StatusCode, errResp.Name, errResp.Message)
			return fmt.Errorf("resend API error (status %d): %s - %s", resp.StatusCode, errResp.Name, errResp.Message)
		}
		cleanBody := strings.ReplaceAll(strings.ReplaceAll(string(respBody), "\n", " "), "\r", " ")
		// #nosec G706 //nolint:gosec -- sanitized log inputs
		log.Printf("[RESEND] Failed to send OTP email to %s: status=%d, body=%s", destClean, resp.StatusCode, cleanBody)
		return fmt.Errorf("resend API error (status %d): %s", resp.StatusCode, cleanBody)
	}

	var resendResp ResendResponse
	_ = json.Unmarshal(respBody, &resendResp)

	// Note: Plaintext OTP code is NOT logged in non-local mode to preserve secrecy.
	// #nosec G706 //nolint:gosec -- destClean and resendResp.ID are sanitized
	log.Printf("[RESEND] OTP email successfully dispatched to %s (id=%s)", destClean, resendResp.ID)
	return nil
}
