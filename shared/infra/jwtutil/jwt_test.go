package jwtutil

import (
	"errors"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
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
