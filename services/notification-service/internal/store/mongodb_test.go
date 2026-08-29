package store

import (
	"context"
	"fmt"
	"os"
	"testing"
	"time"

	"go.mongodb.org/mongo-driver/v2/bson"
)

func setupTestMongoDB(t *testing.T) (*MongoDB, func()) {
	urisToTry := []string{
		os.Getenv("MONGO_URI"),
		"mongodb://root:devpassword123@localhost:27017/?authSource=admin",
		"mongodb://localhost:27017",
	}

	var (
		s   *MongoDB
		err error
	)

	dbName := fmt.Sprintf("saas_notif_store_test_%d", time.Now().UnixNano())

	for _, uri := range urisToTry {
		if uri == "" {
			continue
		}
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		s, err = NewMongoDB(ctx, uri, dbName)
		cancel()
		if err == nil {
			break
		}
	}

	if s == nil {
		t.Skipf("Skipping MongoDB store tests: MongoDB unreachable: %v", err)
		return nil, nil
	}

	cleanup := func() {
		cleanupCtx, cCancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cCancel()
		_ = s.DropDatabase(cleanupCtx)
		_ = s.Close(cleanupCtx)
	}

	return s, cleanup
}

func TestMongoDB_InvalidURI(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 1*time.Second)
	defer cancel()

	_, err := NewMongoDB(ctx, "mongodb://127.0.0.1:59999", "testdb")
	if err == nil {
		t.Errorf("Expected error connecting to unreachable MongoDB URI, got nil")
	}
}

func TestMongoDB_InsertAndListScoping(t *testing.T) {
	s, cleanup := setupTestMongoDB(t)
	if s == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()

	// 1. Direct notification for user-1 in tenant-1
	notif1 := &Notification{
		ID:        "notif-user-1",
		TenantID:  "tenant-1",
		UserID:    "user-1",
		Title:     "Direct user-1",
		Body:      "Hello user 1",
		Timestamp: time.Now().UTC().Add(-3 * time.Minute),
	}
	if err := s.InsertNotification(ctx, notif1); err != nil {
		t.Fatalf("InsertNotification failed: %v", err)
	}

	// 2. Direct notification for user-2 in tenant-1
	notif2 := &Notification{
		ID:        "notif-user-2",
		TenantID:  "tenant-1",
		UserID:    "user-2",
		Title:     "Direct user-2",
		Body:      "Hello user 2",
		Timestamp: time.Now().UTC().Add(-2 * time.Minute),
	}
	if err := s.InsertNotification(ctx, notif2); err != nil {
		t.Fatalf("InsertNotification failed: %v", err)
	}

	// 3. Role-based broadcast in tenant-1 for owner
	notif3 := &Notification{
		ID:        "notif-role-owner",
		TenantID:  "tenant-1",
		Roles:     []string{"owner"},
		Title:     "Owner Broadcast",
		Body:      "Hello owners",
		Timestamp: time.Now().UTC().Add(-1 * time.Minute),
	}
	if err := s.InsertNotification(ctx, notif3); err != nil {
		t.Fatalf("InsertNotification failed: %v", err)
	}

	// 4. Role-based broadcast in tenant-2 for owner (cross-tenant)
	notif4 := &Notification{
		ID:        "notif-tenant-2-owner",
		TenantID:  "tenant-2",
		Roles:     []string{"owner"},
		Title:     "Tenant 2 Owner",
		Body:      "Tenant 2 alert",
		Timestamp: time.Now().UTC(),
	}
	if err := s.InsertNotification(ctx, notif4); err != nil {
		t.Fatalf("InsertNotification failed: %v", err)
	}

	// Query as user-1 with role "client" in tenant-1
	res1, err := s.ListForUser(ctx, "tenant-1", "user-1", []string{"client"}, 30, nil)
	if err != nil {
		t.Fatalf("ListForUser failed: %v", err)
	}
	if len(res1) != 1 || res1[0].ID != "notif-user-1" {
		t.Fatalf("Expected only notif-user-1 for user-1, got %d items: %+v", len(res1), res1)
	}

	// Query as user-1 with role "owner" in tenant-1
	resOwner, err := s.ListForUser(ctx, "tenant-1", "user-1", []string{"owner"}, 30, nil)
	if err != nil {
		t.Fatalf("ListForUser failed: %v", err)
	}
	if len(resOwner) != 2 {
		t.Fatalf("Expected 2 notifications for owner in tenant-1, got %d", len(resOwner))
	}

	// Verify tenant-2 isolation: owner in tenant-1 must NEVER see notif-tenant-2-owner
	for _, n := range resOwner {
		if n.TenantID != "tenant-1" {
			t.Errorf("Cross-tenant leak detected: got notification from tenant %s", n.TenantID)
		}
	}
}

func TestMongoDB_PaginationBeforeCursor(t *testing.T) {
	s, cleanup := setupTestMongoDB(t)
	if s == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()
	baseTime := time.Date(2026, 8, 29, 10, 0, 0, 0, time.UTC)

	// Insert 5 notifications with sequential timestamps
	for i := 1; i <= 5; i++ {
		notif := &Notification{
			ID:        fmt.Sprintf("page-notif-%d", i),
			TenantID:  "tenant-paginated",
			UserID:    "user-page",
			Title:     fmt.Sprintf("Title %d", i),
			Body:      fmt.Sprintf("Body %d", i),
			Timestamp: baseTime.Add(time.Duration(i) * time.Minute),
		}
		if err := s.InsertNotification(ctx, notif); err != nil {
			t.Fatalf("Insert failed: %v", err)
		}
	}

	// Page 1: limit 2, before nil -> should return notif-5 and notif-4
	p1, err := s.ListForUser(ctx, "tenant-paginated", "user-page", nil, 2, nil)
	if err != nil {
		t.Fatalf("Page 1 failed: %v", err)
	}
	if len(p1) != 2 || p1[0].ID != "page-notif-5" || p1[1].ID != "page-notif-4" {
		t.Fatalf("Unexpected Page 1: %+v", p1)
	}

	// Page 2: limit 2, before notif-4 timestamp -> should return notif-3 and notif-2
	beforeP2 := p1[1].Timestamp
	p2, err := s.ListForUser(ctx, "tenant-paginated", "user-page", nil, 2, &beforeP2)
	if err != nil {
		t.Fatalf("Page 2 failed: %v", err)
	}
	if len(p2) != 2 || p2[0].ID != "page-notif-3" || p2[1].ID != "page-notif-2" {
		t.Fatalf("Unexpected Page 2: %+v", p2)
	}

	// Page 3: limit 2, before notif-2 timestamp -> should return notif-1
	beforeP3 := p2[1].Timestamp
	p3, err := s.ListForUser(ctx, "tenant-paginated", "user-page", nil, 2, &beforeP3)
	if err != nil {
		t.Fatalf("Page 3 failed: %v", err)
	}
	if len(p3) != 1 || p3[0].ID != "page-notif-1" {
		t.Fatalf("Unexpected Page 3: %+v", p3)
	}
}

func TestMongoDB_MarkRead(t *testing.T) {
	s, cleanup := setupTestMongoDB(t)
	if s == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()

	notif := &Notification{
		ID:        "read-notif-1",
		TenantID:  "tenant-read",
		UserID:    "user-owner",
		Title:     "Unread item",
		Body:      "Please read me",
		IsRead:    false,
		Timestamp: time.Now().UTC(),
	}
	if err := s.InsertNotification(ctx, notif); err != nil {
		t.Fatalf("Insert failed: %v", err)
	}

	// Another user attempts to mark it read -> should fail with ErrNotFound
	err := s.MarkRead(ctx, "tenant-read", "attacker-user", nil, "read-notif-1")
	if err != ErrNotFound {
		t.Errorf("Expected ErrNotFound for unauthorized user, got %v", err)
	}

	// Legitimate user marks it read
	if err := s.MarkRead(ctx, "tenant-read", "user-owner", nil, "read-notif-1"); err != nil {
		t.Fatalf("MarkRead failed: %v", err)
	}

	// Verify is_read is now true
	items, err := s.ListForUser(ctx, "tenant-read", "user-owner", nil, 10, nil)
	if err != nil || len(items) != 1 || !items[0].IsRead {
		t.Fatalf("Expected is_read=true, got items=%+v, err=%v", items, err)
	}
}

func TestMongoDB_MarkAllRead(t *testing.T) {
	s, cleanup := setupTestMongoDB(t)
	if s == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()

	// Insert 2 for user-A
	_ = s.InsertNotification(ctx, &Notification{
		ID:        "all-read-1",
		TenantID:  "tenant-all",
		UserID:    "user-A",
		Title:     "A1",
		Body:      "B1",
		IsRead:    false,
		Timestamp: time.Now().UTC(),
	})
	_ = s.InsertNotification(ctx, &Notification{
		ID:        "all-read-2",
		TenantID:  "tenant-all",
		UserID:    "user-A",
		Title:     "A2",
		Body:      "B2",
		IsRead:    false,
		Timestamp: time.Now().UTC(),
	})

	// Insert 1 for user-B
	_ = s.InsertNotification(ctx, &Notification{
		ID:        "all-read-B",
		TenantID:  "tenant-all",
		UserID:    "user-B",
		Title:     "B1",
		Body:      "B1",
		IsRead:    false,
		Timestamp: time.Now().UTC(),
	})

	// user-A marks all as read
	if err := s.MarkAllRead(ctx, "tenant-all", "user-A", nil); err != nil {
		t.Fatalf("MarkAllRead failed: %v", err)
	}

	// user-A items should be read
	itemsA, _ := s.ListForUser(ctx, "tenant-all", "user-A", nil, 10, nil)
	for _, n := range itemsA {
		if !n.IsRead {
			t.Errorf("Expected user-A notification %s to be read", n.ID)
		}
	}

	// user-B item must remain UNREAD
	itemsB, _ := s.ListForUser(ctx, "tenant-all", "user-B", nil, 10, nil)
	if len(itemsB) != 1 || itemsB[0].IsRead {
		t.Errorf("User B's notification was affected by User A's MarkAllRead! Items: %+v", itemsB)
	}
}

func TestMongoDB_Delete(t *testing.T) {
	s, cleanup := setupTestMongoDB(t)
	if s == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()

	notif := &Notification{
		ID:        "del-notif-1",
		TenantID:  "tenant-del",
		UserID:    "user-del",
		Title:     "To be deleted",
		Body:      "Body",
		Timestamp: time.Now().UTC(),
	}
	_ = s.InsertNotification(ctx, notif)

	// Unauthorized delete attempt
	err := s.Delete(ctx, "tenant-del", "other-user", nil, "del-notif-1")
	if err != ErrNotFound {
		t.Errorf("Expected ErrNotFound for unauthorized delete, got %v", err)
	}

	// Authorized delete
	if err := s.Delete(ctx, "tenant-del", "user-del", nil, "del-notif-1"); err != nil {
		t.Fatalf("Delete failed: %v", err)
	}

	// Item must be gone
	items, _ := s.ListForUser(ctx, "tenant-del", "user-del", nil, 10, nil)
	if len(items) != 0 {
		t.Fatalf("Expected 0 items after delete, got %d", len(items))
	}
}

func TestMongoDB_DeleteAll(t *testing.T) {
	s, cleanup := setupTestMongoDB(t)
	if s == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()

	_ = s.InsertNotification(ctx, &Notification{
		ID:        "delall-1",
		TenantID:  "tenant-clear",
		UserID:    "user-clear",
		Title:     "Item 1",
		Body:      "Body",
		Timestamp: time.Now().UTC(),
	})
	_ = s.InsertNotification(ctx, &Notification{
		ID:        "delall-2",
		TenantID:  "tenant-clear",
		UserID:    "user-stay",
		Title:     "Item 2",
		Body:      "Body",
		Timestamp: time.Now().UTC(),
	})

	// user-clear deletes all
	if err := s.DeleteAll(ctx, "tenant-clear", "user-clear", nil); err != nil {
		t.Fatalf("DeleteAll failed: %v", err)
	}

	// user-clear should have 0 items
	itemsClear, _ := s.ListForUser(ctx, "tenant-clear", "user-clear", nil, 10, nil)
	if len(itemsClear) != 0 {
		t.Errorf("Expected 0 items for user-clear, got %d", len(itemsClear))
	}

	// user-stay should still have its item
	itemsStay, _ := s.ListForUser(ctx, "tenant-clear", "user-stay", nil, 10, nil)
	if len(itemsStay) != 1 || itemsStay[0].ID != "delall-2" {
		t.Errorf("User-stay item was erroneously deleted! Items: %+v", itemsStay)
	}
}

// TestMongoDB_CrossTenantCrossUserIsolation explicitly validates that tenant A / user A
// cannot view, mark read, or delete notifications belonging to tenant B / user B.
func TestMongoDB_CrossTenantCrossUserIsolation(t *testing.T) {
	s, cleanup := setupTestMongoDB(t)
	if s == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()

	// Tenant 1 / User 1
	_ = s.InsertNotification(ctx, &Notification{
		ID:        "iso-t1-u1",
		TenantID:  "tenant-alpha",
		UserID:    "user-alice",
		Title:     "Confidential Alice",
		Body:      "Alpha secret",
		IsRead:    false,
		Timestamp: time.Now().UTC(),
	})

	// Tenant 1 / User 2
	_ = s.InsertNotification(ctx, &Notification{
		ID:        "iso-t1-u2",
		TenantID:  "tenant-alpha",
		UserID:    "user-adam",
		Title:     "Confidential Adam",
		Body:      "Alpha secret 2",
		IsRead:    false,
		Timestamp: time.Now().UTC(),
	})

	// Tenant 2 / User 1
	_ = s.InsertNotification(ctx, &Notification{
		ID:        "iso-t2-u1",
		TenantID:  "tenant-beta",
		UserID:    "user-bob",
		Title:     "Confidential Bob",
		Body:      "Beta secret",
		IsRead:    false,
		Timestamp: time.Now().UTC(),
	})

	// 1. Bob (tenant-beta) queries history -> MUST NOT see Alice's or Adam's notifications
	bobItems, err := s.ListForUser(ctx, "tenant-beta", "user-bob", nil, 10, nil)
	if err != nil {
		t.Fatalf("Bob ListForUser failed: %v", err)
	}
	if len(bobItems) != 1 || bobItems[0].ID != "iso-t2-u1" {
		t.Fatalf("Bob saw unexpected notifications: %+v", bobItems)
	}

	// 2. Alice (tenant-alpha) queries history -> MUST NOT see Adam's or Bob's notifications
	aliceItems, err := s.ListForUser(ctx, "tenant-alpha", "user-alice", nil, 10, nil)
	if err != nil {
		t.Fatalf("Alice ListForUser failed: %v", err)
	}
	if len(aliceItems) != 1 || aliceItems[0].ID != "iso-t1-u1" {
		t.Fatalf("Alice saw unexpected notifications: %+v", aliceItems)
	}

	// 3. Bob tries to mark Alice's notification as read -> MUST return ErrNotFound
	if err := s.MarkRead(ctx, "tenant-beta", "user-bob", nil, "iso-t1-u1"); err != ErrNotFound {
		t.Errorf("Expected ErrNotFound when Bob attempts to mark Alice's notification as read, got %v", err)
	}

	// 4. Adam tries to mark Alice's notification as read -> MUST return ErrNotFound
	if err := s.MarkRead(ctx, "tenant-alpha", "user-adam", nil, "iso-t1-u1"); err != ErrNotFound {
		t.Errorf("Expected ErrNotFound when Adam attempts to mark Alice's notification as read, got %v", err)
	}

	// 5. Bob tries to delete Alice's notification -> MUST return ErrNotFound
	if err := s.Delete(ctx, "tenant-beta", "user-bob", nil, "iso-t1-u1"); err != ErrNotFound {
		t.Errorf("Expected ErrNotFound when Bob attempts to delete Alice's notification, got %v", err)
	}

	// 6. Adam tries to delete Alice's notification -> MUST return ErrNotFound
	if err := s.Delete(ctx, "tenant-alpha", "user-adam", nil, "iso-t1-u1"); err != ErrNotFound {
		t.Errorf("Expected ErrNotFound when Adam attempts to delete Alice's notification, got %v", err)
	}

	// 7. Verify Alice's notification is still unread and intact
	aliceCheck, err := s.ListForUser(ctx, "tenant-alpha", "user-alice", nil, 10, nil)
	if err != nil || len(aliceCheck) != 1 || aliceCheck[0].IsRead {
		t.Fatalf("Alice's notification was modified or deleted! Items: %+v, err: %v", aliceCheck, err)
	}
}

func TestMongoDB_TTLIndexAndCreatedAt(t *testing.T) {
	s, cleanup := setupTestMongoDB(t)
	if s == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()

	// 1. Insert a notification without setting CreatedAt
	notif := &Notification{
		ID:        "notif-ttl-test",
		TenantID:  "tenant-ttl",
		UserID:    "user-ttl",
		Title:     "TTL Test Notification",
		Body:      "Should have CreatedAt and TTL index",
		Timestamp: time.Now().UTC(),
	}

	beforeInsert := time.Now().UTC().Add(-2 * time.Second)
	if err := s.InsertNotification(ctx, notif); err != nil {
		t.Fatalf("InsertNotification failed: %v", err)
	}
	afterInsert := time.Now().UTC().Add(2 * time.Second)

	// 2. Confirm CreatedAt is populated and close to "now"
	if notif.CreatedAt.IsZero() {
		t.Fatalf("Expected notif.CreatedAt to be populated, got zero time")
	}
	if notif.CreatedAt.Before(beforeInsert) || notif.CreatedAt.After(afterInsert) {
		t.Errorf("Expected CreatedAt to be between %v and %v, got %v", beforeInsert, afterInsert, notif.CreatedAt)
	}

	// Read directly from collection to verify persisted BSON
	var persisted bson.M
	if err := s.notifications.FindOne(ctx, bson.M{"_id": "notif-ttl-test"}).Decode(&persisted); err != nil {
		t.Fatalf("FindOne failed: %v", err)
	}
	rawCreatedAt, ok := persisted["created_at"]
	if !ok || rawCreatedAt == nil {
		t.Fatalf("Persisted document missing created_at field in MongoDB: %+v", persisted)
	}

	// 3. Confirm TTL index exists on created_at with ExpireAfterSeconds == 2592000
	cursor, err := s.notifications.Indexes().List(ctx)
	if err != nil {
		t.Fatalf("List indexes failed: %v", err)
	}
	defer cursor.Close(ctx)

	var indexes []bson.M
	if err := cursor.All(ctx, &indexes); err != nil {
		t.Fatalf("Decode indexes failed: %v", err)
	}

	var foundTTLIndex bool
	for _, idx := range indexes {
		keyMap := make(map[string]any)
		switch k := idx["key"].(type) {
		case bson.M:
			for k1, v1 := range k {
				keyMap[k1] = v1
			}
		case bson.D:
			for _, elem := range k {
				keyMap[elem.Key] = elem.Value
			}
		}

		if keyMap != nil {
			val, hasCreatedAt := keyMap["created_at"]
			if hasCreatedAt && (val == int32(1) || val == int64(1) || val == 1) {
				foundTTLIndex = true
				rawExp, hasExp := idx["expireAfterSeconds"]
				if !hasExp {
					t.Fatalf("Index on created_at exists but lacks expireAfterSeconds: %+v", idx)
				}
				var expSec int64
				switch v := rawExp.(type) {
				case int32:
					expSec = int64(v)
				case int64:
					expSec = v
				case float64:
					expSec = int64(v)
				default:
					t.Fatalf("Unexpected type for expireAfterSeconds: %T (%v)", rawExp, rawExp)
				}
				if expSec != 2592000 {
					t.Errorf("Expected expireAfterSeconds to be 2592000 (30 days), got %d", expSec)
				}
				break
			}
		}
	}

	if !foundTTLIndex {
		t.Fatalf("TTL index on created_at not found in collection indexes: %+v", indexes)
	}
}

func TestMongoDB_BroadcastReadDismissIsPerRecipient(t *testing.T) {
	s, cleanup := setupTestMongoDB(t)
	if s == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()

	// 1. Insert one broadcast notification with Roles: ["owner", "employee"] and no UserID
	notif := &Notification{
		ID:        "bc-alert-1",
		TenantID:  "tenant-broadcast-test",
		Roles:     []string{"owner", "employee"},
		Title:     "New Job Available",
		Body:      "Plumbing job #101 is open for dispatch",
		Timestamp: time.Now().UTC(),
	}
	if err := s.InsertNotification(ctx, notif); err != nil {
		t.Fatalf("InsertNotification failed: %v", err)
	}

	// Confirm both owner-1 and employee-1 see it initially as unread
	ownerInitial, err := s.ListForUser(ctx, "tenant-broadcast-test", "owner-1", []string{"owner"}, 10, nil)
	if err != nil || len(ownerInitial) != 1 {
		t.Fatalf("owner-1 should see the broadcast notification initially, got len=%d, err=%v", len(ownerInitial), err)
	}
	if ownerInitial[0].IsRead {
		t.Errorf("owner-1 should see unread notification initially, got IsRead=true")
	}

	empInitial, err := s.ListForUser(ctx, "tenant-broadcast-test", "employee-1", []string{"employee"}, 10, nil)
	if err != nil || len(empInitial) != 1 {
		t.Fatalf("employee-1 should see the broadcast notification initially, got len=%d, err=%v", len(empInitial), err)
	}
	if empInitial[0].IsRead {
		t.Errorf("employee-1 should see unread notification initially, got IsRead=true")
	}

	// 2. owner-1 calls MarkRead
	if err := s.MarkRead(ctx, "tenant-broadcast-test", "owner-1", []string{"owner"}, "bc-alert-1"); err != nil {
		t.Fatalf("owner-1 MarkRead failed: %v", err)
	}

	// 3. Assert querying as owner-1 shows it read, but querying as employee-1 still shows it unread
	ownerAfterRead, err := s.ListForUser(ctx, "tenant-broadcast-test", "owner-1", []string{"owner"}, 10, nil)
	if err != nil || len(ownerAfterRead) != 1 {
		t.Fatalf("owner-1 should still see 1 notification, got len=%d, err=%v", len(ownerAfterRead), err)
	}
	if !ownerAfterRead[0].IsRead {
		t.Errorf("owner-1 should see notification marked as read (IsRead=true), got false")
	}

	empAfterOwnerRead, err := s.ListForUser(ctx, "tenant-broadcast-test", "employee-1", []string{"employee"}, 10, nil)
	if err != nil || len(empAfterOwnerRead) != 1 {
		t.Fatalf("employee-1 should still see 1 notification, got len=%d, err=%v", len(empAfterOwnerRead), err)
	}
	if empAfterOwnerRead[0].IsRead {
		t.Errorf("employee-1 must still see notification as UNREAD after owner-1 marked read, got IsRead=true")
	}

	// 4. employee-1 calls Delete on it
	if err := s.Delete(ctx, "tenant-broadcast-test", "employee-1", []string{"employee"}, "bc-alert-1"); err != nil {
		t.Fatalf("employee-1 Delete failed: %v", err)
	}

	// 5. Assert employee-1 no longer sees it in ListForUser, but owner-1 still does
	empAfterDelete, err := s.ListForUser(ctx, "tenant-broadcast-test", "employee-1", []string{"employee"}, 10, nil)
	if err != nil {
		t.Fatalf("employee-1 ListForUser failed: %v", err)
	}
	if len(empAfterDelete) != 0 {
		t.Errorf("employee-1 should no longer see dismissed broadcast notification, got %d items", len(empAfterDelete))
	}

	ownerAfterEmpDelete, err := s.ListForUser(ctx, "tenant-broadcast-test", "owner-1", []string{"owner"}, 10, nil)
	if err != nil || len(ownerAfterEmpDelete) != 1 {
		t.Fatalf("owner-1 MUST still see the notification after employee-1 dismissed it! Got len=%d, err=%v", len(ownerAfterEmpDelete), err)
	}
	if !ownerAfterEmpDelete[0].IsRead {
		t.Errorf("owner-1 should still see notification as read, got IsRead=false")
	}
}

// TestMongoDB_BroadcastJobAlert_OwnerAndCustomerMarkReadDelete_Success proves that
// when a broadcast job alert notification is persisted (even if UserID is populated with
// an assigned employee or empty), owners and clients in the tenant can successfully mark it read
// and delete it without encountering ErrNotFound (HTTP 404).
func TestMongoDB_BroadcastJobAlert_OwnerAndCustomerMarkReadDelete_Success(t *testing.T) {
	s, cleanup := setupTestMongoDB(t)
	if s == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()

	alertID := "job-alert-success-1"
	alert := &Notification{
		ID:        alertID,
		TenantID:  "tenant-jobalert",
		UserID:    "emp-assigned-42",
		Roles:     []string{"owner", "employee", "client"},
		Title:     "🆕 New Job Alert",
		Body:      "New job 101 for service Cleaning",
		Timestamp: time.Now().UTC(),
	}
	if err := s.InsertNotification(ctx, alert); err != nil {
		t.Fatalf("InsertNotification failed: %v", err)
	}

	// 1. Owner views notification in ListForUser
	ownerList, err := s.ListForUser(ctx, "tenant-jobalert", "owner-1", []string{"owner"}, 10, nil)
	if err != nil || len(ownerList) != 1 {
		t.Fatalf("Owner should see job alert in ListForUser, got len=%d, err=%v", len(ownerList), err)
	}
	if ownerList[0].IsRead {
		t.Errorf("Owner initially expected is_read: false")
	}

	// 2. Owner marks it read via MarkRead with role "owner" -> must succeed cleanly
	if err := s.MarkRead(ctx, "tenant-jobalert", "owner-1", []string{"owner"}, alertID); err != nil {
		t.Fatalf("Owner MarkRead unexpectedly failed: %v", err)
	}

	ownerListAfter, err := s.ListForUser(ctx, "tenant-jobalert", "owner-1", []string{"owner"}, 10, nil)
	if err != nil || len(ownerListAfter) != 1 || !ownerListAfter[0].IsRead {
		t.Fatalf("Owner expected 1 notification with is_read: true, got %+v, err=%v", ownerListAfter, err)
	}

	// 3. Client in same tenant sees it as unread
	clientList, err := s.ListForUser(ctx, "tenant-jobalert", "client-1", []string{"client"}, 10, nil)
	if err != nil || len(clientList) != 1 || clientList[0].IsRead {
		t.Fatalf("Client expected 1 unread notification, got %+v, err=%v", clientList, err)
	}

	// 4. Client deletes/dismisses the notification -> must succeed cleanly
	if err := s.Delete(ctx, "tenant-jobalert", "client-1", []string{"client"}, alertID); err != nil {
		t.Fatalf("Client Delete unexpectedly failed: %v", err)
	}

	clientListAfter, err := s.ListForUser(ctx, "tenant-jobalert", "client-1", []string{"client"}, 10, nil)
	if err != nil || len(clientListAfter) != 0 {
		t.Fatalf("Client expected 0 notifications after delete, got %d", len(clientListAfter))
	}

	// 5. Owner STILL sees the notification as read
	ownerStillSees, err := s.ListForUser(ctx, "tenant-jobalert", "owner-1", []string{"owner"}, 10, nil)
	if err != nil || len(ownerStillSees) != 1 || !ownerStillSees[0].IsRead {
		t.Fatalf("Owner must still see read notification after client dismissed, got %+v", ownerStillSees)
	}
}

// TestMongoDB_GlobalNotification_RoleScoped_MarkReadDelete_Success proves that
// a Global: true notification targeted to roles can be marked read and deleted
// by users across tenants without failing with ErrNotFound (HTTP 404).
func TestMongoDB_GlobalNotification_RoleScoped_MarkReadDelete_Success(t *testing.T) {
	s, cleanup := setupTestMongoDB(t)
	if s == nil {
		return
	}
	defer cleanup()

	ctx := context.Background()

	globalNotif := &Notification{
		ID:        "global-announcement-succ-1",
		Global:    true,
		UserID:    "admin-system",
		Roles:     []string{"owner", "employee", "client"},
		Title:     "📢 System-wide Maintenance",
		Body:      "Scheduled maintenance tonight",
		Timestamp: time.Now().UTC(),
	}
	if err := s.InsertNotification(ctx, globalNotif); err != nil {
		t.Fatalf("InsertNotification failed: %v", err)
	}

	// 1. User from tenant-A marks it read
	if err := s.MarkRead(ctx, "tenant-A", "user-A", []string{"owner"}, "global-announcement-succ-1"); err != nil {
		t.Fatalf("tenant-A user MarkRead failed: %v", err)
	}

	itemsA, err := s.ListForUser(ctx, "tenant-A", "user-A", []string{"owner"}, 10, nil)
	if err != nil || len(itemsA) != 1 || !itemsA[0].IsRead {
		t.Fatalf("tenant-A expected is_read: true, got %+v", itemsA)
	}

	// 2. User from tenant-B sees it unread
	itemsB, err := s.ListForUser(ctx, "tenant-B", "user-B", []string{"client"}, 10, nil)
	if err != nil || len(itemsB) != 1 || itemsB[0].IsRead {
		t.Fatalf("tenant-B expected is_read: false, got %+v", itemsB)
	}

	// 3. User from tenant-B dismisses it
	if err := s.Delete(ctx, "tenant-B", "user-B", []string{"client"}, "global-announcement-succ-1"); err != nil {
		t.Fatalf("tenant-B user Delete failed: %v", err)
	}

	itemsBAfter, _ := s.ListForUser(ctx, "tenant-B", "user-B", []string{"client"}, 10, nil)
	if len(itemsBAfter) != 0 {
		t.Fatalf("tenant-B expected 0 notifications after delete, got %d", len(itemsBAfter))
	}

	// 4. User from tenant-A still sees it as read
	itemsAAfter, _ := s.ListForUser(ctx, "tenant-A", "user-A", []string{"owner"}, 10, nil)
	if len(itemsAAfter) != 1 || !itemsAAfter[0].IsRead {
		t.Fatalf("tenant-A expected to still see 1 read notification, got %+v", itemsAAfter)
	}
}
