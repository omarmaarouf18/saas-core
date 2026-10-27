package handlers

import (
	"bytes"
	"net/http/httptest"
	"testing"

	"github.com/project/user-service/internal/config"
)

// PROD-PHOTO-STORAGE item 1: without a valid DOCUMENT_ENCRYPTION_KEY the
// service never builds photo storage (no unencrypted or throwaway-key
// photos); upload answers the existing 503 photo_storage_unavailable.
func TestServicePhoto_InvalidEncryptionKey_FailsClosed(t *testing.T) {
	u, _, _, ownerToken, _ := setupPhotoTestService(t)

	for name, key := range map[string]string{
		"empty":     "",
		"not hex":   "not-a-hex-key-zzzz",
		"too short": "00112233445566778899aabbccddeeff",
	} {
		t.Run(name, func(t *testing.T) {
			cfg := &config.Config{
				AppEnv:                "test",
				StorageBaseDir:        t.TempDir(),
				StorageBaseURL:        "/api/v1",
				JWTSecret:             "test-secret",
				DocumentEncryptionKey: key,
			}
			svc := NewUserService(nil, cfg, nil)
			t.Cleanup(svc.Close)
			if svc.storage != nil {
				t.Fatalf("storage was initialized with an unusable key")
			}

			// Same handler path as production: swap the fail-closed nil
			// storage into the fully wired test service.
			u.storage = svc.storage
			req := httptest.NewRequest("POST", "/users/services/photo", bytes.NewReader(createTestImage("jpeg")))
			req.Header.Set("Content-Type", "image/jpeg")
			req.Header.Set("Authorization", "Bearer "+ownerToken)
			rec := httptest.NewRecorder()
			u.UploadServicePhoto(rec, req)
			assertPhotoStorageUnavailable(t, rec, "upload with "+name+" key")
		})
	}

	t.Run("valid key", func(t *testing.T) {
		cfg := &config.Config{
			AppEnv:                "test",
			StorageBaseDir:        t.TempDir(),
			StorageBaseURL:        "/api/v1",
			JWTSecret:             "test-secret",
			DocumentEncryptionKey: "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff",
		}
		svc := NewUserService(nil, cfg, nil)
		t.Cleanup(svc.Close)
		if svc.storage == nil {
			t.Fatal("storage not initialized with a valid key")
		}
	})
}
