package config

import (
	"os"
	"testing"
)

func TestLoad(t *testing.T) {
	clearEnv := func() {
		os.Unsetenv("GATEWAY_SECRET")
		os.Unsetenv("INTERNAL_SERVICE_TOKEN")
		os.Unsetenv("TLS_CERT_PATH")
		os.Unsetenv("TLS_KEY_PATH")
		os.Unsetenv("TLS_CA_PATH")
		os.Unsetenv("EXTERNAL_TLS_CERT_PATH")
		os.Unsetenv("EXTERNAL_TLS_KEY_PATH")
		os.Unsetenv("REDIS_URI")
		os.Unsetenv("PORT")
		os.Unsetenv("ALLOWED_ORIGIN")
		os.Unsetenv("AUTH_SERVICE_URL")
		os.Unsetenv("USER_SERVICE_URL")
		os.Unsetenv("CHAT_SERVICE_URL")
		os.Unsetenv("NOTIFICATION_SERVICE_URL")
	}

	clearEnv()
	defer clearEnv()

	// 1. Missing GATEWAY_SECRET
	_, err := Load()
	if err == nil {
		t.Errorf("Expected error for missing GATEWAY_SECRET, got nil")
	}

	// 2. Missing INTERNAL_SERVICE_TOKEN
	os.Setenv("GATEWAY_SECRET", "secret")
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

	// 6. Missing EXTERNAL_TLS_CERT_PATH
	os.Setenv("TLS_CA_PATH", "/path/to/ca")
	_, err = Load()
	if err == nil {
		t.Errorf("Expected error for missing EXTERNAL_TLS_CERT_PATH, got nil")
	}

	// 7. Missing EXTERNAL_TLS_KEY_PATH
	os.Setenv("EXTERNAL_TLS_CERT_PATH", "/path/to/extcert")
	_, err = Load()
	if err == nil {
		t.Errorf("Expected error for missing EXTERNAL_TLS_KEY_PATH, got nil")
	}

	// 8. Missing REDIS_URI
	os.Setenv("EXTERNAL_TLS_KEY_PATH", "/path/to/extkey")
	_, err = Load()
	if err == nil {
		t.Errorf("Expected error for missing REDIS_URI, got nil")
	}

	// 9. Success with defaults
	os.Setenv("REDIS_URI", "redis://localhost:6379")
	cfg, err := Load()
	if err != nil {
		t.Fatalf("Unexpected error loading config: %v", err)
	}

	if cfg.Port != "8080" {
		t.Errorf("Expected default Port '8080', got %q", cfg.Port)
	}
	if cfg.AllowedOrigin != "http://localhost:3000" {
		t.Errorf("Expected default AllowedOrigin, got %q", cfg.AllowedOrigin)
	}
	if len(cfg.Routes) != 4 {
		t.Errorf("Expected 4 default routes, got %d", len(cfg.Routes))
	}
}
