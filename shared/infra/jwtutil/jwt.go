package jwtutil

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"log"
	"os"
	"strconv"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/redis/go-redis/v9"
)

var (
	ErrInvalidToken = errors.New("invalid token")
	ErrExpiredToken = errors.New("token has expired")
)

type Claims struct {
	UserID   string `json:"user_id"`
	Role     string `json:"role"`
	TenantID string `json:"tenant_id"`
	Email    string `json:"email"`
	jwt.RegisteredClaims
}

var jwtSecret []byte
var redisClient *redis.Client

func Init(secret string) {
	if secret == "" {
		panic("JWT_SECRET is required and must not be empty")
	}
	jwtSecret = []byte(secret)
}

func SetRedisClient(client *redis.Client) {
	redisClient = client
}

func getSecret() []byte {
	if len(jwtSecret) == 0 {
		secret := os.Getenv("JWT_SECRET")
		if secret == "" {
			panic("JWT_SECRET environment variable is required and must not be empty")
		}
		return []byte(secret)
	}
	return jwtSecret
}

// GenerateUUID generates an RFC 4122 compliant UUID v4.
func GenerateUUID() (string, error) {
	uuid := make([]byte, 16)
	_, err := rand.Read(uuid)
	if err != nil {
		return "", err
	}
	// Set version to 4
	uuid[6] = (uuid[6] & 0x0f) | 0x40
	// Set variant to RFC 4122
	uuid[8] = (uuid[8] & 0x3f) | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", uuid[0:4], uuid[4:6], uuid[6:8], uuid[8:10], uuid[10:]), nil
}

func GenerateToken(userID string, role string, tenantID string, email string) (string, error) {
	uuidStr, err := GenerateUUID()
	if err != nil {
		return "", fmt.Errorf("jwtutil: failed to generate token uuid: %w", err)
	}

	claims := Claims{
		UserID:   userID,
		Role:     role,
		TenantID: tenantID,
		Email:    email,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(24 * time.Hour)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			NotBefore: jwt.NewNumericDate(time.Now()),
			ID:        uuidStr,
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(getSecret())
}

func ValidateToken(tokenStr string) (*Claims, error) {
	token, err := jwt.ParseWithClaims(tokenStr, &Claims{}, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}
		return getSecret(), nil
	})

	var isExpired bool
	if err != nil {
		if errors.Is(err, jwt.ErrTokenExpired) {
			isExpired = true
		} else {
			return nil, err
		}
	}

	claims, ok := token.Claims.(*Claims)
	if !ok {
		return nil, ErrInvalidToken
	}

	// Redis-backed denylist check.
	// We explicitly fail-closed if Redis is unreachable to maintain security integrity.
	if redisClient != nil && claims.RegisteredClaims.ID != "" {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		isDenylisted, err := redisClient.Exists(ctx, "jwt:denylist:"+claims.RegisteredClaims.ID).Result()
		if err != nil {
			log.Printf("[SECURITY CRITICAL] Redis error checking JWT denylist (FAIL CLOSED): %v. Rejecting token jti: %s", err, claims.RegisteredClaims.ID)
			return nil, fmt.Errorf("jwtutil: security check failed (denylist unreachable): %w", err)
		}
		if isDenylisted > 0 {
			return nil, errors.New("jwtutil: token has been revoked")
		}
	}

	// Redis-backed per-user token invalidation check (tokens issued before stored timestamp).
	// We explicitly fail-closed if Redis is unreachable to maintain security integrity.
	if redisClient != nil && claims.UserID != "" {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		invalidatedStr, err := redisClient.Get(ctx, "jwt:invalidated_before:"+claims.UserID).Result()
		if err != nil && !errors.Is(err, redis.Nil) {
			log.Printf("[SECURITY CRITICAL] Redis error checking user token invalidation (FAIL CLOSED): %v. Rejecting user_id: %s", err, claims.UserID)
			return nil, fmt.Errorf("jwtutil: security check failed (user invalidation lookup unreachable): %w", err)
		}
		if err == nil && invalidatedStr != "" {
			ts, parseErr := strconv.ParseInt(invalidatedStr, 10, 64)
			if parseErr != nil {
				log.Printf("[SECURITY CRITICAL] Redis error parsing user token invalidation timestamp (FAIL CLOSED): %v. Rejecting user_id: %s", parseErr, claims.UserID)
				return nil, fmt.Errorf("jwtutil: security check failed (invalid timestamp format): %w", parseErr)
			}
			if claims.IssuedAt == nil || claims.IssuedAt.Time.Unix() < ts {
				return nil, errors.New("jwtutil: token has been revoked")
			}
		}
	}

	if isExpired {
		return claims, ErrExpiredToken
	}

	if !token.Valid {
		return nil, ErrInvalidToken
	}

	return claims, nil
}

// RevokeAllUserTokens invalidates all tokens issued for a specific user prior to the current timestamp.
// It sets a Redis key jwt:invalidated_before:<user_id> to the current Unix timestamp.
func RevokeAllUserTokens(userID string) error {
	if userID == "" {
		return errors.New("jwtutil: missing user_id")
	}
	if redisClient == nil {
		return errors.New("jwtutil: redis client not initialized")
	}

	now := time.Now()
	timestamp := now.Unix()

	// TTL: 24h token expiry + 7-day refresh window (matches RevokeToken TTL pattern)
	ttl := 24*time.Hour + 7*24*time.Hour

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	key := "jwt:invalidated_before:" + userID
	err := redisClient.Set(ctx, key, strconv.FormatInt(timestamp, 10), ttl).Err()
	if err != nil {
		log.Printf("[SECURITY CRITICAL] Redis error storing user token invalidation timestamp (FAIL CLOSED): %v. User ID: %s", err, userID)
		return fmt.Errorf("jwtutil: revoke all user tokens failed: %w", err)
	}
	return nil
}

// RevokeToken denylists a token's jti in Redis.
// Expired tokens are held in the denylist until the end of their 7-day refresh window.
func RevokeToken(tokenStr string) error {
	claims, err := ValidateToken(tokenStr)
	// We allow revoking expired tokens so they cannot be refreshed
	if err != nil && !errors.Is(err, ErrExpiredToken) {
		return err
	}
	if claims == nil || claims.RegisteredClaims.ID == "" {
		return errors.New("jwtutil: invalid token or missing jti")
	}
	if redisClient == nil {
		return errors.New("jwtutil: redis client not initialized")
	}

	var ttl time.Duration
	if claims.ExpiresAt != nil {
		// Hold until token expiry + 7 days refresh window to prevent refresh reuse
		ttl = time.Until(claims.ExpiresAt.Time.Add(7 * 24 * time.Hour))
	}

	if ttl <= 0 {
		return nil // Already past the refresh window
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	err = redisClient.Set(ctx, "jwt:denylist:"+claims.RegisteredClaims.ID, "1", ttl).Err()
	if err != nil {
		log.Printf("[SECURITY CRITICAL] Redis error storing revoked JWT (FAIL CLOSED): %v. Token jti: %s", err, claims.RegisteredClaims.ID)
		return fmt.Errorf("jwtutil: revoke failed: %w", err)
	}
	return nil
}

// GenerateSecureToken generates a cryptographically secure 32-byte hex token.
func GenerateSecureToken() (string, error) {
	bytes := make([]byte, 32)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	return hex.EncodeToString(bytes), nil
}
