// API Gateway — Reverse proxy entry point.
//
// Routes incoming traffic to backend microservices based on path prefix.
// All target URLs are read from environment variables at startup.
package main

import (
	"context"
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"regexp"
	"strings"
	"syscall"
	"time"

	"go.mongodb.org/mongo-driver/v2/mongo"
	"go.mongodb.org/mongo-driver/v2/mongo/options"

	"github.com/project/gateway/internal/adminaudit"
	"github.com/project/gateway/internal/config"
	"github.com/project/gateway/internal/iputil"
	"github.com/project/gateway/internal/middleware"
	"github.com/project/gateway/internal/proxy"
	"github.com/project/gateway/internal/version"
	"github.com/project/shared/infra/handlerutil"
	"github.com/project/shared/infra/ratelimit"
	"github.com/project/shared/infra/resilience"
	"github.com/project/shared/infra/tlsutil"
)

func main() {
	// --check-env: validate config and exit without starting the server.
	// Used by the CD pipeline pre-flight to verify env vars before deployment.
	if len(os.Args) > 1 && os.Args[1] == "--check-env" {
		_, err := config.Load()
		if err != nil {
			fmt.Fprintf(os.Stderr, "PREFLIGHT FAILED: %v\n", err)
			os.Exit(1)
		}
		fmt.Println("PREFLIGHT OK: api-gateway config validated")
		os.Exit(0)
	}

	// ---- Load configuration from environment ----
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	// ---- Initialize Redis rate limiter client ----
	redisClient, err := ratelimit.NewRedisClient(cfg.RedisURI)
	if err != nil {
		log.Fatalf("Failed to connect to Redis: %v", err)
	}

	var clientTransport http.RoundTripper
	if cfg.TLSCertPath != "" && cfg.TLSKeyPath != "" && cfg.TLSCAPath != "" {
		tlsConfig, err := tlsutil.LoadClientTLSConfig(cfg.TLSCertPath, cfg.TLSKeyPath, cfg.TLSCAPath)
		if err != nil {
			log.Fatalf("Failed to load gateway client TLS config: %v", err)
		}
		clientTransport = &http.Transport{
			TLSClientConfig: tlsConfig,
		}
	} else {
		clientTransport = http.DefaultTransport
	}

	// ---- Initialize App Version Store and admin audit store (MongoDB, gateway_db) ----
	storeCtx, storeCancel := context.WithTimeout(context.Background(), 10*time.Second)
	versionStore, auditStore, err := openGatewayStores(storeCtx, cfg.MongoURI, cfg.MongoDatabase, cfg.AppEnv)
	storeCancel()
	if err != nil {
		log.Fatalf("[GATEWAY] FATAL: refusing to start: version store unavailable (APP_ENV=%q): %v. "+
			"Fix MONGO_URI/MongoDB, or run with APP_ENV=local for the in-memory fallback.", cfg.AppEnv, err)
	}

	mux := http.NewServeMux()

	// ---- Health check endpoint ----
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			handlerutil.WriteJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
			return
		}
		handlerutil.WriteJSON(w, http.StatusOK, map[string]any{
			"status": "ok",
		})
	})

	// ---- Internal Health check endpoint ----
	mux.HandleFunc("/health/internal", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			handlerutil.WriteJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
			return
		}
		gotToken := r.Header.Get("X-Internal-Token")
		// Empty-secret guard (QA audit Q23): never authenticate when unconfigured.
		if cfg.InternalServiceToken == "" || subtle.ConstantTimeCompare([]byte(gotToken), []byte(cfg.InternalServiceToken)) != 1 {
			handlerutil.WriteJSON(w, http.StatusForbidden, map[string]string{"error": "access denied: invalid internal token"})
			return
		}
		handlerutil.WriteJSON(w, http.StatusOK, map[string]any{
			"status":       "ok",
			"dependencies": resilience.GetBreakerStats(),
		})
	})

	// ---- Admin App Version Configuration Endpoint ----
	// SEC-02: guarded by the dedicated ADMIN_API_TOKEN (X-Admin-Token), not
	// the internal service token that every service holds.
	mux.HandleFunc("/api/v1/admin/version-config", VersionConfigHandler(cfg.AdminAPIToken, versionStore))

	// ---- Reviewer App Version Configuration Endpoint (Console X-Internal-Token + X-Reviewer-Token) ----
	authClient := &http.Client{Transport: clientTransport, Timeout: 5 * time.Second}
	reviewerVersionHandler := ReviewerVersionConfigHandler(cfg.InternalServiceToken, cfg.AuthServiceURL, authClient, versionStore, auditStore)
	mux.HandleFunc("/admin/version", reviewerVersionHandler)
	mux.HandleFunc("/api/v1/admin/version", reviewerVersionHandler)
	// Gateway admin audit records for auth-service's merged GET /admin/audit.
	mux.HandleFunc("/admin/internal/audit", adminaudit.ListHandler(cfg.InternalServiceToken, auditStore))

	// ---- Service info endpoint ----
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		// Only match the exact root path; anything else should 404.
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		if r.Method != http.MethodGet {
			handlerutil.WriteJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
			return
		}
		info := map[string]any{
			"service": "api-gateway",
			"version": "0.1.0",
		}
		handlerutil.WriteJSON(w, http.StatusOK, info)
	})

	// ---- Register reverse proxy routes ----
	registerServiceRoutes(mux, cfg.Routes, func(route config.ServiceRoute) (http.Handler, error) {
		resilientTransport := resilience.NewRoundTripper(clientTransport, route.Prefix, 2, 5*time.Second)
		return proxy.New(route, cfg.GatewaySecret, cfg.TrustedProxyIPs, resilientTransport)
	})

	// ---- Wrap with version gate, rate limiting, and logging middleware ----
	// General bucket: 300 req/min per client IP across all REST routes.
	// Sized against measured steady-state single-user load (~40/min) with
	// headroom for multi-device households behind one CGNAT address; the
	// lockout counter resets when a lockout engages (shared/infra), so the
	// worst case is one short pause rather than an escalating spiral.
	rl := ratelimit.NewRateLimiter(redisClient, 300, 1*time.Minute, "gateway")
	limiter := middleware.NewRateLimiter(rl, cfg.TrustedProxyIPs)
	// Isolated SSE bucket: the notifications stream is long-lived but mobile
	// clients reconnect aggressively after network blips or stack redeploys.
	// Without isolation, that connect churn exhausts the shared per-IP budget
	// and locks the client out of every unrelated endpoint (observed live:
	// 438 stream-driven 429s in ~6 minutes after a deploy, cascading into
	// lockouts on auth/user and ratings for the same IP).
	sseRl := ratelimit.NewRateLimiter(redisClient, 100, 1*time.Minute, "gateway-sse")
	sseLimiter := middleware.NewRateLimiter(sseRl, cfg.TrustedProxyIPs)
	versionGated := middleware.VersionGate(versionStore)(mux)
	rateLimited := middleware.RateLimitWithOverrides(limiter, map[string]*middleware.RateLimiter{
		"/api/v1/notifications/stream": sseLimiter,
	})(versionGated)
	maxBounded := handlerutil.MaxBytesMiddleware(1 << 20)(rateLimited)
	logged := middleware.Logging(cfg.AllowedOrigin)(maxBounded)

	// ---- Start server ----
	addr := ":" + cfg.Port
	log.Printf("API Gateway listening on HTTPS %s", addr)
	log.Printf("Routes active: %d", len(cfg.Routes))
	server := &http.Server{
		Addr:    addr,
		Handler: logged,
		// ReadTimeout bounds slow-body slowloris reads (request headers
		// were already capped at 3s). IdleTimeout reaps idle keep-alive
		// connections. WriteTimeout is deliberately unset: SSE streams and
		// proxied long-lived responses must never be truncated by a write
		// deadline.
		ReadHeaderTimeout: 3 * time.Second,
		ReadTimeout:       30 * time.Second,
		IdleTimeout:       120 * time.Second,
	}
	// Graceful shutdown.
	go func() {
		sigCh := make(chan os.Signal, 1)
		signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
		<-sigCh
		log.Println("[GATEWAY] Shutting down...")

		shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer shutdownCancel()

		if err := server.Shutdown(shutdownCtx); err != nil {
			log.Printf("[ERROR] server shutdown error: %v", err)
		}
	}()

	tlsConfig, err := serverTLSConfig(cfg.ExternalTLSCertPath, cfg.ExternalTLSKeyPath, cfg.TLSCertPath, cfg.TLSKeyPath)
	if err != nil {
		log.Fatalf("[GATEWAY] TLS setup failed: %v", err)
	}
	server.TLSConfig = tlsConfig
	if err := server.ListenAndServeTLS("", ""); err != nil && err != http.ErrServerClosed {
		log.Fatalf("Server error: %v", err)
	}
}

// registerServiceRoutes mounts one reverse-proxy handler per service route.
//
// Every route prefix in config ends with a trailing slash (e.g.
// "/api/v1/notifications/"), which Go's http.ServeMux treats as a
// subtree-only registration: a request to the exact bare path
// ("/api/v1/notifications", the natural REST shape for "the collection")
// never reaches the handler and instead gets an automatic 3xx redirect
// to the slashed URL. Method-preserving redirects on non-GET verbs are
// mishandled by some HTTP clients, and the redirect short-circuits the
// proxy entirely, so collection-level calls (e.g. DELETE "clear all")
// break while deeper paths (e.g. DELETE /notifications/{id}) work fine.
// Registering the exact bare-path companion alongside the subtree pattern
// makes both shapes proxy directly with no redirect in between, for every
// HTTP method including OPTIONS and DELETE.
func registerServiceRoutes(mux *http.ServeMux, routes []config.ServiceRoute, buildHandler func(config.ServiceRoute) (http.Handler, error)) {
	for _, route := range routes {
		handler, err := buildHandler(route)
		if err != nil {
			log.Fatalf("Failed to create proxy for %s: %v", route.Prefix, err)
		}
		mux.Handle(route.Prefix, handler)
		log.Printf("Route registered: %s → %s (env: %s)", route.Prefix, route.Target, route.EnvKey)
		if bare := strings.TrimSuffix(route.Prefix, "/"); bare != route.Prefix {
			mux.Handle(bare, handler)
			log.Printf("Route registered: %s → %s (env: %s)", bare, route.Target, route.EnvKey)
		}
	}
}

// VersionConfigHandler handles GET and PUT requests for /api/v1/admin/version-config.
//
// SEC-02: authenticated with the dedicated admin credential (X-Admin-Token),
// NOT the internal service token shared by all services. The internal token
// deliberately does not grant access here.
func VersionConfigHandler(adminToken string, versionStore *version.Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		gotToken := r.Header.Get("X-Admin-Token")
		// Empty-secret guard (QA audit Q23): never authenticate when unconfigured.
		if adminToken == "" || subtle.ConstantTimeCompare([]byte(gotToken), []byte(adminToken)) != 1 {
			handlerutil.WriteJSON(w, http.StatusForbidden, map[string]string{"error": "access denied: invalid admin token"})
			return
		}

		if r.Method == http.MethodGet {
			vConfig, err := versionStore.GetConfig(r.Context())
			if err != nil {
				handlerutil.WriteSafeError(w, r, http.StatusInternalServerError, handlerutil.ErrCodeInternal, "internal server error", err)
				return
			}
			handlerutil.WriteJSON(w, http.StatusOK, vConfig)
			return
		}

		if r.Method == http.MethodPut {
			var req version.PlatformVersions
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				handlerutil.WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON body"})
				return
			}
			updated, err := versionStore.UpdateConfig(r.Context(), req)
			if err != nil {
				if errors.Is(err, version.ErrPersist) {
					handlerutil.WriteSafeError(w, r, http.StatusServiceUnavailable, handlerutil.ErrCodeUnavailable, "version store unavailable, config not saved", err)
					return
				}
				handlerutil.WriteJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
				return
			}
			// SEC-02: audit trail for client version-policy changes.
			handlerutil.ShipSecurityEvent(r.Context(), "VERSION_CONFIG_CHANGED", "api-gateway", "admin", "",
				fmt.Sprintf("latest=%s min=%s enforce=%t revision=%d",
					updated.LatestVersion, updated.MinimumSupportedVersion, updated.EnforceMinimumVersion, updated.Revision),
				handlerutil.GetClientIP(r))
			handlerutil.WriteJSON(w, http.StatusOK, map[string]any{"message": "version configuration updated successfully", "config": updated})
			return
		}

		handlerutil.WriteJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
	}
}

// openGatewayStores opens the version policy and admin audit stores. Without
// MONGO_URI both are in memory. With MONGO_URI set, MongoDB must be reachable
// and the version policy seeded at startup; otherwise the gateway refuses to
// start (returns an error), except with APP_ENV=local or test, where it falls
// back to in memory with a loud warning. ADMIN-API silently fell back in every
// environment, so later version changes were lost on restart.
func openGatewayStores(ctx context.Context, mongoURI, dbName, appEnv string) (*version.Store, *adminaudit.Store, error) {
	if dbName == "" {
		dbName = "gateway_db"
	}
	if mongoURI == "" {
		log.Printf("[GATEWAY] MONGO_URI not set: version policy and admin audit records are in memory and lost on restart")
		return version.NewStore(nil, ""), adminaudit.NewStore(nil, ""), nil
	}
	client, err := mongo.Connect(options.Client().ApplyURI(mongoURI))
	if err == nil {
		err = client.Ping(ctx, nil)
	}
	var vs *version.Store
	if err == nil {
		vs, err = version.NewMongoStore(ctx, client, dbName)
	}
	if err != nil {
		if client != nil {
			_ = client.Disconnect(context.Background())
		}
		env := strings.ToLower(strings.TrimSpace(appEnv))
		if env == "local" || env == "test" {
			log.Printf("[GATEWAY] WARNING: MongoDB version store unavailable (%v); APP_ENV=%s so falling back to IN-MEMORY stores. Version policy changes will be LOST on restart.", err, env)
			return version.NewStore(nil, ""), adminaudit.NewStore(nil, ""), nil
		}
		return nil, nil, err
	}
	log.Printf("[GATEWAY] Version store connected to MongoDB (db=%s, collections=platform_versions, admin_audit)", dbName)
	return vs, adminaudit.NewStore(client, dbName), nil
}

// consoleClientIPHeader carries the reviewer's browser IP on saas-net. The
// console sets it; the gateway trusts it only after the X-Internal-Token
// check has passed and only when it parses as an IP.
const consoleClientIPHeader = "X-Console-Client-IP"

// reviewerClientIP returns the reviewer IP to report to auth-service. Call it
// only after the internal token check: it trusts X-Console-Client-IP, never
// X-Forwarded-For or X-Real-IP, and otherwise uses RemoteAddr.
func reviewerClientIP(r *http.Request) string {
	if ip := strings.TrimSpace(r.Header.Get(consoleClientIPHeader)); ip != "" && net.ParseIP(ip) != nil {
		return ip
	}
	return iputil.ExtractIP(r.RemoteAddr)
}

var auditRequestIDPattern = regexp.MustCompile(`^[A-Za-z0-9._-]{1,64}$`)

// auditRequestID returns the caller's X-Request-ID when it is a safe token,
// else a fresh random id.
func auditRequestID(r *http.Request) string {
	if rid := strings.TrimSpace(r.Header.Get("X-Request-ID")); auditRequestIDPattern.MatchString(rid) {
		return rid
	}
	return newAuditID()
}

func newAuditID() string {
	b := make([]byte, 12)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

// ReviewerVersionUpdateRequest is the payload for updating version config from the reviewer console.
type ReviewerVersionUpdateRequest struct {
	LatestVersion           string `json:"latest_version"`
	MinimumSupportedVersion string `json:"minimum_supported_version"`
	EnforceMinimumVersion   *bool  `json:"enforce_minimum_version,omitempty"`
	DownloadURL             string `json:"download_url"`
	Reason                  string `json:"reason"`
}

// ReviewerVersionConfigHandler handles reviewer console access to read and update version policy (ADR-0023).
// GET /admin/version & PUT /admin/version & POST /admin/version
func ReviewerVersionConfigHandler(internalToken, authServiceURL string, authClient *http.Client, versionStore *version.Store, auditStore *adminaudit.Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		gotInternal := r.Header.Get("X-Internal-Token")
		if internalToken == "" || subtle.ConstantTimeCompare([]byte(gotInternal), []byte(internalToken)) != 1 {
			handlerutil.WriteJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized internal token"})
			return
		}

		revToken := r.Header.Get("X-Reviewer-Token")
		if revToken == "" {
			handlerutil.WriteJSON(w, http.StatusUnauthorized, map[string]string{"error": "missing reviewer token"})
			return
		}

		authBase := authServiceURL
		if authBase == "" {
			authBase = "https://auth-service:3002"
		}
		verifyURL := fmt.Sprintf("%s/auth/reviewer/verify", strings.TrimSuffix(authBase, "/"))
		// #nosec G704 //nolint:gosec -- verifyURL is constructed from trusted internal config
		verifyReq, err := http.NewRequestWithContext(r.Context(), http.MethodGet, verifyURL, nil)
		if err != nil {
			handlerutil.WriteSafeError(w, r, http.StatusInternalServerError, handlerutil.ErrCodeInternal, "failed to create reviewer auth request", err)
			return
		}
		verifyReq.Header.Set("X-Internal-Token", internalToken)
		verifyReq.Header.Set("X-Reviewer-Token", revToken)
		// The reviewer rate limit in auth-service keys on this IP. A client
		// X-Forwarded-For is never forwarded (rotating it reset the limit).
		clientIP := reviewerClientIP(r)
		verifyReq.Header.Set(consoleClientIPHeader, clientIP)

		client := authClient
		if client == nil {
			client = http.DefaultClient
		}
		// #nosec G704 //nolint:gosec -- verifyURL is trusted
		authResp, err := client.Do(verifyReq)
		if err != nil {
			handlerutil.WriteSafeError(w, r, http.StatusBadGateway, handlerutil.ErrCodeUnavailable, "auth-service unavailable", err)
			return
		}
		defer authResp.Body.Close()

		if authResp.StatusCode != http.StatusOK {
			if authResp.StatusCode == http.StatusTooManyRequests {
				if ra := authResp.Header.Get("Retry-After"); ra != "" {
					w.Header().Set("Retry-After", ra)
				}
				handlerutil.WriteJSON(w, http.StatusTooManyRequests, map[string]string{"error": "too many requests"})
				return
			}
			handlerutil.WriteJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid reviewer token"})
			return
		}

		var revIdentity struct {
			ID   string `json:"id"`
			Name string `json:"name"`
		}
		if err := json.NewDecoder(authResp.Body).Decode(&revIdentity); err != nil {
			handlerutil.WriteSafeError(w, r, http.StatusInternalServerError, handlerutil.ErrCodeInternal, "invalid auth response", err)
			return
		}

		if r.Method == http.MethodGet {
			vConfig, err := versionStore.GetConfig(r.Context())
			if err != nil {
				handlerutil.WriteSafeError(w, r, http.StatusInternalServerError, handlerutil.ErrCodeInternal, "internal server error", err)
				return
			}
			handlerutil.WriteJSON(w, http.StatusOK, vConfig)
			return
		}

		if r.Method == http.MethodPut || r.Method == http.MethodPost {
			var req ReviewerVersionUpdateRequest
			if err := json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(&req); err != nil {
				handlerutil.WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON body"})
				return
			}

			reason := strings.TrimSpace(req.Reason)
			if len(reason) < 1 || len(reason) > 1000 {
				handlerutil.WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "reason is required (1-1000 characters)"})
				return
			}

			current, err := versionStore.GetConfig(r.Context())
			if err != nil {
				handlerutil.WriteSafeError(w, r, http.StatusInternalServerError, handlerutil.ErrCodeInternal, "failed to read existing version config", err)
				return
			}

			newConfig := current
			if req.LatestVersion != "" {
				newConfig.LatestVersion = req.LatestVersion
			}
			if req.MinimumSupportedVersion != "" {
				newConfig.MinimumSupportedVersion = req.MinimumSupportedVersion
			}
			if req.DownloadURL != "" {
				newConfig.DownloadURL = req.DownloadURL
			}
			if req.EnforceMinimumVersion != nil {
				newConfig.EnforceMinimumVersion = *req.EnforceMinimumVersion
			}

			if err := version.ValidateDownloadURL(newConfig.DownloadURL); err != nil {
				handlerutil.WriteJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
				return
			}

			updated, err := versionStore.UpdateConfig(r.Context(), newConfig)
			if err != nil {
				if errors.Is(err, version.ErrPersist) {
					handlerutil.WriteSafeError(w, r, http.StatusServiceUnavailable, handlerutil.ErrCodeUnavailable, "version store unavailable, config not saved", err)
					return
				}
				handlerutil.WriteJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
				return
			}

			if auditStore != nil {
				rec := adminaudit.Record{
					ID:         newAuditID(),
					Source:     "api-gateway",
					ActorID:    revIdentity.ID,
					Action:     adminaudit.ActionVersionUpdate,
					TargetType: "version_policy",
					TargetID:   updated.ID,
					Reason:     reason,
					Details: fmt.Sprintf("latest=%s min=%s enforce=%t revision=%d",
						updated.LatestVersion, updated.MinimumSupportedVersion, updated.EnforceMinimumVersion, updated.Revision),
					RequestID: auditRequestID(r),
					CreatedAt: time.Now().UTC(),
				}
				if err := auditStore.Append(r.Context(), rec); err != nil {
					log.Printf("[GATEWAY] failed to persist %s audit record: %v", adminaudit.ActionVersionUpdate, err)
					handlerutil.ShipSecurityEvent(r.Context(), "ADMIN_AUDIT_WRITE_FAILED", "api-gateway", revIdentity.ID, "", "action="+adminaudit.ActionVersionUpdate, clientIP)
				}
			}

			handlerutil.ShipSecurityEvent(r.Context(), "ADMIN_VERSION_CONFIG_CHANGED", "api-gateway", revIdentity.ID, "",
				fmt.Sprintf("latest=%s min=%s enforce=%t reason=%s revision=%d",
					updated.LatestVersion, updated.MinimumSupportedVersion, updated.EnforceMinimumVersion, reason, updated.Revision),
				clientIP)

			handlerutil.WriteJSON(w, http.StatusOK, map[string]any{
				"message": "version configuration updated successfully",
				"config":  updated,
			})
			return
		}

		handlerutil.WriteJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
	}
}
