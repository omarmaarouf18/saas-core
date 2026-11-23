package handlers

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/project/chat-service/internal/config"
)

// brokenStorageConfig makes storage.NewLocalStorageWithPath fail outside
// local/test: the encryption key is not hex, so createDocAEAD refuses it.
func brokenStorageConfig(t *testing.T) *config.Config {
	t.Helper()
	return &config.Config{
		AppEnv:                  "production",
		AllowedOrigin:           "http://localhost:3000",
		StorageBaseDir:          t.TempDir(),
		StorageBaseURL:          "/api/v1",
		AttachmentEncryptionKey: "not-a-hex-key-zzzz",
		AttachmentSigningSecret: "signing-secret",
	}
}

// KEY-FAILFAST item 1: a failed storage init must leave chatStorage as a true
// nil interface, never a typed-nil *LocalStorage. Before the fix
// `chatStorage, _ = storage.NewLocalStorageWithPath(...)` stored a typed nil
// and `c.storage != nil` was true.
func TestNewChat_StorageInitFailureLeavesNilInterface(t *testing.T) {
	c := NewChat(nil, nil, brokenStorageConfig(t), nil)

	if c.storage != nil {
		t.Fatalf("storage = %#v, want a nil interface after storage init failure", c.storage)
	}
}

func assertAttachmentStorageUnavailable(t *testing.T, rec *httptest.ResponseRecorder, step string) {
	t.Helper()
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("%s: expected 503, got %d: %s", step, rec.Code, rec.Body.String())
	}
	var body map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("%s: response is not JSON: %v (%s)", step, err, rec.Body.String())
	}
	if body["code"] != "attachment_storage_unavailable" || body["error"] != "attachment storage unavailable" {
		t.Errorf("%s: unexpected body: %s", step, rec.Body.String())
	}
	if strings.Contains(rec.Body.String(), "not-a-hex-key-zzzz") {
		t.Errorf("%s: response leaks the key: %s", step, rec.Body.String())
	}
}

// KEY-FAILFAST item 1: with storage unavailable, attachment upload and view
// answer 503 attachment_storage_unavailable instead of dereferencing a
// typed-nil *LocalStorage. Before the fix the view path panicked.
func TestAttachmentHandlers_StorageUnavailable_503(t *testing.T) {
	c := NewChat(nil, nil, brokenStorageConfig(t), nil)

	uploadReq := httptest.NewRequest(http.MethodPost, "/chat/tickets/t1/attachment", strings.NewReader("ignored"))
	uploadRec := httptest.NewRecorder()
	c.UploadTicketAttachment(uploadRec, uploadReq)
	assertAttachmentStorageUnavailable(t, uploadRec, "upload")

	viewReq := httptest.NewRequest(http.MethodGet, "/chat/attachments/view?token=whatever", nil)
	viewRec := httptest.NewRecorder()
	c.ViewAttachment(viewRec, viewReq)
	assertAttachmentStorageUnavailable(t, viewRec, "view")
}
