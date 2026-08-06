package config

import (
	"os"
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
