package contracts

import (
	"bytes"
	"encoding/json"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

// FindProjectRoot locates the repository root by looking upward for go.work.
func FindProjectRoot(t *testing.T) string {
	t.Helper()
	dir, err := os.Getwd()
	if err != nil {
		t.Fatalf("Failed to get current working directory: %v", err)
	}
	for {
		if _, err := os.Stat(filepath.Join(dir, "go.work")); err == nil {
			return dir
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			t.Fatalf("Could not find repository root containing go.work starting from %s", dir)
		}
		dir = parent
	}
}

// StrictUnmarshal deserializes JSON data into v, failing if unknown fields are encountered.
func StrictUnmarshal(data []byte, v any) error {
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.DisallowUnknownFields()
	return dec.Decode(v)
}

// ParseJSONToMap parses raw JSON bytes into a generic map for ad-hoc inspection.
func ParseJSONToMap(t *testing.T, data []byte) map[string]any {
	t.Helper()
	var m map[string]any
	if err := json.Unmarshal(data, &m); err != nil {
		t.Fatalf("Failed to parse JSON into map: %v. Raw JSON: %s", err, string(data))
	}
	return m
}

// AssertJSONTagMap validates that the provided JSON string can be decoded into expected struct
// without missing fields and without breaking types.
func AssertJSONTagMap(t *testing.T, rawJSON []byte, requiredFields []string) {
	t.Helper()
	m := ParseJSONToMap(t, rawJSON)
	for _, f := range requiredFields {
		val, exists := m[f]
		if !exists {
			t.Fatalf("Contract violation: expected required JSON field %q was not found in payload: %s", f, string(rawJSON))
		}
		if val == nil {
			t.Fatalf("Contract violation: required JSON field %q is null in payload: %s", f, string(rawJSON))
		}
	}
}

// StructFieldInfo holds AST inspection data for a struct field.
type StructFieldInfo struct {
	FieldName string
	JSONTag   string
	FieldType string
}

// InspectStructInFile parses the Go file at relPath and extracts field definitions from the specified struct type.
// If typeName is "local:<funcName>:<varName>", it searches inside the function for a local struct variable.
func InspectStructInFile(t *testing.T, rootDir, relPath, typeName string) map[string]StructFieldInfo {
	t.Helper()
	fullPath := filepath.Join(rootDir, relPath)
	fset := token.NewFileSet()
	node, err := parser.ParseFile(fset, fullPath, nil, parser.ParseComments)
	if err != nil {
		t.Fatalf("Failed to parse Go file %s: %v", fullPath, err)
	}

	fields := make(map[string]StructFieldInfo)

	if strings.HasPrefix(typeName, "local:") {
		parts := strings.Split(typeName, ":")
		if len(parts) != 3 {
			t.Fatalf("Invalid local struct selector %q, expected 'local:funcName:varName'", typeName)
		}
		targetFunc := parts[1]
		targetVar := parts[2]

		ast.Inspect(node, func(n ast.Node) bool {
			fn, ok := n.(*ast.FuncDecl)
			if !ok || fn.Name.Name != targetFunc {
				return true
			}
			// Search within this function
			ast.Inspect(fn.Body, func(inner ast.Node) bool {
				genDecl, ok := inner.(*ast.GenDecl)
				if !ok || genDecl.Tok != token.VAR {
					return true
				}
				for _, spec := range genDecl.Specs {
					valueSpec, ok := spec.(*ast.ValueSpec)
					if !ok {
						continue
					}
					for _, name := range valueSpec.Names {
						if name.Name == targetVar {
							if st, ok := valueSpec.Type.(*ast.StructType); ok {
								extractFieldsFromStruct(st, fields)
							}
						}
					}
				}
				return true
			})
			return false
		})
	} else {
		ast.Inspect(node, func(n ast.Node) bool {
			ts, ok := n.(*ast.TypeSpec)
			if !ok || ts.Name.Name != typeName {
				return true
			}
			st, ok := ts.Type.(*ast.StructType)
			if !ok {
				return true
			}
			extractFieldsFromStruct(st, fields)
			return false
		})
	}

	if len(fields) == 0 {
		t.Fatalf("Struct %q not found or has no fields in %s", typeName, relPath)
	}
	return fields
}

// InspectMapKeysInFunction searches a function for composite map literals (like map[string]any{...})
// and extracts all literal string keys defined in them.
func InspectMapKeysInFunction(t *testing.T, rootDir, relPath, funcName string) [][]string {
	t.Helper()
	fullPath := filepath.Join(rootDir, relPath)
	fset := token.NewFileSet()
	node, err := parser.ParseFile(fset, fullPath, nil, parser.ParseComments)
	if err != nil {
		t.Fatalf("Failed to parse Go file %s: %v", fullPath, err)
	}

	var allMapKeys [][]string

	ast.Inspect(node, func(n ast.Node) bool {
		fn, ok := n.(*ast.FuncDecl)
		if !ok || fn.Name.Name != funcName {
			return true
		}
		ast.Inspect(fn.Body, func(inner ast.Node) bool {
			compLit, ok := inner.(*ast.CompositeLit)
			if !ok {
				return true
			}
			var keys []string
			for _, elt := range compLit.Elts {
				kv, ok := elt.(*ast.KeyValueExpr)
				if !ok {
					continue
				}
				if basicLit, ok := kv.Key.(*ast.BasicLit); ok && basicLit.Kind == token.STRING {
					keys = append(keys, strings.Trim(basicLit.Value, "\""))
				}
			}
			if len(keys) > 0 {
				allMapKeys = append(allMapKeys, keys)
			}
			return true
		})
		return false
	})

	if len(allMapKeys) == 0 {
		t.Fatalf("No map composite literals found in function %q of %s", funcName, relPath)
	}
	return allMapKeys
}

func extractFieldsFromStruct(st *ast.StructType, fields map[string]StructFieldInfo) {
	for _, field := range st.Fields.List {
		jsonTag := ""
		if field.Tag != nil {
			tagVal := reflect.StructTag(strings.Trim(field.Tag.Value, "`"))
			jsonTag = tagVal.Get("json")
			// remove ,omitempty
			if idx := strings.Index(jsonTag, ","); idx != -1 {
				jsonTag = jsonTag[:idx]
			}
		}
		for _, name := range field.Names {
			fields[name.Name] = StructFieldInfo{
				FieldName: name.Name,
				JSONTag:   jsonTag,
			}
		}
	}
}
