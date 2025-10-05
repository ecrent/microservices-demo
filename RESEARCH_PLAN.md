# JWT Token Shredding & HPACK Compression Research Plan

## 🎯 Research Goal
Optimize header size in microservices communication by implementing JWT token shredding and measuring the impact of HPACK compression on network performance.

## 📊 Current State (Phase 1 - ✅ COMPLETE)

### What We Have:
✅ **Baseline JWT Implementation**
- JWT tokens generated at frontend gateway
- Tokens passed in HTTP Authorization headers (frontend)
- User ID extracted and passed to backend services via gRPC metadata
- Full token structure:
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
- Token size: ~300-400 bytes (base64 encoded)

### Current Communication Pattern:
```
Frontend (HTTP/1.1 + JWT)
    ↓
    ↓ gRPC metadata: {"user-id": "session-uuid"}
    ↓
Backend Services (gRPC/HTTP2)
    - CartService
    - CheckoutService
    - RecommendationService
    - PaymentService
    - ShippingService
```

---

## 🔬 Phase 2: JWT Token Shredding (NEXT)

### Concept: Token Shredding
Instead of passing the entire JWT token through the service mesh, we'll:

1. **Validate JWT at Gateway** (Frontend) ✅ Already doing this
2. **Extract Essential Claims** (user_id, roles, etc.)
3. **Pass Only Necessary Data** via gRPC metadata (minimize header size)
4. **Reconstruct/Validate** at each service if needed

### Implementation Strategy:

#### Option A: Minimal Metadata (Most Aggressive Shredding)
```
Current:
  metadata: {"user-id": "608637cf-66ec-415d-b32c-1cd1a63df45d"}
  Size: ~50 bytes

Shredded (Minimal):
  metadata: {"uid": "608637cf"}  // First 8 chars only
  Size: ~15 bytes
  Reduction: 70%
```

#### Option B: Hash-Based Reference
```
Shredded (Hash Reference):
  metadata: {
    "token-hash": "a3f2b1c4",  // Short hash
    "user-id": "608637cf"       // Shortened
  }
  Size: ~25 bytes
  Reduction: 50%
```

#### Option C: Token Claims Selection
```
Shredded (Selected Claims):
  metadata: {
    "uid": "608637cf",
    "exp": "1759774182",
    "scope": "user"
  }
  Size: ~40 bytes
  Reduction: 20%
```

### What to Implement:

1. **Frontend: Token Shredding Logic**
   - File: `src/frontend/jwt_shredder.go` (NEW)
   - Extract minimal claims from JWT
   - Create compressed metadata payload
   - Add shredding strategy configuration

2. **Backend: Claim Reconstruction** (Optional)
   - Verify shortened user IDs
   - Validate token hashes
   - Log metadata size for comparison

3. **Metrics Collection**
   - Header size before/after shredding
   - Network bandwidth usage
   - Latency impact

---

## 🔬 Phase 3: HPACK Compression Analysis

### What is HPACK?
- HTTP/2 header compression algorithm
- Uses static + dynamic tables
- Compresses repeated headers efficiently

### gRPC Already Uses HPACK (HTTP/2)
```
gRPC Communication:
  Service A → Service B
    ↓
    HTTP/2 (HPACK compression enabled by default)
```

### Our A/B Test Design:

#### Test Scenario A: Full JWT in Metadata
```
metadata: {
  "authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user-id": "608637cf-66ec-415d-b32c-1cd1a63df45d"
}
Size: ~400 bytes (uncompressed)
HPACK Size: ~??? bytes (to measure)
```

#### Test Scenario B: Shredded Token
```
metadata: {
  "uid": "608637cf",
  "exp": "1759774182"
}
Size: ~40 bytes (uncompressed)
HPACK Size: ~??? bytes (to measure)
```

### Metrics to Collect:

1. **Header Size**
   - Uncompressed size
   - HPACK compressed size
   - Compression ratio

2. **Network Performance**
   - Bandwidth usage
   - Latency (p50, p95, p99)
   - Throughput (requests/sec)

3. **Service Mesh Impact**
   - Istio proxy overhead
   - CPU/Memory usage
   - Network I/O

---

## 🔬 Phase 4: Istio A/B Testing

### Istio Setup:

1. **Install Istio** (if not already)
2. **Configure Traffic Splitting**:
   - 50% traffic → Full JWT implementation
   - 50% traffic → Shredded JWT implementation

3. **Collect Metrics**:
   - Prometheus for metrics
   - Grafana for visualization
   - Jaeger for tracing

### Test Configuration:

```yaml
# VirtualService for A/B Testing
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: frontend-ab-test
spec:
  hosts:
  - frontend
  http:
  - match:
    - headers:
        x-test-group:
          exact: "control"
    route:
    - destination:
        host: frontend
        subset: full-jwt
      weight: 50
  - route:
    - destination:
        host: frontend
        subset: shredded-jwt
      weight: 50
```

### Comparison Metrics:

| Metric | Full JWT | Shredded JWT | Improvement |
|--------|----------|--------------|-------------|
| Header Size (uncompressed) | ~400B | ~40B | -90% |
| Header Size (HPACK) | TBD | TBD | TBD |
| Latency (p50) | TBD | TBD | TBD |
| Bandwidth (MB/s) | TBD | TBD | TBD |
| CPU Usage (%) | TBD | TBD | TBD |

---

## 📋 Implementation Roadmap

### ✅ Phase 1: JWT Baseline (COMPLETE)
- [x] JWT generation at frontend
- [x] JWT validation middleware
- [x] User ID in gRPC metadata
- [x] End-to-end token flow

### 🔄 Phase 2: JWT Token Shredding (NEXT - 2-3 hours)
- [ ] Create `jwt_shredder.go`
- [ ] Implement shredding strategies (A, B, C)
- [ ] Update `rpc.go` to use shredded metadata
- [ ] Add configuration flags
- [ ] Deploy shredded version

### 🔄 Phase 3: HPACK Measurement (1-2 hours)
- [ ] Set up packet capture tools
- [ ] Measure header sizes (tcpdump/wireshark)
- [ ] Collect baseline metrics
- [ ] Collect shredded metrics
- [ ] Compare compression ratios

### 🔄 Phase 4: Istio A/B Testing (2-3 hours)
- [ ] Install Istio service mesh
- [ ] Configure traffic splitting
- [ ] Set up Prometheus metrics
- [ ] Run load tests (loadgenerator)
- [ ] Collect comparative data
- [ ] Analyze results

---

## 🛠️ Tools & Technologies

### Already Available:
✅ **Kubernetes** - Container orchestration
✅ **gRPC/HTTP2** - Communication protocol with HPACK
✅ **LoadGenerator** - Built-in traffic generator
✅ **Minikube** - Local K8s cluster

### To Install:
- [ ] **Istio** - Service mesh for A/B testing
- [ ] **Prometheus** - Metrics collection
- [ ] **Grafana** - Metrics visualization
- [ ] **Wireshark/tcpdump** - Packet analysis
- [ ] **hey/wrk** - Additional load testing tools

---

## 📊 Expected Outcomes

### Hypothesis:
Token shredding will reduce header size, which combined with HPACK compression, will result in:
- **Lower network bandwidth** usage
- **Reduced latency** (fewer bytes to transfer)
- **Better throughput** (more requests/sec)
- **Lower CPU usage** (less compression work)

### Potential Findings:

1. **HPACK Efficiency**:
   - HPACK already compresses headers well
   - Shredding might have diminishing returns with HPACK
   - But still reduces initial uncompressed size

2. **Service Mesh Overhead**:
   - Istio proxy adds latency
   - Header size impact on proxy performance
   - Memory/CPU trade-offs

3. **Real-world Impact**:
   - Quantify actual improvement percentages
   - Identify optimal shredding strategy
   - Document best practices

---

## 🎯 Next Immediate Steps

Would you like me to:

1. **Implement JWT Token Shredding** (Phase 2)?
   - Create shredding strategies
   - Measure header size reduction
   - Deploy and test

2. **Set up Measurement Tools** (Phase 3)?
   - Configure packet capture
   - Set up metrics collection
   - Prepare comparison scripts

3. **Install Istio** (Phase 4 prep)?
   - Deploy Istio to the cluster
   - Configure observability
   - Prepare A/B test configuration

Which phase should we tackle next?
