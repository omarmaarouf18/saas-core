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

// TestParseSemVer_PrereleaseAndBuildSuffixes reproduces the prerelease
// parsing bug: "1.2.3-beta" split into ["1","2","3-beta"] and strconv.Atoi
// failed on "3-beta", rejecting valid semver client versions (HTTP 400 from
// the VersionGate for every prerelease build).
//
// Pre-fix expectation: error "invalid semver integers".
// Post-fix expectation: 1.2.3 parsed; prerelease/build suffixes ignored for
// comparison purposes.
func TestParseSemVer_PrereleaseAndBuildSuffixes(t *testing.T) {
	cases := []struct {
		in   string
		want SemVer
	}{
		{"1.2.3-beta", SemVer{Major: 1, Minor: 2, Patch: 3}},
		{"1.2.3-beta.1+build5", SemVer{Major: 1, Minor: 2, Patch: 3}},
		{"v2.0.0-rc.2", SemVer{Major: 2, Minor: 0, Patch: 0}},
	}
	for _, tc := range cases {
		got, err := ParseSemVer(tc.in)
		if err != nil {
			t.Errorf("ParseSemVer(%q) failed: %v (valid semver with prerelease must parse)", tc.in, err)
			continue
		}
		if got != tc.want {
			t.Errorf("ParseSemVer(%q) = %v, want %v", tc.in, got, tc.want)
		}
	}
}
