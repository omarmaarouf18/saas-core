// Package passwordpolicy implements the shared password strength policy
// enforced wherever a password is set (SEC-03).
//
// Policy:
//   - at least MinLength (8) characters, counted in runes so multi-byte
//     characters count once;
//   - at most MaxLength (72) bytes — bcrypt ignores input beyond 72 bytes,
//     so without this cap a long password would silently be equivalent to
//     its 72-byte prefix;
//   - not a commonly used password, checked as a case-insensitive exact
//     match against the embedded blocklist (common_passwords.txt).
//
// Validate returns a user-facing error for the first violated rule. Error
// values are exported so callers and tests can compare with errors.Is.
package passwordpolicy

import (
	_ "embed"
	"errors"
	"strings"
	"unicode/utf8"
)

const (
	// MinLength is the minimum accepted password length in runes.
	MinLength = 8
	// MaxLength is the maximum accepted password length in bytes (the
	// bcrypt input limit).
	MaxLength = 72
)

//go:embed common_passwords.txt
var commonPasswordsFile string

// commonPasswords is loaded once from the embedded blocklist. Entries are
// compared lowercased, so the file may be written in any case.
var commonPasswords = func() map[string]struct{} {
	set := make(map[string]struct{})
	for _, entry := range strings.Fields(commonPasswordsFile) {
		set[strings.ToLower(entry)] = struct{}{}
	}
	return set
}()

// Errors returned by Validate. Error() strings are safe to show to end
// users as-is.
var (
	ErrTooShort  = errors.New("password must be at least 8 characters")
	ErrTooLong   = errors.New("password must be at most 72 bytes")
	ErrTooCommon = errors.New("password is too common")
)

// Validate checks password against the shared policy and returns
// ErrTooShort, ErrTooLong, ErrTooCommon, or nil.
func Validate(password string) error {
	if utf8.RuneCountInString(password) < MinLength {
		return ErrTooShort
	}
	if len(password) > MaxLength {
		return ErrTooLong
	}
	if _, common := commonPasswords[strings.ToLower(password)]; common {
		return ErrTooCommon
	}
	return nil
}
