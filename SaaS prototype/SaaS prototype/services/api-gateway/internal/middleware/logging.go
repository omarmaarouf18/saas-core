// Package middleware provides HTTP middleware for the API Gateway.
package middleware

import (
	"log"
	"net/http"
	"time"
)

// statusRecorder wraps http.ResponseWriter to capture the status code.
type statusRecorder struct {
	http.ResponseWriter
	statusCode int
}

func (sr *statusRecorder) WriteHeader(code int) {
	sr.statusCode = code
	sr.ResponseWriter.WriteHeader(code)
}

// Logging is a global middleware that logs every request with:
//   - HTTP method
//   - Request path
//   - Response status code
//   - Duration
//
// This fulfills the Traffic API monitoring requirement.
// Logging is a global middleware that logs every request and provides CORS.
func Logging(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Forwarded-For")

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusOK)
			return
		}

		start := time.Now()

		rec := &statusRecorder{
			ResponseWriter: w,
			statusCode:     http.StatusOK,
		}

		next.ServeHTTP(rec, r)

		duration := time.Since(start)

		log.Printf("[TRAFFIC] %s %s → %d (%s)",
			r.Method,
			r.URL.Path,
			rec.statusCode,
			duration.Round(time.Microsecond),
		)
	})
}
