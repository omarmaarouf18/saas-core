// Package testutil gives tests that share external resources (Redis keys,
// pub/sub channels, Mongo database names) a per-run suffix so that two test
// runs executing concurrently against the same local Redis/Mongo cannot
// collide (TST-01). `make ci` exports TEST_DB_SUFFIX as
// "<worktree>-<pid>"; when it is not set (a plain `go test`), a value unique
// per process is generated instead.
package testutil

import (
	"fmt"
	"os"
	"strings"
	"sync"
	"time"
)

var (
	suffixOnce sync.Once
	suffix     string
)

// Suffix returns the per-run identifier: the sanitized TEST_DB_SUFFIX value
// when set, otherwise "<pid>-<unixnano>" generated once per process. The
// value is stable for the whole process, so every ID(...) call within one
// test run shares the same suffix.
func Suffix() string {
	suffixOnce.Do(func() {
		env := os.Getenv("TEST_DB_SUFFIX")
		if env == "" {
			env = fmt.Sprintf("%d-%d", os.Getpid(), time.Now().UnixNano())
		}
		suffix = sanitize(env)
	})
	return suffix
}

// ID returns prefix joined with Suffix as "<prefix>-<suffix>", sanitized to
// [A-Za-z0-9_-] so the result is safe to embed in Redis keys, pub/sub
// channels and Mongo database names.
func ID(prefix string) string {
	return sanitize(prefix + "-" + Suffix())
}

// sanitize replaces every character outside [A-Za-z0-9_-] with '_' (Mongo
// database names cannot contain e.g. spaces or dots; Redis keys and pub/sub
// channels stay printable ASCII).
func sanitize(s string) string {
	return strings.Map(func(r rune) rune {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9', r == '_', r == '-':
			return r
		default:
			return '_'
		}
	}, s)
}
