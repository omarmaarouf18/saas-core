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
	"github.com/project/auth-service/internal/otp"
	"github.com/project/auth-service/internal/store"
)

// Auth holds dependencies for the authentication handlers.
type Auth struct {
	store      *store.MongoDB
	dispatcher otp.OTPDispatcher
	isLocal    bool // true when APP_ENV == "local"
}

// NewAuth creates a new Auth handler group.
//   - s:          MongoDB-backed persistent store
//   - dispatcher: OTPDispatcher implementation (mock for local, real for prod)
//   - appEnv:     value of the APP_ENV environment variable
func NewAuth(s *store.MongoDB, dispatcher otp.OTPDispatcher, appEnv string) *Auth {
	isLocal := strings.EqualFold(appEnv, "local")
	if isLocal {
		log.Printf("[AUTH] ⚠ Running in LOCAL mode — OTP codes will be exposed in API responses")
	}
	return &Auth{store: s, dispatcher: dispatcher, isLocal: isLocal}
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
// For "owner" and "user" roles, a 4-digit OTP is generated, encrypted
// via AES-256-GCM, stored in MongoDB, and dispatched to the user.
// When APP_ENV=local, the plaintext OTP is appended as "dev_otp" in the response.
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

	ctx := r.Context()

	// KYE Enforce OwnerID binding for employees
	if req.Role == models.RoleEmployee {
		if req.OwnerID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{
				"error": "owner_id binding is required for employees to satisfy KYE",
			})
			return
		}
		// Verify owner exists and has RoleOwner
		owner := a.store.GetByID(ctx, req.OwnerID)
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
		Password:  req.Password, // plain-text for now (bcrypt in production)
		Role:      req.Role,
		IsActive:  true, // Active by default
		AntiSpam:  generateAntiSpamToken(),
		CreatedAt: time.Now().UTC(),
	}

	if req.Role == models.RoleEmployee {
		user.OwnerID = req.OwnerID
		user.TenantID = req.OwnerID
	}

	// Owner-specific: KYC status check. Owner is their own tenant.
	if req.Role == models.RoleOwner {
		user.KYCStatus = models.KYCPendingApproval
		user.TenantID = user.ID
	}

	if err := a.store.CreateUser(ctx, user); err != nil {
		writeJSON(w, http.StatusConflict, map[string]string{
			"error": err.Error(),
		})
		return
	}

	log.Printf("[AUTH] Signup: email=%s role=%s id=%s owner_id=%s", user.Email, user.Role, user.ID, user.OwnerID)

	// For owner/user roles, generate and dispatch OTP on signup.
	if req.Role == models.RoleOwner || req.Role == models.RoleUser {
		otpCode := generate4DigitOTP()

		// Encrypt and store in MongoDB (AES-256-GCM).
		if err := a.store.SetOTP(ctx, user.Email, otpCode); err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{
				"error": "failed to set OTP: " + err.Error(),
			})
			return
		}

		// Dispatch via the configured dispatcher (mock logs to stdout).
		if err := a.dispatcher.Dispatch(user.Email, otpCode); err != nil {
			log.Printf("[AUTH] OTP dispatch error via %s: %v", a.dispatcher.Name(), err)
		}

		log.Printf("[AUTH] OTP generated for signup: email=%s code=%s dispatcher=%s",
			user.Email, otpCode, a.dispatcher.Name())

		resp := map[string]any{
			"status":  "success",
			"message": "OTP dispatched",
		}
		// Expose OTP in response ONLY in local environment.
		if a.isLocal {
			resp["dev_otp"] = otpCode
		}

		writeJSON(w, http.StatusCreated, resp)
		return
	}

	// Employee signup — no OTP required.
	writeJSON(w, http.StatusCreated, map[string]any{
		"status":  "success",
		"message": "registration successful",
		"user_id": user.ID,
		"email":   user.Email,
		"role":    user.Role,
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
//   - "owner" / "user": generates a 4-digit OTP, encrypts via AES-256,
//     stores in MongoDB, dispatches via OTPDispatcher.
//     When APP_ENV=local, appends "dev_otp" to the JSON response.
//   - "employee": bypasses 2FA, returns authenticated immediately
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

	ctx := r.Context()
	user := a.store.GetByEmail(ctx, req.Email)
	if user == nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{
			"error": "invalid email or password",
		})
		return
	}

	// Plain-text password comparison (temporary; use bcrypt in production).
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
		// Generate a 4-digit OTP.
		otpCode := generate4DigitOTP()

		// Encrypt and store in MongoDB (AES-256-GCM).
		if err := a.store.SetOTP(ctx, user.Email, otpCode); err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{
				"error": "failed to generate OTP: " + err.Error(),
			})
			return
		}

		// Dispatch via the configured dispatcher (mock logs to stdout).
		if err := a.dispatcher.Dispatch(user.Email, otpCode); err != nil {
			log.Printf("[AUTH] OTP dispatch error via %s: %v", a.dispatcher.Name(), err)
		}

		log.Printf("[AUTH] 2FA triggered: email=%s role=%s code=%s dispatcher=%s",
			user.Email, user.Role, otpCode, a.dispatcher.Name())

		resp := map[string]any{
			"status":  "success",
			"message": "OTP dispatched",
		}
		// Expose OTP in response ONLY in local environment.
		if a.isLocal {
			resp["dev_otp"] = otpCode
		}

		writeJSON(w, http.StatusOK, resp)

	case models.RoleEmployee:
		// Employees bypass 2FA.
		writeJSON(w, http.StatusOK, map[string]any{
			"status":  "success",
			"message": "authenticated",
			"user_id": user.ID,
			"role":    user.Role,
		})
	}
}

// ---------------------------------------------------------------------------
// POST /auth/verify-otp
// ---------------------------------------------------------------------------

// VerifyOTP completes the 2FA flow by validating the OTP code.
// The store decrypts the AES-256-GCM encrypted OTP from MongoDB and
// compares it against the submitted plaintext — identical to production.
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

	ctx := r.Context()

	if err := a.store.VerifyOTP(ctx, req.Email, req.OTP); err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{
			"error": err.Error(),
		})
		return
	}

	user := a.store.GetByEmail(ctx, req.Email)

	log.Printf("[AUTH] OTP verified: email=%s role=%s", user.Email, user.Role)

	response := map[string]any{
		"status":       "success",
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

	ctx := r.Context()

	// Get Owner
	owner := a.store.GetByEmail(ctx, req.OwnerEmail)
	if owner == nil || owner.Role != models.RoleOwner {
		writeJSON(w, http.StatusForbidden, map[string]string{
			"error": "invalid owner credentials or owner does not exist",
		})
		return
	}

	// Toggle Active Status
	err := a.store.ToggleEmployeeActive(ctx, req.EmployeeEmail, owner.ID, req.SetActive)
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
// It performs validation and appends the action to the audit log.
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

	ctx := r.Context()

	// Fetch employee
	emp := a.store.GetByEmail(ctx, req.Email)
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
	a.store.AppendAudit(ctx, entry)

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

	ctx := r.Context()
	tenantID := r.URL.Query().Get("tenant_id")
	entries := a.store.GetAuditLog(ctx, tenantID)

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

// generate4DigitOTP returns a cryptographically random 4-digit numeric OTP.
func generate4DigitOTP() string {
	b := make([]byte, 2)
	if _, err := rand.Read(b); err != nil {
		return "1234"
	}
	// Convert 2 random bytes to a number in [0, 9999].
	num := (int(b[0])<<8 | int(b[1])) % 10000
	return fmt.Sprintf("%04d", num)
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
