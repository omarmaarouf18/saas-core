package config_test

import (
	"os"
	"strings"
	"testing"

	"github.com/project/auth-service/internal/config"
)

func TestLoad_DefaultAppEnv(t *testing.T) {
	// Set required environment variables to prevent Load() from failing
	os.Setenv("JWT_SECRET", "dummy-jwt-secret")
	os.Setenv("DOCUMENT_SIGNING_SECRET", "dummy-doc-signing-secret")
	os.Setenv("DOCUMENT_ENCRYPTION_KEY", "dummy-doc-encryption-key")
	os.Setenv("GATEWAY_SECRET", "dummy-gateway-secret")
	os.Setenv("INTERNAL_SERVICE_TOKEN", "dummy-token")
	os.Setenv("TLS_CERT_PATH", "dummy-cert")
	os.Setenv("TLS_KEY_PATH", "dummy-key")
	os.Setenv("TLS_CA_PATH", "dummy-ca")
	os.Setenv("REDIS_URI", "redis://localhost:6379")

	// Unset APP_ENV to test default fallback
	os.Unsetenv("APP_ENV")

	defer func() {
		os.Unsetenv("JWT_SECRET")
		os.Unsetenv("DOCUMENT_SIGNING_SECRET")
		os.Unsetenv("DOCUMENT_ENCRYPTION_KEY")
		os.Unsetenv("GATEWAY_SECRET")
		os.Unsetenv("INTERNAL_SERVICE_TOKEN")
		os.Unsetenv("TLS_CERT_PATH")
		os.Unsetenv("TLS_KEY_PATH")
		os.Unsetenv("TLS_CA_PATH")
		os.Unsetenv("REDIS_URI")
	}()

	cfg, err := config.Load()
	if err != nil {
		t.Fatalf("unexpected error loading config: %v", err)
	}

	if cfg.AppEnv != "production" {
		t.Errorf("expected default AppEnv to be 'production', got %q", cfg.AppEnv)
	}

	isLocal := strings.EqualFold(cfg.AppEnv, "local")
	if isLocal {
		t.Errorf("expected isLocal to be false, got true")
	}
}

func TestLoad_MissingDocumentEncryptionKeyInProduction(t *testing.T) {
	os.Setenv("JWT_SECRET", "dummy-jwt-secret")
	os.Setenv("DOCUMENT_SIGNING_SECRET", "dummy-doc-signing-secret")
	os.Setenv("GATEWAY_SECRET", "dummy-gateway-secret")
	os.Setenv("INTERNAL_SERVICE_TOKEN", "dummy-token")
	os.Setenv("TLS_CERT_PATH", "dummy-cert")
	os.Setenv("TLS_KEY_PATH", "dummy-key")
	os.Setenv("TLS_CA_PATH", "dummy-ca")
	os.Setenv("REDIS_URI", "redis://localhost:6379")
	os.Setenv("APP_ENV", "production")
	os.Unsetenv("DOCUMENT_ENCRYPTION_KEY")

	defer func() {
		os.Unsetenv("JWT_SECRET")
		os.Unsetenv("DOCUMENT_SIGNING_SECRET")
		os.Unsetenv("GATEWAY_SECRET")
		os.Unsetenv("INTERNAL_SERVICE_TOKEN")
		os.Unsetenv("TLS_CERT_PATH")
		os.Unsetenv("TLS_KEY_PATH")
		os.Unsetenv("TLS_CA_PATH")
		os.Unsetenv("REDIS_URI")
		os.Unsetenv("APP_ENV")
	}()

	_, err := config.Load()
	if err == nil {
		t.Fatalf("expected error when DOCUMENT_ENCRYPTION_KEY is missing in production mode, got nil")
	}
	if !strings.Contains(err.Error(), "DOCUMENT_ENCRYPTION_KEY") {
		t.Errorf("expected error to mention DOCUMENT_ENCRYPTION_KEY, got %v", err)
	}
}

func TestLoad_ResendConfig(t *testing.T) {
	os.Setenv("JWT_SECRET", "dummy-jwt-secret")
	os.Setenv("DOCUMENT_SIGNING_SECRET", "dummy-doc-signing-secret")
	os.Setenv("DOCUMENT_ENCRYPTION_KEY", "dummy-doc-encryption-key")
	os.Setenv("GATEWAY_SECRET", "dummy-gateway-secret")
	os.Setenv("INTERNAL_SERVICE_TOKEN", "dummy-token")
	os.Setenv("TLS_CERT_PATH", "dummy-cert")
	os.Setenv("TLS_KEY_PATH", "dummy-key")
	os.Setenv("TLS_CA_PATH", "dummy-ca")
	os.Setenv("REDIS_URI", "redis://localhost:6379")

	defer func() {
		os.Unsetenv("JWT_SECRET")
		os.Unsetenv("DOCUMENT_SIGNING_SECRET")
		os.Unsetenv("DOCUMENT_ENCRYPTION_KEY")
		os.Unsetenv("GATEWAY_SECRET")
		os.Unsetenv("INTERNAL_SERVICE_TOKEN")
		os.Unsetenv("TLS_CERT_PATH")
		os.Unsetenv("TLS_KEY_PATH")
		os.Unsetenv("TLS_CA_PATH")
		os.Unsetenv("REDIS_URI")
		os.Unsetenv("RESEND_API_KEY")
		os.Unsetenv("RESEND_FROM_EMAIL")
	}()

	// Case (a): RESEND_API_KEY set + RESEND_FROM_EMAIL empty -> Load() returns error
	os.Setenv("RESEND_API_KEY", "re_test_123")
	os.Unsetenv("RESEND_FROM_EMAIL")
	if _, err := config.Load(); err == nil {
		t.Errorf("expected error when RESEND_API_KEY is set and RESEND_FROM_EMAIL is empty, got nil")
	}

	// Case (b): Both set -> Load() succeeds
	os.Setenv("RESEND_FROM_EMAIL", "Quick Delivery <onboarding@resend.dev>")
	cfg, err := config.Load()
	if err != nil {
		t.Fatalf("expected success when both RESEND_API_KEY and RESEND_FROM_EMAIL are set, got: %v", err)
	}
	if cfg.ResendAPIKey != "re_test_123" || cfg.ResendFromEmail != "Quick Delivery <onboarding@resend.dev>" {
		t.Errorf("unexpected Resend config values: key=%q, from=%q", cfg.ResendAPIKey, cfg.ResendFromEmail)
	}

	// Case (c): Both empty -> Load() succeeds
	os.Unsetenv("RESEND_API_KEY")
	os.Unsetenv("RESEND_FROM_EMAIL")
	cfg, err = config.Load()
	if err != nil {
		t.Fatalf("expected success when both RESEND_API_KEY and RESEND_FROM_EMAIL are empty, got: %v", err)
	}
	if cfg.ResendAPIKey != "" || cfg.ResendFromEmail != "" {
		t.Errorf("expected empty Resend config values when unset, got key=%q from=%q", cfg.ResendAPIKey, cfg.ResendFromEmail)
	}
}

func TestLoad_MongoDatabaseDefaults(t *testing.T) {
	os.Setenv("JWT_SECRET", "dummy-jwt-secret")
	os.Setenv("DOCUMENT_SIGNING_SECRET", "dummy-doc-signing-secret")
	os.Setenv("DOCUMENT_ENCRYPTION_KEY", "dummy-doc-encryption-key")
	os.Setenv("GATEWAY_SECRET", "dummy-gateway-secret")
	os.Setenv("INTERNAL_SERVICE_TOKEN", "dummy-token")
	os.Setenv("TLS_CERT_PATH", "dummy-cert")
	os.Setenv("TLS_KEY_PATH", "dummy-key")
	os.Setenv("TLS_CA_PATH", "dummy-ca")
	os.Setenv("REDIS_URI", "redis://localhost:6379")

	defer func() {
		os.Unsetenv("JWT_SECRET")
		os.Unsetenv("DOCUMENT_SIGNING_SECRET")
		os.Unsetenv("DOCUMENT_ENCRYPTION_KEY")
		os.Unsetenv("GATEWAY_SECRET")
		os.Unsetenv("INTERNAL_SERVICE_TOKEN")
		os.Unsetenv("TLS_CERT_PATH")
		os.Unsetenv("TLS_KEY_PATH")
		os.Unsetenv("TLS_CA_PATH")
		os.Unsetenv("REDIS_URI")
		os.Unsetenv("AUTH_MONGO_DATABASE")
		os.Unsetenv("MONGO_INITDB_DATABASE")
	}()

	os.Unsetenv("AUTH_MONGO_DATABASE")
	os.Unsetenv("MONGO_INITDB_DATABASE")
	cfg, err := config.Load()
	if err != nil {
		t.Fatalf("unexpected error loading config: %v", err)
	}
	if cfg.MongoDatabase != "auth_db" {
		t.Errorf("expected default MongoDatabase to be 'auth_db', got %q", cfg.MongoDatabase)
	}

	os.Setenv("AUTH_MONGO_DATABASE", "custom_auth_db")
	cfg, err = config.Load()
	if err != nil {
		t.Fatalf("unexpected error loading config: %v", err)
	}
	if cfg.MongoDatabase != "custom_auth_db" {
		t.Errorf("expected MongoDatabase to be 'custom_auth_db', got %q", cfg.MongoDatabase)
	}
}
