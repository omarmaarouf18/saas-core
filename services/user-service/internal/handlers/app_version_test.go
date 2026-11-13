package handlers

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestAppVersion_ParsingTable(t *testing.T) {
	cases := []struct {
		input string
		want  bool
	}{
		{"2.1.0", true},
		{"v2.1.0", true},
		{"2.1.0+7", true},
		{"2.0.9", false},
		{"10.0.0", true},
		{"2.1", false},
		{"garbage", false},
		{"", false},
		// Additional edge cases
		{"  2.1.0  ", true},
		{"2.1.0-beta.1", true},
		{"2.1.1", true},
		{"2.0.0", false},
		{"v1.9.9", false},
		{"1.0.0+42", false},
		{"-2.1.0", false},
		{"2.1.0.0", false},
	}

	for _, tc := range cases {
		t.Run(tc.input, func(t *testing.T) {
			got := isAppVersionAtLeast(tc.input, 2, 1, 0)
			if got != tc.want {
				t.Errorf("isAppVersionAtLeast(%q, 2, 1, 0) = %v, want %v", tc.input, got, tc.want)
			}

			req := httptest.NewRequest(http.MethodPost, "/users/jobs/track", nil)
			if tc.input != "" {
				req.Header.Set("X-App-Version", tc.input)
			}
			gotReq := isAtLeastAppVersion210(req)
			if gotReq != tc.want {
				t.Errorf("isAtLeastAppVersion210(header=%q) = %v, want %v", tc.input, gotReq, tc.want)
			}
		})
	}
}

func TestAppVersion_NilRequest(t *testing.T) {
	if isAtLeastAppVersion210(nil) {
		t.Errorf("isAtLeastAppVersion210(nil) want false")
	}
	if isLegacyAppBuild(nil) {
		t.Errorf("isLegacyAppBuild(nil) want false")
	}
}

func TestIsLegacyAppBuild(t *testing.T) {
	cases := []struct {
		input string
		want  bool
	}{
		{"1", true},
		{"1.9", true},
		{"v1", true},
		{"1.9.3+4", true},
		{"2", false},
		{"2.0.0", false},
		{"", false},
		{"garbage", false},
	}

	for _, tc := range cases {
		t.Run("header="+tc.input, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodPut, "/users/services", nil)
			if tc.input != "" {
				req.Header.Set("X-App-Version", tc.input)
			}
			got := isLegacyAppBuild(req)
			if got != tc.want {
				t.Errorf("isLegacyAppBuild(header=%q) = %v, want %v", tc.input, got, tc.want)
			}
		})
	}
}
