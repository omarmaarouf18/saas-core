package config

import (
	"errors"
	"os"
)

type Config struct {
	Port                   string
	MongoURI               string
	MongoDatabase          string
	JWTSecret              string
	InternalServiceToken   string
	AuthServiceURL         string
	UserServiceURL         string
	NotificationServiceURL string
	AllowedOrigin          string
	CloudWatchLogGroup     string
	TLSCertPath            string
	TLSKeyPath             string
	TLSCAPath              string
	RedisURI               string
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

	tlsCertPath := os.Getenv("TLS_CERT_PATH")
	if tlsCertPath == "" {
		return nil, errors.New("config: required env var TLS_CERT_PATH is empty")
	}

	tlsKeyPath := os.Getenv("TLS_KEY_PATH")
	if tlsKeyPath == "" {
		return nil, errors.New("config: required env var TLS_KEY_PATH is empty")
	}

	tlsCAPath := os.Getenv("TLS_CA_PATH")
	if tlsCAPath == "" {
		return nil, errors.New("config: required env var TLS_CA_PATH is empty")
	}

	redisURI := os.Getenv("REDIS_URI")
	if redisURI == "" {
		return nil, errors.New("config: required env var REDIS_URI is empty")
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "3001"
	}

	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}

	dbName := os.Getenv("MONGO_INITDB_DATABASE")
	if dbName == "" {
		dbName = "chat_db"
	}

	authServiceURL := os.Getenv("AUTH_SERVICE_URL")
	if authServiceURL == "" {
		authServiceURL = "http://localhost:3002"
	}

	userServiceURL := os.Getenv("USER_SERVICE_URL")
	if userServiceURL == "" {
		userServiceURL = "http://localhost:3003"
	}

	notificationServiceURL := os.Getenv("NOTIFICATION_SERVICE_URL")
	if notificationServiceURL == "" {
		notificationServiceURL = "http://localhost:3004"
	}

	allowedOrigin := os.Getenv("ALLOWED_ORIGIN")
	if allowedOrigin == "" {
		allowedOrigin = "http://localhost:3000"
	}

	return &Config{
		Port:                   port,
		MongoURI:               mongoURI,
		MongoDatabase:          dbName,
		JWTSecret:              jwtSecret,
		InternalServiceToken:   internalServiceToken,
		AuthServiceURL:         authServiceURL,
		UserServiceURL:         userServiceURL,
		NotificationServiceURL: notificationServiceURL,
		AllowedOrigin:          allowedOrigin,
		CloudWatchLogGroup:     os.Getenv("CLOUDWATCH_LOG_GROUP"),
		TLSCertPath:            tlsCertPath,
		TLSKeyPath:             tlsKeyPath,
		TLSCAPath:              tlsCAPath,
		RedisURI:               redisURI,
	}, nil
}
