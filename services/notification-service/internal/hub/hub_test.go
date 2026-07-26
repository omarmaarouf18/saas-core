package hub

import (
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
