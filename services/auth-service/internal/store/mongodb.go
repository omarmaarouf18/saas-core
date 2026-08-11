// Package store provides a MongoDB-backed persistent data store for the auth-service.
// Replaces the previous in-memory implementation with production-grade database persistence.
package store

import (
	"context"
	"crypto/subtle"
	"fmt"
	"log"
	"strings"
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
	client              *mongo.Client
	db                  *mongo.Database
	users               *mongo.Collection
	auditLog            *mongo.Collection
	reviewers           *mongo.Collection
	pendingSignups      *mongo.Collection
	pendingEmailChanges *mongo.Collection
	cipher              *otpcrypto.Cipher // AES-256-GCM for OTP encryption at rest
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
		client:              client,
		db:                  db,
		users:               db.Collection("users"),
		auditLog:            db.Collection("audit_log"),
		reviewers:           db.Collection("reviewers"),
		pendingSignups:      db.Collection("pending_signups"),
		pendingEmailChanges: db.Collection("pending_email_changes"),
		cipher:              otpCipher,
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

// DropDatabase drops the associated database (primarily for integration tests).
func (s *MongoDB) DropDatabase(ctx context.Context) error {
	return s.db.Drop(ctx)
}

// DatabaseForTesting returns the internal database instance for test setup.
func (s *MongoDB) DatabaseForTesting() *mongo.Database {
	return s.db
}

// UpdateKYCStatus updates a user's KYC status (primarily for integration tests).
func (s *MongoDB) UpdateKYCStatus(ctx context.Context, userID string, status models.KYCStatus) error {
	_, err := s.users.UpdateOne(ctx, bson.M{"_id": userID}, bson.M{"$set": bson.M{"kyc_status": status}})
	return err
}

// UpdateUser applies an update query directly to the user record.
func (s *MongoDB) UpdateUser(ctx context.Context, userID string, update bson.M) error {
	_, err := s.users.UpdateOne(ctx, bson.M{"_id": userID}, update)
	return err
}

// UpdateUserConditional performs an UpdateOne matching both _id and statusField equal to expectedStatus.
// Returns (true, nil) if a document was matched and updated, (false, nil) if MatchedCount == 0 (race condition / status changed),
// or (false, err) on database error.
func (s *MongoDB) UpdateUserConditional(ctx context.Context, userID string, statusField string, expectedStatus models.KYCStatus, update bson.M) (bool, error) {
	filter := bson.M{
		"_id":       userID,
		statusField: expectedStatus,
	}
	res, err := s.users.UpdateOne(ctx, filter, update)
	if err != nil {
		return false, err
	}
	return res.MatchedCount > 0, nil
}

// GetPendingKYBKYE returns all users with pending KYB or KYE approval status.
func (s *MongoDB) GetPendingKYBKYE(ctx context.Context) ([]*models.User, error) {
	filter := bson.M{
		"$or": []bson.M{
			{"kyc_status": models.KYCPendingApproval},
			{"kye_status": models.KYCPendingApproval},
		},
	}
	cursor, err := s.users.Find(ctx, filter)
	if err != nil {
		return nil, err
	}
	var results []*models.User
	if err := cursor.All(ctx, &results); err != nil {
		return nil, err
	}
	return results, nil
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

	// Pending email changes: unique user_id index.
	_, err = s.pendingEmailChanges.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys:    bson.D{{Key: "user_id", Value: 1}},
		Options: options.Index().SetUnique(true),
	})
	if err != nil {
		return fmt.Errorf("pending email changes user_id index: %w", err)
	}

	// Check for case-insensitive duplicate usernames before creating unique index
	dupPipeline := mongo.Pipeline{
		{{Key: "$group", Value: bson.D{
			{Key: "_id", Value: bson.D{{Key: "$toLower", Value: "$username"}}},
			{Key: "count", Value: bson.D{{Key: "$sum", Value: 1}}},
			{Key: "usernames", Value: bson.D{{Key: "$push", Value: "$username"}}},
		}}},
		{{Key: "$match", Value: bson.D{
			{Key: "count", Value: bson.D{{Key: "$gt", Value: 1}}},
			{Key: "_id", Value: bson.D{{Key: "$ne", Value: nil}}}, // skip empty/null usernames
		}}},
	}

	cursor, err := s.users.Aggregate(ctx, dupPipeline)
	if err == nil {
		defer cursor.Close(ctx)
		var duplicates []struct {
			ID        string   `bson:"_id"`
			Count     int      `bson:"count"`
			Usernames []string `bson:"usernames"`
		}
		if err := cursor.All(ctx, &duplicates); err == nil && len(duplicates) > 0 {
			var conflicts []string
			for _, dup := range duplicates {
				conflicts = append(conflicts, fmt.Sprintf("%q (matches: %v)", dup.ID, dup.Usernames))
			}
			log.Printf("[MIGRATION ERROR] Cannot enable case-insensitive username uniqueness because duplicate usernames exist: %v. Please resolve these manually.", conflicts)
			return fmt.Errorf("case-insensitive duplicate usernames exist in database: %v", conflicts)
		}
	}

	// Drop old case-sensitive username index if it exists to prevent options conflict
	_ = s.users.Indexes().DropOne(ctx, "username_1")

	// Users: unique case-insensitive username index.
	_, err = s.users.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{{Key: "username", Value: 1}},
		Options: options.Index().SetUnique(true).SetCollation(&options.Collation{
			Locale:   "en",
			Strength: 2, // Case-insensitive
		}),
	})
	if err != nil {
		return fmt.Errorf("users username unique index: %w", err)
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

	// Reviewers: unique token index
	_, err = s.reviewers.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys:    bson.D{{Key: "token", Value: 1}},
		Options: options.Index().SetUnique(true),
	})
	if err != nil {
		return fmt.Errorf("reviewers token index: %w", err)
	}

	// Pending signups: unique email index.
	_, err = s.pendingSignups.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys:    bson.D{{Key: "email", Value: 1}},
		Options: options.Index().SetUnique(true),
	})
	if err != nil {
		return fmt.Errorf("pending_signups email index: %w", err)
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
			if strings.Contains(err.Error(), "username") {
				return fmt.Errorf("username already taken")
			}
			return fmt.Errorf("email already registered")
		}
		return fmt.Errorf("store: insert user: %w", err)
	}
	return nil
}

// DeleteUser deletes a user by ID.
func (s *MongoDB) DeleteUser(ctx context.Context, id string) error {
	_, err := s.users.DeleteOne(ctx, bson.M{"_id": id})
	if err != nil {
		return fmt.Errorf("store: delete user: %w", err)
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

// GetByUsername retrieves a user by username (case-insensitive search matching index).
func (s *MongoDB) GetByUsername(ctx context.Context, username string) *models.User {
	var user models.User
	opts := options.FindOne().SetCollation(&options.Collation{
		Locale:   "en",
		Strength: 2,
	})
	err := s.users.FindOne(ctx, bson.M{"username": username}, opts).Decode(&user)
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

	expiresAt := time.Now().Add(5 * time.Minute)

	result, err := s.users.UpdateOne(ctx,
		bson.M{"email": email},
		bson.M{"$set": bson.M{"otp_code": encrypted, "otp_verified": false, "otp_expires_at": expiresAt}},
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

	// Check if OTP has expired
	if !user.OTPExpiresAt.IsZero() && user.OTPExpiresAt.Before(time.Now()) {
		// Clear the expired code
		_, _ = s.users.UpdateOne(ctx,
			bson.M{"email": email},
			bson.M{"$set": bson.M{"otp_code": ""}},
		)
		return fmt.Errorf("OTP has expired")
	}

	// Decrypt the stored OTP and compare against the submitted plaintext.
	decrypted, err := s.cipher.Decrypt(user.OTPCode)
	if err != nil {
		return fmt.Errorf("store: OTP decryption failed: %w", err)
	}
	if subtle.ConstantTimeCompare([]byte(decrypted), []byte(otp)) != 1 {
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
// Pending Signup Operations (Pre-Confirmation Accounts)
// ---------------------------------------------------------------------------

// SetPendingSignup encrypts the OTP code via AES-256-GCM and stores the pending signup
// payload in MongoDB under the pending_signups collection. If a pending signup already
// exists for this email, it is overwritten.
func (s *MongoDB) SetPendingSignup(ctx context.Context, email string, pending *models.PendingSignup, otp string) error {
	encrypted, err := s.cipher.Encrypt(otp)
	if err != nil {
		return fmt.Errorf("store: OTP encryption failed: %w", err)
	}

	pending.Email = email
	pending.OTPCode = encrypted
	pending.OTPExpiresAt = time.Now().Add(5 * time.Minute)
	if pending.CreatedAt.IsZero() {
		pending.CreatedAt = time.Now().UTC()
	}

	opts := options.Replace().SetUpsert(true)
	_, err = s.pendingSignups.ReplaceOne(ctx, bson.M{"email": email}, pending, opts)
	if err != nil {
		return fmt.Errorf("store: set pending signup: %w", err)
	}
	return nil
}

// GetPendingSignup retrieves an unverified pending signup payload by email. Returns nil if not found.
func (s *MongoDB) GetPendingSignup(ctx context.Context, email string) *models.PendingSignup {
	var pending models.PendingSignup
	err := s.pendingSignups.FindOne(ctx, bson.M{"email": email}).Decode(&pending)
	if err != nil {
		return nil
	}
	return &pending
}

// GetAndConsumePendingSignup validates the submitted OTP against the pending signup record.
// On success, it atomically deletes the pending signup from MongoDB to prevent replay attacks,
// and returns the pending signup payload.
func (s *MongoDB) GetAndConsumePendingSignup(ctx context.Context, email, otp string) (*models.PendingSignup, error) {
	var pending models.PendingSignup
	err := s.pendingSignups.FindOne(ctx, bson.M{"email": email}).Decode(&pending)
	if err != nil {
		return nil, fmt.Errorf("pending signup for %q not found", email)
	}

	if !pending.OTPExpiresAt.IsZero() && pending.OTPExpiresAt.Before(time.Now()) {
		_, _ = s.pendingSignups.DeleteOne(ctx, bson.M{"email": email})
		return nil, fmt.Errorf("OTP has expired")
	}

	decrypted, err := s.cipher.Decrypt(pending.OTPCode)
	if err != nil {
		return nil, fmt.Errorf("store: OTP decryption failed: %w", err)
	}
	if subtle.ConstantTimeCompare([]byte(decrypted), []byte(otp)) != 1 {
		return nil, fmt.Errorf("invalid OTP")
	}

	_, err = s.pendingSignups.DeleteOne(ctx, bson.M{"email": email})
	if err != nil {
		log.Printf("[AUTH-STORE] Failed to delete consumed pending signup for %s: %v", email, err)
	}

	return &pending, nil
}

// ---------------------------------------------------------------------------
// Pending Email Change Operations
// ---------------------------------------------------------------------------

// SetPendingEmailChange encrypts the OTP code via AES-256-GCM and stores the pending email change
// payload in MongoDB under the pending_email_changes collection. If a pending request already
// exists for this userID, it is overwritten.
func (s *MongoDB) SetPendingEmailChange(ctx context.Context, userID string, pending *models.PendingEmailChange, otp string) error {
	encrypted, err := s.cipher.Encrypt(otp)
	if err != nil {
		return fmt.Errorf("store: OTP encryption failed: %w", err)
	}

	pending.UserID = userID
	pending.OTPCode = encrypted
	if pending.OTPExpiresAt.IsZero() {
		pending.OTPExpiresAt = time.Now().Add(5 * time.Minute)
	}
	if pending.CreatedAt.IsZero() {
		pending.CreatedAt = time.Now().UTC()
	}

	opts := options.Replace().SetUpsert(true)
	_, err = s.pendingEmailChanges.ReplaceOne(ctx, bson.M{"user_id": userID}, pending, opts)
	if err != nil {
		return fmt.Errorf("store: set pending email change: %w", err)
	}
	return nil
}

// GetPendingEmailChange retrieves an unverified pending email change payload by userID. Returns nil if not found.
func (s *MongoDB) GetPendingEmailChange(ctx context.Context, userID string) *models.PendingEmailChange {
	var pending models.PendingEmailChange
	err := s.pendingEmailChanges.FindOne(ctx, bson.M{"user_id": userID}).Decode(&pending)
	if err != nil {
		return nil
	}
	return &pending
}

// GetAndConsumePendingEmailChange validates the submitted OTP against the pending email change record.
// It uses an atomic FindOneAndDelete operation to retrieve and remove the record in a single
// round trip, guaranteeing single-use consumption and preventing concurrent replay races.
func (s *MongoDB) GetAndConsumePendingEmailChange(ctx context.Context, userID, otp string) (*models.PendingEmailChange, error) {
	var pending models.PendingEmailChange
	err := s.pendingEmailChanges.FindOneAndDelete(ctx, bson.M{"user_id": userID}).Decode(&pending)
	if err != nil {
		return nil, fmt.Errorf("pending email change for user %q not found", userID)
	}

	if !pending.OTPExpiresAt.IsZero() && pending.OTPExpiresAt.Before(time.Now()) {
		return nil, fmt.Errorf("OTP has expired")
	}

	decrypted, err := s.cipher.Decrypt(pending.OTPCode)
	if err != nil {
		return nil, fmt.Errorf("store: OTP decryption failed: %w", err)
	}
	if subtle.ConstantTimeCompare([]byte(decrypted), []byte(otp)) != 1 {
		return nil, fmt.Errorf("invalid OTP")
	}

	return &pending, nil
}

// UpdateEmail updates a user's email address in MongoDB.
func (s *MongoDB) UpdateEmail(ctx context.Context, userID, newEmail string) error {
	res, err := s.users.UpdateOne(ctx, bson.M{"_id": userID}, bson.M{"$set": bson.M{"email": newEmail}})
	if err != nil {
		return fmt.Errorf("store: update email: %w", err)
	}
	if res.MatchedCount == 0 {
		return fmt.Errorf("user %q not found", userID)
	}
	return nil
}

// StartOTPCleanup periodically sweeps MongoDB and invalidates expired OTPs and pending signups.
func (s *MongoDB) StartOTPCleanup(ctx context.Context, interval time.Duration) {
	ticker := time.NewTicker(interval)
	go func() {
		for range ticker.C {
			now := time.Now()
			_, err := s.users.UpdateMany(ctx,
				bson.M{
					"otp_code":       bson.M{"$ne": ""},
					"otp_expires_at": bson.M{"$lt": now},
				},
				bson.M{"$set": bson.M{"otp_code": ""}},
			)
			if err != nil {
				log.Printf("[AUTH-STORE] Failed to sweep expired OTPs: %v", err)
			}

			_, err = s.pendingSignups.DeleteMany(ctx, bson.M{
				"otp_expires_at": bson.M{"$lt": now},
			})
			if err != nil {
				log.Printf("[AUTH-STORE] Failed to sweep expired pending signups: %v", err)
			}

			_, err = s.pendingEmailChanges.DeleteMany(ctx, bson.M{
				"otp_expires_at": bson.M{"$lt": now},
			})
			if err != nil {
				log.Printf("[AUTH-STORE] Failed to sweep expired pending email changes: %v", err)
			}
		}
	}()
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

// AddReviewer saves a new reviewer to the reviewers collection.
func (s *MongoDB) AddReviewer(ctx context.Context, rev *models.Reviewer) error {
	_, err := s.reviewers.InsertOne(ctx, rev)
	if err != nil {
		if mongo.IsDuplicateKeyError(err) {
			return fmt.Errorf("reviewer with ID or token already exists: %w", err)
		}
		return err
	}
	return nil
}

// GetReviewerByID fetches a reviewer by ID.
func (s *MongoDB) GetReviewerByID(ctx context.Context, id string) (*models.Reviewer, error) {
	var rev models.Reviewer
	err := s.reviewers.FindOne(ctx, bson.M{"_id": id}).Decode(&rev)
	if err != nil {
		return nil, err
	}
	return &rev, nil
}

// GetReviewerByToken fetches a reviewer by their unique token.
func (s *MongoDB) GetReviewerByToken(ctx context.Context, token string) (*models.Reviewer, error) {
	var rev models.Reviewer
	err := s.reviewers.FindOne(ctx, bson.M{"token": token}).Decode(&rev)
	if err != nil {
		return nil, err
	}
	return &rev, nil
}

// ---------------------------------------------------------------------------
// Device Token Operations (FCM Push Notifications)
// ---------------------------------------------------------------------------

// UpsertDeviceToken adds or updates a device token on a user record without duplicates.
func (s *MongoDB) UpsertDeviceToken(ctx context.Context, userID, tokenStr, platform string) error {
	if strings.TrimSpace(tokenStr) == "" {
		return fmt.Errorf("device token cannot be empty")
	}
	if platform == "" {
		platform = "android"
	}

	// First pull any existing token with the same token string to avoid duplicate array items
	_, err := s.users.UpdateOne(ctx,
		bson.M{"_id": userID},
		bson.M{"$pull": bson.M{"device_tokens": bson.M{"token": tokenStr}}},
	)
	if err != nil {
		return fmt.Errorf("store: pull existing device token: %w", err)
	}

	// Push the fresh device token
	entry := models.DeviceToken{
		Token:     tokenStr,
		Platform:  platform,
		UpdatedAt: time.Now(),
	}
	res, err := s.users.UpdateOne(ctx,
		bson.M{"_id": userID},
		bson.M{"$push": bson.M{"device_tokens": entry}},
	)
	if err != nil {
		return fmt.Errorf("store: push device token: %w", err)
	}
	if res.MatchedCount == 0 {
		return fmt.Errorf("user %q not found", userID)
	}
	return nil
}

// RemoveDeviceToken unregisters a specific device token (or all tokens if tokenStr is empty) from a user record.
func (s *MongoDB) RemoveDeviceToken(ctx context.Context, userID, tokenStr string) error {
	var update bson.M
	if strings.TrimSpace(tokenStr) == "" {
		update = bson.M{"$set": bson.M{"device_tokens": []models.DeviceToken{}}}
	} else {
		update = bson.M{"$pull": bson.M{"device_tokens": bson.M{"token": tokenStr}}}
	}

	res, err := s.users.UpdateOne(ctx, bson.M{"_id": userID}, update)
	if err != nil {
		return fmt.Errorf("store: remove device token: %w", err)
	}
	if res.MatchedCount == 0 {
		return fmt.Errorf("user %q not found", userID)
	}
	return nil
}
