package middleware

import (
	"context"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/project/gateway/internal/version"
)

// VersionGate is a middleware that enforces app minimum supported version policies on incoming client requests.
func VersionGate(vStore *version.Store) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			path := r.URL.Path

			// Bypass version gate for health checks, admin endpoints, and exact root
			if path == "/health" || path == "/health/internal" || path == "/" || strings.HasPrefix(path, "/api/v1/admin/version-config") {
				next.ServeHTTP(w, r)
				return
			}

			ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
			defer cancel()

			vConfig, err := vStore.GetConfig(ctx)
			if err != nil {
				// On store error, allow traffic through to avoid blocking production on db failures
				next.ServeHTTP(w, r)
				return
			}

			clientVerStr := r.Header.Get("X-App-Version")

			// Rollout Policy for Missing Header:
			// If X-App-Version is missing and enforce_minimum_version is false, allow request through during rollout grace period.
			if clientVerStr == "" {
				if !vConfig.EnforceMinimumVersion {
					next.ServeHTTP(w, r)
					return
				}
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusUpgradeRequired) // HTTP 426
				// #nosec G705 //nolint:gosec -- raw JSON response does not contain user-provided HTML
				fmt.Fprintf(w, `{"error":"app_update_required","message":"X-App-Version header is required","minimum_version":%q,"latest_version":%q,"download_url":%q}`,
					vConfig.MinimumSupportedVersion, vConfig.LatestVersion, vConfig.DownloadURL)
				return
			}

			clientVer, err := version.ParseSemVer(clientVerStr)
			if err != nil {
				// If header present but unparseable, reject if enforcing
				if vConfig.EnforceMinimumVersion {
					w.Header().Set("Content-Type", "application/json")
					w.WriteHeader(http.StatusUpgradeRequired) // HTTP 426
					// #nosec G705 //nolint:gosec -- raw JSON response does not contain user-provided HTML
					fmt.Fprintf(w, `{"error":"app_update_required","message":"Invalid X-App-Version header format","minimum_version":%q,"latest_version":%q,"current_version":%q,"download_url":%q}`,
						vConfig.MinimumSupportedVersion, vConfig.LatestVersion, clientVerStr, vConfig.DownloadURL)
					return
				}
				next.ServeHTTP(w, r)
				return
			}

			minVer, err := version.ParseSemVer(vConfig.MinimumSupportedVersion)
			if err != nil {
				next.ServeHTTP(w, r)
				return
			}

			// If client version is below minimum supported version AND enforcement is enabled
			if clientVer.LessThan(minVer) && vConfig.EnforceMinimumVersion {
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusUpgradeRequired) // HTTP 426
				// #nosec G705 //nolint:gosec -- raw JSON response does not contain user-provided HTML
				fmt.Fprintf(w, `{"error":"app_update_required","message":"A required app update is available. Please update to continue using Quick Delivery.","minimum_version":%q,"latest_version":%q,"current_version":%q,"download_url":%q}`,
					vConfig.MinimumSupportedVersion, vConfig.LatestVersion, clientVerStr, vConfig.DownloadURL)
				return
			}

			next.ServeHTTP(w, r)
		})
	}
}
