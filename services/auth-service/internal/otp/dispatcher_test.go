package otp

import (
	"testing"
)

func TestMockSMSDispatcher(t *testing.T) {
	d := &MockSMSDispatcher{}
	if name := d.Name(); name != "MockSMS" {
		t.Errorf("Expected Name 'MockSMS', got %q", name)
	}

	if err := d.Dispatch("+1234567890", "123456"); err != nil {
		t.Errorf("Dispatch failed: %v", err)
	}
}

func TestMockEmailDispatcher(t *testing.T) {
	d := &MockEmailDispatcher{}
	if name := d.Name(); name != "MockEmail" {
		t.Errorf("Expected Name 'MockEmail', got %q", name)
	}

	if err := d.Dispatch("user@example.com", "654321"); err != nil {
		t.Errorf("Dispatch failed: %v", err)
	}
}

func TestNoopDispatcher(t *testing.T) {
	d := &NoopDispatcher{}
	if name := d.Name(); name != "Noop" {
		t.Errorf("Expected Name 'Noop', got %q", name)
	}

	if err := d.Dispatch("any", "111222"); err != nil {
		t.Errorf("Dispatch failed: %v", err)
	}
}
