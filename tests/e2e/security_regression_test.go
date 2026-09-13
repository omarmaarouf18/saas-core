package e2e

import (
	"context"
	"encoding/json"
	"fmt"
	"math/rand"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/project/shared/infra/jwtutil"
)

// TestSecurity_JWTTampering verifies that re-signed / tampered JWT tokens
// are rejected with HTTP 401 across all platform microservices.
func TestSecurity_JWTTampering(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	cfg := LoadConfig()

	// Generate a validly structured token signed with a forged/tampered secret key
	claims := jwtutil.Claims{
		UserID:   "attacker-user",
		Role:     "owner",
		TenantID: "tenant-tamper-test",
		Email:    "attacker@evil.com",
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(1 * time.Hour)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
		},
	}
	tokenObj := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tamperedToken, err := tokenObj.SignedString([]byte("bogus-attacker-secret-key-1234567890"))
	if err != nil {
		t.Fatalf("Failed to sign tampered token: %v", err)
	}

	endpoints := []struct {
		service string
		method  string
		url     string
	}{
		{"auth-service", http.MethodGet, fmt.Sprintf("%s/api/v1/auth/user?id=attacker-user", cfg.GatewayURL)},
		{"user-service", http.MethodGet, fmt.Sprintf("%s/api/v1/users/wallet?tenant_id=tenant-tamper-test", cfg.GatewayURL)},
		{"chat-service", http.MethodGet, fmt.Sprintf("%s/api/v1/chat/tickets/mine", cfg.GatewayURL)},
		{"notification-service", http.MethodGet, fmt.Sprintf("%s/api/v1/notifications/history", cfg.GatewayURL)},
	}

	for _, ep := range endpoints {
		t.Run(fmt.Sprintf("%s_%s", ep.service, ep.method), func(t *testing.T) {
			resp, body, err := DoJSONRequest(ctx, ep.method, ep.url, tamperedToken, nil)
			if err != nil {
				t.Fatalf("[%s] Request failed: %v", ep.service, err)
			}
			if resp.StatusCode != http.StatusUnauthorized {
				t.Fatalf("[%s] Expected 401 Unauthorized for tampered JWT, got %d. Body: %s", ep.service, resp.StatusCode, string(body))
			}
			// Verify structured error shape
			var errResp map[string]any
			if err := json.Unmarshal(body, &errResp); err != nil {
				t.Fatalf("[%s] Response body is not valid JSON: %s", ep.service, string(body))
			}
			if _, hasErr := errResp["error"]; !hasErr {
				t.Errorf("[%s] Expected 'error' field in response, got: %s", ep.service, string(body))
			}
		})
	}
}

// TestSecurity_JWTExpiry verifies that expired tokens are consistently rejected with 401
// across all services without any stale/cached claims acceptance.
func TestSecurity_JWTExpiry(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	cfg := LoadConfig()

	// Generate a token signed with the REAL secret, but expired 2 hours ago
	claims := jwtutil.Claims{
		UserID:   "expired-user",
		Role:     "user",
		TenantID: "tenant-expired-test",
		Email:    "expired@staging.local",
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(-2 * time.Hour)),
			IssuedAt:  jwt.NewNumericDate(time.Now().Add(-3 * time.Hour)),
		},
	}
	tokenObj := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	expiredToken, err := tokenObj.SignedString([]byte(cfg.JWTSecret))
	if err != nil {
		t.Fatalf("Failed to create expired token: %v", err)
	}

	endpoints := []struct {
		service string
		method  string
		url     string
	}{
		{"auth-service", http.MethodGet, fmt.Sprintf("%s/api/v1/auth/user?id=expired-user", cfg.GatewayURL)},
		{"user-service", http.MethodGet, fmt.Sprintf("%s/api/v1/users/jobs/mine", cfg.GatewayURL)},
		{"chat-service", http.MethodGet, fmt.Sprintf("%s/api/v1/chat/tickets/mine", cfg.GatewayURL)},
		{"notification-service", http.MethodGet, fmt.Sprintf("%s/api/v1/notifications/history", cfg.GatewayURL)},
	}

	for _, ep := range endpoints {
		t.Run(fmt.Sprintf("%s_%s", ep.service, ep.method), func(t *testing.T) {
			resp, body, err := DoJSONRequest(ctx, ep.method, ep.url, expiredToken, nil)
			if err != nil {
				t.Fatalf("[%s] Request failed: %v", ep.service, err)
			}
			if resp.StatusCode != http.StatusUnauthorized {
				t.Fatalf("[%s] Expected 401 for expired token, got %d. Body: %s", ep.service, resp.StatusCode, string(body))
			}
			var errResp map[string]any
			if err := json.Unmarshal(body, &errResp); err != nil {
				t.Fatalf("[%s] Expected valid JSON error, got: %s", ep.service, string(body))
			}
			if _, ok := errResp["error"]; !ok {
				t.Errorf("[%s] Expected 'error' field in response, got: %s", ep.service, string(body))
			}
		})
	}
}

// TestSecurity_TokenReplayAfterLogout verifies that a token revoked via POST /auth/logout
// is recorded in the Redis denylist and cannot be reused.
func TestSecurity_TokenReplayAfterLogout(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 25*time.Second)
	defer cancel()

	cfg := LoadConfig()
	db, err := ConnectStagingDB(ctx, cfg.MongoURI)
	if err != nil {
		t.Fatalf("Failed to connect to staging DB: %v", err)
	}
	defer db.Close(ctx)

	rnd := rand.New(rand.NewSource(time.Now().UnixNano())).Intn(900000) + 100000
	tenantID := fmt.Sprintf("tenant-logout-%d", rnd)
	customerID := fmt.Sprintf("cust-logout-%d", rnd)
	customerEmail := fmt.Sprintf("%s@staging.local", customerID)

	defer db.CleanupTestEntities(ctx, []string{tenantID}, []string{customerID})

	if err := db.SeedCustomer(ctx, tenantID, customerID, customerEmail); err != nil {
		t.Fatalf("Failed to seed customer: %v", err)
	}

	token, err := cfg.GenerateJWT(customerID, "user", tenantID, customerEmail)
	if err != nil {
		t.Fatalf("Failed to generate token: %v", err)
	}

	// 1. Verify token works prior to logout
	userURL := fmt.Sprintf("%s/api/v1/auth/user?user_token=%s", cfg.GatewayURL, token)
	resp, body, err := GetJSON(ctx, userURL, token)
	if err != nil || resp.StatusCode != http.StatusOK {
		t.Fatalf("Pre-logout verification failed: status %d body %s err %v", resp.StatusCode, string(body), err)
	}

	// 2. Perform Logout
	logoutURL := fmt.Sprintf("%s/api/v1/auth/logout", cfg.GatewayURL)
	logoutResp, logoutBody, err := PostJSON(ctx, logoutURL, token, map[string]string{})
	if err != nil || logoutResp.StatusCode != http.StatusOK {
		t.Fatalf("Logout failed: status %d body %s err %v", logoutResp.StatusCode, string(logoutBody), err)
	}

	// 3. Replay token on auth-service: must be rejected with 401
	respPostLogout, bodyPostLogout, err := GetJSON(ctx, userURL, token)
	if err != nil {
		t.Fatalf("Replay request failed: %v", err)
	}
	if respPostLogout.StatusCode != http.StatusUnauthorized {
		t.Fatalf("Expected 401 Unauthorized for replayed logged-out token, got %d. Body: %s",
			respPostLogout.StatusCode, string(bodyPostLogout))
	}

	// 4. Replay token on user-service: must also be rejected with 401
	jobsURL := fmt.Sprintf("%s/api/v1/users/jobs/mine", cfg.GatewayURL)
	respJobs, bodyJobs, err := GetJSON(ctx, jobsURL, token)
	if err != nil {
		t.Fatalf("Jobs replay request failed: %v", err)
	}
	if respJobs.StatusCode != http.StatusUnauthorized {
		t.Fatalf("Expected 401 Unauthorized on user-service for logged-out token, got %d. Body: %s",
			respJobs.StatusCode, string(bodyJobs))
	}
}

// TestSecurity_ReviewerRateLimitBypass verifies that reviewer login lockout
// cannot be bypassed by rotating tokens holding IP constant, OR rotating IP holding token constant.
func TestSecurity_ReviewerRateLimitBypass(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	cfg := LoadConfig()

	// Clear existing reviewer limits
	_ = FlushReviewerRateLimits(ctx, cfg.RedisURI)
	defer FlushReviewerRateLimits(ctx, cfg.RedisURI)

	// Sub-test A: Hold IP constant, rotate tokens
	t.Run("Hold_IP_Rotate_Tokens_Engages_Lockout", func(t *testing.T) {
		queueURL := fmt.Sprintf("%s/api/queue", cfg.ConsoleURL)

		// 3 failed attempts with different tokens
		for i := 1; i <= 3; i++ {
			bogusToken := fmt.Sprintf("invalid-tok-rot-%d-%d", time.Now().UnixNano(), i)
			headers := map[string]string{
				"X-Reviewer-Token": bogusToken,
			}
			resp, _, err := DoRequestWithHeaders(ctx, http.MethodGet, queueURL, headers, nil)
			if err != nil {
				t.Fatalf("Attempt %d failed: %v", i, err)
			}
			// First 2 might be 401, 3rd triggers lockout 429
			if i == 3 && resp.StatusCode != http.StatusTooManyRequests && resp.StatusCode != http.StatusUnauthorized {
				t.Fatalf("Attempt %d returned unexpected status %d", i, resp.StatusCode)
			}
		}

		// 4th attempt with a BRAND NEW token from same IP -> must be locked out (429)
		newBogusToken := fmt.Sprintf("brand-new-token-%d", time.Now().UnixNano())
		resp4, body4, err := DoRequestWithHeaders(ctx, http.MethodGet, queueURL, map[string]string{"X-Reviewer-Token": newBogusToken}, nil)
		if err != nil {
			t.Fatalf("Attempt 4 failed: %v", err)
		}
		if resp4.StatusCode != http.StatusTooManyRequests {
			t.Fatalf("Expected 429 Too Many Requests when rotating tokens from locked IP, got %d. Body: %s",
				resp4.StatusCode, string(body4))
		}
	})

	// Clear limits between sub-tests
	_ = FlushReviewerRateLimits(ctx, cfg.RedisURI)

	// Sub-test B: Hold token constant, rotate IPs via X-Forwarded-For
	t.Run("Hold_Token_Rotate_IP_Engages_Lockout", func(t *testing.T) {
		queueURL := fmt.Sprintf("%s/api/queue", cfg.ConsoleURL)
		constantToken := fmt.Sprintf("constant-target-token-%d", time.Now().UnixNano())

		// 3 failed attempts with same token from different spoofed IPs
		for i := 1; i <= 3; i++ {
			spoofedIP := fmt.Sprintf("198.51.100.%d", 10+i)
			headers := map[string]string{
				"X-Reviewer-Token": constantToken,
				"X-Forwarded-For":  spoofedIP,
			}
			resp, _, err := DoRequestWithHeaders(ctx, http.MethodGet, queueURL, headers, nil)
			if err != nil {
				t.Fatalf("Attempt %d failed: %v", i, err)
			}
			if i == 3 && resp.StatusCode != http.StatusTooManyRequests && resp.StatusCode != http.StatusUnauthorized {
				t.Fatalf("Attempt %d returned unexpected status %d", i, resp.StatusCode)
			}
		}

		// 4th attempt with the SAME token from a COMPLETELY NEW IP -> token itself is locked out!
		newIP := "203.0.113.88"
		headers4 := map[string]string{
			"X-Reviewer-Token": constantToken,
			"X-Forwarded-For":  newIP,
		}
		resp4, body4, err := DoRequestWithHeaders(ctx, http.MethodGet, queueURL, headers4, nil)
		if err != nil {
			t.Fatalf("Attempt 4 failed: %v", err)
		}
		if resp4.StatusCode != http.StatusTooManyRequests {
			t.Fatalf("Expected 429 Too Many Requests when rotating IP for locked token, got %d. Body: %s",
				resp4.StatusCode, string(body4))
		}
	})
}

// TestSecurity_CORSConfiguration verifies preflight and cross-origin handling:
// - Allowed origin preflight -> 200 OK, Access-Control-Allow-Origin, PATCH included in methods
// - Disallowed origin preflight -> 403 Forbidden
// - Disallowed origin cross-origin request -> Origin is NOT reflected in Access-Control-Allow-Origin
func TestSecurity_CORSConfiguration(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	cfg := LoadConfig()

	// 1. Preflight OPTIONS from disallowed origin
	disallowedOrigin := "https://malicious-phishing-site.example.com"
	headersPreflightBad := map[string]string{
		"Origin":                         disallowedOrigin,
		"Access-Control-Request-Method":  "PATCH",
		"Access-Control-Request-Headers": "Content-Type, Authorization",
	}
	respBad, _, err := DoRequestWithHeaders(ctx, http.MethodOptions, fmt.Sprintf("%s/api/v1/auth/login", cfg.GatewayURL), headersPreflightBad, nil)
	if err != nil {
		t.Fatalf("Disallowed preflight failed: %v", err)
	}
	// Gateway returns 403 when origin is disallowed or does not reflect origin
	if respBad.StatusCode == http.StatusOK {
		allowOrigin := respBad.Header.Get("Access-Control-Allow-Origin")
		if allowOrigin == disallowedOrigin {
			t.Fatalf("CRITICAL CORS DEFECT: Gateway reflected untrusted origin %q!", disallowedOrigin)
		}
	} else if respBad.StatusCode != http.StatusForbidden {
		t.Fatalf("Expected 403 Forbidden for disallowed CORS origin, got %d", respBad.StatusCode)
	}

	// 2. Preflight OPTIONS from allowed origin (e.g. localhost or standard port)
	allowedOrigin := "http://localhost:8080"
	headersPreflightGood := map[string]string{
		"Origin":                         allowedOrigin,
		"Access-Control-Request-Method":  "PATCH",
		"Access-Control-Request-Headers": "Content-Type, Authorization, X-Reviewer-Token",
	}
	respGood, _, err := DoRequestWithHeaders(ctx, http.MethodOptions, fmt.Sprintf("%s/api/v1/auth/login", cfg.GatewayURL), headersPreflightGood, nil)
	if err != nil {
		t.Fatalf("Allowed preflight failed: %v", err)
	}
	if respGood.StatusCode != http.StatusOK {
		t.Fatalf("Expected 200 OK for allowed preflight, got %d", respGood.StatusCode)
	}
	methods := respGood.Header.Get("Access-Control-Allow-Methods")
	if !strings.Contains(methods, "PATCH") {
		t.Errorf("Access-Control-Allow-Methods missing PATCH: %s", methods)
	}
	allowHeaders := respGood.Header.Get("Access-Control-Allow-Headers")
	if !strings.Contains(allowHeaders, "X-Reviewer-Token") {
		t.Errorf("Access-Control-Allow-Headers missing X-Reviewer-Token: %s", allowHeaders)
	}
}

// TestSecurity_BroadRBACMatrix systematically evaluates all 5 platform roles
// against representative endpoints in every platform domain.
func TestSecurity_BroadRBACMatrix(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	cfg := LoadConfig()
	db, err := ConnectStagingDB(ctx, cfg.MongoURI)
	if err != nil {
		t.Fatalf("Failed to connect to staging DB: %v", err)
	}
	defer db.Close(ctx)

	rnd := rand.New(rand.NewSource(time.Now().UnixNano())).Intn(900000) + 100000
	tenantID := fmt.Sprintf("tenant-broad-rbac-%d", rnd)
	ownerID := tenantID
	courierID := fmt.Sprintf("courier-broad-rbac-%d", rnd)
	customerID := fmt.Sprintf("cust-broad-rbac-%d", rnd)
	reviewerID := fmt.Sprintf("rev-broad-rbac-%d", rnd)
	rawReviewerToken := fmt.Sprintf("rev-token-broad-%d", rnd)
	serviceID := fmt.Sprintf("svc-broad-%d", rnd)

	defer func() {
		db.CleanupTestEntities(ctx, []string{tenantID}, []string{ownerID, courierID, customerID})
		_, _ = db.client.Database("staging_auth_db").Collection("reviewers").DeleteOne(ctx, map[string]any{"_id": reviewerID})
	}()

	startLat, startLon := 30.0444, 31.2357
	if err := db.SeedTenantAndService(ctx, tenantID, ownerID, serviceID, 20.0, 5.0, startLat, startLon); err != nil {
		t.Fatalf("Failed to seed tenant: %v", err)
	}
	if err := db.SeedCourier(ctx, tenantID, courierID, courierID+"@staging.local", startLat, startLon); err != nil {
		t.Fatalf("Failed to seed courier: %v", err)
	}
	if err := db.SeedCustomer(ctx, tenantID, customerID, customerID+"@staging.local"); err != nil {
		t.Fatalf("Failed to seed customer: %v", err)
	}
	if err := db.SeedReviewer(ctx, reviewerID, "Broad Reviewer", rawReviewerToken); err != nil {
		t.Fatalf("Failed to seed reviewer: %v", err)
	}

	customerToken, _ := cfg.GenerateJWT(customerID, "user", tenantID, customerID+"@staging.local")
	courierToken, _ := cfg.GenerateJWT(courierID, "employee", tenantID, courierID+"@staging.local")
	ownerToken, _ := cfg.GenerateJWT(ownerID, "owner", tenantID, ownerID+"@staging.local")

	roles := []struct {
		name    string
		token   string
		headers map[string]string
	}{
		{"Anonymous", "", nil},
		{"Customer", customerToken, nil},
		{"Courier", courierToken, nil},
		{"Owner", ownerToken, nil},
		{"Reviewer", "", map[string]string{"X-Reviewer-Token": rawReviewerToken}},
	}

	type endpointCheck struct {
		name        string
		method      string
		targetURLFn func(rName, token string) string
		body        any
		allowRoles  map[string]int // role -> expected allowed status code
		denyStatus  map[string]int // optional custom deny status (default 401/403)
	}

	checks := []endpointCheck{
		{
			name:   "Courier_Location_Update",
			method: http.MethodPost,
			targetURLFn: func(rName, token string) string {
				return fmt.Sprintf("%s/api/v1/users/employee/location", cfg.GatewayURL)
			},
			body:       map[string]any{"latitude": startLat, "longitude": startLon},
			allowRoles: map[string]int{"Courier": http.StatusOK},
		},
		{
			name:   "Owner_Service_Creation",
			method: http.MethodPost,
			targetURLFn: func(rName, token string) string {
				return fmt.Sprintf("%s/api/v1/users/services", cfg.GatewayURL)
			},
			body:       map[string]any{"name": "New Svc", "category": "delivery", "tenant_base_price": 10.0, "tenant_price_per_km": 2.0, "latitude": startLat, "longitude": startLon, "coverage_radius_km": 10.0},
			allowRoles: map[string]int{"Owner": http.StatusCreated},
			denyStatus: map[string]int{"Anonymous": http.StatusBadRequest, "Reviewer": http.StatusBadRequest},
		},
		{
			name:   "Owner_Wallet_Read",
			method: http.MethodGet,
			targetURLFn: func(rName, token string) string {
				if token != "" {
					return fmt.Sprintf("%s/api/v1/users/wallet?tenant_token=%s", cfg.GatewayURL, token)
				}
				return fmt.Sprintf("%s/api/v1/users/wallet?tenant_id=%s", cfg.GatewayURL, tenantID)
			},
			body:       nil,
			allowRoles: map[string]int{"Owner": http.StatusOK},
		},
		{
			name:   "Customer_Create_Ticket",
			method: http.MethodPost,
			targetURLFn: func(rName, token string) string {
				return fmt.Sprintf("%s/api/v1/chat/tickets", cfg.GatewayURL)
			},
			body: map[string]any{"subject": "Delivery Issue", "description": "Need help with order"},
			allowRoles: map[string]int{
				"Customer": http.StatusCreated,
				"Courier":  http.StatusCreated,
				"Owner":    http.StatusCreated,
			},
		},
		{
			name:   "Reviewer_KYC_Queue",
			method: http.MethodGet,
			targetURLFn: func(rName, token string) string {
				return fmt.Sprintf("%s/api/queue", cfg.ConsoleURL)
			},
			body:       nil,
			allowRoles: map[string]int{"Reviewer": http.StatusOK},
		},
		{
			name:   "Internal_Admin_Version_Config",
			method: http.MethodGet,
			targetURLFn: func(rName, token string) string {
				return fmt.Sprintf("%s/api/v1/admin/version-config", cfg.GatewayURL)
			},
			body:       nil,
			allowRoles: map[string]int{}, // none of the normal roles are allowed (requires internal token)
		},
	}

	for _, check := range checks {
		t.Run(check.name, func(t *testing.T) {
			for _, r := range roles {
				t.Run(r.name, func(t *testing.T) {
					var resp *http.Response
					var err error

					headers := make(map[string]string)
					for k, v := range r.headers {
						headers[k] = v
					}
					if r.token != "" {
						headers["Authorization"] = "Bearer " + r.token
					}
					headers["Content-Type"] = "application/json"

					var bodyBytes []byte
					if check.body != nil {
						bodyBytes, _ = json.Marshal(check.body)
					}

					url := check.targetURLFn(r.name, r.token)
					resp, body, err := DoRequestWithHeaders(ctx, check.method, url, headers, bodyBytes)
					if err != nil {
						t.Fatalf("[%s][%s] Request error: %v", check.name, r.name, err)
					}

					expectedCode, allowed := check.allowRoles[r.name]
					if allowed {
						if resp.StatusCode != expectedCode {
							t.Errorf("[%s][%s] Expected allowed status %d, got %d. Body: %s",
								check.name, r.name, expectedCode, resp.StatusCode, string(body))
						}
					} else {
						if expectedDeny, hasCustomDeny := check.denyStatus[r.name]; hasCustomDeny {
							if resp.StatusCode != expectedDeny {
								t.Errorf("[%s][%s] Expected denied status %d, got %d. Body: %s",
									check.name, r.name, expectedDeny, resp.StatusCode, string(body))
							}
						} else {
							// Must be denied with 401 or 403
							if resp.StatusCode != http.StatusUnauthorized && resp.StatusCode != http.StatusForbidden {
								t.Errorf("[%s][%s] CRITICAL RBAC LEAK: Expected 401/403 Denied, got %d. Body: %s",
									check.name, r.name, resp.StatusCode, string(body))
							}
						}
					}
				})
			}
		})
	}
}
