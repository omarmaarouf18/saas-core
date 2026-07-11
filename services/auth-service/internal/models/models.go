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
	KYCRejected        KYCStatus = "rejected"
	KYCNone            KYCStatus = ""
)

// User represents a registered user in the platform.
type User struct {
	ID               string    `json:"id"                        bson:"_id"`
	Email            string    `json:"email"                     bson:"email"`
	Phone            string    `json:"phone,omitempty"           bson:"phone,omitempty"`
	Password         string    `json:"-"                         bson:"password"`
	Role             Role      `json:"role"                      bson:"role"`
	TenantID         string    `json:"tenant_id,omitempty"       bson:"tenant_id,omitempty"` // the tenant this user belongs to
	OwnerID          string    `json:"owner_id,omitempty"        bson:"owner_id,omitempty"`  // KYE: tenant binding (employees only)
	IsActive         bool      `json:"is_active"                 bson:"is_active"`           // KYE: owner can freeze employee accounts
	IsConfirmed      bool      `json:"is_confirmed"              bson:"is_confirmed"`
	KYCStatus        KYCStatus `json:"kyc_status,omitempty"      bson:"kyc_status,omitempty"` // KYB status for owners
	KYEStatus        KYCStatus `json:"kye_status,omitempty"      bson:"kye_status,omitempty"` // KYE status for employees
	IDFrontDoc       string    `json:"id_front_doc,omitempty"       bson:"id_front_doc,omitempty"`
	IDBackDoc        string    `json:"id_back_doc,omitempty"        bson:"id_back_doc,omitempty"`
	SelfieDoc        string    `json:"selfie_doc,omitempty"         bson:"selfie_doc,omitempty"`
	BusinessProofDoc string    `json:"business_proof_doc,omitempty" bson:"business_proof_doc,omitempty"`
	ReviewerID       string    `json:"reviewer_id,omitempty"        bson:"reviewer_id,omitempty"`
	ReviewedAt       time.Time `json:"reviewed_at,omitempty"        bson:"reviewed_at,omitempty"`
	RejectionReason  string    `json:"rejection_reason,omitempty"   bson:"rejection_reason,omitempty"`
	OTPCode          string    `json:"-"                         bson:"otp_code,omitempty"`
	OTPExpiresAt     time.Time `json:"-"                         bson:"otp_expires_at,omitempty"`
	OTPVerified      bool      `json:"otp_verified"              bson:"otp_verified"`
	CreatedAt        time.Time `json:"created_at"                bson:"created_at"`
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
	OwnerPassword string `json:"owner_password"`
	SetActive     bool   `json:"set_active"`
}

// AuditEntry records a single employee action for the Action Server log.
type AuditEntry struct {
	ID         string    `json:"id"          bson:"_id,omitempty"`
	EmployeeID string    `json:"employee_id" bson:"employee_id"`
	TenantID   string    `json:"tenant_id"   bson:"tenant_id"` // the OwnerID this employee belongs to
	Action     string    `json:"action"      bson:"action"`
	Timestamp  time.Time `json:"timestamp"   bson:"timestamp"`
	ClientIP   string    `json:"client_ip"   bson:"client_ip"`
}
