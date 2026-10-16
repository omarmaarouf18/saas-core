package handlerutil

import (
	"bytes"
	"context"
	"encoding/json"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatchlogs"
)

func TestShipSecurityEvent_EmitsJSONToStdoutWhenCloudWatchDisabled(t *testing.T) {
	origOutput := securityOutput
	buf := &bytes.Buffer{}
	securityOutput = buf
	defer func() { securityOutput = origOutput }()

	CwEnabled = false
	CwClient = nil
	CwLogGroup = ""

	ShipSecurityEvent(context.Background(), "TEST_OBS_EVENT", "test-service", "actor-1", "tenant-1", "detail-1", "127.0.0.1")

	line := strings.TrimSpace(buf.String())
	var decoded map[string]any
	if err := json.Unmarshal([]byte(line), &decoded); err != nil {
		t.Fatalf("expected valid JSON line on stdout, got %q: %v", line, err)
	}
	if decoded["msg"] != "security_event" {
		t.Errorf("expected msg=security_event, got %v", decoded["msg"])
	}
	if decoded["event_type"] != "TEST_OBS_EVENT" || decoded["service"] != "test-service" || decoded["actor_id"] != "actor-1" {
		t.Errorf("event fields not emitted correctly: %v", decoded)
	}
}

func TestShipSecurityEvent_EmitsJSONToStdoutWhenCloudWatchEnabled(t *testing.T) {
	origOutput := securityOutput
	origEnabled := CwEnabled
	origClient := CwClient
	buf := &bytes.Buffer{}
	securityOutput = buf
	defer func() {
		securityOutput = origOutput
		CwEnabled = origEnabled
		CwClient = origClient
	}()

	CwLogGroup = "test-group"
	CwEnabled = true
	CwClient = cloudwatchlogs.NewFromConfig(aws.Config{})

	ShipSecurityEvent(context.Background(), "TEST_OBS_ENABLED", "test-service", "", "", "", "")

	if !strings.Contains(buf.String(), `"event_type":"TEST_OBS_ENABLED"`) {
		t.Errorf("expected stdout emission with CloudWatch enabled, got %q", buf.String())
	}
}

func TestEnqueueSecurityEvent_DropsWhenQueueFull(t *testing.T) {
	origQueue := securityEventQueue
	origDropped := atomic.SwapInt64(&securityEventsDropped, 0)
	securityEventQueue = make(chan pendingSecurityEvent, 1)
	defer func() {
		securityEventQueue = origQueue
		atomic.StoreInt64(&securityEventsDropped, origDropped)
	}()

	enqueueSecurityEvent(pendingSecurityEvent{event: SecurityEvent{EventType: "FIRST"}})
	if got := atomic.LoadInt64(&securityEventsDropped); got != 0 {
		t.Fatalf("expected 0 drops after first enqueue, got %d", got)
	}

	enqueueSecurityEvent(pendingSecurityEvent{event: SecurityEvent{EventType: "SECOND"}})
	if got := atomic.LoadInt64(&securityEventsDropped); got != 1 {
		t.Fatalf("expected 1 drop after overflowing queue, got %d", got)
	}
	if len(securityEventQueue) != 1 {
		t.Fatalf("expected queue to still hold exactly 1 event, got %d", len(securityEventQueue))
	}
}

func TestShipSecurityEventNonBlocking(t *testing.T) {
	// Setup invalid configuration to guarantee SDK calls fail
	CwLogGroup = "test-group"
	CwEnabled = true
	CwClient = cloudwatchlogs.NewFromConfig(aws.Config{})

	ctx, cancel := context.WithTimeout(context.Background(), 1*time.Second)
	defer cancel()

	start := time.Now()
	// Call ShipSecurityEvent which runs in a goroutine
	ShipSecurityEvent(ctx, "TEST_EVENT", "test-service", "actor", "tenant", "detail", "127.0.0.1")
	duration := time.Since(start)

	// Verify that it runs asynchronously and does not block
	if duration > 100*time.Millisecond {
		t.Errorf("ShipSecurityEvent blocked for %v, expected instant return", duration)
	}
}

func TestShipSecurityEvent_AgnosticFailureModes(t *testing.T) {
	// Backup original globals
	origCwClient := CwClient
	origCwLogGroup := CwLogGroup
	origCwEnabled := CwEnabled
	defer func() {
		CwClient = origCwClient
		CwLogGroup = origCwLogGroup
		CwEnabled = origCwEnabled
	}()

	t.Run("DisabledCloudWatchDoesNotBlockOrPanic", func(t *testing.T) {
		CwEnabled = false
		CwClient = nil
		CwLogGroup = ""

		ctx, cancel := context.WithTimeout(context.Background(), 1*time.Second)
		defer cancel()

		start := time.Now()
		// Should return immediately, not block, and not panic
		ShipSecurityEvent(ctx, "TEST_EVENT", "test-service", "actor", "tenant", "detail", "127.0.0.1")
		duration := time.Since(start)

		if duration > 100*time.Millisecond {
			t.Errorf("ShipSecurityEvent blocked for %v when disabled", duration)
		}
	})

	t.Run("NilClientWithEnabledDoesNotBlockOrPanic", func(t *testing.T) {
		CwEnabled = true
		CwClient = nil
		CwLogGroup = "test-group"

		ctx, cancel := context.WithTimeout(context.Background(), 1*time.Second)
		defer cancel()

		start := time.Now()
		// Should return immediately, not block, and not panic
		ShipSecurityEvent(ctx, "TEST_EVENT", "test-service", "actor", "tenant", "detail", "127.0.0.1")
		duration := time.Since(start)

		if duration > 100*time.Millisecond {
			t.Errorf("ShipSecurityEvent blocked for %v with nil client", duration)
		}
	})

	t.Run("UnreachableLogSinkDoesNotBlockOrPanic", func(t *testing.T) {
		CwLogGroup = "test-group"
		CwEnabled = true
		// Invalid client configurations to guarantee failures and timeouts
		CwClient = cloudwatchlogs.NewFromConfig(aws.Config{})

		ctx, cancel := context.WithTimeout(context.Background(), 1*time.Second)
		defer cancel()

		start := time.Now()
		// Runs in a goroutine, should not block the caller even if log sink fails
		ShipSecurityEvent(ctx, "TEST_EVENT", "test-service", "actor", "tenant", "detail", "127.0.0.1")
		duration := time.Since(start)

		if duration > 100*time.Millisecond {
			t.Errorf("ShipSecurityEvent blocked for %v when log sink is unreachable", duration)
		}

		// Wait slightly to let the goroutine execute and ensure it doesn't panic
		time.Sleep(50 * time.Millisecond)
	})
}

func TestGetClientIP(t *testing.T) {
	// 1. Nil request -> returns ""
	if ip := GetClientIP(nil); ip != "" {
		t.Errorf("Expected empty string for nil request, got %q", ip)
	}
}
