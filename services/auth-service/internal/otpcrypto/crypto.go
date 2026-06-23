// Package otpcrypto provides AES-256-GCM encryption for OTP codes
// so they are stored encrypted in MongoDB, not as plaintext.
package otpcrypto

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"io"
)

// Cipher wraps an AES-256-GCM AEAD for encrypting/decrypting OTP codes.
type Cipher struct {
	aead cipher.AEAD
}

// NewCipher creates a new AES-256-GCM cipher from a 32-byte hex-encoded key.
// If the key is shorter than 32 bytes, it is zero-padded.
// If the key is empty, a random 32-byte key is generated (ephemeral, local-only).
func NewCipher(hexKey string) (*Cipher, error) {
	var keyBytes []byte

	if hexKey == "" {
		// Generate an ephemeral key for local development.
		keyBytes = make([]byte, 32)
		if _, err := rand.Read(keyBytes); err != nil {
			return nil, fmt.Errorf("otpcrypto: failed to generate random key: %w", err)
		}
	} else {
		var err error
		keyBytes, err = hex.DecodeString(hexKey)
		if err != nil {
			// If not valid hex, use raw bytes padded/truncated to 32.
			keyBytes = make([]byte, 32)
			copy(keyBytes, []byte(hexKey))
		}
	}

	// Ensure exactly 32 bytes for AES-256.
	if len(keyBytes) < 32 {
		padded := make([]byte, 32)
		copy(padded, keyBytes)
		keyBytes = padded
	} else if len(keyBytes) > 32 {
		keyBytes = keyBytes[:32]
	}

	block, err := aes.NewCipher(keyBytes)
	if err != nil {
		return nil, fmt.Errorf("otpcrypto: new cipher: %w", err)
	}

	aead, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("otpcrypto: new GCM: %w", err)
	}

	return &Cipher{aead: aead}, nil
}

// Encrypt encrypts the plaintext OTP and returns a hex-encoded ciphertext
// (nonce prepended to ciphertext).
func (c *Cipher) Encrypt(plaintext string) (string, error) {
	nonce := make([]byte, c.aead.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return "", fmt.Errorf("otpcrypto: nonce generation failed: %w", err)
	}

	ciphertext := c.aead.Seal(nonce, nonce, []byte(plaintext), nil)
	return hex.EncodeToString(ciphertext), nil
}

// Decrypt decrypts a hex-encoded ciphertext (with prepended nonce) back to plaintext.
func (c *Cipher) Decrypt(hexCiphertext string) (string, error) {
	data, err := hex.DecodeString(hexCiphertext)
	if err != nil {
		return "", fmt.Errorf("otpcrypto: hex decode: %w", err)
	}

	nonceSize := c.aead.NonceSize()
	if len(data) < nonceSize {
		return "", fmt.Errorf("otpcrypto: ciphertext too short")
	}

	nonce, ciphertext := data[:nonceSize], data[nonceSize:]
	plaintext, err := c.aead.Open(nil, nonce, ciphertext, nil)
	if err != nil {
		return "", fmt.Errorf("otpcrypto: decrypt failed: %w", err)
	}

	return string(plaintext), nil
}
