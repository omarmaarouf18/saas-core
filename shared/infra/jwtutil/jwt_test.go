package jwtutil

import (
	"crypto/rand"
	"crypto/rsa"
	"errors"
	"math"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/golang-jwt/jwt/v5"
	"github.com/redis/go-redis/v9"
)

func TestValidateToken_Expired(t *testing.T) {
	Init("super-secret-key-that-is-at-least-thirty-two-bytes-long")

	// 1. Test valid token
	tokenStr, err := GenerateToken("user123", "owner", "tenant456", "user@example.com")
	if err != nil {
		t.Fatalf("failed to generate token: %v", err)
	}

	claims, err := ValidateToken(tokenStr)
	if err != nil {
		t.Fatalf("failed to validate valid token: %v", err)
	}
	if claims.UserID != "user123" {
		t.Errorf("expected userID user123, got %s", claims.UserID)
	}

	// 2. Test expired token (1 hour ago)
	expiredClaims := Claims{
		UserID:   "expiredUser",
		Role:     "customer",
		TenantID: "tenantXYZ",
		Email:    "expired@example.com",
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(-1 * time.Hour)),
			IssuedAt:  jwt.NewNumericDate(time.Now().Add(-2 * time.Hour)),
		},
	}
	expiredToken := jwt.NewWithClaims(jwt.SigningMethodHS256, expiredClaims)
	expiredTokenStr, err := expiredToken.SignedString(getSecret())
	if err != nil {
		t.Fatalf("failed to sign expired token: %v", err)
	}

	claims, err = ValidateToken(expiredTokenStr)
	if !errors.Is(err, ErrExpiredToken) {
		t.Fatalf("expected ErrExpiredToken, got %v", err)
	}
	if claims == nil {
		t.Fatalf("expected claims to be populated even when token is expired, got nil")
	}
	if claims.UserID != "expiredUser" {
		t.Errorf("expected userID expiredUser, got %s", claims.UserID)
	}
}

func TestValidateToken_ExpiredAndInvalidSignature(t *testing.T) {
	Init("super-secret-key-that-is-at-least-thirty-two-bytes-long")

	// Create an expired token signed with a DIFFERENT key
	expiredClaims := Claims{
		UserID:   "attacker",
		Role:     "owner",
		TenantID: "tenantXYZ",
		Email:    "attacker@example.com",
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(-1 * time.Hour)),
			IssuedAt:  jwt.NewNumericDate(time.Now().Add(-2 * time.Hour)),
		},
	}
	expiredToken := jwt.NewWithClaims(jwt.SigningMethodHS256, expiredClaims)
	badSecret := []byte("wrong-secret-key-that-is-also-long-enough")
	expiredTokenStr, err := expiredToken.SignedString(badSecret)
	if err != nil {
		t.Fatalf("failed to sign expired token: %v", err)
	}

	claims, err := ValidateToken(expiredTokenStr)
	// We expect validation to fail with a signature error, NOT ErrExpiredToken!
	if err == nil {
		t.Fatalf("expected error for token with bad signature and expired, got nil")
	}
	if errors.Is(err, ErrExpiredToken) {
		t.Fatalf("security violation: token with invalid signature was treated as expired but otherwise valid claims returned (claims: %+v)", claims)
	}
}

func TestJWT_ExtraCoverage(t *testing.T) {
	Init("super-secret-key-that-is-at-least-thirty-two-bytes-long")

	// 1. None algorithm token is rejected
	t.Run("NoneAlgorithmRejected", func(t *testing.T) {
		claims := Claims{
			UserID:   "user123",
			Role:     "owner",
			TenantID: "tenant456",
			Email:    "user@example.com",
			RegisteredClaims: jwt.RegisteredClaims{
				ExpiresAt: jwt.NewNumericDate(time.Now().Add(24 * time.Hour)),
				IssuedAt:  jwt.NewNumericDate(time.Now()),
			},
		}
		token := jwt.NewWithClaims(jwt.SigningMethodNone, claims)
		tokenStr, err := token.SignedString(jwt.UnsafeAllowNoneSignatureType)
		if err != nil {
			t.Fatalf("failed to sign none algorithm token: %v", err)
		}

		_, err = ValidateToken(tokenStr)
		if err == nil {
			t.Error("expected none algorithm token to be rejected, but err was nil")
		}
	})

	// 2. Mismatched signing method (RSA key signed, expecting HMAC) is rejected
	t.Run("MismatchedSigningMethod", func(t *testing.T) {
		claims := Claims{
			UserID:   "user123",
			Role:     "owner",
			TenantID: "tenant456",
			Email:    "user@example.com",
			RegisteredClaims: jwt.RegisteredClaims{
				ExpiresAt: jwt.NewNumericDate(time.Now().Add(24 * time.Hour)),
				IssuedAt:  jwt.NewNumericDate(time.Now()),
			},
		}
		// Generate small RSA private key for testing signature mismatch
		privKey, err := rsa.GenerateKey(rand.Reader, 2048)
		if err != nil {
			t.Fatalf("failed to generate RSA key: %v", err)
		}

		token := jwt.NewWithClaims(jwt.SigningMethodRS256, claims)
		tokenStr, err := token.SignedString(privKey)
		if err != nil {
			t.Fatalf("failed to sign RS256 token: %v", err)
		}

		_, err = ValidateToken(tokenStr)
		if err == nil {
			t.Error("expected RS256 token to be rejected by HMAC validation, but err was nil")
		}
	})

	// 3. Expired token behavior in ValidateToken vs RevokeToken, and TTL calculation correctness
	t.Run("ExpiredTokenAndTTLAndRevokingTwice", func(t *testing.T) {
		mr, err := miniredis.Run()
		if err != nil {
			t.Fatalf("failed to start miniredis: %v", err)
		}
		defer mr.Close()

		rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
		defer rdb.Close()

		SetRedisClient(rdb)
		defer SetRedisClient(nil)

		// Create a token that expired 1 hour ago
		jti, err := GenerateUUID()
		if err != nil {
			t.Fatalf("failed to generate UUID: %v", err)
		}

		expiresAt := time.Now().Add(-1 * time.Hour)
		expiredClaims := Claims{
			UserID:   "expiredUser",
			Role:     "customer",
			TenantID: "tenantXYZ",
			Email:    "expired@example.com",
			RegisteredClaims: jwt.RegisteredClaims{
				ExpiresAt: jwt.NewNumericDate(expiresAt),
				IssuedAt:  jwt.NewNumericDate(time.Now().Add(-2 * time.Hour)),
				ID:        jti,
			},
		}
		expiredToken := jwt.NewWithClaims(jwt.SigningMethodHS256, expiredClaims)
		expiredTokenStr, err := expiredToken.SignedString(getSecret())
		if err != nil {
			t.Fatalf("failed to sign expired token: %v", err)
		}

		// ValidateToken returns the claims AND ErrExpiredToken
		claims, err := ValidateToken(expiredTokenStr)
		if !errors.Is(err, ErrExpiredToken) {
			t.Fatalf("expected ValidateToken to return ErrExpiredToken, got %v", err)
		}
		if claims == nil {
			t.Fatal("expected claims to not be nil even for expired token")
		}

		// RevokeToken succeeds for an expired token if it's within the 7-day refresh window
		err = RevokeToken(expiredTokenStr)
		if err != nil {
			t.Fatalf("expected RevokeToken to succeed on expired token, got: %v", err)
		}

		// Verify key is denylisted in Redis and check the TTL
		denylistKey := "jwt:denylist:" + jti
		if !mr.Exists(denylistKey) {
			t.Error("expected key to exist in Redis denylist")
		}

		// Expected TTL = 7 days + token expiry (since token expiry is -1h, TTL is 7 days - 1h)
		expectedTTL := 7*24*time.Hour + time.Until(expiresAt)
		mrTTL := mr.TTL(denylistKey)
		// Check that the TTL is within 5 seconds of the expected value
		if math.Abs(float64(mrTTL-expectedTTL)) > float64(5*time.Second) {
			t.Errorf("expected TTL close to %v, got %v", expectedTTL, mrTTL)
		}

		// Revoking a token twice should return the revocation error
		err = RevokeToken(expiredTokenStr)
		if err == nil || err.Error() != "jwtutil: token has been revoked" {
			t.Errorf("expected second RevokeToken to fail with 'jwtutil: token has been revoked', got: %v", err)
		}
	})

	// 5. Revoking an already-expired token that is way past the 7-day refresh window
	t.Run("RevokingWayPastRefreshWindow", func(t *testing.T) {
		mr, err := miniredis.Run()
		if err != nil {
			t.Fatalf("failed to start miniredis: %v", err)
		}
		defer mr.Close()

		rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
		defer rdb.Close()

		SetRedisClient(rdb)
		defer SetRedisClient(nil)

		// Create a token that expired 8 days ago
		jti, err := GenerateUUID()
		if err != nil {
			t.Fatalf("failed to generate UUID: %v", err)
		}

		expiresAt := time.Now().Add(-8 * 24 * time.Hour)
		oldClaims := Claims{
			UserID:   "oldUser",
			Role:     "customer",
			TenantID: "tenantXYZ",
			Email:    "old@example.com",
			RegisteredClaims: jwt.RegisteredClaims{
				ExpiresAt: jwt.NewNumericDate(expiresAt),
				IssuedAt:  jwt.NewNumericDate(time.Now().Add(-9 * 24 * time.Hour)),
				ID:        jti,
			},
		}
		oldToken := jwt.NewWithClaims(jwt.SigningMethodHS256, oldClaims)
		oldTokenStr, err := oldToken.SignedString(getSecret())
		if err != nil {
			t.Fatalf("failed to sign old token: %v", err)
		}

		// RevokeToken returns nil early (no-op) and does not write to Redis
		err = RevokeToken(oldTokenStr)
		if err != nil {
			t.Fatalf("expected RevokeToken to return nil for token past refresh window, got: %v", err)
		}

		denylistKey := "jwt:denylist:" + jti
		if mr.Exists(denylistKey) {
			t.Error("expected token past refresh window NOT to be written to Redis denylist")
		}
	})

	// 6. Redis denylist fail-closed behavior when Redis is unreachable
	t.Run("RedisFailClosed", func(t *testing.T) {
		// Generate valid token
		tokenStr, err := GenerateToken("user123", "owner", "tenant456", "user@example.com")
		if err != nil {
			t.Fatalf("failed to generate token: %v", err)
		}

		// Setup unreachable Redis client by using a client that is closed
		rdb := redis.NewClient(&redis.Options{Addr: "localhost:9999"})
		rdb.Close() // Force immediate failure without network wait times

		SetRedisClient(rdb)
		defer SetRedisClient(nil)

		// ValidateToken should fail-closed and return error
		_, err = ValidateToken(tokenStr)
		if err == nil {
			t.Error("expected ValidateToken to fail-closed on unreachable Redis, but err was nil")
		}

		// RevokeToken should fail-closed and return error
		err = RevokeToken(tokenStr)
		if err == nil {
			t.Error("expected RevokeToken to fail-closed on unreachable Redis, but err was nil")
		}
	})
}

func TestRevokeAllUserTokens(t *testing.T) {
	Init("super-secret-key-that-is-at-least-thirty-two-bytes-long")

	// 1. Missing inputs / uninitialized redis errors
	t.Run("ValidationErrors", func(t *testing.T) {
		SetRedisClient(nil)
		if err := RevokeAllUserTokens("user123"); err == nil || err.Error() != "jwtutil: redis client not initialized" {
			t.Errorf("expected 'jwtutil: redis client not initialized', got %v", err)
		}

		mr, err := miniredis.Run()
		if err != nil {
			t.Fatalf("failed to start miniredis: %v", err)
		}
		defer mr.Close()
		rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
		defer rdb.Close()

		SetRedisClient(rdb)
		defer SetRedisClient(nil)

		if err := RevokeAllUserTokens(""); err == nil || err.Error() != "jwtutil: missing user_id" {
			t.Errorf("expected 'jwtutil: missing user_id', got %v", err)
		}
	})

	// 2. Successful revocation of pre-invalidation tokens & validity of post-invalidation tokens
	t.Run("RevocationLifecycle", func(t *testing.T) {
		mr, err := miniredis.Run()
		if err != nil {
			t.Fatalf("failed to start miniredis: %v", err)
		}
		defer mr.Close()
		rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
		defer rdb.Close()

		SetRedisClient(rdb)
		defer SetRedisClient(nil)

		userID1 := "user-revoke-1"
		userID2 := "user-revoke-2"

		// Generate token1 for user1 BEFORE revocation
		token1, err := GenerateToken(userID1, "customer", "tenant-1", "user1@example.com")
		if err != nil {
			t.Fatalf("failed to generate token1: %v", err)
		}

		// Generate token3 for user2 BEFORE revocation
		token3, err := GenerateToken(userID2, "customer", "tenant-1", "user2@example.com")
		if err != nil {
			t.Fatalf("failed to generate token3: %v", err)
		}

		// Ensure token issuance timestamp is strictly before the revocation timestamp
		time.Sleep(1 * time.Second)

		// Revoke all user tokens for user1
		if err := RevokeAllUserTokens(userID1); err != nil {
			t.Fatalf("RevokeAllUserTokens failed: %v", err)
		}

		// Key should exist in miniredis
		key := "jwt:invalidated_before:" + userID1
		if !mr.Exists(key) {
			t.Fatalf("expected key %s to exist in miniredis", key)
		}

		// Generate token2 for user1 AFTER revocation
		token2, err := GenerateToken(userID1, "customer", "tenant-1", "user1@example.com")
		if err != nil {
			t.Fatalf("failed to generate token2: %v", err)
		}

		// Validate token1 (user1, pre-revocation) -> MUST BE REJECTED
		claims1, err1 := ValidateToken(token1)
		if err1 == nil || err1.Error() != "jwtutil: token has been revoked" {
			t.Errorf("expected token1 to be revoked, got err: %v, claims: %+v", err1, claims1)
		}

		// Validate token2 (user1, post-revocation) -> MUST BE VALID
		claims2, err2 := ValidateToken(token2)
		if err2 != nil {
			t.Errorf("expected token2 to be valid after revocation timestamp, got err: %v", err2)
		}
		if claims2 == nil || claims2.UserID != userID1 {
			t.Errorf("expected claims2 UserID to be %s, got %+v", userID1, claims2)
		}

		// Validate token3 (user2, unaffected user) -> MUST BE VALID
		claims3, err3 := ValidateToken(token3)
		if err3 != nil {
			t.Errorf("expected token3 for user2 to be unaffected, got err: %v", err3)
		}
		if claims3 == nil || claims3.UserID != userID2 {
			t.Errorf("expected claims3 UserID to be %s, got %+v", userID2, claims3)
		}
	})

	// 3. Fail-closed behavior on Redis lookup failure
	t.Run("RedisFailClosedOnUserCheck", func(t *testing.T) {
		tokenStr, err := GenerateToken("user-fail-closed", "customer", "tenant-1", "fail@example.com")
		if err != nil {
			t.Fatalf("failed to generate token: %v", err)
		}

		rdb := redis.NewClient(&redis.Options{Addr: "localhost:9999"})
		rdb.Close()

		SetRedisClient(rdb)
		defer SetRedisClient(nil)

		_, err = ValidateToken(tokenStr)
		if err == nil || !errors.Is(err, errors.New("jwtutil: security check failed (user invalidation lookup unreachable)")) {
			if err == nil || !testing.Verbose() && err.Error() == "" {
				t.Errorf("expected ValidateToken to fail closed on user invalidation check error, got: %v", err)
			}
		}

		err = RevokeAllUserTokens("user-fail-closed")
		if err == nil {
			t.Error("expected RevokeAllUserTokens to fail on closed Redis client")
		}
	})
}

func TestGenerateSecureToken(t *testing.T) {
	tok, err := GenerateSecureToken()
	if err != nil {
		t.Fatalf("GenerateSecureToken failed: %v", err)
	}
	if len(tok) != 64 {
		t.Errorf("Expected hex string of length 64 (32 bytes), got length %d", len(tok))
	}
}
