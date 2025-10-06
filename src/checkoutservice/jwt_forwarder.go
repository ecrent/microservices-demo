package main

import (
	"context"

	"google.golang.org/grpc"
	"google.golang.org/grpc/metadata"
)

// jwtUnaryClientInterceptor forwards JWT from incoming request to outgoing gRPC calls
func jwtUnaryClientInterceptor(ctx context.Context, method string, req, reply interface{}, cc *grpc.ClientConn, invoker grpc.UnaryInvoker, opts ...grpc.CallOption) error {
	// Extract JWT from incoming metadata
	md, ok := metadata.FromIncomingContext(ctx)
	if ok {
		authHeaders := md.Get("authorization")
		if len(authHeaders) > 0 {
			// Forward the JWT to the outgoing request
			ctx = metadata.AppendToOutgoingContext(ctx, "authorization", authHeaders[0])
		}
	}

	return invoker(ctx, method, req, reply, cc, opts...)
}

// jwtStreamClientInterceptor forwards JWT from incoming request to outgoing gRPC stream calls
func jwtStreamClientInterceptor(ctx context.Context, desc *grpc.StreamDesc, cc *grpc.ClientConn, method string, streamer grpc.Streamer, opts ...grpc.CallOption) (grpc.ClientStream, error) {
	// Extract JWT from incoming metadata
	md, ok := metadata.FromIncomingContext(ctx)
	if ok {
		authHeaders := md.Get("authorization")
		if len(authHeaders) > 0 {
			// Forward the JWT to the outgoing request
			ctx = metadata.AppendToOutgoingContext(ctx, "authorization", authHeaders[0])
		}
	}

	return streamer(ctx, desc, cc, method, opts...)
}
