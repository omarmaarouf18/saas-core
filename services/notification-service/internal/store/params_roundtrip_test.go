package store

import (
	"context"
	"testing"
	"time"
)

// PUSH-L10N item 3: a notification's template params survive MongoDB;
// documents without params (older history) read back with none.
func TestMongoDB_ParamsRoundTrip(t *testing.T) {
	s, cleanup := setupTestMongoDB(t)
	defer cleanup()
	ctx := context.Background()

	now := time.Now().UTC()
	for _, n := range []*Notification{
		{ID: "n-params", Type: "job_accepted", TenantID: "t1", UserID: "u1", Title: "T", Body: "B",
			Timestamp: now, Params: map[string]string{"fare": "45.50", "variant": "negotiable"}},
		{ID: "n-legacy", Type: "job_accepted", TenantID: "t1", UserID: "u1", Title: "T", Body: "B",
			Timestamp: now.Add(-time.Minute)},
	} {
		if err := s.InsertNotification(ctx, n); err != nil {
			t.Fatalf("insert %s: %v", n.ID, err)
		}
	}
	items, err := s.ListForUser(ctx, "t1", "u1", []string{"client"}, 10, nil)
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	got := map[string]map[string]string{}
	for _, it := range items {
		got[it.ID] = it.Params
	}
	if p := got["n-params"]; p["fare"] != "45.50" || p["variant"] != "negotiable" {
		t.Errorf("params: got %v", p)
	}
	if p, ok := got["n-legacy"]; !ok || p != nil {
		t.Errorf("legacy item: got %v (found %v), want no params", p, ok)
	}
}
