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

func TestGenerateSecureToken(t *testing.T) {
	tok, err := GenerateSecureToken()
	if err != nil {
		t.Fatalf("GenerateSecureToken failed: %v", err)
	}
	if len(tok) != 64 {
		t.Errorf("Expected hex string of length 64 (32 bytes), got length %d", len(tok))
	}
}
