package hub

import (
	"testing"
	"time"
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

	// 2. Slow client buffer full drop
	slowClient := &SSEClient{ID: "slow", TenantID: "tenant-C", Role: RoleClient, Send: make(chan []byte, 1)}
	// Fill buffer
	slowClient.Send <- []byte("busy")
	h.Register(slowClient)

	// Broadcast to slow client
	h.Broadcast(Notification{
		TenantID: "tenant-C",
		Title:    "Test Slow Drop",
	})
	// Should not block or panic
}
