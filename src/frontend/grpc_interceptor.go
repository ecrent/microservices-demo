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
	"strings"

	"google.golang.org/grpc"
	"google.golang.org/grpc/metadata"
)

// shouldSkipJWT checks if the method doesn't need JWT (public/anonymous services)
func shouldSkipJWT(method string) bool {
	// Product Catalog Service - public product data, no user context needed
	if strings.Contains(method, "ProductCatalogService") {
		return true
	}
	// Currency Service - pure conversion, no user context needed
	if strings.Contains(method, "CurrencyService") {
		return true
	}
	// Ad Service - public ads, no user-specific targeting needed
	if strings.Contains(method, "AdService") {
		return true
	}
	// Recommendation Service - can work with anonymous users
	if strings.Contains(method, "RecommendationService") {
		return true
	}
	return false
}

// jwtUnaryClientInterceptor adds JWT to outgoing gRPC calls
func jwtUnaryClientInterceptor() grpc.UnaryClientInterceptor {
	return func(
		ctx context.Context,
		method string,
		req, reply interface{},
		cc *grpc.ClientConn,
		invoker grpc.UnaryInvoker,
		opts ...grpc.CallOption,
	) error {
		// Skip JWT for services that don't need it (performance optimization)
		if shouldSkipJWT(method) {
			return invoker(ctx, method, req, reply, cc, opts...)
		}

		tokenStr, ok := ctx.Value(ctxKeyJWTToken{}).(string)
		if !ok || tokenStr == "" {
			// Fallback for safety, though should not happen in normal flow
			if claims, ok := getJWTFromContext(ctx); ok && claims != nil {
				var err error
				tokenStr, err = generateJWTFromClaims(claims)
				if err != nil {
					log.Warnf("No JWT token string in context and failed to regenerate from claims for method %s. Proceeding without JWT.", method)
					return invoker(ctx, method, req, reply, cc, opts...)
				}
			} else {
				log.Warnf("No JWT token string or claims in context for method %s. Proceeding without JWT.", method)
				return invoker(ctx, method, req, reply, cc, opts...)
			}
		}

		// Check if JWT compression is enabled.
		if IsJWTCompressionEnabled() {
			// JWT COMPRESSION ENABLED: Decompose JWT into cacheable components
			components, err := DecomposeJWT(tokenStr)
			if err != nil {
				// Fallback to full JWT if decomposition fails
				log.Warnf("Failed to decompose JWT, using full token: %v", err)
				md := metadata.Pairs("authorization", "Bearer "+tokenStr)
				ctx = metadata.NewOutgoingContext(ctx, md)
			} else {
				// Add compressed JWT headers with -bin suffix for dynamic components
				md := metadata.Pairs(
					"x-jwt-static", components.Static,
					"x-jwt-session", components.Session,
					"x-jwt-dynamic-bin", components.Dynamic,
					"x-jwt-sig-bin", components.Signature,
				)
				ctx = metadata.NewOutgoingContext(ctx, md)
				sizes := GetJWTComponentSizes(components)
				log.Infof("[JWT-FLOW] Frontend → %s: Sending DECOMPOSED JWT (total=%db)", method, sizes["total"])
			}
		} else {
			// JWT COMPRESSION DISABLED: Send full JWT in authorization header
			log.Infof("[JWT-FLOW] Frontend → %s: Sending FULL JWT in authorization header (%d bytes)", method, len(tokenStr))
			md := metadata.Pairs("authorization", "Bearer "+tokenStr)
			ctx = metadata.NewOutgoingContext(ctx, md)
		}

		// Invoke the RPC with the modified context
		return invoker(ctx, method, req, reply, cc, opts...)
	}
}

// jwtStreamClientInterceptor adds JWT to outgoing streaming gRPC calls
func jwtStreamClientInterceptor() grpc.StreamClientInterceptor {
	return func(
		ctx context.Context,
		desc *grpc.StreamDesc,
		cc *grpc.ClientConn,
		method string,
		streamer grpc.Streamer,
		opts ...grpc.CallOption,
	) (grpc.ClientStream, error) {
		// Skip JWT for services that don't need it
		if shouldSkipJWT(method) {
			return streamer(ctx, desc, cc, method, opts...)
		}

		tokenStr, ok := ctx.Value(ctxKeyJWTToken{}).(string)
		if !ok || tokenStr == "" {
			log.Warnf("No JWT token string in context for stream method %s. Proceeding without JWT.", method)
			return streamer(ctx, desc, cc, method, opts...)
		}

		// Check if JWT compression is enabled
		if IsJWTCompressionEnabled() {
			// Decompose JWT into cacheable components
			components, err := DecomposeJWT(tokenStr)
			if err != nil {
				// Fallback to full JWT if decomposition fails
				log.Warnf("Failed to decompose JWT for stream, using full token: %v", err)
				md := metadata.Pairs("authorization", "Bearer "+tokenStr)
				ctx = metadata.NewOutgoingContext(ctx, md)
			} else {
				// Add compressed JWT headers
				md := metadata.Pairs(
					"x-jwt-static", components.Static,
					"x-jwt-session", components.Session,
					"x-jwt-dynamic-bin", components.Dynamic,
					"x-jwt-sig-bin", components.Signature,
				)
				ctx = metadata.NewOutgoingContext(ctx, md)
				log.Infof("[JWT-FLOW] Frontend → %s (stream): Sending DECOMPOSED JWT", method)
			}
		} else {
			// JWT COMPRESSION DISABLED: Send full JWT in authorization header
			log.Infof("[JWT-FLOW] Frontend → %s (stream): Sending FULL JWT in authorization header (%d bytes)", method, len(tokenStr))
			md := metadata.Pairs("authorization", "Bearer "+tokenStr)
			ctx = metadata.NewOutgoingContext(ctx, md)
		}

		// Invoke the streaming RPC with the modified context
		return streamer(ctx, desc, cc, method, opts...)
	}
}
