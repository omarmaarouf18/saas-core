// Package config loads gateway configuration from environment variables.
package config

import (
	"fmt"
	"os"
	"strings"
)

// ServiceRoute maps a URL path prefix to a backend service address.
type ServiceRoute struct {
	Prefix      string // path prefix to match  (e.g., "/api/v1/auth/")
	Target      string // backend URL           (e.g., "http://auth-service:3002")
	StripPrefix string // prefix stripped before forwarding (e.g., "/api/v1")
	EnvKey      string // env var name the target was read from
}

// Config holds all runtime configuration for the API Gateway.
type Config struct {
	Port                 string
	Routes               []ServiceRoute
	GatewaySecret        string
	AllowedOrigin        string
	TLSCertPath          string
	TLSKeyPath           string
	TLSCAPath            string
	ExternalTLSCertPath  string
	ExternalTLSKeyPath   string
	InternalServiceToken string
	RedisURI             string
}

// Load reads configuration from environment variables.
// Falls back to sensible defaults for local development.
func Load() (*Config, error) {
	gatewaySecret := os.Getenv("GATEWAY_SECRET")
	if gatewaySecret == "" {
		return nil, fmt.Errorf("config: required env var GATEWAY_SECRET is required and must not be empty")
	}

	internalServiceToken := os.Getenv("INTERNAL_SERVICE_TOKEN")
	if internalServiceToken == "" {
		return nil, fmt.Errorf("config: required env var INTERNAL_SERVICE_TOKEN is required and must not be empty")
	}

	tlsCertPath := os.Getenv("TLS_CERT_PATH")
	if tlsCertPath == "" {
		return nil, fmt.Errorf("config: required env var TLS_CERT_PATH is empty")
	}

	tlsKeyPath := os.Getenv("TLS_KEY_PATH")
	if tlsKeyPath == "" {
		return nil, fmt.Errorf("config: required env var TLS_KEY_PATH is empty")
	}

	tlsCAPath := os.Getenv("TLS_CA_PATH")
	if tlsCAPath == "" {
		return nil, fmt.Errorf("config: required env var TLS_CA_PATH is empty")
	}

	externalTLSCertPath := os.Getenv("EXTERNAL_TLS_CERT_PATH")
	if externalTLSCertPath == "" {
		return nil, fmt.Errorf("config: required env var EXTERNAL_TLS_CERT_PATH is empty")
	}

	externalTLSKeyPath := os.Getenv("EXTERNAL_TLS_KEY_PATH")
	if externalTLSKeyPath == "" {
		return nil, fmt.Errorf("config: required env var EXTERNAL_TLS_KEY_PATH is empty")
	}

	redisURI := os.Getenv("REDIS_URI")
	if redisURI == "" {
		return nil, fmt.Errorf("config: required env var REDIS_URI is empty")
	}

	cfg := &Config{
		Port:                 envOrDefault("PORT", "8080"),
		GatewaySecret:        gatewaySecret,
		AllowedOrigin:        envOrDefault("ALLOWED_ORIGIN", "http://localhost:3000"),
		TLSCertPath:          tlsCertPath,
		TLSKeyPath:           tlsKeyPath,
		TLSCAPath:            tlsCAPath,
		ExternalTLSCertPath:  externalTLSCertPath,
		ExternalTLSKeyPath:   externalTLSKeyPath,
		InternalServiceToken: internalServiceToken,
		RedisURI:             redisURI,
	}

	// Each route is defined by: path prefix → env var → default address.
	routeDefs := []struct {
		prefix     string
		envKey     string
		defaultURL string
	}{
		{"/api/v1/auth/", "AUTH_SERVICE_URL", "https://auth-service:3002"},
		{"/api/v1/users/", "USER_SERVICE_URL", "https://user-service:3003"},
		{"/api/v1/chat/", "CHAT_SERVICE_URL", "https://chat-service:3001"},
		{"/api/v1/notifications/stream", "NOTIFICATION_SERVICE_URL", "https://notification-service:3004"},
	}

	for _, rd := range routeDefs {
		target := envOrDefault(rd.envKey, rd.defaultURL)
		if target == "" {
			return nil, fmt.Errorf("config: required env var %s is empty", rd.envKey)
		}
		if tlsCertPath != "" && !strings.HasPrefix(target, "https://") {
			return nil, fmt.Errorf("config: route %s target %q must use https scheme when mTLS client config is active", rd.prefix, target)
		}
		cfg.Routes = append(cfg.Routes, ServiceRoute{
			Prefix:      rd.prefix,
			Target:      target,
			StripPrefix: "/api/v1",
			EnvKey:      rd.envKey,
		})
	}

	return cfg, nil
}

func envOrDefault(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
