# Current JWT & Header Baseline Measurements

## 📏 Current State (Before Shredding)

### JWT Token Structure
```json
{
  "sub": "608637cf-66ec-415d-b32c-1cd1a63df45d",
  "session_id": "608637cf-66ec-415d-b32c-1cd1a63df45d",
  "iss": "online-boutique-frontend",
  "exp": 1759774182,
  "nbf": 1759687782,
  "iat": 1759687782
}
```

### Token Size Breakdown

| Component | Size | Notes |
|-----------|------|-------|
| Header | ~36 bytes | `{"alg":"HS256","typ":"JWT"}` base64 |
| Payload | ~180 bytes | Claims (see above) base64 |
| Signature | ~43 bytes | HMAC-SHA256 signature base64 |
| **Total JWT** | **~259 bytes** | Without "Bearer " prefix |
| **With Bearer** | **~266 bytes** | "Bearer " + token |

### Current gRPC Metadata (Per Service Call)

```go
metadata: {
  "user-id": "608637cf-66ec-415d-b32c-1cd1a63df45d",  // 36 bytes
  "x-user-id": "608637cf-66ec-415d-b32c-1cd1a63df45d" // 36 bytes (duplicate)
}
```

**Current Metadata Size**: ~72 bytes (uncompressed)

### Service-to-Service Communication Frequency

Based on a typical user checkout flow:

```
1 Frontend Request
    ├─→ 1x ProductCatalogService (get product)
    ├─→ 1x CartService (get cart)
    │       └─→ 1x Redis (get cart data)
    ├─→ 1x RecommendationService (get recommendations)
    │       └─→ 1x ProductCatalogService (get recommended products)
    └─→ 1x CheckoutService (place order)
            ├─→ 1x CartService (get cart)
            ├─→ 1x PaymentService (charge card)
            ├─→ 1x ShippingService (ship items)
            ├─→ 1x CurrencyService (convert currency)
            └─→ 1x EmailService (send confirmation)

Total gRPC calls: ~12 per user action
Total metadata transferred: ~12 × 72 bytes = ~864 bytes per action
```

---

## 🎯 Optimization Targets

### Where JWT/Metadata is Currently Used:

1. **Frontend → CartService**
   - `getCart(userId)`
   - `addToCart(userId, item)`
   - `emptyCart(userId)`
   
2. **Frontend → RecommendationService**
   - `getRecommendations(userId, productIds)`

3. **Frontend → CheckoutService**
   - `placeOrder(userId, orderDetails)`

### Optimization Opportunity:

```
Current:  12 calls × 72 bytes = 864 bytes/request
Target:   12 calls × 15 bytes = 180 bytes/request
Savings:  684 bytes/request (79% reduction)
```

With 1000 requests/sec:
- **Current**: 864 KB/s metadata overhead
- **Target**: 180 KB/s metadata overhead
- **Savings**: 684 KB/s = **~5.4 Mb/s** bandwidth saved

---

## 🔬 Measurement Plan

### Baseline Metrics to Collect

#### 1. Header Size Metrics
```bash
# Measure actual gRPC metadata size
# Tool: grpcurl with verbose output
grpcurl -v -d '{"user_id":"test"}' \
  -H "user-id: 608637cf-66ec-415d-b32c-1cd1a63df45d" \
  localhost:7070 hipstershop.CartService/GetCart
```

#### 2. Network Bandwidth
```bash
# Monitor network traffic
kubectl exec -it deployment/frontend -- sh
apk add tcpdump
tcpdump -i any -s 0 -w /tmp/traffic.pcap port 7070

# Analyze with Wireshark or tshark
```

#### 3. HPACK Compression Ratio
```bash
# HTTP/2 frames analysis
# Need to decrypt TLS or use service mesh observability
```

---

## 📊 Comparison Matrix

### Full JWT in Metadata (Option 1)
```go
metadata: {
  "authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user-id": "608637cf-66ec-415d-b32c-1cd1a63df45d"
}
```
- **Size**: ~338 bytes
- **Pros**: Full token verification at each service
- **Cons**: Large overhead, repeated token transmission

### Shredded - Minimal (Option 2)
```go
metadata: {
  "uid": "608637cf"  // First 8 chars
}
```
- **Size**: ~15 bytes
- **Reduction**: 95.6% vs full JWT
- **Pros**: Minimal bandwidth
- **Cons**: No verification, collision risk

### Shredded - Hash Reference (Option 3)
```go
metadata: {
  "tid": "a3f2b1c4",      // Token hash (8 chars)
  "uid": "608637cf",       // User ID prefix
  "exp": "1759774182"      // Expiry timestamp
}
```
- **Size**: ~48 bytes
- **Reduction**: 85.8% vs full JWT
- **Pros**: Balance of size and verifiability
- **Cons**: Need hash validation logic

### Current Implementation (Baseline)
```go
metadata: {
  "user-id": "608637cf-66ec-415d-b32c-1cd1a63df45d",
  "x-user-id": "608637cf-66ec-415d-b32c-1cd1a63df45d"
}
```
- **Size**: ~72 bytes
- **Reduction**: N/A (baseline)
- **Pros**: Simple, full user ID
- **Cons**: Duplicate data, no verification

---

## 🎯 Research Questions to Answer

1. **HPACK Efficiency**:
   - How much does HPACK already compress our metadata?
   - Does shredding still help after HPACK compression?
   - What's the compression ratio for repeated vs unique headers?

2. **Performance Impact**:
   - Does smaller headers actually reduce latency?
   - What's the CPU trade-off for compression?
   - How does this scale with request volume?

3. **Optimal Strategy**:
   - Which shredding strategy gives best ROI?
   - Is there a sweet spot between size and functionality?
   - What about security implications?

4. **Service Mesh Overhead**:
   - How does Istio proxy affect the results?
   - Does sidecars benefit from smaller headers?
   - What's the memory/CPU impact?

---

## 🛠️ Quick Baseline Test

Run this to get current measurements:

```bash
# 1. Check current metadata in logs
kubectl logs -f deployment/cartservice | grep -i "user-id"

# 2. Monitor network traffic
kubectl exec deployment/frontend -- sh -c '
  apk add tcpdump 2>/dev/null
  timeout 10 tcpdump -i any -c 100 -s 0 port 7070 -w - | wc -c
'

# 3. Load test current implementation
kubectl exec deployment/loadgenerator -- sh -c '
  echo "Current load: $(ps aux | grep locust | wc -l) processes"
'
```

---

## 📈 Success Criteria

Your research will be successful if you can demonstrate:

1. ✅ **Measurable header size reduction** (target: >50%)
2. ✅ **Quantified HPACK compression benefit** (before/after comparison)
3. ✅ **Network performance improvement** (bandwidth/latency)
4. ✅ **Istio A/B test results** with statistical significance
5. ✅ **Practical recommendations** for production use

---

## Next Steps

Ready to implement JWT token shredding? Let me know which shredding strategy you want to start with!

**Recommended**: Start with **Option 3 (Hash Reference)** as it balances optimization with security.
