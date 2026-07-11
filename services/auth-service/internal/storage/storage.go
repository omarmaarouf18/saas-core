package storage

import (
	"context"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// Storage defines the interface for document storage.
type Storage interface {
	Upload(ctx context.Context, key string, reader io.Reader, contentType string) error
	GetSignedURL(ctx context.Context, key string, expires time.Duration) (string, error)
}

// LocalStorage implements Storage using local disk for development.
type LocalStorage struct {
	baseDir   string
	baseURL   string
	jwtSecret []byte
}

// DocClaims holds JWT claims for securing document viewing access.
type DocClaims struct {
	Key string `json:"key"`
	jwt.RegisteredClaims
}

// NewLocalStorage initializes a new LocalStorage.
func NewLocalStorage(baseDir, baseURL, secret string) (*LocalStorage, error) {
	if err := os.MkdirAll(baseDir, 0700); err != nil {
		return nil, fmt.Errorf("storage: failed to create base directory: %w", err)
	}
	return &LocalStorage{
		baseDir:   baseDir,
		baseURL:   baseURL,
		jwtSecret: []byte(secret),
	}, nil
}

// Upload writes a document file to the local disk.
func (l *LocalStorage) Upload(ctx context.Context, key string, reader io.Reader, contentType string) error {
	destPath := filepath.Join(l.baseDir, filepath.Clean(key))
	if err := os.MkdirAll(filepath.Dir(destPath), 0700); err != nil {
		return fmt.Errorf("storage: failed to create subdirectories: %w", err)
	}

	file, err := os.OpenFile(destPath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0600)
	if err != nil {
		return fmt.Errorf("storage: failed to open destination file: %w", err)
	}
	defer file.Close()

	if _, err := io.Copy(file, reader); err != nil {
		return fmt.Errorf("storage: failed to write file: %w", err)
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

// OpenFile opens the local file for reading.
func (l *LocalStorage) OpenFile(key string) (io.ReadCloser, error) {
	destPath := filepath.Join(l.baseDir, filepath.Clean(key))
	file, err := os.Open(destPath)
	if err != nil {
		return nil, fmt.Errorf("storage: failed to open file %s: %w", key, err)
	}
	return file, nil
}
