package main

import (
	"context"
	"strings"

	"google.golang.org/grpc"
	"google.golang.org/grpc/metadata"
)

// Context key for storing JWT token
type ctxKeyJWT struct{}

// jwtUnaryServerInterceptor extracts JWT from incoming metadata and stores in context
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
		components := &JWTComponents{
			Static:    md.Get("x-jwt-static")[0],
			Session:   md.Get("x-jwt-session")[0],
			Dynamic:   md.Get("x-jwt-dynamic")[0],
			Signature: md.Get("x-jwt-sig")[0],
		}

		// Calculate actual compressed size (the size on the wire)
		compressedSize := len(components.Static) + len(components.Session) + len(components.Dynamic) + len(components.Signature)

		// Reassemble JWT from components
		reassembled, err := ReassembleJWT(components)
		if err != nil {
			log.Warnf("Failed to reassemble JWT: %v", err)
			return handler(ctx, req) // Continue without JWT
		}
		jwtToken = reassembled
		log.Infof("[JWT-FLOW] Checkout Service ← Frontend: Received compressed JWT (%d bytes compressed from %d bytes) via %s", compressedSize, len(jwtToken), info.FullMethod)

	} else if authHeaders := md.Get("authorization"); len(authHeaders) > 0 {
		// Standard format: "Bearer <token>"
		jwtToken = strings.TrimPrefix(authHeaders[0], "Bearer ")
		log.Infof("[JWT-FLOW] Checkout Service ← Frontend: Received full JWT (%d bytes) via %s", len(jwtToken), info.FullMethod)
	}

	// Store JWT in context for client interceptor to forward
	if jwtToken != "" {
		ctx = context.WithValue(ctx, ctxKeyJWT{}, jwtToken)
	}

	return handler(ctx, req)
}

// jwtStreamServerInterceptor extracts JWT from incoming stream metadata
func jwtStreamServerInterceptor(srv interface{}, ss grpc.ServerStream, info *grpc.StreamServerInfo, handler grpc.StreamHandler) error {
	ctx := ss.Context()
	md, ok := metadata.FromIncomingContext(ctx)
	if !ok {
		return handler(srv, ss)
	}

	var jwtToken string

	// Check for compressed JWT format
	if staticHeaders := md.Get("x-jwt-static"); len(staticHeaders) > 0 {
		components := &JWTComponents{
			Static:    md.Get("x-jwt-static")[0],
			Session:   md.Get("x-jwt-session")[0],
			Dynamic:   md.Get("x-jwt-dynamic")[0],
			Signature: md.Get("x-jwt-sig")[0],
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
		ctx = context.WithValue(ctx, ctxKeyJWT{}, jwtToken)
	}

	return handler(srv, &wrappedServerStream{ServerStream: ss, ctx: ctx})
}

// wrappedServerStream wraps a grpc.ServerStream with a custom context
type wrappedServerStream struct {
	grpc.ServerStream
	ctx context.Context
}

func (w *wrappedServerStream) Context() context.Context {
	return w.ctx
}

// jwtUnaryClientInterceptor forwards JWT from incoming request to outgoing gRPC calls
func jwtUnaryClientInterceptor(ctx context.Context, method string, req, reply interface{}, cc *grpc.ClientConn, invoker grpc.UnaryInvoker, opts ...grpc.CallOption) error {
	// Get JWT from context (set by server interceptor)
	jwtToken, ok := ctx.Value(ctxKeyJWT{}).(string)
	if !ok || jwtToken == "" {
		// No JWT in context, invoke without adding headers
		return invoker(ctx, method, req, reply, cc, opts...)
	}

	// Check if compression is enabled
	if IsJWTCompressionEnabled() {
		// Decompose JWT for HPACK compression
		components, err := DecomposeJWT(jwtToken)
		if err != nil {
			// Fallback to full JWT
			log.Warnf("Failed to decompose JWT, using full token: %v", err)
			ctx = metadata.AppendToOutgoingContext(ctx, "authorization", "Bearer "+jwtToken)
		} else {
			// Forward as compressed headers with HPACK indexing control
			// Static and Session: Allow HPACK caching
			ctx = metadata.AppendToOutgoingContext(ctx,
				"x-jwt-static", components.Static,
				"x-jwt-session", components.Session)
			
			// Dynamic and Signature: Prevent HPACK caching (won't be indexed)
			ctx = metadata.AppendToOutgoingContext(ctx,
				"x-jwt-dynamic", components.Dynamic,
				"x-jwt-sig", components.Signature)
			
			sizes := GetJWTComponentSizes(components)
			log.Infof("[JWT-FLOW] Checkout Service → %s: Forwarding compressed JWT (total=%db, static/session=CACHED, dynamic/sig=NO-CACHE)", method, sizes["total"])
		}
	} else {
		// JWT COMPRESSION DISABLED: Forward as standard authorization header
		log.Infof("[JWT-FLOW] Checkout Service → %s: Forwarding full JWT in authorization header (%d bytes)", method, len(jwtToken))
		ctx = metadata.AppendToOutgoingContext(ctx, "authorization", "Bearer "+jwtToken)
	}

	return invoker(ctx, method, req, reply, cc, opts...)
}

// jwtStreamClientInterceptor forwards JWT from incoming request to outgoing gRPC stream calls
func jwtStreamClientInterceptor(ctx context.Context, desc *grpc.StreamDesc, cc *grpc.ClientConn, method string, streamer grpc.Streamer, opts ...grpc.CallOption) (grpc.ClientStream, error) {
	// Get JWT from context
	jwtToken, ok := ctx.Value(ctxKeyJWT{}).(string)
	if !ok || jwtToken == "" {
		return streamer(ctx, desc, cc, method, opts...)
	}

	// Check if compression is enabled
	if IsJWTCompressionEnabled() {
		components, err := DecomposeJWT(jwtToken)
		if err != nil {
			log.Warnf("Failed to decompose JWT for stream, using full token: %v", err)
			ctx = metadata.AppendToOutgoingContext(ctx, "authorization", "Bearer "+jwtToken)
		} else {
			// Forward with HPACK indexing control
			ctx = metadata.AppendToOutgoingContext(ctx,
				"x-jwt-static", components.Static,
				"x-jwt-session", components.Session)
			
			// Dynamic and signature without indexing
			ctx = metadata.AppendToOutgoingContext(ctx,
				"x-jwt-dynamic", components.Dynamic,
				"x-jwt-sig", components.Signature)
			
			log.Infof("[JWT-FLOW] Checkout Service → %s (stream): Forwarding compressed JWT (static/session=CACHED, dynamic/sig=NO-CACHE)", method)
		}
	} else {
		// JWT COMPRESSION DISABLED: Forward as standard authorization header
		log.Infof("[JWT-FLOW] Checkout Service → %s (stream): Forwarding full JWT in authorization header (%d bytes)", method, len(jwtToken))
		ctx = metadata.AppendToOutgoingContext(ctx, "authorization", "Bearer "+jwtToken)
	}

	return streamer(ctx, desc, cc, method, opts...)
}
