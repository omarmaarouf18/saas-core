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
