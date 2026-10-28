package fcm

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/project/shared/infra/redact"
)

// DefaultAndroidChannelID is the Android notification channel every push
// names. The app (PUSH-FCM) creates a channel with this id; a push naming a
// channel the app never created falls back to the app's default channel.
const DefaultAndroidChannelID = "qd_default"

// DefaultAPIBaseURL is the FCM HTTP v1 API host.
const DefaultAPIBaseURL = "https://fcm.googleapis.com"

const (
	defaultMaxAttempts = 3 // first try + 2 retries on 429/5xx
	defaultRetryBase   = 250 * time.Millisecond
	maxRetryWait       = 2 * time.Second
)

// Dispatcher defines the interface for push notification delivery.
type Dispatcher interface {
	SendPush(ctx context.Context, token, title, body string, data map[string]string) (isStale bool, err error)
	IsEnabled() bool
}

// Client implements Dispatcher for FCM HTTP v1 REST API.
//
// Two modes:
//   - Google (default): every send carries an OAuth2 access token minted
//     from the service-account key (see tokenSource).
//   - Internal relay (FCMEndpointURL set): sends go to that endpoint with
//     X-Internal-Token and no OAuth token, unchanged from before.
type Client struct {
	httpClient           *http.Client
	endpointURL          string
	customEndpoint       bool // true when FCMEndpointURL pointed at an internal relay
	projectID            string
	serviceAccountJSON   string
	enabled              bool
	disabledReason       string // why a Google-mode client is disabled; never key material
	internalServiceToken string
	authServiceURL       string
	tokens               *tokenSource // nil in relay mode
	androidChannelID     string
	maxAttempts          int
	retryBase            time.Duration
}

// Option configures optional Client settings.
type Option func(*options)

type options struct {
	apiBaseURL string
}

// WithAPIBaseURL replaces https://fcm.googleapis.com (tests and local fakes
// only; it must be https or a loopback http URL).
func WithAPIBaseURL(base string) Option {
	return func(o *options) {
		if strings.TrimSpace(base) != "" {
			o.apiBaseURL = strings.TrimRight(strings.TrimSpace(base), "/")
		}
	}
}

// FCMMessagePayload matches the FCM HTTP v1 API JSON request structure.
type FCMMessagePayload struct {
	Message FCMMessage `json:"message"`
}

type FCMMessage struct {
	Token        string            `json:"token"`
	Notification FCMNotification   `json:"notification"`
	Data         map[string]string `json:"data,omitempty"`
	Android      *FCMAndroid       `json:"android,omitempty"`
}

type FCMNotification struct {
	Title string `json:"title"`
	Body  string `json:"body"`
}

// FCMAndroid is the android block of an FCM v1 message.
type FCMAndroid struct {
	Priority     string                  `json:"priority"`
	Notification *FCMAndroidNotification `json:"notification,omitempty"`
}

type FCMAndroidNotification struct {
	ChannelID string `json:"channel_id"`
}

// FCMErrorDetail is one entry of error.details: FcmError carries errorCode,
// google.rpc.BadRequest carries fieldViolations.
type FCMErrorDetail struct {
	ErrorCode       string `json:"errorCode"`
	FieldViolations []struct {
		Field       string `json:"field"`
		Description string `json:"description"`
	} `json:"fieldViolations"`
}

// FCMErrorResponse matches FCM HTTP v1 API error payload structure.
type FCMErrorResponse struct {
	Error struct {
		Code    int              `json:"code"`
		Message string           `json:"message"`
		Status  string           `json:"status"`
		Details []FCMErrorDetail `json:"details"`
	} `json:"error"`
}

// NewClient initializes an FCM client. With a custom endpoint it relays to
// that endpoint; otherwise it needs a usable service-account key and a
// project (FCM_PROJECT_ID or the key's project_id), and stays disabled
// without them.
func NewClient(serviceAccountJSON, projectID, customEndpointURL, authServiceURL, internalServiceToken string, httpClient *http.Client, opts ...Option) *Client {
	if httpClient == nil {
		httpClient = &http.Client{Timeout: 5 * time.Second}
	}
	o := options{apiBaseURL: DefaultAPIBaseURL}
	for _, opt := range opts {
		opt(&o)
	}

	c := &Client{
		httpClient:           httpClient,
		projectID:            strings.TrimSpace(projectID),
		serviceAccountJSON:   serviceAccountJSON,
		internalServiceToken: internalServiceToken,
		authServiceURL:       authServiceURL,
		androidChannelID:     DefaultAndroidChannelID,
		maxAttempts:          defaultMaxAttempts,
		retryBase:            defaultRetryBase,
	}

	if strings.TrimSpace(customEndpointURL) != "" {
		c.customEndpoint = true
		c.endpointURL = customEndpointURL
		c.enabled = true
		return c
	}

	if strings.TrimSpace(serviceAccountJSON) == "" && c.projectID == "" {
		log.Println("[FCM-PUSH] ⚠ FCM credentials not set (FCM_SERVICE_ACCOUNT_JSON / FCM_PROJECT_ID) — push notifications disabled")
		c.disabledReason = "no FCM service-account key"
		return c
	}

	switch {
	case strings.TrimSpace(serviceAccountJSON) == "":
		c.disabledReason = "no FCM service-account key"
	default:
		ts, keyProject, err := newTokenSource(serviceAccountJSON, httpClient)
		if err != nil {
			c.disabledReason = err.Error()
			break
		}
		if c.projectID == "" {
			c.projectID = keyProject
		}
		if c.projectID == "" {
			c.disabledReason = "no FCM_PROJECT_ID and no project_id in the key"
			break
		}
		if err := checkOutboundURL(o.apiBaseURL); err != nil {
			c.disabledReason = "FCM API base URL " + err.Error()
			break
		}
		c.tokens = ts
		c.endpointURL = fmt.Sprintf("%s/v1/projects/%s/messages:send", o.apiBaseURL, url.PathEscape(c.projectID))
		c.enabled = true
	}
	if !c.enabled {
		log.Printf("[FCM-PUSH] push disabled: %s", c.disabledReason)
	}
	return c
}

func (c *Client) IsEnabled() bool {
	return c.enabled && c.endpointURL != ""
}

// StartupCheck mints one access token (it sends nothing) and returns the
// truthful push status line for the startup log and --check-env:
//
//	push enabled (project X, token ok)
//	push disabled: token mint failed: <reason>      (key or grant rejected)
//	push enabled (project X, token mint failed: <reason>; retried on every send)
//	                                                (transient: network, 429, 5xx)
//
// A rejected key disables the client. Relay mode returns "" (config already
// logged it); a client disabled at construction returns its reason. Call it
// once before the client is shared (it may flip enabled).
func (c *Client) StartupCheck(ctx context.Context) string {
	if c.customEndpoint {
		return ""
	}
	if !c.IsEnabled() {
		return "push disabled: " + c.disabledReason
	}
	if _, err := c.tokens.Token(ctx); err != nil {
		var te *tokenError
		if errors.Is(err, errKeyInvalid) || (errors.As(err, &te) && te.Permanent) {
			c.enabled = false
			c.disabledReason = "token mint failed: " + err.Error()
			return "push disabled: " + c.disabledReason
		}
		return fmt.Sprintf("push enabled (project %s, token mint failed: %v; retried on every send)", c.projectID, err)
	}
	return fmt.Sprintf("push enabled (project %s, token ok)", c.projectID)
}

// SendPush dispatches a push notification to a device token via FCM HTTP v1 API.
// Returns isStale=true if FCM indicates the token is unregistered or invalid.
// In Google mode a 401 drops the cached access token and retries once with a
// fresh one; 429 and 5xx are retried with backoff, at most maxAttempts in all.
func (c *Client) SendPush(ctx context.Context, token, title, body string, data map[string]string) (bool, error) {
	if !c.IsEnabled() {
		log.Printf("[FCM-PUSH] FCM disabled, skipping push to token %s...", redact.PreviewToken(token))
		return false, nil
	}

	msg := FCMMessage{
		Token: token,
		Notification: FCMNotification{
			Title: title,
			Body:  body,
		},
		Data: data,
	}
	if !c.customEndpoint {
		msg.Android = &FCMAndroid{
			Priority:     "HIGH",
			Notification: &FCMAndroidNotification{ChannelID: c.androidChannelID},
		}
	}

	bodyBytes, err := json.Marshal(FCMMessagePayload{Message: msg})
	if err != nil {
		return false, fmt.Errorf("fcm: failed to marshal payload: %w", err)
	}

	tokenPreview := redact.PreviewToken(token)
	refreshed := false
	var status int
	var respBody []byte
	for attempt := 1; ; attempt++ {
		var bearer string
		if c.tokens != nil {
			bearer, err = c.tokens.Token(ctx)
			if err != nil {
				log.Printf("[FCM-PUSH] access token unavailable, push to token %s... not sent: %v", tokenPreview, err)
				return false, fmt.Errorf("fcm: access token: %w", err)
			}
		}

		var retryAfter string
		status, retryAfter, respBody, err = c.post(ctx, bodyBytes, bearer)
		if err != nil {
			return false, fmt.Errorf("fcm: http request failed: %s", safeTransportError(err))
		}

		if status == http.StatusOK {
			log.Printf("[FCM-PUSH] Push delivered successfully to token %s...", tokenPreview)
			return false, nil
		}
		if status == http.StatusUnauthorized && c.tokens != nil && !refreshed {
			refreshed = true
			c.tokens.Invalidate(bearer)
			log.Printf("[FCM-PUSH] FCM answered 401, refreshing the access token once")
			attempt-- // the refresh retry does not use up a 429/5xx attempt
			continue
		}
		if (status == http.StatusTooManyRequests || status >= 500) && attempt < c.maxAttempts {
			wait := c.backoff(attempt, retryAfter)
			log.Printf("[FCM-PUSH] FCM answered %d, retry %d/%d in %s", status, attempt, c.maxAttempts-1, wait)
			select {
			case <-ctx.Done():
				return false, fmt.Errorf("fcm: HTTP %d, retry cancelled: %w", status, ctx.Err())
			case <-time.After(wait):
			}
			continue
		}
		break
	}

	var errResp FCMErrorResponse
	_ = json.Unmarshal(respBody, &errResp)

	if isStaleTokenError(status, errResp) {
		log.Printf("[FCM-PUSH] Stale/unregistered token detected for token %s... (status=%d)", tokenPreview, status)
		return true, fmt.Errorf("fcm: token unregistered or invalid")
	}

	msgText := truncate(errResp.Error.Message, 200)
	log.Printf("[FCM-PUSH] FCM request failed with status %d %s: %s", status, errResp.Error.Status, msgText)
	return false, fmt.Errorf("fcm: HTTP %d: %s", status, msgText)
}

// post sends one request and returns status, Retry-After and body.
func (c *Client) post(ctx context.Context, body []byte, bearer string) (int, string, []byte, error) {
	req, err := http.NewRequestWithContext(ctx, "POST", c.endpointURL, bytes.NewReader(body))
	if err != nil {
		return 0, "", nil, fmt.Errorf("fcm: failed to create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	if bearer != "" {
		req.Header.Set("Authorization", "Bearer "+bearer)
	}
	// X-Internal-Token authenticates service-to-service calls inside our own
	// network. It must never be handed to external hosts: only attach it when
	// an explicit internal relay endpoint (FCMEndpointURL) is configured.
	if c.customEndpoint && c.internalServiceToken != "" {
		req.Header.Set("X-Internal-Token", c.internalServiceToken)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return 0, "", nil, err
	}
	defer resp.Body.Close()
	respBody, _ := io.ReadAll(io.LimitReader(resp.Body, 64<<10))
	return resp.StatusCode, resp.Header.Get("Retry-After"), respBody, nil
}

// backoff: retryBase doubled per attempt, or Retry-After seconds when
// given, capped at maxRetryWait either way.
func (c *Client) backoff(attempt int, retryAfter string) time.Duration {
	wait := c.retryBase << (attempt - 1)
	if secs, err := strconv.Atoi(strings.TrimSpace(retryAfter)); err == nil && secs >= 0 {
		wait = time.Duration(secs) * time.Second
	}
	return min(wait, maxRetryWait)
}

// isStaleTokenError reports whether FCM rejected the device token itself:
// 404 / NOT_FOUND / UNREGISTERED, or INVALID_ARGUMENT that names the token
// (field message.token, or "registration token" in the message). Other
// INVALID_ARGUMENT errors are payload bugs and must not delete the token.
func isStaleTokenError(status int, e FCMErrorResponse) bool {
	if status == http.StatusNotFound || e.Error.Status == "NOT_FOUND" || e.Error.Code == 404 {
		return true
	}
	invalidArg := e.Error.Status == "INVALID_ARGUMENT"
	tokenNamed := strings.Contains(strings.ToLower(e.Error.Message), "registration token")
	for _, d := range e.Error.Details {
		switch d.ErrorCode {
		case "UNREGISTERED":
			return true
		case "INVALID_ARGUMENT":
			invalidArg = true
		}
		for _, v := range d.FieldViolations {
			if v.Field == "message.token" {
				tokenNamed = true
			}
		}
	}
	return invalidArg && tokenNamed
}
