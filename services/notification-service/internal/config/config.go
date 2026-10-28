package config

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"os"
	"strings"
)

type Config struct {
	Port                  string
	MongoURI              string
	MongoDatabase         string
	JWTSecret             string
	InternalServiceToken  string
	AuthServiceURL        string
	AllowedOrigin         string
	TLSCertPath           string
	TLSKeyPath            string
	TLSCAPath             string
	RedisURI              string
	FCMServiceAccountJSON string
	FCMProjectID          string
	FCMEndpointURL        string
	// FCMAPIBaseURL replaces https://fcm.googleapis.com when set
	// (FCM_API_BASE_URL; local fakes and e2e only). Empty in production.
	FCMAPIBaseURL string
	// FCMStatus is the one-line key status logged by Load (startup and
	// --check-env): "push key loaded (project X)", "push enabled (internal
	// relay ...)" or "push disabled: <reason>". With a key loaded, cmd/main
	// then mints one access token and logs the final "push enabled (project
	// X, token ok)" / "push disabled: token mint failed: ..." line. It never
	// contains credential material.
	FCMStatus string
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
		port = "3004"
	}

	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017/notification_db"
	}

	dbName := os.Getenv("NOTIFICATION_MONGO_DATABASE")
	if dbName == "" {
		dbName = os.Getenv("MONGO_INITDB_DATABASE")
	}
	if dbName == "" {
		dbName = "notification_db"
	}

	authServiceURL := os.Getenv("AUTH_SERVICE_URL")
	if authServiceURL == "" {
		authServiceURL = "http://localhost:3002"
	}

	allowedOrigin := os.Getenv("ALLOWED_ORIGIN")
	if allowedOrigin == "" {
		allowedOrigin = "http://localhost:3000"
	}

	fcmServiceAccountJSON, fcmProjectID, fcmEndpointURL, fcmStatus := loadFCM()
	log.Printf("[CONFIG] %s", fcmStatus)

	return &Config{
		Port:                  port,
		MongoURI:              mongoURI,
		MongoDatabase:         dbName,
		JWTSecret:             jwtSecret,
		InternalServiceToken:  internalServiceToken,
		AuthServiceURL:        authServiceURL,
		AllowedOrigin:         allowedOrigin,
		TLSCertPath:           tlsCertPath,
		TLSKeyPath:            tlsKeyPath,
		TLSCAPath:             tlsCAPath,
		RedisURI:              redisURI,
		FCMServiceAccountJSON: fcmServiceAccountJSON,
		FCMProjectID:          fcmProjectID,
		FCMEndpointURL:        fcmEndpointURL,
		FCMAPIBaseURL:         strings.TrimSpace(os.Getenv("FCM_API_BASE_URL")),
		FCMStatus:             fcmStatus,
	}, nil
}

// serviceAccount holds the fields of a Google service-account key file that
// FCM needs; any other field is ignored.
type serviceAccount struct {
	Type        string `json:"type"`
	ProjectID   string `json:"project_id"`
	ClientEmail string `json:"client_email"`
	PrivateKey  string `json:"private_key"`
}

// loadFCM reads the FCM settings. The service-account key comes from, in
// order: FCM_SERVICE_ACCOUNT_JSON, FCM_CREDENTIALS_JSON (raw JSON), or
// FCM_SERVICE_ACCOUNT_JSON_B64 (base64 of the key file, decoded here).
// FCM_PROJECT_ID defaults to the key's project_id. A missing or unusable
// key disables push (credentials and project are cleared, so the FCM
// client stays disabled) without failing startup, unless FCM_ENDPOINT_URL
// points at an internal relay, which needs no key. Reasons never include
// key material.
func loadFCM() (saJSON, projectID, endpointURL, status string) {
	endpointURL = strings.TrimSpace(os.Getenv("FCM_ENDPOINT_URL"))
	projectID = strings.TrimSpace(os.Getenv("FCM_PROJECT_ID"))

	saJSON = os.Getenv("FCM_SERVICE_ACCOUNT_JSON")
	if saJSON == "" {
		saJSON = os.Getenv("FCM_CREDENTIALS_JSON")
	}
	source := "FCM_SERVICE_ACCOUNT_JSON"
	var reason string
	if saJSON == "" {
		if b64 := os.Getenv("FCM_SERVICE_ACCOUNT_JSON_B64"); b64 != "" {
			source = "FCM_SERVICE_ACCOUNT_JSON_B64"
			decoded, err := decodeBase64(b64)
			if err != nil {
				reason = "FCM_SERVICE_ACCOUNT_JSON_B64 is not valid base64"
			} else {
				saJSON = string(decoded)
			}
		}
	}

	if reason == "" && saJSON != "" {
		var sa serviceAccount
		switch {
		case json.Unmarshal([]byte(saJSON), &sa) != nil:
			reason = source + " is not valid JSON"
		case sa.Type != "service_account" || sa.ClientEmail == "" || sa.PrivateKey == "":
			reason = source + " is not a service-account key (needs type service_account, client_email, private_key)"
		case projectID == "" && sa.ProjectID == "":
			reason = "no FCM_PROJECT_ID and no project_id in " + source
		case projectID == "":
			projectID = sa.ProjectID
		}
	}
	if reason == "" && saJSON == "" {
		reason = "no FCM service-account key (set FCM_SERVICE_ACCOUNT_JSON_B64)"
	}

	switch {
	case endpointURL != "":
		return saJSON, projectID, endpointURL, "push enabled (internal relay FCM_ENDPOINT_URL)"
	case reason != "":
		return "", "", "", "push disabled: " + reason
	}
	return saJSON, projectID, "", fmt.Sprintf("push key loaded (project %s)", projectID)
}

// decodeBase64 decodes standard base64, padded or not, ignoring whitespace
// and line breaks (`base64` wraps its output at 76 columns by default).
func decodeBase64(s string) ([]byte, error) {
	s = strings.Join(strings.Fields(s), "")
	if b, err := base64.StdEncoding.DecodeString(s); err == nil {
		return b, nil
	}
	return base64.RawStdEncoding.DecodeString(s)
}
