# JWT Header Splitting - Testing & Measurement Guide

## 🧪 Testing the Implementation

### Step 1: Build and Deploy

```bash
cd /workspaces/microservices-demo

# Enable JWT splitting via environment variable
kubectl set env deployment/frontend ENABLE_JWT_SPLITTING=true

# Rebuild and redeploy
skaffold run

# Verify deployment
kubectl get pods | grep frontend
kubectl logs deployment/frontend | grep -i "jwt"
```

Expected output:
```
JWT initialized successfully.
JWT header splitting ENABLED for HPACK optimization.
```

### Step 2: Enable Debug Logging

```bash
# Set log level to debug to see splitting metrics
kubectl set env deployment/frontend LOG_LEVEL=debug

# Watch logs in real-time
kubectl logs -f deployment/frontend | grep -i "splitting"
```

Expected output:
```json
{
  "level": "debug",
  "msg": "JWT header splitting metrics",
  "full_jwt_bytes": 266,
  "split_uncompressed": 210,
  "split_hpack_estimated": 81,
  "savings_bytes": 185,
  "savings_percent": 69
}
```

---

## 📊 Measurement Methods

### Method 1: Application-Level Metrics (Easy)

The interceptor logs metrics automatically:

```bash
# Watch splitting metrics
kubectl logs deployment/frontend --tail=100 | grep "splitting metrics"

# Count successful splits
kubectl logs deployment/frontend | grep "splitting metrics" | wc -l
```

### Method 2: Network-Level Analysis (Advanced)

#### Using tcpdump

```bash
# Access frontend pod
kubectl exec -it deployment/frontend -- sh

# Install tcpdump
apk add tcpdump

# Capture gRPC traffic to CartService
tcpdump -i any -s 0 -w /tmp/grpc-traffic.pcap 'port 7070'

# Download the capture
kubectl cp default/frontend-xxx:/tmp/grpc-traffic.pcap ./grpc-traffic.pcap

# Analyze with Wireshark or tshark
tshark -r grpc-traffic.pcap -Y "http2" -T fields \
  -e frame.number \
  -e http2.header.name \
  -e http2.header.value \
  -e http2.length
```

#### Expected Headers in Wireshark

**Without Splitting** (ENABLE_JWT_SPLITTING=false):
```
:method: POST
:path: /hipstershop.CartService/GetCart
:authority: cartservice:7070
user-id: 608637cf-66ec-415d-b32c-1cd1a63df45d
x-user-id: 608637cf-66ec-415d-b32c-1cd1a63df45d
```

**With Splitting** (ENABLE_JWT_SPLITTING=true):
```
:method: POST
:path: /hipstershop.CartService/GetCart
:authority: cartservice:7070
auth-jwt-h: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9
auth-jwt-c-iss: online-boutique-frontend
auth-jwt-c-sub: 608637cf-66ec-415d-b32c-1cd1a63df45d
auth-jwt-c-iat: 1759687782
auth-jwt-c-exp: 1759774182
auth-jwt-c-nbf: 1759687782
auth-jwt-s: Hd9OAfwTtruKnf5YumBagbHxrAp8yoTlg19ZQuwMUfQ
user-id: 608637cf-66ec-415d-b32c-1cd1a63df45d  (kept for backwards compat)
```

### Method 3: HPACK Frame Analysis

```bash
# Use tshark to decode HTTP/2 frames
tshark -r grpc-traffic.pcap -Y "http2.type == 1" -V | grep -A 20 "HEADERS"

# Look for:
# - Indexed Header Field (from dynamic table): 1-2 bytes
# - Literal Header Field: full size
```

#### HPACK Compression Indicators

```
Indexed Header Field (0x80): Header is in dynamic/static table
  Example: 0x82 = index 2 in static table
  Size: 1 byte

Literal Header Field with Incremental Indexing (0x40):
  New header added to dynamic table
  Size: name_length + value_length + 2 bytes

Literal Header Field without Indexing (0x00):
  Header not added to dynamic table
  Size: name_length + value_length + 2 bytes
```

---

## 📈 A/B Testing Setup

### Test Scenario 1: Baseline vs Splitting

```bash
# Deploy Control Group (no splitting)
kubectl create deployment frontend-control \
  --image=frontend:latest \
  --replicas=1

kubectl set env deployment/frontend-control ENABLE_JWT_SPLITTING=false

# Deploy Treatment Group (with splitting)
kubectl create deployment frontend-treatment \
  --image=frontend:latest \
  --replicas=1

kubectl set env deployment/frontend-treatment ENABLE_JWT_SPLITTING=true

# Configure Istio VirtualService for 50/50 split
kubectl apply -f - <<EOF
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
        host: frontend-control
  - match:
    - headers:
        x-test-group:
          exact: "treatment"
    route:
    - destination:
        host: frontend-treatment
  - route:
    - destination:
        host: frontend-control
      weight: 50
    - destination:
        host: frontend-treatment
      weight: 50
EOF
```

### Test Scenario 2: Load Testing

```bash
# Use the built-in load generator
kubectl scale deployment/loadgenerator --replicas=5

# Monitor metrics
kubectl top pods
kubectl logs deployment/loadgenerator | tail -20

# Custom load test with hey
kubectl run load-test --image=williamyeh/hey:latest --rm -it -- \
  -z 60s -c 100 -m GET http://frontend:80/
```

---

## 📊 Metrics to Collect

### 1. Header Size Metrics

```bash
# Extract from logs
kubectl logs deployment/frontend | \
  grep "splitting metrics" | \
  jq -r '[.full_jwt_bytes, .split_hpack_estimated, .savings_percent] | @csv'

# Calculate averages
kubectl logs deployment/frontend | \
  grep "splitting metrics" | \
  jq -r '.savings_percent' | \
  awk '{sum+=$1; count++} END {print "Average savings:", sum/count "%"}'
```

### 2. Network Bandwidth

```bash
# Monitor network I/O
kubectl exec deployment/frontend -- sh -c '
  cat /proc/net/dev | grep eth0
  sleep 5
  cat /proc/net/dev | grep eth0
' | awk '{print ($2-prev)/5 " bytes/sec"; prev=$2}'
```

### 3. Latency Metrics

```bash
# Get p50, p95, p99 latencies from load generator
kubectl logs deployment/loadgenerator | grep -E "p50|p95|p99"

# Or use Prometheus queries (if installed)
# rate(grpc_client_handling_seconds_bucket[1m])
```

### 4. CPU/Memory Usage

```bash
# Resource usage
kubectl top pods --containers | grep frontend

# Detailed metrics
kubectl exec deployment/frontend -- sh -c '
  cat /proc/meminfo | grep -E "MemTotal|MemAvailable"
  top -bn1 | grep "Cpu(s)"
'
```

---

## 📋 Test Checklist

### Phase 1: Functional Testing
- [ ] Frontend builds successfully with new code
- [ ] JWT splitting can be enabled/disabled via env var
- [ ] Split headers are correctly added to gRPC metadata
- [ ] Backend services receive split headers
- [ ] Backwards compatibility (works with splitting disabled)
- [ ] No errors in logs

### Phase 2: Performance Testing
- [ ] Measure baseline header sizes (splitting disabled)
- [ ] Measure optimized header sizes (splitting enabled)
- [ ] Calculate compression ratios
- [ ] Monitor CPU/memory overhead
- [ ] Test under sustained load
- [ ] Test under burst load

### Phase 3: A/B Testing
- [ ] Deploy control and treatment groups
- [ ] Configure traffic splitting (50/50)
- [ ] Collect metrics from both groups
- [ ] Statistical significance testing
- [ ] Document findings

---

## 🎯 Success Criteria

### Expected Results

| Metric | Control (No Splitting) | Treatment (With Splitting) | Target Improvement |
|--------|------------------------|----------------------------|-------------------|
| Header Size (first req) | ~266 bytes | ~190 bytes | -28% |
| Header Size (cached) | ~266 bytes | ~81 bytes | -69% |
| Bandwidth (1000 req/s) | 266 KB/s | 81 KB/s | -69% |
| Latency (p50) | Baseline | < Baseline | -5% to -15% |
| CPU Usage | Baseline | < Baseline + 5% | Minimal increase |

### Statistical Significance

```bash
# Collect at least 10,000 requests per group
# Calculate mean and standard deviation
# Perform t-test for significance

# Example Python script:
python3 - <<EOF
import scipy.stats as stats
control = [266, 266, 266, ...]  # Header sizes from logs
treatment = [190, 81, 81, ...]   # Header sizes from logs
t_stat, p_value = stats.ttest_ind(control, treatment)
print(f"T-statistic: {t_stat}, P-value: {p_value}")
if p_value < 0.05:
    print("Result is statistically significant!")
EOF
```

---

## 🐛 Troubleshooting

### Problem: Headers not being split

**Check:**
```bash
# Verify environment variable
kubectl exec deployment/frontend -- env | grep ENABLE_JWT_SPLITTING

# Check logs for initialization
kubectl logs deployment/frontend | grep "JWT header splitting"

# Verify interceptor is registered
kubectl logs deployment/frontend | grep "interceptor"
```

### Problem: Backend not receiving headers

**Check:**
```bash
# Check backend logs
kubectl logs deployment/cartservice | grep -i "auth-jwt"

# Verify metadata propagation
kubectl logs deployment/frontend -c frontend | grep "user-id"
```

### Problem: High CPU usage

**Check:**
```bash
# Monitor CPU
kubectl top pods --containers

# Profile the application
kubectl port-forward deployment/frontend 6060:6060
go tool pprof http://localhost:6060/debug/pprof/profile
```

---

## 📖 Next Steps

1. ✅ Deploy with splitting enabled
2. ✅ Collect baseline metrics
3. ✅ Run A/B tests
4. ✅ Analyze results
5. ✅ Document findings
6. ⏭️ Optimize further (short header names, etc.)
7. ⏭️ Production rollout plan

---

**Ready to test?** Run the commands above and collect your data!
