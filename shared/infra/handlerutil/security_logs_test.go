package handlerutil

import (
	"context"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatchlogs"
)

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
