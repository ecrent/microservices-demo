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
	"encoding/base64"
	"encoding/json"
	"strings"

	"github.com/pkg/errors"
)

// JWTClaims represents the JWT claims we want to split
type JWTClaims struct {
	Sub       string `json:"sub"`        // Subject (user ID)
	SessionID string `json:"session_id"` // Session ID
	Iss       string `json:"iss"`        // Issuer
	Exp       int64  `json:"exp"`        // Expiration
	Nbf       int64  `json:"nbf"`        // Not before
	Iat       int64  `json:"iat"`        // Issued at
}

// SplitJWTHeaders represents the split JWT components
type SplitJWTHeaders struct {
	Header    string // auth-jwt-h: JWT header (algorithm, type)
	Issuer    string // auth-jwt-c-iss: Issuer (highly cacheable)
	Subject   string // auth-jwt-c-sub: Subject/User ID (session cacheable)
	IssuedAt  string // auth-jwt-c-iat: Issued at timestamp
	ExpiresAt string // auth-jwt-c-exp: Expiration timestamp
	NotBefore string // auth-jwt-c-nbf: Not before timestamp
	Signature string // auth-jwt-s: Signature (not compressible)
}

// splitJWT splits a JWT token into individual headers for HPACK optimization
// This allows HPACK's dynamic table to cache static/semi-static components
func splitJWT(jwtToken string) (*SplitJWTHeaders, error) {
	// JWT format: header.payload.signature
	parts := strings.Split(jwtToken, ".")
	if len(parts) != 3 {
		return nil, errors.New("invalid JWT format: expected 3 parts")
	}

	headerEncoded := parts[0]
	payloadEncoded := parts[1]
	signature := parts[2]

	// Decode payload to extract claims
	payloadBytes, err := base64.RawURLEncoding.DecodeString(payloadEncoded)
	if err != nil {
		return nil, errors.Wrap(err, "failed to decode JWT payload")
	}

	var claims JWTClaims
	if err := json.Unmarshal(payloadBytes, &claims); err != nil {
		return nil, errors.Wrap(err, "failed to unmarshal JWT claims")
	}

	// Create split headers
	split := &SplitJWTHeaders{
		Header:    headerEncoded,                  // Highly cacheable (same for all tokens)
		Issuer:    claims.Iss,                     // Highly cacheable (same issuer)
		Subject:   claims.Sub,                     // Session cacheable (same user)
		IssuedAt:  stringInt64(claims.Iat),        // Not cacheable (changes per token)
		ExpiresAt: stringInt64(claims.Exp),        // Not cacheable (changes per token)
		NotBefore: stringInt64(claims.Nbf),        // Not cacheable (changes per token)
		Signature: signature,                      // Not cacheable (unique per token)
	}

	return split, nil
}

// reconstructJWT rebuilds a JWT token from split headers
// Used for backwards compatibility and validation
func reconstructJWT(split *SplitJWTHeaders) (string, error) {
	if split == nil {
		return "", errors.New("split headers cannot be nil")
	}

	// Reconstruct payload
	claims := JWTClaims{
		Sub:       split.Subject,
		SessionID: split.Subject, // Session ID is same as Subject/UserID
		Iss:       split.Issuer,
		Exp:       parseInt64(split.ExpiresAt),
		Nbf:       parseInt64(split.NotBefore),
		Iat:       parseInt64(split.IssuedAt),
	}

	payloadBytes, err := json.Marshal(claims)
	if err != nil {
		return "", errors.Wrap(err, "failed to marshal JWT claims")
	}

	payloadEncoded := base64.RawURLEncoding.EncodeToString(payloadBytes)

	// Reconstruct JWT
	jwtToken := split.Header + "." + payloadEncoded + "." + split.Signature

	return jwtToken, nil
}

// Helper function to convert int64 to string
func stringInt64(i int64) string {
	b, _ := json.Marshal(i)
	return string(b)
}

// Helper function to parse string to int64
func parseInt64(s string) int64 {
	var i int64
	_ = json.Unmarshal([]byte(s), &i)
	return i
}

// getHeaderSizeMetrics calculates the size savings from header splitting
func getHeaderSizeMetrics(fullJWT string, split *SplitJWTHeaders) map[string]int {
	fullSize := len("Authorization: Bearer ") + len(fullJWT)
	
	splitSize := 0
	splitSize += len("auth-jwt-h: ") + len(split.Header)
	splitSize += len("auth-jwt-c-iss: ") + len(split.Issuer)
	splitSize += len("auth-jwt-c-sub: ") + len(split.Subject)
	splitSize += len("auth-jwt-c-iat: ") + len(split.IssuedAt)
	splitSize += len("auth-jwt-c-exp: ") + len(split.ExpiresAt)
	splitSize += len("auth-jwt-c-nbf: ") + len(split.NotBefore)
	splitSize += len("auth-jwt-s: ") + len(split.Signature)

	// Estimated HPACK compressed size (after first request when cached)
	// Highly cacheable headers become ~2 bytes (indexed)
	hpackCachedSize := 0
	hpackCachedSize += 2 // auth-jwt-h (indexed from dynamic table)
	hpackCachedSize += 2 // auth-jwt-c-iss (indexed from dynamic table)
	hpackCachedSize += 2 // auth-jwt-c-sub (indexed for same user)
	hpackCachedSize += len("auth-jwt-c-iat: ") + len(split.IssuedAt) // Not cached
	hpackCachedSize += len("auth-jwt-c-exp: ") + len(split.ExpiresAt) // Not cached
	hpackCachedSize += len("auth-jwt-c-nbf: ") + len(split.NotBefore) // Not cached
	hpackCachedSize += len("auth-jwt-s: ") + len(split.Signature)     // Not cached

	return map[string]int{
		"full_jwt_size":         fullSize,
		"split_uncompressed":    splitSize,
		"split_hpack_estimated": hpackCachedSize,
		"savings_bytes":         fullSize - hpackCachedSize,
		"savings_percent":       ((fullSize - hpackCachedSize) * 100) / fullSize,
	}
}
