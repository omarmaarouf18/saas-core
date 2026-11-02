package handlers

import (
	"context"
	"encoding/json"
	"go/ast"
	"go/parser"
	"go/token"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// TestAdminHandlers_StoreFailureDoesNotLeakTheStoreError covers BE-HARDEN
// item 5: a failing store must not put the store error text into the
// response body. The error is logged server-side and the client gets the
// stable sanitized body (error + code + request_id).
func TestAdminHandlers_StoreFailureDoesNotLeakTheStoreError(t *testing.T) {
	svc, mongoStore, validToken := setupAdminJobsTestEnv(t)
	if svc == nil {
		return
	}

	// Closing the client makes every following store call fail.
	closeCtx, closeCancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer closeCancel()
	if err := mongoStore.Close(closeCtx); err != nil {
		t.Fatalf("failed to close the mongo client: %v", err)
	}

	cases := []struct {
		name   string
		method string
		path   string
		body   string
		call   func(w http.ResponseWriter, r *http.Request)
	}{
		{
			name:   "list services",
			method: http.MethodGet,
			path:   "/admin/services",
			call:   svc.AdminListServices,
		},
		{
			name:   "hide service",
			method: http.MethodPost,
			path:   "/admin/services/svc-1/hide",
			body:   `{"service_id":"svc-1","reason":"support request"}`,
			call:   svc.AdminHideService,
		},
		{
			name:   "unhide service",
			method: http.MethodPost,
			path:   "/admin/services/svc-1/unhide",
			body:   `{"service_id":"svc-1","reason":"support request"}`,
			call:   svc.AdminUnhideService,
		},
		{
			name:   "remove service photo",
			method: http.MethodPost,
			path:   "/admin/services/svc-1/photo/remove",
			body:   `{"service_id":"svc-1","reason":"support request"}`,
			call:   svc.AdminRemoveServicePhoto,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			var body io.Reader
			if tc.body != "" {
				body = strings.NewReader(tc.body)
			}
			req := httptest.NewRequest(tc.method, tc.path, body)
			req.Header.Set("X-Internal-Token", "test-internal-token")
			req.Header.Set("X-Reviewer-Token", validToken)
			rec := httptest.NewRecorder()

			tc.call(rec, req)

			if rec.Code != http.StatusInternalServerError {
				t.Fatalf("expected 500 Internal Server Error, got %d (body: %s)", rec.Code, rec.Body.String())
			}
			assertNoStoreLeak(t, rec.Body.String())
		})
	}
}

// assertNoStoreLeak checks that the response carries the sanitized body and
// no store/driver internals.
func assertNoStoreLeak(t *testing.T, body string) {
	t.Helper()

	var decoded map[string]any
	if err := json.Unmarshal([]byte(body), &decoded); err != nil {
		t.Fatalf("body not JSON: %s", body)
	}
	if decoded["code"] != "internal_error" {
		t.Errorf("expected the code %q, got body %s", "internal_error", body)
	}
	rid, ok := decoded["request_id"].(string)
	if !ok || len(rid) != 16 {
		t.Errorf("request_id missing/malformed in %s", body)
	}

	leaks := []string{
		"mongo", "Mongo", "BSON", "server selection", "client is disconnected",
		"connection refused", "store: ", "duplicate key", "index",
	}
	for _, leak := range leaks {
		if strings.Contains(body, leak) {
			t.Errorf("internal detail %q leaked in body %s", leak, body)
		}
	}
}

// TestAdminHandlers_NoInternalServerErrorBodyCarriesTheStoreError covers
// BE-HARDEN item 5 for the paths that cannot be forced to fail in a test
// (the job cancel and stuck-COD repair): no admin handler may build a 500
// body out of err.Error().
func TestAdminHandlers_NoInternalServerErrorBodyCarriesTheStoreError(t *testing.T) {
	entries, err := os.ReadDir(".")
	if err != nil {
		t.Fatalf("failed to read the handlers directory: %v", err)
	}

	fset := token.NewFileSet()
	for _, entry := range entries {
		name := entry.Name()
		if entry.IsDir() || !strings.HasPrefix(name, "admin_") || !strings.HasSuffix(name, ".go") || strings.HasSuffix(name, "_test.go") {
			continue
		}

		file, err := parser.ParseFile(fset, name, nil, 0)
		if err != nil {
			t.Fatalf("failed to parse %s: %v", name, err)
		}

		ast.Inspect(file, func(n ast.Node) bool {
			call, ok := n.(*ast.CallExpr)
			if !ok {
				return true
			}
			var callee string
			switch fun := call.Fun.(type) {
			case *ast.Ident:
				callee = fun.Name
			case *ast.SelectorExpr:
				callee = fun.Sel.Name
			}
			if callee != "writeJSON" || len(call.Args) < 3 {
				return true
			}
			status, ok := call.Args[1].(*ast.SelectorExpr)
			if !ok || status.Sel.Name != "StatusInternalServerError" {
				return true
			}
			if containsErrorTextCall(call.Args[2]) {
				t.Errorf("%s: a 500 response body is built from err.Error() — use handlerutil.WriteSafeError instead", filepath.Base(name))
			}
			return true
		})
	}
}

// containsErrorTextCall reports whether the expression calls .Error() on a
// value (the store error text).
func containsErrorTextCall(expr ast.Expr) bool {
	found := false
	ast.Inspect(expr, func(n ast.Node) bool {
		call, ok := n.(*ast.CallExpr)
		if !ok {
			return true
		}
		if sel, ok := call.Fun.(*ast.SelectorExpr); ok && sel.Sel.Name == "Error" {
			found = true
		}
		return true
	})
	return found
}
