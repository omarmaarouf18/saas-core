package fcm

import (
	"context"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

// messagingScope is the OAuth2 scope FCM HTTP v1 requires.
const messagingScope = "https://www.googleapis.com/auth/firebase.messaging"

// defaultTokenURI is used when the key file has no token_uri.
const defaultTokenURI = "https://oauth2.googleapis.com/token" // #nosec G101 -- public Google OAuth2 endpoint URL, not a credential

// tokenRefreshMargin: a cached token is replaced this long before it expires.
const tokenRefreshMargin = 5 * time.Minute

// assertionLifetime is the lifetime of the signed JWT assertion (Google's
// maximum is one hour).
const assertionLifetime = time.Hour

// serviceAccountKey holds the fields of a Google service-account key file
// needed to mint access tokens; any other field is ignored.
type serviceAccountKey struct {
	Type         string `json:"type"`
	ProjectID    string `json:"project_id"`
	PrivateKeyID string `json:"private_key_id"`
	PrivateKey   string `json:"private_key"`
	ClientEmail  string `json:"client_email"`
	TokenURI     string `json:"token_uri"`
}

// tokenSource mints OAuth2 access tokens with the JWT-bearer grant
// (RFC 7523) from a service-account key and caches them until
// tokenRefreshMargin before expiry. Safe for concurrent use: a single mutex
// is held across a mint, so concurrent senders wait for one mint instead of
// each minting their own.
type tokenSource struct {
	httpClient  *http.Client
	clientEmail string
	keyID       string
	key         *rsa.PrivateKey
	tokenURI    string
	now         func() time.Time

	mu      sync.Mutex
	token   string
	expires time.Time
}

// errKeyInvalid wraps every error caused by the key file itself, so callers
// can tell a permanent failure from a transient one. Messages never contain
// key material.
var errKeyInvalid = errors.New("service-account key unusable")

// newTokenSource parses a service-account key. Errors never include key
// material.
func newTokenSource(serviceAccountJSON string, httpClient *http.Client) (*tokenSource, string, error) {
	var sa serviceAccountKey
	if err := json.Unmarshal([]byte(serviceAccountJSON), &sa); err != nil {
		return nil, "", fmt.Errorf("%w: not valid JSON", errKeyInvalid)
	}
	if sa.Type != "service_account" || sa.ClientEmail == "" || sa.PrivateKey == "" {
		return nil, "", fmt.Errorf("%w: needs type service_account, client_email, private_key", errKeyInvalid)
	}
	key, err := parseRSAPrivateKey(sa.PrivateKey)
	if err != nil {
		return nil, "", err
	}
	tokenURI := strings.TrimSpace(sa.TokenURI)
	if tokenURI == "" {
		tokenURI = defaultTokenURI
	}
	if err := checkOutboundURL(tokenURI); err != nil {
		return nil, "", fmt.Errorf("%w: token_uri %v", errKeyInvalid, err)
	}
	return &tokenSource{
		httpClient:  httpClient,
		clientEmail: sa.ClientEmail,
		keyID:       sa.PrivateKeyID,
		key:         key,
		tokenURI:    tokenURI,
		now:         time.Now,
	}, sa.ProjectID, nil
}

// parseRSAPrivateKey accepts a PEM "PRIVATE KEY" (PKCS#8, what Google
// issues) or "RSA PRIVATE KEY" (PKCS#1).
func parseRSAPrivateKey(pemText string) (*rsa.PrivateKey, error) {
	block, _ := pem.Decode([]byte(pemText))
	if block == nil {
		return nil, fmt.Errorf("%w: private_key is not PEM", errKeyInvalid)
	}
	if k, err := x509.ParsePKCS8PrivateKey(block.Bytes); err == nil {
		rsaKey, ok := k.(*rsa.PrivateKey)
		if !ok {
			return nil, fmt.Errorf("%w: private_key is not an RSA key", errKeyInvalid)
		}
		return rsaKey, nil
	}
	if k, err := x509.ParsePKCS1PrivateKey(block.Bytes); err == nil {
		return k, nil
	}
	return nil, fmt.Errorf("%w: private_key cannot be parsed", errKeyInvalid)
}

// checkOutboundURL refuses a URL that would send credentials in clear text:
// it must be https, or http only to a loopback host (tests, local fakes).
func checkOutboundURL(raw string) error {
	u, err := url.Parse(raw)
	if err != nil || u.Host == "" {
		return errors.New("is not an absolute URL")
	}
	switch u.Scheme {
	case "https":
		return nil
	case "http":
		host := u.Hostname()
		if host == "localhost" {
			return nil
		}
		if ip := net.ParseIP(host); ip != nil && ip.IsLoopback() {
			return nil
		}
		return errors.New("must use https (http is allowed only for loopback hosts)")
	}
	return errors.New("must use https")
}

// Token returns a cached access token, minting a new one when none is
// cached or the cached one expires within tokenRefreshMargin.
func (s *tokenSource) Token(ctx context.Context) (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.token != "" && s.now().Add(tokenRefreshMargin).Before(s.expires) {
		return s.token, nil
	}
	token, expires, err := s.mint(ctx)
	if err != nil {
		return "", err
	}
	s.token, s.expires = token, expires
	return token, nil
}

// Invalidate drops the cached token if it is still the given one (another
// goroutine may already have replaced it after its own 401).
func (s *tokenSource) Invalidate(token string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.token == token {
		s.token, s.expires = "", time.Time{}
	}
}

// tokenError is a failed token exchange. Its message carries only the HTTP
// status and Google's short error code / description, never the assertion.
type tokenError struct {
	Status    int
	Permanent bool // 4xx: the key or grant is wrong, retrying will not help
	Detail    string
}

func (e *tokenError) Error() string {
	if e.Detail == "" {
		return fmt.Sprintf("token endpoint returned HTTP %d", e.Status)
	}
	return fmt.Sprintf("token endpoint returned HTTP %d: %s", e.Status, e.Detail)
}

func (s *tokenSource) mint(ctx context.Context) (string, time.Time, error) {
	now := s.now()
	assertion, err := s.signAssertion(now)
	if err != nil {
		return "", time.Time{}, err
	}
	form := url.Values{
		"grant_type": {"urn:ietf:params:oauth:grant-type:jwt-bearer"},
		"assertion":  {assertion},
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, s.tokenURI, strings.NewReader(form.Encode()))
	if err != nil {
		return "", time.Time{}, errors.New("cannot build token request")
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return "", time.Time{}, fmt.Errorf("token request failed: %s", safeTransportError(err))
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 64<<10))

	var tr struct {
		AccessToken      string `json:"access_token"`
		ExpiresIn        int64  `json:"expires_in"`
		Error            string `json:"error"`
		ErrorDescription string `json:"error_description"`
	}
	_ = json.Unmarshal(body, &tr)

	if resp.StatusCode != http.StatusOK {
		return "", time.Time{}, &tokenError{
			Status:    resp.StatusCode,
			Permanent: resp.StatusCode >= 400 && resp.StatusCode < 500 && resp.StatusCode != http.StatusTooManyRequests,
			Detail:    truncate(strings.TrimSpace(tr.Error+" "+tr.ErrorDescription), 200),
		}
	}
	if tr.AccessToken == "" {
		return "", time.Time{}, errors.New("token endpoint returned no access_token")
	}
	if tr.ExpiresIn <= 0 {
		tr.ExpiresIn = 3600
	}
	return tr.AccessToken, now.Add(time.Duration(tr.ExpiresIn) * time.Second), nil
}

// signAssertion builds the RS256-signed JWT the token endpoint exchanges
// for an access token.
func (s *tokenSource) signAssertion(now time.Time) (string, error) {
	header := map[string]string{"alg": "RS256", "typ": "JWT"}
	if s.keyID != "" {
		header["kid"] = s.keyID
	}
	claims := map[string]any{
		"iss":   s.clientEmail,
		"scope": messagingScope,
		"aud":   s.tokenURI,
		"iat":   now.Unix(),
		"exp":   now.Add(assertionLifetime).Unix(),
	}
	h, err := json.Marshal(header)
	if err != nil {
		return "", err
	}
	c, err := json.Marshal(claims)
	if err != nil {
		return "", err
	}
	enc := base64.RawURLEncoding
	signingInput := enc.EncodeToString(h) + "." + enc.EncodeToString(c)
	digest := sha256.Sum256([]byte(signingInput))
	sig, err := rsa.SignPKCS1v15(rand.Reader, s.key, crypto.SHA256, digest[:])
	if err != nil {
		return "", errors.New("cannot sign token assertion")
	}
	return signingInput + "." + enc.EncodeToString(sig), nil
}

// safeTransportError reduces a transport error to a message without the
// request URL's query or body (it never contains them, but url.Error
// prints the full URL).
func safeTransportError(err error) string {
	var ue *url.Error
	if errors.As(err, &ue) {
		return ue.Err.Error()
	}
	return err.Error()
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "..."
}
