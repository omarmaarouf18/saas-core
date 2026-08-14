package version

import (
	"testing"
)

func TestParseSemVer(t *testing.T) {
	tests := []struct {
		input    string
		expected SemVer
		wantErr  bool
	}{
		{"1.0.0", SemVer{1, 0, 0}, false},
		{"v1.2.3", SemVer{1, 2, 3}, false},
		{"1.0.0+1", SemVer{1, 0, 0}, false},
		{"2.10.5+build.42", SemVer{2, 10, 5}, false},
		{"invalid", SemVer{}, true},
		{"1.0", SemVer{}, true},
		{"", SemVer{}, true},
	}

	for _, tt := range tests {
		got, err := ParseSemVer(tt.input)
		if tt.wantErr {
			if err == nil {
				t.Errorf("ParseSemVer(%q) expected error, got nil", tt.input)
			}
		} else {
			if err != nil {
				t.Errorf("ParseSemVer(%q) unexpected error: %v", tt.input, err)
			}
			if got != tt.expected {
				t.Errorf("ParseSemVer(%q) = %v, want %v", tt.input, got, tt.expected)
			}
		}
	}
}

func TestSemVer_LessThan(t *testing.T) {
	v100, _ := ParseSemVer("1.0.0")
	v101, _ := ParseSemVer("1.0.1")
	v110, _ := ParseSemVer("1.1.0")
	v200, _ := ParseSemVer("2.0.0")

	if !v100.LessThan(v101) {
		t.Errorf("1.0.0 should be LessThan 1.0.1")
	}
	if !v101.LessThan(v110) {
		t.Errorf("1.0.1 should be LessThan 1.1.0")
	}
	if !v110.LessThan(v200) {
		t.Errorf("1.1.0 should be LessThan 2.0.0")
	}
	if v100.LessThan(v100) {
		t.Errorf("1.0.0 should NOT be LessThan 1.0.0")
	}
	if v200.LessThan(v100) {
		t.Errorf("2.0.0 should NOT be LessThan 1.0.0")
	}
}
