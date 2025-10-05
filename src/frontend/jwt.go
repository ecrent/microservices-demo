// Copyright 2024 Google LLC
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
	"crypto/rand"
	"encoding/hex"
	"os"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/pkg/errors"
)

var (
	jwtSecret     []byte
	jwtExpiration = 24 * time.Hour // 24 hours token expiration
)

// Claims represents the JWT claims structure
type Claims struct {
	UserID    string `json:"sub"`
	SessionID string `json:"session_id"`
	jwt.RegisteredClaims
}

// initJWT initializes the JWT secret from environment or generates a random one
func initJWT() error {
	secretStr := os.Getenv("JWT_SECRET")
	if secretStr == "" {
		// Generate a random secret for development
		randomBytes := make([]byte, 32)
		if _, err := rand.Read(randomBytes); err != nil {
			return errors.Wrap(err, "failed to generate random JWT secret")
		}
		jwtSecret = []byte(hex.EncodeToString(randomBytes))
	} else {
		jwtSecret = []byte(secretStr)
	}
	return nil
}

// generateJWT creates a new JWT token for the given session ID
func generateJWT(sessionID string) (string, error) {
	claims := &Claims{
		UserID:    sessionID, // Using session ID as user ID for simplicity
		SessionID: sessionID,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(jwtExpiration)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			NotBefore: jwt.NewNumericDate(time.Now()),
			Issuer:    "online-boutique-frontend",
			Subject:   sessionID,
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenString, err := token.SignedString(jwtSecret)
	if err != nil {
		return "", errors.Wrap(err, "failed to sign JWT token")
	}

	return tokenString, nil
}

// validateJWT validates a JWT token and returns the claims
func validateJWT(tokenString string) (*Claims, error) {
	token, err := jwt.ParseWithClaims(tokenString, &Claims{}, func(token *jwt.Token) (interface{}, error) {
		// Verify the signing method
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, errors.Errorf("unexpected signing method: %v", token.Header["alg"])
		}
		return jwtSecret, nil
	})

	if err != nil {
		return nil, errors.Wrap(err, "failed to parse JWT token")
	}

	if claims, ok := token.Claims.(*Claims); ok && token.Valid {
		return claims, nil
	}

	return nil, errors.New("invalid JWT token")
}
