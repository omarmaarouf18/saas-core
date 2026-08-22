package middleware

import (
	"bytes"
	"log"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// TestLogging_TRAFFICSanitizesNewlinesInPath reproduces the log-injection
// vector: a request path containing an encoded newline (%0A) survives URL
// decoding into r.URL.Path and was interpolated verbatim into the [TRAFFIC]
// line, letting a client forge additional log lines.
//
// Pre-fix expectation: captured log output contains a literal newline inside
// the TRAFFIC record (two lines from one request).
// Post-fix expectation: CR/LF bytes are replaced before interpolation.
func TestLogging_TRAFFICSanitizesNewlinesInPath(t *testing.T) {
	var buf bytes.Buffer
	oldOut := log.Writer()
	log.SetOutput(&buf)
	defer log.SetOutput(oldOut)

	handler := Logging("http://localhost:3000")(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	req := httptest.NewRequest("GET", "/api/v1/users/services%0A[FAKE]%0Dinjected", nil)
	handler.ServeHTTP(httptest.NewRecorder(), req)

	out := buf.String()
	if strings.Contains(out, "\n[FAKE]") || strings.Count(out, "[TRAFFIC]") != 1 {
		t.Errorf("LOG INJECTION POSSIBLE: single request produced manipulated log output: %q", out)
	}
	if !strings.Contains(out, "[TRAFFIC]") {
		t.Fatalf("expected a TRAFFIC line in output, got %q", out)
	}
}
