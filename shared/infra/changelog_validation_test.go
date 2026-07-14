package infra

import (
	"bufio"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

func TestChangelogCommitSHAs(t *testing.T) {
	// Path to docs/changelog relative to shared/infra
	changelogDir := filepath.Join("..", "..", "docs", "changelog")

	files, err := filepath.Glob(filepath.Join(changelogDir, "*.md"))
	if err != nil {
		t.Fatalf("failed to glob changelog files: %v", err)
	}

	if len(files) == 0 {
		t.Fatalf("no changelog files found in %s", changelogDir)
	}

	// Regex to match a 40-character hexadecimal SHA wrapped in double backticks: ``[0-9a-f]{40}``
	validSHARegex := regexp.MustCompile("^``[0-9a-f]{40}``$")

	for _, file := range files {
		t.Run(filepath.Base(file), func(t *testing.T) {
			f, err := os.Open(file)
			if err != nil {
				t.Fatalf("failed to open file %s: %v", file, err)
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
					}
				}
			}

			if err := scanner.Err(); err != nil {
				t.Fatalf("error reading file %s: %v", file, err)
			}
		})
	}
}
