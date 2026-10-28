package fcm

import (
	"bytes"
	"context"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"log"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

// throwawayKey is an RSA key generated for this test binary only. It never
// leaves the process and is not written anywhere.
var (
	throwawayKeyOnce sync.Once
	throwawayKey     *rsa.PrivateKey
	throwawayKeyPEM  string
)

func testKey(t *testing.T) (*rsa.PrivateKey, string) {
	t.Helper()
	throwawayKeyOnce.Do(func() {
		k, err := rsa.GenerateKey(rand.Reader, 2048)
		if err != nil {
			panic(err)
		}
		der, err := x509.MarshalPKCS8PrivateKey(k)
		if err != nil {
			panic(err)
		}
		throwawayKey = k
		throwawayKeyPEM = string(pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der}))
	})
	return throwawayKey, throwawayKeyPEM
}

// fakeTokenServer plays oauth2.googleapis.com/token: it checks the
// JWT-bearer grant (RS256 signature against the throwaway key's public half,
// iss/scope/aud claims) and issues tok-1, tok-2, ...
type fakeTokenServer struct {
	*httptest.Server
	t          *testing.T
	mints      atomic.Int32
	expiresIn  int
	mu         sync.Mutex
	assertions []string
	// fail, when set, answers instead of issuing a token.
	failStatus int
	failBody   string
}

func newFakeTokenServer(t *testing.T) *fakeTokenServer {
	t.Helper()
	key, _ := testKey(t)
	s := &fakeTokenServer{t: t, expiresIn: 3600}
	s.Server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if err := r.ParseForm(); err != nil {
			http.Error(w, "bad form", http.StatusBadRequest)
			return
		}
		assertion := r.PostForm.Get("assertion")
		s.mu.Lock()
		s.assertions = append(s.assertions, assertion)
		s.mu.Unlock()
		if s.failStatus != 0 {
			w.WriteHeader(s.failStatus)
			_, _ = w.Write([]byte(s.failBody))
			return
		}
		if got := r.PostForm.Get("grant_type"); got != "urn:ietf:params:oauth:grant-type:jwt-bearer" {
			t.Errorf("grant_type = %q", got)
		}
		if err := verifyAssertion(assertion, &key.PublicKey, s.URL); err != nil {
			t.Errorf("assertion rejected: %v", err)
			w.WriteHeader(http.StatusBadRequest)
			_, _ = w.Write([]byte(`{"error":"invalid_grant","error_description":"Invalid JWT Signature."}`))
			return
		}
		n := s.mints.Add(1)
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{
			"access_token": fmt.Sprintf("tok-%d", n),
			"expires_in":   s.expiresIn,
			"token_type":   "Bearer",
		})
	}))
	t.Cleanup(s.Close)
	return s
}

func (s *fakeTokenServer) serviceAccountJSON(projectID string) string {
	_, keyPEM := testKey(s.t)
	b, _ := json.Marshal(map[string]string{
		"type":           "service_account",
		"project_id":     projectID,
		"private_key_id": "kid-test",
		"private_key":    keyPEM,
		"client_email":   "fcm-sender@" + projectID + ".iam.gserviceaccount.com",
		"token_uri":      s.URL,
	})
	return string(b)
}

func verifyAssertion(assertion string, pub *rsa.PublicKey, aud string) error {
	parts := strings.Split(assertion, ".")
	if len(parts) != 3 {
		return fmt.Errorf("not a JWT")
	}
	enc := base64.RawURLEncoding
	var header map[string]string
	hb, _ := enc.DecodeString(parts[0])
	if err := json.Unmarshal(hb, &header); err != nil || header["alg"] != "RS256" || header["kid"] != "kid-test" {
		return fmt.Errorf("bad header %v", header)
	}
	sig, _ := enc.DecodeString(parts[2])
	digest := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
	if err := rsa.VerifyPKCS1v15(pub, crypto.SHA256, digest[:], sig); err != nil {
		return fmt.Errorf("signature: %v", err)
	}
	var claims map[string]any
	cb, _ := enc.DecodeString(parts[1])
	if err := json.Unmarshal(cb, &claims); err != nil {
		return err
	}
	if claims["scope"] != messagingScope || claims["aud"] != aud ||
		!strings.HasPrefix(fmt.Sprint(claims["iss"]), "fcm-sender@") {
		return fmt.Errorf("bad claims %v", claims)
	}
	iat, _ := claims["iat"].(float64)
	exp, _ := claims["exp"].(float64)
	if exp-iat != 3600 {
		return fmt.Errorf("lifetime %v", exp-iat)
	}
	return nil
}

// fakeFCM plays fcm.googleapis.com. respond decides each answer (nil: 200).
type fakeFCM struct {
	*httptest.Server
	mu       sync.Mutex
	calls    int
	auth     []string
	paths    []string
	payloads []FCMMessagePayload
	respond  func(call int, bearer string) (int, string)
}

func newFakeFCM(t *testing.T, respond func(call int, bearer string) (int, string)) *fakeFCM {
	t.Helper()
	f := &fakeFCM{respond: respond}
	f.Server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var p FCMMessagePayload
		_ = json.NewDecoder(r.Body).Decode(&p)
		f.mu.Lock()
		f.calls++
		call := f.calls
		auth := r.Header.Get("Authorization")
		f.auth = append(f.auth, auth)
		f.paths = append(f.paths, r.URL.Path)
		f.payloads = append(f.payloads, p)
		f.mu.Unlock()
		status, body := http.StatusOK, `{"name":"projects/qd-test/messages/1"}`
		if f.respond != nil {
			status, body = f.respond(call, strings.TrimPrefix(auth, "Bearer "))
		}
		w.WriteHeader(status)
		_, _ = w.Write([]byte(body))
	}))
	t.Cleanup(f.Close)
	return f
}

func newOAuthClient(t *testing.T, tok *fakeTokenServer, api *fakeFCM) *Client {
	t.Helper()
	c := NewClient(tok.serviceAccountJSON("qd-test"), "", "", "http://auth", "secret-internal-token", nil, WithAPIBaseURL(api.URL))
	if !c.IsEnabled() {
		t.Fatalf("client disabled: %s", c.disabledReason)
	}
	c.retryBase = time.Millisecond
	return c
}

func TestFCMOAuth_TokenMintedCachedAndSentAsBearer(t *testing.T) {
	tok := newFakeTokenServer(t)
	api := newFakeFCM(t, nil)
	c := newOAuthClient(t, tok, api)

	data := map[string]string{"type": "job_picked_up", "event_type": "job_picked_up", "job_id": "job-42"}
	for i := 0; i < 2; i++ {
		if stale, err := c.SendPush(context.Background(), "device-1", "Picked up", "Your parcel is on its way", data); err != nil || stale {
			t.Fatalf("send %d: stale=%v err=%v", i, stale, err)
		}
	}
	if n := tok.mints.Load(); n != 1 {
		t.Errorf("token minted %d times for 2 sends, want 1 (cached)", n)
	}
	for i, a := range api.auth {
		if a != "Bearer tok-1" {
			t.Errorf("send %d Authorization = %q, want Bearer tok-1", i, a)
		}
	}
	if api.paths[0] != "/v1/projects/qd-test/messages:send" {
		t.Errorf("path = %q (project must come from the key)", api.paths[0])
	}
	m := api.payloads[0].Message
	if m.Token != "device-1" || m.Notification.Title != "Picked up" || m.Notification.Body != "Your parcel is on its way" {
		t.Errorf("message = %+v", m)
	}
	for k, v := range data {
		if m.Data[k] != v {
			t.Errorf("data[%s] = %q, want %q", k, m.Data[k], v)
		}
	}
	if m.Android == nil || m.Android.Priority != "HIGH" || m.Android.Notification == nil || m.Android.Notification.ChannelID != "qd_default" {
		t.Errorf("android block = %+v, want priority HIGH, channel_id qd_default", m.Android)
	}
}

func TestFCMOAuth_TokenRefreshedFiveMinutesBeforeExpiry(t *testing.T) {
	tok := newFakeTokenServer(t)
	api := newFakeFCM(t, nil)
	c := newOAuthClient(t, tok, api)
	now := time.Now()
	c.tokens.now = func() time.Time { return now }

	send := func() {
		t.Helper()
		if _, err := c.SendPush(context.Background(), "d", "t", "b", nil); err != nil {
			t.Fatal(err)
		}
	}
	send()
	now = now.Add(54 * time.Minute) // 6 min left: still cached
	send()
	if n := tok.mints.Load(); n != 1 {
		t.Fatalf("mints after 54 min = %d, want 1", n)
	}
	now = now.Add(2 * time.Minute) // 4 min left: inside the 5 min margin
	send()
	if n := tok.mints.Load(); n != 2 {
		t.Fatalf("mints after 56 min = %d, want 2", n)
	}
	if got := api.auth[2]; got != "Bearer tok-2" {
		t.Errorf("third send used %q, want Bearer tok-2", got)
	}
}

func TestFCMOAuth_RefreshOn401Once(t *testing.T) {
	t.Run("401 then ok", func(t *testing.T) {
		tok := newFakeTokenServer(t)
		api := newFakeFCM(t, func(call int, bearer string) (int, string) {
			if bearer == "tok-1" {
				return http.StatusUnauthorized, `{"error":{"code":401,"status":"UNAUTHENTICATED","message":"Request had invalid authentication credentials."}}`
			}
			return http.StatusOK, `{}`
		})
		c := newOAuthClient(t, tok, api)
		if stale, err := c.SendPush(context.Background(), "d", "t", "b", nil); err != nil || stale {
			t.Fatalf("stale=%v err=%v", stale, err)
		}
		if api.calls != 2 || tok.mints.Load() != 2 {
			t.Errorf("calls=%d mints=%d, want 2 and 2", api.calls, tok.mints.Load())
		}
		if api.auth[1] != "Bearer tok-2" {
			t.Errorf("retry used %q, want Bearer tok-2", api.auth[1])
		}
	})
	t.Run("always 401: one refresh only", func(t *testing.T) {
		tok := newFakeTokenServer(t)
		api := newFakeFCM(t, func(int, string) (int, string) {
			return http.StatusUnauthorized, `{"error":{"code":401,"status":"UNAUTHENTICATED"}}`
		})
		c := newOAuthClient(t, tok, api)
		stale, err := c.SendPush(context.Background(), "d", "t", "b", nil)
		if err == nil || stale {
			t.Fatalf("stale=%v err=%v, want an error and not stale", stale, err)
		}
		if api.calls != 2 {
			t.Errorf("calls = %d, want 2 (one refresh)", api.calls)
		}
	})
}

func TestFCMOAuth_ConcurrentSendsMintOnce(t *testing.T) {
	tok := newFakeTokenServer(t)
	api := newFakeFCM(t, nil)
	c := newOAuthClient(t, tok, api)
	var wg sync.WaitGroup
	for i := 0; i < 20; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if _, err := c.SendPush(context.Background(), "d", "t", "b", nil); err != nil {
				t.Error(err)
			}
		}()
	}
	wg.Wait()
	if n := tok.mints.Load(); n != 1 {
		t.Errorf("20 concurrent sends minted %d tokens, want 1", n)
	}
}

func TestFCMOAuth_StaleTokenMapping(t *testing.T) {
	cases := []struct {
		name      string
		status    int
		body      string
		wantStale bool
	}{
		{"404 UNREGISTERED", 404, `{"error":{"code":404,"status":"NOT_FOUND","details":[{"errorCode":"UNREGISTERED"}]}}`, true},
		{"UNREGISTERED detail alone", 400, `{"error":{"code":400,"status":"FAILED_PRECONDITION","details":[{"errorCode":"UNREGISTERED"}]}}`, true},
		{"INVALID_ARGUMENT on message.token", 400, `{"error":{"code":400,"status":"INVALID_ARGUMENT","message":"Invalid value","details":[{"errorCode":"INVALID_ARGUMENT"},{"fieldViolations":[{"field":"message.token","description":"Invalid registration token"}]}]}}`, true},
		{"INVALID_ARGUMENT registration token message", 400, `{"error":{"code":400,"status":"INVALID_ARGUMENT","message":"The registration token is not a valid FCM registration token","details":[{"errorCode":"INVALID_ARGUMENT"}]}}`, true},
		{"INVALID_ARGUMENT on the payload is not stale", 400, `{"error":{"code":400,"status":"INVALID_ARGUMENT","message":"Invalid JSON payload received.","details":[{"errorCode":"INVALID_ARGUMENT"},{"fieldViolations":[{"field":"message.data[0].value"}]}]}}`, false},
		{"SENDER_ID_MISMATCH is not stale", 403, `{"error":{"code":403,"status":"PERMISSION_DENIED","details":[{"errorCode":"SENDER_ID_MISMATCH"}]}}`, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			tok := newFakeTokenServer(t)
			api := newFakeFCM(t, func(int, string) (int, string) { return tc.status, tc.body })
			c := newOAuthClient(t, tok, api)
			stale, err := c.SendPush(context.Background(), "device-x", "t", "b", nil)
			if err == nil {
				t.Fatal("want an error")
			}
			if stale != tc.wantStale {
				t.Errorf("stale = %v, want %v", stale, tc.wantStale)
			}
		})
	}
}

func TestFCMOAuth_RetryOn429And5xx(t *testing.T) {
	t.Run("503, 429, then ok", func(t *testing.T) {
		tok := newFakeTokenServer(t)
		api := newFakeFCM(t, func(call int, _ string) (int, string) {
			switch call {
			case 1:
				return http.StatusServiceUnavailable, `{"error":{"code":503,"status":"UNAVAILABLE"}}`
			case 2:
				return http.StatusTooManyRequests, `{"error":{"code":429,"status":"RESOURCE_EXHAUSTED","details":[{"errorCode":"QUOTA_EXCEEDED"}]}}`
			}
			return http.StatusOK, `{}`
		})
		c := newOAuthClient(t, tok, api)
		if _, err := c.SendPush(context.Background(), "d", "t", "b", nil); err != nil {
			t.Fatal(err)
		}
		if api.calls != 3 {
			t.Errorf("calls = %d, want 3", api.calls)
		}
	})
	t.Run("always 500: bounded", func(t *testing.T) {
		tok := newFakeTokenServer(t)
		api := newFakeFCM(t, func(int, string) (int, string) {
			return http.StatusInternalServerError, `{"error":{"code":500,"status":"INTERNAL"}}`
		})
		c := newOAuthClient(t, tok, api)
		stale, err := c.SendPush(context.Background(), "d", "t", "b", nil)
		if err == nil || stale {
			t.Fatalf("stale=%v err=%v", stale, err)
		}
		if api.calls != defaultMaxAttempts {
			t.Errorf("calls = %d, want %d", api.calls, defaultMaxAttempts)
		}
	})
	t.Run("Retry-After is capped", func(t *testing.T) {
		c := &Client{retryBase: time.Millisecond}
		if got := c.backoff(1, "3600"); got != maxRetryWait {
			t.Errorf("backoff with Retry-After 3600 = %s, want %s", got, maxRetryWait)
		}
		if got := c.backoff(3, ""); got != 4*time.Millisecond {
			t.Errorf("backoff attempt 3 = %s, want 4ms", got)
		}
	})
}

func TestFCMOAuth_StartupCheck(t *testing.T) {
	t.Run("token ok, nothing sent", func(t *testing.T) {
		tok := newFakeTokenServer(t)
		api := newFakeFCM(t, nil)
		c := newOAuthClient(t, tok, api)
		if got, want := c.StartupCheck(context.Background()), "push enabled (project qd-test, token ok)"; got != want {
			t.Errorf("status = %q, want %q", got, want)
		}
		if api.calls != 0 || tok.mints.Load() != 1 {
			t.Errorf("FCM calls=%d mints=%d, want 0 and 1", api.calls, tok.mints.Load())
		}
	})
	t.Run("grant rejected disables push", func(t *testing.T) {
		tok := newFakeTokenServer(t)
		tok.failStatus, tok.failBody = http.StatusBadRequest, `{"error":"invalid_grant","error_description":"Invalid JWT Signature."}`
		api := newFakeFCM(t, nil)
		c := newOAuthClient(t, tok, api)
		want := "push disabled: token mint failed: token endpoint returned HTTP 400: invalid_grant Invalid JWT Signature."
		if got := c.StartupCheck(context.Background()); got != want {
			t.Errorf("status = %q, want %q", got, want)
		}
		if c.IsEnabled() {
			t.Error("client still enabled after a rejected grant")
		}
	})
	t.Run("transient failure keeps push enabled", func(t *testing.T) {
		tok := newFakeTokenServer(t)
		tok.failStatus, tok.failBody = http.StatusServiceUnavailable, `oops`
		api := newFakeFCM(t, nil)
		c := newOAuthClient(t, tok, api)
		got := c.StartupCheck(context.Background())
		if !strings.HasPrefix(got, "push enabled (project qd-test, token mint failed: token endpoint returned HTTP 503") || !c.IsEnabled() {
			t.Errorf("status = %q enabled=%v", got, c.IsEnabled())
		}
	})
	t.Run("unusable key", func(t *testing.T) {
		tok := newFakeTokenServer(t)
		sa := strings.Replace(tok.serviceAccountJSON("qd-test"), "BEGIN PRIVATE KEY", "BEGIN NOTHING", 1)
		c := NewClient(sa, "", "", "", "", nil)
		if c.IsEnabled() {
			t.Fatal("enabled with an unusable key")
		}
		if got, want := c.StartupCheck(context.Background()), "push disabled: service-account key unusable: private_key is not PEM"; got != want {
			t.Errorf("status = %q, want %q", got, want)
		}
	})
	t.Run("plain http token_uri off loopback refused", func(t *testing.T) {
		tok := newFakeTokenServer(t)
		sa := strings.Replace(tok.serviceAccountJSON("qd-test"), tok.URL, "http://token.example.com/token", 1)
		c := NewClient(sa, "", "", "", "", nil)
		if c.IsEnabled() || !strings.Contains(c.disabledReason, "token_uri must use https") {
			t.Errorf("enabled=%v reason=%q", c.IsEnabled(), c.disabledReason)
		}
	})
}

func TestFCMOAuth_NoKeyMaterialInLogs(t *testing.T) {
	var logs bytes.Buffer
	prev := log.Writer()
	log.SetOutput(&logs)
	t.Cleanup(func() { log.SetOutput(prev) })

	_, keyPEM := testKey(t)
	tok := newFakeTokenServer(t)
	api := newFakeFCM(t, func(call int, _ string) (int, string) {
		if call <= 2 {
			return http.StatusUnauthorized, `{"error":{"code":401,"status":"UNAUTHENTICATED"}}`
		}
		return http.StatusOK, `{}`
	})
	c := newOAuthClient(t, tok, api)
	_ = c.StartupCheck(context.Background())
	_, _ = c.SendPush(context.Background(), "device-token-abcdefghijklmnop", "t", "b", nil) // 401, refresh, 401
	_, _ = c.SendPush(context.Background(), "device-token-abcdefghijklmnop", "t", "b", nil) // ok
	tok.failStatus, tok.failBody = http.StatusBadRequest, `{"error":"invalid_grant"}`
	c.tokens.Invalidate("tok-3")
	_, _ = c.SendPush(context.Background(), "device-token-abcdefghijklmnop", "t", "b", nil) // mint fails

	out := logs.String()
	if out == "" {
		t.Fatal("captured no logs")
	}
	keyBody := strings.Split(keyPEM, "\n")[1]
	secrets := []string{"PRIVATE KEY", keyBody, "tok-1", "tok-2", "tok-3", "device-token-abcdefghijklmnop"}
	tok.mu.Lock()
	for _, a := range tok.assertions {
		secrets = append(secrets, a, strings.Split(a, ".")[2])
	}
	tok.mu.Unlock()
	for _, s := range secrets {
		if s != "" && strings.Contains(out, s) {
			t.Errorf("log output contains secret material %.20q...", s)
		}
	}
}
