package testutil

import (
	"os"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"testing"
)

// resetSuffixForTest clears the process-wide once so each test starts from a
// known state. Safe: tests in a package run sequentially unless t.Parallel is
// used (it is not here), and none of these tests use t.Setenv in parallel.
func resetSuffixForTest() {
	suffixOnce = sync.Once{}
	suffix = ""
}

var safeChars = regexp.MustCompile(`^[A-Za-z0-9_-]+$`)

func TestSuffixUsesEnvWhenSet(t *testing.T) {
	t.Setenv("TEST_DB_SUFFIX", "SaaS_prototype-12345")
	resetSuffixForTest()

	if got := Suffix(); got != "SaaS_prototype-12345" {
		t.Fatalf("Suffix() = %q, want the TEST_DB_SUFFIX value %q", got, "SaaS_prototype-12345")
	}
}

func TestSuffixSanitizesUnsafeCharacters(t *testing.T) {
	t.Setenv("TEST_DB_SUFFIX", "SaaS prototype.123/45")
	resetSuffixForTest()

	if got := Suffix(); got != "SaaS_prototype_123_45" {
		t.Fatalf("Suffix() = %q, want unsafe characters replaced with '_' (%q)", got, "SaaS_prototype_123_45")
	}
}

func TestSuffixStableWithinProcess(t *testing.T) {
	t.Setenv("TEST_DB_SUFFIX", "stable-1")
	resetSuffixForTest()

	first := Suffix()
	// Changing the environment after the first call must not change the
	// suffix: it is computed once per process.
	t.Setenv("TEST_DB_SUFFIX", "different-2")
	second := Suffix()

	if first != second {
		t.Fatalf("Suffix() changed within a process: %q then %q", first, second)
	}
}

func TestSuffixFallbackWithoutEnv(t *testing.T) {
	t.Setenv("TEST_DB_SUFFIX", "")
	resetSuffixForTest()

	got := Suffix()
	if got == "" {
		t.Fatal("Suffix() is empty without TEST_DB_SUFFIX; want a per-process fallback")
	}
	if !safeChars.MatchString(got) {
		t.Fatalf("Suffix() = %q, want only [A-Za-z0-9_-]", got)
	}
	if wantPrefix := strconv.Itoa(os.Getpid()) + "-"; !strings.HasPrefix(got, wantPrefix) {
		t.Fatalf("Suffix() = %q, want the per-process fallback to start with %q", got, wantPrefix)
	}
	if again := Suffix(); again != got {
		t.Fatalf("fallback Suffix() changed within a process: %q then %q", got, again)
	}
}

func TestDifferentEnvValuesGiveDifferentIDs(t *testing.T) {
	t.Setenv("TEST_DB_SUFFIX", "aaa")
	resetSuffixForTest()
	idA := ID("owner-e2e-adr0006")

	t.Setenv("TEST_DB_SUFFIX", "bbb")
	resetSuffixForTest()
	idB := ID("owner-e2e-adr0006")

	if idA == idB {
		t.Fatalf("ID() identical for different TEST_DB_SUFFIX values: %q", idA)
	}
	if idA != "owner-e2e-adr0006-aaa" {
		t.Fatalf("ID() = %q, want %q", idA, "owner-e2e-adr0006-aaa")
	}
	if idB != "owner-e2e-adr0006-bbb" {
		t.Fatalf("ID() = %q, want %q", idB, "owner-e2e-adr0006-bbb")
	}
}

func TestIDSanitizesPrefixAndKeepsSuffix(t *testing.T) {
	t.Setenv("TEST_DB_SUFFIX", "run-1")
	resetSuffixForTest()

	got := ID("job:real cross")
	if got != "job_real_cross-run-1" {
		t.Fatalf("ID() = %q, want %q", got, "job_real_cross-run-1")
	}
}
