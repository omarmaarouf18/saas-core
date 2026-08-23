package main

import (
	"strings"
	"testing"
)

func TestSelectOTPDispatcher(t *testing.T) {
	t.Run("local environments use the stdout mock", func(t *testing.T) {
		for _, env := range []string{"local", "dev", "development"} {
			d, err := selectOTPDispatcher(env, "", "")
			if err != nil {
				t.Fatalf("env %q: unexpected error: %v", env, err)
			}
			if d.Name() != "MockSMS" {
				t.Errorf("env %q: expected MockSMS dispatcher, got %q", env, d.Name())
			}
		}
	})

	t.Run("production with Resend key uses ResendDispatcher", func(t *testing.T) {
		d, err := selectOTPDispatcher("production", "re_test_key", "otp@example.com")
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if d.Name() != "Resend" {
			t.Errorf("expected Resend dispatcher, got %q", d.Name())
		}
	})

	t.Run("production without key fails fast", func(t *testing.T) {
		d, err := selectOTPDispatcher("production", "", "")
		if err == nil {
			t.Fatal("expected fail-fast error when RESEND_API_KEY is unset in production")
		}
		if d != nil {
			t.Errorf("expected nil dispatcher on error, got %v", d.Name())
		}
		if !strings.Contains(err.Error(), "RESEND_API_KEY") {
			t.Errorf("error should mention RESEND_API_KEY, got: %v", err)
		}
	})

	t.Run("arbitrary non-local environment without key fails fast", func(t *testing.T) {
		if _, err := selectOTPDispatcher("staging", "", ""); err == nil {
			t.Fatal("expected fail-fast error for non-local env without RESEND_API_KEY")
		}
	})
}
