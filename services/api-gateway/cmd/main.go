// API Gateway — Reverse proxy entry point.
//
// Routes incoming traffic to backend microservices based on path prefix.
// All target URLs are read from environment variables at startup.
package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"

	"github.com/project/gateway/internal/config"
	"github.com/project/gateway/internal/middleware"
	"github.com/project/gateway/internal/proxy"
)

func main() {
	// ---- Load configuration from environment ----
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	mux := http.NewServeMux()

	// ---- Health check endpoint ----
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		fmt.Fprintln(w, `{"status": "ok"}`)
	})

	// ---- Service info endpoint ----
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		// Only match the exact root path; anything else should 404.
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)

		info := map[string]any{
			"service": "api-gateway",
			"version": "0.1.0",
			"routes":  make([]map[string]string, 0, len(cfg.Routes)),
		}
		for _, route := range cfg.Routes {
			info["routes"] = append(info["routes"].([]map[string]string), map[string]string{
				"prefix": route.Prefix,
				"target": route.Target,
			})
		}
		json.NewEncoder(w).Encode(info)
	})

	// ---- Register reverse proxy routes ----
	for _, route := range cfg.Routes {
		handler, err := proxy.New(route)
		if err != nil {
			log.Fatalf("Failed to create proxy for %s: %v", route.Prefix, err)
		}
		mux.Handle(route.Prefix, handler)
		log.Printf("Route registered: %s → %s (env: %s)", route.Prefix, route.Target, route.EnvKey)
	}

	// ---- Wrap with global logging middleware ----
	logged := middleware.Logging(mux)

	// ---- Start server ----
	addr := ":" + cfg.Port
	log.Printf("API Gateway listening on %s", addr)
	log.Printf("Routes active: %d", len(cfg.Routes))
	if err := http.ListenAndServe(addr, logged); err != nil {
		log.Fatalf("Server error: %v", err)
	}
}
