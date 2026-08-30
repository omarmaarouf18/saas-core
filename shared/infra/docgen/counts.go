package docgen

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

// DocsCounts captures falsifiable component and documentation counts across the repo.
type DocsCounts struct {
	ChangelogCounts map[string]int `json:"changelog_counts"`
	TotalChangelog  int            `json:"total_changelog"`
	ScreenFiles     int            `json:"screen_files"`
	WidgetFiles     int            `json:"widget_files"`
	ProviderFiles   int            `json:"provider_files"`
	ModelFiles      int            `json:"model_files"`
	ArbKeysEn       int            `json:"arb_keys_en"`
	ArbKeysAr       int            `json:"arb_keys_ar"`
}

// GetDocsCounts inspects the repository and tallies exact current component & changelog counts.
func GetDocsCounts(repoRoot string) (*DocsCounts, error) {
	counts := &DocsCounts{
		ChangelogCounts: make(map[string]int),
	}

	// 1. Changelog entries (count lines matching `^## ` in docs/changelog/*.md)
	changelogDir := filepath.Clean(filepath.Join(repoRoot, "docs", "changelog"))
	entries, err := os.ReadDir(changelogDir)
	if err != nil {
		return nil, fmt.Errorf("failed to read changelog dir %s: %w", changelogDir, err)
	}

	headerRegex := regexp.MustCompile(`^##\s+`)
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".md") || entry.Name() == "README.md" {
			continue
		}
		path := filepath.Clean(filepath.Join(changelogDir, entry.Name()))
		// #nosec G304 //nolint:gosec -- path is constructed within local repository root, not user-controlled
		f, err := os.Open(path)
		if err != nil {
			return nil, fmt.Errorf("failed to open %s: %w", path, err)
		}
		scanner := bufio.NewScanner(f)
		count := 0
		for scanner.Scan() {
			if headerRegex.MatchString(scanner.Text()) {
				count++
			}
		}
		_ = f.Close()
		counts.ChangelogCounts[entry.Name()] = count
		counts.TotalChangelog += count
	}

	// 2. Flutter Dart file counts
	countDartFiles := func(relDir string) (int, error) {
		dir := filepath.Clean(filepath.Join(repoRoot, relDir))
		dirEntries, err := os.ReadDir(dir)
		if err != nil {
			if os.IsNotExist(err) {
				return 0, nil
			}
			return 0, err
		}
		total := 0
		for _, e := range dirEntries {
			if !e.IsDir() && strings.HasSuffix(e.Name(), ".dart") {
				total++
			}
		}
		return total, nil
	}

	var errCount error
	if counts.ScreenFiles, errCount = countDartFiles("frontend/lib/screens"); errCount != nil {
		return nil, errCount
	}
	if counts.WidgetFiles, errCount = countDartFiles("frontend/lib/widgets"); errCount != nil {
		return nil, errCount
	}
	if counts.ProviderFiles, errCount = countDartFiles("frontend/lib/providers"); errCount != nil {
		return nil, errCount
	}
	if counts.ModelFiles, errCount = countDartFiles("frontend/lib/models"); errCount != nil {
		return nil, errCount
	}

	// 3. ARB Localization keys
	countArbKeys := func(relPath string) (int, error) {
		p := filepath.Clean(filepath.Join(repoRoot, relPath))
		// #nosec G304 //nolint:gosec -- path is constructed within local repository root, not user-controlled
		data, err := os.ReadFile(p)
		if err != nil {
			return 0, err
		}
		var parsed map[string]interface{}
		if err := json.Unmarshal(data, &parsed); err != nil {
			return 0, err
		}
		total := 0
		for k := range parsed {
			if !strings.HasPrefix(k, "@") {
				total++
			}
		}
		return total, nil
	}

	if counts.ArbKeysEn, errCount = countArbKeys("frontend/lib/l10n/app_en.arb"); errCount != nil {
		return nil, errCount
	}
	if counts.ArbKeysAr, errCount = countArbKeys("frontend/lib/l10n/app_ar.arb"); errCount != nil {
		return nil, errCount
	}

	return counts, nil
}

// PrintDocsCounts formats and outputs the counts report to stdout.
func PrintDocsCounts(counts *DocsCounts) {
	fmt.Println("==================================================")
	fmt.Println("       DOCUMENTATION & REPO METRICS REPORT        ")
	fmt.Println("==================================================")
	fmt.Printf("Frontend Screen Files:   %d\n", counts.ScreenFiles)
	fmt.Printf("Frontend Shared Widgets: %d\n", counts.WidgetFiles)
	fmt.Printf("Frontend State Providers:%d\n", counts.ProviderFiles)
	fmt.Printf("Frontend Data Models:    %d\n", counts.ModelFiles)
	fmt.Printf("ARB Keys (en / ar):      %d / %d (symmetric: %t)\n", counts.ArbKeysEn, counts.ArbKeysAr, counts.ArbKeysEn == counts.ArbKeysAr)
	fmt.Println("--------------------------------------------------")
	fmt.Println("Changelog Entries Breakdown:")

	var names []string
	for name := range counts.ChangelogCounts {
		names = append(names, name)
	}
	sort.Strings(names)
	for _, name := range names {
		fmt.Printf("  - %-32s : %d\n", name, counts.ChangelogCounts[name])
	}
	fmt.Printf("Total Changelog Entries: %d\n", counts.TotalChangelog)
	fmt.Println("==================================================")
}

// VerifyDocsCounts checks whether key documentation files reflect current counts.
func VerifyDocsCounts(repoRoot string) []error {
	var errs []error
	counts, err := GetDocsCounts(repoRoot)
	if err != nil {
		return []error{err}
	}

	// 1. Check ARB symmetry
	if counts.ArbKeysEn != counts.ArbKeysAr {
		errs = append(errs, fmt.Errorf("ARB localization key mismatch: app_en.arb has %d keys, app_ar.arb has %d keys", counts.ArbKeysEn, counts.ArbKeysAr))
	}

	// 2. Check docs/changelog/README.md
	readmePath := filepath.Clean(filepath.Join(repoRoot, "docs", "changelog", "README.md"))
	// #nosec G304 //nolint:gosec -- path is constructed within local repository root, not user-controlled
	readmeBytes, err := os.ReadFile(readmePath)
	if err != nil {
		errs = append(errs, fmt.Errorf("failed to read %s: %w", readmePath, err))
	} else {
		readmeText := string(readmeBytes)
		for filename, expectedCount := range counts.ChangelogCounts {
			pattern := regexp.MustCompile(`\[[^\]]+\]\(` + regexp.QuoteMeta(filename) + `\)\s+—\s+(\d+)\s+entries`)
			matches := pattern.FindStringSubmatch(readmeText)
			if len(matches) == 2 {
				var countInDoc int
				_, _ = fmt.Sscanf(matches[1], "%d", &countInDoc)
				if countInDoc != expectedCount {
					errs = append(errs, fmt.Errorf("docs/changelog/README.md lists %d entries for %s, but actual count is %d", countInDoc, filename, expectedCount))
				}
			}
		}
	}

	// 3. Check DESIGN.md widget count
	designPath := filepath.Clean(filepath.Join(repoRoot, "DESIGN.md"))
	// #nosec G304 //nolint:gosec -- path is constructed within local repository root, not user-controlled
	if designBytes, err := os.ReadFile(designPath); err == nil {
		re := regexp.MustCompile(`(\d+)\s+reusable widgets in frontend/lib/widgets/`)
		if m := re.FindStringSubmatch(string(designBytes)); len(m) == 2 {
			var wCount int
			_, _ = fmt.Sscanf(m[1], "%d", &wCount)
			if wCount != counts.WidgetFiles {
				errs = append(errs, fmt.Errorf("DESIGN.md claims %d reusable widgets, but frontend/lib/widgets/ has %d files", wCount, counts.WidgetFiles))
			}
		}
	}

	// 4. Check docs/frontend/DESIGN_SYSTEM.md widget count
	designSystemPath := filepath.Clean(filepath.Join(repoRoot, "docs", "frontend", "DESIGN_SYSTEM.md"))
	// #nosec G304 //nolint:gosec -- path is constructed within local repository root, not user-controlled
	if dsBytes, err := os.ReadFile(designSystemPath); err == nil {
		re := regexp.MustCompile(`catalog of (\d+) shared widgets`)
		if m := re.FindStringSubmatch(string(dsBytes)); len(m) == 2 {
			var wCount int
			_, _ = fmt.Sscanf(m[1], "%d", &wCount)
			if wCount != counts.WidgetFiles {
				errs = append(errs, fmt.Errorf("docs/frontend/DESIGN_SYSTEM.md claims %d shared widgets, but frontend/lib/widgets/ has %d files", wCount, counts.WidgetFiles))
			}
		}
	}

	return errs
}
