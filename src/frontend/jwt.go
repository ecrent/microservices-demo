// Copyright 2018 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package main

import (
	"context"
	"crypto/rsa"
	"fmt"
	"net/http"
	"os"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

const (
	cookieJWT = cookiePrefix + "jwt"
	jwtIssuer = "https://auth.hipstershop.com"
	jwtAudience = "urn:hipstershop:api"
)

var (
	privateKey *rsa.PrivateKey
	publicKey  *rsa.PublicKey
)

type JWTClaims struct {
	SessionID string `json:"session_id"`
	Name      string `json:"name"`
	MarketID  string `json:"market_id"`
	Currency  string `json:"currency"`
	CartID    string `json:"cart_id"`
	jwt.RegisteredClaims
}

type ctxKeyJWT struct{}
type ctxKeyJWTToken struct{}

// loadRSAKeys loads the RSA private and public keys from PEM files
func loadRSAKeys() error {
	// Load private key
	privateKeyData, err := os.ReadFile("jwt_private_key.pem")
	if err != nil {
		return fmt.Errorf("failed to read private key: %w", err)
	}

	privateKey, err = jwt.ParseRSAPrivateKeyFromPEM(privateKeyData)
	if err != nil {
		return fmt.Errorf("failed to parse private key: %w", err)
	}

	// Load public key
	publicKeyData, err := os.ReadFile("jwt_public_key.pem")
	if err != nil {
		return fmt.Errorf("failed to read public key: %w", err)
	}

	publicKey, err = jwt.ParseRSAPublicKeyFromPEM(publicKeyData)
	if err != nil {
		return fmt.Errorf("failed to parse public key: %w", err)
	}

	return nil
}

// generateJWT creates a new JWT token with the given session ID and currency
func generateJWT(sessionID, currency string) (string, error) {
	now := time.Now()
	jti, _ := uuid.NewRandom()

	// Handle empty sessionID
	cartIDSuffix := "unknown"
	subjectSuffix := "unknown"
	if len(sessionID) >= 20 {
		cartIDSuffix = sessionID[:8]
		subjectSuffix = sessionID[:20]
	} else if len(sessionID) > 0 {
		cartIDSuffix = sessionID
		subjectSuffix = sessionID
	}

	claims := JWTClaims{
		SessionID: sessionID,
		Name:      "Jane Doe",
		MarketID:  "US",
		Currency:  currency,
		CartID:    fmt.Sprintf("cart-uuid-%s", cartIDSuffix),
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    jwtIssuer,
			Subject:   fmt.Sprintf("urn:hipstershop:user:%s", subjectSuffix),
			Audience:  jwt.ClaimStrings{jwtAudience},
			ExpiresAt: jwt.NewNumericDate(now.Add(5 * time.Minute)),
			IssuedAt:  jwt.NewNumericDate(now),
			ID:        jti.String(),
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodRS256, claims)
	tokenString, err := token.SignedString(privateKey)
	if err != nil {
		return "", fmt.Errorf("failed to sign token: %w", err)
	}

	return tokenString, nil
}

// validateJWT validates a JWT token and returns the claims if valid
func validateJWT(tokenString string) (*JWTClaims, error) {
	token, err := jwt.ParseWithClaims(tokenString, &JWTClaims{}, func(token *jwt.Token) (interface{}, error) {
		// Verify the signing method
		if _, ok := token.Method.(*jwt.SigningMethodRSA); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}
		return publicKey, nil
	})

	if err != nil {
		return nil, fmt.Errorf("failed to parse token: %w", err)
	}

	if claims, ok := token.Claims.(*JWTClaims); ok && token.Valid {
		// Check if name is "Jane Doe"
		if claims.Name != "Jane Doe" {
			return nil, fmt.Errorf("invalid user name in token")
		}
		return claims, nil
	}

	return nil, fmt.Errorf("invalid token")
}

// generateJWTFromClaims regenerates a JWT token from existing claims
func generateJWTFromClaims(claims *JWTClaims) (string, error) {
	token := jwt.NewWithClaims(jwt.SigningMethodRS256, claims)
	tokenString, err := token.SignedString(privateKey)
	if err != nil {
		return "", fmt.Errorf("failed to sign token: %w", err)
	}
	return tokenString, nil
}

// ensureJWT middleware ensures that a valid JWT exists for the request
func ensureJWT(next http.Handler) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var tokenString string
		var claims *JWTClaims
		var needNewToken bool = false

		// Try to get JWT from cookie
		c, err := r.Cookie(cookieJWT)
		if err == http.ErrNoCookie {
			needNewToken = true
		} else if err != nil {
			http.Error(w, "Error reading JWT cookie", http.StatusInternalServerError)
			return
		} else {
			tokenString = c.Value
			// Validate existing token
			claims, err = validateJWT(tokenString)
			if err != nil {
				// Token is invalid or expired, need new one
				needNewToken = true
			}
		}

		// Generate new JWT if needed
		if needNewToken {
			sessionID := sessionID(r)
			currency := currentCurrency(r)
			
			newToken, err := generateJWT(sessionID, currency)
			if err != nil {
				http.Error(w, "Failed to generate JWT", http.StatusInternalServerError)
				return
			}

			tokenString = newToken
			
			// Validate to get claims
			claims, _ = validateJWT(tokenString)

			// Set JWT cookie
			http.SetCookie(w, &http.Cookie{
				Name:     cookieJWT,
				Value:    tokenString,
				MaxAge:   300, // 5 minutes (same as JWT expiration)
				HttpOnly: true,
				SameSite: http.SameSiteStrictMode,
			})
		}

		// Add JWT token string and claims to context for use in gRPC calls
		ctx := context.WithValue(r.Context(), ctxKeyJWTToken{}, tokenString)
		ctx = context.WithValue(ctx, ctxKeyJWT{}, claims)
		r = r.WithContext(ctx)

		next.ServeHTTP(w, r)
	}
}

// getJWTFromContext retrieves JWT claims from context
func getJWTFromContext(ctx context.Context) (*JWTClaims, bool) {
	claims, ok := ctx.Value(ctxKeyJWT{}).(*JWTClaims)
	return claims, ok
}

// Helper function to get current JWT token from request
func getJWTToken(r *http.Request) string {
	c, err := r.Cookie(cookieJWT)
	if err != nil {
		return ""
	}
	return c.Value
}
