// Package config loads gateway configuration from environment variables.
package config

import (
	"fmt"
	"os"
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
	Port   string
	Routes []ServiceRoute
}

// Load reads configuration from environment variables.
// Falls back to sensible defaults for local development.
func Load() (*Config, error) {
	cfg := &Config{
		Port: envOrDefault("PORT", "8080"),
	}

	// Each route is defined by: path prefix → env var → default address.
	routeDefs := []struct {
		prefix     string
		envKey     string
		defaultURL string
	}{
		{"/api/v1/auth/", "AUTH_SERVICE_URL", "http://auth-service:3002"},
		{"/api/v1/users/", "USER_SERVICE_URL", "http://user-service:3003"},
		{"/api/v1/chat/", "CHAT_SERVICE_URL", "http://chat-service:3001"},
		{"/api/v1/notifications/", "NOTIFICATION_SERVICE_URL", "http://notification-service:3004"},
	}

	for _, rd := range routeDefs {
		target := envOrDefault(rd.envKey, rd.defaultURL)
		if target == "" {
			return nil, fmt.Errorf("config: required env var %s is empty", rd.envKey)
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
