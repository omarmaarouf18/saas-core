package models

import "testing"

func TestValidRole(t *testing.T) {
	if !ValidRole(RoleOwner) {
		t.Errorf("Expected RoleOwner to be valid")
	}
	if !ValidRole(RoleUser) {
		t.Errorf("Expected RoleUser to be valid")
	}
	if !ValidRole(RoleEmployee) {
		t.Errorf("Expected RoleEmployee to be valid")
	}
	if ValidRole(Role("invalid_role")) {
		t.Errorf("Expected 'invalid_role' to be invalid")
	}
}

// PUSH-L10N item 1: device-token locales.
func TestNormalizeDeviceLocale(t *testing.T) {
	cases := []struct {
		in   string
		want string
		ok   bool
	}{
		{"", "", true},
		{"ar", "ar", true},
		{"en", "en", true},
		{"AR", "ar", true},
		{" en ", "en", true},
		{"ar_EG", "ar", true},
		{"en-US", "en", true},
		{"fr", "", false},
		{"arabic", "", false},
		{"-ar", "", false},
	}
	for _, c := range cases {
		got, ok := NormalizeDeviceLocale(c.in)
		if got != c.want || ok != c.ok {
			t.Errorf("NormalizeDeviceLocale(%q) = %q, %v; want %q, %v", c.in, got, ok, c.want, c.ok)
		}
	}
}
