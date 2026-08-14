package storage

import (
	"bytes"
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// Storage defines the interface for document storage.
type Storage interface {
	Upload(ctx context.Context, key string, reader io.Reader, contentType string) error
	GetSignedURL(ctx context.Context, key string, expires time.Duration) (string, error)
	ValidateSignedURLToken(tokenStr string) (string, error)
	OpenFile(key string) (io.ReadCloser, error)
}

// LocalStorage implements Storage using local disk with AES-256-GCM encryption at rest.
type LocalStorage struct {
	baseDir   string
	baseURL   string
	jwtSecret []byte
	aead      cipher.AEAD
}

// DocClaims holds JWT claims for securing document viewing access.
type DocClaims struct {
	Key string `json:"key"`
	jwt.RegisteredClaims
}

func createDocAEAD(hexKey, appEnv string) (cipher.AEAD, error) {
	var keyBytes []byte
	var err error

	isLocalOrTest := appEnv == "local" || appEnv == "test" || appEnv == ""

	if hexKey == "" {
		if appEnv == "production" {
			return nil, fmt.Errorf("storage: DOCUMENT_ENCRYPTION_KEY is required in environment: %s", appEnv)
		}
		// Generate a random 32-byte key for local/test ephemeral storage if empty
		keyBytes = make([]byte, 32)
		if _, err := rand.Read(keyBytes); err != nil {
			return nil, fmt.Errorf("storage: failed to generate random key: %w", err)
		}
	} else {
		keyBytes, err = hex.DecodeString(hexKey)
		if err != nil {
			if !isLocalOrTest && appEnv == "production" {
				return nil, fmt.Errorf("storage: DOCUMENT_ENCRYPTION_KEY must be a valid hex string: %w", err)
			}
			// If not valid hex in local/test, use raw bytes padded/truncated to 32
			keyBytes = make([]byte, 32)
			copy(keyBytes, []byte(hexKey))
		} else if len(keyBytes) != 32 {
			if !isLocalOrTest && appEnv == "production" {
				return nil, fmt.Errorf("storage: DOCUMENT_ENCRYPTION_KEY must be exactly 32 bytes (64 hex characters), got %d bytes", len(keyBytes))
			}
		}
	}

	if len(keyBytes) < 32 {
		padded := make([]byte, 32)
		copy(padded, keyBytes)
		keyBytes = padded
	} else if len(keyBytes) > 32 {
		keyBytes = keyBytes[:32]
	}

	block, err := aes.NewCipher(keyBytes)
	if err != nil {
		return nil, fmt.Errorf("storage: new cipher: %w", err)
	}

	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("storage: new GCM: %w", err)
	}

	return gcm, nil
}

// NewLocalStorage initializes a new LocalStorage.
func NewLocalStorage(baseDir, baseURL, secret, encKey, appEnv string) (*LocalStorage, error) {
	if err := os.MkdirAll(baseDir, 0700); err != nil {
		return nil, fmt.Errorf("storage: failed to create base directory: %w", err)
	}

	aead, err := createDocAEAD(encKey, appEnv)
	if err != nil {
		return nil, fmt.Errorf("storage: failed to create encryption cipher: %w", err)
	}

	return &LocalStorage{
		baseDir:   baseDir,
		baseURL:   baseURL,
		jwtSecret: []byte(secret),
		aead:      aead,
	}, nil
}

// Upload writes an encrypted document file to the local disk.
func (l *LocalStorage) Upload(ctx context.Context, key string, reader io.Reader, contentType string) error {
	destPath := filepath.Join(l.baseDir, filepath.Clean(key))
	absBase, err := filepath.Abs(l.baseDir)
	if err != nil {
		return fmt.Errorf("storage: invalid base directory: %w", err)
	}
	absDest, err := filepath.Abs(destPath)
	if err != nil {
		return fmt.Errorf("storage: invalid destination path: %w", err)
	}
	if !strings.HasPrefix(absDest, absBase) {
		return fmt.Errorf("storage: directory traversal detected")
	}

	plaintext, err := io.ReadAll(reader)
	if err != nil {
		return fmt.Errorf("storage: failed to read file content: %w", err)
	}

	nonce := make([]byte, l.aead.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return fmt.Errorf("storage: failed to generate nonce: %w", err)
	}

	ciphertext := l.aead.Seal(nonce, nonce, plaintext, nil)

	if err := os.MkdirAll(filepath.Dir(destPath), 0700); err != nil {
		return fmt.Errorf("storage: failed to create subdirectories: %w", err)
	}

	// #nosec G304 //nolint:gosec -- path prefix validation ensures file is scoped to storage directory, preventing directory traversal
	file, err := os.OpenFile(destPath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0600)
	if err != nil {
		return fmt.Errorf("storage: failed to open destination file: %w", err)
	}
	defer file.Close()

	if _, err := file.Write(ciphertext); err != nil {
		return fmt.Errorf("storage: failed to write encrypted file: %w", err)
	}

	return nil
}

// GetSignedURL generates a short-lived signed URL to access the document.
func (l *LocalStorage) GetSignedURL(ctx context.Context, key string, expires time.Duration) (string, error) {
	claims := DocClaims{
		Key: key,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(expires)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenStr, err := token.SignedString(l.jwtSecret)
	if err != nil {
		return "", fmt.Errorf("storage: failed to sign token: %w", err)
	}

	return fmt.Sprintf("%s/auth/documents/view?token=%s", l.baseURL, tokenStr), nil
}

// ValidateSignedURLToken parses and validates a signed view URL token.
func (l *LocalStorage) ValidateSignedURLToken(tokenStr string) (string, error) {
	token, err := jwt.ParseWithClaims(tokenStr, &DocClaims{}, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}
		return l.jwtSecret, nil
	})
	if err != nil {
		return "", fmt.Errorf("storage: token validation failed: %w", err)
	}

	claims, ok := token.Claims.(*DocClaims)
	if !ok || !token.Valid {
		return "", fmt.Errorf("storage: invalid token claims")
	}

	return claims.Key, nil
}

// OpenFile opens and decrypts the local file for reading.
func (l *LocalStorage) OpenFile(key string) (io.ReadCloser, error) {
	destPath := filepath.Join(l.baseDir, filepath.Clean(key))
	absBase, err := filepath.Abs(l.baseDir)
	if err != nil {
		return nil, fmt.Errorf("storage: invalid base directory: %w", err)
	}
	absDest, err := filepath.Abs(destPath)
	if err != nil {
		return nil, fmt.Errorf("storage: invalid destination path: %w", err)
	}
	if !strings.HasPrefix(absDest, absBase) {
		return nil, fmt.Errorf("storage: directory traversal detected")
	}

	// #nosec G304 //nolint:gosec -- path prefix validation ensures file is scoped to storage directory, preventing directory traversal
	data, err := os.ReadFile(destPath)
	if err != nil {
		return nil, fmt.Errorf("storage: failed to open file %s: %w", key, err)
	}

	nonceSize := l.aead.NonceSize()
	if len(data) < nonceSize {
		return nil, fmt.Errorf("storage: file %s is too short to contain valid ciphertext", key)
	}

	nonce, ciphertext := data[:nonceSize], data[nonceSize:]
	plaintext, err := l.aead.Open(nil, nonce, ciphertext, nil)
	if err != nil {
		return nil, fmt.Errorf("storage: failed to decrypt file %s: %w", key, err)
	}

	return io.NopCloser(bytes.NewReader(plaintext)), nil
}
