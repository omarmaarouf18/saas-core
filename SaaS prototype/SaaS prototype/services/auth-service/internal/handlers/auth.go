// Package handlers implements HTTP handlers for the auth-service.
package handlers

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/project/auth-service/internal/models"
	"github.com/project/auth-service/internal/store"
)

// Auth holds dependencies for the authentication handlers.
type Auth struct {
	store *store.Memory
}

// NewAuth creates a new Auth handler group.
func NewAuth(s *store.Memory) *Auth {
	return &Auth{store: s}
}

// RegisterRoutes mounts all auth endpoints on the given ServeMux.
// Paths include the /auth/ prefix so they align with the gateway's
// routing: /api/v1/auth/* → auth-service → /auth/*.
func (a *Auth) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/auth/signup", a.Signup)
	mux.HandleFunc("/auth/login", a.Login)
	mux.HandleFunc("/auth/verify-otp", a.VerifyOTP)
	mux.HandleFunc("/auth/employee/toggle", a.ToggleEmployee)
	mux.HandleFunc("/auth/employee/action", a.SimulateEmployeeAction)
	mux.HandleFunc("/auth/audit-log", a.GetAuditLog)
}

// ---------------------------------------------------------------------------
// POST /auth/signup
// ---------------------------------------------------------------------------

// Signup handles new user registration.
//
// Accepts: { "email", "password", "role", "owner_id"? }
// Roles:   "owner", "user", "employee"
//
// Behavior:
//   - Validates role type
//   - For "employee": enforces OwnerID binding (must point to existing owner)
//   - Generates an anti-spam status token
//   - For "owner" role: sets KYC status to "pending_super_admin_approval"
//   - Returns the created user (password excluded from JSON)
func (a *Auth) Signup(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{
			"error": "method not allowed, use POST",
		})
		return
	}

	var req models.SignupRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "invalid JSON body: " + err.Error(),
		})
		return
	}

	// Validate required fields.
	if req.Email == "" || req.Password == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "email and password are required",
		})
		return
	}

	if !models.ValidRole(req.Role) {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error":       "invalid role",
			"valid_roles": "owner, user, employee",
		})
		return
	}

	// KYE Enforce OwnerID binding for employees
	if req.Role == models.RoleEmployee {
		if req.OwnerID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{
				"error": "owner_id binding is required for employees to satisfy KYE",
			})
			return
		}
		// Verify owner exists and has RoleOwner
		owner := a.store.GetByID(req.OwnerID)
		if owner == nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{
				"error": fmt.Sprintf("specified owner_id %q does not exist", req.OwnerID),
			})
			return
		}
		if owner.Role != models.RoleOwner {
			writeJSON(w, http.StatusBadRequest, map[string]string{
				"error": fmt.Sprintf("user %q is not an owner tenant", req.OwnerID),
			})
			return
		}
	}

	// Build user record.
	user := &models.User{
		ID:        generateID(),
		Email:     req.Email,
		Password:  req.Password, // plain-text for now (no DB, no bcrypt)
		Role:      req.Role,
		IsActive:  true, // Active by default
		AntiSpam:  generateAntiSpamToken(),
		CreatedAt: time.Now().UTC(),
	}

	if req.Role == models.RoleEmployee {
		user.OwnerID = req.OwnerID
	}

	// Owner-specific: KYC status check.
	if req.Role == models.RoleOwner {
		user.KYCStatus = models.KYCPendingApproval
	}

	if err := a.store.CreateUser(user); err != nil {
		writeJSON(w, http.StatusConflict, map[string]string{
			"error": err.Error(),
		})
		return
	}

	log.Printf("[AUTH] Signup: email=%s role=%s id=%s owner_id=%s", user.Email, user.Role, user.ID, user.OwnerID)

	writeJSON(w, http.StatusCreated, map[string]any{
		"message":          "registration successful",
		"user_id":          user.ID,
		"email":            user.Email,
		"role":             user.Role,
		"anti_spam_token":  user.AntiSpam,
		"kyc_status":       user.KYCStatus,
		"owner_id":         user.OwnerID,
		"is_active":        user.IsActive,
	})
}

// ---------------------------------------------------------------------------
// POST /auth/login
// ---------------------------------------------------------------------------

// Login validates credentials and determines 2FA requirements by role.
//
// Accepts: { "email", "password" }
//
// Behavior:
//   - Enforces IsActive status check for employees (frozen accounts blocked)
//   - "owner" / "user": triggers mocked 2FA, returns otp_hint for testing
//   - "employee":       bypasses 2FA, returns authenticated immediately
func (a *Auth) Login(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{
			"error": "method not allowed, use POST",
		})
		return
	}

	var req models.LoginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "invalid JSON body: " + err.Error(),
		})
		return
	}

	user := a.store.GetByEmail(req.Email)
	if user == nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{
			"error": "invalid email or password",
		})
		return
	}

	// Plain-text password comparison (temporary, no DB, no bcrypt).
	if user.Password != req.Password {
		writeJSON(w, http.StatusUnauthorized, map[string]string{
			"error": "invalid email or password",
		})
		return
	}

	// KYE Freeze Account check for Employees
	if user.Role == models.RoleEmployee && !user.IsActive {
		writeJSON(w, http.StatusForbidden, map[string]string{
			"error": "employee account is frozen/inactive. please contact your tenant owner.",
		})
		return
	}

	log.Printf("[AUTH] Login: email=%s role=%s", user.Email, user.Role)

	// Role-based 2FA decision.
	switch user.Role {
	case models.RoleOwner, models.RoleUser:
		// Generate a mocked 6-digit OTP.
		otp := generateMockedOTP()
		if err := a.store.SetOTP(user.Email, otp); err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{
				"error": "failed to generate OTP: " + err.Error(),
			})
			return
		}

		log.Printf("[AUTH] 2FA triggered for %s (role=%s), mocked OTP=%s", user.Email, user.Role, otp)

		resp := models.LoginResponse{
			Message:     "credentials valid — 2FA verification required",
			UserID:      user.ID,
			Role:        user.Role,
			Requires2FA: true,
			OTPHint:     otp, // exposed for testing; remove in production
		}
		writeJSON(w, http.StatusOK, resp)

	case models.RoleEmployee:
		// Employees bypass 2FA.
		resp := models.LoginResponse{
			Message:     "authenticated",
			UserID:      user.ID,
			Role:        user.Role,
			Requires2FA: false,
		}
		writeJSON(w, http.StatusOK, resp)
	}
}

// ---------------------------------------------------------------------------
// POST /auth/verify-otp
// ---------------------------------------------------------------------------

// VerifyOTP completes the 2FA flow by validating the mocked OTP code.
//
// Accepts: { "email", "otp" }
func (a *Auth) VerifyOTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{
			"error": "method not allowed, use POST",
		})
		return
	}

	var req models.VerifyOTPRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "invalid JSON body: " + err.Error(),
		})
		return
	}

	if req.Email == "" || req.OTP == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "email and otp are required",
		})
		return
	}

	if err := a.store.VerifyOTP(req.Email, req.OTP); err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{
			"error": err.Error(),
		})
		return
	}

	user := a.store.GetByEmail(req.Email)

	log.Printf("[AUTH] OTP verified: email=%s role=%s", user.Email, user.Role)

	response := map[string]any{
		"message":      "2FA verification successful — authenticated",
		"user_id":      user.ID,
		"role":         user.Role,
		"otp_verified": true,
	}

	// Include KYC status for owners.
	if user.Role == models.RoleOwner {
		response["kyc_status"] = user.KYCStatus
	}

	writeJSON(w, http.StatusOK, response)
}

// ---------------------------------------------------------------------------
// POST /auth/employee/toggle
// ---------------------------------------------------------------------------

// ToggleEmployee allows owners to activate or freeze their employee accounts.
//
// Accepts: { "employee_email", "owner_email", "set_active" }
func (a *Auth) ToggleEmployee(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{
			"error": "method not allowed, use POST",
		})
		return
	}

	var req models.ToggleEmployeeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "invalid JSON body: " + err.Error(),
		})
		return
	}

	if req.EmployeeEmail == "" || req.OwnerEmail == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "employee_email and owner_email are required",
		})
		return
	}

	// Get Owner
	owner := a.store.GetByEmail(req.OwnerEmail)
	if owner == nil || owner.Role != models.RoleOwner {
		writeJSON(w, http.StatusForbidden, map[string]string{
			"error": "invalid owner credentials or owner does not exist",
		})
		return
	}

	// Toggle Active Status
	err := a.store.ToggleEmployeeActive(req.EmployeeEmail, owner.ID, req.SetActive)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": err.Error(),
		})
		return
	}

	statusStr := "frozen"
	if req.SetActive {
		statusStr = "activated"
	}

	log.Printf("[AUTH] Owner %s toggled employee %s to %s", owner.Email, req.EmployeeEmail, statusStr)

	writeJSON(w, http.StatusOK, map[string]any{
		"message":        fmt.Sprintf("employee account successfully %s", statusStr),
		"employee_email": req.EmployeeEmail,
		"is_active":      req.SetActive,
	})
}

// ---------------------------------------------------------------------------
// POST /auth/employee/action
// ---------------------------------------------------------------------------

// SimulateEmployeeAction represents a simulated write operation by an employee.
// It performs validation and appends the action to the in-memory audit log.
//
// Accepts: { "email", "action" }
func (a *Auth) SimulateEmployeeAction(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{
			"error": "method not allowed, use POST",
		})
		return
	}

	var req struct {
		Email  string `json:"email"`
		Action string `json:"action"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "invalid JSON body: " + err.Error(),
		})
		return
	}

	if req.Email == "" || req.Action == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "email and action are required",
		})
		return
	}

	// Fetch employee
	emp := a.store.GetByEmail(req.Email)
	if emp == nil || emp.Role != models.RoleEmployee {
		writeJSON(w, http.StatusForbidden, map[string]string{
			"error": "specified user is not an employee or does not exist",
		})
		return
	}

	// Verify employee is active
	if !emp.IsActive {
		writeJSON(w, http.StatusForbidden, map[string]string{
			"error": "action blocked: employee account is frozen",
		})
		return
	}

	// Extract Client IP
	clientIP := getClientIP(r)

	// Append to Audit Log
	entry := models.AuditEntry{
		EmployeeID: emp.ID,
		TenantID:   emp.OwnerID,
		Action:     req.Action,
		Timestamp:  time.Now().UTC(),
		ClientIP:   clientIP,
	}
	a.store.AppendAudit(entry)

	log.Printf("[AUDIT] Action recorded: employee=%s tenant=%s action=%s ip=%s", emp.ID, emp.OwnerID, req.Action, clientIP)

	writeJSON(w, http.StatusOK, map[string]any{
		"message":     "action recorded in audit log",
		"audit_entry": entry,
	})
}

// ---------------------------------------------------------------------------
// GET /auth/audit-log?tenant_id=<tenant_id>
// ---------------------------------------------------------------------------

// GetAuditLog returns the action server audit log, optionally filtered by tenant.
func (a *Auth) GetAuditLog(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{
			"error": "method not allowed, use GET",
		})
		return
	}

	tenantID := r.URL.Query().Get("tenant_id")
	entries := a.store.GetAuditLog(tenantID)

	writeJSON(w, http.StatusOK, map[string]any{
		"count":   len(entries),
		"entries": entries,
	})
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

func writeJSON(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}

// generateID creates a short random hex ID (16 chars).
func generateID() string {
	b := make([]byte, 8)
	if _, err := rand.Read(b); err != nil {
		return fmt.Sprintf("fallback-%d", time.Now().UnixNano())
	}
	return hex.EncodeToString(b)
}

// generateAntiSpamToken creates a longer random token (32 chars).
func generateAntiSpamToken() string {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return fmt.Sprintf("spam-%d", time.Now().UnixNano())
	}
	return hex.EncodeToString(b)
}

// generateMockedOTP returns a deterministic-length 6-digit code.
func generateMockedOTP() string {
	b := make([]byte, 3)
	if _, err := rand.Read(b); err != nil {
		return "123456"
	}
	// Convert to a 6-digit number by taking modulo.
	num := (int(b[0])<<16 | int(b[1])<<8 | int(b[2])) % 1000000
	return fmt.Sprintf("%06d", num)
}

// getClientIP extracts the user's real IP from the request headers or RemoteAddr.
func getClientIP(r *http.Request) string {
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		parts := strings.Split(xff, ",")
		return strings.TrimSpace(parts[0])
	}
	if rip := r.Header.Get("X-Real-IP"); rip != "" {
		return rip
	}
	// Strip port from RemoteAddr
	parts := strings.Split(r.RemoteAddr, ":")
	if len(parts) > 0 {
		return parts[0]
	}
	return r.RemoteAddr
}
