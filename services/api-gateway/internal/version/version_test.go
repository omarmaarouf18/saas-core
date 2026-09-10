package version

import (
	"context"
	"fmt"
	"os"
	"testing"
	"time"

	"go.mongodb.org/mongo-driver/v2/mongo"
	"go.mongodb.org/mongo-driver/v2/mongo/options"
)

func setupTestVersionMongo(t *testing.T) (*mongo.Client, string, func()) {
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://root:devpassword123@localhost:27017/saas_platform?authSource=admin"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	client, err := mongo.Connect(options.Client().ApplyURI(mongoURI))
	if err != nil {
		t.Skipf("skipping MongoDB version tests: %v", err)
		return nil, "", nil
	}

	if err := client.Ping(ctx, nil); err != nil {
		_ = client.Disconnect(ctx)
		t.Skipf("skipping MongoDB version tests: ping failed: %v", err)
		return nil, "", nil
	}

	dbName := fmt.Sprintf("saas_version_test_%d", time.Now().UnixNano())
	cleanup := func() {
		cleanupCtx, cCancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cCancel()
		_ = client.Database(dbName).Drop(cleanupCtx)
		_ = client.Disconnect(cleanupCtx)
	}

	return client, dbName, cleanup
}

func TestVersionStore_InMemoryRevisionIncrement(t *testing.T) {
	store := NewStore(nil, "")

	cfg1, err := store.GetConfig(context.Background())
	if err != nil {
		t.Fatalf("GetConfig failed: %v", err)
	}
	if cfg1.Revision != 0 {
		t.Fatalf("expected initial revision 0, got %d", cfg1.Revision)
	}

	updated, err := store.UpdateConfig(context.Background(), PlatformVersions{
		LatestVersion:           "1.2.0",
		MinimumSupportedVersion: "1.1.0",
	})
	if err != nil {
		t.Fatalf("UpdateConfig failed: %v", err)
	}
	if updated.Revision != 1 {
		t.Fatalf("expected revision 1, got %d", updated.Revision)
	}

	cfg2, err := store.GetConfig(context.Background())
	if err != nil {
		t.Fatalf("GetConfig failed: %v", err)
	}
	if cfg2.Revision != 1 || cfg2.LatestVersion != "1.2.0" {
		t.Fatalf("expected cached revision 1 and version 1.2.0, got revision %d version %s", cfg2.Revision, cfg2.LatestVersion)
	}
}

func TestVersionStore_MongoDB_PersistBeforeCacheAndRevision(t *testing.T) {
	client, dbName, cleanup := setupTestVersionMongo(t)
	if client == nil {
		return
	}
	defer cleanup()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	store := NewStore(client, dbName)

	// First update
	v1, err := store.UpdateConfig(ctx, PlatformVersions{
		LatestVersion:           "2.0.0",
		MinimumSupportedVersion: "1.5.0",
		DownloadURL:             "https://example.com/v2.apk",
	})
	if err != nil {
		t.Fatalf("UpdateConfig 1 failed: %v", err)
	}
	if v1.Revision != 1 {
		t.Fatalf("expected revision 1 after first update, got %d", v1.Revision)
	}

	// Second update increments revision monotonically
	v2, err := store.UpdateConfig(ctx, PlatformVersions{
		LatestVersion:           "2.1.0",
		MinimumSupportedVersion: "2.0.0",
		DownloadURL:             "https://example.com/v2.1.apk",
	})
	if err != nil {
		t.Fatalf("UpdateConfig 2 failed: %v", err)
	}
	if v2.Revision != 2 {
		t.Fatalf("expected revision 2 after second update, got %d", v2.Revision)
	}

	// Persist failure: pass cancelled context.
	// In-memory cache must NOT be corrupted with failed update values.
	cancelledCtx, cancelNow := context.WithCancel(context.Background())
	cancelNow()

	_, err = store.UpdateConfig(cancelledCtx, PlatformVersions{
		LatestVersion:           "3.0.0",
		MinimumSupportedVersion: "3.0.0",
	})
	if err == nil {
		t.Fatalf("expected UpdateConfig to fail with cancelled context, got nil")
	}

	// Cache must still hold v2 ("2.1.0" with Revision 2)
	cached, err := store.GetConfig(ctx)
	if err != nil {
		t.Fatalf("GetConfig failed: %v", err)
	}
	if cached.LatestVersion != "2.1.0" || cached.Revision != 2 {
		t.Fatalf("in-memory cache was corrupted after failed persist! got version %s, revision %d", cached.LatestVersion, cached.Revision)
	}
}
