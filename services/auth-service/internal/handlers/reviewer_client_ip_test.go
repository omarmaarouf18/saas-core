package handlers

import (
	"net/http/httptest"
	"testing"
)

// TestGetReviewerClientIP_TrustsOnlyConsoleHeaderAfterInternalToken pins
// the ADMIN-API-FIX rule for the reviewer rate-limit key: X-Forwarded-For
// and X-Real-IP are never trusted (any hop can append to them, so rotating
// them reset the per-IP limit); the dedicated X-Console-Client-IP header is
// trusted only when the request carries the valid internal token, and only
// when it parses as an IP. Everything else keys on RemoteAddr.
func TestGetReviewerClientIP_TrustsOnlyConsoleHeaderAfterInternalToken(t *testing.T) {
	a := &Auth{internalServiceToken: "internal-tok", gatewaySecret: "gw-secret"}

	cases := []struct {
		name     string
		internal string
		headers  map[string]string
		want     string
	}{
		{"rotating XFF with internal token keys on RemoteAddr", "internal-tok",
			map[string]string{"X-Forwarded-For": "198.51.100.7"}, "172.20.0.9"},
		{"X-Real-IP with internal token keys on RemoteAddr", "internal-tok",
			map[string]string{"X-Real-IP": "198.51.100.8"}, "172.20.0.9"},
		{"XFF with gateway secret keys on RemoteAddr", "internal-tok",
			map[string]string{"X-Gateway-Secret": "gw-secret", "X-Forwarded-For": "198.51.100.9"}, "172.20.0.9"},
		{"console header with internal token is trusted", "internal-tok",
			map[string]string{"X-Console-Client-IP": "203.0.113.10", "X-Forwarded-For": "198.51.100.7"}, "203.0.113.10"},
		{"console header without internal token is ignored", "wrong",
			map[string]string{"X-Console-Client-IP": "203.0.113.10"}, "172.20.0.9"},
		{"console header that is not an IP is ignored", "internal-tok",
			map[string]string{"X-Console-Client-IP": "tok_prefix:abc"}, "172.20.0.9"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest("GET", "/auth/reviewer/verify", nil)
			req.RemoteAddr = "172.20.0.9:50000"
			req.Header.Set("X-Internal-Token", tc.internal)
			for k, v := range tc.headers {
				req.Header.Set(k, v)
			}
			if got := a.getReviewerClientIP(req); got != tc.want {
				t.Fatalf("getReviewerClientIP = %q, want %q", got, tc.want)
			}
		})
	}
}
