package storage

import (
	"bytes"
	"context"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestLocalStorage(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "storage-test-*")
	if err != nil {
		t.Fatalf("failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	secret := "super-secret-jwt-key-32-bytes-long!!"
	encKey := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef" // 64 hex chars
	store, err := NewLocalStorage(tempDir, "http://localhost:8080", secret, encKey, "test")
	if err != nil {
		t.Fatalf("failed to create LocalStorage: %v", err)
	}

	ctx := context.Background()

	// 1. Test Upload success
	fileContent := "test document binary content"
	key := "tenant-1/docs/id_front.jpg"
	err = store.Upload(ctx, key, strings.NewReader(fileContent), "image/jpeg")
	if err != nil {
		t.Fatalf("Upload failed: %v", err)
	}

	// 2. Test Upload directory traversal protection
	err = store.Upload(ctx, "../../../etc/passwd", strings.NewReader("bad content"), "text/plain")
	if err == nil {
		t.Fatalf("expected upload directory traversal to be rejected, got nil")
	}

	// 3. Test OpenFile success
	rc, err := store.OpenFile(key)
	if err != nil {
		t.Fatalf("OpenFile failed: %v", err)
	}
	defer rc.Close()

	readBytes, err := io.ReadAll(rc)
	if err != nil {
		t.Fatalf("failed to read file content: %v", err)
	}
	if string(readBytes) != fileContent {
		t.Errorf("Expected content %q, got %q", fileContent, string(readBytes))
	}

	// 4. Test OpenFile non-existent file
	_, err = store.OpenFile("tenant-1/docs/non-existent.png")
	if err == nil {
		t.Errorf("Expected error for non-existent file, got nil")
	}

	// 5. Test OpenFile directory traversal protection
	_, err = store.OpenFile("../../etc/passwd")
	if err == nil {
		t.Errorf("Expected error for directory traversal open, got nil")
	}

	// 6. Test Signed URL Generation & Validation
	signedURL, err := store.GetSignedURL(ctx, key, 5*time.Minute)
	if err != nil {
		t.Fatalf("GetSignedURL failed: %v", err)
	}
	if !strings.Contains(signedURL, "http://localhost:8080/auth/documents/view?token=") {
		t.Errorf("Unexpected signed URL format: %s", signedURL)
	}

	tokenStr := strings.TrimPrefix(signedURL, "http://localhost:8080/auth/documents/view?token=")
	valKey, err := store.ValidateSignedURLToken(tokenStr)
	if err != nil {
		t.Fatalf("ValidateSignedURLToken failed: %v", err)
	}
	if valKey != key {
		t.Errorf("Expected key %q, got %q", key, valKey)
	}

	// 7. Test Expired Signed URL Token
	expiredSignedURL, err := store.GetSignedURL(ctx, key, -1*time.Minute)
	if err != nil {
		t.Fatalf("GetSignedURL failed for expired token test: %v", err)
	}
	expiredTokenStr := strings.TrimPrefix(expiredSignedURL, "http://localhost:8080/auth/documents/view?token=")
	_, err = store.ValidateSignedURLToken(expiredTokenStr)
	if err == nil {
		t.Errorf("Expected error validating expired token, got nil")
	}

	// 8. Test Invalid Signature Token
	otherStore, _ := NewLocalStorage(tempDir, "http://localhost:8080", "different-secret-key-32-bytes!!", encKey, "test")
	_, err = otherStore.ValidateSignedURLToken(tokenStr)
	if err == nil {
		t.Errorf("Expected error validating token signed with wrong secret, got nil")
	}
}

func TestLocalStorage_EncryptionRoundTripAndDiskVerification(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "storage-enc-test-*")
	if err != nil {
		t.Fatalf("failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	secret := "super-secret-jwt-key-32-bytes-long!!"
	encKey := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
	store, err := NewLocalStorage(tempDir, "http://localhost:8080", secret, encKey, "test")
	if err != nil {
		t.Fatalf("failed to create LocalStorage: %v", err)
	}

	ctx := context.Background()

	// Recognizable JPEG header + payload
	jpegHeader := []byte{0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01}
	plaintext := append(jpegHeader, []byte("CONFIDENTIAL-IDENTITY-DOCUMENT-PAYLOAD-12345")...)
	key := "kyb/tenant-99/id_card.jpg"

	// 1. Upload encrypted file
	if err := store.Upload(ctx, key, bytes.NewReader(plaintext), "image/jpeg"); err != nil {
		t.Fatalf("Upload failed: %v", err)
	}

	// 2. OpenFile transparent decryption round-trip
	rc, err := store.OpenFile(key)
	if err != nil {
		t.Fatalf("OpenFile failed: %v", err)
	}
	defer rc.Close()

	decryptedBytes, err := io.ReadAll(rc)
	if err != nil {
		t.Fatalf("ReadAll failed: %v", err)
	}
	if !bytes.Equal(decryptedBytes, plaintext) {
		t.Fatalf("Decrypted bytes do not match original plaintext! Round-trip failed")
	}

	// 3. Inspect raw disk file to verify actual encryption at rest
	diskFilePath := filepath.Join(tempDir, key)
	diskBytes, err := os.ReadFile(diskFilePath)
	if err != nil {
		t.Fatalf("Failed to read raw disk file: %v", err)
	}

	// Disk file size must be larger than plaintext due to nonce + GCM tag
	if len(diskBytes) <= len(plaintext) {
		t.Errorf("Expected raw disk size (%d) to exceed plaintext size (%d) due to GCM overhead", len(diskBytes), len(plaintext))
	}

	// Disk file must NOT start with the JPEG header
	if bytes.HasPrefix(diskBytes, jpegHeader) {
		t.Errorf("SECURITY CRITICAL: Raw disk file starts with unencrypted JPEG header! Encryption at rest failed!")
	}

	// Disk file must NOT contain the plaintext secret string
	if bytes.Contains(diskBytes, []byte("CONFIDENTIAL-IDENTITY-DOCUMENT-PAYLOAD-12345")) {
		t.Errorf("SECURITY CRITICAL: Raw disk file contains raw plaintext payload string!")
	}
}

func TestLocalStorage_ProductionModeMissingKey(t *testing.T) {
	tempDir := t.TempDir()
	secret := "super-secret-jwt-key-32-bytes-long!!"

	// Calling NewLocalStorage with empty encKey in production mode must fail
	_, err := NewLocalStorage(tempDir, "http://localhost:8080", secret, "", "production")
	if err == nil {
		t.Fatalf("Expected NewLocalStorage to fail when DOCUMENT_ENCRYPTION_KEY is empty in production mode, got nil")
	}
	if !strings.Contains(err.Error(), "DOCUMENT_ENCRYPTION_KEY") {
		t.Errorf("Expected error to mention DOCUMENT_ENCRYPTION_KEY, got %v", err)
	}
}

func TestLocalStorage_NewError(t *testing.T) {
	tempFile, err := os.CreateTemp("", "storage-file-*")
	if err != nil {
		t.Fatalf("failed to create temp file: %v", err)
	}
	defer os.Remove(tempFile.Name())
	tempFile.Close()

	invalidDir := filepath.Join(tempFile.Name(), "subdir")
	_, err = NewLocalStorage(invalidDir, "http://localhost", "secret", "", "test")
	if err == nil {
		t.Errorf("Expected error when baseDir cannot be created, got nil")
	}
}

func TestLocalStorage_UploadWriterFail(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "storage-test-*")
	if err != nil {
		t.Fatalf("failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	store, _ := NewLocalStorage(tempDir, "http://localhost:8080", "secret", "", "test")
	ctx := context.Background()

	// Pass a reader that fails midway
	failReader := &errReader{}
	err = store.Upload(ctx, "fail.txt", failReader, "text/plain")
	if err == nil {
		t.Errorf("Expected error when reader fails during upload, got nil")
	}
}

type errReader struct{}

func (e *errReader) Read(p []byte) (n int, err error) {
	return 0, bytes.ErrTooLarge
}
