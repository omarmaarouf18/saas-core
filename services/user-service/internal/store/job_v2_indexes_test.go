package store

// ADR-0028 §4.2 v2 list-query indexes: the three compound jobs indexes the
// dashboards and courier board page/filter on must exist exactly as
// specified — the key tuples (and their order) are asserted directly.
import (
	"context"
	"testing"
	"time"
)

func TestJobV2Indexes(t *testing.T) {
	s, cleanup := setupTestMongoDB(t)
	if s == nil {
		return
	}
	defer cleanup()

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	specs, err := s.jobs.Indexes().ListSpecifications(ctx)
	if err != nil {
		t.Fatalf("list jobs indexes: %v", err)
	}

	found := map[string]bool{}
	for _, spec := range specs {
		elements, err := spec.KeysDocument.Elements()
		if err != nil {
			continue
		}
		var keys []string
		for _, e := range elements {
			keys = append(keys, e.Key())
		}
		switch {
		case len(keys) == 3 && keys[0] == "user_id" && keys[1] == "status" && keys[2] == "created_at":
			found["customer"] = true
		case len(keys) == 3 && keys[0] == "employee_id" && keys[1] == "status" && keys[2] == "sub_status":
			found["courier"] = true
		case len(keys) == 3 && keys[0] == "owner_id" && keys[1] == "status" && keys[2] == "created_at":
			found["owner"] = true
		}
	}
	for name, want := range map[string]string{
		"customer": "user_id,status,created_at",
		"courier":  "employee_id,status,sub_status",
		"owner":    "owner_id,status,created_at",
	} {
		if !found[name] {
			t.Errorf("missing ADR-0028 v2 compound index for %s dashboards (keys %s)", name, want)
		}
	}
}
