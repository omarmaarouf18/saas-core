// Package testutil gives tests that share external resources (Redis keys,
// pub/sub channels, Mongo database names) a per-run suffix so that two test
// runs executing concurrently against the same local Redis/Mongo cannot
// collide (TST-01). `make ci` exports TEST_DB_SUFFIX as
// "<worktree>-<pid>"; when it is not set (a plain `go test`), a value unique
// per process is generated instead.
package testutil

import (
	"fmt"
	"hash/fnv"
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

// IP returns a valid IPv4 address for request n (0..253) of a test that
// sends X-Real-IP headers: "10.<a>.<b>.<n+1>", where <a>.<b> come from an
// FNV-1a hash of prefix and Suffix(). Rate limiters key on the client IP, so
// the value is stable within one run, distinct per n, and differs between
// concurrent runs (and between prefixes) with high probability. It panics on
// an n outside 0..253, which would leave the host octet range.
func IP(prefix string, n int) string {
	if n < 0 || n > 253 {
		panic(fmt.Sprintf("testutil.IP: n=%d out of range 0..253", n))
	}
	h := fnv.New32a()
	_, _ = h.Write([]byte(prefix + "-" + Suffix()))
	sum := h.Sum32()
	return fmt.Sprintf("10.%d.%d.%d", (sum>>16)&0xff, (sum>>8)&0xff, n+1)
}
