# JWT Header Splitting for HPACK Optimization

## 🎯 Strategy: Maximize HPACK Dynamic Table Efficiency

Instead of sending the entire JWT as one header, split it into multiple headers based on cacheability:

### Header Split Strategy

```
Original JWT:
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyLTEyMzQ1Iiwi...

Split into:
auth-jwt-h:       eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9        (header)
auth-jwt-c-iss:   online-boutique-frontend                      (issuer)
auth-jwt-c-sub:   608637cf-66ec-415d-b32c-1cd1a63df45d         (subject/user)
auth-jwt-c-iat:   1759687782                                    (issued at)
auth-jwt-c-exp:   1759774182                                    (expiration)
auth-jwt-c-nbf:   1759687782                                    (not before)
auth-jwt-s:       Hd9OAfwTtruKnf5YumBagbHxrAp8yoTlg19ZQuwMUfQ   (signature)
```

### HPACK Compression Benefits

#### Dynamic Table Caching

| Header | Cacheability | HPACK Benefit | Reasoning |
|--------|--------------|---------------|-----------|
| `auth-jwt-h` | **Highly Cacheable** | First request: ~40 bytes<br>Subsequent: ~2 bytes | Same for all users, all sessions |
| `auth-jwt-c-iss` | **Highly Cacheable** | First request: ~30 bytes<br>Subsequent: ~2 bytes | Same issuer for all tokens |
| `auth-jwt-c-sub` | **Session Cacheable** | First request: ~45 bytes<br>Same user: ~2 bytes | Same per user session |
| `auth-jwt-c-iat` | **Not Cacheable** | Always: ~15 bytes | Changes every token |
| `auth-jwt-c-exp` | **Not Cacheable** | Always: ~15 bytes | Changes every token |
| `auth-jwt-c-nbf` | **Not Cacheable** | Always: ~15 bytes | Changes every token |
| `auth-jwt-s` | **Not Cacheable** | Always: ~45 bytes | Unique signature |

### Compression Comparison

#### Traditional (Single Header)
```
Request 1: Authorization: Bearer eyJ... (~266 bytes uncompressed)
  HPACK: ~266 bytes (first time, no cache benefit)
  
Request 2: Authorization: Bearer eyJ... (different token)
  HPACK: ~266 bytes (token changed, no cache benefit)
  
Request 3+: Same pattern, no compression improvement
  HPACK: ~266 bytes each
```

**Total for 10 requests**: ~2,660 bytes

#### Optimized (Split Headers with HPACK)
```
Request 1:
  auth-jwt-h: eyJhbGc... (~40 bytes → added to dynamic table)
  auth-jwt-c-iss: online-boutique-frontend (~30 bytes → added to dynamic table)
  auth-jwt-c-sub: user-123 (~45 bytes → added to dynamic table)
  auth-jwt-c-iat: 1759687782 (~15 bytes)
  auth-jwt-c-exp: 1759774182 (~15 bytes)
  auth-jwt-s: Hd9OAf... (~45 bytes)
  Total: ~190 bytes
  
Request 2 (same user, refreshed token):
  auth-jwt-h: [indexed] (~2 bytes, from dynamic table)
  auth-jwt-c-iss: [indexed] (~2 bytes, from dynamic table)
  auth-jwt-c-sub: [indexed] (~2 bytes, from dynamic table)
  auth-jwt-c-iat: 1759687800 (~15 bytes)
  auth-jwt-c-exp: 1759774200 (~15 bytes)
  auth-jwt-s: xYz123... (~45 bytes)
  Total: ~81 bytes (57% reduction!)
  
Request 3-10: Same pattern
  Total: ~81 bytes each
```

**Total for 10 requests**: ~919 bytes
**Savings**: ~1,741 bytes (65% reduction!)

---

## 🔧 Implementation Plan

### 1. gRPC Interceptor Architecture

```
Client (Frontend)
    ↓
[Unary Interceptor - JWT Splitter]
    ↓ Splits JWT into multiple headers
    ↓ Adds to outgoing metadata
    ↓
gRPC Client
    ↓ HTTP/2 with HPACK
    ↓ Dynamic table caching
    ↓
gRPC Server
    ↓
[Unary Interceptor - JWT Reconstructor]
    ↓ Reads split headers
    ↓ Reconstructs JWT
    ↓ Validates signature
    ↓
Backend Service Handler
```

### 2. Files to Create/Modify

#### New Files:
```
src/frontend/
├── grpc_interceptor.go          # Client-side interceptor
└── jwt_splitter.go              # JWT splitting logic

src/cartservice/src/
└── Interceptors/
    ├── JwtReconstructorInterceptor.cs  # Server-side interceptor

src/checkoutservice/
└── grpc_interceptor.go          # Server-side interceptor
```

#### Modified Files:
```
src/frontend/
├── main.go                      # Register client interceptor
└── rpc.go                       # Use interceptor in gRPC calls

src/cartservice/src/
└── Program.cs                   # Register server interceptor

src/checkoutservice/
└── main.go                      # Register server interceptor
```

---

## 📊 Expected Performance Gains

### Scenario: E-commerce Checkout Flow

```
User Journey:
1. View Cart (1 gRPC call to CartService)
2. Get Recommendations (1 gRPC call to RecommendationService)
3. Checkout (5 gRPC calls: Cart, Payment, Shipping, Currency, Email)

Total: 7 gRPC calls per checkout
```

#### Without Header Splitting:
```
7 calls × 266 bytes = 1,862 bytes per checkout
1,000 checkouts/min = 1.86 MB/min = 31 KB/sec
```

#### With Header Splitting + HPACK:
```
First call: 190 bytes
Next 6 calls: 81 bytes each = 486 bytes
Total: 676 bytes per checkout (64% reduction!)
1,000 checkouts/min = 0.68 MB/min = 11 KB/sec
Savings: 20 KB/sec bandwidth
```

### At Scale (10,000 req/sec):
- **Without**: 2.66 MB/sec = 21.3 Mbps
- **With**: 0.81 MB/sec = 6.5 Mbps
- **Savings**: 14.8 Mbps (69% reduction)

---

## 🎯 Advantages of This Approach

1. **HPACK Native**: Leverages existing HTTP/2 compression
2. **No Protocol Changes**: Standard gRPC metadata
3. **Selective Caching**: Different cache strategies per claim
4. **Backwards Compatible**: Can fall back to full JWT
5. **Service Mesh Friendly**: Istio/Envoy benefit from smaller headers
6. **Reduced Memory**: Smaller header tables in proxies

---

## 🔍 Additional Optimizations

### Header Naming Strategy

**Short Names** for better compression:
```
Instead of:        Use:
auth-jwt-header    → a-h
auth-jwt-c-iss     → a-i
auth-jwt-c-sub     → a-s
auth-jwt-c-exp     → a-e
auth-jwt-sig       → a-g
```

**Savings**: ~40 bytes per request (header name overhead)

### Huffman Encoding

HPACK uses Huffman encoding for header values:
- Common characters compress better
- Base64 is ~33% overhead already
- Could use base64url for better compression

### Static Table Utilization

HPACK has 61 predefined static entries. We could:
- Use standard header names that match static table
- Example: `:authority`, `:method`, `:path`

---

## 🧪 A/B Testing Scenarios

### Test 1: Baseline vs Split Headers
```
Control:    Single Authorization header
Variant A:  Split headers (7 headers)
Variant B:  Split headers + short names (7 headers)
```

### Test 2: Cache Hit Ratio
```
Measure HPACK dynamic table hit rate:
- Same user, multiple requests
- Different users, same service
- Cross-service calls
```

### Test 3: Performance Under Load
```
Load patterns:
- Sustained: 1,000 req/sec for 10 minutes
- Burst: 10,000 req/sec for 30 seconds
- Mixed: Varying load with different cache scenarios
```

---

## 🚀 Implementation Priority

### Phase 1: JWT Splitter (Client-side)
1. Create `jwt_splitter.go`
2. Implement header splitting logic
3. Create client interceptor
4. Test with one service (CartService)

### Phase 2: JWT Reconstructor (Server-side)
1. Implement for Go services (CheckoutService)
2. Implement for C# services (CartService)
3. Add validation logic
4. Handle missing headers gracefully

### Phase 3: Measurement
1. Add metrics collection
2. Measure header sizes before/after
3. Monitor HPACK compression ratios
4. Collect performance data

### Phase 4: A/B Testing
1. Deploy both versions
2. Use Istio for traffic splitting
3. Compare metrics
4. Analyze results

---

## 🎓 Research Questions

1. **What's the actual HPACK dynamic table hit rate?**
2. **How does the split strategy perform with varying session lengths?**
3. **What's the optimal number of headers to split into?**
4. **Does this benefit persist through Istio/Envoy proxies?**
5. **What's the CPU trade-off for splitting/reconstructing?**

---

Ready to implement the gRPC interceptors for JWT header splitting?
