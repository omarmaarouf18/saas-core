package docgen

import (
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

// Endpoint represents a parsed HTTP endpoint
type Endpoint struct {
	Method      string
	Path        string
	Service     string
	Permissions string
	Function    string
	Targets     string
	HandlerName string
}

// KnownEndpoints contains verified info for current endpoints
var KnownEndpoints = map[string]struct {
	Permissions string
	Function    string
	Targets     string
}{
	// api-gateway static routes
	"GET /health": {
		Permissions: "Public",
		Function:    "Public gateway health status.",
		Targets:     "None.",
	},
	"GET /health/internal": {
		Permissions: "`X-Internal-Token`",
		Function:    "Returns circuit breaker metrics.",
		Targets:     "Reads breaker memory.",
	},
	"GET /": {
		Permissions: "Public",
		Function:    "Root index.",
		Targets:     "None.",
	},

	// auth-service
	"GET /health (auth-service)": {
		Permissions: "Public (Internal)",
		Function:    "Public service health status.",
		Targets:     "None.",
	},
	"GET / (auth-service)": {
		Permissions: "Public (Internal)",
		Function:    "Service version and status.",
		Targets:     "None.",
	},
	"POST /auth/signup": {
		Permissions: "Public (via Gateway)",
		Function:    "Registers a new tenant or user.",
		Targets:     "Writes `users` collection. Logs OTP code.",
	},
	"POST /auth/login": {
		Permissions: "Public (via Gateway)",
		Function:    "Logs in user, dispatches 2FA OTP.",
		Targets:     "Reads/writes `users` collection (OTP/attempts). Writes `audit_logs`.",
	},
	"POST /auth/verify-otp": {
		Permissions: "Public (via Gateway)",
		Function:    "Validates 2FA OTP, issues JWT.",
		Targets:     "Reads/writes `users` collection. Writes `audit_logs`.",
	},
	"POST /auth/refresh": {
		Permissions: "Public (via Gateway)",
		Function:    "Refreshes active JWT sessions.",
		Targets:     "None.",
	},
	"POST /auth/resend-otp": {
		Permissions: "Public",
		Function:    "ResendOTP handles resending a fresh OTP for unconfirmed accounts.",
		Targets:     "Reads `users` collection by email, updates `otp_code` and `otp_expires_at` fields.",
	},
	"POST /auth/logout": {
		Permissions: "Bearer JWT",
		Function:    "Logs out user, revokes JWT session.",
		Targets:     "Writes token JTI to Redis denylist.",
	},
	"POST /auth/employee/toggle": {
		Permissions: "Owner JWT (KYC Approved)",
		Function:    "Activates/deactivates employee account.",
		Targets:     "Reads `users` (owner/employee), updates `users`.",
	},
	"POST /auth/employee/action": {
		Permissions: "Target Employee JWT",
		Function:    "Records a simulated worker activity.",
		Targets:     "Writes `audit_logs` collection.",
	},
	"GET /auth/audit-log": {
		Permissions: "Tenant Owner JWT",
		Function:    "Fetches tenant security audit logs.",
		Targets:     "Reads `audit_logs` collection.",
	},
	"POST /auth/kyb/upload": {
		Permissions: "Owner JWT",
		Function:    "Uploads KYB verification files (ID front/back, selfie, business proof).",
		Targets:     "Writes uploaded documents to local storage. Updates `users` collection.",
	},
	"POST /auth/kye/upload": {
		Permissions: "Employee JWT",
		Function:    "Uploads KYE verification files (ID front/back, selfie).",
		Targets:     "Writes uploaded documents to local storage. Updates `users` collection.",
	},
	"GET /auth/kyb-kye/pending": {
		Permissions: "Reviewer Token & `X-Internal-Token`",
		Function:    "Fetches pending KYB verification submissions.",
		Targets:     "Reads `users` and `reviewers` collections.",
	},
	"POST /auth/kyb-kye/review": {
		Permissions: "Reviewer Token & `X-Internal-Token`",
		Function:    "Approves or rejects KYB submissions.",
		Targets:     "Updates `users` status. Writes `audit_logs` and `reviewers`.",
	},
	"GET /auth/documents/view": {
		Permissions: "Reviewer Token & `X-Internal-Token`",
		Function:    "Validates signed URL token and streams/serves the uploaded document file.",
		Targets:     "Streams file content.",
	},
	"GET /auth/user": {
		Permissions: "`X-Internal-Token` OR User JWT",
		Function:    "Resolves user profile and role details.",
		Targets:     "Reads `users` collection.",
	},

	// chat-service
	"GET /health (chat-service)": {
		Permissions: "Public (Internal)",
		Function:    "Service health status.",
		Targets:     "None.",
	},
	"GET / (chat-service)": {
		Permissions: "Public (Internal)",
		Function:    "Service status and runtime info.",
		Targets:     "None.",
	},
	"GET /chat/ws": {
		Permissions: "User JWT OR Agent Token",
		Function:    "WebSocket connection upgrade path.",
		Targets:     "Reads `support_agents` (for agent tokens). Downstream: calls `auth-service/auth/user`.",
	},
	"GET /chat/history": {
		Permissions: "Channel Member JWT",
		Function:    "Retrieves channel chat history.",
		Targets:     "Reads `chat_messages` collection. Downstream: calls `user-service/users/jobs/get`.",
	},
	"POST /chat/internal/broadcast-location": {
		Permissions: "`X-Internal-Token`",
		Function:    "Broadcasts driver location event.",
		Targets:     "None.",
	},
	"POST /chat/tickets": {
		Permissions: "User JWT",
		Function:    "Submits complaint ticket & assigns agent.",
		Targets:     "Reads/writes `complaint_tickets` and `support_agents` (atomic).",
	},
	"POST /chat/tickets/resolve": {
		Permissions: "Support Agent Token",
		Function:    "Resolves ticket & releases agent status.",
		Targets:     "Updates `complaint_tickets` and `support_agents`.",
	},

	// notification-service
	"GET /health (notification-service)": {
		Permissions: "Public (Internal)",
		Function:    "Returns SSE hub client active stats.",
		Targets:     "Reads SSE Hub client statistics.",
	},
	"GET / (notification-service)": {
		Permissions: "Public (Internal)",
		Function:    "Service details and status.",
		Targets:     "None.",
	},
	"GET /notifications/stream": {
		Permissions: "User JWT",
		Function:    "Opens SSE channel for alerts.",
		Targets:     "Downstream: calls `auth-service/auth/user`.",
	},
	"POST /notifications/send": {
		Permissions: "`X-Internal-Token`",
		Function:    "Sends a targeted popup alert.",
		Targets:     "Dispatches message to SSE client.",
	},
	"POST /notifications/broadcast/job-alert": {
		Permissions: "`X-Internal-Token`",
		Function:    "Broadcasts job alert to employees.",
		Targets:     "Dispatches message to SSE clients.",
	},

	// user-service
	"GET /health (user-service)": {
		Permissions: "Public (Internal)",
		Function:    "Service health status.",
		Targets:     "None.",
	},
	"GET / (user-service)": {
		Permissions: "Public (Internal)",
		Function:    "Service status and details.",
		Targets:     "None.",
	},
	"GET /users/services": {
		Permissions: "Public",
		Function:    "Spatial search on services directory.",
		Targets:     "Reads `services` collection.",
	},
	"POST /users/services": {
		Permissions: "Owner JWT (KYC Approved)",
		Function:    "Inserts service listing.",
		Targets:     "Downstream: calls `auth-service/auth/user`. Writes `services` collection.",
	},
	"POST /users/jobs/track": {
		Permissions: "Owner/Employee JWT (legacy tracking) OR Customer JWT + service_id (owner resolved server-side; supports optional employee pre-assignment)",
		Function:    "Books job with coordinate validation, resolves owner ID, validates optional employee assignment, and broadcasts alert.",
		Targets:     "Downstream: calls `auth-service/auth/user`. Writes `jobs`.",
	},
	"GET /users/jobs/get": {
		Permissions: "`X-Internal-Token` OR User JWT",
		Function:    "Resolves detailed job configuration (single job by ID) OR lists all jobs assigned to the requesting employee.",
		Targets:     "Reads `jobs` collection. Enforces IDOR protection: if `employee_id` query param is provided, it must match the employee identity strictly resolved from the JWT token.",
	},
	"POST /users/jobs/complete": {
		Permissions: "Owner or Employee JWT",
		Function:    "Completes active job, processes fees.",
		Targets:     "Updates `jobs`, writes `wallets`, writes `ledger`.",
	},
	"POST /users/jobs/cancel": {
		Permissions: "Owner JWT (KYC Approved)",
		Function:    "Cancels an active job and processes escrow refunds.",
		Targets:     "Updates `jobs` collection. Updates `wallets` and `ledger` collections.",
	},
	"GET /users/wallet": {
		Permissions: "Owner JWT",
		Function:    "Fetches active balance details.",
		Targets:     "Reads `wallets` collection.",
	},
	"POST /users/wallet/deposit": {
		Permissions: "Owner JWT",
		Function:    "Loads funds up to maximum limits.",
		Targets:     "Updates `wallets` collection.",
	},
	"GET /users/ledger": {
		Permissions: "Owner JWT",
		Function:    "Lists financial ledger records.",
		Targets:     "Reads `ledger` collection.",
	},
	"GET /users/platform/config": {
		Permissions: "Public",
		Function:    "Fetches global fees configuration.",
		Targets:     "Reads `platform_config` collection.",
	},
	"POST /users/subscription": {
		Permissions: "Owner JWT (KYC Approved)",
		Function:    "Subscribes/renews SaaS tier.",
		Targets:     "Updates `subscriptions`, writes `wallets`, writes `ledger`.",
	},
	"POST /users/jobs/rate": {
		Permissions: "Owner or Employee JWT",
		Function:    "Submits a double-blind rating.",
		Targets:     "Writes `ratings`, updates `jobs`.",
	},
	"GET /users/ratings": {
		Permissions: "User JWT",
		Function:    "Returns ratings count and average.",
		Targets:     "Reads `ratings` collection.",
	},
	"POST /users/jobs/location/update": {
		Permissions: "Employee JWT",
		Function:    "Updates driver coordinates (validates coordinate bounds and speed).",
		Targets:     "Reads `jobs`, updates `jobs`. Downstream: calls `chat-service/chat/internal/broadcast-location`.",
	},
}

// HandlerFuncInfo parses a file's AST to gather functions and their comments
type HandlerFuncInfo struct {
	Name string
	Body *ast.BlockStmt
	Doc  string
}

// ParseHandlers parses Go files in the handler directory and extracts functions
func ParseHandlers(dirPath string) (map[string]HandlerFuncInfo, error) {
	fset := token.NewFileSet()
	pkgs, err := parser.ParseDir(fset, dirPath, nil, parser.ParseComments)
	if err != nil {
		return nil, err
	}

	handlers := make(map[string]HandlerFuncInfo)
	for _, pkg := range pkgs {
		for _, file := range pkg.Files {
			for _, decl := range file.Decls {
				funcDecl, ok := decl.(*ast.FuncDecl)
				if !ok {
					continue
				}
				name := funcDecl.Name.Name
				var docText string
				if funcDecl.Doc != nil {
					docText = funcDecl.Doc.Text()
				}
				handlers[name] = HandlerFuncInfo{
					Name: name,
					Body: funcDecl.Body,
					Doc:  docText,
				}
			}
		}
	}
	return handlers, nil
}

// GenerateEndpointsList parses the RegisterRoutes functions and extracts endpoint definitions
func GenerateEndpointsList(repoRoot string) ([]Endpoint, error) {
	var endpoints []Endpoint

	// Add api-gateway static endpoints
	endpoints = append(endpoints, Endpoint{Method: "GET", Path: "/health", Service: "api-gateway", Permissions: "Public", Function: "Public gateway health status.", Targets: "None.", HandlerName: "GatewayHealth"})
	endpoints = append(endpoints, Endpoint{Method: "GET", Path: "/health/internal", Service: "api-gateway", Permissions: "`X-Internal-Token`", Function: "Returns circuit breaker metrics.", Targets: "Reads breaker memory.", HandlerName: "GatewayInternalHealth"})
	endpoints = append(endpoints, Endpoint{Method: "GET", Path: "/", Service: "api-gateway", Permissions: "Public", Function: "Root index.", Targets: "None.", HandlerName: "GatewayIndex"})

	services := []struct {
		Name     string
		FilePath string
		Handlers string
	}{
		{"auth-service", "services/auth-service/internal/handlers/auth.go", "services/auth-service/internal/handlers"},
		{"chat-service", "services/chat-service/internal/handlers/chat.go", "services/chat-service/internal/handlers"},
		{"notification-service", "services/notification-service/internal/handlers/handlers.go", "services/notification-service/internal/handlers"},
		{"user-service", "services/user-service/internal/handlers/handlers.go", "services/user-service/internal/handlers"},
	}

	for _, s := range services {
		fullPath := filepath.Join(repoRoot, s.FilePath)
		handlersDir := filepath.Join(repoRoot, s.Handlers)

		// Parse the handlers package to find doc comments and bodies
		funcMap, err := ParseHandlers(handlersDir)
		if err != nil {
			return nil, fmt.Errorf("failed to parse handler files in %s: %w", handlersDir, err)
		}

		fset := token.NewFileSet()
		node, err := parser.ParseFile(fset, fullPath, nil, parser.ParseComments)
		if err != nil {
			return nil, fmt.Errorf("failed to parse file %s: %w", s.FilePath, err)
		}

		// Find RegisterRoutes function
		var regFunc *ast.FuncDecl
		for _, decl := range node.Decls {
			f, ok := decl.(*ast.FuncDecl)
			if ok && f.Name.Name == "RegisterRoutes" {
				regFunc = f
				break
			}
		}

		if regFunc == nil {
			return nil, fmt.Errorf("RegisterRoutes function not found in %s", s.FilePath)
		}

		// Traverse RegisterRoutes body to find HandleFunc calls
		ast.Inspect(regFunc.Body, func(n ast.Node) bool {
			call, ok := n.(*ast.CallExpr)
			if !ok {
				return true
			}

			sel, ok := call.Fun.(*ast.SelectorExpr)
			if !ok || sel.Sel.Name != "HandleFunc" {
				return true
			}

			// Must have at least 2 args: path and handler
			if len(call.Args) < 2 {
				return true
			}

			// 1. Get Path (arg 0)
			pathLit, ok := call.Args[0].(*ast.BasicLit)
			if !ok || pathLit.Kind != token.STRING {
				return true
			}
			pathVal := strings.Trim(pathLit.Value, "\"")

			// 2. Get Handler Info (arg 1)
			handlerArg := call.Args[1]

			// Case A: inline function (like /users/services)
			if funcLit, ok := handlerArg.(*ast.FuncLit); ok {
				// Let's inspect the switch/ifs inside the inline function to get ListServices/CreateService
				ast.Inspect(funcLit.Body, func(sub ast.Node) bool {
					caseClause, ok := sub.(*ast.CaseClause)
					if !ok {
						return true
					}
					// Check for http.MethodXXX in List
					for _, expr := range caseClause.List {
						selExpr, ok := expr.(*ast.SelectorExpr)
						if !ok {
							continue
						}
						var method string
						switch selExpr.Sel.Name {
						case "MethodGet":
							method = "GET"
						case "MethodPost":
							method = "POST"
						case "MethodPut":
							method = "PUT"
						case "MethodDelete":
							method = "DELETE"
						}
						if method == "" {
							continue
						}

						// Look for the call inside body
						for _, stmt := range caseClause.Body {
							exprStmt, ok := stmt.(*ast.ExprStmt)
							if !ok {
								continue
							}
							subCall, ok := exprStmt.X.(*ast.CallExpr)
							if !ok {
								continue
							}
							subSel, ok := subCall.Fun.(*ast.SelectorExpr)
							if !ok {
								continue
							}
							handlerName := subSel.Sel.Name

							ep := makeEndpoint(method, pathVal, s.Name, handlerName, funcMap)
							endpoints = append(endpoints, ep)
						}
					}
					return true
				})
				return true
			}

			// Case B: selector expression (like a.Signup, c.HandleWebSocket)
			if selExpr, ok := handlerArg.(*ast.SelectorExpr); ok {
				handlerName := selExpr.Sel.Name

				// Let's also search for `/health` and `/` routes and append service name if ambiguity exists
				lookupPath := pathVal
				if pathVal == "/health" || pathVal == "/" {
					lookupPath = fmt.Sprintf("%s (%s)", pathVal, s.Name)
				}

				// Infer method from handler function name prefix by default, then override if known
				method := "GET"
				if strings.HasPrefix(handlerName, "Create") || strings.HasPrefix(handlerName, "Upload") || strings.HasPrefix(handlerName, "Post") || strings.HasPrefix(handlerName, "Signup") || strings.HasPrefix(handlerName, "Login") || strings.HasPrefix(handlerName, "Verify") || strings.HasPrefix(handlerName, "Refresh") || strings.HasPrefix(handlerName, "Toggle") || strings.HasPrefix(handlerName, "Simulate") || strings.HasPrefix(handlerName, "Rate") || strings.HasPrefix(handlerName, "WalletDeposit") || strings.HasPrefix(handlerName, "Subscription") || strings.HasPrefix(handlerName, "Broadcast") || strings.HasPrefix(handlerName, "Send") || strings.HasPrefix(handlerName, "HandleResolveTicket") {
					method = "POST"
				}

				// Check actual code for method override if checks exist inside the body
				if info, found := funcMap[handlerName]; found && info.Body != nil {
					ast.Inspect(info.Body, func(sub ast.Node) bool {
						binExpr, ok := sub.(*ast.BinaryExpr)
						if !ok {
							return true
						}
						// Check r.Method != http.MethodXXX or r.Method == http.MethodXXX
						leftSel, ok := binExpr.X.(*ast.SelectorExpr)
						if ok && leftSel.Sel.Name == "Method" {
							rightSel, ok := binExpr.Y.(*ast.SelectorExpr)
							if ok && strings.HasPrefix(rightSel.Sel.Name, "Method") {
								m := strings.TrimPrefix(rightSel.Sel.Name, "Method")
								mUpper := strings.ToUpper(m)
								if binExpr.Op == token.NEQ {
									method = mUpper
								} else if binExpr.Op == token.EQL {
									method = mUpper
								}
							}
						}
						return true
					})
				}

				ep := makeEndpoint(method, lookupPath, s.Name, handlerName, funcMap)
				endpoints = append(endpoints, ep)
				return true
			}

			return true
		})
	}

	return endpoints, nil
}

func makeEndpoint(method, path, service, handlerName string, funcMap map[string]HandlerFuncInfo) Endpoint {
	// Look up in known endpoints map
	lookupKey := path
	if !strings.Contains(lookupKey, " /") {
		lookupKey = fmt.Sprintf("%s %s", method, path)
	}

	info, exists := KnownEndpoints[lookupKey]
	if exists {
		// Clean up displayed path (remove suffix like `(auth-service)`)
		cleanPath := path
		if idx := strings.Index(cleanPath, " ("); idx != -1 {
			cleanPath = cleanPath[:idx]
		}
		return Endpoint{
			Method:      method,
			Path:        cleanPath,
			Service:     service,
			Permissions: info.Permissions,
			Function:    info.Function,
			Targets:     info.Targets,
			HandlerName: handlerName,
		}
	}

	// Dynamic fallback using AST analysis on the handler function
	permissions := "<!-- TODO: verify manually -->"
	function := "<!-- TODO: verify manually -->"
	targets := "<!-- TODO: verify manually -->"

	if hInfo, found := funcMap[handlerName]; found {
		// Use doc comment for function
		if hInfo.Doc != "" {
			lines := strings.Split(hInfo.Doc, "\n")
			for _, line := range lines {
				line = strings.TrimSpace(line)
				if line == "" || strings.HasPrefix(line, "Accepts:") || strings.HasPrefix(line, "Roles:") {
					continue
				}
				if function == "<!-- TODO: verify manually -->" {
					function = line
				}
			}
		}

		// Analyze body AST for authentication checks
		if hInfo.Body != nil {
			var hasInternalToken, hasReviewerToken, hasJWT, hasEmployee, hasOwner, hasKYCApproved bool
			ast.Inspect(hInfo.Body, func(sub ast.Node) bool {
				call, ok := sub.(*ast.CallExpr)
				if !ok {
					// Check header Get values
					if sel, ok := sub.(*ast.SelectorExpr); ok {
						if sel.Sel.Name == "RoleEmployee" {
							hasEmployee = true
						} else if sel.Sel.Name == "RoleOwner" {
							hasOwner = true
						}
					}
					// Check for "X-Internal-Token" literal
					if lit, ok := sub.(*ast.BasicLit); ok && lit.Kind == token.STRING {
						if lit.Value == `"X-Internal-Token"` {
							hasInternalToken = true
						} else if lit.Value == `"X-Reviewer-Token"` {
							hasReviewerToken = true
						}
					}
					return true
				}
				funSel, ok := call.Fun.(*ast.SelectorExpr)
				if !ok {
					if id, ok := call.Fun.(*ast.Ident); ok {
						if id.Name == "resolveToken" || id.Name == "resolveRequester" {
							hasJWT = true
						}
					}
					return true
				}
				switch funSel.Sel.Name {
				case "authenticateUser":
					hasJWT = true
				case "authenticateReviewer":
					hasReviewerToken = true
					hasInternalToken = true
				case "ValidateToken":
					hasJWT = true
				case "verifyEmployeeAssignment":
					hasJWT = true
				case "verifyEmployee":
					hasEmployee = true
				}
				return true
			})

			// Check role/permissions combinations
			if hasReviewerToken && hasInternalToken {
				permissions = "Reviewer Token & `X-Internal-Token`"
			} else if hasInternalToken && hasJWT {
				permissions = "`X-Internal-Token` OR User JWT"
			} else if hasInternalToken {
				permissions = "`X-Internal-Token`"
			} else if hasJWT {
				if hasEmployee {
					permissions = "Employee JWT"
				} else if hasOwner {
					if hasKYCApproved {
						permissions = "Owner JWT (KYC Approved)"
					} else {
						permissions = "Owner JWT"
					}
				} else {
					permissions = "User JWT"
				}
			} else {
				permissions = "Public"
			}
		}
	}

	return Endpoint{
		Method:      method,
		Path:        path,
		Service:     service,
		Permissions: permissions,
		Function:    function,
		Targets:     targets,
		HandlerName: handlerName,
	}
}

// GenerateMarkdownTable builds the table string
func GenerateMarkdownTable(endpoints []Endpoint) string {
	// Sort by Service, then Path, then Method
	sort.Slice(endpoints, func(i, j int) bool {
		if endpoints[i].Service != endpoints[j].Service {
			return endpoints[i].Service < endpoints[j].Service
		}
		if endpoints[i].Path != endpoints[j].Path {
			return endpoints[i].Path < endpoints[j].Path
		}
		return endpoints[i].Method < endpoints[j].Method
	})

	var sb strings.Builder
	sb.WriteString("| Method + Path | Owning Service | Caller Permissions | Core Functionality | Read / Write Target & Downstream Actions |\n")
	sb.WriteString("| :--- | :--- | :--- | :--- | :--- |\n")
	for _, ep := range endpoints {
		sb.WriteString(fmt.Sprintf("| **`%s %s`** | `%s` | %s | %s | %s |\n", ep.Method, ep.Path, ep.Service, ep.Permissions, ep.Function, ep.Targets))
	}
	return sb.String()
}

// UpdateApplicationMap replaces the generated block and Git SHA in docs/APPLICATION_MAP.md
func UpdateApplicationMap(repoRoot string, checkOnly bool) (bool, string, error) {
	mapPath := filepath.Join(repoRoot, "docs", "APPLICATION_MAP.md")
	contentBytes, err := os.ReadFile(mapPath)
	if err != nil {
		return false, "", fmt.Errorf("failed to read %s: %w", mapPath, err)
	}
	content := string(contentBytes)

	// Generate the endpoint list and markdown table
	endpoints, err := GenerateEndpointsList(repoRoot)
	if err != nil {
		return false, "", fmt.Errorf("failed to generate endpoints list: %w", err)
	}
	newTable := GenerateMarkdownTable(endpoints)

	// Replace the table block between markers
	startMarker := "<!-- GENERATED:ENDPOINTS:START -->"
	endMarker := "<!-- GENERATED:ENDPOINTS:END -->"
	
	startIdx := strings.Index(content, startMarker)
	endIdx := strings.Index(content, endMarker)
	if startIdx == -1 || endIdx == -1 || startIdx >= endIdx {
		return false, "", fmt.Errorf("could not find GENERATED:ENDPOINTS markers in %s", mapPath)
	}

	beforeBlock := content[:startIdx+len(startMarker)]
	afterBlock := content[endIdx:]

	// Construct new content with new table
	updatedContent := beforeBlock + "\n" + newTable + afterBlock

	// Retrieve current HEAD short SHA
	cmd := exec.Command("git", "rev-parse", "--short", "HEAD")
	cmd.Dir = repoRoot
	shaBytes, err := cmd.Output()
	var currentSHA string
	if err == nil {
		currentSHA = strings.TrimSpace(string(shaBytes))
	} else {
		// Fallback to searching the existing short SHA in the document
		shaRegex := regexp.MustCompile(`as of Git commit: \*\*` + "`" + `([0-9a-f]{7})` + "`" + `\*\*`)
		matches := shaRegex.FindStringSubmatch(content)
		if len(matches) > 1 {
			currentSHA = matches[1]
		} else {
			currentSHA = "unknown"
		}
	}

	// Update the short SHA note at the top
	shaRegex := regexp.MustCompile(`as of Git commit: \*\*` + "`" + `[0-9a-f]{7}` + "`" + `\*\*`)
	updatedContent = shaRegex.ReplaceAllString(updatedContent, fmt.Sprintf("as of Git commit: **`%s`**", currentSHA))

	if content == updatedContent {
		return false, content, nil
	}

	if !checkOnly {
		err = os.WriteFile(mapPath, []byte(updatedContent), 0644)
		if err != nil {
			return false, "", fmt.Errorf("failed to write updated application map: %w", err)
		}
	}

	return true, updatedContent, nil
}
