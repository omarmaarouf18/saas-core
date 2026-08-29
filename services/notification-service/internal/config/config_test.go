package config

import (
	"os"
	"testing"
)

func TestLoad(t *testing.T) {
	clearEnv := func() {
		os.Unsetenv("JWT_SECRET")
		os.Unsetenv("INTERNAL_SERVICE_TOKEN")
		os.Unsetenv("TLS_CERT_PATH")
		os.Unsetenv("TLS_KEY_PATH")
		os.Unsetenv("TLS_CA_PATH")
		os.Unsetenv("REDIS_URI")
		os.Unsetenv("PORT")
		os.Unsetenv("AUTH_SERVICE_URL")
		os.Unsetenv("ALLOWED_ORIGIN")
		os.Unsetenv("MONGO_URI")
		os.Unsetenv("NOTIFICATION_MONGO_DATABASE")
		os.Unsetenv("MONGO_INITDB_DATABASE")
	}

	clearEnv()
	defer clearEnv()

	// 1. Missing JWT_SECRET
	_, err := Load()
	if err == nil {
		t.Errorf("Expected error for missing JWT_SECRET, got nil")
	}

	// 2. Missing INTERNAL_SERVICE_TOKEN
	os.Setenv("JWT_SECRET", "secret")
	_, err = Load()
	if err == nil {
		t.Errorf("Expected error for missing INTERNAL_SERVICE_TOKEN, got nil")
	}

	// 3. Missing TLS_CERT_PATH
	os.Setenv("INTERNAL_SERVICE_TOKEN", "token")
	_, err = Load()
	if err == nil {
		t.Errorf("Expected error for missing TLS_CERT_PATH, got nil")
	}

	// 4. Missing TLS_KEY_PATH
	os.Setenv("TLS_CERT_PATH", "/path/to/cert")
	_, err = Load()
	if err == nil {
		t.Errorf("Expected error for missing TLS_KEY_PATH, got nil")
	}

	// 5. Missing TLS_CA_PATH
	os.Setenv("TLS_KEY_PATH", "/path/to/key")
	_, err = Load()
	if err == nil {
		t.Errorf("Expected error for missing TLS_CA_PATH, got nil")
	}

	// 6. Missing REDIS_URI
	os.Setenv("TLS_CA_PATH", "/path/to/ca")
	_, err = Load()
	if err == nil {
		t.Errorf("Expected error for missing REDIS_URI, got nil")
	}

	// 7. Success with defaults
	os.Setenv("REDIS_URI", "redis://localhost:6379")
	cfg, err := Load()
	if err != nil {
		t.Fatalf("Unexpected error loading config: %v", err)
	}

	if cfg.Port != "3004" {
		t.Errorf("Expected default Port '3004', got %q", cfg.Port)
	}
	if cfg.MongoURI != "mongodb://localhost:27017/notification_db" {
		t.Errorf("Expected default MongoURI, got %q", cfg.MongoURI)
	}
	if cfg.MongoDatabase != "notification_db" {
		t.Errorf("Expected default MongoDatabase, got %q", cfg.MongoDatabase)
	}
	if cfg.AuthServiceURL != "http://localhost:3002" {
		t.Errorf("Expected default AuthServiceURL, got %q", cfg.AuthServiceURL)
	}
	if cfg.AllowedOrigin != "http://localhost:3000" {
		t.Errorf("Expected default AllowedOrigin, got %q", cfg.AllowedOrigin)
	}

	// 8. Custom Mongo overrides
	os.Setenv("MONGO_URI", "mongodb://custom:27017")
	os.Setenv("NOTIFICATION_MONGO_DATABASE", "custom_notif_db")
	cfgCustom, err := Load()
	if err != nil {
		t.Fatalf("Unexpected error loading custom config: %v", err)
	}
	if cfgCustom.MongoURI != "mongodb://custom:27017" {
		t.Errorf("Expected custom MongoURI, got %q", cfgCustom.MongoURI)
	}
	if cfgCustom.MongoDatabase != "custom_notif_db" {
		t.Errorf("Expected custom MongoDatabase, got %q", cfgCustom.MongoDatabase)
	}
}
