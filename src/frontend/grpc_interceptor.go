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
			log.Infof("[JWT-FLOW] Frontend → %s: Skipping JWT (public service)", method)
			return invoker(ctx, method, req, reply, cc, opts...)
		}
		
		// Get JWT token string from context
		if tokenStr, ok := ctx.Value(ctxKeyJWTToken{}).(string); ok && tokenStr != "" {
			
			// Check if JWT compression is enabled
			if IsJWTCompressionEnabled() {
				// Decompose JWT into cacheable components
				components, err := DecomposeJWT(tokenStr)
				if err != nil {
					// Fallback to full JWT if decomposition fails
					log.Warnf("Failed to decompose JWT, using full token: %v", err)
					md := metadata.Pairs("authorization", "Bearer "+tokenStr)
					ctx = metadata.NewOutgoingContext(ctx, md)
				} else {
					// Add compressed headers (HPACK will cache these efficiently)
					md := metadata.Pairs(
						"x-jwt-static", components.Static,
						"x-jwt-session", components.Session,
						"x-jwt-dynamic", components.Dynamic,
						"x-jwt-sig", components.Signature,
					)
					ctx = metadata.NewOutgoingContext(ctx, md)
					
					// Log JWT flow
					sizes := GetJWTComponentSizes(components)
					log.Infof("[JWT-FLOW] Frontend → %s: Sending compressed JWT (total=%db)", method, sizes["total"])
				}
			} else {
				// Standard behavior: send full JWT
				log.Infof("[JWT-FLOW] Frontend → %s: Sending full JWT", method)
				md := metadata.Pairs("authorization", "Bearer "+tokenStr)
				ctx = metadata.NewOutgoingContext(ctx, md)
			}
		} else if claims, ok := getJWTFromContext(ctx); ok && claims != nil {
			// Fallback: regenerate token from claims if token string not available
			tokenStr, err := generateJWTFromClaims(claims)
			if err == nil {
				md := metadata.Pairs("authorization", "Bearer "+tokenStr)
				ctx = metadata.NewOutgoingContext(ctx, md)
			}
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
		// Skip JWT for services that don't need it (performance optimization)
		if shouldSkipJWT(method) {
			log.Debugf("Skipping JWT for public streaming service: %s", method)
			return streamer(ctx, desc, cc, method, opts...)
		}
		
		// Get JWT token from context
		if tokenStr, ok := ctx.Value(ctxKeyJWTToken{}).(string); ok && tokenStr != "" {
			
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
					// Add compressed headers
					md := metadata.Pairs(
						"x-jwt-static", components.Static,
						"x-jwt-session", components.Session,
						"x-jwt-dynamic", components.Dynamic,
						"x-jwt-sig", components.Signature,
					)
					ctx = metadata.NewOutgoingContext(ctx, md)
				}
			} else {
				// Standard behavior: send full JWT
				md := metadata.Pairs("authorization", "Bearer "+tokenStr)
				ctx = metadata.NewOutgoingContext(ctx, md)
			}
		}

		// Invoke the streaming RPC with the modified context
		return streamer(ctx, desc, cc, method, opts...)
	}
}
