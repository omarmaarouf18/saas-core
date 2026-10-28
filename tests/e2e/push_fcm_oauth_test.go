package e2e

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"math/big"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/redis/go-redis/v9"
	"go.mongodb.org/mongo-driver/v2/mongo"
	"go.mongodb.org/mongo-driver/v2/mongo/options"
)

// TestPushBE_NotificationServiceDeliversViaFCMOAuth (PUSH-BE item 6) runs the
// real notification-service binary, built from this checkout, against three
// local fakes: Google's OAuth2 token endpoint, the FCM HTTP v1 API (via
// FCM_API_BASE_URL) and auth-service's device-token lookup. It checks the
// whole path a production push takes: --check-env and startup mint one
// token and log "push enabled (project X, token ok)"; POST
// /notifications/send over mTLS reaches FCM with a Bearer token and the
// payload the app routes on; a token FCM reports as UNREGISTERED is
// unregistered at auth-service.
//
// The service itself runs outside the staging stack (the staging compose
// cannot point notification-service at a fake Google without a hot-path
// change). It uses the staging Redis and Mongo (STAGING_REDIS_URI /
// STAGING_MONGO_URI, as every e2e test does; Mongo in a throwaway database
// dropped afterwards) because POST /notifications/send panics when either
// failed to connect at startup (a pre-existing defect, see
// docs/worklog/PUSH-BE.md); the test skips when they are unreachable. The
// service-account key is a throwaway RSA key generated here.
func TestPushBE_NotificationServiceDeliversViaFCMOAuth(t *testing.T) {
	if _, err := exec.LookPath("go"); err != nil {
		t.Skip("go toolchain not on PATH")
	}
	cfg := LoadConfig()
	redisURI := cfg.RedisURI
	if opts, err := redis.ParseURL(redisURI); err != nil {
		t.Skipf("STAGING_REDIS_URI unusable: %v", err)
	} else {
		rdb := redis.NewClient(opts)
		pingCtx, cancelPing := context.WithTimeout(context.Background(), 2*time.Second)
		err := rdb.Ping(pingCtx).Err()
		cancelPing()
		_ = rdb.Close()
		if err != nil {
			t.Skipf("staging Redis unreachable (%v): start the staging stack", err)
		}
	}
	notifDB := fmt.Sprintf("push_e2e_%d", time.Now().UnixNano())
	{
		ctx, cancelDB := context.WithTimeout(context.Background(), 5*time.Second)
		mc, err := mongo.Connect(options.Client().ApplyURI(cfg.MongoURI))
		if err == nil {
			err = mc.Ping(ctx, nil)
		}
		cancelDB()
		if err != nil {
			t.Skipf("staging Mongo unreachable (%v): start the staging stack", err)
		}
		t.Cleanup(func() {
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			_ = mc.Database(notifDB).Drop(ctx)
			_ = mc.Disconnect(ctx)
		})
	}
	tmp := t.TempDir()

	// Build the service binary from this checkout.
	bin := filepath.Join(tmp, "notification-service")
	build := exec.Command("go", "build", "-o", bin, "./cmd")
	build.Dir = filepath.Join("..", "..", "services", "notification-service")
	if out, err := build.CombinedOutput(); err != nil {
		t.Fatalf("build notification-service: %v\n%s", err, out)
	}

	// Throwaway service-account key.
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	der, _ := x509.MarshalPKCS8PrivateKey(key)
	keyPEM := string(pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der}))
	keyBody := strings.Split(keyPEM, "\n")[1]

	// Fake Google token endpoint.
	var mu sync.Mutex
	var mints int
	var assertions []string
	tokenSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = r.ParseForm()
		if r.PostForm.Get("grant_type") != "urn:ietf:params:oauth:grant-type:jwt-bearer" || strings.Count(r.PostForm.Get("assertion"), ".") != 2 {
			w.WriteHeader(http.StatusBadRequest)
			_, _ = w.Write([]byte(`{"error":"invalid_grant"}`))
			return
		}
		mu.Lock()
		mints++
		n := mints
		assertions = append(assertions, r.PostForm.Get("assertion"))
		mu.Unlock()
		_ = json.NewEncoder(w).Encode(map[string]any{"access_token": fmt.Sprintf("e2e-access-%d", n), "expires_in": 3600})
	}))
	defer tokenSrv.Close()

	saJSON, _ := json.Marshal(map[string]string{
		"type": "service_account", "project_id": "qd-e2e", "private_key_id": "kid-e2e",
		"private_key": keyPEM, "client_email": "fcm@qd-e2e.iam.gserviceaccount.com", "token_uri": tokenSrv.URL,
	})

	// Fake FCM API.
	type fcmCall struct {
		Path, Auth string
		Message    struct {
			Token        string            `json:"token"`
			Notification map[string]string `json:"notification"`
			Data         map[string]string `json:"data"`
			Android      struct {
				Priority     string            `json:"priority"`
				Notification map[string]string `json:"notification"`
			} `json:"android"`
		} `json:"message"`
	}
	var fcmCalls []fcmCall
	fcmSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var c fcmCall
		_ = json.NewDecoder(r.Body).Decode(&c)
		c.Path, c.Auth = r.URL.Path, r.Header.Get("Authorization")
		mu.Lock()
		fcmCalls = append(fcmCalls, c)
		mu.Unlock()
		if c.Message.Token == "device-stale" {
			w.WriteHeader(http.StatusNotFound)
			_, _ = w.Write([]byte(`{"error":{"code":404,"status":"NOT_FOUND","details":[{"errorCode":"UNREGISTERED"}]}}`))
			return
		}
		_, _ = w.Write([]byte(`{"name":"projects/qd-e2e/messages/1"}`))
	}))
	defer fcmSrv.Close()

	// Fake auth-service: device tokens and stale-token unregistration.
	const internalToken = "e2e-internal-token"
	var unregistered []string
	authSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("X-Internal-Token") != internalToken {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		switch r.URL.Path {
		case "/auth/user":
			_ = json.NewEncoder(w).Encode(map[string]any{"id": r.URL.Query().Get("id"),
				"device_tokens": []map[string]string{{"token": "device-good"}, {"token": "device-stale"}}})
		case "/auth/device-token":
			var body map[string]string
			_ = json.NewDecoder(r.Body).Decode(&body)
			mu.Lock()
			unregistered = append(unregistered, body["action"]+":"+body["token"])
			mu.Unlock()
			w.WriteHeader(http.StatusOK)
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer authSrv.Close()

	// mTLS material for the service and for this test as its client.
	caPEM, serverCert, serverKey, clientTLS := e2eMTLS(t)
	for name, data := range map[string][]byte{"ca.crt": caPEM, "server.crt": serverCert, "server.key": serverKey} {
		if err := os.WriteFile(filepath.Join(tmp, name), data, 0o600); err != nil {
			t.Fatal(err)
		}
	}

	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := l.Addr().(*net.TCPAddr).Port
	_ = l.Close()

	env := []string{
		"PATH=" + os.Getenv("PATH"),
		"PORT=" + fmt.Sprint(port),
		"JWT_SECRET=e2e-jwt-secret-not-used-by-this-test",
		"INTERNAL_SERVICE_TOKEN=" + internalToken,
		"TLS_CERT_PATH=" + filepath.Join(tmp, "server.crt"),
		"TLS_KEY_PATH=" + filepath.Join(tmp, "server.key"),
		"TLS_CA_PATH=" + filepath.Join(tmp, "ca.crt"),
		"REDIS_URI=" + redisURI,
		"MONGO_URI=" + cfg.MongoURI,
		"NOTIFICATION_MONGO_DATABASE=" + notifDB,
		"AUTH_SERVICE_URL=" + authSrv.URL,
		"FCM_SERVICE_ACCOUNT_JSON_B64=" + base64.StdEncoding.EncodeToString(saJSON),
		"FCM_API_BASE_URL=" + fcmSrv.URL,
	}
	secrets := func() []string {
		mu.Lock()
		defer mu.Unlock()
		s := []string{keyBody, "PRIVATE KEY", base64.StdEncoding.EncodeToString(saJSON)[:40], "e2e-access-1", "device-good", "device-stale"}
		for _, a := range assertions {
			s = append(s, a[strings.LastIndex(a, ".")+1:])
		}
		return s
	}
	assertNoSecrets := func(what, out string) {
		t.Helper()
		for _, s := range secrets() {
			if strings.Contains(out, s) {
				t.Errorf("%s output contains secret material %.12q...", what, s)
			}
		}
	}

	// 1. --check-env: mints one token, sends nothing, exits 0.
	check := exec.Command(bin, "--check-env")
	check.Env = env
	checkOut, err := check.CombinedOutput()
	if err != nil {
		t.Fatalf("--check-env: %v\n%s", err, checkOut)
	}
	for _, want := range []string{
		"[CONFIG] push key loaded (project qd-e2e)",
		"[FCM] push enabled (project qd-e2e, token ok)",
		"PREFLIGHT OK: notification-service config validated",
	} {
		if !strings.Contains(string(checkOut), want) {
			t.Errorf("--check-env output lacks %q:\n%s", want, checkOut)
		}
	}
	mu.Lock()
	if mints != 1 || len(fcmCalls) != 0 {
		t.Errorf("--check-env: %d mints, %d FCM calls; want 1 and 0", mints, len(fcmCalls))
	}
	mu.Unlock()
	assertNoSecrets("--check-env", string(checkOut))

	// 2. Start the service.
	var logs safeBuffer
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	svc := exec.CommandContext(ctx, bin)
	svc.Env = env
	svc.Stdout, svc.Stderr = &logs, &logs
	if err := svc.Start(); err != nil {
		t.Fatal(err)
	}
	defer func() { cancel(); _ = svc.Wait() }()

	client := &http.Client{Timeout: 3 * time.Second, Transport: &http.Transport{TLSClientConfig: clientTLS}}
	base := fmt.Sprintf("https://127.0.0.1:%d", port)
	deadline := time.Now().Add(30 * time.Second)
	for {
		resp, err := client.Get(base + "/health")
		if err == nil {
			_ = resp.Body.Close()
			if resp.StatusCode == http.StatusOK {
				break
			}
		}
		if time.Now().After(deadline) {
			t.Fatalf("notification-service did not become healthy: %v\n%s", err, logs.String())
		}
		time.Sleep(200 * time.Millisecond)
	}
	if !strings.Contains(logs.String(), "[FCM] push enabled (project qd-e2e, token ok)") {
		t.Errorf("startup log lacks the push enabled line:\n%s", logs.String())
	}

	// 3. A job notification for user u-e2e.
	body, _ := json.Marshal(map[string]any{
		"type": "job_picked_up", "tenant_id": "tenant-e2e", "user_id": "u-e2e", "job_id": "job-e2e-1",
		"title": "Picked up", "body": "Your parcel is on its way",
	})
	req, _ := http.NewRequest(http.MethodPost, base+"/notifications/send", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Internal-Token", internalToken)
	resp, err := client.Do(req)
	if err != nil {
		t.Fatalf("send: %v\n%s", err, logs.String())
	}
	_ = resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("send: HTTP %d", resp.StatusCode)
	}

	deadline = time.Now().Add(15 * time.Second)
	for {
		mu.Lock()
		nCalls, unreg := len(fcmCalls), append([]string(nil), unregistered...)
		mu.Unlock()
		if nCalls >= 2 && len(unreg) >= 1 {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("push not delivered: %d FCM calls, unregistered %v\n%s", nCalls, unreg, logs.String())
		}
		time.Sleep(100 * time.Millisecond)
	}

	mu.Lock()
	calls, unreg := append([]fcmCall(nil), fcmCalls...), append([]string(nil), unregistered...)
	mu.Unlock()
	for _, c := range calls {
		if c.Path != "/v1/projects/qd-e2e/messages:send" {
			t.Errorf("FCM path %q", c.Path)
		}
		if !strings.HasPrefix(c.Auth, "Bearer e2e-access-") {
			t.Errorf("FCM call without Bearer access token: %q", c.Auth)
		}
		m := c.Message
		if m.Notification["title"] != "Picked up" || m.Data["type"] != "job_picked_up" ||
			m.Data["event_type"] != "job_picked_up" || m.Data["job_id"] != "job-e2e-1" {
			t.Errorf("FCM message %+v", m)
		}
		if m.Android.Priority != "HIGH" || m.Android.Notification["channel_id"] != "qd_default" {
			t.Errorf("android block %+v", m.Android)
		}
	}
	if len(unreg) != 1 || unreg[0] != "unregister:device-stale" {
		t.Errorf("unregistered = %v, want [unregister:device-stale]", unreg)
	}
	cancel()
	_ = svc.Wait()
	assertNoSecrets("service log", logs.String())
}

// safeBuffer is a bytes.Buffer safe for the child's concurrent writes.
type safeBuffer struct {
	mu sync.Mutex
	b  bytes.Buffer
}

func (s *safeBuffer) Write(p []byte) (int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.b.Write(p)
}

func (s *safeBuffer) String() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.b.String()
}

// e2eMTLS makes a throwaway CA, a server certificate for 127.0.0.1 and a
// client TLS config presenting a CA-signed client certificate.
func e2eMTLS(t *testing.T) (caPEM, serverPEM, serverKeyPEM []byte, client *tls.Config) {
	t.Helper()
	newKey := func() *rsa.PrivateKey {
		k, err := rsa.GenerateKey(rand.Reader, 2048)
		if err != nil {
			t.Fatal(err)
		}
		return k
	}
	caKey := newKey()
	caTmpl := &x509.Certificate{
		SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: "push-e2e-ca"},
		NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().Add(time.Hour),
		IsCA: true, BasicConstraintsValid: true, KeyUsage: x509.KeyUsageCertSign,
	}
	caDER, err := x509.CreateCertificate(rand.Reader, caTmpl, caTmpl, &caKey.PublicKey, caKey)
	if err != nil {
		t.Fatal(err)
	}
	caCert, _ := x509.ParseCertificate(caDER)
	issue := func(cn string, usage x509.ExtKeyUsage, serial int64) ([]byte, *rsa.PrivateKey) {
		k := newKey()
		tmpl := &x509.Certificate{
			SerialNumber: big.NewInt(serial), Subject: pkix.Name{CommonName: cn},
			NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().Add(time.Hour),
			KeyUsage: x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment, ExtKeyUsage: []x509.ExtKeyUsage{usage},
			IPAddresses: []net.IP{net.ParseIP("127.0.0.1")}, DNSNames: []string{"localhost"},
		}
		der, err := x509.CreateCertificate(rand.Reader, tmpl, caCert, &k.PublicKey, caKey)
		if err != nil {
			t.Fatal(err)
		}
		return der, k
	}
	pemOf := func(typ string, b []byte) []byte { return pem.EncodeToMemory(&pem.Block{Type: typ, Bytes: b}) }

	srvDER, srvKey := issue("notification-service", x509.ExtKeyUsageServerAuth, 2)
	cliDER, cliKey := issue("user-service", x509.ExtKeyUsageClientAuth, 3)
	pool := x509.NewCertPool()
	pool.AddCert(caCert)
	client = &tls.Config{
		MinVersion:   tls.VersionTLS12,
		RootCAs:      pool,
		Certificates: []tls.Certificate{{Certificate: [][]byte{cliDER}, PrivateKey: cliKey}},
	}
	return pemOf("CERTIFICATE", caDER), pemOf("CERTIFICATE", srvDER), pemOf("RSA PRIVATE KEY", x509.MarshalPKCS1PrivateKey(srvKey)), client
}
