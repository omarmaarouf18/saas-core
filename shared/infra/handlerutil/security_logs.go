package handlerutil

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log"
	"log/slog"
	"net/http"
	"os"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatchlogs"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatchlogs/types"
)

var (
	CwClient   *cloudwatchlogs.Client
	CwInitOnce sync.Once
	CwLogGroup string
	CwEnabled  bool
)

// securityQueueCapacity bounds the pending CloudWatch shipping backlog.
// Events beyond this are dropped (and counted) rather than blocking the caller.
const securityQueueCapacity = 1000

var (
	securityEventQueue    chan pendingSecurityEvent
	securityWorkerOnce    sync.Once
	securityEventsDropped int64
	// securityOutput is the destination for the always-on structured stdout
	// emission. It is a variable only so tests can capture the output.
	securityOutput io.Writer = os.Stdout
)

// pendingSecurityEvent captures the event plus the shipping destination at
// enqueue time, so the worker never reads the mutable Cw* globals.
type pendingSecurityEvent struct {
	event    SecurityEvent
	client   *cloudwatchlogs.Client
	logGroup string
}

// InitCloudWatch initializes the CloudWatch Logs client with the provided log group.
// It logs a warning if logGroup is not configured.
func InitCloudWatch(logGroup string) {
	CwInitOnce.Do(func() {
		CwLogGroup = logGroup
		if CwLogGroup == "" {
			log.Println("security event shipping disabled — CloudWatch log group not set")
			return
		}

		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()

		cfg, err := config.LoadDefaultConfig(ctx)
		if err != nil {
			log.Printf("[SECURITY-SHIP-FAILED] failed to load AWS SDK config: %v", err)
			return
		}

		CwClient = cloudwatchlogs.NewFromConfig(cfg)
		CwEnabled = true
		log.Printf("security event shipping enabled: group=%s", CwLogGroup)
	})
}

type SecurityEvent struct {
	Timestamp string `json:"timestamp"`
	EventType string `json:"event_type"`
	Service   string `json:"service"`
	ActorID   string `json:"actor_id,omitempty"`
	TenantID  string `json:"tenant_id,omitempty"`
	Detail    string `json:"detail,omitempty"`
	ClientIP  string `json:"client_ip,omitempty"`
}

// ShipSecurityEvent always emits the event as a structured JSON line on
// stdout (via slog) so security events are observable even when CloudWatch
// shipping is disabled. When CloudWatch is enabled, the event is also
// enqueued to the single shipping worker; the queue is bounded and events
// are dropped (not blocked on) if it fills up.
func ShipSecurityEvent(ctx context.Context, eventType, service, actorID, tenantID, detail, clientIP string) {
	InitCloudWatch("")

	event := SecurityEvent{
		Timestamp: time.Now().UTC().Format(time.RFC3339),
		EventType: eventType,
		Service:   service,
		ActorID:   actorID,
		TenantID:  tenantID,
		Detail:    detail,
		ClientIP:  clientIP,
	}

	emitSecurityEventStdout(event)

	if !CwEnabled || CwClient == nil {
		return
	}
	startSecurityWorker()
	enqueueSecurityEvent(pendingSecurityEvent{
		event:    event,
		client:   CwClient,
		logGroup: CwLogGroup,
	})
}

// emitSecurityEventStdout writes the event as a JSON line to securityOutput.
func emitSecurityEventStdout(event SecurityEvent) {
	logger := slog.New(slog.NewJSONHandler(securityOutput, nil))
	logger.LogAttrs(context.Background(), slog.LevelInfo, "security_event",
		slog.String("timestamp", event.Timestamp),
		slog.String("event_type", event.EventType),
		slog.String("service", event.Service),
		slog.String("actor_id", event.ActorID),
		slog.String("tenant_id", event.TenantID),
		slog.String("detail", event.Detail),
		slog.String("client_ip", event.ClientIP),
	)
}

// startSecurityWorker lazily starts the single goroutine that drains the
// bounded queue and ships events to CloudWatch, preserving FIFO order.
func startSecurityWorker() {
	securityWorkerOnce.Do(func() {
		if securityEventQueue == nil {
			securityEventQueue = make(chan pendingSecurityEvent, securityQueueCapacity)
		}
		queue := securityEventQueue
		go func() {
			for pending := range queue {
				shipSecurityEventToCloudWatch(pending)
			}
		}()
	})
}

// enqueueSecurityEvent never blocks: if the bounded queue is full the event
// is dropped and counted.
func enqueueSecurityEvent(pending pendingSecurityEvent) {
	select {
	case securityEventQueue <- pending:
	default:
		n := atomic.AddInt64(&securityEventsDropped, 1)
		if n == 1 || n%100 == 0 {
			log.Printf("[SECURITY-SHIP-DROPPED] security event queue full, %d event(s) dropped so far", n)
		}
	}
}

// shipSecurityEventToCloudWatch performs the actual PutLogEvents call, with a
// bounded timeout that outlives the request context to prevent evasion.
func shipSecurityEventToCloudWatch(pending pendingSecurityEvent) {
	client := pending.client
	logGroup := pending.logGroup
	if client == nil {
		return
	}

	shipCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	payload, err := json.Marshal(pending.event)
	if err != nil {
		log.Printf("[SECURITY-SHIP-FAILED] failed to marshal security event: %v", err)
		return
	}

	logStream := pending.event.Service

	input := &cloudwatchlogs.PutLogEventsInput{
		LogGroupName:  aws.String(logGroup),
		LogStreamName: aws.String(logStream),
		LogEvents: []types.InputLogEvent{
			{
				Message:   aws.String(string(payload)),
				Timestamp: aws.Int64(time.Now().UnixNano() / int64(time.Millisecond)),
			},
		},
	}

	_, err = client.PutLogEvents(shipCtx, input)
	if err != nil {
		var nf *types.ResourceNotFoundException
		if errors.As(err, &nf) {
			_, errCreate := client.CreateLogStream(shipCtx, &cloudwatchlogs.CreateLogStreamInput{
				LogGroupName:  aws.String(logGroup),
				LogStreamName: aws.String(logStream),
			})
			var alreadyExists *types.ResourceAlreadyExistsException
			if errCreate == nil || errors.As(errCreate, &alreadyExists) {
				_, err = client.PutLogEvents(shipCtx, input)
			} else {
				log.Printf("[SECURITY-SHIP-FAILED] failed to create log stream %s: %v", logStream, errCreate)
				return
			}
		}
	}

	if err != nil {
		log.Printf("[SECURITY-SHIP-FAILED] failed to ship to CloudWatch: %v", err)
	}
}

// GetClientIP extracts client IP address from request.
func GetClientIP(r *http.Request) string {
	if r == nil {
		return ""
	}
	var ip string
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		parts := strings.Split(xff, ",")
		ip = strings.TrimSpace(parts[0])
	} else if rip := r.Header.Get("X-Real-IP"); rip != "" {
		ip = rip
	} else {
		ip = r.RemoteAddr
	}

	if strings.Contains(ip, "]") {
		if idx := strings.LastIndex(ip, ":"); idx != -1 {
			ip = ip[:idx]
		}
		ip = strings.Trim(ip, "[]")
	} else {
		if count := strings.Count(ip, ":"); count == 1 {
			if idx := strings.LastIndex(ip, ":"); idx != -1 {
				ip = ip[:idx]
			}
		}
	}
	return ip
}
