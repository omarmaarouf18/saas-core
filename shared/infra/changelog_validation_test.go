package infra

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

type errorReporter interface {
	Errorf(format string, args ...any)
	Fatalf(format string, args ...any)
}

var validSHARegex = regexp.MustCompile("^``[0-9a-f]{40}``$")

func validateChangelogFile(t errorReporter, file string, repoRoot string) {
	f, err := os.Open(file)
	if err != nil {
		t.Fatalf("failed to open file %s: %v", file, err)
		return
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	lineNum := 0
	for scanner.Scan() {
		lineNum++
		line := strings.TrimSpace(scanner.Text())
		if strings.HasPrefix(line, "- **Commit SHA**:") {
			parts := strings.SplitN(line, ":", 2)
			if len(parts) < 2 {
				t.Errorf("Line %d: malformed Commit SHA line: %q", lineNum, line)
				continue
			}
			shaVal := strings.TrimSpace(parts[1])

			if !validSHARegex.MatchString(shaVal) {
				t.Errorf("Line %d: invalid Commit SHA value %q. Must be a 40-character hex SHA wrapped in double backticks (e.g., ``[0-9a-f]{40}``) and cannot be a placeholder.", lineNum, shaVal)
				continue
			}

			// Verify the SHA actually exists in git history
			sha := strings.ReplaceAll(shaVal, "``", "")
			cmd := exec.Command("git", "cat-file", "-e", sha+"^{commit}")
			cmd.Dir = repoRoot
			if err := cmd.Run(); err != nil {
				t.Errorf("File %s, Line %d: Fabricated Commit SHA %q (value: %s) does not exist in git history!", filepath.Base(file), lineNum, sha, shaVal)
			}
		}
	}

	if err := scanner.Err(); err != nil {
		t.Fatalf("error reading file %s: %v", file, err)
	}
}

func TestChangelogCommitSHAs(t *testing.T) {
	changelogDir := filepath.Join("..", "..", "docs", "changelog")
	repoRoot, err := filepath.Abs(filepath.Join(changelogDir, "..", ".."))
	if err != nil {
		t.Fatalf("failed to get absolute path of repository root: %v", err)
	}

	files, err := filepath.Glob(filepath.Join(changelogDir, "*.md"))
	if err != nil {
		t.Fatalf("failed to glob changelog files: %v", err)
	}

	if len(files) == 0 {
		t.Fatalf("no changelog files found in %s", changelogDir)
	}

	for _, file := range files {
		t.Run(filepath.Base(file), func(t *testing.T) {
			validateChangelogFile(t, file, repoRoot)
		})
	}
}

type mockReporter struct {
	errors []string
}

func (m *mockReporter) Errorf(format string, args ...any) {
	m.errors = append(m.errors, fmt.Sprintf(format, args...))
}

func (m *mockReporter) Fatalf(format string, args ...any) {
	m.errors = append(m.errors, fmt.Sprintf(format, args...))
}

func TestChangelogCommitSHAs_Validation(t *testing.T) {
	// Prove enforcement works by writing an invalid SHA to a temp file and validating it
	tempDir, err := os.MkdirTemp("", "changelog-validation-test-*")
	if err != nil {
		t.Fatalf("failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	tempFile := filepath.Join(tempDir, "invalid-sha-test.md")
	content := []byte(`# Test Changelog

- **Commit SHA**: ` + "``" + `0000000000000000000000000000000000000000` + "``" + `
`)
	if err := os.WriteFile(tempFile, content, 0644); err != nil {
		t.Fatalf("failed to write temp file: %v", err)
	}

	mock := &mockReporter{}
	changelogDir := filepath.Join("..", "..", "docs", "changelog")
	repoRoot, err := filepath.Abs(filepath.Join(changelogDir, "..", ".."))
	if err != nil {
		t.Fatalf("failed to get absolute path of repository root: %v", err)
	}

	validateChangelogFile(mock, tempFile, repoRoot)

	if len(mock.errors) == 0 {
		t.Errorf("expected validation to fail for non-existent SHA, but it succeeded without errors")
	} else {
		foundExpectedError := false
		for _, errMsg := range mock.errors {
			if strings.Contains(errMsg, "does not exist in git history!") {
				foundExpectedError = true
				break
			}
		}
		if !foundExpectedError {
			t.Errorf("expected 'does not exist in git history!' error, got: %v", mock.errors)
		}
	}
}
