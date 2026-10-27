package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/project/shared/infra/storage"
)

// failingUploadStorage is a storage whose writes fail (full or read-only
// volume); every other call is delegated.
type failingUploadStorage struct{ storage.Storage }

func (failingUploadStorage) Upload(context.Context, string, io.Reader, string) error {
	return errors.New("write /data/service_photos/services/x/photo.jpg: read-only file system")
}

func assertPhotoStorageUnavailable(t *testing.T, rec *httptest.ResponseRecorder, step string) {
	t.Helper()
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("%s: expected 503, got %d: %s", step, rec.Code, rec.Body.String())
	}
	var body map[string]string
	_ = json.Unmarshal(rec.Body.Bytes(), &body)
	if body["code"] != ErrCodePhotoStorageUnavailable || body["error"] != "photo storage unavailable" {
		t.Errorf("%s: unexpected body: %s", step, rec.Body.String())
	}
	if bytes.Contains(rec.Body.Bytes(), []byte("read-only")) || bytes.Contains(rec.Body.Bytes(), []byte("/data/")) {
		t.Errorf("%s: storage detail leaked: %s", step, rec.Body.String())
	}
}

// BE-GAPS-FIX item 3: storage not initialized and a failed storage write
// both answer 503 with the one stable code photo_storage_unavailable
// (before: 500 "storage not initialized" / 500 "failed to store photo").
func TestServicePhoto_StorageUnavailable_503StableCode(t *testing.T) {
	u, _, _, ownerToken, customerToken := setupPhotoTestService(t)
	working := u.storage

	// 1. Write fails.
	u.SetStorage(failingUploadStorage{working})
	req := httptest.NewRequest("POST", "/users/services/photo", bytes.NewReader(createTestImage("jpeg")))
	req.Header.Set("Content-Type", "image/jpeg")
	req.Header.Set("Authorization", "Bearer "+ownerToken)
	rec := httptest.NewRecorder()
	u.UploadServicePhoto(rec, req)
	assertPhotoStorageUnavailable(t, rec, "upload with failing write")

	// 2. Storage never initialized: upload and read.
	u.storage = nil
	req = httptest.NewRequest("POST", "/users/services/photo", bytes.NewReader(createTestImage("jpeg")))
	req.Header.Set("Content-Type", "image/jpeg")
	req.Header.Set("Authorization", "Bearer "+ownerToken)
	rec = httptest.NewRecorder()
	u.UploadServicePhoto(rec, req)
	assertPhotoStorageUnavailable(t, rec, "upload without storage")

	getReq := httptest.NewRequest("GET", "/users/services/photo?key=services/x/photo.jpg", nil)
	getReq.Header.Set("Authorization", "Bearer "+customerToken)
	getRec := httptest.NewRecorder()
	u.GetServicePhoto(getRec, getReq)
	assertPhotoStorageUnavailable(t, getRec, "read without storage")
}
