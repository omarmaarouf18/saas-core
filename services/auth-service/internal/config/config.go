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
	TLSCertPath          string
	TLSKeyPath           string
	TLSCAPath            string
	StorageBaseDir       string
	StorageBaseURL       string
	RedisURI             string
	UserServiceURL       string
	ResendAPIKey         string
	ResendFromEmail      string
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
		appEnv = "production"
	}

	storageBaseDir := os.Getenv("STORAGE_BASE_DIR")
	if storageBaseDir == "" {
		storageBaseDir = "./data/documents"
	}

	storageBaseURL := os.Getenv("STORAGE_BASE_URL")
	if storageBaseURL == "" {
		storageBaseURL = "/api/v1"
	}

	userServiceURL := os.Getenv("USER_SERVICE_URL")
	if userServiceURL == "" {
		userServiceURL = "https://user-service:3003"
	}

	resendAPIKey := os.Getenv("RESEND_API_KEY")
	resendFromEmail := os.Getenv("RESEND_FROM_EMAIL")
	if resendAPIKey != "" && resendFromEmail == "" {
		return nil, errors.New("config: RESEND_FROM_EMAIL is required when RESEND_API_KEY is set")
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
		TLSCertPath:          tlsCertPath,
		TLSKeyPath:           tlsKeyPath,
		TLSCAPath:            tlsCAPath,
		RedisURI:             redisURI,
		StorageBaseDir:       storageBaseDir,
		StorageBaseURL:       storageBaseURL,
		UserServiceURL:       userServiceURL,
		ResendAPIKey:         resendAPIKey,
		ResendFromEmail:      resendFromEmail,
	}, nil
}
