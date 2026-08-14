package version

import (
	"context"
	"fmt"
	"log"
	"sync"
	"time"

	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
	"go.mongodb.org/mongo-driver/v2/mongo/options"
)

// PlatformVersions represents the app version registry stored in MongoDB (collection: platform_versions).
type PlatformVersions struct {
	ID                      string    `bson:"_id" json:"id"`
	LatestVersion           string    `bson:"latest_version" json:"latest_version"`
	MinimumSupportedVersion string    `bson:"minimum_supported_version" json:"minimum_supported_version"`
	EnforceMinimumVersion   bool      `bson:"enforce_minimum_version" json:"enforce_minimum_version"`
	DownloadURL             string    `bson:"download_url" json:"download_url"`
	UpdatedAt               time.Time `bson:"updated_at" json:"updated_at"`
}

// DefaultVersions returns fallback default version settings for local dev & testing.
func DefaultVersions() PlatformVersions {
	return PlatformVersions{
		ID:                      "global",
		LatestVersion:           "1.0.0",
		MinimumSupportedVersion: "1.0.0",
		EnforceMinimumVersion:   false, // Default false during initial rollout grace period
		DownloadURL:             "https://github.com/omarmaarouf18/quick-delivery-mobile/releases/latest/download/app-release.apk",
		UpdatedAt:               time.Now().UTC(),
	}
}

// Store handles persistence and thread-safe caching of version configuration.
type Store struct {
	mu           sync.RWMutex
	cached       PlatformVersions
	collection   *mongo.Collection
	useInMemory bool
}

// NewStore initializes a new version Store. If client is nil, falls back to in-memory mode.
func NewStore(client *mongo.Client, dbName string) *Store {
	store := &Store{
		cached: DefaultVersions(),
	}

	if client != nil {
		if dbName == "" {
			dbName = "saas_platform"
		}
		store.collection = client.Database(dbName).Collection("platform_versions")
		// Seed default config into MongoDB if not present
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = store.seedInitialConfig(ctx)
	} else {
		store.useInMemory = true
	}

	return store
}

func (s *Store) seedInitialConfig(ctx context.Context) error {
	if s.collection == nil {
		return nil
	}

	var existing PlatformVersions
	err := s.collection.FindOne(ctx, bson.M{"_id": "global"}).Decode(&existing)
	if err == mongo.ErrNoDocuments {
		initial := DefaultVersions()
		_, err := s.collection.InsertOne(ctx, initial)
		if err != nil {
			log.Printf("[VERSION-STORE] Failed to seed initial version config: %v", err)
			return err
		}
		log.Printf("[VERSION-STORE] Seeded default platform_versions config (latest: %s, min: %s)", initial.LatestVersion, initial.MinimumSupportedVersion)
		s.mu.Lock()
		s.cached = initial
		s.mu.Unlock()
		return nil
	} else if err == nil {
		s.mu.Lock()
		s.cached = existing
		s.mu.Unlock()
	}
	return nil
}

// GetConfig returns the active PlatformVersions configuration.
func (s *Store) GetConfig(ctx context.Context) (PlatformVersions, error) {
	if s.useInMemory || s.collection == nil {
		s.mu.RLock()
		defer s.mu.RUnlock()
		return s.cached, nil
	}

	var config PlatformVersions
	err := s.collection.FindOne(ctx, bson.M{"_id": "global"}).Decode(&config)
	if err != nil {
		s.mu.RLock()
		defer s.mu.RUnlock()
		return s.cached, nil // Fall back to cached if query fails
	}

	s.mu.Lock()
	s.cached = config
	s.mu.Unlock()

	return config, nil
}

// UpdateConfig updates the global PlatformVersions configuration in MongoDB and cache.
func (s *Store) UpdateConfig(ctx context.Context, newConfig PlatformVersions) (PlatformVersions, error) {
	newConfig.ID = "global"
	newConfig.UpdatedAt = time.Now().UTC()

	// Validate semver strings
	if _, err := ParseSemVer(newConfig.LatestVersion); err != nil {
		return PlatformVersions{}, fmt.Errorf("invalid latest_version: %w", err)
	}
	if _, err := ParseSemVer(newConfig.MinimumSupportedVersion); err != nil {
		return PlatformVersions{}, fmt.Errorf("invalid minimum_supported_version: %w", err)
	}

	s.mu.Lock()
	s.cached = newConfig
	s.mu.Unlock()

	if !s.useInMemory && s.collection != nil {
		opts := options.UpdateOne().SetUpsert(true)
		_, err := s.collection.UpdateOne(ctx, bson.M{"_id": "global"}, bson.M{"$set": newConfig}, opts)
		if err != nil {
			return PlatformVersions{}, fmt.Errorf("failed to persist version config to MongoDB: %w", err)
		}
	}

	return newConfig, nil
}
