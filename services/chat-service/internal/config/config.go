package config

import (
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"strings"
)

// devAttachmentEncryptionKey is the DOCUMENT_ENCRYPTION_KEY published in
// infrastructure/.env.example. It is a syntactically valid AES-256 key, so a
// deployment that copies the example file passes every format check — but
// every attachment encrypted with it can be decrypted by everyone who reads
// the repository. Outside local/test the service refuses to start. The value
// is never written to a log or to an error message.
const devAttachmentEncryptionKey = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"

// isDevOnlyAppEnv reports whether appEnv names an environment that may use
// the published development key: local development and the test suite. The
// rule matches auth-service and user-service: trimmed, case-insensitive, and
// only "local" or "test".
func isDevOnlyAppEnv(appEnv string) bool {
	switch strings.ToLower(strings.TrimSpace(appEnv)) {
	case "local", "test":
		return true
	default:
		return false
	}
}

type Config struct {
	Port                    string
	MongoURI                string
	MongoDatabase           string
	JWTSecret               string
	InternalServiceToken    string
	AuthServiceURL          string
	UserServiceURL          string
	NotificationServiceURL  string
	AllowedOrigin           string
	CloudWatchLogGroup      string
	TLSCertPath             string
	TLSKeyPath              string
	TLSCAPath               string
	RedisURI                string
	AppEnv                  string
	StorageBaseDir          string
	StorageBaseURL          string
	AttachmentEncryptionKey string
	AttachmentSigningSecret string
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

	appEnv := os.Getenv("APP_ENV")
	if appEnv == "" {
		appEnv = "production"
	}

	storageBaseDir := os.Getenv("STORAGE_BASE_DIR")
	if storageBaseDir == "" {
		storageBaseDir = "./data/attachments"
	}

	storageBaseURL := os.Getenv("STORAGE_BASE_URL")
	if storageBaseURL == "" {
		storageBaseURL = "/api/v1"
	}

	attachmentKeyEnv := "ATTACHMENT_ENCRYPTION_KEY"
	attachmentKey := os.Getenv(attachmentKeyEnv)
	if attachmentKey == "" {
		attachmentKeyEnv = "DOCUMENT_ENCRYPTION_KEY"
		attachmentKey = os.Getenv(attachmentKeyEnv)
	}
	// Outside local/test the service refuses an unusable attachment key at
	// startup, the same rule auth-service and user-service apply. In
	// local/test the storage layer accepts any key (it derives or generates
	// one), so development and tests keep starting.
	if !isDevOnlyAppEnv(appEnv) {
		if err := validateAttachmentEncryptionKey(attachmentKeyEnv, attachmentKey); err != nil {
			return nil, err
		}
	}

	attachmentSecret := os.Getenv("ATTACHMENT_SIGNING_SECRET")
	if attachmentSecret == "" {
		attachmentSecret = os.Getenv("DOCUMENT_SIGNING_SECRET")
	}
	if attachmentSecret == "" {
		attachmentSecret = jwtSecret
	}

	return &Config{
		Port:                    port,
		MongoURI:                mongoURI,
		MongoDatabase:           dbName,
		JWTSecret:               jwtSecret,
		InternalServiceToken:    internalServiceToken,
		AuthServiceURL:          authServiceURL,
		UserServiceURL:          userServiceURL,
		NotificationServiceURL:  notificationServiceURL,
		AllowedOrigin:           allowedOrigin,
		CloudWatchLogGroup:      os.Getenv("CLOUDWATCH_LOG_GROUP"),
		TLSCertPath:             tlsCertPath,
		TLSKeyPath:              tlsKeyPath,
		TLSCAPath:               tlsCAPath,
		RedisURI:                redisURI,
		AppEnv:                  appEnv,
		StorageBaseDir:          storageBaseDir,
		StorageBaseURL:          storageBaseURL,
		AttachmentEncryptionKey: attachmentKey,
		AttachmentSigningSecret: attachmentSecret,
	}, nil
}

// validateAttachmentEncryptionKey checks that key is a usable AES-256 key:
// exactly 64 hex characters (32 bytes), and not the key published in
// infrastructure/.env.example. name is the environment variable the key came
// from, so the error names it. The error never contains the key.
func validateAttachmentEncryptionKey(name, key string) error {
	if key == "" {
		return fmt.Errorf("config: %s is empty; set a 64-character hex key outside local/test", name)
	}
	if key == devAttachmentEncryptionKey {
		return fmt.Errorf("config: refusing to start: %s is the published development key; generate a unique key (openssl rand -hex 32) before deploying outside local/test", name)
	}
	keyBytes, err := hex.DecodeString(key)
	if err != nil {
		return fmt.Errorf("config: %s is not a valid hex string", name)
	}
	if len(keyBytes) != 32 {
		return fmt.Errorf("config: %s must be 32 bytes (64 hex characters), got %d bytes", name, len(keyBytes))
	}
	return nil
}
