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
	"context"
	"os"

	"github.com/sirupsen/logrus"
	"google.golang.org/grpc"
	"google.golang.org/grpc/metadata"
)

const (
	// Header names for split JWT components
	// Using short names for better HPACK compression
	headerJWTHeader    = "auth-jwt-h"      // JWT header (highly cacheable)
	headerJWTIssuer    = "auth-jwt-c-iss"  // Issuer (highly cacheable)
	headerJWTSubject   = "auth-jwt-c-sub"  // Subject/User ID (session cacheable)
	headerJWTIssuedAt  = "auth-jwt-c-iat"  // Issued at (not cacheable)
	headerJWTExpiresAt = "auth-jwt-c-exp"  // Expires at (not cacheable)
	headerJWTNotBefore = "auth-jwt-c-nbf"  // Not before (not cacheable)
	headerJWTSignature = "auth-jwt-s"      // Signature (not cacheable)
	
	// Feature flag to enable/disable header splitting
	envEnableJWTSplitting = "ENABLE_JWT_SPLITTING"
)

// jwtSplittingEnabled checks if JWT header splitting is enabled
func jwtSplittingEnabled() bool {
	return os.Getenv(envEnableJWTSplitting) == "true"
}

// UnaryClientInterceptorJWTSplitter is a gRPC client interceptor that splits JWT tokens
// into multiple headers for better HPACK compression efficiency
func UnaryClientInterceptorJWTSplitter(log *logrus.Logger) grpc.UnaryClientInterceptor {
	return func(
		ctx context.Context,
		method string,
		req, reply interface{},
		cc *grpc.ClientConn,
		invoker grpc.UnaryInvoker,
		opts ...grpc.CallOption,
	) error {
		// Check if JWT splitting is enabled
		if !jwtSplittingEnabled() {
			// Pass through without modification
			return invoker(ctx, method, req, reply, cc, opts...)
		}

		// Get existing metadata from context
		md, ok := metadata.FromOutgoingContext(ctx)
		if !ok {
			md = metadata.New(nil)
		} else {
			// Clone to avoid modifying original
			md = md.Copy()
		}

		// Check if we have a JWT token to split
		// Option 1: Check for "authorization" header with Bearer token
		if authHeaders := md.Get("authorization"); len(authHeaders) > 0 {
			// This would be from HTTP → gRPC conversion
			// Not typically used, but included for completeness
			jwtToken := extractBearerToken(authHeaders[0])
			if jwtToken != "" {
				if err := addSplitJWTToMetadata(md, jwtToken, log); err != nil {
					log.WithError(err).Warn("failed to split JWT token, using original")
				} else {
					// Remove original authorization header
					delete(md, "authorization")
				}
			}
		}

		// Option 2: Check for user-id header (our current implementation)
		// Generate JWT from user-id and split it
		if userIDs := md.Get("user-id"); len(userIDs) > 0 {
			userID := userIDs[0]
			
			// Generate a JWT token for this user (simplified for demo)
			// In production, this would come from a proper auth token
			jwtToken, err := generateJWT(userID)
			if err != nil {
				log.WithError(err).Warn("failed to generate JWT for splitting")
			} else {
				if err := addSplitJWTToMetadata(md, jwtToken, log); err != nil {
					log.WithError(err).Warn("failed to split JWT token")
				} else {
					// Keep user-id for backwards compatibility
					// In production, you might remove it to save space
				}
			}
		}

		// Create new context with modified metadata
		ctx = metadata.NewOutgoingContext(ctx, md)

		// Continue with the RPC call
		return invoker(ctx, method, req, reply, cc, opts...)
	}
}

// addSplitJWTToMetadata splits a JWT token and adds individual components to metadata
func addSplitJWTToMetadata(md metadata.MD, jwtToken string, log *logrus.Logger) error {
	// Split the JWT token
	split, err := splitJWT(jwtToken)
	if err != nil {
		return err
	}

	// Add split components to metadata
	md.Set(headerJWTHeader, split.Header)
	md.Set(headerJWTIssuer, split.Issuer)
	md.Set(headerJWTSubject, split.Subject)
	md.Set(headerJWTIssuedAt, split.IssuedAt)
	md.Set(headerJWTExpiresAt, split.ExpiresAt)
	md.Set(headerJWTNotBefore, split.NotBefore)
	md.Set(headerJWTSignature, split.Signature)

	// Log metrics for research purposes
	if log.Level >= logrus.DebugLevel {
		metrics := getHeaderSizeMetrics(jwtToken, split)
		log.WithFields(logrus.Fields{
			"full_jwt_bytes":        metrics["full_jwt_size"],
			"split_uncompressed":    metrics["split_uncompressed"],
			"split_hpack_estimated": metrics["split_hpack_estimated"],
			"savings_bytes":         metrics["savings_bytes"],
			"savings_percent":       metrics["savings_percent"],
		}).Debug("JWT header splitting metrics")
	}

	return nil
}

// extractBearerToken extracts the token from "Bearer <token>" format
func extractBearerToken(authHeader string) string {
	const prefix = "Bearer "
	if len(authHeader) > len(prefix) && authHeader[:len(prefix)] == prefix {
		return authHeader[len(prefix):]
	}
	return ""
}

// UnaryServerInterceptorJWTReconstructor is a server-side interceptor that reconstructs
// JWT tokens from split headers (for validation)
func UnaryServerInterceptorJWTReconstructor(log *logrus.Logger) grpc.UnaryServerInterceptor {
	return func(
		ctx context.Context,
		req interface{},
		info *grpc.UnaryServerInfo,
		handler grpc.UnaryHandler,
	) (interface{}, error) {
		// Check if JWT splitting is enabled
		if !jwtSplittingEnabled() {
			// Pass through without modification
			return handler(ctx, req)
		}

		// Get incoming metadata
		md, ok := metadata.FromIncomingContext(ctx)
		if !ok {
			// No metadata, continue
			return handler(ctx, req)
		}

		// Check if we have split JWT headers
		if hasSplitJWT(md) {
			// Reconstruct the JWT token
			split := &SplitJWTHeaders{
				Header:    getMetadataValue(md, headerJWTHeader),
				Issuer:    getMetadataValue(md, headerJWTIssuer),
				Subject:   getMetadataValue(md, headerJWTSubject),
				IssuedAt:  getMetadataValue(md, headerJWTIssuedAt),
				ExpiresAt: getMetadataValue(md, headerJWTExpiresAt),
				NotBefore: getMetadataValue(md, headerJWTNotBefore),
				Signature: getMetadataValue(md, headerJWTSignature),
			}

			jwtToken, err := reconstructJWT(split)
			if err != nil {
				log.WithError(err).Warn("failed to reconstruct JWT from split headers")
			} else {
				// Validate the reconstructed JWT
				claims, err := validateJWT(jwtToken)
				if err != nil {
					log.WithError(err).Warn("reconstructed JWT validation failed")
				} else {
					// Add validated user info to context
					log.WithFields(logrus.Fields{
						"user_id": claims.UserID,
						"method":  info.FullMethod,
					}).Debug("JWT reconstructed and validated from split headers")
				}
			}
		}

		// Continue with the RPC call
		return handler(ctx, req)
	}
}

// hasSplitJWT checks if the metadata contains split JWT headers
func hasSplitJWT(md metadata.MD) bool {
	return len(md.Get(headerJWTHeader)) > 0 &&
		len(md.Get(headerJWTSignature)) > 0
}

// getMetadataValue safely gets a single value from metadata
func getMetadataValue(md metadata.MD, key string) string {
	values := md.Get(key)
	if len(values) > 0 {
		return values[0]
	}
	return ""
}
