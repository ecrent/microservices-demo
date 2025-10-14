package main

import (
	"context"
	"strings"

	"google.golang.org/grpc"
	"google.golang.org/grpc/metadata"
)

// jwtUnaryServerInterceptor extracts and reassembles JWT from incoming metadata
func jwtUnaryServerInterceptor(ctx context.Context, req interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (interface{}, error) {
	md, ok := metadata.FromIncomingContext(ctx)
	if !ok {
		// No metadata, continue without JWT
		return handler(ctx, req)
	}

	var jwtToken string

	// Check for compressed JWT format (x-jwt-* headers)
	if staticHeaders := md.Get("x-jwt-static"); len(staticHeaders) > 0 {
		// Compressed format detected
		var dynamic, signature string
		
		// Try to get -bin headers first (gRPC auto-decodes them)
		if dynamicBinHeaders := md.Get("x-jwt-dynamic-bin"); len(dynamicBinHeaders) > 0 {
			// gRPC automatically base64-decodes -bin headers
			dynamic = dynamicBinHeaders[0]
		} else if dynamicHeaders := md.Get("x-jwt-dynamic"); len(dynamicHeaders) > 0 {
			dynamic = dynamicHeaders[0]
		}
		
		if sigBinHeaders := md.Get("x-jwt-sig-bin"); len(sigBinHeaders) > 0 {
			// gRPC automatically base64-decodes -bin headers
			signature = sigBinHeaders[0]
		} else if sigHeaders := md.Get("x-jwt-sig"); len(sigHeaders) > 0 {
			signature = sigHeaders[0]
		}
		
		components := &JWTComponents{
			Static:    staticHeaders[0],
			Session:   md.Get("x-jwt-session")[0],
			Dynamic:   dynamic,
			Signature: signature,
		}

		// Reassemble JWT from components
		reassembled, err := ReassembleJWT(components)
		if err != nil {
			log.Warnf("Failed to reassemble JWT: %v", err)
			return handler(ctx, req) // Continue without JWT
		}
		jwtToken = reassembled
		sizes := GetJWTComponentSizes(components)
		log.Infof("[JWT-FLOW] Shipping Service ← Checkout: Received compressed JWT (%d bytes) via %s", sizes["total"], info.FullMethod)

	} else if authHeaders := md.Get("authorization"); len(authHeaders) > 0 {
		// Standard format: "Bearer <token>"
		jwtToken = strings.TrimPrefix(authHeaders[0], "Bearer ")
		log.Infof("[JWT-FLOW] Shipping Service ← Checkout: Received full JWT (%d bytes) via %s", len(jwtToken), info.FullMethod)
	}

	// JWT received and reassembled (no forwarding needed for shippingservice)
	if jwtToken == "" {
		// Don't log health checks - they're infrastructure probes
		if !strings.Contains(info.FullMethod, "Health/Check") {
			log.Infof("[JWT-FLOW] Shipping Service: No JWT received for %s", info.FullMethod)
		}
	}

	return handler(ctx, req)
}

// jwtStreamServerInterceptor extracts and reassembles JWT from incoming stream metadata
func jwtStreamServerInterceptor(srv interface{}, ss grpc.ServerStream, info *grpc.StreamServerInfo, handler grpc.StreamHandler) error {
	ctx := ss.Context()
	md, ok := metadata.FromIncomingContext(ctx)
	if !ok {
		return handler(srv, ss)
	}

	var jwtToken string

	// Check for compressed JWT format
	if staticHeaders := md.Get("x-jwt-static"); len(staticHeaders) > 0 {
		var dynamic, signature string
		
		// Try to get -bin headers first (gRPC auto-decodes them)
		if dynamicBinHeaders := md.Get("x-jwt-dynamic-bin"); len(dynamicBinHeaders) > 0 {
			// gRPC automatically base64-decodes -bin headers
			dynamic = dynamicBinHeaders[0]
		} else if dynamicHeaders := md.Get("x-jwt-dynamic"); len(dynamicHeaders) > 0 {
			dynamic = dynamicHeaders[0]
		}
		
		if sigBinHeaders := md.Get("x-jwt-sig-bin"); len(sigBinHeaders) > 0 {
			// gRPC automatically base64-decodes -bin headers
			signature = sigBinHeaders[0]
		} else if sigHeaders := md.Get("x-jwt-sig"); len(sigHeaders) > 0 {
			signature = sigHeaders[0]
		}
		
		components := &JWTComponents{
			Static:    staticHeaders[0],
			Session:   md.Get("x-jwt-session")[0],
			Dynamic:   dynamic,
			Signature: signature,
		}

		reassembled, err := ReassembleJWT(components)
		if err != nil {
			log.Warnf("Failed to reassemble JWT in stream: %v", err)
			return handler(srv, ss)
		}
		jwtToken = reassembled
	} else if authHeaders := md.Get("authorization"); len(authHeaders) > 0 {
		jwtToken = strings.TrimPrefix(authHeaders[0], "Bearer ")
	}

	if jwtToken != "" {
		log.Infof("JWT received for stream %s (compressed=%v)", info.FullMethod, len(md.Get("x-jwt-static")) > 0)
	}

	return handler(srv, ss)
}
