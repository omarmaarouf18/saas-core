// Package store provides a MongoDB-backed persistent data store for the auth-service.
// Replaces the previous in-memory implementation with production-grade database persistence.
package store

import (
	"context"
	"fmt"
	"log"
	"time"

	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
	"go.mongodb.org/mongo-driver/v2/mongo/options"

	"github.com/project/auth-service/internal/models"
	"github.com/project/auth-service/internal/otpcrypto"
)

// MongoDB is a persistent store backed by MongoDB for user registration states
// and the employee action audit log.
type MongoDB struct {
	client   *mongo.Client
	db       *mongo.Database
	users    *mongo.Collection
	auditLog *mongo.Collection
	cipher   *otpcrypto.Cipher // AES-256-GCM for OTP encryption at rest
}

// NewMongoDB connects to the given MongoDB URI, creates the database and
// collections, ensures all required indexes exist, and initializes the
// AES-256-GCM cipher for OTP encryption at rest.
func NewMongoDB(ctx context.Context, uri, dbName string, otpCipher *otpcrypto.Cipher) (*MongoDB, error) {
	client, err := mongo.Connect(options.Client().ApplyURI(uri))
	if err != nil {
		return nil, fmt.Errorf("store: failed to connect to MongoDB: %w", err)
	}

	// Verify connectivity.
	pingCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	if err := client.Ping(pingCtx, nil); err != nil {
		return nil, fmt.Errorf("store: MongoDB ping failed: %w", err)
	}

	db := client.Database(dbName)
	s := &MongoDB{
		client:   client,
		db:       db,
		users:    db.Collection("users"),
		auditLog: db.Collection("audit_log"),
		cipher:   otpCipher,
	}

	if err := s.ensureIndexes(ctx); err != nil {
		return nil, fmt.Errorf("store: failed to create indexes: %w", err)
	}

	log.Printf("[AUTH-STORE] Connected to MongoDB: %s/%s (OTP encryption: AES-256-GCM)", uri, dbName)
	return s, nil
}

// Close disconnects the MongoDB client.
func (s *MongoDB) Close(ctx context.Context) error {
	return s.client.Disconnect(ctx)
}

// ensureIndexes creates unique and query-optimized indexes on all collections.
func (s *MongoDB) ensureIndexes(ctx context.Context) error {
	// Users: unique email index.
	_, err := s.users.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys:    bson.D{{Key: "email", Value: 1}},
		Options: options.Index().SetUnique(true),
	})
	if err != nil {
		return fmt.Errorf("users email index: %w", err)
	}

	// Users: owner_id index for employee lookups.
	_, err = s.users.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{{Key: "owner_id", Value: 1}},
	})
	if err != nil {
		return fmt.Errorf("users owner_id index: %w", err)
	}

	// Users: role index.
	_, err = s.users.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{{Key: "role", Value: 1}},
	})
	if err != nil {
		return fmt.Errorf("users role index: %w", err)
	}

	// Users: tenant_id index.
	_, err = s.users.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{{Key: "tenant_id", Value: 1}},
	})
	if err != nil {
		return fmt.Errorf("users tenant_id index: %w", err)
	}

	// Users: phone sparse unique index (only users with phone set).
	_, err = s.users.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys:    bson.D{{Key: "phone", Value: 1}},
		Options: options.Index().SetUnique(true).SetSparse(true),
	})
	if err != nil {
		return fmt.Errorf("users phone index: %w", err)
	}

	// Audit log: tenant_id index for filtered queries.
	_, err = s.auditLog.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{{Key: "tenant_id", Value: 1}},
	})
	if err != nil {
		return fmt.Errorf("audit_log tenant_id index: %w", err)
	}

	// Audit log: timestamp index for chronological ordering.
	_, err = s.auditLog.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{{Key: "timestamp", Value: -1}},
	})
	if err != nil {
		return fmt.Errorf("audit_log timestamp index: %w", err)
	}

	log.Println("[AUTH-STORE] All indexes ensured")
	return nil
}

// ---------------------------------------------------------------------------
// User CRUD
// ---------------------------------------------------------------------------

// CreateUser stores a new user. Returns an error if the email already exists
// (enforced by the unique index on email).
func (s *MongoDB) CreateUser(ctx context.Context, user *models.User) error {
	_, err := s.users.InsertOne(ctx, user)
	if err != nil {
		if mongo.IsDuplicateKeyError(err) {
			return fmt.Errorf("user with email %q already exists", user.Email)
		}
		return fmt.Errorf("store: insert user: %w", err)
	}
	return nil
}

// GetByEmail retrieves a user by email. Returns nil if not found.
func (s *MongoDB) GetByEmail(ctx context.Context, email string) *models.User {
	var user models.User
	err := s.users.FindOne(ctx, bson.M{"email": email}).Decode(&user)
	if err != nil {
		return nil
	}
	return &user
}

// GetByID retrieves a user by ID (_id). Returns nil if not found.
func (s *MongoDB) GetByID(ctx context.Context, id string) *models.User {
	var user models.User
	err := s.users.FindOne(ctx, bson.M{"_id": id}).Decode(&user)
	if err != nil {
		return nil
	}
	return &user
}

// ---------------------------------------------------------------------------
// OTP operations — AES-256-GCM encrypted at rest
// ---------------------------------------------------------------------------

// SetOTP encrypts the OTP code via AES-256-GCM and stores the ciphertext
// in MongoDB. The plaintext OTP never touches the database.
func (s *MongoDB) SetOTP(ctx context.Context, email, otp string) error {
	encrypted, err := s.cipher.Encrypt(otp)
	if err != nil {
		return fmt.Errorf("store: OTP encryption failed: %w", err)
	}

	result, err := s.users.UpdateOne(ctx,
		bson.M{"email": email},
		bson.M{"$set": bson.M{"otp_code": encrypted, "otp_verified": false}},
	)
	if err != nil {
		return fmt.Errorf("store: set OTP: %w", err)
	}
	if result.MatchedCount == 0 {
		return fmt.Errorf("user %q not found", email)
	}
	return nil
}

// VerifyOTP decrypts the stored OTP ciphertext and compares it against
// the plaintext code submitted by the user. This ensures the /verify
// endpoint functions identically to the production flow.
func (s *MongoDB) VerifyOTP(ctx context.Context, email, otp string) error {
	// Fetch the user to get the encrypted OTP.
	user := s.GetByEmail(ctx, email)
	if user == nil {
		return fmt.Errorf("user %q not found", email)
	}
	if user.OTPCode == "" {
		return fmt.Errorf("no OTP pending for %q", email)
	}

	// Decrypt the stored OTP and compare against the submitted plaintext.
	decrypted, err := s.cipher.Decrypt(user.OTPCode)
	if err != nil {
		return fmt.Errorf("store: OTP decryption failed: %w", err)
	}
	if decrypted != otp {
		return fmt.Errorf("invalid OTP")
	}

	// Mark as verified and clear the encrypted code atomically.
	_, err = s.users.UpdateOne(ctx,
		bson.M{"email": email},
		bson.M{"$set": bson.M{"otp_verified": true, "otp_code": ""}},
	)
	if err != nil {
		return fmt.Errorf("store: verify OTP: %w", err)
	}
	return nil
}

// ---------------------------------------------------------------------------
// KYE (Know Your Employee) operations
// ---------------------------------------------------------------------------

// GetEmployeesByOwner returns all employees bound to the given owner ID.
func (s *MongoDB) GetEmployeesByOwner(ctx context.Context, ownerID string) []*models.User {
	cursor, err := s.users.Find(ctx, bson.M{
		"role":     models.RoleEmployee,
		"owner_id": ownerID,
	})
	if err != nil {
		log.Printf("[AUTH-STORE] GetEmployeesByOwner error: %v", err)
		return nil
	}
	defer cursor.Close(ctx)

	var employees []*models.User
	if err := cursor.All(ctx, &employees); err != nil {
		log.Printf("[AUTH-STORE] GetEmployeesByOwner decode error: %v", err)
		return nil
	}
	return employees
}

// ToggleEmployeeActive sets the IsActive status for an employee.
// Only the employee's bound owner (verified by ownerID) can perform this.
func (s *MongoDB) ToggleEmployeeActive(ctx context.Context, employeeEmail, ownerID string, active bool) error {
	result, err := s.users.UpdateOne(ctx,
		bson.M{
			"email":    employeeEmail,
			"role":     models.RoleEmployee,
			"owner_id": ownerID,
		},
		bson.M{"$set": bson.M{"is_active": active}},
	)
	if err != nil {
		return fmt.Errorf("store: toggle employee: %w", err)
	}
	if result.MatchedCount == 0 {
		// Determine the specific error.
		user := s.GetByEmail(ctx, employeeEmail)
		if user == nil {
			return fmt.Errorf("employee %q not found", employeeEmail)
		}
		if user.Role != models.RoleEmployee {
			return fmt.Errorf("user %q is not an employee", employeeEmail)
		}
		return fmt.Errorf("owner mismatch: employee %q does not belong to owner %q", employeeEmail, ownerID)
	}
	return nil
}

// ---------------------------------------------------------------------------
// Audit Log (Action Server)
// ---------------------------------------------------------------------------

// AppendAudit records an employee action in the audit log.
func (s *MongoDB) AppendAudit(ctx context.Context, entry models.AuditEntry) {
	if entry.Timestamp.IsZero() {
		entry.Timestamp = time.Now().UTC()
	}
	if entry.ID == "" {
		entry.ID = fmt.Sprintf("audit-%d", time.Now().UnixNano())
	}

	_, err := s.auditLog.InsertOne(ctx, entry)
	if err != nil {
		log.Printf("[AUTH-STORE] Failed to insert audit entry: %v", err)
	}
}

// GetAuditLog returns audit entries, optionally filtered by tenant (owner) ID.
// If tenantID is empty, all entries are returned.
func (s *MongoDB) GetAuditLog(ctx context.Context, tenantID string) []models.AuditEntry {
	filter := bson.M{}
	if tenantID != "" {
		filter["tenant_id"] = tenantID
	}

	opts := options.Find().SetSort(bson.D{{Key: "timestamp", Value: -1}})
	cursor, err := s.auditLog.Find(ctx, filter, opts)
	if err != nil {
		log.Printf("[AUTH-STORE] GetAuditLog error: %v", err)
		return nil
	}
	defer cursor.Close(ctx)

	var entries []models.AuditEntry
	if err := cursor.All(ctx, &entries); err != nil {
		log.Printf("[AUTH-STORE] GetAuditLog decode error: %v", err)
		return nil
	}
	return entries
}

// AuditCount returns the total number of audit entries.
func (s *MongoDB) AuditCount(ctx context.Context) int {
	count, err := s.auditLog.CountDocuments(ctx, bson.M{})
	if err != nil {
		log.Printf("[AUTH-STORE] AuditCount error: %v", err)
		return 0
	}
	return int(count)
}
