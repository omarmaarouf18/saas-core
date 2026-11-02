package config

import (
	"os"
	"strings"
	"testing"
)

func TestLoad_AllowTestPaymentBypass(t *testing.T) {
	os.Setenv("JWT_SECRET", "test-secret-12345678901234567890")
	os.Setenv("INTERNAL_SERVICE_TOKEN", "test-internal-token")
	os.Setenv("TLS_CERT_PATH", "/tmp/cert.pem")
	os.Setenv("TLS_KEY_PATH", "/tmp/key.pem")
	os.Setenv("TLS_CA_PATH", "/tmp/ca.pem")
	os.Setenv("REDIS_URI", "redis://localhost:6379")
	defer func() {
		os.Unsetenv("ALLOW_TEST_PAYMENT_BYPASS")
		os.Unsetenv("APP_ENV")
	}()

	// Case 1: ALLOW_TEST_PAYMENT_BYPASS=true in production environment MUST fail
	os.Setenv("APP_ENV", "production")
	os.Setenv("ALLOW_TEST_PAYMENT_BYPASS", "true")
	_, err := Load()
	if err == nil {
		t.Fatal("Expected error when ALLOW_TEST_PAYMENT_BYPASS=true in APP_ENV=production, got nil")
	}

	// Case 2: ALLOW_TEST_PAYMENT_BYPASS=true in test environment MUST succeed
	os.Setenv("APP_ENV", "test")
	os.Setenv("ALLOW_TEST_PAYMENT_BYPASS", "true")
	cfg, err := Load()
	if err != nil {
		t.Fatalf("Expected success when ALLOW_TEST_PAYMENT_BYPASS=true in APP_ENV=test, got err: %v", err)
	}
	if !cfg.AllowTestPaymentBypass {
		t.Error("Expected AllowTestPaymentBypass to be true")
	}
}

func TestLoad_MongoDatabaseDefaults(t *testing.T) {
	os.Setenv("JWT_SECRET", "test-secret-12345678901234567890")
	os.Setenv("INTERNAL_SERVICE_TOKEN", "test-internal-token")
	os.Setenv("TLS_CERT_PATH", "/tmp/cert.pem")
	os.Setenv("TLS_KEY_PATH", "/tmp/key.pem")
	os.Setenv("TLS_CA_PATH", "/tmp/ca.pem")
	os.Setenv("REDIS_URI", "redis://localhost:6379")
	t.Setenv("DOCUMENT_ENCRYPTION_KEY", testDocKey)

	defer func() {
		os.Unsetenv("JWT_SECRET")
		os.Unsetenv("INTERNAL_SERVICE_TOKEN")
		os.Unsetenv("TLS_CERT_PATH")
		os.Unsetenv("TLS_KEY_PATH")
		os.Unsetenv("TLS_CA_PATH")
		os.Unsetenv("REDIS_URI")
		os.Unsetenv("USER_MONGO_DATABASE")
		os.Unsetenv("MONGO_INITDB_DATABASE")
	}()

	os.Unsetenv("USER_MONGO_DATABASE")
	os.Unsetenv("MONGO_INITDB_DATABASE")
	cfg, err := Load()
	if err != nil {
		t.Fatalf("unexpected error loading config: %v", err)
	}
	if cfg.MongoDatabase != "user_db" {
		t.Errorf("expected default MongoDatabase to be 'user_db', got %q", cfg.MongoDatabase)
	}

	os.Setenv("USER_MONGO_DATABASE", "custom_user_db")
	cfg, err = Load()
	if err != nil {
		t.Fatalf("unexpected error loading config: %v", err)
	}
	if cfg.MongoDatabase != "custom_user_db" {
		t.Errorf("expected MongoDatabase to be 'custom_user_db', got %q", cfg.MongoDatabase)
	}
}

func TestLoad_DigitalPaymentsEnabled(t *testing.T) {
	t.Setenv("JWT_SECRET", "test-secret-12345678901234567890")
	t.Setenv("INTERNAL_SERVICE_TOKEN", "test-internal-token")
	t.Setenv("TLS_CERT_PATH", "/tmp/cert.pem")
	t.Setenv("TLS_KEY_PATH", "/tmp/key.pem")
	t.Setenv("TLS_CA_PATH", "/tmp/ca.pem")
	t.Setenv("REDIS_URI", "redis://localhost:6379")
	t.Setenv("APP_ENV", "production")
	t.Setenv("ALLOW_TEST_PAYMENT_BYPASS", "")
	t.Setenv("DOCUMENT_ENCRYPTION_KEY", testDocKey)

	cases := []struct {
		name, digital, legacy string
		want, wantErr         bool
	}{
		{"default off", "", "", false, false},
		{"explicit false", "false", "", false, false},
		{"explicit true", "true", "", true, false},
		{"one", "1", "", true, false},
		{"legacy alias honoured", "", "true", true, false},
		{"both agree", "true", "1", true, false},
		{"both disagree", "false", "true", false, true},
		{"invalid value", "yes", "", false, true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Setenv("DIGITAL_PAYMENTS_ENABLED", tc.digital)
			t.Setenv("ELECTRONIC_PAYMENTS_ENABLED", tc.legacy)
			cfg, err := Load()
			if tc.wantErr {
				if err == nil {
					t.Fatalf("expected an error, got cfg %+v", cfg)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if cfg.DigitalPaymentsEnabled != tc.want {
				t.Errorf("DigitalPaymentsEnabled = %v, want %v", cfg.DigitalPaymentsEnabled, tc.want)
			}
		})
	}
}

// testDocKey is a valid 64-hex-character (32-byte) test key.
const testDocKey = "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"

// PROD-PHOTO-STORAGE item 1: an empty or invalid DOCUMENT_ENCRYPTION_KEY is
// a config error in production and a --check-env warning elsewhere; the
// message never contains the key.
func TestLoad_DocumentEncryptionKey(t *testing.T) {
	t.Setenv("JWT_SECRET", "test-secret-12345678901234567890")
	t.Setenv("INTERNAL_SERVICE_TOKEN", "test-internal-token")
	t.Setenv("TLS_CERT_PATH", "/tmp/cert.pem")
	t.Setenv("TLS_KEY_PATH", "/tmp/key.pem")
	t.Setenv("TLS_CA_PATH", "/tmp/ca.pem")
	t.Setenv("REDIS_URI", "redis://localhost:6379")
	t.Setenv("ALLOW_TEST_PAYMENT_BYPASS", "")

	badKeys := map[string]string{
		"empty":          "",
		"not hex":        "not-a-hex-key-zzzz",
		"too short":      "00112233445566778899aabbccddeeff",
		"too long":       testDocKey + "00",
		"odd hex length": testDocKey[:63],
	}
	for name, key := range badKeys {
		t.Run(name, func(t *testing.T) {
			t.Setenv("DOCUMENT_ENCRYPTION_KEY", key)

			t.Setenv("APP_ENV", "production")
			cfg, err := Load()
			if err == nil {
				t.Fatalf("production: expected an error, got cfg with warnings %v", cfg.Warnings)
			}
			if !strings.Contains(err.Error(), "DOCUMENT_ENCRYPTION_KEY") {
				t.Errorf("production: error does not name the variable: %v", err)
			}
			if key != "" && strings.Contains(err.Error(), key) {
				t.Errorf("production: error leaks the key: %v", err)
			}

			for _, env := range []string{"local", "test"} {
				t.Setenv("APP_ENV", env)
				cfg, err := Load()
				if err != nil {
					t.Fatalf("%s: expected a warning, got error: %v", env, err)
				}
				if len(cfg.Warnings) != 1 || !strings.Contains(cfg.Warnings[0], "DOCUMENT_ENCRYPTION_KEY") ||
					!strings.Contains(cfg.Warnings[0], "photo_storage_unavailable") {
					t.Errorf("%s: unexpected warnings %v", env, cfg.Warnings)
				}
			}
		})
	}

	t.Run("valid key", func(t *testing.T) {
		t.Setenv("DOCUMENT_ENCRYPTION_KEY", testDocKey)
		for _, env := range []string{"production", "local", "test"} {
			t.Setenv("APP_ENV", env)
			cfg, err := Load()
			if err != nil {
				t.Fatalf("%s: unexpected error: %v", env, err)
			}
			if len(cfg.Warnings) != 0 {
				t.Errorf("%s: unexpected warnings %v", env, cfg.Warnings)
			}
		}
	})
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
	t.Setenv("JWT_SECRET", "test-secret-12345678901234567890")
	t.Setenv("INTERNAL_SERVICE_TOKEN", "test-internal-token")
	t.Setenv("TLS_CERT_PATH", "/tmp/cert.pem")
	t.Setenv("TLS_KEY_PATH", "/tmp/key.pem")
	t.Setenv("TLS_CA_PATH", "/tmp/ca.pem")
	t.Setenv("REDIS_URI", "redis://localhost:6379")
	t.Setenv("ALLOW_TEST_PAYMENT_BYPASS", "")
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
			_, err := Load()
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
			cfg, err := Load()
			if err != nil {
				t.Fatalf("APP_ENV=%q: expected Load to accept the published dev key, got: %v", env, err)
			}
			if len(cfg.Warnings) != 0 {
				t.Errorf("APP_ENV=%q: unexpected warnings %v", env, cfg.Warnings)
			}
		})
	}
}
