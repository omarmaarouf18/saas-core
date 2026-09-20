package otp

import (
	"testing"
)

// NoopDispatcher does nothing. Used for automated tests and benchmarks.
type NoopDispatcher struct{}

func (n *NoopDispatcher) Dispatch(_, _ string) error { return nil }
func (n *NoopDispatcher) Name() string               { return "Noop" }

func TestNoopDispatcher(t *testing.T) {
	d := &NoopDispatcher{}
	if name := d.Name(); name != "Noop" {
		t.Errorf("Expected Name 'Noop', got %q", name)
	}

	if err := d.Dispatch("any", "111222"); err != nil {
		t.Errorf("Dispatch failed: %v", err)
	}
}
