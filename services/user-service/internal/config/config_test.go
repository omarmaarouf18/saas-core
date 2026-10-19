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

func TestLoad_DigitalPaymentsEnabled(t *testing.T) {
	t.Setenv("JWT_SECRET", "test-secret-12345678901234567890")
	t.Setenv("INTERNAL_SERVICE_TOKEN", "test-internal-token")
	t.Setenv("TLS_CERT_PATH", "/tmp/cert.pem")
	t.Setenv("TLS_KEY_PATH", "/tmp/key.pem")
	t.Setenv("TLS_CA_PATH", "/tmp/ca.pem")
	t.Setenv("REDIS_URI", "redis://localhost:6379")
	t.Setenv("APP_ENV", "production")
	t.Setenv("ALLOW_TEST_PAYMENT_BYPASS", "")

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
