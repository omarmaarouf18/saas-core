package hub

import (
	"context"
	"strings"
	"sync"
	"testing"
	"time"
)

// BE-GAPS-FIX item 1: every notification about one job carries
// event_type == type on the SSE wire and in the FCM data; others carry none.
func TestSSEHub_JobNotificationCarriesEventType(t *testing.T) {
	h := NewSSEHub()
	client := &SSEClient{ID: "c1", UserID: "cust-1", TenantID: "tenant-A", Role: RoleClient, Send: make(chan []byte, 5)}
	h.Register(client)

	var mu sync.Mutex
	var pushed []map[string]string
	h.SetPushDispatcher(&mockFCMDispatcher{
		enabled: true,
		sendPushFunc: func(ctx context.Context, token, title, body string, data map[string]string) (bool, error) {
			mu.Lock()
			defer mu.Unlock()
			pushed = append(pushed, data)
			return false, nil
		},
	}, &mockDeviceTokenFetcher{
		tokensFunc: func(ctx context.Context, userID string) ([]string, error) {
			return []string{"token-1"}, nil
		},
	})

	h.Broadcast(Notification{
		ID: "n-job", Type: "job_picked_up", TenantID: "tenant-A", UserID: "cust-1",
		JobID: "job-42", Title: "Picked up", Body: "On the way", Timestamp: time.Now(),
	})
	h.Broadcast(Notification{
		ID: "n-ticket", Type: "ticket_resolved", TenantID: "tenant-A", UserID: "cust-1",
		Title: "Resolved", Body: "Done", Timestamp: time.Now(),
	})

	msg1 := string(<-client.Send)
	msg2 := string(<-client.Send)
	if !strings.Contains(msg1, `"event_type":"job_picked_up"`) || !strings.Contains(msg1, `"job_id":"job-42"`) {
		t.Errorf("job notification SSE frame lacks event_type/job_id: %s", msg1)
	}
	if strings.Contains(msg2, "event_type") {
		t.Errorf("non-job notification must not carry event_type: %s", msg2)
	}

	deadline := time.Now().Add(2 * time.Second)
	for {
		mu.Lock()
		n := len(pushed)
		mu.Unlock()
		if n == 2 || time.Now().After(deadline) {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	mu.Lock()
	defer mu.Unlock()
	if len(pushed) != 2 {
		t.Fatalf("expected 2 pushes, got %d", len(pushed))
	}
	var jobData, otherData map[string]string
	for _, d := range pushed {
		if d["id"] == "n-job" {
			jobData = d
		} else {
			otherData = d
		}
	}
	if jobData["event_type"] != "job_picked_up" || jobData["job_id"] != "job-42" || jobData["type"] != "job_picked_up" {
		t.Errorf("FCM data for job notification = %v", jobData)
	}
	if _, ok := otherData["event_type"]; ok {
		t.Errorf("FCM data for non-job notification carries event_type: %v", otherData)
	}
}
