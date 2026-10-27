package storage

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// BE-GAPS-FIX item 4: LocalStorage removes a stored object; a missing key
// is not an error; keys outside the base directory (traversal, a sibling
// directory sharing the base's name prefix, the base itself) are refused.
func TestLocalStorage_Delete(t *testing.T) {
	parent := t.TempDir()
	base := filepath.Join(parent, "store")
	sibling := filepath.Join(parent, "store-other")
	if err := os.MkdirAll(sibling, 0700); err != nil {
		t.Fatalf("mkdir sibling: %v", err)
	}
	victim := filepath.Join(sibling, "keep.txt")
	if err := os.WriteFile(victim, []byte("x"), 0600); err != nil {
		t.Fatalf("write sibling file: %v", err)
	}

	encKey := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
	l, err := NewLocalStorage(base, "http://localhost:8080", "super-secret-jwt-key-32-bytes-long!!", encKey, "test")
	if err != nil {
		t.Fatalf("NewLocalStorage: %v", err)
	}
	var d Deleter = l
	ctx := context.Background()

	key := "services/svc-1/photo.jpg"
	if err := l.Upload(ctx, key, strings.NewReader("img"), "image/jpeg"); err != nil {
		t.Fatalf("Upload: %v", err)
	}
	if err := d.Delete(ctx, key); err != nil {
		t.Fatalf("Delete: %v", err)
	}
	if _, err := l.OpenFile(key); err == nil {
		t.Fatalf("object still readable after Delete")
	}
	if err := d.Delete(ctx, key); err != nil {
		t.Fatalf("Delete of a missing key must succeed, got %v", err)
	}

	for _, bad := range []string{"../store-other/keep.txt", "../../etc/passwd", "", "."} {
		if err := d.Delete(ctx, bad); err == nil {
			t.Errorf("Delete(%q) must be refused", bad)
		}
	}
	if _, err := os.Stat(victim); err != nil {
		t.Fatalf("file outside the base directory was touched: %v", err)
	}
	if _, err := os.Stat(base); err != nil {
		t.Fatalf("base directory removed: %v", err)
	}
}
