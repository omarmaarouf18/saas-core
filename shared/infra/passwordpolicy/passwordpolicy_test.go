package passwordpolicy

import (
	"errors"
	"strings"
	"testing"
)

func TestValidate_AcceptsStrongPasswords(t *testing.T) {
	for _, password := range []string{
		"correct-horse-battery-staple",
		"Str0ng!P@ssword",
		"éééééééé",                     // 8 runes, 16 bytes
		"密码密码密码密码",                     // 8 runes, 24 bytes
		strings.Repeat("a", MaxLength), // exactly 72 bytes is allowed
	} {
		if err := Validate(password); err != nil {
			t.Errorf("Validate(%q) = %v, want nil", password, err)
		}
	}
}

func TestValidate_MinLengthCountsRunes(t *testing.T) {
	for _, password := range []string{
		"1234567", // 7 ASCII runes
		"short1!", // 7 ASCII runes
		"ééééééé", // 7 runes, 14 bytes
		"密码密码密码",  // 5 runes, 15 bytes
		"😀😀😀😀😀😀😀", // 7 runes, 28 bytes
	} {
		if err := Validate(password); !errors.Is(err, ErrTooShort) {
			t.Errorf("Validate(%q) = %v, want ErrTooShort", password, err)
		}
	}
}

func TestValidate_MaxLengthEnforcedBeforeBcryptTruncation(t *testing.T) {
	if err := Validate(strings.Repeat("a", MaxLength+1)); !errors.Is(err, ErrTooLong) {
		t.Errorf("73 bytes: got %v, want ErrTooLong", err)
	}
	// 25 CJK runes = 75 bytes: long enough in runes but over the bcrypt
	// byte limit.
	if err := Validate(strings.Repeat("密", 25)); !errors.Is(err, ErrTooLong) {
		t.Errorf("75-byte CJK password: got %v, want ErrTooLong", err)
	}
}

func TestValidate_RejectsCommonPasswords(t *testing.T) {
	for _, password := range []string{
		"password",
		"PASSWORD",    // case-insensitive match
		"Password",    // mixed case match
		"password123", // trailing digits do not help
		"12345678",    // pure digit sequence
		"qwertyuiop",  // keyboard walk
		"iloveyou",    // classic
		"letmein123!", // punctuation does not help if it is in the list
	} {
		if err := Validate(password); !errors.Is(err, ErrTooCommon) {
			t.Errorf("Validate(%q) = %v, want ErrTooCommon", password, err)
		}
	}
}

// TestValidate_ExactMatchOnly documents the blocklist semantics: only exact
// (case-insensitive) matches are rejected; close variants pass, which is
// intentional for a minimal hard blocklist (length + uniqueness rules are
// separate concerns).
func TestValidate_ExactMatchOnly(t *testing.T) {
	for _, password := range []string{
		"password1234x",
		"xpassword123",
		"pa55word123",
	} {
		if err := Validate(password); err != nil {
			t.Errorf("Validate(%q) = %v, want nil (not an exact blocklist match)", password, err)
		}
	}
}

func TestValidate_ErrorMessagesAreUserFacing(t *testing.T) {
	cases := []struct {
		password string
		want     string
	}{
		{"short1", "password must be at least 8 characters"},
		{strings.Repeat("a", 73), "password must be at most 72 bytes"},
		{"password", "password is too common"},
	}
	for _, tc := range cases {
		if err := Validate(tc.password); err == nil || err.Error() != tc.want {
			t.Errorf("Validate(%q) error = %v, want %q", tc.password, err, tc.want)
		}
	}
}

func TestCommonPasswordListLoaded(t *testing.T) {
	if len(commonPasswords) < 100 {
		t.Fatalf("embedded common-password list looks empty or truncated: %d entries", len(commonPasswords))
	}
	for entry := range commonPasswords {
		if entry != strings.ToLower(entry) {
			t.Errorf("common password entry %q is not stored lowercase", entry)
		}
	}
}
