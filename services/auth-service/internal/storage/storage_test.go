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
	store, err := NewLocalStorage(tempDir, "http://localhost:8080", secret)
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
	otherStore, _ := NewLocalStorage(tempDir, "http://localhost:8080", "different-secret-key-32-bytes!!")
	_, err = otherStore.ValidateSignedURLToken(tokenStr)
	if err == nil {
		t.Errorf("Expected error validating token signed with wrong secret, got nil")
	}
}

func TestLocalStorage_NewError(t *testing.T) {
	// Try creating storage in a path that cannot be created (file instead of directory)
	tempFile, err := os.CreateTemp("", "storage-file-*")
	if err != nil {
		t.Fatalf("failed to create temp file: %v", err)
	}
	defer os.Remove(tempFile.Name())
	tempFile.Close()

	invalidDir := filepath.Join(tempFile.Name(), "subdir")
	_, err = NewLocalStorage(invalidDir, "http://localhost", "secret")
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

	store, _ := NewLocalStorage(tempDir, "http://localhost:8080", "secret")
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
