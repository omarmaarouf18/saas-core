package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/project/shared/infra/docgen"
)

func main() {
	checkOnly := flag.Bool("check", false, "only check if docs are up to date, don't overwrite")
	flag.Parse()

	repoRoot := "." // Assume run from root of workspace
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
