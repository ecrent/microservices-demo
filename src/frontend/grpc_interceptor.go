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

	"google.golang.org/grpc"
	"google.golang.org/grpc/metadata"
)

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
		// Get JWT claims from context (set by ensureJWT middleware)
		if claims, ok := getJWTFromContext(ctx); ok {
			// Generate token string from claims (we need to re-sign it)
			// Or better: get the token string from the request
			// For now, let's get it from the HTTP request cookie
			
			// Check if we have a JWT token string in the context
			if tokenStr, ok := ctx.Value(ctxKeyJWTToken{}).(string); ok && tokenStr != "" {
				// Add JWT to gRPC metadata
				md := metadata.Pairs("authorization", "Bearer "+tokenStr)
				ctx = metadata.NewOutgoingContext(ctx, md)
			} else if claims != nil {
				// Fallback: regenerate token from claims
				// This shouldn't normally happen but provides a safety net
				tokenStr, err := generateJWTFromClaims(claims)
				if err == nil {
					md := metadata.Pairs("authorization", "Bearer "+tokenStr)
					ctx = metadata.NewOutgoingContext(ctx, md)
				}
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
		// Get JWT token from context
		if tokenStr, ok := ctx.Value(ctxKeyJWTToken{}).(string); ok && tokenStr != "" {
			// Add JWT to gRPC metadata
			md := metadata.Pairs("authorization", "Bearer "+tokenStr)
			ctx = metadata.NewOutgoingContext(ctx, md)
		}

		// Invoke the streaming RPC with the modified context
		return streamer(ctx, desc, cc, method, opts...)
	}
}
