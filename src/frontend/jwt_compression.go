package main

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"os"
	"strings"
)

// JWTComponents represents the decomposed parts of a JWT for compression
type JWTComponents struct {
	Static    string // Highly cacheable: alg, typ, iss, aud, name
	Session   string // Session-cacheable: sub, session_id, market_id, currency, cart_id
	Dynamic   string // Not cacheable: exp, iat, jti
	Signature string // Not compressible: cryptographic signature
}

// IsJWTCompressionEnabled checks if JWT compression is enabled via environment variable
func IsJWTCompressionEnabled() bool {
	return os.Getenv("ENABLE_JWT_COMPRESSION") == "true"
}

// DecomposeJWT splits a JWT into cacheable components for HPACK optimization
// Input: "header.payload.signature" JWT string
// Output: JWTComponents with split JSON objects
func DecomposeJWT(jwtToken string) (*JWTComponents, error) {
	parts := strings.Split(jwtToken, ".")
	if len(parts) != 3 {
		return nil, fmt.Errorf("invalid JWT format: expected 3 parts, got %d", len(parts))
	}

	// Decode header (base64url)
	headerJSON, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return nil, fmt.Errorf("failed to decode JWT header: %w", err)
	}

	// Decode payload (base64url)
	payloadJSON, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return nil, fmt.Errorf("failed to decode JWT payload: %w", err)
	}

	var header map[string]interface{}
	var payload map[string]interface{}

	if err := json.Unmarshal(headerJSON, &header); err != nil {
		return nil, fmt.Errorf("failed to parse JWT header: %w", err)
	}

	if err := json.Unmarshal(payloadJSON, &payload); err != nil {
		return nil, fmt.Errorf("failed to parse JWT payload: %w", err)
	}

	// Build static claims (highly cacheable - same across all requests)
	static := map[string]interface{}{
		"alg": header["alg"],
		"typ": header["typ"],
	}
	
	// Add static payload claims if they exist
	if iss, ok := payload["iss"]; ok {
		static["iss"] = iss
	}
	if aud, ok := payload["aud"]; ok {
		static["aud"] = aud
	}
	if name, ok := payload["name"]; ok {
		static["name"] = name
	}

	// Build session claims (cacheable per user session)
	session := make(map[string]interface{})
	sessionKeys := []string{"sub", "session_id", "market_id", "currency", "cart_id"}
	for _, key := range sessionKeys {
		if val, ok := payload[key]; ok {
			session[key] = val
		}
	}

	// Build dynamic claims (changes frequently, not cacheable)
	dynamic := make(map[string]interface{})
	dynamicKeys := []string{"exp", "iat", "jti", "random_value"}
	for _, key := range dynamicKeys {
		if val, ok := payload[key]; ok {
			dynamic[key] = val
		}
	}

	// Serialize components to JSON
	staticJSON, _ := json.Marshal(static)
	sessionJSON, _ := json.Marshal(session)
	dynamicJSON, _ := json.Marshal(dynamic)

	return &JWTComponents{
		Static:    string(staticJSON),
		Session:   string(sessionJSON),
		Dynamic:   string(dynamicJSON),
		Signature: parts[2], // Keep signature as-is (base64url encoded)
	}, nil
}

// ReassembleJWT reconstructs a JWT from its decomposed components
// Input: JWTComponents
// Output: "header.payload.signature" JWT string
func ReassembleJWT(components *JWTComponents) (string, error) {
	var staticMap, sessionMap, dynamicMap map[string]interface{}

	if err := json.Unmarshal([]byte(components.Static), &staticMap); err != nil {
		return "", fmt.Errorf("failed to parse static claims: %w", err)
	}

	if err := json.Unmarshal([]byte(components.Session), &sessionMap); err != nil {
		return "", fmt.Errorf("failed to parse session claims: %w", err)
	}

	if err := json.Unmarshal([]byte(components.Dynamic), &dynamicMap); err != nil {
		return "", fmt.Errorf("failed to parse dynamic claims: %w", err)
	}

	// Rebuild header
	header := map[string]interface{}{
		"alg": staticMap["alg"],
		"typ": staticMap["typ"],
	}

	// Rebuild payload (merge all claims)
	payload := make(map[string]interface{})
	
	// Add static claims (except alg and typ which go in header)
	for k, v := range staticMap {
		if k != "alg" && k != "typ" {
			payload[k] = v
		}
	}
	
	// Add session claims
	for k, v := range sessionMap {
		payload[k] = v
	}
	
	// Add dynamic claims
	for k, v := range dynamicMap {
		payload[k] = v
	}

	// Encode header and payload to JSON
	headerJSON, err := json.Marshal(header)
	if err != nil {
		return "", fmt.Errorf("failed to marshal header: %w", err)
	}

	payloadJSON, err := json.Marshal(payload)
	if err != nil {
		return "", fmt.Errorf("failed to marshal payload: %w", err)
	}

	// Base64url encode header and payload
	headerB64 := base64.RawURLEncoding.EncodeToString(headerJSON)
	payloadB64 := base64.RawURLEncoding.EncodeToString(payloadJSON)

	// Reconstruct JWT: header.payload.signature
	return fmt.Sprintf("%s.%s.%s", headerB64, payloadB64, components.Signature), nil
}

// GetJWTComponentSizes returns the byte sizes of each component for logging/metrics
func GetJWTComponentSizes(components *JWTComponents) map[string]int {
	return map[string]int{
		"static":    len(components.Static),
		"session":   len(components.Session),
		"dynamic":   len(components.Dynamic),
		"signature": len(components.Signature),
		"total":     len(components.Static) + len(components.Session) + len(components.Dynamic) + len(components.Signature),
	}
}
