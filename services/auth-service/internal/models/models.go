// Package models defines data types for the auth-service.
package models

import "time"

// Role represents the authorization level of a user in the platform.
type Role string

const (
	RoleOwner    Role = "owner"
	RoleUser     Role = "user"
	RoleEmployee Role = "employee"
)

// ValidRoles returns true if the given role string is a known role.
func ValidRole(r Role) bool {
	switch r {
	case RoleOwner, RoleUser, RoleEmployee:
		return true
	}
	return false
}

// KYCStatus represents the Know-Your-Customer verification state for owners.
type KYCStatus string

const (
	KYCPendingApproval KYCStatus = "pending_super_admin_approval"
	KYCApproved        KYCStatus = "approved"
	KYCNone            KYCStatus = ""
)

// User represents a registered user in the platform.
type User struct {
	ID          string    `json:"id"`
	Email       string    `json:"email"`
	Password    string    `json:"-"`
	Role        Role      `json:"role"`
	OwnerID     string    `json:"owner_id,omitempty"`    // KYE: tenant binding (employees only)
	IsActive    bool      `json:"is_active"`             // KYE: owner can freeze employee accounts
	KYCStatus   KYCStatus `json:"kyc_status,omitempty"`
	AntiSpam    string    `json:"anti_spam_token,omitempty"`
	OTPCode     string    `json:"-"`
	OTPVerified bool      `json:"otp_verified"`
	CreatedAt   time.Time `json:"created_at"`
}

// SignupRequest is the expected JSON body for POST /auth/signup.
type SignupRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
	Role     Role   `json:"role"`
	OwnerID  string `json:"owner_id,omitempty"` // required for employees (KYE binding)
}

// LoginRequest is the expected JSON body for POST /auth/login.
type LoginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

// VerifyOTPRequest is the expected JSON body for POST /auth/verify-otp.
type VerifyOTPRequest struct {
	Email string `json:"email"`
	OTP   string `json:"otp"`
}

// LoginResponse is returned on successful credential validation.
type LoginResponse struct {
	Message     string `json:"message"`
	UserID      string `json:"user_id"`
	Role        Role   `json:"role"`
	Requires2FA bool   `json:"requires_2fa"`
	OTPHint     string `json:"otp_hint,omitempty"`
}

// ToggleEmployeeRequest is used by owners to freeze/activate employees.
type ToggleEmployeeRequest struct {
	EmployeeEmail string `json:"employee_email"`
	OwnerEmail    string `json:"owner_email"`
	SetActive     bool   `json:"set_active"`
}

// AuditEntry records a single employee action for the Action Server log.
type AuditEntry struct {
	EmployeeID string    `json:"employee_id"`
	TenantID   string    `json:"tenant_id"` // the OwnerID this employee belongs to
	Action     string    `json:"action"`
	Timestamp  time.Time `json:"timestamp"`
	ClientIP   string    `json:"client_ip"`
}
