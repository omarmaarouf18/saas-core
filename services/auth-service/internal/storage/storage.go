package storage

import (
	"github.com/project/shared/infra/storage"
)

// Storage defines the interface for document storage (aliased from shared/infra/storage).
type Storage = storage.Storage

// LocalStorage implements Storage using local disk with AES-256-GCM encryption at rest (aliased).
type LocalStorage = storage.LocalStorage

// DocClaims holds JWT claims for securing document viewing access (aliased).
type DocClaims = storage.DocClaims

// NewLocalStorage initializes a new LocalStorage.
var NewLocalStorage = storage.NewLocalStorage

// NewLocalStorageWithPath initializes a new LocalStorage with custom view path.
var NewLocalStorageWithPath = storage.NewLocalStorageWithPath
