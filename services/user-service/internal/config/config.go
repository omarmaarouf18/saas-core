package config

import (
	"errors"
	"os"
)

type Config struct {
	Port                 string
	MongoURI             string
	MongoDatabase        string
	JWTSecret            string
	InternalServiceToken string
	AuthServiceURL       string
	ChatServiceURL       string
	CloudWatchLogGroup   string
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
		port = "3003"
	}

	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017/saas_platform"
	}

	dbName := os.Getenv("MONGO_INITDB_DATABASE")
	if dbName == "" {
		dbName = "saas_platform"
	}

	authServiceURL := os.Getenv("AUTH_SERVICE_URL")
	if authServiceURL == "" {
		authServiceURL = "http://localhost:3002"
	}

	chatServiceURL := os.Getenv("CHAT_SERVICE_URL")
	if chatServiceURL == "" {
		chatServiceURL = "http://localhost:3001"
	}

	return &Config{
		Port:                 port,
		MongoURI:             mongoURI,
		MongoDatabase:        dbName,
		JWTSecret:            jwtSecret,
		InternalServiceToken: internalServiceToken,
		AuthServiceURL:       authServiceURL,
		ChatServiceURL:       chatServiceURL,
		CloudWatchLogGroup:   os.Getenv("CLOUDWATCH_LOG_GROUP"),
	}, nil
}
