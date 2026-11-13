package handlers

import (
	"net/http"
	"strconv"
	"strings"
)

type appVersion struct {
	major int
	minor int
	patch int
}

// parseAppVersion parses a client version string into major, minor, patch.
// It accepts formats like "2.1.0", "v2.1.0", "2.1.0+7", "2.1.0-beta.1".
// It requires a 3-part semver (major.minor.patch); missing or unparseable parts return false.
func parseAppVersion(v string) (appVersion, bool) {
	v = strings.TrimSpace(v)
	if v == "" {
		return appVersion{}, false
	}
	if idx := strings.Index(v, "+"); idx != -1 {
		v = v[:idx]
	}
	if idx := strings.Index(v, "-"); idx != -1 {
		v = v[:idx]
	}
	v = strings.TrimPrefix(v, "v")
	parts := strings.Split(v, ".")
	if len(parts) != 3 {
		return appVersion{}, false
	}
	major, err1 := strconv.Atoi(parts[0])
	minor, err2 := strconv.Atoi(parts[1])
	patch, err3 := strconv.Atoi(parts[2])
	if err1 != nil || err2 != nil || err3 != nil || major < 0 || minor < 0 || patch < 0 {
		return appVersion{}, false
	}
	return appVersion{major: major, minor: minor, patch: patch}, true
}

// isAppVersionAtLeast reports whether v is a valid semver string that is >= targetMajor.targetMinor.targetPatch.
// An empty or invalid version returns false.
func isAppVersionAtLeast(v string, targetMajor, targetMinor, targetPatch int) bool {
	ver, ok := parseAppVersion(v)
	if !ok {
		return false
	}
	if ver.major != targetMajor {
		return ver.major > targetMajor
	}
	if ver.minor != targetMinor {
		return ver.minor > targetMinor
	}
	return ver.patch >= targetPatch
}

// isAtLeastAppVersion210 reports whether the request's X-App-Version is ≥ 2.1.0.
// A missing or invalid header returns false.
func isAtLeastAppVersion210(r *http.Request) bool {
	if r == nil {
		return false
	}
	return isAppVersionAtLeast(r.Header.Get("X-App-Version"), 2, 1, 0)
}

// parseAppMajor extracts only the major version integer from a version string
// (e.g. "1", "1.9", "v1", "1.9.3+4", "2", "2.0.0").
// Missing, negative, or non-numeric major returns (0, false).
func parseAppMajor(v string) (int, bool) {
	v = strings.TrimPrefix(strings.TrimSpace(v), "v")
	majorStr, _, _ := strings.Cut(v, ".")
	major, err := strconv.Atoi(majorStr)
	if err != nil || major < 0 {
		return 0, false
	}
	return major, true
}
