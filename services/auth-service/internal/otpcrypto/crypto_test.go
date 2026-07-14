package otpcrypto

import (
	"encoding/hex"
	"testing"
)

func TestNewCipher_Validation(t *testing.T) {
	// 32-byte valid hex key (64 hex characters)
	valid32ByteKey := hex.EncodeToString(make([]byte, 32))
	shortKey := hex.EncodeToString(make([]byte, 31)) // 31-byte key

	tests := []struct {
		name      string
		hexKey    string
		appEnv    string
		expectErr bool
	}{
		{
			name:      "Local empty key (ephemeral)",
			hexKey:    "",
			appEnv:    "local",
			expectErr: false,
		},
		{
			name:      "Test empty key (ephemeral)",
			hexKey:    "",
			appEnv:    "test",
			expectErr: false,
		},
		{
			name:      "Production empty key (fails)",
			hexKey:    "",
			appEnv:    "production",
			expectErr: true,
		},
		{
			name:      "Production short key (fails)",
			hexKey:    shortKey,
			appEnv:    "production",
			expectErr: true,
		},
		{
			name:      "Production invalid hex (fails)",
			hexKey:    "not-a-valid-hex-string-!!!",
			appEnv:    "production",
			expectErr: true,
		},
		{
			name:      "Production valid 32-byte key (succeeds)",
			hexKey:    valid32ByteKey,
			appEnv:    "production",
			expectErr: false,
		},
		{
			name:      "Local invalid hex (fallback/succeeds)",
			hexKey:    "not-a-valid-hex-string-!!!",
			appEnv:    "local",
			expectErr: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := NewCipher(tt.hexKey, tt.appEnv)
			if (err != nil) != tt.expectErr {
				t.Errorf("expected error: %v, got: %v", tt.expectErr, err)
			}
		})
	}
}
