package main

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/hex"
	"flag"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"
)

func main() {
	dirFlag := flag.String("dir", "", "Path to storage directory containing documents")
	keyFlag := flag.String("key", "", "DOCUMENT_ENCRYPTION_KEY (32-byte hex string)")
	flag.Parse()

	storageDir := *dirFlag
	if storageDir == "" {
		storageDir = os.Getenv("STORAGE_BASE_DIR")
	}
	if storageDir == "" {
		storageDir = "./data/documents"
	}
	storageDir = filepath.Clean(storageDir)
	absBase, err := filepath.Abs(storageDir)
	if err != nil {
		log.Fatalf("[MIGRATION ERROR] Invalid storage directory: %v", err)
	}

	encKey := *keyFlag
	if encKey == "" {
		encKey = os.Getenv("DOCUMENT_ENCRYPTION_KEY")
	}

	if encKey == "" {
		log.Fatalf("[MIGRATION ERROR] DOCUMENT_ENCRYPTION_KEY environment variable or -key flag is required")
	}

	keyBytes, err := hex.DecodeString(encKey)
	if err != nil || len(keyBytes) != 32 {
		log.Fatalf("[MIGRATION ERROR] DOCUMENT_ENCRYPTION_KEY must be a valid 64-character hex string (32 bytes)")
	}

	block, err := aes.NewCipher(keyBytes)
	if err != nil {
		log.Fatalf("[MIGRATION ERROR] Failed to create AES cipher: %v", err)
	}

	gcm, err := cipher.NewGCM(block)
	if err != nil {
		log.Fatalf("[MIGRATION ERROR] Failed to create GCM mode: %v", err)
	}

	// #nosec G706 //nolint:gosec -- admin CLI tool logging target directory path
	log.Printf("[MIGRATION] Scanning storage directory: %s", absBase)

	// #nosec G703 //nolint:gosec -- admin CLI tool inspecting storage directory
	if _, err := os.Stat(absBase); os.IsNotExist(err) {
		// #nosec G706 //nolint:gosec -- admin CLI tool logging non-existent path
		log.Printf("[MIGRATION] Storage directory %s does not exist. Nothing to migrate.", absBase)
		return
	}

	migratedCount := 0
	skippedCount := 0

	// #nosec G703 //nolint:gosec -- admin CLI tool walking target storage directory
	err = filepath.WalkDir(absBase, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			return nil
		}

		absPath, err := filepath.Abs(path)
		if err != nil || !strings.HasPrefix(absPath, absBase) {
			return fmt.Errorf("directory traversal attempt blocked: %s", path)
		}

		// #nosec G304 G122 //nolint:gosec -- path prefix validation ensures file is scoped to target storage directory
		data, err := os.ReadFile(absPath)
		if err != nil {
			return fmt.Errorf("failed to read file %s: %w", absPath, err)
		}

		// Check if file is already encrypted by attempting to decrypt it
		nonceSize := gcm.NonceSize()
		if len(data) >= nonceSize {
			nonce, ciphertext := data[:nonceSize], data[nonceSize:]
			if _, decErr := gcm.Open(nil, nonce, ciphertext, nil); decErr == nil {
				// File is already encrypted!
				skippedCount++
				return nil
			}
		}

		// File is plaintext -> Encrypt it
		nonce := make([]byte, nonceSize)
		if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
			return fmt.Errorf("failed to generate nonce for %s: %w", absPath, err)
		}

		encryptedData := gcm.Seal(nonce, nonce, data, nil)

		// #nosec G703 G122 //nolint:gosec -- path prefix validation ensures file is scoped to target storage directory
		if err := os.WriteFile(absPath, encryptedData, 0600); err != nil {
			return fmt.Errorf("failed to write encrypted file %s: %w", absPath, err)
		}

		// #nosec G706 //nolint:gosec -- admin CLI tool logging encrypted file path
		log.Printf("[MIGRATION] Successfully encrypted plaintext document: %s", absPath)
		migratedCount++
		return nil
	})

	if err != nil {
		log.Fatalf("[MIGRATION ERROR] Error walking storage directory: %v", err)
	}

	log.Printf("[MIGRATION COMPLETE] Processed %d files (%d encrypted, %d already encrypted)", migratedCount+skippedCount, migratedCount, skippedCount)
}
