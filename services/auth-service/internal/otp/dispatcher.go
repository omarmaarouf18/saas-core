// Package otp defines the OTPDispatcher interface and mock implementations
// for local testing without external SMTP or Meta Graph API calls.
package otp

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
