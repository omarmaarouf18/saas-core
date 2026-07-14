package docgen

import (
	"bufio"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

func TestDartFilesMentionedInStatus(t *testing.T) {
	// Paths relative to shared/infra/docgen
	repoRoot := filepath.Join("..", "..", "..")
	statusPath := filepath.Join(repoRoot, "docs", "frontend", "STATUS.md")
	
	statusBytes, err := os.ReadFile(statusPath)
	if err != nil {
		t.Fatalf("failed to read %s: %v", statusPath, err)
	}
	statusContent := string(statusBytes)

	// Scan directories
	dirsToCheck := []string{
		filepath.Join(repoRoot, "frontend", "lib", "screens"),
		filepath.Join(repoRoot, "frontend", "lib", "providers"),
		filepath.Join(repoRoot, "frontend", "lib", "models"),
	}

	for _, dir := range dirsToCheck {
		if _, err := os.Stat(dir); os.IsNotExist(err) {
			t.Logf("Directory %s does not exist, skipping", dir)
			continue
		}

		err := filepath.Walk(dir, func(path string, info os.FileInfo, err error) error {
			if err != nil {
				return err
			}
			if !info.IsDir() && strings.HasSuffix(info.Name(), ".dart") {
				basename := info.Name()
				if !strings.Contains(statusContent, basename) {
					t.Errorf("Dart file %q (at %s) is not mentioned anywhere in docs/frontend/STATUS.md! Please document its current implementation state in STATUS.md.", basename, path)
				}
			}
			return nil
		})
		if err != nil {
			t.Fatalf("error walking directory %s: %v", dir, err)
		}
	}
}

func TestPubspecDependenciesInDesignDoc(t *testing.T) {
	// Paths relative to shared/infra/docgen
	repoRoot := filepath.Join("..", "..", "..")
	designPath := filepath.Join(repoRoot, "DESIGN.md")
	pubspecPath := filepath.Join(repoRoot, "frontend", "pubspec.yaml")

	designBytes, err := os.ReadFile(designPath)
	if err != nil {
		t.Fatalf("failed to read %s: %v", designPath, err)
	}
	designContent := string(designBytes)

	pubspecFile, err := os.Open(pubspecPath)
	if err != nil {
		t.Fatalf("failed to open %s: %v", pubspecPath, err)
	}
	defer pubspecFile.Close()

	// Parse pubspec dependencies
	dependencies := make(map[string]string)
	scanner := bufio.NewScanner(pubspecFile)
	inDependencies := false
	for scanner.Scan() {
		line := scanner.Text()
		trimmed := strings.TrimSpace(line)
		if trimmed == "dependencies:" {
			inDependencies = true
			continue
		}
		if inDependencies && (strings.HasSuffix(line, ":") && !strings.HasPrefix(line, " ")) {
			// Left dependencies section
			inDependencies = false
		}
		if inDependencies && trimmed != "" && !strings.HasPrefix(trimmed, "#") {
			parts := strings.SplitN(trimmed, ":", 2)
			if len(parts) == 2 {
				pkgName := strings.TrimSpace(parts[0])
				pkgVersion := strings.TrimSpace(parts[1])
				// Clean version (remove quotes)
				pkgVersion = strings.Trim(pkgVersion, "\"'")
				if pkgName != "flutter" && pkgVersion != "sdk" {
					dependencies[pkgName] = pkgVersion
				}
			}
		}
	}

	// Regex to find `pkg` (`version`) in DESIGN.md
	// Matches: `provider` (`^6.1.5`)
	pkgVersionRegex := regexp.MustCompile("`([a-zA-Z0-9_-]+)` \\(`([^`]+)`\\)")
	matches := pkgVersionRegex.FindAllStringSubmatch(designContent, -1)

	if len(matches) == 0 {
		t.Log("No dependency version strings found in DESIGN.md to validate")
		return
	}

	for _, match := range matches {
		pkgName := match[1]
		quotedVersion := match[2]

		pubspecVersion, found := dependencies[pkgName]
		if found {
			if pubspecVersion != quotedVersion {
				t.Errorf("Dependency version mismatch for %q: DESIGN.md quotes %q but frontend/pubspec.yaml specifies %q. Please align them.", pkgName, quotedVersion, pubspecVersion)
			}
		}
	}
}
