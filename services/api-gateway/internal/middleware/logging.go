// Package middleware provides HTTP middleware for the API Gateway.
package middleware

import (
	"bufio"
	"fmt"
	"log"
	"net"
	"net/http"
	"strings"
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

func (sr *statusRecorder) Hijack() (net.Conn, *bufio.ReadWriter, error) {
	if hijacker, ok := sr.ResponseWriter.(http.Hijacker); ok {
		return hijacker.Hijack()
	}
	return nil, nil, fmt.Errorf("http.ResponseWriter does not support hijacking")
}

// Logging is a global middleware that logs every request with:
//   - HTTP method
//   - Request path
//   - Response status code
//   - Duration
//
// This fulfills the Traffic API monitoring requirement.
// Logging is a global middleware that logs every request and provides CORS.
func Logging(allowedOrigin string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Access-Control-Allow-Origin", allowedOrigin)
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

			// CR/LF bytes in a decoded request path would let a client forge
			// additional log lines; strip them before interpolation.
			sanitizedPath := strings.Map(func(r rune) rune {
				if r == '\n' || r == '\r' {
					return ' '
				}
				return r
			}, r.URL.Path)
			// #nosec G706 //nolint:gosec -- method is from the fixed HTTP verb set and the path is CR/LF-sanitized above
			log.Printf("[TRAFFIC] %s %s → %d (%s)",
				r.Method,
				sanitizedPath,
				rec.statusCode,
				duration.Round(time.Microsecond),
			)
		})
	}
}
