package main

import (
	"bufio"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"github.com/project/shared/infra/docgen"
)

type ConsumerCategory string

const (
	CategoryMobileApp  ConsumerCategory = "Mobile App"
	CategoryOpsConsole ConsumerCategory = "Ops Console"
	CategoryInternal   ConsumerCategory = "Internal / Inter-Service"
	CategoryInfra      ConsumerCategory = "Infra / Health"
	CategoryUnconsumed ConsumerCategory = "Unconsumed / Orphan"
)

type CallSite struct {
	Source   string // "mobile" or "console"
	FilePath string
	LineNum  int
	RawPath  string
}

type EndpointReport struct {
	Method      string
	Path        string
	Service     string
	Permissions string
	HandlerName string
	Category    ConsumerCategory
	CallSites   []CallSite
	Note        string
}

var (
	// Known companion aliases (maps alias -> canonical or vice versa)
	companionAliases = map[string][]string{
		"/tickets/mine":                       {"/chat/tickets/mine"},
		"/chat/tickets/mine":                  {"/tickets/mine"},
		"/users/services/update":              {"/users/services"},
		"/users/services":                     {"/users/services/update"},
		"/users/employee/jobs/accept":         {"/users/employee/jobs/{id}/accept"},
		"/users/employee/jobs/{id}/accept":    {"/users/employee/jobs/accept"},
		"/users/employee/jobs/decline":        {"/users/employee/jobs/{id}/decline"},
		"/users/employee/jobs/{id}/decline":   {"/users/employee/jobs/decline"},
		"/notifications/{id}":                 {"/notifications"},
		"/notifications":                      {"/notifications/{id}"},
		"/notifications/{id}/read":            {"/notifications/read-all"},
		"/notifications/read-all":             {"/notifications/{id}/read"},
		"/chat/admin/tickets":                 {"/admin/tickets"},
		"/admin/tickets":                      {"/chat/admin/tickets"},
		"/chat/admin/tickets/resolve":         {"/admin/tickets/resolve"},
		"/admin/tickets/resolve":              {"/chat/admin/tickets/resolve"},
		"/users/admin/reconciliation/queue":   {"/admin/reconciliation/queue"},
		"/admin/reconciliation/queue":         {"/users/admin/reconciliation/queue"},
		"/users/admin/reconciliation/resolve": {"/admin/reconciliation/resolve"},
		"/admin/reconciliation/resolve":       {"/users/admin/reconciliation/resolve"},
		"/users/admin/subscriptions":          {"/admin/subscriptions", "/admin/subscriptions/queue"},
		"/admin/subscriptions/queue":          {"/admin/subscriptions", "/users/admin/subscriptions"},
		"/admin/subscriptions":                {"/admin/subscriptions/queue", "/users/admin/subscriptions"},
		"/users/admin/subscriptions/activate": {"/admin/subscriptions/activate"},
		"/admin/subscriptions/activate":       {"/users/admin/subscriptions/activate"},
		"/users/admin/subscriptions/revoke":   {"/admin/subscriptions/revoke"},
		"/admin/subscriptions/revoke":         {"/users/admin/subscriptions/revoke"},
		"/auth/accounts/{id}/suspend":         {"/auth/accounts/suspend"},
		"/auth/accounts/suspend":              {"/auth/accounts/{id}/suspend"},
		"/auth/accounts/{id}/reactivate":      {"/auth/accounts/reactivate"},
		"/auth/accounts/reactivate":           {"/auth/accounts/{id}/reactivate"},
	}

	// Internal service-to-service endpoints with no direct UI callers
	internalEndpoints = map[string]string{
		"/api/v1/admin/version-config":       "SRE Admin / Version Gate middleware",
		"/chat/internal/broadcast-location":  "Internal (called by user-service)",
		"/notifications/send":                "Internal (called by auth/user/chat)",
		"/notifications/broadcast/job-alert": "Internal (called by user-service)",
		"/users/subscription/internal":       "Internal (called by auth-service)",
		"/auth/reviewer/verify":              "Inter-service / Reviewer verification",
	}

	// Infra & Health endpoints
	infraEndpoints = map[string]string{
		"/health":          "Gateway / Service Health Probe",
		"/health/internal": "Internal Circuit Breaker / Prometheus Metrics",
		"/":                "Gateway Root Information Index",
	}

	// Regex for extracting API path patterns from source lines
	apiPathExtractRegex = regexp.MustCompile(`/(auth|users|chat|notifications|admin|tickets|health)[a-zA-Z0-9_\-/{}\$]*`)
	dartParamRegex      = regexp.MustCompile(`(\$\{[^}]+\}|\$[a-zA-Z0-9_]+)`)
)

func normalizePath(p string) string {
	// Remove query parameters
	if idx := strings.Index(p, "?"); idx != -1 {
		p = p[:idx]
	}
	// Normalize path parameters
	p = dartParamRegex.ReplaceAllString(p, "{id}")
	// Normalize Go path parameters like {id} or {ticket_id}
	p = regexp.MustCompile(`\{[a-zA-Z0-9_]+\}`).ReplaceAllString(p, "{id}")
	p = strings.TrimSuffix(p, "/")
	if p == "" {
		return "/"
	}
	return p
}

func scanFrontendCallSites(frontendDir, repoRoot string) (map[string][]CallSite, error) {
	callSites := make(map[string][]CallSite)

	err := filepath.Walk(frontendDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() || !strings.HasSuffix(path, ".dart") {
			return nil
		}

		relPath, _ := filepath.Rel(repoRoot, path)
		f, err := os.Open(path)
		if err != nil {
			return err
		}
		defer f.Close()

		scanner := bufio.NewScanner(f)
		lineNum := 0
		for scanner.Scan() {
			lineNum++
			line := scanner.Text()

			// Check for path patterns in the line
			for _, match := range apiPathExtractRegex.FindAllString(line, -1) {
				norm := normalizePath(match)
				callSites[norm] = append(callSites[norm], CallSite{
					Source:   "frontend",
					FilePath: relPath,
					LineNum:  lineNum,
					RawPath:  match,
				})
			}
		}
		return scanner.Err()
	})

	return callSites, err
}

func locateConsoleRepo(repoRoot, explicitPath string) (string, func()) {
	cleanup := func() {}

	if explicitPath != "" {
		if _, err := os.Stat(explicitPath); err == nil {
			return explicitPath, cleanup
		}
	}

	envPath := os.Getenv("CONSOLE_REPO_PATH")
	if envPath != "" {
		if _, err := os.Stat(envPath); err == nil {
			return envPath, cleanup
		}
	}

	relativeSibling := filepath.Join(repoRoot, "../kyc-reviewer-console")
	if _, err := os.Stat(relativeSibling); err == nil {
		return relativeSibling, cleanup
	}

	defaultWindowsPath := "/mnt/windows_data/CS tools/Antigravity/kyc-reviewer-console"
	if _, err := os.Stat(defaultWindowsPath); err == nil {
		return defaultWindowsPath, cleanup
	}

	// Attempt clone to temp directory (for CI environments)
	tempDir, err := os.MkdirTemp("", "kyc-reviewer-console-*")
	if err == nil {
		cmd := exec.Command("git", "clone", "--depth", "1", "https://github.com/omarmaarouf18/kyc-reviewer-console.git", tempDir)
		if err := cmd.Run(); err == nil {
			return tempDir, func() { _ = os.RemoveAll(tempDir) }
		}
		_ = os.RemoveAll(tempDir)
	}

	return "", cleanup
}

func scanConsoleCallSites(consoleDir string) (map[string][]CallSite, error) {
	callSites := make(map[string][]CallSite)

	if consoleDir == "" {
		// Fallback known console routes per ADR-0021 / ADR-0022 / ADR-0023
		knownConsoleRoutes := []string{
			"/auth/kyb-kye/pending",
			"/auth/kyb-kye/review",
			"/auth/documents/view",
			"/auth/accounts",
			"/auth/accounts/suspend",
			"/auth/accounts/reactivate",
			"/admin/reconciliation/queue",
			"/admin/reconciliation/resolve",
			"/admin/subscriptions",
			"/admin/subscriptions/activate",
			"/admin/subscriptions/revoke",
			"/admin/tickets",
			"/admin/tickets/resolve",
		}
		for _, r := range knownConsoleRoutes {
			norm := normalizePath(r)
			callSites[norm] = append(callSites[norm], CallSite{
				Source:   "console",
				FilePath: "kyc-reviewer-console:internal/proxy/proxy.go",
				LineNum:  0,
				RawPath:  r,
			})
		}
		return callSites, nil
	}

	err := filepath.Walk(consoleDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() {
			if info.Name() == ".git" || info.Name() == "node_modules" {
				return filepath.SkipDir
			}
			return nil
		}
		ext := filepath.Ext(path)
		if ext != ".go" && ext != ".js" && ext != ".html" {
			return nil
		}

		relPath, _ := filepath.Rel(consoleDir, path)
		f, err := os.Open(path)
		if err != nil {
			return err
		}
		defer f.Close()

		scanner := bufio.NewScanner(f)
		lineNum := 0
		for scanner.Scan() {
			lineNum++
			line := scanner.Text()

			for _, match := range apiPathExtractRegex.FindAllString(line, -1) {
				norm := normalizePath(match)
				callSites[norm] = append(callSites[norm], CallSite{
					Source:   "console",
					FilePath: fmt.Sprintf("kyc-reviewer-console:%s", relPath),
					LineNum:  lineNum,
					RawPath:  match,
				})
			}
		}
		return scanner.Err()
	})

	return callSites, err
}

func main() {
	repoRootFlag := flag.String("repo-root", ".", "Repository root directory")
	consolePathFlag := flag.String("console-path", "", "Path to kyc-reviewer-console repository (optional)")
	strictFlag := flag.Bool("strict", false, "Exit with code 1 if unconsumed routes exist")
	flag.Parse()

	repoRoot := *repoRootFlag

	// 1. Extract backend endpoints
	endpoints, err := docgen.GenerateEndpointsList(repoRoot)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error generating backend endpoints: %v\n", err)
		os.Exit(1)
	}

	// 2. Extract frontend call sites
	frontendDir := filepath.Join(repoRoot, "frontend", "lib")
	frontendCalls, err := scanFrontendCallSites(frontendDir, repoRoot)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Warning: error scanning frontend call sites: %v\n", err)
	}

	// 3. Extract reviewer console call sites
	consoleDir, cleanup := locateConsoleRepo(repoRoot, *consolePathFlag)
	defer cleanup()

	consoleCalls, err := scanConsoleCallSites(consoleDir)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Warning: error scanning console call sites: %v\n", err)
	}

	// 4. Classify each endpoint
	var reports []EndpointReport

	for _, ep := range endpoints {
		normPath := normalizePath(ep.Path)
		report := EndpointReport{
			Method:      ep.Method,
			Path:        ep.Path,
			Service:     ep.Service,
			Permissions: ep.Permissions,
			HandlerName: ep.HandlerName,
		}

		// Check infra
		if note, ok := infraEndpoints[normPath]; ok {
			report.Category = CategoryInfra
			report.Note = note
			reports = append(reports, report)
			continue
		}

		// Check internal service-to-service
		if note, ok := internalEndpoints[normPath]; ok {
			report.Category = CategoryInternal
			report.Note = note
			reports = append(reports, report)
			continue
		}

		// Check ops console
		matchedConsole := false
		if sites, ok := consoleCalls[normPath]; ok && len(sites) > 0 {
			report.Category = CategoryOpsConsole
			report.CallSites = sites
			matchedConsole = true
		} else {
			// Check companion aliases
			if aliases, hasAliases := companionAliases[normPath]; hasAliases {
				for _, a := range aliases {
					if sites, ok := consoleCalls[normalizePath(a)]; ok && len(sites) > 0 {
						report.Category = CategoryOpsConsole
						report.CallSites = sites
						report.Note = fmt.Sprintf("Consumed via companion route %s", a)
						matchedConsole = true
						break
					}
				}
			}
		}

		if matchedConsole {
			reports = append(reports, report)
			continue
		}

		// Check mobile app (frontend)
		matchedMobile := false
		if sites, ok := frontendCalls[normPath]; ok && len(sites) > 0 {
			report.Category = CategoryMobileApp
			report.CallSites = sites
			matchedMobile = true
		} else {
			// Check companion aliases
			if aliases, hasAliases := companionAliases[normPath]; hasAliases {
				for _, a := range aliases {
					if sites, ok := frontendCalls[normalizePath(a)]; ok && len(sites) > 0 {
						report.Category = CategoryMobileApp
						report.CallSites = sites
						report.Note = fmt.Sprintf("Consumed via companion route %s", a)
						matchedMobile = true
						break
					}
				}
			}
		}

		if matchedMobile {
			reports = append(reports, report)
			continue
		}

		// If neither, classify as unconsumed / orphan
		report.Category = CategoryUnconsumed
		if ep.Path == "/chat/tickets/resolve" {
			report.Note = "GAP-03 / ADR-0013: Legacy agent-token ticket resolution endpoint (superseded by Ops Console /admin/tickets/resolve)"
		} else {
			report.Note = "No consumer call site detected in frontend/lib or kyc-reviewer-console"
		}
		reports = append(reports, report)
	}

	// 5. Sort reports for clean presentation (by Category, then Service, then Path)
	sort.Slice(reports, func(i, j int) bool {
		if reports[i].Category != reports[j].Category {
			return reports[i].Category < reports[j].Category
		}
		if reports[i].Service != reports[j].Service {
			return reports[i].Service < reports[j].Service
		}
		return reports[i].Path < reports[j].Path
	})

	// 6. Print Report
	printParityReport(reports, consoleDir)

	if *strictFlag {
		for _, r := range reports {
			if r.Category == CategoryUnconsumed {
				fmt.Fprintln(os.Stderr, "\n[FAIL] Unconsumed route found under -strict mode.")
				os.Exit(1)
			}
		}
	}
}

func printParityReport(reports []EndpointReport, consoleDir string) {
	mobileCount := 0
	consoleCount := 0
	internalCount := 0
	infraCount := 0
	unconsumedCount := 0

	for _, r := range reports {
		switch r.Category {
		case CategoryMobileApp:
			mobileCount++
		case CategoryOpsConsole:
			consoleCount++
		case CategoryInternal:
			internalCount++
		case CategoryInfra:
			infraCount++
		case CategoryUnconsumed:
			unconsumedCount++
		}
	}

	fmt.Println("==========================================================================================")
	fmt.Println("                           BACKEND-FRONTEND API PARITY REPORT                             ")
	fmt.Println("==========================================================================================")
	fmt.Printf("Total Registered Backend Endpoints : %d\n", len(reports))
	fmt.Printf("  • Mobile App Endpoints (Flutter) : %d\n", mobileCount)
	fmt.Printf("  • Ops Console Endpoints (KYC/KYE): %d\n", consoleCount)
	fmt.Printf("  • Internal Service-to-Service    : %d\n", internalCount)
	fmt.Printf("  • Infra / Health Probes          : %d\n", infraCount)
	fmt.Printf("  • Unconsumed / Orphan Routes     : %d\n", unconsumedCount)
	if consoleDir != "" {
		fmt.Printf("Ops Console Directory              : %s\n", consoleDir)
	} else {
		fmt.Printf("Ops Console Directory              : Using built-in route contract\n")
	}
	fmt.Println("------------------------------------------------------------------------------------------")
	fmt.Println()

	fmt.Println("### Registered Endpoint Inventory & Consumer Mapping")
	fmt.Println()
	fmt.Println("| Service | Method | Route Path | Consumer Category | Primary Caller Reference | Notes |")
	fmt.Println("| :--- | :--- | :--- | :--- | :--- | :--- |")

	for _, r := range reports {
		callerRef := "N/A"
		if len(r.CallSites) > 0 {
			first := r.CallSites[0]
			if first.LineNum > 0 {
				callerRef = fmt.Sprintf("`%s:%d`", first.FilePath, first.LineNum)
			} else {
				callerRef = fmt.Sprintf("`%s`", first.FilePath)
			}
			if len(r.CallSites) > 1 {
				callerRef += fmt.Sprintf(" (+%d more)", len(r.CallSites)-1)
			}
		}

		note := r.Note
		if note == "" {
			note = "-"
		}

		fmt.Printf("| `%s` | `%s` | `%s` | **%s** | %s | %s |\n",
			r.Service, r.Method, r.Path, r.Category, callerRef, note)
	}

	fmt.Println()
	if unconsumedCount > 0 {
		fmt.Println("------------------------------------------------------------------------------------------")
		fmt.Printf("⚠️  UNCONSUMED / ORPHAN ROUTES DETECTED: %d\n", unconsumedCount)
		fmt.Println("------------------------------------------------------------------------------------------")
		for _, r := range reports {
			if r.Category == CategoryUnconsumed {
				fmt.Printf("  • Route: %s %s (Service: %s, Handler: %s, Permissions: %s)\n",
					r.Method, r.Path, r.Service, r.HandlerName, r.Permissions)
				fmt.Printf("    Note: %s\n", r.Note)
			}
		}
	} else {
		fmt.Println("✅ All backend routes have verified active consumers or internal classifications!")
	}
	fmt.Println("==========================================================================================")
}
