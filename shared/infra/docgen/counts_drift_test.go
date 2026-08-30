package docgen

import (
	"path/filepath"
	"testing"
)

func TestDocsCountsVerification(t *testing.T) {
	repoRoot := filepath.Join("..", "..", "..")
	errs := VerifyDocsCounts(repoRoot)
	if len(errs) > 0 {
		for _, err := range errs {
			t.Errorf("Documentation count drift detected: %v", err)
		}
		t.Logf("Hint: Run 'make docs-counts' or update documentation files to match current counts.")
	}
}
