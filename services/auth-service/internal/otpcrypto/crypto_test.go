package otpcrypto

import (
	"encoding/hex"
	"testing"
)

func TestCipher_EncryptDecrypt(t *testing.T) {
	// 32-byte hex key = 64 hex characters
	hexKey := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
	c, err := NewCipher(hexKey, "production")
	if err != nil {
		t.Fatalf("NewCipher failed: %v", err)
	}

	plaintext := "654321"
	ciphertext, err := c.Encrypt(plaintext)
	if err != nil {
		t.Fatalf("Encrypt failed: %v", err)
	}

	decrypted, err := c.Decrypt(ciphertext)
	if err != nil {
		t.Fatalf("Decrypt failed: %v", err)
	}

	if decrypted != plaintext {
		t.Errorf("Expected decrypted text %q, got %q", plaintext, decrypted)
	}

	// Test Decrypt invalid hex
	_, err = c.Decrypt("invalid-hex-string")
	if err == nil {
		t.Errorf("Expected error decrypting invalid hex, got nil")
	}

	// Test Decrypt short ciphertext
	shortHex := hex.EncodeToString([]byte("short"))
	_, err = c.Decrypt(shortHex)
	if err == nil {
		t.Errorf("Expected error decrypting short ciphertext, got nil")
	}

	// Test Decrypt tampered payload
	data, _ := hex.DecodeString(ciphertext)
	data[len(data)-1] ^= 0xff // flip last bit
	tamperedHex := hex.EncodeToString(data)
	_, err = c.Decrypt(tamperedHex)
	if err == nil {
		t.Errorf("Expected error decrypting tampered ciphertext, got nil")
	}
}

func TestNewCipher_Validation(t *testing.T) {
	tests := []struct {
		name        string
		key         string
		appEnv      string
		expectError bool
	}{
		{
			name:        "Empty Key Production",
			key:         "",
			appEnv:      "production",
			expectError: true,
		},
		{
			name:        "Empty Key Local (auto-generates ephemeral key)",
			key:         "",
			appEnv:      "local",
			expectError: false,
		},
		{
			name:        "Invalid Hex Key Production",
			key:         "not-valid-hex-zzz",
			appEnv:      "production",
			expectError: true,
		},
		{
			name:        "Invalid Hex Key Local (pads/truncates raw bytes)",
			key:         "not-valid-hex-zzz",
			appEnv:      "local",
			expectError: false,
		},
		{
			name:        "Short Hex Key Production (e.g. 16 bytes)",
			key:         "0123456789abcdef0123456789abcdef",
			appEnv:      "production",
			expectError: true,
		},
		{
			name:        "Short Hex Key Local (zero-padded to 32 bytes)",
			key:         "0123456789abcdef0123456789abcdef",
			appEnv:      "local",
			expectError: false,
		},
		{
			name:        "Valid 32 Byte Hex Key Production",
			key:         "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
			appEnv:      "production",
			expectError: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := NewCipher(tt.key, tt.appEnv)
			if tt.expectError && err == nil {
				t.Errorf("Expected error for case %q, got nil", tt.name)
			}
			if !tt.expectError && err != nil {
				t.Errorf("Unexpected error for case %q: %v", tt.name, err)
			}
		})
	}
}
