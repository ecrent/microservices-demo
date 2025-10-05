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
	"testing"
)

func TestSplitAndReconstructJWT(t *testing.T) {
	// Initialize JWT for testing
	if err := initJWT(); err != nil {
		t.Fatalf("Failed to initialize JWT: %v", err)
	}

	// Generate a test JWT token
	testUserID := "test-user-12345"
	originalJWT, err := generateJWT(testUserID)
	if err != nil {
		t.Fatalf("Failed to generate JWT: %v", err)
	}

	t.Logf("Original JWT: %s", originalJWT)
	t.Logf("Original JWT length: %d bytes", len(originalJWT))

	// Test 1: Split the JWT
	split, err := splitJWT(originalJWT)
	if err != nil {
		t.Fatalf("Failed to split JWT: %v", err)
	}

	// Verify split components
	if split.Header == "" {
		t.Error("Split header is empty")
	}
	if split.Issuer != "online-boutique-frontend" {
		t.Errorf("Expected issuer 'online-boutique-frontend', got '%s'", split.Issuer)
	}
	if split.Subject != testUserID {
		t.Errorf("Expected subject '%s', got '%s'", testUserID, split.Subject)
	}
	if split.Signature == "" {
		t.Error("Split signature is empty")
	}
	if split.IssuedAt == "" {
		t.Error("Split IssuedAt is empty")
	}
	if split.ExpiresAt == "" {
		t.Error("Split ExpiresAt is empty")
	}
	if split.NotBefore == "" {
		t.Error("Split NotBefore is empty")
	}

	t.Logf("Split components:")
	t.Logf("  Header: %s (%d bytes)", split.Header, len(split.Header))
	t.Logf("  Issuer: %s (%d bytes)", split.Issuer, len(split.Issuer))
	t.Logf("  Subject: %s (%d bytes)", split.Subject, len(split.Subject))
	t.Logf("  IssuedAt: %s (%d bytes)", split.IssuedAt, len(split.IssuedAt))
	t.Logf("  ExpiresAt: %s (%d bytes)", split.ExpiresAt, len(split.ExpiresAt))
	t.Logf("  NotBefore: %s (%d bytes)", split.NotBefore, len(split.NotBefore))
	t.Logf("  Signature: %s (%d bytes)", split.Signature, len(split.Signature))

	// Test 2: Reconstruct the JWT
	reconstructedJWT, err := reconstructJWT(split)
	if err != nil {
		t.Fatalf("Failed to reconstruct JWT: %v", err)
	}

	t.Logf("Reconstructed JWT: %s", reconstructedJWT)
	t.Logf("Reconstructed JWT length: %d bytes", len(reconstructedJWT))

	// Test 3: Verify reconstructed JWT matches original
	if originalJWT != reconstructedJWT {
		t.Errorf("Reconstructed JWT does not match original!\nOriginal:      %s\nReconstructed: %s", 
			originalJWT, reconstructedJWT)
	}

	// Test 4: Validate the reconstructed JWT
	claims, err := validateJWT(reconstructedJWT)
	if err != nil {
		t.Fatalf("Reconstructed JWT validation failed: %v", err)
	}

	if claims.UserID != testUserID {
		t.Errorf("Expected UserID '%s', got '%s'", testUserID, claims.UserID)
	}
	if claims.Issuer != "online-boutique-frontend" {
		t.Errorf("Expected Issuer 'online-boutique-frontend', got '%s'", claims.Issuer)
	}

	t.Log("✅ JWT split and reconstruct successful!")
}

func TestHeaderSizeMetrics(t *testing.T) {
	// Initialize JWT
	if err := initJWT(); err != nil {
		t.Fatalf("Failed to initialize JWT: %v", err)
	}

	// Generate test token
	testUserID := "test-user-67890"
	jwtToken, err := generateJWT(testUserID)
	if err != nil {
		t.Fatalf("Failed to generate JWT: %v", err)
	}

	// Split token
	split, err := splitJWT(jwtToken)
	if err != nil {
		t.Fatalf("Failed to split JWT: %v", err)
	}

	// Get metrics
	metrics := getHeaderSizeMetrics(jwtToken, split)

	t.Log("Header Size Metrics:")
	t.Logf("  Full JWT size: %d bytes", metrics["full_jwt_size"])
	t.Logf("  Split uncompressed: %d bytes", metrics["split_uncompressed"])
	t.Logf("  Split HPACK estimated: %d bytes", metrics["split_hpack_estimated"])
	t.Logf("  Savings: %d bytes (%d%%)", 
		metrics["savings_bytes"], 
		metrics["savings_percent"])

	// Verify we get savings
	if metrics["savings_percent"] < 50 {
		t.Errorf("Expected at least 50%% savings, got %d%%", metrics["savings_percent"])
	}

	if metrics["split_hpack_estimated"] >= metrics["full_jwt_size"] {
		t.Error("HPACK compressed size should be smaller than full JWT")
	}

	t.Log("✅ Header size metrics calculated successfully!")
}

func TestInvalidJWT(t *testing.T) {
	// Test with invalid JWT format
	invalidJWTs := []string{
		"",
		"invalid",
		"two.parts",
		"not.a.valid.jwt.token",
	}

	for _, invalidJWT := range invalidJWTs {
		_, err := splitJWT(invalidJWT)
		if err == nil {
			t.Errorf("Expected error for invalid JWT '%s', but got none", invalidJWT)
		}
	}

	t.Log("✅ Invalid JWT handling works correctly!")
}

func TestReconstructWithNilSplit(t *testing.T) {
	_, err := reconstructJWT(nil)
	if err == nil {
		t.Error("Expected error when reconstructing from nil split, but got none")
	}

	t.Log("✅ Nil split handling works correctly!")
}

func TestReconstructWithEmptyComponents(t *testing.T) {
	// Test with empty split components
	emptySplit := &SplitJWTHeaders{
		Header:    "",
		Issuer:    "",
		Subject:   "",
		IssuedAt:  "",
		ExpiresAt: "",
		NotBefore: "",
		Signature: "",
	}

	reconstructedJWT, err := reconstructJWT(emptySplit)
	if err != nil {
		t.Fatalf("Reconstruction failed: %v", err)
	}

	// Should produce a minimal JWT (though invalid)
	t.Logf("Reconstructed from empty: %s", reconstructedJWT)

	// Should have the structure header.payload.signature
	if len(reconstructedJWT) < 3 {
		t.Error("Reconstructed JWT is too short")
	}

	t.Log("✅ Empty components handling works correctly!")
}

func BenchmarkSplitJWT(b *testing.B) {
	// Initialize JWT
	if err := initJWT(); err != nil {
		b.Fatalf("Failed to initialize JWT: %v", err)
	}

	// Generate test token
	jwtToken, err := generateJWT("benchmark-user")
	if err != nil {
		b.Fatalf("Failed to generate JWT: %v", err)
	}

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, err := splitJWT(jwtToken)
		if err != nil {
			b.Fatalf("Split failed: %v", err)
		}
	}
}

func BenchmarkReconstructJWT(b *testing.B) {
	// Initialize JWT
	if err := initJWT(); err != nil {
		b.Fatalf("Failed to initialize JWT: %v", err)
	}

	// Generate and split test token
	jwtToken, err := generateJWT("benchmark-user")
	if err != nil {
		b.Fatalf("Failed to generate JWT: %v", err)
	}

	split, err := splitJWT(jwtToken)
	if err != nil {
		b.Fatalf("Failed to split JWT: %v", err)
	}

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, err := reconstructJWT(split)
		if err != nil {
			b.Fatalf("Reconstruct failed: %v", err)
		}
	}
}

func BenchmarkFullCycle(b *testing.B) {
	// Initialize JWT
	if err := initJWT(); err != nil {
		b.Fatalf("Failed to initialize JWT: %v", err)
	}

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		// Generate
		jwtToken, err := generateJWT("benchmark-user")
		if err != nil {
			b.Fatalf("Failed to generate JWT: %v", err)
		}

		// Split
		split, err := splitJWT(jwtToken)
		if err != nil {
			b.Fatalf("Failed to split JWT: %v", err)
		}

		// Reconstruct
		_, err = reconstructJWT(split)
		if err != nil {
			b.Fatalf("Failed to reconstruct JWT: %v", err)
		}
	}
}
