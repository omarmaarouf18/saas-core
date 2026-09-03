// Package handlers implements HTTP handlers for the auth-service.
package handlers

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/project/auth-service/internal/config"
	"github.com/project/auth-service/internal/models"
	"github.com/project/auth-service/internal/otp"
	"github.com/project/auth-service/internal/storage"
	"github.com/project/auth-service/internal/store"
	"github.com/project/shared/infra/handlerutil"
	"github.com/project/shared/infra/jwtutil"
	"github.com/project/shared/infra/resilience"
	"github.com/project/shared/infra/tlsutil"
	"github.com/redis/go-redis/v9"
	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
	"golang.org/x/crypto/bcrypt"
)

var phoneRegex = regexp.MustCompile(`^\+?[0-9]{7,15}$`)

// Auth holds runtime dependencies for the authentication handlers.
type Auth struct {
	store                *store.MongoDB
	dispatcher           otp.OTPDispatcher
	isLocal              bool // true when APP_ENV == "local"
	limiter              *RateLimiter
	gatewaySecret        string
	internalServiceToken string
	storage              storage.Storage
	userServiceClient    *resilience.ResilienceClient
	userServiceURL       string
	notificationClient   *resilience.ResilienceClient
	notificationURL      string
}

// NewAuth creates a new Auth handler group.
//   - s:             MongoDB-backed persistent store
//   - dispatcher:    OTPDispatcher implementation (mock for local, real for prod)
//   - cfg:           central configuration loader struct
//   - rdb:           Redis client for rate limiting
//   - storage:       local storage engine for documents
//   - storage:       local storage engine for documents
func NewAuth(s *store.MongoDB, dispatcher otp.OTPDispatcher, cfg *config.Config, rdb *redis.Client, storage storage.Storage) *Auth {
	handlerutil.InitCloudWatch(cfg.CloudWatchLogGroup)
	isLocal := strings.EqualFold(cfg.AppEnv, "local")
	if isLocal {
		log.Printf("[AUTH] ⚠ Running in LOCAL mode — OTP codes will be exposed in API responses")
	}

	var client *http.Client
	if cfg.TLSCertPath != "" && cfg.TLSKeyPath != "" && cfg.TLSCAPath != "" {
		var err error
		client, err = tlsutil.NewClient(cfg.TLSCertPath, cfg.TLSKeyPath, cfg.TLSCAPath)
		if err != nil {
			log.Fatalf("[AUTH] Failed to initialize TLS http client: %v", err)
		}
	} else {
		client = http.DefaultClient
	}

	userServiceClient := resilience.NewClient(client, "user-service", 2, 5*time.Second)
	notificationClient := resilience.NewClient(client, "notification-service", 2, 5*time.Second)

	return &Auth{
		store:                s,
		dispatcher:           dispatcher,
		isLocal:              isLocal,
		limiter:              NewRateLimiter(rdb),
		gatewaySecret:        cfg.GatewaySecret,
		internalServiceToken: cfg.InternalServiceToken,
		storage:              storage,
		userServiceClient:    userServiceClient,
		userServiceURL:       cfg.UserServiceURL,
		notificationClient:   notificationClient,
		notificationURL:      cfg.NotificationServiceURL,
	}
}

// RegisterRoutes mounts all auth endpoints on the given ServeMux.
// Paths include the /auth/ prefix so they align with the gateway's
// routing: /api/v1/auth/* → auth-service → /auth/*.
func (a *Auth) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/auth/signup", a.Signup)
	mux.HandleFunc("/auth/login", a.Login)
	mux.HandleFunc("/auth/resend-otp", a.ResendOTP)
	mux.HandleFunc("/auth/verify-otp", a.VerifyOTP)
	mux.HandleFunc("/auth/forgot-password", a.ForgotPassword)
	mux.HandleFunc("/auth/reset-password", a.ResetPassword)
	mux.HandleFunc("/auth/refresh", a.Refresh)
	mux.HandleFunc("/auth/employee/toggle", a.ToggleEmployee)
	mux.HandleFunc("/auth/employee/action", a.SimulateEmployeeAction)
	mux.HandleFunc("/auth/audit-log", a.GetAuditLog)
	mux.HandleFunc("/auth/employees", a.GetEmployees)
	mux.HandleFunc("/auth/user", func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		case http.MethodGet:
			a.GetUser(w, r)
		case http.MethodPatch:
			a.UpdateProfile(w, r)
		default:
			writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		}
	})
	mux.HandleFunc("/auth/user/public-profile", a.GetPublicProfile)
	mux.HandleFunc("/auth/kyb/upload", a.UploadKYB)
	mux.HandleFunc("/auth/kye/upload", a.UploadKYE)
	mux.HandleFunc("/auth/kyb-kye/pending", a.GetPendingKYBKYESubmissions)
	mux.HandleFunc("/auth/kyb-kye/review", a.ReviewKYBKYESubmissions)
	mux.HandleFunc("/auth/documents/view", a.ViewDocument)
	mux.HandleFunc("/auth/accounts", a.GetAccounts)
	mux.HandleFunc("/auth/accounts/{id}/suspend", a.SuspendAccount)
	mux.HandleFunc("/auth/accounts/suspend", a.SuspendAccount)
	mux.HandleFunc("/auth/accounts/{id}/reactivate", a.ReactivateAccount)
	mux.HandleFunc("/auth/accounts/reactivate", a.ReactivateAccount)
	mux.HandleFunc("/auth/reviewer/verify", a.VerifyReviewer)
	mux.HandleFunc("/auth/device-token", a.DeviceToken)
	mux.HandleFunc("/auth/email-change/request", a.RequestEmailChange)
	mux.HandleFunc("/auth/email-change/confirm", a.ConfirmEmailChange)
	mux.HandleFunc("/auth/logout", a.Logout)
}

// ---------------------------------------------------------------------------
// POST /auth/signup
// ---------------------------------------------------------------------------

// Signup handles new user registration.
//
// Accepts: { "email", "password", "role", "owner_id"? }
// Roles:   "owner", "user", "employee"
//
// For "owner" and "user" roles, a 6-digit OTP is generated, encrypted
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

	req.Username = strings.TrimSpace(req.Username)
	if req.Username == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "username is required",
		})
		return
	}

	runeCount := len([]rune(req.Username))
	if runeCount < 3 || runeCount > 30 {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "username must be between 3 and 30 characters",
		})
		return
	}

	// Accepts Latin and Arabic scripts, digits, underscore, and space; rejects other characters to reduce injection/XSS risk.
	for _, r := range req.Username {
		if !((r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '_' || r == ' ' || (r >= 0x0600 && r <= 0x06FF)) {
			writeJSON(w, http.StatusBadRequest, map[string]string{
				"error": "username contains invalid characters",
			})
			return
		}
	}

	if !models.ValidRole(req.Role) {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error":       "invalid role",
			"valid_roles": "owner, user, employee",
		})
		return
	}

	ctx := r.Context()

	clientIP := a.getClientIP(r)

	// KYE Enforce OwnerID binding for employees
	if req.Role == models.RoleEmployee {
		// Rate limiting check on client IP
		if locked, remaining := a.limiter.IsLocked(clientIP); locked {
			writeJSON(w, http.StatusTooManyRequests, map[string]string{
				"error": fmt.Sprintf("too many failed attempts from this IP. Please try again in %.0f seconds.", remaining.Seconds()),
			})
			return
		}

		if req.OwnerID == "" {
			a.limiter.RecordFailure(clientIP)
			handlerutil.ShipSecurityEvent(ctx, "UNAUTHORIZED_EMPLOYEE_PROVISION_BLOCKED", "auth-service", "unauthenticated", "", fmt.Sprintf("attempted to provision employee %s: missing owner_id", req.Email), handlerutil.GetClientIP(r))
			writeJSON(w, http.StatusBadRequest, map[string]string{
				"error": "owner_id binding is required for employees to satisfy KYE",
			})
			return
		}

		// Require proof that the caller is the owner identified by owner_id.
		claims, err := a.authenticateUser(r)
		if err != nil {
			a.limiter.RecordFailure(clientIP)
			handlerutil.ShipSecurityEvent(ctx, "UNAUTHORIZED_EMPLOYEE_PROVISION_BLOCKED", "auth-service", "unauthenticated", req.OwnerID, fmt.Sprintf("attempted to provision employee %s: authentication failed: %s", req.Email, err.Error()), handlerutil.GetClientIP(r))
			writeJSON(w, http.StatusUnauthorized, map[string]string{
				"error": "missing or invalid authorization header, Bearer token required: " + err.Error(),
			})
			return
		}

		if claims.UserID != req.OwnerID {
			a.limiter.RecordFailure(clientIP)
			handlerutil.ShipSecurityEvent(ctx, "UNAUTHORIZED_EMPLOYEE_PROVISION_BLOCKED", "auth-service", claims.UserID, req.OwnerID, fmt.Sprintf("attempted to provision employee %s: token user ID %s does not match requested owner ID %s", req.Email, claims.UserID, req.OwnerID), handlerutil.GetClientIP(r))
			writeJSON(w, http.StatusForbidden, map[string]string{
				"error": "access denied: caller is not the owner specified by owner_id",
			})
			return
		}

		if claims.Role != string(models.RoleOwner) {
			a.limiter.RecordFailure(clientIP)
			handlerutil.ShipSecurityEvent(ctx, "UNAUTHORIZED_EMPLOYEE_PROVISION_BLOCKED", "auth-service", claims.UserID, req.OwnerID, fmt.Sprintf("attempted to provision employee %s: token role %s is not owner", req.Email, claims.Role), handlerutil.GetClientIP(r))
			writeJSON(w, http.StatusForbidden, map[string]string{
				"error": "access denied: owner role required to provision employees",
			})
			return
		}

		// Verify owner exists and has RoleOwner
		owner := a.store.GetByID(ctx, req.OwnerID)
		if owner == nil {
			a.limiter.RecordFailure(clientIP)
			handlerutil.ShipSecurityEvent(ctx, "UNAUTHORIZED_EMPLOYEE_PROVISION_BLOCKED", "auth-service", claims.UserID, req.OwnerID, fmt.Sprintf("attempted to provision employee %s: specified owner %s does not exist", req.Email, req.OwnerID), handlerutil.GetClientIP(r))
			writeJSON(w, http.StatusBadRequest, map[string]string{
				"error": fmt.Sprintf("specified owner_id %q does not exist", req.OwnerID),
			})
			return
		}
		if owner.Role != models.RoleOwner {
			a.limiter.RecordFailure(clientIP)
			handlerutil.ShipSecurityEvent(ctx, "UNAUTHORIZED_EMPLOYEE_PROVISION_BLOCKED", "auth-service", claims.UserID, req.OwnerID, fmt.Sprintf("attempted to provision employee %s: specified user %s has role %s, not owner", req.Email, req.OwnerID, owner.Role), handlerutil.GetClientIP(r))
			writeJSON(w, http.StatusBadRequest, map[string]string{
				"error": fmt.Sprintf("user %q is not an owner tenant", req.OwnerID),
			})
			return
		}

		// Reset limiter upon successful checks/provisioning start
		a.limiter.Reset(clientIP)
	}

	// For owner/user roles, generate and dispatch OTP on signup and store as pending.
	if req.Role == models.RoleOwner || req.Role == models.RoleUser {
		// Duplicate checks against CONFIRMED existing users in DB.
		if existing := a.store.GetByEmail(ctx, req.Email); existing != nil {
			writeJSON(w, http.StatusConflict, map[string]string{
				"error": "email already registered",
			})
			return
		}

		if existing := a.store.GetByUsername(ctx, req.Username); existing != nil {
			writeJSON(w, http.StatusConflict, map[string]string{
				"error": "username already taken",
			})
			return
		}

		hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{
				"error": "failed to hash password: " + err.Error(),
			})
			return
		}

		otpCode := generate6DigitOTP()
		pending := &models.PendingSignup{
			Email:    req.Email,
			Username: req.Username,
			Password: string(hashedPassword),
			Role:     req.Role,
			OwnerID:  req.OwnerID,
		}

		if err := a.store.SetPendingSignup(ctx, req.Email, pending, otpCode); err != nil {
			log.Printf("[AUTH] Failed to set pending signup for %s: %v", req.Email, err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{
				"error": "failed to set pending signup: " + err.Error(),
			})
			return
		}

		if err := a.dispatcher.Dispatch(req.Email, otpCode); err != nil {
			log.Printf("[AUTH] OTP dispatch error via %s: %v", a.dispatcher.Name(), err)
		}

		if a.isLocal {
			log.Printf("[AUTH] OTP generated for signup: email=%s code=%s dispatcher=%s",
				req.Email, otpCode, a.dispatcher.Name())
		} else {
			log.Printf("[AUTH] OTP generated for signup: email=%s dispatcher=%s",
				req.Email, a.dispatcher.Name())
		}

		resp := map[string]any{
			"status":  "success",
			"message": "OTP dispatched",
		}
		if a.isLocal {
			resp["dev_otp"] = otpCode
		}

		writeJSON(w, http.StatusCreated, resp)
		return
	}

	// Employee signup — immediate creation, no OTP required.
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{
			"error": "failed to hash password: " + err.Error(),
		})
		return
	}

	user := &models.User{
		ID:        generateID(),
		Email:     req.Email,
		Username:  req.Username,
		Password:  string(hashedPassword),
		Role:      req.Role,
		OwnerID:   req.OwnerID,
		TenantID:  req.OwnerID,
		IsActive:  true,
		CreatedAt: time.Now().UTC(),
	}

	if err := a.store.CreateUser(ctx, user); err != nil {
		writeJSON(w, http.StatusConflict, map[string]string{
			"error": err.Error(),
		})
		return
	}

	log.Printf("[AUTH] Employee Signup: email=%s role=%s id=%s owner_id=%s", user.Email, user.Role, user.ID, user.OwnerID)

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
//   - "owner" / "user": generates a 6-digit OTP, encrypts via AES-256,
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
		// Timing-parity: burn a real bcrypt comparison against a dummy hash
		// so the not-found path costs the same as the wrong-password path,
		// closing the response-time enumeration side channel.
		_ = bcrypt.CompareHashAndPassword(dummyBcryptHash, []byte(req.Password))
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

	// Account Suspension & Freeze check (ADR-0022)
	if user.EffectiveAccountStatus() == models.AccountStatusSuspended || !user.IsActive {
		if user.Role == models.RoleEmployee {
			writeJSON(w, http.StatusForbidden, map[string]string{
				"error": "employee account is frozen/inactive. please contact your tenant owner.",
			})
		} else {
			writeJSON(w, http.StatusForbidden, map[string]string{
				"error": "account is suspended",
			})
		}
		return
	}

	log.Printf("[AUTH] Login: email=%s role=%s", user.Email, user.Role)

	// Role-based 2FA decision.
	switch user.Role {
	case models.RoleOwner, models.RoleUser:
		// Generate a 6-digit OTP.
		otpCode := generate6DigitOTP()

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

		if a.isLocal {
			log.Printf("[AUTH] 2FA triggered: email=%s role=%s code=%s dispatcher=%s",
				user.Email, user.Role, otpCode, a.dispatcher.Name())
		} else {
			log.Printf("[AUTH] 2FA triggered: email=%s role=%s dispatcher=%s",
				user.Email, user.Role, a.dispatcher.Name())
		}

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
			"status":   "success",
			"message":  "authenticated",
			"user_id":  user.ID,
			"role":     user.Role,
			"username": user.Username,
			"token":    token,
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

	// 1. Check if user already exists in DB (2FA login verification flow)
	if user := a.store.GetByEmail(ctx, req.Email); user != nil {
		if user.EffectiveAccountStatus() == models.AccountStatusSuspended || !user.IsActive {
			writeJSON(w, http.StatusForbidden, map[string]string{
				"error": "account is suspended",
			})
			return
		}

		if err := a.store.VerifyOTP(ctx, req.Email, req.OTP); err != nil {
			a.limiter.RecordFailure(clientIP)
			a.limiter.RecordFailure(req.Email)
			writeJSON(w, http.StatusUnauthorized, map[string]string{
				"error": "invalid or expired OTP code",
			})
			return
		}

		a.limiter.Reset(clientIP)
		a.limiter.Reset(req.Email)

		log.Printf("[AUTH] 2FA Login OTP verified: email=%s role=%s", user.Email, user.Role)

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
			"username":     user.Username,
			"otp_verified": true,
			"token":        token,
		}
		if user.Role == models.RoleOwner {
			response["kyc_status"] = user.KYCStatus
		}

		writeJSON(w, http.StatusOK, response)
		return
	}

	// 2. No user record exists in DB — check pending signup (Signup OTP verification flow)
	pending, err := a.store.GetAndConsumePendingSignup(ctx, req.Email, req.OTP)
	if err != nil {
		a.limiter.RecordFailure(clientIP)
		a.limiter.RecordFailure(req.Email)
		writeJSON(w, http.StatusUnauthorized, map[string]string{
			"error": "invalid or expired OTP code",
		})
		return
	}

	// Reset limits on success
	a.limiter.Reset(clientIP)
	a.limiter.Reset(req.Email)

	// Build real user record now that OTP verification succeeded
	newUser := &models.User{
		ID:        generateID(),
		Email:     pending.Email,
		Username:  pending.Username,
		Password:  pending.Password, // already bcrypt hashed
		Role:      pending.Role,
		IsActive:  true,
		CreatedAt: time.Now().UTC(),
	}

	if pending.Role == models.RoleOwner {
		newUser.KYCStatus = models.KYCPendingApproval
		newUser.TenantID = newUser.ID
	}

	if err := a.store.CreateUser(ctx, newUser); err != nil {
		writeJSON(w, http.StatusConflict, map[string]string{
			"error": err.Error(),
		})
		return
	}

	log.Printf("[AUTH] Signup completed & user created: email=%s role=%s id=%s", newUser.Email, newUser.Role, newUser.ID)

	token, err := jwtutil.GenerateToken(newUser.ID, string(newUser.Role), newUser.TenantID, newUser.Email)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{
			"error": "failed to generate token: " + err.Error(),
		})
		return
	}

	response := map[string]any{
		"status":       "success",
		"message":      "2FA verification successful — authenticated",
		"user_id":      newUser.ID,
		"role":         newUser.Role,
		"username":     newUser.Username,
		"otp_verified": true,
		"token":        token,
	}

	if newUser.Role == models.RoleOwner {
		response["kyc_status"] = newUser.KYCStatus
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

	// Get Owner. Both failure shapes (nonexistent / non-owner account vs
	// wrong password) MUST be indistinguishable in status and body — the
	// prior distinct wordings confirmed which emails belong to real owners.
	owner := a.store.GetByEmail(ctx, req.OwnerEmail)
	if owner == nil || owner.Role != models.RoleOwner {
		_ = bcrypt.CompareHashAndPassword(dummyBcryptHash, []byte(req.OwnerPassword))
		writeJSON(w, http.StatusForbidden, map[string]string{
			"error": "invalid owner credentials",
		})
		return
	}

	// Verify owner password using bcrypt
	if err := bcrypt.CompareHashAndPassword([]byte(owner.Password), []byte(req.OwnerPassword)); err != nil {
		a.limiter.RecordFailure(clientIP)
		a.limiter.RecordFailure(req.OwnerEmail)
		writeJSON(w, http.StatusForbidden, map[string]string{
			"error": "invalid owner credentials",
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

	// Get Employee to resolve ID. Nonexistent and foreign-tenant employees
	// return the SAME status and body here: the previous 404-vs-400 split
	// distinguished "no such account" from "not yours".
	emp := a.store.GetByEmail(ctx, req.EmployeeEmail)
	if emp == nil {
		log.Printf("[AUTH ERROR] ToggleEmployee failed: employee %q not found", req.EmployeeEmail)
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "employee not found or not authorized for this owner",
		})
		return
	}

	// Toggle Active Status
	err := a.store.ToggleEmployeeActive(ctx, req.EmployeeEmail, owner.ID, req.SetActive)
	if err != nil {
		log.Printf("[AUTH ERROR] ToggleEmployeeActive failed: %v", err)
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "employee not found or not authorized for this owner",
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
	if !emp.IsActive || emp.EffectiveAccountStatus() == models.AccountStatusSuspended {
		writeJSON(w, http.StatusForbidden, map[string]string{
			"error": "action blocked: employee account is frozen",
		})
		return
	}

	// Verify employee's owner has approved KYC and is active
	owner := a.store.GetByID(ctx, emp.OwnerID)
	if owner == nil || owner.KYCStatus != models.KYCApproved || owner.EffectiveAccountStatus() == models.AccountStatusSuspended || !owner.IsActive {
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

	// #nosec G706 //nolint:gosec -- action is sanitized by stripping carriage return and newline characters to prevent log injection
	log.Printf("[AUDIT] Action recorded: employee=%s tenant=%s action=%s ip=%s", emp.ID, emp.OwnerID, strings.ReplaceAll(strings.ReplaceAll(req.Action, "\n", " "), "\r", " "), clientIP)

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

	id := r.URL.Query().Get("user_token")
	if id == "" {
		id = r.URL.Query().Get("id")
	}
	if id == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "id parameter is required",
		})
		return
	}

	ctx := r.Context()
	var lookupID string

	if a.internalServiceToken != "" && subtle.ConstantTimeCompare([]byte(r.Header.Get("X-Internal-Token")), []byte(a.internalServiceToken)) == 1 {
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
		"id":                 user.ID,
		"email":              user.Email,
		"role":               user.Role,
		"username":           user.Username,
		"phone":              user.Phone,
		"frequent_addresses": user.FrequentAddresses,
		"tenant_id":          user.TenantID,
		"kyc_status":         user.KYCStatus,
		"is_active":          user.IsActive,
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
// PATCH /auth/user — Self-service profile update for authenticated user
// ---------------------------------------------------------------------------

func (a *Auth) UpdateProfile(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPatch {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed, use PATCH"})
		return
	}

	claims, err := a.authenticateUser(r)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized: " + err.Error()})
		return
	}

	userID := claims.UserID
	if userID == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid user token: missing user ID"})
		return
	}

	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	// #nosec G120 //nolint:gosec -- body is bounded by http.MaxBytesReader, preventing memory exhaustion
	bodyBytes, err := io.ReadAll(r.Body)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "failed to read request body"})
		return
	}
	if len(bodyBytes) == 0 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "request body cannot be empty"})
		return
	}

	var raw map[string]any
	if err := json.Unmarshal(bodyBytes, &raw); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON: " + err.Error()})
		return
	}

	// IDOR Protection: If request body explicitly specifies user_id, id, or user_token that differs from JWT claims, reject with 403 Forbidden.
	if reqUserID, ok := raw["user_id"].(string); ok && reqUserID != "" && reqUserID != userID {
		log.Printf("[SECURITY WARNING] User %s attempted IDOR profile update on user %s", userID, reqUserID) // #nosec G706 -- user IDs are authenticated claims vs request string
		handlerutil.ShipSecurityEvent(r.Context(), "IDOR_PROFILE_UPDATE_ATTEMPT", "auth-service", userID, reqUserID, fmt.Sprintf("user %s attempted profile update on user %s", userID, reqUserID), handlerutil.GetClientIP(r))
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "access denied: cannot update another user's profile"})
		return
	}
	if reqID, ok := raw["id"].(string); ok && reqID != "" && reqID != userID {
		log.Printf("[SECURITY WARNING] User %s attempted IDOR profile update on user %s", userID, reqID) // #nosec G706 -- user IDs are authenticated claims vs request string
		handlerutil.ShipSecurityEvent(r.Context(), "IDOR_PROFILE_UPDATE_ATTEMPT", "auth-service", userID, reqID, fmt.Sprintf("user %s attempted profile update on user %s", userID, reqID), handlerutil.GetClientIP(r))
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "access denied: cannot update another user's profile"})
		return
	}
	if reqUserToken, ok := raw["user_token"].(string); ok && reqUserToken != "" {
		tokenClaims, err := jwtutil.ValidateToken(reqUserToken)
		if err != nil || tokenClaims.UserID != userID {
			log.Printf("[SECURITY WARNING] User %s attempted IDOR profile update via mismatched user_token", userID) // #nosec G706 -- user IDs are authenticated claims
			handlerutil.ShipSecurityEvent(r.Context(), "IDOR_PROFILE_UPDATE_ATTEMPT", "auth-service", userID, reqUserToken, "user attempted profile update via mismatched user_token", handlerutil.GetClientIP(r))
			writeJSON(w, http.StatusForbidden, map[string]string{"error": "access denied: cannot update another user's profile"})
			return
		}
	}

	ctx := r.Context()
	user := a.store.GetByID(ctx, userID)
	if user == nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "user not found"})
		return
	}

	updateFields := bson.M{}

	// 1. Username
	if val, exists := raw["username"]; exists {
		str, ok := val.(string)
		if !ok {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "username must be a string"})
			return
		}
		str = strings.TrimSpace(str)
		if str == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "username cannot be empty"})
			return
		}
		if str != user.Username {
			existing := a.store.GetByUsername(ctx, str)
			if existing != nil && existing.ID != user.ID {
				writeJSON(w, http.StatusConflict, map[string]string{"error": "username is already taken"})
				return
			}
			updateFields["username"] = str
		}
	}

	// 2. Phone
	if val, exists := raw["phone"]; exists {
		str, ok := val.(string)
		if !ok {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "phone must be a string"})
			return
		}
		str = strings.TrimSpace(str)
		if str == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "phone number cannot be empty"})
			return
		}
		if !phoneRegex.MatchString(str) {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid phone number format"})
			return
		}
		updateFields["phone"] = str
	}

	// 3. Frequent Addresses
	if val, exists := raw["frequent_addresses"]; exists {
		arr, ok := val.([]any)
		if !ok {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "frequent_addresses must be an array of strings"})
			return
		}
		if len(arr) > 10 {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "frequent_addresses cannot exceed 10 entries"})
			return
		}
		addresses := make([]string, 0, len(arr))
		for _, item := range arr {
			addrStr, ok := item.(string)
			if !ok {
				writeJSON(w, http.StatusBadRequest, map[string]string{"error": "frequent_addresses entries must be strings"})
				return
			}
			addrStr = strings.TrimSpace(addrStr)
			if addrStr != "" {
				addresses = append(addresses, addrStr)
			}
		}
		updateFields["frequent_addresses"] = addresses
	}

	if len(updateFields) == 0 {
		writeJSON(w, http.StatusOK, map[string]any{"message": "no profile fields updated", "user": user})
		return
	}

	if err := a.store.UpdateUser(ctx, userID, bson.M{"$set": updateFields}); err != nil {
		log.Printf("[AUTH] Failed to update user profile for user %s: %v", userID, err)
		if mongo.IsDuplicateKeyError(err) {
			writeJSON(w, http.StatusConflict, map[string]string{"error": "username is already taken"})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "failed to update user profile"})
		return
	}

	updatedUser := a.store.GetByID(ctx, userID)
	log.Printf("[AUTH] User profile updated: id=%s username=%s", updatedUser.ID, updatedUser.Username) // #nosec G706 -- updatedUser.ID and Username are loaded from DB record
	writeJSON(w, http.StatusOK, map[string]any{
		"message": "profile updated successfully",
		"user":    updatedUser,
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
	if tenantID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "tenant_id parameter is required",
		})
		return
	}

	requesterParam := r.URL.Query().Get("requester_token")
	if requesterParam == "" {
		requesterParam = r.URL.Query().Get("requester_id")
	}
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
		// #nosec G706 //nolint:gosec -- user and tenant IDs are validated and extracted from cryptographically verified JWT claims, log injection is not possible
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

// dummyBcryptHash is a valid bcrypt digest of an unknown random string,
// compared against on every user-not-found authentication path so response
// timing is independent of account existence (cost 10).
var dummyBcryptHash = []byte("$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy")

func writeJSON(w http.ResponseWriter, status int, data any) {
	handlerutil.WriteJSON(w, status, data)
}

// generateID creates a short random hex ID (16 chars).
func generateID() string {
	b := make([]byte, 8)
	if _, err := rand.Read(b); err != nil {
		log.Fatalf("generateID: failed to read random bytes: %v", err)
	}
	return hex.EncodeToString(b)
}

// generate6DigitOTP returns a cryptographically random 6-digit numeric OTP.
func generate6DigitOTP() string {
	b := make([]byte, 4)
	if _, err := rand.Read(b); err != nil {
		log.Fatalf("generate6DigitOTP: failed to read random bytes: %v", err)
	}
	// Convert 4 random bytes to a number in [0, 999999].
	num := (uint32(b[0])<<24 | uint32(b[1])<<16 | uint32(b[2])<<8 | uint32(b[3])) % 1000000
	return fmt.Sprintf("%06d", num)
}

// getClientIP extracts the user's real IP from the request headers or RemoteAddr.
// Trust Chain Hop 2 (api-gateway -> auth-service):
// auth-service trusts X-Forwarded-For ONLY if the request contains a valid X-Gateway-Secret
// header injected exclusively by api-gateway. When valid, auth-service parses the first IP
// in the X-Forwarded-For chain (the original client IP preserved by api-gateway).
// If X-Gateway-Secret is missing/invalid, auth-service falls back to r.RemoteAddr.
func (a *Auth) getClientIP(r *http.Request) string {
	var ip string
	// Constant-time comparison: the gateway secret gates XFF trust for
	// security-relevant audit attribution. Empty-secret precondition prevents
	// matching unconfigured secrets.
	if a.gatewaySecret != "" && subtle.ConstantTimeCompare([]byte(r.Header.Get("X-Gateway-Secret")), []byte(a.gatewaySecret)) == 1 {
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
	// #nosec G120 //nolint:gosec -- body is bounded by http.MaxBytesReader, preventing memory exhaustion
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
	// #nosec G120 //nolint:gosec -- body is bounded by http.MaxBytesReader, preventing memory exhaustion
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

	reviewer, err := a.authenticateReviewer(r)
	if err != nil {
		writeReviewerAuthError(w, err)
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
		Username         string           `json:"username"`
		Role             models.Role      `json:"role"`
		KYCStatus        models.KYCStatus `json:"kyc_status,omitempty"`
		KYEStatus        models.KYCStatus `json:"kye_status,omitempty"`
		IDFrontURL       string           `json:"id_front_url,omitempty"`
		IDBackURL        string           `json:"id_back_url,omitempty"`
		SelfieURL        string           `json:"selfie_url,omitempty"`
		BusinessProofURL string           `json:"business_proof_url,omitempty"`
		DocumentErrors   []string         `json:"document_errors,omitempty"`
	}

	results := make([]Submission, 0, len(users))
	for _, u := range users {
		sub := Submission{
			UserID:    u.ID,
			Email:     u.Email,
			Username:  u.Username,
			Role:      u.Role,
			KYCStatus: u.KYCStatus,
			KYEStatus: u.KYEStatus,
		}

		if u.IDFrontDoc != "" {
			url, err := a.storage.GetSignedURL(ctx, u.IDFrontDoc, 15*time.Minute)
			if err != nil {
				log.Printf("[AUTH] Failed to generate signed URL for id_front doc (user %s): %v", u.ID, err)
				sub.DocumentErrors = append(sub.DocumentErrors, "Failed to load id_front")
			} else {
				sub.IDFrontURL = url
				handlerutil.ShipSecurityEvent(ctx, "DOCUMENT_VIEWED", "auth-service", reviewer.ID, u.ID, fmt.Sprintf("generated signed url for IDFrontDoc key: %s", u.IDFrontDoc), handlerutil.GetClientIP(r))
			}
		}
		if u.IDBackDoc != "" {
			url, err := a.storage.GetSignedURL(ctx, u.IDBackDoc, 15*time.Minute)
			if err != nil {
				log.Printf("[AUTH] Failed to generate signed URL for id_back doc (user %s): %v", u.ID, err)
				sub.DocumentErrors = append(sub.DocumentErrors, "Failed to load id_back")
			} else {
				sub.IDBackURL = url
				handlerutil.ShipSecurityEvent(ctx, "DOCUMENT_VIEWED", "auth-service", reviewer.ID, u.ID, fmt.Sprintf("generated signed url for IDBackDoc key: %s", u.IDBackDoc), handlerutil.GetClientIP(r))
			}
		}
		if u.SelfieDoc != "" {
			url, err := a.storage.GetSignedURL(ctx, u.SelfieDoc, 15*time.Minute)
			if err != nil {
				log.Printf("[AUTH] Failed to generate signed URL for selfie doc (user %s): %v", u.ID, err)
				sub.DocumentErrors = append(sub.DocumentErrors, "Failed to load selfie")
			} else {
				sub.SelfieURL = url
				handlerutil.ShipSecurityEvent(ctx, "DOCUMENT_VIEWED", "auth-service", reviewer.ID, u.ID, fmt.Sprintf("generated signed url for SelfieDoc key: %s", u.SelfieDoc), handlerutil.GetClientIP(r))
			}
		}
		if u.BusinessProofDoc != "" {
			url, err := a.storage.GetSignedURL(ctx, u.BusinessProofDoc, 15*time.Minute)
			if err != nil {
				log.Printf("[AUTH] Failed to generate signed URL for business_proof doc (user %s): %v", u.ID, err)
				sub.DocumentErrors = append(sub.DocumentErrors, "Failed to load business_proof")
			} else {
				sub.BusinessProofURL = url
				handlerutil.ShipSecurityEvent(ctx, "DOCUMENT_VIEWED", "auth-service", reviewer.ID, u.ID, fmt.Sprintf("generated signed url for BusinessProofDoc key: %s", u.BusinessProofDoc), handlerutil.GetClientIP(r))
			}
		}

		results = append(results, sub)
	}

	handlerutil.ShipSecurityEvent(ctx, "KYC_PENDING_LISTED", "auth-service", reviewer.ID, "", "retrieved list of pending KYB/KYE applications", handlerutil.GetClientIP(r))

	writeJSON(w, http.StatusOK, results)
}

// POST /auth/kyb-kye/review
func (a *Auth) ReviewKYBKYESubmissions(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use POST"})
		return
	}

	reviewer, err := a.authenticateReviewer(r)
	if err != nil {
		writeReviewerAuthError(w, err)
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

	// ADR-0021: a rejection must always carry an explanation. Enforced at the
	// API layer (defense in depth) so the rule holds regardless of which
	// client calls this endpoint.
	if req.Action == "reject" && strings.TrimSpace(req.Reason) == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "reason is required for rejection"})
		return
	}

	// Bound the reason length, mirroring the RateJob comment limit.
	if len(req.Reason) > 1000 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "reason exceeds maximum length of 1000 characters"})
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
			"reviewer_id":      reviewer.ID,
			"reviewed_at":      time.Now().UTC(),
			"rejection_reason": req.Reason,
		},
	}

	var statusField string
	if isOwner {
		statusField = "kyc_status"
		update["$set"].(bson.M)["kyc_status"] = finalStatus
	} else {
		statusField = "kye_status"
		update["$set"].(bson.M)["kye_status"] = finalStatus
	}

	updated, err := a.store.UpdateUserConditional(ctx, targetUser.ID, statusField, models.KYCPendingApproval, update)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	if !updated {
		writeJSON(w, http.StatusConflict, map[string]string{"error": "submission status has already changed or been reviewed"})
		return
	}

	a.store.AppendAudit(ctx, models.AuditEntry{
		EmployeeID: reviewer.ID,
		TenantID:   targetUser.ID,
		Action:     "KYC_REVIEWED",
		Timestamp:  time.Now().UTC(),
		ClientIP:   handlerutil.GetClientIP(r),
	})

	handlerutil.ShipSecurityEvent(ctx, "KYC_REVIEWED", "auth-service", reviewer.ID, req.UserID, fmt.Sprintf("action: %s, reason: %s", req.Action, req.Reason), handlerutil.GetClientIP(r))

	// ADR-0021: fire-and-forget user notification. Deliberately decoupled from
	// the review transaction — a dispatch failure must never fail the
	// already-persisted review (see dispatchReviewOutcomeNotification).
	a.dispatchReviewOutcomeNotification(targetUser, finalStatus, req.Reason)

	writeJSON(w, http.StatusOK, map[string]string{"status": "reviewed", "action": req.Action})
}

// dispatchReviewOutcomeNotification informs the reviewed user of an approve or
// reject decision via notification-service's internal send endpoint
// (POST /notifications/send). It runs asynchronously: if the dispatch fails,
// the failure is logged distinctly under [KYC-NOTIFY] and swallowed — the
// review itself remains recorded and auditable, and the existing KYC status
// screens remain the source of truth. No inline retry in this iteration
// (deferred per ADR-0021).
func (a *Auth) dispatchReviewOutcomeNotification(targetUser *models.User, finalStatus models.KYCStatus, reason string) {
	if a.notificationURL == "" || a.notificationClient == nil {
		log.Printf("[KYC-NOTIFY] notification-service not configured; skipping outcome notification for user %s", targetUser.ID)
		return
	}

	kind := "KYE"
	if targetUser.Role == models.RoleOwner {
		kind = "KYB"
	}

	var notifType, title, body string
	switch finalStatus {
	case models.KYCApproved:
		notifType = "kyc_approved"
		title = "Verification approved"
		body = fmt.Sprintf("Your %s verification has been approved.", kind)
	case models.KYCRejected:
		notifType = "kyc_rejected"
		title = "Verification rejected"
		body = fmt.Sprintf("Your %s verification was rejected. Reason: %s", kind, reason)
	default:
		return
	}

	payload := map[string]any{
		"type":      notifType,
		"tenant_id": targetUser.TenantID,
		"user_id":   targetUser.ID,
		"title":     title,
		"body":      body,
	}
	bodyBytes, err := json.Marshal(payload)
	if err != nil {
		log.Printf("[KYC-NOTIFY] Failed to marshal outcome notification for user %s: %v", targetUser.ID, err)
		return
	}

	go func() {
		defer func() {
			if rec := recover(); rec != nil {
				log.Printf("[KYC-NOTIFY] Recovered from panic dispatching outcome notification for user %s: %v", targetUser.ID, rec)
			}
		}()

		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()

		sendURL := strings.TrimSuffix(a.notificationURL, "/") + "/notifications/send"
		// #nosec G704 //nolint:gosec -- sendURL is constructed from internal service config (NOTIFICATION_SERVICE_URL)
		req, err := http.NewRequestWithContext(ctx, http.MethodPost, sendURL, bytes.NewReader(bodyBytes))
		if err != nil {
			log.Printf("[KYC-NOTIFY] Failed to build outcome notification request for user %s: %v", targetUser.ID, err)
			return
		}
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("X-Internal-Token", a.internalServiceToken)

		resp, err := a.notificationClient.Do(req)
		if err != nil {
			log.Printf("[KYC-NOTIFY] FAILED to dispatch %s notification for user %s: %v (review remains recorded; status screens are source of truth)", notifType, targetUser.ID, err)
			return
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			// #nosec G706 //nolint:gosec -- status code only; no user-controlled data interpolated
			log.Printf("[KYC-NOTIFY] notification-service returned status %d for %s notification targeting user %s", resp.StatusCode, notifType, targetUser.ID)
			return
		}
	}()
}

// GET /auth/documents/view?token=xxx
func (a *Auth) ViewDocument(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use GET"})
		return
	}

	reviewer, err := a.authenticateReviewer(r)
	if err != nil {
		writeReviewerAuthError(w, err)
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

	handlerutil.ShipSecurityEvent(r.Context(), "DOCUMENT_VIEWED", "auth-service", reviewer.ID, "", fmt.Sprintf("accessed document key: %s", key), handlerutil.GetClientIP(r))

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
		// #nosec G706 //nolint:gosec -- key is validated and extracted from cryptographically signed JWT token, log injection is not possible
		log.Printf("[VIEW] failed to stream document %s: %v", key, err)
	}
}

// GET /auth/accounts
func (a *Auth) GetAccounts(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use GET"})
		return
	}

	reviewer, err := a.authenticateReviewer(r)
	if err != nil {
		writeReviewerAuthError(w, err)
		return
	}

	search := r.URL.Query().Get("search")
	role := r.URL.Query().Get("role")
	status := r.URL.Query().Get("status")

	page := 1
	if pStr := r.URL.Query().Get("page"); pStr != "" {
		if p, err := strconv.Atoi(pStr); err == nil && p > 0 {
			page = p
		}
	}
	limit := 20
	if lStr := r.URL.Query().Get("limit"); lStr != "" {
		if l, err := strconv.Atoi(lStr); err == nil && l > 0 {
			limit = l
			if limit > 100 {
				limit = 100
			}
		}
	}

	ctx := r.Context()
	users, total, err := a.store.ListAccounts(ctx, search, role, status, page, limit)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	items := make([]models.AccountDirectoryItem, 0, len(users))
	for _, u := range users {
		items = append(items, models.AccountDirectoryItem{
			ID:               u.ID,
			Email:            u.Email,
			Username:         u.Username,
			Role:             u.Role,
			KYCStatus:        u.KYCStatus,
			KYEStatus:        u.KYEStatus,
			AccountStatus:    u.EffectiveAccountStatus(),
			IsActive:         u.IsActive,
			SuspensionReason: u.SuspensionReason,
			SuspendedAt:      u.SuspendedAt,
			ReactivatedAt:    u.ReactivatedAt,
			CreatedAt:        u.CreatedAt,
		})
	}

	handlerutil.ShipSecurityEvent(ctx, "ACCOUNTS_LISTED", "auth-service", reviewer.ID, "", fmt.Sprintf("listed accounts search=%q role=%q status=%q page=%d limit=%d total=%d", search, role, status, page, limit, total), handlerutil.GetClientIP(r))

	writeJSON(w, http.StatusOK, models.AccountDirectoryResponse{
		Accounts: items,
		Total:    total,
		Page:     page,
		Limit:    limit,
	})
}

// POST /auth/accounts/suspend or POST /auth/accounts/{id}/suspend
func (a *Auth) SuspendAccount(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use POST"})
		return
	}

	reviewer, err := a.authenticateReviewer(r)
	if err != nil {
		writeReviewerAuthError(w, err)
		return
	}

	// Extract target user ID from PathValue, URL path prefix, or JSON body
	targetUserID := r.PathValue("id")
	if targetUserID == "" && strings.HasPrefix(r.URL.Path, "/auth/accounts/") {
		trimmed := strings.TrimPrefix(r.URL.Path, "/auth/accounts/")
		if idx := strings.Index(trimmed, "/suspend"); idx > 0 {
			targetUserID = trimmed[:idx]
		}
	}

	var req models.SuspendAccountRequest
	if r.Body != nil {
		_ = json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(&req)
	}
	if targetUserID == "" {
		targetUserID = req.UserID
	}

	if targetUserID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "user_id is required"})
		return
	}

	reason := strings.TrimSpace(req.Reason)
	if reason == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "reason is required for suspension"})
		return
	}
	if len(reason) > 1000 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "reason exceeds maximum length of 1000 characters"})
		return
	}

	ctx := r.Context()
	targetUser := a.store.GetByID(ctx, targetUserID)
	if targetUser == nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "user not found"})
		return
	}

	// Atomic CAS update: only suspend if not already suspended
	suspended, err := a.store.SuspendUser(ctx, targetUserID, reason, reviewer.ID)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	if !suspended {
		writeJSON(w, http.StatusConflict, map[string]string{"error": "account is already suspended"})
		return
	}

	// Invalidate active JWT tokens in Redis across all services
	_ = jwtutil.RevokeAllUserTokens(targetUserID)

	// Append audit log
	a.store.AppendAudit(ctx, models.AuditEntry{
		EmployeeID: reviewer.ID,
		TenantID:   targetUser.ID,
		Action:     "ACCOUNT_SUSPENDED",
		Timestamp:  time.Now().UTC(),
		ClientIP:   handlerutil.GetClientIP(r),
	})

	handlerutil.ShipSecurityEvent(ctx, "ACCOUNT_SUSPENDED", "auth-service", reviewer.ID, targetUserID, fmt.Sprintf("reason: %s", reason), handlerutil.GetClientIP(r))

	// Dispatch notification fire-and-forget
	a.dispatchAccountStatusNotification(targetUser, models.AccountStatusSuspended, reason)

	writeJSON(w, http.StatusOK, map[string]any{
		"status":         "suspended",
		"user_id":        targetUserID,
		"account_status": models.AccountStatusSuspended,
	})
}

// POST /auth/accounts/reactivate or POST /auth/accounts/{id}/reactivate
func (a *Auth) ReactivateAccount(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use POST"})
		return
	}

	reviewer, err := a.authenticateReviewer(r)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return
	}

	// Extract target user ID from PathValue, URL path prefix, or JSON body
	targetUserID := r.PathValue("id")
	if targetUserID == "" && strings.HasPrefix(r.URL.Path, "/auth/accounts/") {
		trimmed := strings.TrimPrefix(r.URL.Path, "/auth/accounts/")
		if idx := strings.Index(trimmed, "/reactivate"); idx > 0 {
			targetUserID = trimmed[:idx]
		}
	}

	var req models.ReactivateAccountRequest
	if r.Body != nil {
		_ = json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(&req)
	}
	if targetUserID == "" {
		targetUserID = req.UserID
	}

	if targetUserID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "user_id is required"})
		return
	}

	reason := strings.TrimSpace(req.Reason)
	if len(reason) > 1000 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "reason exceeds maximum length of 1000 characters"})
		return
	}

	ctx := r.Context()
	targetUser := a.store.GetByID(ctx, targetUserID)
	if targetUser == nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "user not found"})
		return
	}

	// Atomic CAS update: only reactivate if currently suspended
	reactivated, err := a.store.ReactivateUser(ctx, targetUserID, reason, reviewer.ID)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	if !reactivated {
		writeJSON(w, http.StatusConflict, map[string]string{"error": "account is already active"})
		return
	}

	// Append audit log
	a.store.AppendAudit(ctx, models.AuditEntry{
		EmployeeID: reviewer.ID,
		TenantID:   targetUser.ID,
		Action:     "ACCOUNT_REACTIVATED",
		Timestamp:  time.Now().UTC(),
		ClientIP:   handlerutil.GetClientIP(r),
	})

	handlerutil.ShipSecurityEvent(ctx, "ACCOUNT_REACTIVATED", "auth-service", reviewer.ID, targetUserID, fmt.Sprintf("reason: %s", reason), handlerutil.GetClientIP(r))

	// Dispatch notification fire-and-forget
	a.dispatchAccountStatusNotification(targetUser, models.AccountStatusActive, reason)

	writeJSON(w, http.StatusOK, map[string]any{
		"status":         "reactivated",
		"user_id":        targetUserID,
		"account_status": models.AccountStatusActive,
	})
}

// dispatchAccountStatusNotification informs the affected user of account suspension or reactivation
// via notification-service's internal send endpoint (POST /notifications/send).
func (a *Auth) dispatchAccountStatusNotification(targetUser *models.User, newStatus models.AccountStatus, reason string) {
	if a.notificationURL == "" || a.notificationClient == nil {
		log.Printf("[ACCOUNT-NOTIFY] notification-service not configured; skipping account status notification for user %s", targetUser.ID)
		return
	}

	var notifType, title, body string
	switch newStatus {
	case models.AccountStatusSuspended:
		notifType = "account_suspended"
		title = "Account suspended"
		body = fmt.Sprintf("Your account has been suspended. Reason: %s", reason)
	case models.AccountStatusActive:
		notifType = "account_reactivated"
		title = "Account reactivated"
		body = "Your account has been reactivated and access has been restored."
	default:
		return
	}

	payload := map[string]any{
		"type":      notifType,
		"tenant_id": targetUser.TenantID,
		"user_id":   targetUser.ID,
		"title":     title,
		"body":      body,
	}
	bodyBytes, err := json.Marshal(payload)
	if err != nil {
		// #nosec G706 //nolint:gosec -- log format string does not interpolate unsanitized user inputs
		log.Printf("[ACCOUNT-NOTIFY] Failed to marshal account status notification for user %s: %v", targetUser.ID, err)
		return
	}

	go func() {
		defer func() {
			if rec := recover(); rec != nil {
				// #nosec G706 //nolint:gosec -- log format string does not interpolate unsanitized user inputs
				log.Printf("[ACCOUNT-NOTIFY] Recovered from panic dispatching account status notification for user %s: %v", targetUser.ID, rec)
			}
		}()

		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()

		sendURL := strings.TrimSuffix(a.notificationURL, "/") + "/notifications/send"
		// #nosec G704 //nolint:gosec -- sendURL is constructed from internal service config (NOTIFICATION_SERVICE_URL)
		req, err := http.NewRequestWithContext(ctx, http.MethodPost, sendURL, bytes.NewReader(bodyBytes))
		if err != nil {
			// #nosec G706 //nolint:gosec -- log format string does not interpolate unsanitized user inputs
			log.Printf("[ACCOUNT-NOTIFY] Failed to build account status notification request for user %s: %v", targetUser.ID, err)
			return
		}
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("X-Internal-Token", a.internalServiceToken)

		resp, err := a.notificationClient.Do(req)
		if err != nil {
			// #nosec G706 //nolint:gosec -- log format string does not interpolate unsanitized user inputs
			log.Printf("[ACCOUNT-NOTIFY] FAILED to dispatch %s notification for user %s: %v", notifType, targetUser.ID, err)
			return
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			// #nosec G706 //nolint:gosec -- status code only; no user-controlled data interpolated
			log.Printf("[ACCOUNT-NOTIFY] notification-service returned status %d for %s notification targeting user %s", resp.StatusCode, notifType, targetUser.ID)
			return
		}
	}()
}

func hashToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

// ReviewerRateLimitError indicates that the reviewer login attempt was rejected due to rate limiting.
type ReviewerRateLimitError struct {
	Remaining time.Duration
}

func (e *ReviewerRateLimitError) Error() string {
	return fmt.Sprintf("too many failed reviewer login attempts. Please try again in %.0f seconds.", e.Remaining.Seconds())
}

func writeReviewerAuthError(w http.ResponseWriter, err error) {
	var rle *ReviewerRateLimitError
	if errors.As(err, &rle) {
		writeJSON(w, http.StatusTooManyRequests, map[string]string{
			"error": rle.Error(),
		})
		return
	}
	writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
}

// authenticateReviewer verifies the reviewer's credentials.
// It checks both the X-Internal-Token and the X-Reviewer-Token headers.
// Defaulting to requiring both as the safer option (internal network context + reviewer token).
// Enforces 3 failed attempts -> 5-minute lockout rate limiting keyed by IP and hashed token.
func (a *Auth) authenticateReviewer(r *http.Request) (*models.Reviewer, error) {
	// FLAGGED: Operationally, KYB/KYE reviews could be performed by internal staff via an internal network
	// or remote staff over HTTPS. As it is unclear whether remote access is required without the internal token,
	// we default to the safer option of requiring BOTH the X-Internal-Token (internal network context)
	// and the reviewer token (X-Reviewer-Token).

	// 1. Verify X-Internal-Token header
	internalToken := r.Header.Get("X-Internal-Token")
	// Empty-secret precondition mirrors GetUser: ConstantTimeCompare on two
	// empty byte slices returns 1, which would authenticate any caller if the
	// configured token were ever empty.
	if a.internalServiceToken == "" || subtle.ConstantTimeCompare([]byte(internalToken), []byte(a.internalServiceToken)) != 1 {
		return nil, errors.New("unauthorized internal token")
	}

	clientIP := a.getClientIP(r)

	// Check if client IP is currently locked out
	if locked, remaining := a.limiter.IsReviewerLocked(clientIP); locked {
		return nil, &ReviewerRateLimitError{Remaining: remaining}
	}

	// 2. Verify X-Reviewer-Token header
	reviewerToken := r.Header.Get("X-Reviewer-Token")
	if reviewerToken == "" {
		lockoutIP := a.limiter.RecordReviewerFailure(clientIP)
		if lockoutIP > 0 {
			return nil, &ReviewerRateLimitError{Remaining: lockoutIP}
		}
		return nil, errors.New("missing reviewer token")
	}

	tokenHash := hashToken(reviewerToken)
	// Check if attempted token hash is currently locked out
	if locked, remaining := a.limiter.IsReviewerLocked(tokenHash); locked {
		return nil, &ReviewerRateLimitError{Remaining: remaining}
	}

	ctx := r.Context()
	rev, err := a.store.GetReviewerByToken(ctx, reviewerToken)
	if err != nil {
		lockoutIP := a.limiter.RecordReviewerFailure(clientIP)
		lockoutTok := a.limiter.RecordReviewerFailure(tokenHash)
		remaining := lockoutIP
		if lockoutTok > remaining {
			remaining = lockoutTok
		}
		if remaining > 0 {
			return nil, &ReviewerRateLimitError{Remaining: remaining}
		}
		return nil, errors.New("invalid reviewer token")
	}

	// Constant-time confirmation against the single candidate row. The stored
	// credential is a SHA-256 digest for all reviewers onboarded since the
	// at-rest hashing migration, so the presented RAW token must be hashed
	// before comparison; legacy plaintext rows compare directly.
	if !store.MatchesStoredReviewerCredential(rev.Token, reviewerToken) {
		lockoutIP := a.limiter.RecordReviewerFailure(clientIP)
		lockoutTok := a.limiter.RecordReviewerFailure(tokenHash)
		remaining := lockoutIP
		if lockoutTok > remaining {
			remaining = lockoutTok
		}
		if remaining > 0 {
			return nil, &ReviewerRateLimitError{Remaining: remaining}
		}
		return nil, errors.New("invalid reviewer token")
	}

	// Reset failure counter on successful authentication
	a.limiter.ResetReviewer(clientIP)
	a.limiter.ResetReviewer(tokenHash)

	return rev, nil
}

// VerifyReviewer verifies a reviewer's token and returns reviewer identity.
// GET /auth/reviewer/verify
func (a *Auth) VerifyReviewer(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use GET"})
		return
	}

	reviewer, err := a.authenticateReviewer(r)
	if err != nil {
		writeReviewerAuthError(w, err)
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"id":   reviewer.ID,
		"name": reviewer.Name,
	})
}

// POST /auth/logout
func (a *Auth) Logout(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use POST"})
		return
	}

	authHeader := r.Header.Get("Authorization")
	if !strings.HasPrefix(authHeader, "Bearer ") {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing or invalid authorization header, Bearer token required"})
		return
	}
	tokenStr := strings.TrimPrefix(authHeader, "Bearer ")

	err := jwtutil.RevokeToken(tokenStr)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "logout failed: " + err.Error()})
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"message": "successfully logged out"})
}

// ResendOTPRequest represents the payload for resending an OTP.
type ResendOTPRequest struct {
	Email string `json:"email"`
}

// ResendOTP handles resending a fresh OTP for unconfirmed accounts.
func (a *Auth) ResendOTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{
			"error": "method not allowed, use POST",
		})
		return
	}

	var req ResendOTPRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "invalid JSON body: " + err.Error(),
		})
		return
	}

	if req.Email == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "email is required",
		})
		return
	}

	clientIP := a.getClientIP(r)

	// Check if IP is locked out
	if locked, remaining := a.limiter.IsLocked(clientIP); locked {
		writeJSON(w, http.StatusTooManyRequests, map[string]string{
			"error": fmt.Sprintf("too many attempts from this IP. Please try again in %.0f seconds.", remaining.Seconds()),
		})
		return
	}

	// Check if Email is locked out
	if locked, remaining := a.limiter.IsLocked(req.Email); locked {
		writeJSON(w, http.StatusTooManyRequests, map[string]string{
			"error": fmt.Sprintf("too many attempts for this email. Please try again in %.0f seconds.", remaining.Seconds()),
		})
		return
	}

	ctx := r.Context()

	// Generic success response to avoid identity leakage
	genericResponse := map[string]any{
		"status":  "success",
		"message": "OTP dispatched",
	}

	user := a.store.GetByEmail(ctx, req.Email)
	if user != nil {
		// Existing user records in DB are already confirmed accounts.
		writeJSON(w, http.StatusOK, genericResponse)
		return
	}

	// Check if a pending signup exists for this email
	pending := a.store.GetPendingSignup(ctx, req.Email)
	if pending == nil {
		a.limiter.RecordFailure(clientIP)
		a.limiter.RecordFailure(req.Email)
		writeJSON(w, http.StatusOK, genericResponse)
		return
	}

	// Pending signup found: generate a fresh 6-digit OTP code and overwrite the pending signup.
	otpCode := generate6DigitOTP()
	if err := a.store.SetPendingSignup(ctx, req.Email, pending, otpCode); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{
			"error": "failed to set OTP: " + err.Error(),
		})
		return
	}

	// Dispatch via the configured dispatcher (mock logs to stdout).
	if err := a.dispatcher.Dispatch(req.Email, otpCode); err != nil {
		log.Printf("[AUTH] OTP resend dispatch error via %s: %v", a.dispatcher.Name(), err)
	}

	if a.isLocal {
		log.Printf("[AUTH] OTP generated for resend: email=%s code=%s dispatcher=%s",
			req.Email, otpCode, a.dispatcher.Name())
		genericResponse["dev_otp"] = otpCode
	} else {
		log.Printf("[AUTH] OTP generated for resend: email=%s dispatcher=%s",
			req.Email, a.dispatcher.Name())
	}

	// Record request in rate limiter
	a.limiter.RecordFailure(clientIP)
	a.limiter.RecordFailure(req.Email)

	writeJSON(w, http.StatusOK, genericResponse)
}

// ---------------------------------------------------------------------------
// POST /auth/forgot-password
// ---------------------------------------------------------------------------

// ForgotPassword dispatches a 6-digit password reset OTP to the specified email if registered.
// Regardless of whether the email exists or OTP generation fails, it returns an identical 200 OK
// response to prevent identity enumeration.
func (a *Auth) ForgotPassword(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{
			"error": "method not allowed, use POST",
		})
		return
	}

	var req models.ForgotPasswordRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "invalid JSON body: " + err.Error(),
		})
		return
	}

	if req.Email == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "email is required",
		})
		return
	}

	clientIP := a.getClientIP(r)

	// Rate limiting check on client IP
	if locked, remaining := a.limiter.IsLocked(clientIP); locked {
		writeJSON(w, http.StatusTooManyRequests, map[string]string{
			"error": fmt.Sprintf("too many attempts from this IP. Please try again in %.0f seconds.", remaining.Seconds()),
		})
		return
	}

	// Rate limiting check on Email
	if locked, remaining := a.limiter.IsLocked(req.Email); locked {
		writeJSON(w, http.StatusTooManyRequests, map[string]string{
			"error": fmt.Sprintf("too many attempts for this email. Please try again in %.0f seconds.", remaining.Seconds()),
		})
		return
	}

	ctx := r.Context()
	user := a.store.GetByEmail(ctx, req.Email)

	// Base response payload identical for all cases to prevent account enumeration.
	resp := map[string]any{
		"status":  "success",
		"message": "If an account exists for this email, a reset code has been sent.",
	}

	if user == nil {
		a.limiter.RecordFailure(clientIP)
		a.limiter.RecordFailure(req.Email)
		writeJSON(w, http.StatusOK, resp)
		return
	}

	// User exists: generate OTP, encrypt & store in MongoDB, and dispatch.
	otpCode := generate6DigitOTP()

	if err := a.store.SetOTP(ctx, user.Email, otpCode); err != nil {
		log.Printf("[AUTH] Failed to set password reset OTP for %s: %v", user.Email, err)
		writeJSON(w, http.StatusOK, resp)
		return
	}

	if err := a.dispatcher.Dispatch(user.Email, otpCode); err != nil {
		log.Printf("[AUTH] Password reset OTP dispatch error for %s via %s: %v", user.Email, a.dispatcher.Name(), err)
	}

	if a.isLocal {
		log.Printf("[AUTH] Password reset OTP generated: email=%s code=%s dispatcher=%s",
			user.Email, otpCode, a.dispatcher.Name())
		resp["dev_otp"] = otpCode
	} else {
		log.Printf("[AUTH] Password reset OTP generated: email=%s dispatcher=%s",
			user.Email, a.dispatcher.Name())
	}

	writeJSON(w, http.StatusOK, resp)
}

// ---------------------------------------------------------------------------
// POST /auth/reset-password
// ---------------------------------------------------------------------------

// ResetPassword validates the reset OTP code and updates the user's password.
func (a *Auth) ResetPassword(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{
			"error": "method not allowed, use POST",
		})
		return
	}

	var req models.ResetPasswordRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "invalid JSON body: " + err.Error(),
		})
		return
	}

	if req.Email == "" || req.OTP == "" || req.NewPassword == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "email, otp, and new_password are required",
		})
		return
	}

	clientIP := a.getClientIP(r)

	// Rate limiting check on client IP
	if locked, remaining := a.limiter.IsLocked(clientIP); locked {
		writeJSON(w, http.StatusTooManyRequests, map[string]string{
			"error": fmt.Sprintf("too many attempts from this IP. Please try again in %.0f seconds.", remaining.Seconds()),
		})
		return
	}

	// Rate limiting check on Email
	if locked, remaining := a.limiter.IsLocked(req.Email); locked {
		writeJSON(w, http.StatusTooManyRequests, map[string]string{
			"error": fmt.Sprintf("too many attempts for this email. Please try again in %.0f seconds.", remaining.Seconds()),
		})
		return
	}

	ctx := r.Context()

	// Validate OTP against MongoDB via store.VerifyOTP
	if err := a.store.VerifyOTP(ctx, req.Email, req.OTP); err != nil {
		a.limiter.RecordFailure(clientIP)
		a.limiter.RecordFailure(req.Email)
		writeJSON(w, http.StatusUnauthorized, map[string]string{
			"error": "invalid or expired OTP code",
		})
		return
	}

	// Reset limiter on successful OTP verification
	a.limiter.Reset(clientIP)
	a.limiter.Reset(req.Email)

	user := a.store.GetByEmail(ctx, req.Email)
	if user == nil {
		writeJSON(w, http.StatusNotFound, map[string]string{
			"error": "user not found",
		})
		return
	}

	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.NewPassword), bcrypt.DefaultCost)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{
			"error": "failed to hash password: " + err.Error(),
		})
		return
	}

	// Update password and ensure OTP fields are cleared so OTP cannot be reused
	update := bson.M{
		"$set": bson.M{
			"password":       string(hashedPassword),
			"otp_code":       "",
			"otp_verified":   false,
			"otp_expires_at": time.Time{},
		},
	}

	if err := a.store.UpdateUser(ctx, user.ID, update); err != nil {
		log.Printf("[AUTH] Failed to update user password for user %s: %v", user.ID, err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{
			"error": "failed to update password",
		})
		return
	}

	if err := jwtutil.RevokeAllUserTokens(user.ID); err != nil {
		log.Printf("[SECURITY WARNING] Failed to revoke user tokens after password reset for user_id=%s: %v", user.ID, err)
	}

	log.Printf("[AUTH] Password reset successfully for email=%s user_id=%s", user.Email, user.ID)

	writeJSON(w, http.StatusOK, map[string]any{
		"status":  "success",
		"message": "password reset successfully",
	})
}

// GET /auth/user/public-profile?id=<target_id>&requester_id=<token>
// GetPublicProfile returns only non-sensitive, public profile fields (ID and username).
// Note: This endpoint is consciously designed to allow any authenticated user to lookup
// another user's username by ID (acting as a public display name), while strictly
// excluding sensitive user attributes (kyc_status, role, tenant_id, email) to prevent
// information disclosure.
func (a *Auth) GetPublicProfile(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{
			"error": "method not allowed, use GET",
		})
		return
	}

	id := r.URL.Query().Get("user_token")
	if id == "" {
		id = r.URL.Query().Get("id")
	}
	if id == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "id parameter is required",
		})
		return
	}

	requesterID := r.URL.Query().Get("requester_token")
	if requesterID == "" {
		requesterID = r.URL.Query().Get("requester_id")
	}
	if requesterID == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{
			"error": "requester_id parameter is required",
		})
		return
	}

	// Validate requester token signature
	_, err := jwtutil.ValidateToken(requesterID)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{
			"error": "invalid requester token: " + err.Error(),
		})
		return
	}

	ctx := r.Context()
	user := a.store.GetByID(ctx, id)
	if user == nil {
		writeJSON(w, http.StatusNotFound, map[string]string{
			"error": "user not found",
		})
		return
	}

	// Return ONLY public, non-sensitive profile information
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"id":       user.ID,
		"username": user.Username,
	})
}

// EmployeeResponse represents an employee item returned by GetEmployees.
type EmployeeResponse struct {
	ID        string    `json:"id"`
	Username  string    `json:"username"`
	Email     string    `json:"email"`
	IsActive  bool      `json:"is_active"`
	CreatedAt time.Time `json:"created_at"`
}

// GetEmployees returns all employees registered under the caller's tenant owner account.
//
// GET /auth/employees
func (a *Auth) GetEmployees(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "use GET"})
		return
	}

	tokenStr := ""
	authHeader := r.Header.Get("Authorization")
	if strings.HasPrefix(authHeader, "Bearer ") {
		tokenStr = strings.TrimPrefix(authHeader, "Bearer ")
	} else {
		tokenStr = r.URL.Query().Get("owner_token")
	}
	if tokenStr == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "authorization token required"})
		return
	}

	claims, err := jwtutil.ValidateToken(tokenStr)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": err.Error()})
		return
	}

	ctx := r.Context()
	owner := a.store.GetByID(ctx, claims.UserID)
	if owner == nil || owner.Role != models.RoleOwner {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "access denied: owner role required"})
		return
	}

	if limited, remaining := a.limiter.CheckAndRecord(owner.ID); limited {
		writeJSON(w, http.StatusTooManyRequests, map[string]string{
			"error": fmt.Sprintf("too many requests for this account. Please try again in %.0f seconds.", remaining.Seconds()),
		})
		return
	}

	employees := a.store.GetEmployeesByOwner(ctx, owner.ID)

	res := make([]EmployeeResponse, 0, len(employees))
	for _, emp := range employees {
		if emp == nil {
			continue
		}
		res = append(res, EmployeeResponse{
			ID:        emp.ID,
			Username:  emp.Username,
			Email:     emp.Email,
			IsActive:  emp.IsActive,
			CreatedAt: emp.CreatedAt,
		})
	}

	writeJSON(w, http.StatusOK, res)
}

// ---------------------------------------------------------------------------
// POST /auth/device-token & DELETE /auth/device-token
// ---------------------------------------------------------------------------

// DeviceToken handles registration, update, and removal of client device tokens.
//
// Accepts:
// POST: { "token": "...", "platform": "android|ios|web", "action": "register|unregister"? }
// DELETE: { "token": "..." } or ?token=...
func (a *Auth) DeviceToken(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost && r.Method != http.MethodDelete {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{
			"error": "use POST or DELETE",
		})
		return
	}

	claims, err := a.authenticateUser(r)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{
			"error": "unauthorized: " + err.Error(),
		})
		return
	}

	ctx := r.Context()

	if r.Method == http.MethodDelete {
		var req models.DeviceTokenRequest
		if r.Body != nil {
			_ = json.NewDecoder(r.Body).Decode(&req)
		}
		if req.Token == "" {
			req.Token = r.URL.Query().Get("token")
		}

		if err := a.store.RemoveDeviceToken(ctx, claims.UserID, req.Token); err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{
				"error": "failed to unregister device token: " + err.Error(),
			})
			return
		}
		writeJSON(w, http.StatusOK, map[string]string{
			"message": "device token unregistered successfully",
		})
		return
	}

	// POST method
	var req models.DeviceTokenRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "invalid request body",
		})
		return
	}

	// Platform whitelist: only known client platforms may be recorded.
	// (Empty keeps the store's legacy "android" default.)
	switch req.Platform {
	case "", "android", "ios", "web":
	default:
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "invalid platform: must be one of android, ios, web",
		})
		return
	}

	if req.Action == "unregister" || req.Token == "" {
		if err := a.store.RemoveDeviceToken(ctx, claims.UserID, req.Token); err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{
				"error": "failed to unregister device token: " + err.Error(),
			})
			return
		}
		writeJSON(w, http.StatusOK, map[string]string{
			"message": "device token unregistered successfully",
		})
		return
	}

	// Upsert token
	if err := a.store.UpsertDeviceToken(ctx, claims.UserID, req.Token, req.Platform); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{
			"error": "failed to register device token: " + err.Error(),
		})
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{
		"message": "device token registered successfully",
	})
}

// ---------------------------------------------------------------------------
// POST /auth/email-change/request
// ---------------------------------------------------------------------------

// RequestEmailChange accepts a new email address, validates its format and availability,
// and sends an OTP verification code to the new email address.
func (a *Auth) RequestEmailChange(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{
			"error": "method not allowed, use POST",
		})
		return
	}

	claims, err := a.authenticateUser(r)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{
			"error": "unauthorized: " + err.Error(),
		})
		return
	}

	ctx := r.Context()
	user := a.store.GetByID(ctx, claims.UserID)
	if user == nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{
			"error": "user not found",
		})
		return
	}

	var req models.EmailChangeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "invalid JSON body: " + err.Error(),
		})
		return
	}

	newEmail := strings.ToLower(strings.TrimSpace(req.NewEmail))
	if newEmail == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "new_email is required",
		})
		return
	}

	if !strings.Contains(newEmail, "@") || !strings.Contains(newEmail, ".") {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "invalid email format",
		})
		return
	}

	if strings.EqualFold(user.Email, newEmail) {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "new_email must be different from current email",
		})
		return
	}

	// Check if new_email is already registered to another account
	existing := a.store.GetByEmail(ctx, newEmail)
	if existing != nil && existing.ID != user.ID {
		writeJSON(w, http.StatusConflict, map[string]string{
			"error": "email is already registered to another account",
		})
		return
	}

	clientIP := a.getClientIP(r)

	// Rate limiting checks
	if locked, remaining := a.limiter.IsLocked(clientIP); locked {
		writeJSON(w, http.StatusTooManyRequests, map[string]string{
			"error": fmt.Sprintf("too many attempts from this IP. Please try again in %.0f seconds.", remaining.Seconds()),
		})
		return
	}

	if locked, remaining := a.limiter.IsLocked(user.ID); locked {
		writeJSON(w, http.StatusTooManyRequests, map[string]string{
			"error": fmt.Sprintf("too many attempts for this user. Please try again in %.0f seconds.", remaining.Seconds()),
		})
		return
	}

	otpCode := generate6DigitOTP()

	pending := &models.PendingEmailChange{
		UserID:   user.ID,
		OldEmail: user.Email,
		NewEmail: newEmail,
	}

	if err := a.store.SetPendingEmailChange(ctx, user.ID, pending, otpCode); err != nil {
		log.Printf("[AUTH] Failed to store pending email change for %s: %v", user.ID, err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{
			"error": "failed to initiate email change request",
		})
		return
	}

	if err := a.dispatcher.Dispatch(newEmail, otpCode); err != nil {
		log.Printf("[AUTH] Email change OTP dispatch error for %s via %s: %v", newEmail, a.dispatcher.Name(), err)
	}

	resp := map[string]any{
		"status":  "success",
		"message": "Verification OTP sent to new email address.",
	}

	if a.isLocal {
		log.Printf("[AUTH] Email change OTP generated: new_email=%s code=%s dispatcher=%s",
			newEmail, otpCode, a.dispatcher.Name())
		resp["dev_otp"] = otpCode
	} else {
		log.Printf("[AUTH] Email change OTP generated: new_email=%s dispatcher=%s",
			newEmail, a.dispatcher.Name())
	}

	writeJSON(w, http.StatusOK, resp)
}

// ---------------------------------------------------------------------------
// POST /auth/email-change/confirm
// ---------------------------------------------------------------------------

// ConfirmEmailChange verifies the OTP sent to the new email address, updates the user's
// email address in MongoDB, deletes the pending change record, and returns an updated user
// object and fresh JWT token.
func (a *Auth) ConfirmEmailChange(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{
			"error": "method not allowed, use POST",
		})
		return
	}

	claims, err := a.authenticateUser(r)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{
			"error": "unauthorized: " + err.Error(),
		})
		return
	}

	ctx := r.Context()
	user := a.store.GetByID(ctx, claims.UserID)
	if user == nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{
			"error": "user not found",
		})
		return
	}

	var req models.EmailChangeConfirmRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "invalid JSON body: " + err.Error(),
		})
		return
	}

	if strings.TrimSpace(req.OTP) == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "otp is required",
		})
		return
	}

	clientIP := a.getClientIP(r)

	// Rate limiting checks
	if locked, remaining := a.limiter.IsLocked(clientIP); locked {
		writeJSON(w, http.StatusTooManyRequests, map[string]string{
			"error": fmt.Sprintf("too many attempts from this IP. Please try again in %.0f seconds.", remaining.Seconds()),
		})
		return
	}

	if locked, remaining := a.limiter.IsLocked(user.ID); locked {
		writeJSON(w, http.StatusTooManyRequests, map[string]string{
			"error": fmt.Sprintf("too many attempts for this user. Please try again in %.0f seconds.", remaining.Seconds()),
		})
		return
	}

	pending, err := a.store.GetAndConsumePendingEmailChange(ctx, user.ID, req.OTP)
	if err != nil {
		a.limiter.RecordFailure(clientIP)
		a.limiter.RecordFailure(user.ID)
		writeJSON(w, http.StatusUnauthorized, map[string]string{
			"error": "invalid or expired OTP code",
		})
		return
	}

	// Re-verify that new_email has not been registered in the interim
	existing := a.store.GetByEmail(ctx, pending.NewEmail)
	if existing != nil && existing.ID != user.ID {
		writeJSON(w, http.StatusConflict, map[string]string{
			"error": "email is already registered to another account",
		})
		return
	}

	a.limiter.Reset(clientIP)
	a.limiter.Reset(user.ID)

	if err := a.store.UpdateEmail(ctx, user.ID, pending.NewEmail); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{
			"error": "failed to update email address: " + err.Error(),
		})
		return
	}

	updatedUser := a.store.GetByID(ctx, user.ID)
	token, err := jwtutil.GenerateToken(updatedUser.ID, string(updatedUser.Role), updatedUser.TenantID, updatedUser.Email)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{
			"error": "failed to generate updated token: " + err.Error(),
		})
		return
	}

	log.Printf("[AUTH] Email successfully changed for user_id=%s from=%s to=%s", user.ID, pending.OldEmail, pending.NewEmail)

	writeJSON(w, http.StatusOK, map[string]any{
		"status":  "success",
		"message": "Email updated successfully",
		"token":   token,
		"user":    updatedUser,
	})
}
