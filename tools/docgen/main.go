package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/project/shared/infra/docgen"
)

func main() {
	checkOnly := flag.Bool("check", false, "only check if docs are up to date, don't overwrite")
	countsOnly := flag.Bool("counts", false, "display documentation component and changelog metrics")
	flag.Parse()

	repoRoot := "." // Assume run from root of workspace

	if *countsOnly {
		counts, err := docgen.GetDocsCounts(repoRoot)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error calculating documentation counts: %v\n", err)
			os.Exit(1)
		}
		docgen.PrintDocsCounts(counts)

		errs := docgen.VerifyDocsCounts(repoRoot)
		if len(errs) > 0 {
			fmt.Println("\n[DRIFT WARNINGS]")
			for _, e := range errs {
				fmt.Printf("  ⚠️ %v\n", e)
			}
			os.Exit(1)
		}
		fmt.Println("\n✅ All documented counts match reality!")
		return
	}

	changed, _, err := docgen.UpdateApplicationMap(repoRoot, *checkOnly)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error updating APPLICATION_MAP.md: %v\n", err)
		os.Exit(1)
	}

	if *checkOnly {
		if changed {
			fmt.Println("APPLICATION_MAP.md is out of sync with route definitions! Run 'make docs' to regenerate.")
			os.Exit(1)
		}
		fmt.Println("APPLICATION_MAP.md is fresh.")
		return
	}

	if changed {
		fmt.Println("APPLICATION_MAP.md updated successfully.")
	} else {
		fmt.Println("No changes to APPLICATION_MAP.md.")
	}
}
