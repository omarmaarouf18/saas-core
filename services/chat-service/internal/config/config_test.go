package config

import (
	"os"
	"strings"
	"testing"
)

func TestLoad(t *testing.T) {
	// Helper to clear relevant env vars
	clearEnv := func() {
		os.Unsetenv("JWT_SECRET")
		os.Unsetenv("INTERNAL_SERVICE_TOKEN")
		os.Unsetenv("TLS_CERT_PATH")
		os.Unsetenv("TLS_KEY_PATH")
		os.Unsetenv("TLS_CA_PATH")
		os.Unsetenv("REDIS_URI")
		os.Unsetenv("PORT")
		os.Unsetenv("MONGO_URI")
		os.Unsetenv("MONGO_INITDB_DATABASE")
		os.Unsetenv("AUTH_SERVICE_URL")
		os.Unsetenv("USER_SERVICE_URL")
		os.Unsetenv("NOTIFICATION_SERVICE_URL")
		os.Unsetenv("ALLOWED_ORIGIN")
		os.Unsetenv("APP_ENV")
		os.Unsetenv("ATTACHMENT_ENCRYPTION_KEY")
		os.Unsetenv("DOCUMENT_ENCRYPTION_KEY")
		os.Unsetenv("STORAGE_BASE_DIR")
		os.Unsetenv("STORAGE_BASE_URL")
		os.Unsetenv("ATTACHMENT_SIGNING_SECRET")
		os.Unsetenv("DOCUMENT_SIGNING_SECRET")
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

	// 7. Success with defaults. APP_ENV is unset, so it defaults to
	// production and a valid attachment key is required (KEY-FAILFAST).
	os.Setenv("REDIS_URI", "redis://localhost:6379")
	os.Setenv("ATTACHMENT_ENCRYPTION_KEY", validTestAttachmentKey)
	cfg, err := Load()
	if err != nil {
		t.Fatalf("Unexpected error loading config: %v", err)
	}

	if cfg.Port != "3001" {
		t.Errorf("Expected default Port '3001', got %q", cfg.Port)
	}
	if cfg.MongoURI != "mongodb://localhost:27017" {
		t.Errorf("Expected default MongoURI, got %q", cfg.MongoURI)
	}
	if cfg.MongoDatabase != "chat_db" {
		t.Errorf("Expected default MongoDatabase 'chat_db', got %q", cfg.MongoDatabase)
	}
	if cfg.AuthServiceURL != "http://localhost:3002" {
		t.Errorf("Expected default AuthServiceURL, got %q", cfg.AuthServiceURL)
	}
	if cfg.UserServiceURL != "http://localhost:3003" {
		t.Errorf("Expected default UserServiceURL, got %q", cfg.UserServiceURL)
	}
	if cfg.NotificationServiceURL != "http://localhost:3004" {
		t.Errorf("Expected default NotificationServiceURL, got %q", cfg.NotificationServiceURL)
	}
	if cfg.AllowedOrigin != "http://localhost:3000" {
		t.Errorf("Expected default AllowedOrigin, got %q", cfg.AllowedOrigin)
	}

	// 8. Explicit NOTIFICATION_SERVICE_URL
	os.Setenv("NOTIFICATION_SERVICE_URL", "https://notification-service:3004")
	cfg, err = Load()
	if err != nil {
		t.Fatalf("Unexpected error loading explicit config: %v", err)
	}
	if cfg.NotificationServiceURL != "https://notification-service:3004" {
		t.Errorf("Expected explicit NotificationServiceURL 'https://notification-service:3004', got %q", cfg.NotificationServiceURL)
	}
}

// validTestAttachmentKey is a valid 64-hex-character (32-byte) AES-256 key.
const validTestAttachmentKey = "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"

// publishedDevAttachmentKey is the DOCUMENT_ENCRYPTION_KEY published in
// infrastructure/.env.example. The literal is repeated here on purpose so a
// drifting blocklist fails this test.
const publishedDevAttachmentKey = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"

// KEY-FAILFAST item 1: outside local/test chat-service must refuse an empty,
// non-hex, wrong-length or published development attachment key at config
// load. The error names the variable that was used and never contains the
// key. Local/test keep starting with any key.
func TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest(t *testing.T) {
	setRequired := func(t *testing.T) {
		t.Helper()
		t.Setenv("JWT_SECRET", "secret")
		t.Setenv("INTERNAL_SERVICE_TOKEN", "token")
		t.Setenv("TLS_CERT_PATH", "/path/to/cert")
		t.Setenv("TLS_KEY_PATH", "/path/to/key")
		t.Setenv("TLS_CA_PATH", "/path/to/ca")
		t.Setenv("REDIS_URI", "redis://localhost:6379")
		t.Setenv("ATTACHMENT_ENCRYPTION_KEY", "")
		t.Setenv("DOCUMENT_ENCRYPTION_KEY", "")
	}

	badKeys := map[string]string{
		"empty":             "",
		"not hex":           "not-a-hex-key-zzzz",
		"wrong length":      "00112233445566778899aabbccddeeff",
		"published dev key": publishedDevAttachmentKey,
	}
	nonDevEnvs := []string{"staging", "prod", "Production", "production", ""}

	for _, env := range nonDevEnvs {
		for name, key := range badKeys {
			t.Run("refuses "+env+" "+name, func(t *testing.T) {
				setRequired(t)
				t.Setenv("APP_ENV", env)
				t.Setenv("ATTACHMENT_ENCRYPTION_KEY", key)

				_, err := Load()
				if err == nil {
					t.Fatalf("APP_ENV=%q ATTACHMENT_ENCRYPTION_KEY=%s: expected Load to refuse the key, got nil", env, name)
				}
				// An empty ATTACHMENT_ENCRYPTION_KEY falls back to
				// DOCUMENT_ENCRYPTION_KEY, so that is the variable the error
				// must name. Any non-empty bad value names ATTACHMENT_...
				wantVar := "ATTACHMENT_ENCRYPTION_KEY"
				if key == "" {
					wantVar = "DOCUMENT_ENCRYPTION_KEY"
				}
				if !strings.Contains(err.Error(), wantVar) {
					t.Errorf("APP_ENV=%q: error does not name %s: %v", env, wantVar, err)
				}
				if key != "" && strings.Contains(err.Error(), key) {
					t.Errorf("APP_ENV=%q: error leaks the key: %v", env, err)
				}
			})
		}
	}

	t.Run("document fallback names DOCUMENT_ENCRYPTION_KEY", func(t *testing.T) {
		setRequired(t)
		t.Setenv("APP_ENV", "staging")
		t.Setenv("DOCUMENT_ENCRYPTION_KEY", "not-a-hex-key-zzzz")

		_, err := Load()
		if err == nil {
			t.Fatal("expected Load to refuse the fallback DOCUMENT_ENCRYPTION_KEY, got nil")
		}
		if !strings.Contains(err.Error(), "DOCUMENT_ENCRYPTION_KEY") {
			t.Errorf("error does not name DOCUMENT_ENCRYPTION_KEY: %v", err)
		}
		if strings.Contains(err.Error(), "not-a-hex-key-zzzz") {
			t.Errorf("error leaks the key: %v", err)
		}
	})

	t.Run("valid key outside local/test", func(t *testing.T) {
		for _, env := range []string{"staging", "prod", "Production", "production", ""} {
			t.Run(env, func(t *testing.T) {
				setRequired(t)
				t.Setenv("APP_ENV", env)
				t.Setenv("ATTACHMENT_ENCRYPTION_KEY", validTestAttachmentKey)

				if _, err := Load(); err != nil {
					t.Fatalf("APP_ENV=%q: unexpected error with a valid key: %v", env, err)
				}
			})
		}
	})

	for _, env := range []string{"local", "LOCAL", " local ", "test", "TEST", " test "} {
		for name, key := range badKeys {
			t.Run("allows "+env+" "+name, func(t *testing.T) {
				setRequired(t)
				t.Setenv("APP_ENV", env)
				t.Setenv("ATTACHMENT_ENCRYPTION_KEY", key)

				if _, err := Load(); err != nil {
					t.Fatalf("APP_ENV=%q: expected Load to accept the key, got: %v", env, err)
				}
			})
		}
	}
}
