// Package store provides an in-memory data store for development/testing.
// This replaces persistent DB calls until schemas are finalized.
package store

import (
	"fmt"
	"sync"
	"time"

	"github.com/project/auth-service/internal/models"
)

// Memory is a thread-safe in-memory store for user registration states
// and the employee action audit log.
type Memory struct {
	mu       sync.RWMutex
	users    map[string]*models.User   // keyed by email
	auditLog []models.AuditEntry       // append-only action log
}

// NewMemory creates an empty in-memory store.
func NewMemory() *Memory {
	return &Memory{
		users: make(map[string]*models.User),
	}
}

// ---------------------------------------------------------------------------
// User CRUD
// ---------------------------------------------------------------------------

// CreateUser stores a new user. Returns an error if the email already exists.
func (m *Memory) CreateUser(user *models.User) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	if _, exists := m.users[user.Email]; exists {
		return fmt.Errorf("user with email %q already exists", user.Email)
	}
	m.users[user.Email] = user
	return nil
}

// GetByEmail retrieves a user by email. Returns nil if not found.
func (m *Memory) GetByEmail(email string) *models.User {
	m.mu.RLock()
	defer m.mu.RUnlock()

	return m.users[email]
}

// GetByID retrieves a user by ID. Returns nil if not found.
func (m *Memory) GetByID(id string) *models.User {
	m.mu.RLock()
	defer m.mu.RUnlock()

	for _, u := range m.users {
		if u.ID == id {
			return u
		}
	}
	return nil
}

// ---------------------------------------------------------------------------
// OTP operations
// ---------------------------------------------------------------------------

// SetOTP sets the mocked OTP code for a user.
func (m *Memory) SetOTP(email, otp string) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	user, exists := m.users[email]
	if !exists {
		return fmt.Errorf("user %q not found", email)
	}
	user.OTPCode = otp
	user.OTPVerified = false
	return nil
}

// VerifyOTP checks the OTP code and marks it as verified if correct.
func (m *Memory) VerifyOTP(email, otp string) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	user, exists := m.users[email]
	if !exists {
		return fmt.Errorf("user %q not found", email)
	}
	if user.OTPCode == "" {
		return fmt.Errorf("no OTP pending for %q", email)
	}
	if user.OTPCode != otp {
		return fmt.Errorf("invalid OTP")
	}
	user.OTPVerified = true
	user.OTPCode = "" // consumed
	return nil
}

// ---------------------------------------------------------------------------
// KYE (Know Your Employee) operations
// ---------------------------------------------------------------------------

// GetEmployeesByOwner returns all employees bound to the given owner ID.
func (m *Memory) GetEmployeesByOwner(ownerID string) []*models.User {
	m.mu.RLock()
	defer m.mu.RUnlock()

	var employees []*models.User
	for _, u := range m.users {
		if u.Role == models.RoleEmployee && u.OwnerID == ownerID {
			employees = append(employees, u)
		}
	}
	return employees
}

// ToggleEmployeeActive sets the IsActive status for an employee.
// Only the employee's bound owner (verified by ownerID) can perform this.
func (m *Memory) ToggleEmployeeActive(employeeEmail, ownerID string, active bool) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	user, exists := m.users[employeeEmail]
	if !exists {
		return fmt.Errorf("employee %q not found", employeeEmail)
	}
	if user.Role != models.RoleEmployee {
		return fmt.Errorf("user %q is not an employee", employeeEmail)
	}
	if user.OwnerID != ownerID {
		return fmt.Errorf("owner mismatch: employee %q does not belong to owner %q", employeeEmail, ownerID)
	}
	user.IsActive = active
	return nil
}

// ---------------------------------------------------------------------------
// Audit Log (Action Server)
// ---------------------------------------------------------------------------

// AppendAudit records an employee action in the audit log.
func (m *Memory) AppendAudit(entry models.AuditEntry) {
	m.mu.Lock()
	defer m.mu.Unlock()

	if entry.Timestamp.IsZero() {
		entry.Timestamp = time.Now().UTC()
	}
	m.auditLog = append(m.auditLog, entry)
}

// GetAuditLog returns audit entries, optionally filtered by tenant (owner) ID.
// If tenantID is empty, all entries are returned.
func (m *Memory) GetAuditLog(tenantID string) []models.AuditEntry {
	m.mu.RLock()
	defer m.mu.RUnlock()

	if tenantID == "" {
		result := make([]models.AuditEntry, len(m.auditLog))
		copy(result, m.auditLog)
		return result
	}

	var filtered []models.AuditEntry
	for _, e := range m.auditLog {
		if e.TenantID == tenantID {
			filtered = append(filtered, e)
		}
	}
	return filtered
}

// AuditCount returns the total number of audit entries.
func (m *Memory) AuditCount() int {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return len(m.auditLog)
}
