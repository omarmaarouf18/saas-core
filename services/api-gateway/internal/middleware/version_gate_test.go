package middleware

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/project/gateway/internal/version"
)

func TestVersionGate(t *testing.T) {
	vStore := version.NewStore(nil, "")
	ctx := context.Background()

	// Initial default config: min 1.0.0, enforce false
	vGate := VersionGate(vStore)
	nextHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("OK"))
	})
	handler := vGate(nextHandler)

	// 1. Missing header when enforce is false -> 200 OK (Grace period rollout)
	req1 := httptest.NewRequest("GET", "/api/v1/users/profile", nil)
	rr1 := httptest.NewRecorder()
	handler.ServeHTTP(rr1, req1)
	if rr1.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK for missing header during grace period, got %d", rr1.Code)
	}

	// Enable enforcement and set minimum version to 1.1.0
	_, err := vStore.UpdateConfig(ctx, version.PlatformVersions{
		LatestVersion:           "1.2.0",
		MinimumSupportedVersion: "1.1.0",
		EnforceMinimumVersion:   true,
		DownloadURL:             "https://example.com/app.apk",
	})
	if err != nil {
		t.Fatalf("Failed to update config: %v", err)
	}

	// 2. Missing header when enforce is true -> 426 Upgrade Required
	req2 := httptest.NewRequest("GET", "/api/v1/users/profile", nil)
	rr2 := httptest.NewRecorder()
	handler.ServeHTTP(rr2, req2)
	if rr2.Code != http.StatusUpgradeRequired {
		t.Fatalf("Expected 426 Upgrade Required for missing header when enforcing, got %d", rr2.Code)
	}

	// 3. Client version 1.0.0 (below 1.1.0) -> 426 Upgrade Required
	req3 := httptest.NewRequest("GET", "/api/v1/users/profile", nil)
	req3.Header.Set("X-App-Version", "1.0.0")
	rr3 := httptest.NewRecorder()
	handler.ServeHTTP(rr3, req3)
	if rr3.Code != http.StatusUpgradeRequired {
		t.Fatalf("Expected 426 Upgrade Required for client 1.0.0 (min 1.1.0), got %d", rr3.Code)
	}
	if !strings.Contains(rr3.Body.String(), "app_update_required") {
		t.Errorf("Expected body to contain app_update_required error, got %s", rr3.Body.String())
	}

	// 4. Client version 1.1.0 (equals min 1.1.0) -> 200 OK
	req4 := httptest.NewRequest("GET", "/api/v1/users/profile", nil)
	req4.Header.Set("X-App-Version", "1.1.0")
	rr4 := httptest.NewRecorder()
	handler.ServeHTTP(rr4, req4)
	if rr4.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK for client 1.1.0, got %d", rr4.Code)
	}

	// 5. Client version 1.2.0 (greater than min 1.1.0) -> 200 OK
	req5 := httptest.NewRequest("GET", "/api/v1/users/profile", nil)
	req5.Header.Set("X-App-Version", "1.2.0+42")
	rr5 := httptest.NewRecorder()
	handler.ServeHTTP(rr5, req5)
	if rr5.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK for client 1.2.0+42, got %d", rr5.Code)
	}

	// 6. Bypass paths (/health) -> 200 OK even without header
	reqHealth := httptest.NewRequest("GET", "/health", nil)
	rrHealth := httptest.NewRecorder()
	handler.ServeHTTP(rrHealth, reqHealth)
	if rrHealth.Code != http.StatusOK {
		t.Fatalf("Expected 200 OK for bypass path /health, got %d", rrHealth.Code)
	}
}
