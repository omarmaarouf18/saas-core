package version

import (
	"fmt"
	"strconv"
	"strings"
)

// SemVer represents a parsed semantic version (Major.Minor.Patch).
type SemVer struct {
	Major int
	Minor int
	Patch int
}

// ParseSemVer parses a version string like "1.0.0", "v1.2.3", or "1.0.0+1" into SemVer.
func ParseSemVer(v string) (SemVer, error) {
	v = strings.TrimSpace(v)
	if v == "" {
		return SemVer{}, fmt.Errorf("empty version string")
	}

	// Strip optional build metadata suffix (e.g. +1, +build123)
	if idx := strings.Index(v, "+"); idx != -1 {
		v = v[:idx]
	}
	// Strip optional leading 'v'
	v = strings.TrimPrefix(v, "v")

	parts := strings.Split(v, ".")
	if len(parts) < 3 {
		return SemVer{}, fmt.Errorf("invalid semver string %q: must contain major.minor.patch", v)
	}

	major, err1 := strconv.Atoi(parts[0])
	minor, err2 := strconv.Atoi(parts[1])
	patch, err3 := strconv.Atoi(parts[2])

	if err1 != nil || err2 != nil || err3 != nil {
		return SemVer{}, fmt.Errorf("invalid semver integers in %q", v)
	}

	return SemVer{Major: major, Minor: minor, Patch: patch}, nil
}

// LessThan returns true if s is strictly less than o.
func (s SemVer) LessThan(o SemVer) bool {
	if s.Major != o.Major {
		return s.Major < o.Major
	}
	if s.Minor != o.Minor {
		return s.Minor < o.Minor
	}
	return s.Patch < o.Patch
}

// String returns the canonical Major.Minor.Patch string representation.
func (s SemVer) String() string {
	return fmt.Sprintf("%d.%d.%d", s.Major, s.Minor, s.Patch)
}
