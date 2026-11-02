package hub

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/project/shared/infra/resilience"
)

// HTTPDeviceTokenFetcher fetches user device tokens from auth-service via HTTP.
type HTTPDeviceTokenFetcher struct {
	authServiceURL       string
	internalServiceToken string
	resilienceClient     *resilience.ResilienceClient
}

func NewHTTPDeviceTokenFetcher(authServiceURL, internalServiceToken string, client *http.Client) *HTTPDeviceTokenFetcher {
	if client == nil {
		client = &http.Client{Timeout: 5 * time.Second}
	}
	resClient := resilience.NewClient(client, "auth-service", 2, 5*time.Second)
	return &HTTPDeviceTokenFetcher{
		authServiceURL:       authServiceURL,
		internalServiceToken: internalServiceToken,
		resilienceClient:     resClient,
	}
}

func (f *HTTPDeviceTokenFetcher) GetUserDeviceTokens(ctx context.Context, userID string) ([]string, error) {
	targets, err := f.GetUserPushTargets(ctx, userID)
	if err != nil {
		return nil, err
	}
	tokens := make([]string, 0, len(targets))
	for _, t := range targets {
		tokens = append(tokens, t.Token)
	}
	return tokens, nil
}

// GetUserPushTargets returns the user's device tokens with the app language
// each one registered (PUSH-L10N; empty for legacy apps).
func (f *HTTPDeviceTokenFetcher) GetUserPushTargets(ctx context.Context, userID string) ([]PushTarget, error) {
	url := fmt.Sprintf("%s/auth/user?id=%s", f.authServiceURL, userID)
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("X-Internal-Token", f.internalServiceToken)

	resp, err := f.resilienceClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("auth-service returned status %d", resp.StatusCode)
	}

	var user struct {
		DeviceTokens []struct {
			Token  string `json:"token"`
			Locale string `json:"locale"`
		} `json:"device_tokens"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&user); err != nil {
		return nil, err
	}

	targets := make([]PushTarget, 0, len(user.DeviceTokens))
	for _, dt := range user.DeviceTokens {
		if strings.TrimSpace(dt.Token) != "" {
			targets = append(targets, PushTarget{Token: dt.Token, Locale: dt.Locale})
		}
	}
	return targets, nil
}

// UnregisterStaleToken asks auth-service to drop a stale push device token.
//
// The internal endpoint removes the token from every user that still holds
// it, so the notification-service does not need to know the owning account
// (the userID is kept for the interface and for logging only). A non-2xx
// answer is an error: the old code ignored the status code, so a rejected
// cleanup looked like a successful one and the stale token was pushed to
// again on every following notification.
//
// POST /auth/internal/device-token/unregister
func (f *HTTPDeviceTokenFetcher) UnregisterStaleToken(ctx context.Context, userID, token string) error {
	url := fmt.Sprintf("%s/auth/internal/device-token/unregister", f.authServiceURL)
	body, err := json.Marshal(map[string]string{"token": token})
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Internal-Token", f.internalServiceToken)

	resp, err := f.resilienceClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode < http.StatusOK || resp.StatusCode >= http.StatusMultipleChoices {
		return fmt.Errorf("auth-service device-token unregister returned status %d", resp.StatusCode)
	}
	return nil
}
