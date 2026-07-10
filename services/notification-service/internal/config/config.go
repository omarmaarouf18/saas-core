package config

import (
	"errors"
	"os"
)

type Config struct {
	Port                 string
	JWTSecret            string
	InternalServiceToken string
	AuthServiceURL       string
	AllowedOrigin        string
}

func Load() (*Config, error) {
	jwtSecret := os.Getenv("JWT_SECRET")
	if jwtSecret == "" {
		return nil, errors.New("config: required env var JWT_SECRET is empty")
	}

	internalServiceToken := os.Getenv("INTERNAL_SERVICE_TOKEN")
	if internalServiceToken == "" {
		return nil, errors.New("config: required env var INTERNAL_SERVICE_TOKEN is empty")
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "3004"
	}

	authServiceURL := os.Getenv("AUTH_SERVICE_URL")
	if authServiceURL == "" {
		authServiceURL = "http://localhost:3002"
	}

	allowedOrigin := os.Getenv("ALLOWED_ORIGIN")
	if allowedOrigin == "" {
		allowedOrigin = "http://localhost:3000"
	}

	return &Config{
		Port:                 port,
		JWTSecret:            jwtSecret,
		InternalServiceToken: internalServiceToken,
		AuthServiceURL:       authServiceURL,
		AllowedOrigin:        allowedOrigin,
	}, nil
}
