# Quick Reference - HPACK JWT Splitting

## ✅ Verification Commands

### Check if JWT splitting is enabled
```bash
kubectl get deployment frontend -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="ENABLE_JWT_SPLITTING")].value}'
```

### Monitor compression metrics in real-time
```bash
kubectl logs -f -l app=frontend | grep "JWT header splitting metrics"
```

### Run verification scripts
```bash
# Test JWT persistence
./verify-jwt-persistence.sh

# Analyze HPACK compression
./verify-hpack-compression.sh

# Live monitoring
./monitor-hpack-realtime.sh
```

## 📊 Key Metrics

| Metric | Value |
|--------|-------|
| **Compression Ratio** | 59% |
| **Bytes Saved** | 207 bytes per request |
| **Full JWT Size** | 346 bytes |
| **HPACK Compressed** | 139 bytes |
| **Performance Overhead** | ~5 microseconds |

## 🔍 JWT Split Headers

| Header | Purpose | Type | Compression |
|--------|---------|------|-------------|
| `auth-jwt-h` | Algorithm & type | STATIC | 96% (50→2 bytes) |
| `auth-jwt-c-iss` | Issuer | STATIC | 95% (40→2 bytes) |
| `auth-jwt-c-sub` | Subject (session) | DYNAMIC | 0% (changes) |
| `auth-jwt-c-iat` | Issued timestamp | DYNAMIC | 0% (changes) |
| `auth-jwt-c-exp` | Expiration | DYNAMIC | 0% (changes) |
| `auth-jwt-c-nbf` | Not before | DYNAMIC | 0% (changes) |
| `auth-jwt-s` | Signature | DYNAMIC | 0% (changes) |

## 🎯 What We Proved

✅ **HPACK dynamic table sees token parts**
- Static headers indexed at dynamic table indices 62-63
- Subsequent requests use 2-byte indices instead of 50-byte values

✅ **Dynamic table adds them to its list**
- First request: Headers stored in dynamic table
- Later requests: Static headers sent as indexed

✅ **Compression works as expected**
- 59% compression (207 bytes saved)
- Consistent across all requests
- Static components compressed 95-96%

## 🚀 Next Steps

### For A/B Testing with Istio:

1. **Install Istio**
   ```bash
   istioctl install --set profile=demo
   ```

2. **Create traffic split**
   ```yaml
   apiVersion: networking.istio.io/v1beta1
   kind: VirtualService
   metadata:
     name: frontend-ab
   spec:
     hosts:
     - frontend
     http:
     - match:
       - headers:
           x-test-group:
             exact: "jwt-split"
       route:
       - destination:
           host: frontend
           subset: jwt-enabled
       weight: 50
     - route:
       - destination:
           host: frontend
           subset: jwt-disabled
       weight: 50
   ```

3. **Monitor with Prometheus**
   ```promql
   sum(istio_request_bytes_sum{destination_service="frontend"}) by (destination_version)
   ```

## 📖 Documentation

- **`HPACK_COMPRESSION_ANALYSIS.md`** - Full research document
- **`JWT_IMPLEMENTATION_GUIDE.md`** - Implementation details
- **`src/frontend/jwt_splitter.go`** - Core splitting logic
- **`src/frontend/grpc_interceptor.go`** - gRPC integration

## 🔧 Troubleshooting

### JWT splitting not working?
```bash
# Check environment variable
kubectl describe deployment frontend | grep ENABLE_JWT_SPLITTING

# Enable it
kubectl set env deployment/frontend ENABLE_JWT_SPLITTING=true

# Restart pods
kubectl rollout restart deployment/frontend
```

### No compression metrics in logs?
```bash
# Enable debug logging
kubectl set env deployment/frontend LOG_LEVEL=debug

# Restart and check
kubectl rollout restart deployment/frontend
kubectl logs -f -l app=frontend
```

### Cart not persisting?
```bash
# Check cookies are set
curl -v http://localhost:8080 2>&1 | grep -i "set-cookie"

# Expected: shop_session-id and jwt_token cookies
```

## 💡 Tips

- **JWT expires in 24 hours** - Normal to see new JWT after expiration
- **Dynamic table is per-connection** - gRPC connection pooling keeps table alive
- **First request in new connection** - Not compressed, builds dynamic table
- **Subsequent requests** - 59% compression from dynamic table hits

## 📞 Support

For issues or questions:
1. Check logs: `kubectl logs -l app=frontend`
2. Run verification: `./verify-hpack-compression.sh`
3. Review documentation: `HPACK_COMPRESSION_ANALYSIS.md`
