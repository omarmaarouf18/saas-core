// Package handlers implements HTTP handlers for the auth-service.
package handlers

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"path/filepath"
	"strings"
	"time"

	"github.com/project/auth-service/internal/config"
	"github.com/project/auth-service/internal/models"
	"github.com/project/auth-service/internal/otp"
	"github.com/project/auth-service/internal/storage"
	"github.com/project/auth-service/internal/store"
	"github.com/project/shared/infra/handlerutil"
	"github.com/project/shared/infra/jwtutil"
	"github.com/redis/go-redis/v9"
	"go.mongodb.org/mongo-driver/v2/bson"
	"golang.org/x/crypto/bcrypt"
)

// Auth holds dependencies for the authentication handlers.
type Auth struct {
	store                *store.MongoDB
	dispatcher           otp.OTPDispatcher
	isLocal              bool // true when APP_ENV == "local"
	limiter              *RateLimiter
	gatewaySecret        string
	internalServiceToken string
	storage              *storage.LocalStorage
}

// NewAuth creates a new Auth handler group.
//   - s:             MongoDB-backed persistent store
//   - dispatcher:    OTPDispatcher implementation (mock for local, real for prod)
//   - cfg:           central configuration loader struct
//   - rdb:           Redis client for rate limiting
//   - storage:       local storage engine for documents
func NewAuth(s *store.MongoDB, dispatcher otp.OTPDispatcher, cfg *config.Config, rdb *redis.Client, storage *storage.LocalStorage) *Auth {
	handlerutil.InitCloudWatch(cfg.CloudWatchLogGroup)
	isLocal := strings.EqualFold(cfg.AppEnv, "local")
	if isLocal {
		log.Printf("[AUTH] ⚠ Running in LOCAL mode — OTP codes will be exposed in API responses")
	}
	return &Auth{
		store:                s,
		dispatcher:           dispatcher,
		isLocal:              isLocal,
		limiter:              NewRateLimiter(rdb),
		gatewaySecret:        cfg.GatewaySecret,
		internalServiceToken: cfg.InternalServiceToken,
		storage:              storage,
	}
}

// RegisterRoutes mounts all auth endpoints on the given ServeMux.
// Paths include the /auth/ prefix so they align with the gateway's
// routing: /api/v1/auth/* → auth-service → /auth/*.
func (a *Auth) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/auth/signup", a.Signup)
	mux.HandleFunc("/auth/login", a.Login)
	mux.HandleFunc("/auth/verify-otp", a.VerifyOTP)
	mux.HandleFunc("/auth/refresh", a.Refresh)
	mux.HandleFunc("/auth/employee/toggle", a.ToggleEmployee)
	mux.HandleFunc("/auth/employee/action", a.SimulateEmployeeAction)
	mux.HandleFunc("/auth/audit-log", a.GetAuditLog)
	mux.HandleFunc("/auth/user", a.GetUser)
	mux.HandleFunc("/auth/kyb/upload", a.UploadKYB)
	mux.HandleFunc("/auth/kye/upload", a.UploadKYE)
	mux.HandleFunc("/auth/kyb-kye/pending", a.GetPendingKYBKYESubmissions)
	mux.HandleFunc("/auth/kyb-kye/review", a.ReviewKYBKYESubmissions)
	mux.HandleFunc("/auth/documents/view", a.ViewDocument)
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

	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{
			"error": "failed to hash password: " + err.Error(),
		})
		return
	}

	// Build user record.
	user := &models.User{
		ID:          generateID(),
		Email:       req.Email,
		Password:    string(hashedPassword),
		Role:        req.Role,
		IsActive:    true, // Active by default
		IsConfirmed: req.Role == models.RoleEmployee,
		CreatedAt:   time.Now().UTC(),
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

	clientIP := a.getClientIP(r)

	// Check if IP is locked out
	if locked, remaining := a.limiter.IsLocked(clientIP); locked {
		writeJSON(w, http.StatusTooManyRequests, map[string]string{
			"error": fmt.Sprintf("too many failed attempts from this IP. Please try again in %.0f seconds.", remaining.Seconds()),
		})
		return
	}

	// Check if Email is locked out
	if req.Email != "" {
		if locked, remaining := a.limiter.IsLocked(req.Email); locked {
			writeJSON(w, http.StatusTooManyRequests, map[string]string{
				"error": fmt.Sprintf("too many failed attempts for this email. Please try again in %.0f seconds.", remaining.Seconds()),
			})
			return
		}
	}

	ctx := r.Context()
	user := a.store.GetByEmail(ctx, req.Email)
	if user == nil {
		a.limiter.RecordFailure(clientIP)
		if req.Email != "" {
			a.limiter.RecordFailure(req.Email)
		}
		writeJSON(w, http.StatusUnauthorized, map[string]string{
			"error": "invalid email or password",
		})
		return
	}

	// Verify hashed password using bcrypt.
	if err := bcrypt.CompareHashAndPassword([]byte(user.Password), []byte(req.Password)); err != nil {
		a.limiter.RecordFailure(clientIP)
		if req.Email != "" {
			a.limiter.RecordFailure(req.Email)
		}
		writeJSON(w, http.StatusUnauthorized, map[string]string{
			"error": "invalid email or password",
		})
		return
	}

	// Reset limits on success
	a.limiter.Reset(clientIP)
	a.limiter.Reset(req.Email)

	// Signup verification check
	if !user.IsConfirmed {
		writeJSON(w, http.StatusForbidden, map[string]string{
			"error": "account is not confirmed. please verify the signup OTP first.",
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
		token, err := jwtutil.GenerateToken(user.ID, string(user.Role), user.TenantID, user.Email)
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{
				"error": "failed to generate token: " + err.Error(),
			})
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{
			"status":  "success",
			"message": "authenticated",
			"user_id": user.ID,
			"role":    user.Role,
			"token":   token,
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

	clientIP := a.getClientIP(r)

	// Check if IP is locked out
	if locked, remaining := a.limiter.IsLocked(clientIP); locked {
		writeJSON(w, http.StatusTooManyRequests, map[string]string{
			"error": fmt.Sprintf("too many failed attempts from this IP. Please try again in %.0f seconds.", remaining.Seconds()),
		})
		return
	}

	// Check if Email is locked out
	if locked, remaining := a.limiter.IsLocked(req.Email); locked {
		writeJSON(w, http.StatusTooManyRequests, map[string]string{
			"error": fmt.Sprintf("too many failed attempts for this email. Please try again in %.0f seconds.", remaining.Seconds()),
		})
		return
	}

	ctx := r.Context()

	if err := a.store.VerifyOTP(ctx, req.Email, req.OTP); err != nil {
		a.limiter.RecordFailure(clientIP)
		a.limiter.RecordFailure(req.Email)
		writeJSON(w, http.StatusUnauthorized, map[string]string{
			"error": err.Error(),
		})
		return
	}

	// Reset limits on success
	a.limiter.Reset(clientIP)
	a.limiter.Reset(req.Email)

	user := a.store.GetByEmail(ctx, req.Email)

	log.Printf("[AUTH] OTP verified: email=%s role=%s", user.Email, user.Role)

	token, err := jwtutil.GenerateToken(user.ID, string(user.Role), user.TenantID, user.Email)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{
			"error": "failed to generate token: " + err.Error(),
		})
		return
	}

	response := map[string]any{
		"status":       "success",
		"message":      "2FA verification successful — authenticated",
		"user_id":      user.ID,
		"role":         user.Role,
		"otp_verified": true,
		"token":        token,
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

	if req.EmployeeEmail == "" || req.OwnerEmail == "" || req.OwnerPassword == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "employee_email, owner_email, and owner_password are required",
		})
		return
	}

	clientIP := a.getClientIP(r)
	if locked, remaining := a.limiter.IsLocked(clientIP); locked {
		writeJSON(w, http.StatusTooManyRequests, map[string]string{
			"error": fmt.Sprintf("too many attempts, locked out for %.0f seconds", remaining.Seconds()),
		})
		return
	}
	if locked, remaining := a.limiter.IsLocked(req.OwnerEmail); locked {
		writeJSON(w, http.StatusTooManyRequests, map[string]string{
			"error": fmt.Sprintf("too many attempts, locked out for %.0f seconds", remaining.Seconds()),
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

	// Verify owner password using bcrypt
	if err := bcrypt.CompareHashAndPassword([]byte(owner.Password), []byte(req.OwnerPassword)); err != nil {
		a.limiter.RecordFailure(clientIP)
		a.limiter.RecordFailure(req.OwnerEmail)
		writeJSON(w, http.StatusForbidden, map[string]string{
			"error": "invalid owner credentials or password does not match",
		})
		return
	}

	// Verify owner is approved KYC
	if owner.KYCStatus != models.KYCApproved {
		log.Printf("[KYC BLOCKED] Owner %s (ID: %s) attempted to toggle employee %s, but KYC status is %q", owner.Email, owner.ID, req.EmployeeEmail, owner.KYCStatus)
		handlerutil.ShipSecurityEvent(r.Context(), "KYC_BLOCKED", "auth-service", owner.ID, owner.ID, fmt.Sprintf("attempted to toggle employee %s, KYC status is %s", req.EmployeeEmail, owner.KYCStatus), handlerutil.GetClientIP(r))
		writeJSON(w, http.StatusForbidden, map[string]string{
			"error": "action blocked: owner KYC approval is pending",
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

	// Reset limits on success
	a.limiter.Reset(clientIP)
	a.limiter.Reset(req.OwnerEmail)

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

	// Validate caller JWT token matches requested employee email
	authHeader := r.Header.Get("Authorization")
	if !strings.HasPrefix(authHeader, "Bearer ") {
		writeJSON(w, http.StatusUnauthorized, map[string]string{
			"error": "missing or invalid authorization header, Bearer token required",
		})
		return
	}
	tokenStr := strings.TrimPrefix(authHeader, "Bearer ")
	claims, err := jwtutil.ValidateToken(tokenStr)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{
			"error": "invalid token: " + err.Error(),
		})
		return
	}

	if claims.Email != req.Email {
		writeJSON(w, http.StatusForbidden, map[string]string{
			"error": "access denied: token identity does not match requested employee email",
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

	// Verify employee's owner has approved KYC
	owner := a.store.GetByID(ctx, emp.OwnerID)
	if owner == nil || owner.KYCStatus != models.KYCApproved {
		ownerStatus := "none"
		if owner != nil {
			ownerStatus = string(owner.KYCStatus)
		}
		log.Printf("[KYC BLOCKED] Employee %s (ID: %s, Owner ID: %s) attempted action %q, but owner KYC status is %q", emp.Email, emp.ID, emp.OwnerID, req.Action, ownerStatus)
		handlerutil.ShipSecurityEvent(r.Context(), "KYC_BLOCKED", "auth-service", emp.ID, emp.OwnerID, fmt.Sprintf("attempted action %s, owner KYC status is %s", req.Action, ownerStatus), handlerutil.GetClientIP(r))
		writeJSON(w, http.StatusForbidden, map[string]string{
			"error": "action blocked: owner KYC approval is pending",
		})
		return
	}

	// Extract Client IP
	clientIP := a.getClientIP(r)

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

// GET /auth/user?id=<user_id>
func (a *Auth) GetUser(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{
			"error": "method not allowed, use GET",
		})
		return
	}

	id := r.URL.Query().Get("id")
	if id == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "id parameter is required",
		})
		return
	}

	ctx := r.Context()
	var lookupID string

	if subtle.ConstantTimeCompare([]byte(r.Header.Get("X-Internal-Token")), []byte(a.internalServiceToken)) == 1 {
		lookupID = id
	} else {
		claims, err := jwtutil.ValidateToken(id)
		if err != nil {
			writeJSON(w, http.StatusUnauthorized, map[string]string{
				"error": "invalid token signature or expired: " + err.Error(),
			})
			return
		}
		lookupID = claims.UserID
	}

	user := a.store.GetByID(ctx, lookupID)
	if user == nil {
		writeJSON(w, http.StatusNotFound, map[string]string{
			"error": "user not found",
		})
		return
	}

	resp := map[string]any{
		"id":         user.ID,
		"email":      user.Email,
		"role":       user.Role,
		"tenant_id":  user.TenantID,
		"kyc_status": user.KYCStatus,
		"is_active":  user.IsActive,
	}
	if user.Role == models.RoleEmployee {
		resp["kye_status"] = user.KYEStatus
	}
	if user.RejectionReason != "" {
		resp["rejection_reason"] = user.RejectionReason
	}
	writeJSON(w, http.StatusOK, resp)
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
	if tenantID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "tenant_id parameter is required",
		})
		return
	}

	requesterParam := r.URL.Query().Get("requester_id")
	if requesterParam == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "requester_id parameter is required",
		})
		return
	}

	claims, err := jwtutil.ValidateToken(requesterParam)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{
			"error": "invalid requester token: " + err.Error(),
		})
		return
	}
	resolvedRequesterID := claims.UserID

	if resolvedRequesterID != tenantID {
		log.Printf("[TENANT SCOPE BLOCKED] User %s attempted to access audit log for tenant %s", resolvedRequesterID, tenantID)
		handlerutil.ShipSecurityEvent(r.Context(), "TENANT_SCOPE_BLOCKED", "auth-service", resolvedRequesterID, tenantID, "attempted to access audit log", handlerutil.GetClientIP(r))
		writeJSON(w, http.StatusForbidden, map[string]string{
			"error": "access denied: you are not authorized to view this tenant's audit log",
		})
		return
	}

	ctx := r.Context()
	entries := a.store.GetAuditLog(ctx, tenantID)

	writeJSON(w, http.StatusOK, map[string]any{
		"count":   len(entries),
		"entries": entries,
	})
}

// ---------------------------------------------------------------------------
// POST /auth/refresh
// ---------------------------------------------------------------------------

// Refresh accepts a POST request with an expired or active JWT token and reissues a new one.
func (a *Auth) Refresh(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed, use POST"})
		return
	}

	var req struct {
		Token string `json:"token"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON body: " + err.Error()})
		return
	}

	if req.Token == "" {
		// Fallback to Authorization header
		authHeader := r.Header.Get("Authorization")
		if strings.HasPrefix(authHeader, "Bearer ") {
			req.Token = strings.TrimPrefix(authHeader, "Bearer ")
		}
	}

	if req.Token == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "token is required"})
		return
	}

	// Validate token, allowing expired token to be parsed for refresh purposes
	claims, err := jwtutil.ValidateToken(req.Token)
	if err != nil && !errors.Is(err, jwtutil.ErrExpiredToken) {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid token: " + err.Error()})
		return
	}

	if claims.ExpiresAt != nil && time.Since(claims.ExpiresAt.Time) > 7*24*time.Hour {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "token expired too long ago to refresh"})
		return
	}

	ctx := r.Context()
	user := a.store.GetByID(ctx, claims.UserID)
	if user == nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "user associated with token not found"})
		return
	}

	if !user.IsActive {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "user account is frozen/inactive"})
		return
	}

	newToken, err := jwtutil.GenerateToken(user.ID, string(user.Role), user.TenantID, user.Email)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to generate fresh token"})
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"status": "success",
		"token":  newToken,
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
		log.Fatalf("generateID: failed to read random bytes: %v", err)
	}
	return hex.EncodeToString(b)
}

// generate4DigitOTP returns a cryptographically random 4-digit numeric OTP.
func generate4DigitOTP() string {
	b := make([]byte, 2)
	if _, err := rand.Read(b); err != nil {
		log.Fatalf("generate4DigitOTP: failed to read random bytes: %v", err)
	}
	// Convert 2 random bytes to a number in [0, 9999].
	num := (int(b[0])<<8 | int(b[1])) % 10000
	return fmt.Sprintf("%04d", num)
}

// getClientIP extracts the user's real IP from the request headers or RemoteAddr.
func (a *Auth) getClientIP(r *http.Request) string {
	var ip string
	if r.Header.Get("X-Gateway-Secret") == a.gatewaySecret {
		if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
			parts := strings.Split(xff, ",")
			ip = strings.TrimSpace(parts[0])
		} else if rip := r.Header.Get("X-Real-IP"); rip != "" {
			ip = rip
		}
	}

	if ip == "" {
		ip = r.RemoteAddr
	}

	if strings.Contains(ip, "]") {
		if idx := strings.LastIndex(ip, ":"); idx != -1 {
			ip = ip[:idx]
		}
		ip = strings.Trim(ip, "[]")
	} else {
		if count := strings.Count(ip, ":"); count == 1 {
			if idx := strings.LastIndex(ip, ":"); idx != -1 {
				ip = ip[:idx]
			}
		}
	}
	return ip
}

func (a *Auth) authenticateUser(r *http.Request) (*jwtutil.Claims, error) {
	authHeader := r.Header.Get("Authorization")
	if !strings.HasPrefix(authHeader, "Bearer ") {
		return nil, fmt.Errorf("missing or invalid authorization header, Bearer token required")
	}
	tokenStr := strings.TrimPrefix(authHeader, "Bearer ")
	return jwtutil.ValidateToken(tokenStr)
}

// POST /auth/kyb/upload?type=id_front|id_back|selfie|business_proof
func (a *Auth) UploadKYB(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use POST"})
		return
	}

	claims, err := a.authenticateUser(r)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": err.Error()})
		return
	}

	ctx := r.Context()
	user := a.store.GetByID(ctx, claims.UserID)
	if user == nil || user.Role != models.RoleOwner {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "access denied: owner role required"})
		return
	}

	docType := r.URL.Query().Get("type")
	if docType != "id_front" && docType != "id_back" && docType != "selfie" && docType != "business_proof" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid doc type"})
		return
	}

	r.Body = http.MaxBytesReader(w, r.Body, 10<<20)
	if err := r.ParseMultipartForm(10 << 20); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "file too large (max 10MB) or invalid multipart"})
		return
	}

	file, _, err := r.FormFile("file")
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "file parameter is required"})
		return
	}
	defer file.Close()

	buf := make([]byte, 512)
	n, _ := file.Read(buf)
	contentType := http.DetectContentType(buf[:n])
	if _, err := file.Seek(0, io.SeekStart); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	ext := ""
	switch contentType {
	case "image/jpeg":
		ext = "jpg"
	case "image/png":
		ext = "png"
	case "application/pdf":
		if docType == "business_proof" {
			ext = "pdf"
		}
	}

	if ext == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "unsupported file format"})
		return
	}

	key := fmt.Sprintf("kyb/%s/%s.%s", user.ID, docType, ext)
	if err := a.storage.Upload(ctx, key, file, contentType); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	update := bson.M{}
	switch docType {
	case "id_front":
		update["$set"] = bson.M{"id_front_doc": key}
	case "id_back":
		update["$set"] = bson.M{"id_back_doc": key}
	case "selfie":
		update["$set"] = bson.M{"selfie_doc": key}
	case "business_proof":
		update["$set"] = bson.M{"business_proof_doc": key}
	}

	if err := a.store.UpdateUser(ctx, user.ID, update); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	updated := a.store.GetByID(ctx, user.ID)
	if updated.IDFrontDoc != "" && updated.IDBackDoc != "" && updated.SelfieDoc != "" && updated.BusinessProofDoc != "" {
		if err := a.store.UpdateUser(ctx, user.ID, bson.M{"$set": bson.M{"kyc_status": models.KYCPendingApproval, "reviewer_id": "", "rejection_reason": ""}}); err != nil {
			log.Printf("[KYB] failed to update status to pending: %v", err)
		}
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "uploaded", "key": key})
}

// POST /auth/kye/upload?type=id_front|id_back|selfie
func (a *Auth) UploadKYE(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use POST"})
		return
	}

	claims, err := a.authenticateUser(r)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": err.Error()})
		return
	}

	ctx := r.Context()
	user := a.store.GetByID(ctx, claims.UserID)
	if user == nil || user.Role != models.RoleEmployee {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "access denied: employee role required"})
		return
	}

	docType := r.URL.Query().Get("type")
	if docType != "id_front" && docType != "id_back" && docType != "selfie" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid doc type"})
		return
	}

	r.Body = http.MaxBytesReader(w, r.Body, 10<<20)
	if err := r.ParseMultipartForm(10 << 20); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "file too large (max 10MB) or invalid multipart"})
		return
	}

	file, _, err := r.FormFile("file")
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "file parameter is required"})
		return
	}
	defer file.Close()

	buf := make([]byte, 512)
	n, _ := file.Read(buf)
	contentType := http.DetectContentType(buf[:n])
	if _, err := file.Seek(0, io.SeekStart); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	ext := ""
	switch contentType {
	case "image/jpeg":
		ext = "jpg"
	case "image/png":
		ext = "png"
	}

	if ext == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "unsupported file format"})
		return
	}

	key := fmt.Sprintf("kye/%s/%s.%s", user.ID, docType, ext)
	if err := a.storage.Upload(ctx, key, file, contentType); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	update := bson.M{}
	switch docType {
	case "id_front":
		update["$set"] = bson.M{"id_front_doc": key}
	case "id_back":
		update["$set"] = bson.M{"id_back_doc": key}
	case "selfie":
		update["$set"] = bson.M{"selfie_doc": key}
	}

	if err := a.store.UpdateUser(ctx, user.ID, update); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	updated := a.store.GetByID(ctx, user.ID)
	if updated.IDFrontDoc != "" && updated.IDBackDoc != "" && updated.SelfieDoc != "" {
		if err := a.store.UpdateUser(ctx, user.ID, bson.M{"$set": bson.M{"kye_status": models.KYCPendingApproval, "reviewer_id": "", "rejection_reason": ""}}); err != nil {
			log.Printf("[KYE] failed to update status to pending: %v", err)
		}
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "uploaded", "key": key})
}

// GET /auth/kyb-kye/pending
func (a *Auth) GetPendingKYBKYESubmissions(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use GET"})
		return
	}

	if subtle.ConstantTimeCompare([]byte(r.Header.Get("X-Internal-Token")), []byte(a.internalServiceToken)) != 1 {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return
	}

	ctx := r.Context()
	users, err := a.store.GetPendingKYBKYE(ctx)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	type Submission struct {
		UserID           string           `json:"user_id"`
		Email            string           `json:"email"`
		Role             models.Role      `json:"role"`
		KYCStatus        models.KYCStatus `json:"kyc_status,omitempty"`
		KYEStatus        models.KYCStatus `json:"kye_status,omitempty"`
		IDFrontURL       string           `json:"id_front_url,omitempty"`
		IDBackURL        string           `json:"id_back_url,omitempty"`
		SelfieURL        string           `json:"selfie_url,omitempty"`
		BusinessProofURL string           `json:"business_proof_url,omitempty"`
	}

	results := make([]Submission, 0, len(users))
	for _, u := range users {
		sub := Submission{
			UserID:    u.ID,
			Email:     u.Email,
			Role:      u.Role,
			KYCStatus: u.KYCStatus,
			KYEStatus: u.KYEStatus,
		}

		if u.IDFrontDoc != "" {
			sub.IDFrontURL, _ = a.storage.GetSignedURL(ctx, u.IDFrontDoc, 15*time.Minute)
			handlerutil.ShipSecurityEvent(ctx, "DOCUMENT_VIEWED", "auth-service", "internal_reviewer", u.ID, fmt.Sprintf("generated signed url for IDFrontDoc key: %s", u.IDFrontDoc), handlerutil.GetClientIP(r))
		}
		if u.IDBackDoc != "" {
			sub.IDBackURL, _ = a.storage.GetSignedURL(ctx, u.IDBackDoc, 15*time.Minute)
			handlerutil.ShipSecurityEvent(ctx, "DOCUMENT_VIEWED", "auth-service", "internal_reviewer", u.ID, fmt.Sprintf("generated signed url for IDBackDoc key: %s", u.IDBackDoc), handlerutil.GetClientIP(r))
		}
		if u.SelfieDoc != "" {
			sub.SelfieURL, _ = a.storage.GetSignedURL(ctx, u.SelfieDoc, 15*time.Minute)
			handlerutil.ShipSecurityEvent(ctx, "DOCUMENT_VIEWED", "auth-service", "internal_reviewer", u.ID, fmt.Sprintf("generated signed url for SelfieDoc key: %s", u.SelfieDoc), handlerutil.GetClientIP(r))
		}
		if u.BusinessProofDoc != "" {
			sub.BusinessProofURL, _ = a.storage.GetSignedURL(ctx, u.BusinessProofDoc, 15*time.Minute)
			handlerutil.ShipSecurityEvent(ctx, "DOCUMENT_VIEWED", "auth-service", "internal_reviewer", u.ID, fmt.Sprintf("generated signed url for BusinessProofDoc key: %s", u.BusinessProofDoc), handlerutil.GetClientIP(r))
		}

		results = append(results, sub)
	}

	handlerutil.ShipSecurityEvent(ctx, "KYC_PENDING_LISTED", "auth-service", "internal_reviewer", "", "retrieved list of pending KYB/KYE applications", handlerutil.GetClientIP(r))

	writeJSON(w, http.StatusOK, results)
}

// POST /auth/kyb-kye/review
func (a *Auth) ReviewKYBKYESubmissions(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use POST"})
		return
	}

	if subtle.ConstantTimeCompare([]byte(r.Header.Get("X-Internal-Token")), []byte(a.internalServiceToken)) != 1 {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return
	}

	var req struct {
		UserID string `json:"user_id"`
		Action string `json:"action"` // "approve" or "reject"
		Reason string `json:"reason,omitempty"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON"})
		return
	}

	if req.UserID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "user_id is required"})
		return
	}

	if req.Action != "approve" && req.Action != "reject" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "action must be approve or reject"})
		return
	}

	ctx := r.Context()
	targetUser := a.store.GetByID(ctx, req.UserID)
	if targetUser == nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "user not found"})
		return
	}

	isOwner := targetUser.Role == models.RoleOwner
	isEmployee := targetUser.Role == models.RoleEmployee

	if isOwner {
		if targetUser.KYCStatus != models.KYCPendingApproval {
			writeJSON(w, http.StatusConflict, map[string]string{"error": "no pending KYB application for this owner"})
			return
		}
	} else if isEmployee {
		if targetUser.KYEStatus != models.KYCPendingApproval {
			writeJSON(w, http.StatusConflict, map[string]string{"error": "no pending KYE application for this employee"})
			return
		}
	} else {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "specified user role cannot undergo KYB/KYE review"})
		return
	}

	var finalStatus models.KYCStatus
	if req.Action == "approve" {
		finalStatus = models.KYCApproved
	} else {
		finalStatus = models.KYCRejected
	}

	update := bson.M{
		"$set": bson.M{
			"reviewer_id":      "internal_reviewer",
			"reviewed_at":      time.Now().UTC(),
			"rejection_reason": req.Reason,
		},
	}

	if isOwner {
		update["$set"].(bson.M)["kyc_status"] = finalStatus
	} else {
		update["$set"].(bson.M)["kye_status"] = finalStatus
	}

	if err := a.store.UpdateUser(ctx, targetUser.ID, update); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	handlerutil.ShipSecurityEvent(ctx, "KYC_REVIEWED", "auth-service", "internal_reviewer", req.UserID, fmt.Sprintf("action: %s, reason: %s", req.Action, req.Reason), handlerutil.GetClientIP(r))

	writeJSON(w, http.StatusOK, map[string]string{"status": "reviewed", "action": req.Action})
}

// GET /auth/documents/view?token=xxx
func (a *Auth) ViewDocument(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use GET"})
		return
	}

	tokenStr := r.URL.Query().Get("token")
	if tokenStr == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "token is required"})
		return
	}

	key, err := a.storage.ValidateSignedURLToken(tokenStr)
	if err != nil {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "invalid or expired token"})
		return
	}

	handlerutil.ShipSecurityEvent(r.Context(), "DOCUMENT_VIEWED", "auth-service", "system", "", fmt.Sprintf("accessed document key: %s", key), handlerutil.GetClientIP(r))

	file, err := a.storage.OpenFile(key)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "document not found"})
		return
	}
	defer file.Close()

	ext := filepath.Ext(key)
	contentType := "application/octet-stream"
	switch ext {
	case ".jpg", ".jpeg":
		contentType = "image/jpeg"
	case ".png":
		contentType = "image/png"
	case ".pdf":
		contentType = "application/pdf"
	}

	w.Header().Set("Content-Type", contentType)
	if _, err := io.Copy(w, file); err != nil {
		log.Printf("[VIEW] failed to stream document %s: %v", key, err)
	}
}
