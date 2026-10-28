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
	"io"
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

// TestPushL10N_DeviceLanguagePerToken (PUSH-L10N item 6) runs the real
// auth-service and notification-service binaries, built from this checkout,
// over mTLS, against a fake Google OAuth2 endpoint and a fake FCM HTTP v1
// API. One user registers three device tokens through auth-service
// POST /auth/device-token: an Arabic phone (locale "ar"), an English tablet
// ("en_US", normalized to "en") and an old app (no locale). user-service's
// job_accepted payload (title/body in English plus params.fare, exactly as
// broadcastCourierAccepted builds it) is posted to notification-service,
// which reads the tokens and their locales from auth-service and pushes.
// Each fake FCM message must be in its token's language with the fare in
// EGP / ج.م; the old app keeps the English text; no message quotes "$".
//
// The accept flow itself (user-service dispatch) is not run here: the
// payload is the one user-service's unit test pins. Like
// TestPushBE_NotificationServiceDeliversViaFCMOAuth it uses the staging Redis
// and Mongo (throwaway databases, dropped afterwards) and skips when they are
// unreachable.
func TestPushL10N_DeviceLanguagePerToken(t *testing.T) {
	if _, err := exec.LookPath("go"); err != nil {
		t.Skip("go toolchain not on PATH")
	}
	cfg := LoadConfig()
	if opts, err := redis.ParseURL(cfg.RedisURI); err != nil {
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
	suffix := time.Now().UnixNano()
	authDB, notifDB := fmt.Sprintf("push_l10n_auth_%d", suffix), fmt.Sprintf("push_l10n_notif_%d", suffix)
	mc, err := mongo.Connect(options.Client().ApplyURI(cfg.MongoURI))
	if err == nil {
		pingCtx, cancelPing := context.WithTimeout(context.Background(), 5*time.Second)
		err = mc.Ping(pingCtx, nil)
		cancelPing()
	}
	if err != nil {
		t.Skipf("staging Mongo unreachable (%v): start the staging stack", err)
	}
	t.Cleanup(func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = mc.Database(authDB).Drop(ctx)
		_ = mc.Database(notifDB).Drop(ctx)
		_ = mc.Disconnect(ctx)
	})
	tmp := t.TempDir()

	// Build both services from this checkout.
	bins := map[string]string{}
	for _, svc := range []string{"auth-service", "notification-service"} {
		bin := filepath.Join(tmp, svc)
		build := exec.Command("go", "build", "-o", bin, "./cmd")
		build.Dir = filepath.Join("..", "..", "services", svc)
		if out, err := build.CombinedOutput(); err != nil {
			t.Fatalf("build %s: %v\n%s", svc, err, out)
		}
		bins[svc] = bin
	}

	// Throwaway service-account key and fake Google token endpoint.
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	der, _ := x509.MarshalPKCS8PrivateKey(key)
	tokenSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = r.ParseForm()
		if r.PostForm.Get("grant_type") != "urn:ietf:params:oauth:grant-type:jwt-bearer" {
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"access_token": "l10n-access", "expires_in": 3600})
	}))
	defer tokenSrv.Close()
	saJSON, _ := json.Marshal(map[string]string{
		"type": "service_account", "project_id": "qd-l10n", "private_key_id": "kid-l10n",
		"private_key":  string(pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der})),
		"client_email": "fcm@qd-l10n.iam.gserviceaccount.com", "token_uri": tokenSrv.URL,
	})

	// Fake FCM API: records each message by device token.
	type fcmMessage struct {
		Token        string            `json:"token"`
		Notification map[string]string `json:"notification"`
		Data         map[string]string `json:"data"`
	}
	var mu sync.Mutex
	var fcmCalls []fcmMessage
	fcmSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var c struct {
			Message fcmMessage `json:"message"`
		}
		_ = json.NewDecoder(r.Body).Decode(&c)
		mu.Lock()
		fcmCalls = append(fcmCalls, c.Message)
		mu.Unlock()
		_, _ = w.Write([]byte(`{"name":"projects/qd-l10n/messages/1"}`))
	}))
	defer fcmSrv.Close()

	// mTLS: one CA; each service's certificate serves and dials (the
	// services call each other with it); the test dials with its own.
	ca := newL10nCA(t)
	for _, name := range []string{"auth", "notif"} {
		certPEM, keyPEM := ca.issue(t, name)
		if err := os.WriteFile(filepath.Join(tmp, name+".crt"), certPEM, 0o600); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(tmp, name+".key"), keyPEM, 0o600); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(filepath.Join(tmp, "ca.crt"), ca.pem, 0o600); err != nil {
		t.Fatal(err)
	}
	client := &http.Client{Timeout: 5 * time.Second, Transport: &http.Transport{TLSClientConfig: ca.clientTLS(t)}}

	authPort, notifPort := freePort(t), freePort(t)
	authBase := fmt.Sprintf("https://127.0.0.1:%d", authPort)
	notifBase := fmt.Sprintf("https://127.0.0.1:%d", notifPort)
	const internalToken = "l10n-internal-token"
	common := []string{
		"PATH=" + os.Getenv("PATH"),
		"JWT_SECRET=" + cfg.JWTSecret,
		"INTERNAL_SERVICE_TOKEN=" + internalToken,
		"TLS_CA_PATH=" + filepath.Join(tmp, "ca.crt"),
		"REDIS_URI=" + cfg.RedisURI,
		"MONGO_URI=" + cfg.MongoURI,
		"APP_ENV=local",
	}
	tlsEnv := func(name string) []string {
		return []string{
			"TLS_CERT_PATH=" + filepath.Join(tmp, name+".crt"),
			"TLS_KEY_PATH=" + filepath.Join(tmp, name+".key"),
		}
	}
	authEnv := append(append([]string{
		"PORT=" + fmt.Sprint(authPort),
		"AUTH_MONGO_DATABASE=" + authDB,
		"DOCUMENT_SIGNING_SECRET=l10n-document-signing-secret-32-bytes",
		"GATEWAY_SECRET=l10n-gateway-secret",
		"STORAGE_BASE_DIR=" + filepath.Join(tmp, "storage"),
		"NOTIFICATION_SERVICE_URL=" + notifBase,
		"USER_SERVICE_URL=https://127.0.0.1:1",
		// auth-service refuses to start without a Resend dispatcher; this
		// test sends no OTP, so the key is a placeholder never used.
		"RESEND_API_KEY=re_push_l10n_placeholder_not_used",
		"RESEND_FROM_EMAIL=push-l10n@staging.local",
	}, common...), tlsEnv("auth")...)
	notifEnv := append(append([]string{
		"PORT=" + fmt.Sprint(notifPort),
		"NOTIFICATION_MONGO_DATABASE=" + notifDB,
		"AUTH_SERVICE_URL=" + authBase,
		"FCM_SERVICE_ACCOUNT_JSON_B64=" + base64.StdEncoding.EncodeToString(saJSON),
		"FCM_API_BASE_URL=" + fcmSrv.URL,
	}, common...), tlsEnv("notif")...)

	var authLogs, notifLogs safeBuffer
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	start := func(bin string, env []string, logs *safeBuffer, base string) *exec.Cmd {
		t.Helper()
		cmd := exec.CommandContext(ctx, bin)
		cmd.Env = env
		cmd.Stdout, cmd.Stderr = logs, logs
		if err := cmd.Start(); err != nil {
			t.Fatal(err)
		}
		deadline := time.Now().Add(30 * time.Second)
		for {
			resp, err := client.Get(base + "/health")
			if err == nil {
				_ = resp.Body.Close()
				if resp.StatusCode == http.StatusOK {
					return cmd
				}
			}
			if time.Now().After(deadline) {
				t.Fatalf("%s did not become healthy: %v\n%s", filepath.Base(bin), err, logs.String())
			}
			time.Sleep(200 * time.Millisecond)
		}
	}
	authCmd := start(bins["auth-service"], authEnv, &authLogs, authBase)
	defer func() { cancel(); _ = authCmd.Wait() }()
	notifCmd := start(bins["notification-service"], notifEnv, &notifLogs, notifBase)
	defer func() { cancel(); _ = notifCmd.Wait() }()

	// One customer with three devices. Seeded in the owner's tenant, as
	// SeedCustomer does for the other journeys: history (and SSE) filter by
	// the reader's tenant, and job notifications carry the owner's (see
	// docs/worklog/PUSH-L10N.md, follow-ups). The push path does not depend
	// on it.
	const tenantID = "owner-l10n"
	userID := fmt.Sprintf("cust-l10n-%d", suffix)
	email := userID + "@staging.local"
	seedCtx, cancelSeed := context.WithTimeout(context.Background(), 5*time.Second)
	_, err = mc.Database(authDB).Collection("users").InsertOne(seedCtx, map[string]any{
		"_id": userID, "email": email, "username": userID, "role": "user", "tenant_id": tenantID,
		"is_active": true, "account_status": "active", "created_at": time.Now().UTC(),
	})
	cancelSeed()
	if err != nil {
		t.Fatalf("seed user: %v", err)
	}
	jwt, err := cfg.GenerateJWT(userID, "user", tenantID, email)
	if err != nil {
		t.Fatal(err)
	}

	post := func(url string, header map[string]string, payload any) (int, string) {
		t.Helper()
		b, _ := json.Marshal(payload)
		req, _ := http.NewRequest(http.MethodPost, url, bytes.NewReader(b))
		req.Header.Set("Content-Type", "application/json")
		for k, v := range header {
			req.Header.Set(k, v)
		}
		resp, err := client.Do(req)
		if err != nil {
			t.Fatalf("POST %s: %v", url, err)
		}
		defer resp.Body.Close()
		body, _ := io.ReadAll(resp.Body)
		return resp.StatusCode, string(body)
	}
	bearer := map[string]string{"Authorization": "Bearer " + jwt}
	for _, reg := range []map[string]string{
		{"token": "l10n-phone-ar", "platform": "android", "locale": "ar"},
		{"token": "l10n-tablet-en", "platform": "android", "locale": "en_US"},
		{"token": "l10n-old-app", "platform": "android"},
	} {
		if code, body := post(authBase+"/auth/device-token", bearer, reg); code != http.StatusOK {
			t.Fatalf("register %v: HTTP %d %s\n%s", reg, code, body, authLogs.String())
		}
	}
	if code, _ := post(authBase+"/auth/device-token", bearer, map[string]string{"token": "l10n-fr", "locale": "fr"}); code != http.StatusBadRequest {
		t.Errorf("locale fr: HTTP %d, want 400", code)
	}

	waitPushes := func(n int) map[string]fcmMessage {
		t.Helper()
		deadline := time.Now().Add(15 * time.Second)
		for {
			mu.Lock()
			got := len(fcmCalls)
			mu.Unlock()
			if got >= n {
				break
			}
			if time.Now().After(deadline) {
				t.Fatalf("%d of %d pushes sent\nnotification-service:\n%s", got, n, notifLogs.String())
			}
			time.Sleep(100 * time.Millisecond)
		}
		time.Sleep(300 * time.Millisecond) // no extra push may follow
		mu.Lock()
		defer mu.Unlock()
		if len(fcmCalls) != n {
			t.Errorf("%d pushes, want %d: %+v", len(fcmCalls), n, fcmCalls)
		}
		out := map[string]fcmMessage{}
		for _, c := range fcmCalls {
			out[c.Token] = c
		}
		fcmCalls = nil
		return out
	}
	internal := map[string]string{"X-Internal-Token": internalToken}
	jobID := fmt.Sprintf("job-l10n-%d", suffix)

	cases := []struct {
		name    string
		payload map[string]any
		want    map[string][2]string // token -> title, body
	}{
		{
			name: "job_accepted, final fare",
			payload: map[string]any{
				"type": "job_accepted", "tenant_id": tenantID, "user_id": userID, "job_id": jobID,
				"title": "Courier Assigned", "body": "Your courier has accepted! Final fare: EGP 1,250.50",
				"roles": []string{"client", "user"}, "params": map[string]string{"fare": "1250.50"},
			},
			want: map[string][2]string{
				"l10n-phone-ar":  {"مندوب قبل طلبك", "الأجرة النهائية: 1,250.50 ج.م."},
				"l10n-tablet-en": {"A courier accepted your order", "Final fare: EGP 1,250.50."},
				"l10n-old-app":   {"Courier Assigned", "Your courier has accepted! Final fare: EGP 1,250.50"},
			},
		},
		{
			name: "job_accepted, negotiable whole fare",
			payload: map[string]any{
				"type": "job_accepted", "tenant_id": tenantID, "user_id": userID, "job_id": jobID,
				"title": "Courier Assigned", "body": "Your courier has accepted! Suggested fare: EGP 40. Counter-offer review is now open.",
				"roles": []string{"client", "user"}, "params": map[string]string{"fare": "40.00", "variant": "negotiable"},
			},
			want: map[string][2]string{
				"l10n-phone-ar":  {"مندوب قبل طلبك", "الأجرة المقترحة: 40 ج.م. تقدر ترد على العرض دلوقتي."},
				"l10n-tablet-en": {"A courier accepted your order", "Suggested fare: EGP 40. You can answer the offer now."},
				"l10n-old-app":   {"Courier Assigned", "Your courier has accepted! Suggested fare: EGP 40. Counter-offer review is now open."},
			},
		},
	}
	for _, c := range cases {
		if code, body := post(notifBase+"/notifications/send", internal, c.payload); code != http.StatusOK {
			t.Fatalf("%s: send HTTP %d %s", c.name, code, body)
		}
		got := waitPushes(len(c.want))
		for token, w := range c.want {
			m, ok := got[token]
			if !ok {
				t.Errorf("%s: no push to %s", c.name, token)
				continue
			}
			if m.Notification["title"] != w[0] || m.Notification["body"] != w[1] {
				t.Errorf("%s, %s:\n got  %q / %q\n want %q / %q", c.name, token,
					m.Notification["title"], m.Notification["body"], w[0], w[1])
			}
			if strings.Contains(m.Notification["body"], "$") {
				t.Errorf("%s, %s: body quotes $: %q", c.name, token, m.Notification["body"])
			}
			if m.Data["type"] != "job_accepted" || m.Data["job_id"] != jobID {
				t.Errorf("%s, %s: data %v", c.name, token, m.Data)
			}
		}
	}

	// The history (read with the user's JWT, resolved at auth-service)
	// carries the params and both languages.
	req, _ := http.NewRequest(http.MethodGet, notifBase+"/notifications/history?limit=5", nil)
	req.Header.Set("Authorization", "Bearer "+jwt)
	resp, err := client.Do(req)
	if err != nil {
		t.Fatalf("history: %v", err)
	}
	defer resp.Body.Close()
	var hist struct {
		Notifications []struct {
			Body  string                       `json:"body"`
			Texts map[string]map[string]string `json:"texts"`
		} `json:"notifications"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&hist); err != nil || resp.StatusCode != http.StatusOK {
		t.Fatalf("history: HTTP %d, %v", resp.StatusCode, err)
	}
	var found bool
	for _, it := range hist.Notifications {
		if it.Body == "Your courier has accepted! Final fare: EGP 1,250.50" {
			found = true
			if it.Texts["ar"]["body"] != "الأجرة النهائية: 1,250.50 ج.م." || it.Texts["en"]["body"] != "Final fare: EGP 1,250.50." {
				t.Errorf("history texts: %v", it.Texts)
			}
		}
	}
	if !found {
		t.Errorf("history lacks the job_accepted item: %+v", hist.Notifications)
	}
}

func freePort(t *testing.T) int {
	t.Helper()
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer l.Close()
	return l.Addr().(*net.TCPAddr).Port
}

// l10nCA issues certificates usable both as server and as client
// certificate, as the services' own certificates are.
type l10nCA struct {
	cert *x509.Certificate
	key  *rsa.PrivateKey
	pem  []byte
	next int64
}

func newL10nCA(t *testing.T) *l10nCA {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	tmpl := &x509.Certificate{
		SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: "push-l10n-ca"},
		NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().Add(time.Hour),
		IsCA: true, BasicConstraintsValid: true, KeyUsage: x509.KeyUsageCertSign,
	}
	der, err := x509.CreateCertificate(rand.Reader, tmpl, tmpl, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	cert, _ := x509.ParseCertificate(der)
	return &l10nCA{cert: cert, key: key, pem: pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}), next: 2}
}

func (ca *l10nCA) issueRaw(t *testing.T, cn string) ([]byte, *rsa.PrivateKey) {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	ca.next++
	tmpl := &x509.Certificate{
		SerialNumber: big.NewInt(ca.next), Subject: pkix.Name{CommonName: cn},
		NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().Add(time.Hour),
		KeyUsage:    x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment,
		ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth, x509.ExtKeyUsageClientAuth},
		IPAddresses: []net.IP{net.ParseIP("127.0.0.1")}, DNSNames: []string{"localhost"},
	}
	der, err := x509.CreateCertificate(rand.Reader, tmpl, ca.cert, &key.PublicKey, ca.key)
	if err != nil {
		t.Fatal(err)
	}
	return der, key
}

func (ca *l10nCA) issue(t *testing.T, cn string) (certPEM, keyPEM []byte) {
	der, key := ca.issueRaw(t, cn)
	return pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}),
		pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(key)})
}

func (ca *l10nCA) clientTLS(t *testing.T) *tls.Config {
	der, key := ca.issueRaw(t, "e2e-client")
	pool := x509.NewCertPool()
	pool.AddCert(ca.cert)
	return &tls.Config{
		MinVersion:   tls.VersionTLS12,
		RootCAs:      pool,
		Certificates: []tls.Certificate{{Certificate: [][]byte{der}, PrivateKey: key}},
	}
}
