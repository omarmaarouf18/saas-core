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

func TestLoad_RefusesLocalWithCloudWatch(t *testing.T) {
	os.Setenv("JWT_SECRET", "dummy-jwt-secret")
	os.Setenv("DOCUMENT_SIGNING_SECRET", "dummy-doc-signing-secret")
	os.Setenv("GATEWAY_SECRET", "dummy-gateway-secret")
	os.Setenv("INTERNAL_SERVICE_TOKEN", "dummy-token")
	os.Setenv("TLS_CERT_PATH", "dummy-cert")
	os.Setenv("TLS_KEY_PATH", "dummy-key")
	os.Setenv("TLS_CA_PATH", "dummy-ca")
	os.Setenv("REDIS_URI", "redis://localhost:6379")
	os.Setenv("APP_ENV", "local")
	os.Setenv("CLOUDWATCH_LOG_GROUP", "prod-log-group")
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
		os.Unsetenv("CLOUDWATCH_LOG_GROUP")
	}()

	if _, err := config.Load(); err == nil {
		t.Fatalf("expected Load to refuse local + CloudWatch, got nil error")
	} else if !strings.Contains(err.Error(), "CLOUDWATCH_LOG_GROUP") {
		t.Fatalf("expected CloudWatch refusal, got: %v", err)
	}
}

func TestLoad_AllowsLocalWithoutCloudWatch(t *testing.T) {
	os.Setenv("JWT_SECRET", "dummy-jwt-secret")
	os.Setenv("DOCUMENT_SIGNING_SECRET", "dummy-doc-signing-secret")
	os.Setenv("GATEWAY_SECRET", "dummy-gateway-secret")
	os.Setenv("INTERNAL_SERVICE_TOKEN", "dummy-token")
	os.Setenv("TLS_CERT_PATH", "dummy-cert")
	os.Setenv("TLS_KEY_PATH", "dummy-key")
	os.Setenv("TLS_CA_PATH", "dummy-ca")
	os.Setenv("REDIS_URI", "redis://localhost:6379")
	os.Setenv("APP_ENV", "local")
	os.Unsetenv("CLOUDWATCH_LOG_GROUP")
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

	cfg, err := config.Load()
	if err != nil {
		t.Fatalf("local without CloudWatch (staging shape) must start, got: %v", err)
	}
	if cfg.AppEnv != "local" {
		t.Errorf("expected AppEnv local, got %q", cfg.AppEnv)
	}
}

// publishedDevDocKey is the DOCUMENT_ENCRYPTION_KEY published in
// infrastructure/.env.example. The literal is repeated here on purpose: the
// test has to pin the published value, not the constant of the package, so a
// drifting blocklist fails the test.
const publishedDevDocKey = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"

// BE-HARDEN item 7: the published development key is a valid AES-256 key, so
// it passes every format check — but it is public, so every document
// encrypted with it can be decrypted by anyone. The service must refuse to
// start with it outside local/test.
func TestLoad_RefusesPublishedDevDocumentEncryptionKey(t *testing.T) {
	t.Setenv("JWT_SECRET", "dummy-jwt-secret")
	t.Setenv("DOCUMENT_SIGNING_SECRET", "dummy-doc-signing-secret")
	t.Setenv("GATEWAY_SECRET", "dummy-gateway-secret")
	t.Setenv("INTERNAL_SERVICE_TOKEN", "dummy-token")
	t.Setenv("TLS_CERT_PATH", "dummy-cert")
	t.Setenv("TLS_KEY_PATH", "dummy-key")
	t.Setenv("TLS_CA_PATH", "dummy-ca")
	t.Setenv("REDIS_URI", "redis://localhost:6379")
	t.Setenv("DOCUMENT_ENCRYPTION_KEY", publishedDevDocKey)

	// Every environment that is not local/test refuses to start. APP_ENV is
	// compared trimmed and case-insensitively; an unset APP_ENV means
	// production.
	for _, env := range []string{"", "production", "PRODUCTION", " production ", "staging", "prod"} {
		t.Run("refuses "+env, func(t *testing.T) {
			if env == "" {
				t.Setenv("APP_ENV", "")
				os.Unsetenv("APP_ENV")
			} else {
				t.Setenv("APP_ENV", env)
			}
			_, err := config.Load()
			if err == nil {
				t.Fatalf("APP_ENV=%q: expected Load to refuse the published dev key, got nil", env)
			}
			if !strings.Contains(err.Error(), "DOCUMENT_ENCRYPTION_KEY") {
				t.Errorf("APP_ENV=%q: the error must name the variable, got: %v", env, err)
			}
			if strings.Contains(err.Error(), publishedDevDocKey) {
				t.Errorf("APP_ENV=%q: the error must not contain the key: %v", env, err)
			}
		})
	}

	// local and test may use it: the local dev stack copies the example file.
	for _, env := range []string{"local", "LOCAL", " local ", "test", "TEST", " test "} {
		t.Run("allows "+env, func(t *testing.T) {
			t.Setenv("APP_ENV", env)
			if _, err := config.Load(); err != nil {
				t.Fatalf("APP_ENV=%q: expected Load to accept the published dev key, got: %v", env, err)
			}
		})
	}
}
