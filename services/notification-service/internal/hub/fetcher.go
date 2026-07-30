package hub

import (
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
			Token string `json:"token"`
		} `json:"device_tokens"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&user); err != nil {
		return nil, err
	}

	tokens := make([]string, 0, len(user.DeviceTokens))
	for _, dt := range user.DeviceTokens {
		if strings.TrimSpace(dt.Token) != "" {
			tokens = append(tokens, dt.Token)
		}
	}
	return tokens, nil
}

func (f *HTTPDeviceTokenFetcher) UnregisterStaleToken(ctx context.Context, userID, token string) error {
	url := fmt.Sprintf("%s/auth/device-token", f.authServiceURL)
	body := strings.NewReader(fmt.Sprintf(`{"token":%q,"action":"unregister"}`, token))
	req, err := http.NewRequestWithContext(ctx, "POST", url, body)
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
	return nil
}
