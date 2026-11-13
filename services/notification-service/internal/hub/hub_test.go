package hub

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"
)

func TestSSEHub_RegisterUnregisterAndCounts(t *testing.T) {
	h := NewSSEHub()
	if h.ClientCount() != 0 {
		t.Errorf("Expected client count 0, got %d", h.ClientCount())
	}

	client1 := &SSEClient{
		ID:       "client-1",
		TenantID: "tenant-A",
		Role:     RoleOwner,
		Send:     make(chan []byte, 10),
	}
	client2 := &SSEClient{
		ID:       "client-2",
		TenantID: "tenant-A",
		Role:     RoleEmployee,
		Send:     make(chan []byte, 10),
	}

	h.Register(client1)
	h.Register(client2)

	if h.ClientCount() != 2 {
		t.Errorf("Expected client count 2, got %d", h.ClientCount())
	}

	roleCounts := h.ClientsByRole()
	if roleCounts[RoleOwner] != 1 || roleCounts[RoleEmployee] != 1 {
		t.Errorf("Expected 1 owner and 1 employee, got %v", roleCounts)
	}

	h.Unregister(client1)
	if h.ClientCount() != 1 {
		t.Errorf("Expected client count 1 after unregister, got %d", h.ClientCount())
	}

	// Double unregister should be no-op safely
	h.Unregister(client1)
}

func TestSSEHub_BroadcastScopingAndFiltering(t *testing.T) {
	h := NewSSEHub()

	cOwnerA := &SSEClient{ID: "c1", TenantID: "tenant-A", Role: RoleOwner, Send: make(chan []byte, 5)}
	cEmpA := &SSEClient{ID: "c2", TenantID: "tenant-A", Role: RoleEmployee, Send: make(chan []byte, 5)}
	cOwnerB := &SSEClient{ID: "c3", TenantID: "tenant-B", Role: RoleOwner, Send: make(chan []byte, 5)}

	h.Register(cOwnerA)
	h.Register(cEmpA)
	h.Register(cOwnerB)

	// 1. Broadcast to Tenant A, RoleOwner only
	h.Broadcast(Notification{
		Type:      "job_alert",
		TenantID:  "tenant-A",
		Title:     "New Job",
		Body:      "Job payload",
		Roles:     []Role{RoleOwner},
		Timestamp: time.Now(),
	})

	select {
	case msg := <-cOwnerA.Send:
		if len(msg) == 0 {
			t.Errorf("Expected message for cOwnerA")
		}
	default:
		t.Errorf("cOwnerA should have received notification")
	}

	select {
	case <-cEmpA.Send:
		t.Errorf("cEmpA should NOT have received notification (role mismatch)")
	default:
	}

	select {
	case <-cOwnerB.Send:
		t.Errorf("cOwnerB should NOT have received notification (tenant mismatch)")
	default:
	}

	// 3. Test non-global notification with empty/different tenant ID does NOT reach tenant B
	h.Broadcast(Notification{
		Type:     "popup",
		TenantID: "tenant-A",
		Title:    "Private Tenant A Notification",
		Global:   false,
	})

	select {
	case <-cOwnerB.Send:
		t.Errorf("cOwnerB (tenant-B) should NOT receive non-global notification addressed to tenant-A")
	default:
	}

	// 4. Test explicit global broadcast reaches all tenants
	h.BroadcastGlobal(Notification{
		Type:  "system",
		Title: "Platform-wide System Maintenance",
	})

	select {
	case msg := <-cOwnerB.Send:
		if len(msg) == 0 {
			t.Errorf("Expected global notification payload for cOwnerB")
		}
	default:
		t.Errorf("cOwnerB should have received explicit global notification")
	}
}

func TestSSEHub_MultiInstanceRedisPubSubDelivery(t *testing.T) {
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("Failed to start miniredis: %v", err)
	}
	defer mr.Close()

	rdb1 := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb1.Close()

	rdb2 := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb2.Close()

	hub1 := NewSSEHub()
	hub1.SetRedisClient(rdb1)
	defer hub1.Close()

	hub2 := NewSSEHub()
	hub2.SetRedisClient(rdb2)
	defer hub2.Close()

	// Wait for Redis Pub/Sub subscription setup
	time.Sleep(100 * time.Millisecond)

	c1OnHub1 := &SSEClient{ID: "c1", TenantID: "tenant-A", Role: RoleOwner, Send: make(chan []byte, 5)}
	c2OnHub2 := &SSEClient{ID: "c2", TenantID: "tenant-A", Role: RoleEmployee, Send: make(chan []byte, 5)}
	c3OnHub2 := &SSEClient{ID: "c3", TenantID: "tenant-B", Role: RoleOwner, Send: make(chan []byte, 5)}

	hub1.Register(c1OnHub1)
	hub2.Register(c2OnHub2)
	hub2.Register(c3OnHub2)

	// 1. Broadcast on Hub 1 to tenant-A -> should be delivered via Redis Pub/Sub to c2OnHub2 on Hub 2
	hub1.Broadcast(Notification{
		Type:      "job_alert",
		TenantID:  "tenant-A",
		Title:     "Cross-Instance Job Alert",
		Body:      "Dispatched on Replica 1",
		Timestamp: time.Now(),
	})

	// Allow time for Pub/Sub propagation
	time.Sleep(100 * time.Millisecond)

	select {
	case msg := <-c1OnHub1.Send:
		if len(msg) == 0 {
			t.Errorf("c1OnHub1 should have received notification locally on Hub 1")
		}
	default:
		t.Errorf("c1OnHub1 on Hub 1 missed local notification")
	}

	select {
	case msg := <-c2OnHub2.Send:
		if len(msg) == 0 {
			t.Errorf("c2OnHub2 should have received cross-instance notification via Redis Pub/Sub on Hub 2")
		}
	default:
		t.Errorf("c2OnHub2 on Hub 2 missed cross-instance notification sent by Hub 1")
	}

	select {
	case <-c3OnHub2.Send:
		t.Errorf("c3OnHub2 (tenant-B) should NOT have received notification for tenant-A")
	default:
	}

	// 2. Broadcast Global on Hub 1 -> should reach c3OnHub2 on Hub 2
	hub1.BroadcastGlobal(Notification{
		Type:      "system",
		Title:     "Global System Update",
		Timestamp: time.Now(),
	})

	time.Sleep(100 * time.Millisecond)

	select {
	case msg := <-c3OnHub2.Send:
		if len(msg) == 0 {
			t.Errorf("c3OnHub2 should have received cross-instance global notification")
		}
	default:
		t.Errorf("c3OnHub2 on Hub 2 missed cross-instance global notification")
	}
}

type mockFCMDispatcher struct {
	sendPushFunc func(ctx context.Context, token, title, body string, data map[string]string) (bool, error)
	enabled      bool
}

func (m *mockFCMDispatcher) SendPush(ctx context.Context, token, title, body string, data map[string]string) (bool, error) {
	if m.sendPushFunc != nil {
		return m.sendPushFunc(ctx, token, title, body, data)
	}
	return false, nil
}

func (m *mockFCMDispatcher) IsEnabled() bool {
	return m.enabled
}

type mockDeviceTokenFetcher struct {
	tokensFunc           func(ctx context.Context, userID string) ([]string, error)
	unregisterCalledWith []string
	unregisterFunc       func(ctx context.Context, userID, token string) error
}

func (m *mockDeviceTokenFetcher) GetUserDeviceTokens(ctx context.Context, userID string) ([]string, error) {
	if m.tokensFunc != nil {
		return m.tokensFunc(ctx, userID)
	}
	return nil, nil
}

func (m *mockDeviceTokenFetcher) UnregisterStaleToken(ctx context.Context, userID, token string) error {
	m.unregisterCalledWith = append(m.unregisterCalledWith, userID+":"+token)
	if m.unregisterFunc != nil {
		return m.unregisterFunc(ctx, userID, token)
	}
	return nil
}

func TestSSEHub_FCMPushParallelDeliveryAndStaleTokenCleanup(t *testing.T) {
	h := NewSSEHub()

	client1 := &SSEClient{ID: "c1", UserID: "user-1", TenantID: "tenant-A", Role: RoleOwner, Send: make(chan []byte, 5)}
	h.Register(client1)

	var pushedTokens []string
	fcmDisp := &mockFCMDispatcher{
		enabled: true,
		sendPushFunc: func(ctx context.Context, token, title, body string, data map[string]string) (bool, error) {
			pushedTokens = append(pushedTokens, token)
			if token == "stale-token-99" {
				return true, fmt.Errorf("token expired")
			}
			return false, nil
		},
	}

	fetcher := &mockDeviceTokenFetcher{
		tokensFunc: func(ctx context.Context, userID string) ([]string, error) {
			if userID == "user-1" {
				return []string{"valid-token-1", "stale-token-99"}, nil
			}
			return nil, nil
		},
	}

	h.SetPushDispatcher(fcmDisp, fetcher)

	// Broadcast notification targeting user-1
	h.Broadcast(Notification{
		ID:        "notif-test-fcm",
		Type:      "job_alert",
		TenantID:  "tenant-A",
		UserID:    "user-1",
		Title:     "New Job",
		Body:      "Details...",
		Timestamp: time.Now(),
	})

	// 1. Confirm SSE delivery succeeded immediately
	select {
	case msg := <-client1.Send:
		if len(msg) == 0 {
			t.Errorf("Expected SSE message for client1")
		}
	default:
		t.Errorf("client1 missed SSE notification")
	}

	// Wait for async FCM push dispatch goroutine
	time.Sleep(100 * time.Millisecond)

	if len(pushedTokens) != 2 {
		t.Fatalf("Expected 2 tokens pushed, got %d", len(pushedTokens))
	}

	// Verify stale token cleanup call
	if len(fetcher.unregisterCalledWith) != 1 || fetcher.unregisterCalledWith[0] != "user-1:stale-token-99" {
		t.Errorf("Expected stale token 'user-1:stale-token-99' to be unregistered, got %v", fetcher.unregisterCalledWith)
	}
}

func TestSSEHub_FCMFailureDoesNotFailSSEBroadcast(t *testing.T) {
	h := NewSSEHub()
	client1 := &SSEClient{ID: "c1", UserID: "user-1", TenantID: "tenant-A", Role: RoleOwner, Send: make(chan []byte, 5)}
	h.Register(client1)

	// Broken FCM dispatcher that returns errors or panics
	fcmDisp := &mockFCMDispatcher{
		enabled: true,
		sendPushFunc: func(ctx context.Context, token, title, body string, data map[string]string) (bool, error) {
			return false, fmt.Errorf("FCM server 500 internal server error")
		},
	}
	fetcher := &mockDeviceTokenFetcher{
		tokensFunc: func(ctx context.Context, userID string) ([]string, error) {
			return []string{"token-1"}, nil
		},
	}

	h.SetPushDispatcher(fcmDisp, fetcher)

	h.Broadcast(Notification{
		ID:       "notif-err-test",
		TenantID: "tenant-A",
		UserID:   "user-1",
		Title:    "Title",
		Body:     "Body",
	})

	// SSE broadcast must still succeed cleanly
	select {
	case msg := <-client1.Send:
		if len(msg) == 0 {
			t.Errorf("Expected SSE message despite FCM failure")
		}
	default:
		t.Errorf("SSE broadcast failed due to FCM error")
	}
}

func TestSSEHub_AccountSuspended_ForceClosesConnection_F03(t *testing.T) {
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	defer mr.Close()

	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	h := NewSSEHub()
	defer h.Close()

	h.SetRedisClient(rdb)

	client := &SSEClient{
		ID:       "token-123",
		UserID:   "suspended-user-456",
		TenantID: "tenant-A",
		Role:     RoleOwner,
		Send:     make(chan []byte, 10),
	}

	h.Register(client)

	if h.ClientCount() != 1 {
		t.Fatalf("expected 1 client registered, got %d", h.ClientCount())
	}

	// Publish ACCOUNT_SUSPENDED event via Redis
	pubPayload := `{"action":"ACCOUNT_SUSPENDED","user_id":"suspended-user-456"}`
	if err := rdb.Publish(context.Background(), "account:events", pubPayload).Err(); err != nil {
		t.Fatalf("failed to publish suspension event: %v", err)
	}

	// Verify client Send channel is closed
	select {
	case _, ok := <-client.Send:
		if ok {
			t.Errorf("expected client.Send channel to be closed on suspension, but received value")
		}
	case <-time.After(2 * time.Second):
		t.Fatalf("timed out waiting for client.Send channel to be closed after ACCOUNT_SUSPENDED event")
	}

	// Verify client count dropped to 0
	if h.ClientCount() != 0 {
		t.Errorf("expected 0 clients in hub after suspension disconnect, got %d", h.ClientCount())
	}
}

func TestNotification_ToClientStripsRouting(t *testing.T) {
	n := Notification{
		ID:       "n1",
		Type:     "popup",
		TenantID: "t1",
		UserID:   "u1",
		UserIDs:  []string{"u1", "u2"},
		Global:   true,
		Title:    "Hi",
		Body:     "Body",
		Roles:    []Role{RoleOwner},
	}
	raw, err := json.Marshal(n.ToClient())
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	for _, key := range []string{`"user_ids"`, `"roles"`, `"global"`, "u2"} {
		if strings.Contains(string(raw), key) {
			t.Errorf("client payload leaks %q: %s", key, raw)
		}
	}
	var decoded map[string]any
	if err := json.Unmarshal(raw, &decoded); err != nil {
		t.Fatalf("decode: %v", err)
	}
	for _, key := range []string{"id", "type", "tenant_id", "user_id", "title", "body", "timestamp"} {
		if _, ok := decoded[key]; !ok {
			t.Errorf("client payload missing %q", key)
		}
	}
}

func TestSSEHub_RecipientFirstScoping(t *testing.T) {
	h := NewSSEHub()

	// Registered clients:
	// - cCust1: customer in tenant-customer, role: client
	// - cCust2: another customer in tenant-other-cust, role: client
	// - cOwnerUser: owner in tenant-owner, role: owner
	// - cOwnerWorker: another user in tenant-owner, role: client
	// - cEmployeeOther: employee in tenant-other, role: employee
	// - cEmployeeOwner: employee in tenant-owner, role: employee
	cCust1 := &SSEClient{ID: "c-cust-1", UserID: "cust-1", TenantID: "tenant-customer", Role: RoleClient, Send: make(chan []byte, 10)}
	cCust2 := &SSEClient{ID: "c-cust-2", UserID: "cust-2", TenantID: "tenant-other-cust", Role: RoleClient, Send: make(chan []byte, 10)}
	cOwnerUser := &SSEClient{ID: "c-owner", UserID: "owner-1", TenantID: "tenant-owner", Role: RoleOwner, Send: make(chan []byte, 10)}
	cOwnerWorker := &SSEClient{ID: "c-worker", UserID: "worker-1", TenantID: "tenant-owner", Role: RoleClient, Send: make(chan []byte, 10)}
	cEmployeeOther := &SSEClient{ID: "c-emp-other", UserID: "emp-2", TenantID: "tenant-other", Role: RoleEmployee, Send: make(chan []byte, 10)}
	cEmployeeOwner := &SSEClient{ID: "c-emp-owner", UserID: "emp-1", TenantID: "tenant-owner", Role: RoleEmployee, Send: make(chan []byte, 10)}

	h.Register(cCust1)
	h.Register(cCust2)
	h.Register(cOwnerUser)
	h.Register(cOwnerWorker)
	h.Register(cEmployeeOther)
	h.Register(cEmployeeOwner)

	drain := func(c *SSEClient) {
		for {
			select {
			case <-c.Send:
			default:
				return
			}
		}
	}
	drainAll := func() {
		drain(cCust1)
		drain(cCust2)
		drain(cOwnerUser)
		drain(cOwnerWorker)
		drain(cEmployeeOther)
		drain(cEmployeeOwner)
	}

	// 1. Owner-tenant notification with a customer user_id:
	// The customer gets it on SSE; another user in the owner's tenant does not get it,
	// and neither does another customer.
	h.Broadcast(Notification{
		ID:        "job-accepted-1",
		Type:      "job_accepted",
		TenantID:  "tenant-owner",
		UserID:    "cust-1",
		Title:     "Courier Assigned",
		Body:      "Your courier has accepted",
		Roles:     []Role{RoleClient},
		Timestamp: time.Now().UTC(),
	})

	select {
	case msg := <-cCust1.Send:
		if len(msg) == 0 {
			t.Errorf("Expected payload for customer cCust1")
		}
	default:
		t.Errorf("cCust1 MUST receive the owner-tenant notification targeted to cust-1")
	}

	select {
	case <-cOwnerWorker.Send:
		t.Errorf("cOwnerWorker in owner tenant MUST NOT receive user-targeted notification for cust-1")
	default:
	}

	select {
	case <-cCust2.Send:
		t.Errorf("cCust2 MUST NOT receive notification targeted to cust-1")
	default:
	}

	select {
	case <-cOwnerUser.Send:
		t.Errorf("cOwnerUser MUST NOT receive notification targeted to cust-1 with client role")
	default:
	}

	drainAll()

	// 2. A tenant role broadcast is still invisible to other tenants.
	h.Broadcast(Notification{
		ID:        "role-broadcast-1",
		Type:      "job_alert",
		TenantID:  "tenant-owner",
		Roles:     []Role{RoleEmployee},
		Timestamp: time.Now().UTC(),
	})

	select {
	case msg := <-cEmployeeOwner.Send:
		if len(msg) == 0 {
			t.Errorf("Expected payload for cEmployeeOwner")
		}
	default:
		t.Errorf("cEmployeeOwner in tenant-owner MUST receive tenant role broadcast")
	}

	select {
	case <-cEmployeeOther.Send:
		t.Errorf("cEmployeeOther in tenant-other MUST NOT receive role broadcast for tenant-owner")
	default:
	}

	select {
	case <-cCust1.Send:
		t.Errorf("cCust1 MUST NOT receive employee role broadcast")
	default:
	}

	drainAll()

	// 3. An admin announcement with no tenant_id reaches its user on SSE.
	h.Broadcast(Notification{
		ID:        "admin-announcement-1",
		Type:      "admin_announcement",
		TenantID:  "",
		UserID:    "cust-1",
		Title:     "Special Update",
		Body:      "Update for cust-1",
		Timestamp: time.Now().UTC(),
	})

	select {
	case msg := <-cCust1.Send:
		if len(msg) == 0 {
			t.Errorf("Expected payload for cCust1")
		}
	default:
		t.Errorf("cCust1 MUST receive admin announcement with no tenant_id")
	}

	select {
	case <-cCust2.Send:
		t.Errorf("cCust2 MUST NOT receive announcement targeted to cust-1")
	default:
	}

	drainAll()

	// 4. Global broadcast is unchanged (reaches all matching roles across tenants).
	h.BroadcastGlobal(Notification{
		ID:        "global-sys-1",
		Type:      "system",
		Title:     "System Update",
		Body:      "Global alert",
		Timestamp: time.Now().UTC(),
	})

	for _, c := range []*SSEClient{cCust1, cCust2, cOwnerUser, cOwnerWorker, cEmployeeOther, cEmployeeOwner} {
		select {
		case msg := <-c.Send:
			if len(msg) == 0 {
				t.Errorf("Expected payload for %s on global broadcast", c.ID)
			}
		default:
			t.Errorf("%s MUST receive global broadcast", c.ID)
		}
	}
}
