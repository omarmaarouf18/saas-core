// Notification Service — Real-time SSE notifications with role-based broadcasting.
//
// Endpoints:
//
//	GET  /notifications/stream              — SSE stream (token, tenant_id, role)
//	POST /notifications/send                — Push notification to connected clients
//	POST /notifications/broadcast/job-alert — Broadcast job alert to all roles
//	GET  /health                            — Health check with client stats
package main

import (
	"encoding/json"
	"log"
	"net/http"
	"time"

	"github.com/project/notification-service/internal/config"
	"github.com/project/notification-service/internal/handlers"
	"github.com/project/notification-service/internal/hub"
	"github.com/project/shared/infra/jwtutil"
	"github.com/project/shared/infra/ratelimit"
	"github.com/project/shared/infra/resilience"
	"github.com/project/shared/infra/tlsutil"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("[NOTIF] Failed to load configuration: %v", err)
	}

	// Initialize JWT utility package.
	jwtutil.Init(cfg.JWTSecret)

	// Initialize TLS configuration to fail fast if missing/unreadable.
	tlsConfig, err := tlsutil.LoadServerTLSConfig(cfg.TLSCertPath, cfg.TLSKeyPath, cfg.TLSCAPath)
	if err != nil {
		log.Fatalf("[NOTIF] Failed to load TLS configuration: %v", err)
	}

	sseHub := hub.NewSSEHub()

	// Connect to Redis.
	redisClient, err := ratelimit.NewRedisClient(cfg.RedisURI)
	if err != nil {
		log.Printf("[WARN] Redis Pub/Sub initialization failed (%v) - falling back to single-instance local hub mode", err)
	} else {
		jwtutil.SetRedisClient(redisClient)
		sseHub.SetRedisClient(redisClient)
	}
	defer sseHub.Close()

	notifHandlers := handlers.NewNotification(sseHub, cfg, redisClient)

	mux := http.NewServeMux()
	notifHandlers.RegisterRoutes(mux)

	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		if err := json.NewEncoder(w).Encode(map[string]any{
			"status":          "ok",
			"active_clients":  sseHub.ClientCount(),
			"clients_by_role": sseHub.ClientsByRole(),
			"dependencies":    resilience.GetBreakerStats(),
		}); err != nil {
			log.Printf("[ERROR] failed to encode health response: %v", err)
		}
	})

	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		if err := json.NewEncoder(w).Encode(map[string]string{
			"service":   "notification-service",
			"version":   "0.2.0",
			"transport": "SSE",
		}); err != nil {
			log.Printf("[ERROR] failed to encode info response: %v", err)
		}
	})

	addr := ":" + cfg.Port
	server := &http.Server{
		Addr:              addr,
		Handler:           mux,
		TLSConfig:         tlsConfig,
		ReadHeaderTimeout: 3 * time.Second,
	}

	log.Printf("Notification Service listening on %s (HTTPS/SSE)", addr)
	log.Printf("Endpoints: GET /notifications/stream, POST /notifications/send, POST /notifications/broadcast/job-alert")
	if err := server.ListenAndServeTLS("", ""); err != nil && err != http.ErrServerClosed {
		log.Fatalf("Server error: %v", err)
	}
}
