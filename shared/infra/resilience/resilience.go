package resilience

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log"
	"math"
	"math/rand"
	"net/http"
	"sync"
	"time"

	"github.com/sony/gobreaker/v2"
)

// cancelReadCloser invokes its cancel function exactly once when the response
// body is closed. This lets a per-attempt request context stay alive for the
// full lifetime of the body read (including streamed responses such as SSE)
// instead of being cancelled the moment the execute closure returns, while
// still guaranteeing eventual resource release on Close or on error paths.
type cancelReadCloser struct {
	closer     io.Closer
	reader     io.Reader
	cancelOnce sync.Once
	cancel     context.CancelFunc
}

func newCancelReadCloser(rc io.ReadCloser, cancel context.CancelFunc) *cancelReadCloser {
	return &cancelReadCloser{
		closer: rc,
		reader: io.LimitReader(rc, 10<<20),
		cancel: cancel,
	}
}

func (c *cancelReadCloser) Read(p []byte) (int, error) {
	return c.reader.Read(p)
}

func (c *cancelReadCloser) Close() error {
	err := c.closer.Close()
	c.cancelOnce.Do(c.cancel)
	return err
}

type BreakerStats struct {
	Name           string `json:"name"`
	State          string `json:"state"`
	Failures       uint32 `json:"failures"`
	ConsecFailures uint32 `json:"consecutive_failures"`
	Successes      uint32 `json:"successes"`
}

// Option customises a resilience client or round tripper.
type Option func(*options)

type options struct {
	// passthroughUpstream5xx makes an upstream 5xx response reach the caller
	// unchanged instead of being turned into a synthetic error.
	passthroughUpstream5xx bool
}

// WithUpstream5xxPassthrough hands a final upstream 5xx response back to the
// caller with its original status, headers and body and a nil error, instead
// of the synthetic "HTTP status N" error every other caller sees.
//
// The circuit breaker still counts the 5xx as a failure and the retry policy
// is unchanged (an idempotent request is still retried, a non-idempotent one
// is not); only the response of the last attempt is passed through.
//
// This is opt-in: every existing caller keeps the error behaviour unless it
// asks for the passthrough. Only the API gateway proxy transport uses it, so
// the edge can relay an upstream 5xx (for example user-service's
// photo_storage_unavailable) to the client byte for byte.
func WithUpstream5xxPassthrough() Option {
	return func(o *options) {
		o.passthroughUpstream5xx = true
	}
}

func newOptions(opts []Option) *options {
	o := &options{}
	for _, opt := range opts {
		if opt != nil {
			opt(o)
		}
	}
	return o
}

// upstream5xxError marks an upstream 5xx response. It is handed to the
// circuit breaker so the 5xx counts as a failure, but with
// WithUpstream5xxPassthrough the client converts it back into the original
// response for the caller.
//
// The message is unchanged ("HTTP status N") because chat-service parses it
// with a regular expression to keep the upstream outage status visible.
type upstream5xxError struct {
	status int
}

func (e *upstream5xxError) Error() string {
	return fmt.Sprintf("HTTP status %d", e.status)
}

// isUpstream5xx reports whether err marks an upstream 5xx response.
func isUpstream5xx(err error) bool {
	var upErr *upstream5xxError
	return errors.As(err, &upErr)
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
			Failures:       counts.TotalFailures,
			ConsecFailures: counts.ConsecutiveFailures,
			Successes:      counts.TotalSuccesses,
		})
	}
	return stats
}

func backoffWithJitter(attempt int, initialBackoff, maxBackoff time.Duration) time.Duration {
	temp := float64(initialBackoff) * math.Pow(2, float64(attempt))
	if temp > float64(maxBackoff) {
		temp = float64(maxBackoff)
	}
	// Jitter: 50% to 150% of the backoff value
	// #nosec G404 //nolint:gosec -- math/rand is appropriate for network retry backoff jitter, cryptographic randomness is not needed
	jitter := 0.5 + rand.Float64()
	return time.Duration(temp * jitter)
}

type ResilienceClient struct {
	client         *http.Client
	breaker        *gobreaker.CircuitBreaker[*http.Response]
	maxRetries     int
	initialBackoff time.Duration
	maxBackoff     time.Duration
	attemptTimeout time.Duration
	opts           *options
}

func NewClient(client *http.Client, serviceName string, maxRetries int, attemptTimeout time.Duration, opts ...Option) *ResilienceClient {
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
		opts:           newOptions(opts),
	}
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

			// Bound only the time-to-response-headers with the per-attempt
			// timeout. A context.WithTimeout deadline would keep ticking while
			// the caller reads the body and truncate streamed responses (SSE)
			// mid-flight, so the cancellation is driven by a stoppable timer
			// instead and ownership of cancel moves to the body wrapper below.
			timeoutCtx, cancel := context.WithCancel(reqClone.Context())
			timer := time.AfterFunc(rc.attemptTimeout, cancel)

			reqClone = reqClone.WithContext(timeoutCtx)
			// #nosec G704 //nolint:gosec -- Resilience client is a generic wrapper executing caller-supplied requests, SSRF is not applicable here
			resp, err := rc.client.Do(reqClone)
			if err != nil {
				timer.Stop()
				cancel()
				return nil, err
			}

			// Headers received: disarm the per-attempt timer. The body now
			// lives under the caller's original request context; cancel fires
			// when the body is closed (or immediately on any error path).
			// Protocol upgrades (101 Switching Protocols / WebSockets) must NOT
			// have their body wrapped, as httputil.ReverseProxy requires the
			// underlying io.ReadWriteCloser for bidirectional streaming.
			timer.Stop()
			if resp.StatusCode != http.StatusSwitchingProtocols {
				resp.Body = newCancelReadCloser(resp.Body, cancel)
			}

			if resp.StatusCode >= 500 {
				return resp, &upstream5xxError{status: resp.StatusCode}
			}

			return resp, nil
		})

		if lastErr != nil {
			if isUpstream5xx(lastErr) {
				// The upstream answered 5xx. The retry policy is unchanged:
				// the next attempt runs when there is one left.
				if rc.opts.passthroughUpstream5xx && attempt == maxAttempts-1 {
					// Last attempt: hand the upstream response to the caller
					// unchanged. The body is still open, so it is readable.
					// The breaker already counted the 5xx.
					return lastResp, nil
				}
				if lastResp != nil && lastResp.Body != nil {
					_ = lastResp.Body.Close()
				}
				continue
			}
			if lastResp != nil && lastResp.Body != nil {
				_ = lastResp.Body.Close()
			}
			if lastErr == gobreaker.ErrOpenState || lastErr == gobreaker.ErrTooManyRequests {
				break
			}
			continue
		}

		return lastResp, nil
	}

	return lastResp, lastErr
}

type ResilienceRoundTripper struct {
	underlying     http.RoundTripper
	breaker        *gobreaker.CircuitBreaker[*http.Response]
	maxRetries     int
	initialBackoff time.Duration
	maxBackoff     time.Duration
	attemptTimeout time.Duration
	opts           *options
}

func NewRoundTripper(underlying http.RoundTripper, serviceName string, maxRetries int, attemptTimeout time.Duration, opts ...Option) *ResilienceRoundTripper {
	cbSettings := gobreaker.Settings{
		Name:        serviceName,
		MaxRequests: 3,
		Interval:    10 * time.Second,
		Timeout:     15 * time.Second,
		ReadyToTrip: func(counts gobreaker.Counts) bool {
			return counts.ConsecutiveFailures >= 5
		},
		OnStateChange: func(name string, from, to gobreaker.State) {
			log.Printf("[SECURITY EVENT / DOWNSTREAM DEGRADED] Circuit breaker %s transitioned from %s to %s", name, from.String(), to.String())
		},
	}

	cb := gobreaker.NewCircuitBreaker[*http.Response](cbSettings)
	RegisterBreaker(serviceName, cb)

	return &ResilienceRoundTripper{
		underlying:     underlying,
		breaker:        cb,
		maxRetries:     maxRetries,
		initialBackoff: 100 * time.Millisecond,
		maxBackoff:     1 * time.Second,
		attemptTimeout: attemptTimeout,
		opts:           newOptions(opts),
	}
}

func (rt *ResilienceRoundTripper) RoundTrip(req *http.Request) (*http.Response, error) {
	isIdempotent := req.Method == http.MethodGet || req.Method == http.MethodHead
	maxAttempts := 1
	if isIdempotent {
		maxAttempts = rt.maxRetries + 1
	}

	var lastResp *http.Response
	var lastErr error

	for attempt := 0; attempt < maxAttempts; attempt++ {
		if attempt > 0 {
			backoff := backoffWithJitter(attempt-1, rt.initialBackoff, rt.maxBackoff)
			select {
			case <-req.Context().Done():
				return nil, req.Context().Err()
			case <-time.After(backoff):
			}
		}

		lastResp, lastErr = rt.breaker.Execute(func() (*http.Response, error) {
			var reqClone *http.Request
			if attempt > 0 {
				reqClone = req.Clone(req.Context())
			} else {
				reqClone = req
			}

			// Bound only the time-to-response-headers with the per-attempt
			// timeout (see the matching comment in Do). The stoppable timer
			// plus cancel-on-body-close pattern keeps streamed response bodies
			// readable for their full lifetime instead of cancelling them as
			// soon as this closure returns.
			timeoutCtx, cancel := context.WithCancel(reqClone.Context())
			timer := time.AfterFunc(rt.attemptTimeout, cancel)

			reqClone = reqClone.WithContext(timeoutCtx)
			resp, err := rt.underlying.RoundTrip(reqClone)
			if err != nil {
				timer.Stop()
				cancel()
				return nil, err
			}

			// Headers received: disarm the per-attempt timer and hand cancel
			// to the body wrapper so it fires on Close rather than on return.
			// Protocol upgrades (101 Switching Protocols / WebSockets) must NOT
			// have their body wrapped, as httputil.ReverseProxy requires the
			// underlying io.ReadWriteCloser for bidirectional streaming.
			timer.Stop()
			if resp.StatusCode != http.StatusSwitchingProtocols {
				resp.Body = newCancelReadCloser(resp.Body, cancel)
			}

			if resp.StatusCode >= 500 {
				return resp, &upstream5xxError{status: resp.StatusCode}
			}

			return resp, nil
		})

		if lastErr != nil {
			if isUpstream5xx(lastErr) {
				// The upstream answered 5xx. The retry policy is unchanged:
				// the next attempt runs when there is one left.
				if rt.opts.passthroughUpstream5xx && attempt == maxAttempts-1 {
					// Last attempt: hand the upstream response to the caller
					// unchanged. The body is still open, so it is readable.
					// The breaker already counted the 5xx.
					return lastResp, nil
				}
				if lastResp != nil && lastResp.Body != nil {
					_ = lastResp.Body.Close()
				}
				continue
			}
			if lastResp != nil && lastResp.Body != nil {
				_ = lastResp.Body.Close()
			}
			if lastErr == gobreaker.ErrOpenState || lastErr == gobreaker.ErrTooManyRequests {
				break
			}
			continue
		}

		return lastResp, nil
	}

	return lastResp, lastErr
}
