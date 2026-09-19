package otp

import (
	"testing"
)

func TestNoopDispatcher(t *testing.T) {
	d := &NoopDispatcher{}
	if name := d.Name(); name != "Noop" {
		t.Errorf("Expected Name 'Noop', got %q", name)
	}

	if err := d.Dispatch("any", "111222"); err != nil {
		t.Errorf("Dispatch failed: %v", err)
	}
}
