// Package otp defines the OTPDispatcher interface and mock implementations
// for local testing without external SMTP or Meta Graph API calls.
package otp

import (
	"fmt"
	"log"
)

// OTPDispatcher is the interface for sending OTP codes to users.
// Production implementations would dispatch via SMTP (email) or
// Meta Graph API (WhatsApp/SMS). Mocks disable all network calls.
type OTPDispatcher interface {
	// Dispatch sends the OTP code to the given destination (email/phone).
	// Returns an error if the dispatch fails.
	Dispatch(destination, code string) error

	// Name returns a human-readable label for logging (e.g., "MockSMS").
	Name() string
}

// ---------------------------------------------------------------------------
// Mock SMS Dispatcher — logs to stdout, zero network calls
// ---------------------------------------------------------------------------

// MockSMSDispatcher simulates SMS delivery by printing the OTP to stdout.
// No external network calls are made.
type MockSMSDispatcher struct{}

// Dispatch logs the OTP code to stdout, simulating SMS delivery.
func (m *MockSMSDispatcher) Dispatch(destination, code string) error {
	log.Printf("[MOCK-SMS] 📱 OTP dispatched to %s → code: %s", destination, code)
	fmt.Printf("\n╔══════════════════════════════════════════╗\n")
	fmt.Printf("║  MOCK SMS → %-28s ║\n", destination)
	fmt.Printf("║  OTP Code: %-28s  ║\n", code)
	fmt.Printf("╚══════════════════════════════════════════╝\n\n")
	return nil
}

// Name returns "MockSMS".
func (m *MockSMSDispatcher) Name() string { return "MockSMS" }

// ---------------------------------------------------------------------------
// Mock Email Dispatcher — logs to stdout, zero network calls
// ---------------------------------------------------------------------------

// MockEmailDispatcher simulates email delivery by printing the OTP to stdout.
// No external SMTP calls are made.
type MockEmailDispatcher struct{}

// Dispatch logs the OTP code to stdout, simulating email delivery.
func (e *MockEmailDispatcher) Dispatch(destination, code string) error {
	log.Printf("[MOCK-EMAIL] 📧 OTP dispatched to %s → code: %s", destination, code)
	fmt.Printf("\n╔══════════════════════════════════════════╗\n")
	fmt.Printf("║  MOCK EMAIL → %-26s ║\n", destination)
	fmt.Printf("║  OTP Code:   %-26s  ║\n", code)
	fmt.Printf("╚══════════════════════════════════════════╝\n\n")
	return nil
}

// Name returns "MockEmail".
func (e *MockEmailDispatcher) Name() string { return "MockEmail" }

// ---------------------------------------------------------------------------
// Noop Dispatcher — completely silent, for benchmarks
// ---------------------------------------------------------------------------

// NoopDispatcher does nothing. Used for automated tests and benchmarks.
type NoopDispatcher struct{}

func (n *NoopDispatcher) Dispatch(_, _ string) error { return nil }
func (n *NoopDispatcher) Name() string                { return "Noop" }
