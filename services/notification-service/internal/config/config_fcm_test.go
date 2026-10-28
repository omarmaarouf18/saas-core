package config

import (
	"bytes"
	"encoding/base64"
	"log"
	"os"
	"strings"
	"testing"
)

// fakeKeyMaterial must never appear in a status or log line.
const fakeKeyMaterial = "TESTKEYMATERIAL0123456789"

const fakeServiceAccount = `{"type":"service_account","project_id":"qd-test","client_email":"push@qd-test.iam.gserviceaccount.com",` +
	`"private_key":"-----BEGIN PRIVATE KEY-----\n` + fakeKeyMaterial + `\n-----END PRIVATE KEY-----\n"}`

// PROD-PHOTO-STORAGE item 8: FCM credentials from FCM_SERVICE_ACCOUNT_JSON_B64
// (and the existing raw-JSON variables); an unusable key disables push but
// never fails startup; the status line never shows key material.
func TestLoad_FCM(t *testing.T) {
	for k, v := range map[string]string{
		"JWT_SECRET": "secret", "INTERNAL_SERVICE_TOKEN": "token", "TLS_CERT_PATH": "/c",
		"TLS_KEY_PATH": "/k", "TLS_CA_PATH": "/ca", "REDIS_URI": "redis://localhost:6379",
	} {
		t.Setenv(k, v)
	}
	b64 := base64.StdEncoding.EncodeToString([]byte(fakeServiceAccount))
	// `base64` without -w0 wraps at 76 columns.
	var wrapped strings.Builder
	for i := 0; i < len(b64); i += 76 {
		wrapped.WriteString(b64[i:min(i+76, len(b64))] + "\n")
	}

	cases := []struct {
		name                    string
		env                     map[string]string
		wantStatus, wantProject string
		wantJSON                bool
		wantEndpoint            string
	}{
		{"nothing set", nil, "push disabled: no FCM service-account key (set FCM_SERVICE_ACCOUNT_JSON_B64)", "", false, ""},
		{"b64, project from the key", map[string]string{"FCM_SERVICE_ACCOUNT_JSON_B64": b64}, "push key loaded (project qd-test)", "qd-test", true, ""},
		{"b64 wrapped, explicit project", map[string]string{"FCM_SERVICE_ACCOUNT_JSON_B64": wrapped.String(), "FCM_PROJECT_ID": "qd-prod"}, "push key loaded (project qd-prod)", "qd-prod", true, ""},
		{"b64 unpadded", map[string]string{"FCM_SERVICE_ACCOUNT_JSON_B64": strings.TrimRight(b64, "=")}, "push key loaded (project qd-test)", "qd-test", true, ""},
		{"raw FCM_SERVICE_ACCOUNT_JSON still works", map[string]string{"FCM_SERVICE_ACCOUNT_JSON": fakeServiceAccount}, "push key loaded (project qd-test)", "qd-test", true, ""},
		{"raw FCM_CREDENTIALS_JSON still works", map[string]string{"FCM_CREDENTIALS_JSON": fakeServiceAccount, "FCM_PROJECT_ID": "qd-x"}, "push key loaded (project qd-x)", "qd-x", true, ""},
		{"invalid base64", map[string]string{"FCM_SERVICE_ACCOUNT_JSON_B64": "!!" + fakeKeyMaterial + "!!", "FCM_PROJECT_ID": "qd-test"}, "push disabled: FCM_SERVICE_ACCOUNT_JSON_B64 is not valid base64", "", false, ""},
		{"base64 of non-JSON", map[string]string{"FCM_SERVICE_ACCOUNT_JSON_B64": base64.StdEncoding.EncodeToString([]byte("not json " + fakeKeyMaterial))}, "push disabled: FCM_SERVICE_ACCOUNT_JSON_B64 is not valid JSON", "", false, ""},
		{"JSON but not a service account", map[string]string{"FCM_SERVICE_ACCOUNT_JSON_B64": base64.StdEncoding.EncodeToString([]byte(`{"type":"authorized_user","private_key":"` + fakeKeyMaterial + `"}`))}, "push disabled: FCM_SERVICE_ACCOUNT_JSON_B64 is not a service-account key (needs type service_account, client_email, private_key)", "", false, ""},
		{"key without any project", map[string]string{"FCM_SERVICE_ACCOUNT_JSON": strings.Replace(fakeServiceAccount, `"project_id":"qd-test",`, "", 1)}, "push disabled: no FCM_PROJECT_ID and no project_id in FCM_SERVICE_ACCOUNT_JSON", "", false, ""},
		{"project only, no key", map[string]string{"FCM_PROJECT_ID": "qd-test"}, "push disabled: no FCM service-account key (set FCM_SERVICE_ACCOUNT_JSON_B64)", "", false, ""},
		{"internal relay needs no key", map[string]string{"FCM_ENDPOINT_URL": "https://relay.internal/send"}, "push enabled (internal relay FCM_ENDPOINT_URL)", "", false, "https://relay.internal/send"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			for _, k := range []string{"FCM_SERVICE_ACCOUNT_JSON", "FCM_CREDENTIALS_JSON", "FCM_SERVICE_ACCOUNT_JSON_B64", "FCM_PROJECT_ID", "FCM_ENDPOINT_URL"} {
				t.Setenv(k, tc.env[k])
			}
			var logs bytes.Buffer
			log.SetOutput(&logs)
			t.Cleanup(func() { log.SetOutput(os.Stderr) })

			cfg, err := Load()
			if err != nil {
				t.Fatalf("Load must not fail on FCM settings: %v", err)
			}
			if cfg.FCMStatus != tc.wantStatus {
				t.Errorf("status = %q, want %q", cfg.FCMStatus, tc.wantStatus)
			}
			if cfg.FCMProjectID != tc.wantProject || cfg.FCMEndpointURL != tc.wantEndpoint {
				t.Errorf("project/endpoint = %q/%q, want %q/%q", cfg.FCMProjectID, cfg.FCMEndpointURL, tc.wantProject, tc.wantEndpoint)
			}
			if tc.wantJSON != (cfg.FCMServiceAccountJSON == fakeServiceAccount) {
				t.Errorf("service account JSON loaded = %v, want %v", cfg.FCMServiceAccountJSON == fakeServiceAccount, tc.wantJSON)
			}
			if !tc.wantJSON && tc.wantEndpoint == "" && cfg.FCMServiceAccountJSON != "" {
				t.Errorf("disabled push kept credential material")
			}
			if !strings.Contains(logs.String(), "[CONFIG] "+tc.wantStatus) {
				t.Errorf("status not logged; log: %q", logs.String())
			}
			for _, out := range []string{cfg.FCMStatus, logs.String()} {
				if strings.Contains(out, fakeKeyMaterial) || strings.Contains(out, "PRIVATE KEY") || strings.Contains(out, "push@qd-test") {
					t.Errorf("credential material leaked: %q", out)
				}
			}
		})
	}
}
