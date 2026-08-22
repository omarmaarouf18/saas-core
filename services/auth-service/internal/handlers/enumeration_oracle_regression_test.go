package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/project/auth-service/internal/models"
	"github.com/project/shared/infra/jwtutil"
)

// Enumeration-oracle regressions: error responses must not reveal whether an
// account exists.

func enumSignupConfirmed(t *testing.T, a *Auth, email, password string, role models.Role, ownerToken ...string) {
	t.Helper()
	safeUser := "u_" + strings.Map(func(r rune) rune {
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') {
			return r
		}
		return -1
	}, email)
	reqModel := models.SignupRequest{
		Email: email, Username: safeUser, Password: password, Role: role,
	}
	if len(ownerToken) > 1 {
		reqModel.OwnerID = ownerToken[1] // [0]=token, [1]=owner ID the token belongs to
	}
	b, _ := json.Marshal(reqModel)
	req := httptest.NewRequest("POST", "/auth/signup", bytes.NewReader(b))
	if len(ownerToken) > 0 && ownerToken[0] != "" {
		req.Header.Set("Authorization", "Bearer "+ownerToken[0])
	}
	rec := httptest.NewRecorder()
	a.Signup(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("signup %s: %d %s", email, rec.Code, rec.Body.String())
	}
	var res map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &res)
	if otp, ok := res["dev_otp"].(string); ok && otp != "" {
		vb, _ := json.Marshal(models.VerifyOTPRequest{Email: email, OTP: otp})
		rec = httptest.NewRecorder()
		a.VerifyOTP(rec, httptest.NewRequest("POST", "/auth/verify-otp", bytes.NewReader(vb)))
		if rec.Code != http.StatusOK {
			t.Fatalf("verify %s: %d %s", email, rec.Code, rec.Body.String())
		}
	}
	// Employees bypass 2FA at signup (no dev_otp) — nothing to verify.
}

func toggleCall(t *testing.T, a *Auth, ownerEmail, ownerPassword, employeeEmail string) (int, string) {
	t.Helper()
	b, _ := json.Marshal(models.ToggleEmployeeRequest{
		EmployeeEmail: employeeEmail, OwnerEmail: ownerEmail,
		OwnerPassword: ownerPassword, SetActive: false,
	})
	rec := httptest.NewRecorder()
	a.ToggleEmployee(rec, httptest.NewRequest("POST", "/auth/employee/toggle", bytes.NewReader(b)))
	return rec.Code, rec.Body.String()
}

// TestToggleEmployee_NoOwnerExistenceOracle reproduces the wording oracle:
// nonexistent owner returned "…owner does not exist" while wrong password
// returned "…password does not match" — confirming which emails belong to
// real owners. Both must be indistinguishable.
func TestToggleEmployee_NoOwnerExistenceOracle(t *testing.T) {
	a, s, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()
	_ = s

	enumSignupConfirmed(t, a, "owner@oracle.test", "correct-horse-1", models.RoleOwner)
	time.Sleep(10 * time.Millisecond) // limiter keys distinct per attempt

	statusWrongPW, bodyWrongPW := toggleCall(t, a, "owner@oracle.test", "wrong-password", "emp@x.test")
	statusNoOwner, bodyNoOwner := toggleCall(t, a, "ghost-owner@oracle.test", "whatever-password", "emp@x.test")

	if statusWrongPW != statusNoOwner || bodyWrongPW != bodyNoOwner {
		t.Errorf("OWNER EXISTENCE ORACLE: wrong-password → (%d, %s); nonexistent-owner → (%d, %s). Responses must be identical.",
			statusWrongPW, bodyWrongPW, statusNoOwner, bodyNoOwner)
	}
}

// TestToggleEmployee_NoEmployeeExistenceOracle reproduces the status-code
// oracle: a NONEXISTENT employee returned 404 while an existing employee
// belonging to ANOTHER owner returned 400 — distinguishing "no such account"
// from "not yours". Both must collapse to one response.
func TestToggleEmployee_NoEmployeeExistenceOracle(t *testing.T) {
	a, s, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()
	_ = s

	enumSignupConfirmed(t, a, "owner2@oracle.test", "correct-horse-2", models.RoleOwner)
	enumSignupConfirmed(t, a, "otherowner@oracle.test", "correct-horse-3", models.RoleOwner)
	ctxB := context.Background()
	otherOwner := s.GetByEmail(ctxB, "otherowner@oracle.test")
	if otherOwner == nil {
		t.Fatal("otherowner missing")
	}
	// Approve KYC for owner2 so the toggle reaches the employee-resolution
	// branch (otherwise both probes stop at the KYC gate and parity is
	// vacuous — caught during repro debugging).
	owner2 := s.GetByEmail(ctxB, "owner2@oracle.test")
	if owner2 == nil {
		t.Fatal("owner2 missing")
	}
	if err := s.UpdateKYCStatus(ctxB, owner2.ID, models.KYCApproved); err != nil {
		t.Fatalf("approve kyc: %v", err)
	}
	otherOwnerToken, _ := jwtutil.GenerateToken(otherOwner.ID, string(models.RoleOwner), otherOwner.ID, "otherowner@oracle.test")
	enumSignupConfirmed(t, a, "emp-under-other@oracle.test", "employee-pass-1", models.RoleEmployee, otherOwnerToken, otherOwner.ID)
	time.Sleep(10 * time.Millisecond)

	// Existing employee, but belongs to otherowner — store-level mismatch.
	sCtx := context.Background()
	_ = sCtx
	statusOther, bodyOther := toggleCall(t, a, "owner2@oracle.test", "correct-horse-2", "emp-under-other@oracle.test")
	statusMissing, bodyMissing := toggleCall(t, a, "owner2@oracle.test", "correct-horse-2", "ghost-emp@oracle.test")

	t.Logf("DEBUG foreign-tenant employee -> (%d, %s)", statusOther, bodyOther)
	t.Logf("DEBUG nonexistent employee   -> (%d, %s)", statusMissing, bodyMissing)
	if statusOther != statusMissing || bodyOther != bodyMissing {
		t.Errorf("EMPLOYEE EXISTENCE ORACLE: foreign-tenant employee → (%d, %s); nonexistent employee → (%d, %s). Responses must be identical.",
			statusOther, bodyOther, statusMissing, bodyMissing)
	}

	// Sanity: the real owner CAN toggle their own employee.
	// (Covered by the main suite; here we only assert oracle parity.)
}

// TestLogin_TimingParityForUnknownEmail verifies the response-time side
// channel fix: the user-not-found path must perform a real bcrypt comparison
// (dummy hash) so its cost matches the wrong-password path. Threshold is set
// far below typical bcrypt-cost-10 latency (~60-100ms) to stay robust on
// loaded CI machines while still catching a regression to the old
// no-bcrypt-at-all fast path (sub-millisecond DB-miss-only).
func TestLogin_TimingParityForUnknownEmail(t *testing.T) {
	a, _, cleanup := setupTestAuth(t)
	if a == nil {
		return
	}
	defer cleanup()

	// Sign up FIRST: failed logins share one simulated client IP, and the
	// lockout threshold must never be reached mid-probe (repro debugging
	// caught the 429-lockout interaction).
	enumSignupConfirmed(t, a, "realuser@timing.test", "correct-pass-9", models.RoleOwner)

	probe := func(email string) time.Duration {
		b, _ := json.Marshal(models.LoginRequest{Email: email, Password: "some-guess-password"})
		start := time.Now()
		rec := httptest.NewRecorder()
		a.Login(rec, httptest.NewRequest("POST", "/auth/login", bytes.NewReader(b)))
		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("expected 401 for %q, got %d", email, rec.Code)
		}
		return time.Since(start)
	}

	const attempts = 2 // stay under the 5-failure IP lockout threshold
	var unknownTotal, wrongPwTotal time.Duration
	for i := 0; i < attempts; i++ {
		unknownTotal += probe(fmt.Sprintf("ghost-%d@timing.test", i))
	}
	for i := 0; i < attempts; i++ {
		wrongPwTotal += probe("realuser@timing.test")
	}

	avgUnknown := unknownTotal / attempts
	avgWrongPw := wrongPwTotal / attempts
	if avgUnknown < 20*time.Millisecond {
		t.Errorf("LOGIN TIMING ORACLE: unknown-email path averaged %v — no bcrypt work performed (must match wrong-password path, avg %v)", avgUnknown, avgWrongPw)
	}
	t.Logf("avg unknown-email=%v avg wrong-password=%v", avgUnknown, avgWrongPw)
}
