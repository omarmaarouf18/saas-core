package otp

import (
	"context"
	"fmt"
	"html"
	"log"
	"strings"
	"time"

	"github.com/resend/resend-go/v3"
)

// ResendDispatcher dispatches OTP codes via the official Resend Go SDK (github.com/resend/resend-go/v3).
type ResendDispatcher struct {
	apiKey    string
	fromEmail string
	client    *resend.Client
}

// NewResendDispatcher initializes a ResendDispatcher with a default Resend client.
func NewResendDispatcher(apiKey, fromEmail string) *ResendDispatcher {
	return &ResendDispatcher{
		apiKey:    apiKey,
		fromEmail: fromEmail,
		client:    resend.NewClient(apiKey),
	}
}

// NewResendDispatcherWithClient initializes a ResendDispatcher with a custom Resend client (used for testing).
func NewResendDispatcherWithClient(apiKey, fromEmail string, client *resend.Client) *ResendDispatcher {
	if client == nil {
		client = resend.NewClient(apiKey)
	}
	return &ResendDispatcher{
		apiKey:    apiKey,
		fromEmail: fromEmail,
		client:    client,
	}
}

// Name returns "Resend".
func (r *ResendDispatcher) Name() string {
	return "Resend"
}

// Dispatch sends the OTP code to the given destination via the Resend Go SDK.
func (r *ResendDispatcher) Dispatch(destination, code string) error {
	// Sanitize inputs by stripping carriage return and newline characters to prevent header and log injection (G706)
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

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	params := &resend.SendEmailRequest{
		From:    fromClean,
		To:      []string{destClean},
		Subject: "Your Quick Delivery Verification Code",
		Html:    fmt.Sprintf("<p>Your verification code is: <strong>%s</strong>. It expires in 5 minutes.</p>", escapedCode),
		Text:    fmt.Sprintf("Your verification code is: %s. It expires in 5 minutes.", codeClean),
	}

	sent, err := r.client.Emails.SendWithContext(ctx, params)
	if err != nil {
		// #nosec G706 //nolint:gosec -- destClean is sanitized of carriage returns and newlines
		log.Printf("[RESEND] Error dispatching OTP email to %s: %v", destClean, err)
		return fmt.Errorf("resend email dispatch failed: %w", err)
	}

	// Note: Plaintext OTP code is NOT logged in non-local mode to preserve secrecy.
	// #nosec G706 //nolint:gosec -- destClean and sent.Id are sanitized
	log.Printf("[RESEND] OTP email successfully dispatched to %s (id=%s)", destClean, sent.Id)
	return nil
}
