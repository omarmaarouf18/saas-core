package resilience

import (
	"context"
	"fmt"
	"log"
	"math"
	"math/rand"
	"net/http"
	"sync"
	"time"

	"github.com/sony/gobreaker/v2"
)

type BreakerStats struct {
	Name           string `json:"name"`
	State          string `json:"state"`
	Failures       uint32 `json:"failures"`
	ConsecFailures uint32 `json:"consecutive_failures"`
	Successes      uint32 `json:"successes"`
}

var (
	breakersMu sync.RWMutex
	breakers   = make(map[string]*gobreaker.CircuitBreaker[*http.Response])
)

func RegisterBreaker(name string, cb *gobreaker.CircuitBreaker[*http.Response]) {
	breakersMu.Lock()
	defer breakersMu.Unlock()
	breakers[name] = cb
}

func GetBreakerStats() []BreakerStats {
	breakersMu.RLock()
	defer breakersMu.RUnlock()

	stats := make([]BreakerStats, 0, len(breakers))
	for name, cb := range breakers {
		counts := cb.Counts()
		stats = append(stats, BreakerStats{
			Name:           name,
			State:          cb.State().String(),
			Failures:       counts.Failures,
			ConsecFailures: counts.ConsecutiveFailures,
			Successes:      counts.Successes,
		})
	}
	return stats
}

type ResilienceClient struct {
	client         *http.Client
	breaker        *gobreaker.CircuitBreaker[*http.Response]
	maxRetries     int
	initialBackoff time.Duration
	maxBackoff     time.Duration
	attemptTimeout time.Duration
}

func NewClient(client *http.Client, serviceName string, maxRetries int, attemptTimeout time.Duration) *ResilienceClient {
	cbSettings := gobreaker.Settings{
		Name:        serviceName,
		MaxRequests: 3, // consecutive successes needed in half-open state to close
		Interval:    10 * time.Second,
		Timeout:     15 * time.Second, // cooldown period in open state
		ReadyToTrip: func(counts gobreaker.Counts) bool {
			return counts.ConsecutiveFailures >= 5
		},
		OnStateChange: func(name string, from, to gobreaker.State) {
			log.Printf("[SECURITY EVENT / DOWNSTREAM DEGRADED] Circuit breaker %s transitioned from %s to %s", name, from.String(), to.String())
		},
	}

	cb := gobreaker.NewCircuitBreaker[*http.Response](cbSettings)
	RegisterBreaker(serviceName, cb)

	return &ResilienceClient{
		client:         client,
		breaker:        cb,
		maxRetries:     maxRetries,
		initialBackoff: 100 * time.Millisecond,
		maxBackoff:     1 * time.Second,
		attemptTimeout: attemptTimeout,
	}
}

func backoffWithJitter(attempt int, initialBackoff, maxBackoff time.Duration) time.Duration {
	temp := float64(initialBackoff) * math.Pow(2, float64(attempt))
	if temp > float64(maxBackoff) {
		temp = float64(maxBackoff)
	}
	// Jitter: 50% to 150% of the backoff value
	jitter := 0.5 + rand.Float64()
	return time.Duration(temp * jitter)
}

func (rc *ResilienceClient) Do(req *http.Request) (*http.Response, error) {
	isIdempotent := req.Method == http.MethodGet || req.Method == http.MethodHead
	maxAttempts := 1
	if isIdempotent {
		maxAttempts = rc.maxRetries + 1
	}

	var lastResp *http.Response
	var lastErr error

	for attempt := 0; attempt < maxAttempts; attempt++ {
		if attempt > 0 {
			backoff := backoffWithJitter(attempt-1, rc.initialBackoff, rc.maxBackoff)
			select {
			case <-req.Context().Done():
				return nil, req.Context().Err()
			case <-time.After(backoff):
			}
		}

		lastResp, lastErr = rc.breaker.Execute(func() (*http.Response, error) {
			var reqClone *http.Request
			if attempt > 0 {
				reqClone = req.Clone(req.Context())
			} else {
				reqClone = req
			}

			// Per-attempt timeout context
			timeoutCtx, cancel := context.WithTimeout(reqClone.Context(), rc.attemptTimeout)
			defer cancel()

			reqClone = reqClone.WithContext(timeoutCtx)
			resp, err := rc.client.Do(reqClone)
			if err != nil {
				return nil, err
			}

			if resp.StatusCode >= 500 {
				return resp, fmt.Errorf("HTTP status %d", resp.StatusCode)
			}

			return resp, nil
		})

		if lastErr != nil {
			if lastErr == gobreaker.ErrOpenState || lastErr == gobreaker.ErrTooManyRequests {
				break
			}
			continue
		}

		return lastResp, nil
	}

	return lastResp, lastErr
}
