package fcm

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"strings"
	"time"
)

// Dispatcher defines the interface for push notification delivery.
type Dispatcher interface {
	SendPush(ctx context.Context, token, title, body string, data map[string]string) (isStale bool, err error)
	IsEnabled() bool
}

// Client implements Dispatcher for FCM HTTP v1 REST API.
type Client struct {
	httpClient           *http.Client
	endpointURL          string
	customEndpoint       bool // true when FCMEndpointURL pointed at an internal relay
	projectID            string
	serviceAccountJSON   string
	enabled              bool
	internalServiceToken string
	authServiceURL       string
}

// FCMMessagePayload matches the FCM HTTP v1 API JSON request structure.
type FCMMessagePayload struct {
	Message FCMMessage `json:"message"`
}

type FCMMessage struct {
	Token        string            `json:"token"`
	Notification FCMNotification   `json:"notification"`
	Data         map[string]string `json:"data,omitempty"`
}

type FCMNotification struct {
	Title string `json:"title"`
	Body  string `json:"body"`
}

// FCMErrorResponse matches FCM HTTP v1 API error payload structure.
type FCMErrorResponse struct {
	Error struct {
		Code    int    `json:"code"`
		Message string `json:"message"`
		Status  string `json:"status"`
		Details []struct {
			ErrorCode string `json:"errorCode"`
		} `json:"details"`
	} `json:"error"`
}

// NewClient initializes an FCM client. If serviceAccountJSON or projectID is empty, it operates in disabled mode.
func NewClient(serviceAccountJSON, projectID, customEndpointURL, authServiceURL, internalServiceToken string, httpClient *http.Client) *Client {
	if httpClient == nil {
		httpClient = &http.Client{Timeout: 5 * time.Second}
	}

	enabled := true
	if strings.TrimSpace(serviceAccountJSON) == "" && strings.TrimSpace(projectID) == "" && strings.TrimSpace(customEndpointURL) == "" {
		log.Println("[FCM-PUSH] ⚠ FCM credentials not set (FCM_SERVICE_ACCOUNT_JSON / FCM_PROJECT_ID) — push notifications disabled")
		enabled = false
	}

	customEndpoint := strings.TrimSpace(customEndpointURL) != ""
	endpoint := customEndpointURL
	if !customEndpoint && projectID != "" {
		endpoint = fmt.Sprintf("https://fcm.googleapis.com/v1/projects/%s/messages:send", projectID)
	}

	return &Client{
		httpClient:           httpClient,
		endpointURL:          endpoint,
		customEndpoint:       customEndpoint,
		projectID:            projectID,
		serviceAccountJSON:   serviceAccountJSON,
		enabled:              enabled,
		internalServiceToken: internalServiceToken,
		authServiceURL:       authServiceURL,
	}
}

func (c *Client) IsEnabled() bool {
	return c.enabled && c.endpointURL != ""
}

// SendPush dispatches a push notification to a device token via FCM HTTP v1 API.
// Returns isStale=true if FCM indicates the token is unregistered or expired.
func (c *Client) SendPush(ctx context.Context, token, title, body string, data map[string]string) (bool, error) {
	if !c.IsEnabled() {
		log.Printf("[FCM-PUSH] FCM disabled, skipping push to token %s", token)
		return false, nil
	}

	payload := FCMMessagePayload{
		Message: FCMMessage{
			Token: token,
			Notification: FCMNotification{
				Title: title,
				Body:  body,
			},
			Data: data,
		},
	}

	bodyBytes, err := json.Marshal(payload)
	if err != nil {
		return false, fmt.Errorf("fcm: failed to marshal payload: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, "POST", c.endpointURL, bytes.NewReader(bodyBytes))
	if err != nil {
		return false, fmt.Errorf("fcm: failed to create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	// X-Internal-Token authenticates service-to-service calls inside our own
	// network. It must never be handed to external hosts: only attach it when
	// an explicit internal relay endpoint (FCMEndpointURL) is configured.
	if c.customEndpoint && c.internalServiceToken != "" {
		req.Header.Set("X-Internal-Token", c.internalServiceToken)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return false, fmt.Errorf("fcm: http request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusOK {
		tokenPreview := token
		if len(tokenPreview) > 10 {
			tokenPreview = tokenPreview[:10]
		}
		log.Printf("[FCM-PUSH] Push delivered successfully to token %s...", tokenPreview)
		return false, nil
	}

	respBody, _ := io.ReadAll(resp.Body)
	var errResp FCMErrorResponse
	_ = json.Unmarshal(respBody, &errResp)

	// Check if token is invalid or unregistered (FCM 404 NOT_FOUND or UNREGISTERED)
	isStale := resp.StatusCode == http.StatusNotFound ||
		errResp.Error.Status == "NOT_FOUND" ||
		errResp.Error.Code == 404

	for _, d := range errResp.Error.Details {
		if d.ErrorCode == "UNREGISTERED" || d.ErrorCode == "INVALID_ARGUMENT" {
			isStale = true
			break
		}
	}

	tokenPreview := token
	if len(tokenPreview) > 10 {
		tokenPreview = tokenPreview[:10]
	}

	if isStale {
		log.Printf("[FCM-PUSH] Stale/unregistered token detected for token %s... (status=%d)", tokenPreview, resp.StatusCode)
		return true, fmt.Errorf("fcm: token unregistered or expired")
	}

	log.Printf("[FCM-PUSH] FCM request failed with status %d: %s", resp.StatusCode, string(respBody))
	return false, fmt.Errorf("fcm: HTTP %d: %s", resp.StatusCode, errResp.Error.Message)
}
