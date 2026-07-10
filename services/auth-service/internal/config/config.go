package config

import (
	"errors"
	"os"
)

type Config struct {
	Port                 string
	MongoURI             string
	MongoDatabase        string
	AppEnv               string
	GatewaySecret        string
	InternalServiceToken string
	JWTSecret            string
	OTPAESKey            string
	CloudWatchLogGroup   string
}

func Load() (*Config, error) {
	jwtSecret := os.Getenv("JWT_SECRET")
	if jwtSecret == "" {
		return nil, errors.New("config: required env var JWT_SECRET is empty")
	}

	gatewaySecret := os.Getenv("GATEWAY_SECRET")
	if gatewaySecret == "" {
		return nil, errors.New("config: required env var GATEWAY_SECRET is empty")
	}

	internalServiceToken := os.Getenv("INTERNAL_SERVICE_TOKEN")
	if internalServiceToken == "" {
		return nil, errors.New("config: required env var INTERNAL_SERVICE_TOKEN is empty")
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "3002"
	}

	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}

	dbName := os.Getenv("MONGO_INITDB_DATABASE")
	if dbName == "" {
		dbName = "saas_platform"
	}

	appEnv := os.Getenv("APP_ENV")
	if appEnv == "" {
		appEnv = "local"
	}

	return &Config{
		Port:                 port,
		MongoURI:             mongoURI,
		MongoDatabase:        dbName,
		AppEnv:               appEnv,
		GatewaySecret:        gatewaySecret,
		InternalServiceToken: internalServiceToken,
		JWTSecret:            jwtSecret,
		OTPAESKey:            os.Getenv("OTP_AES_KEY"),
		CloudWatchLogGroup:   os.Getenv("CLOUDWATCH_LOG_GROUP"),
	}, nil
}
