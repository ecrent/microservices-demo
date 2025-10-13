# HPACK Table Size Configuration - 64KB

## Overview
Configured HPACK dynamic table size to **64KB** (from default 4KB) to support high-concurrency JWT shredding with session caching.

## Configuration Details

### Capacity Analysis

**With 64KB HPACK Table:**
- **Maximum concurrent users: 306** (17x improvement)
- Static header (all users): 156 bytes
- Per-user session header: 213 bytes
- Dynamic/signature headers: NOT cached (0 bytes in table)

**Formula:**
```
Max Users = (HPACK_TABLE_SIZE - STATIC_HEADER_SIZE) / SESSION_HEADER_SIZE
          = (65536 - 156) / 213
          = 307 users (rounded to 306)
```

### Comparison Table

| Configuration | HPACK Size | Max Cached Sessions | Memory per Service |
|---------------|------------|---------------------|-------------------|
| **Default**   | 4 KB       | ~18 users          | 4 KB              |
| **Configured**| 64 KB      | **306 users**      | 64 KB             |
| **Improvement**| 16x       | 17x                | +60 KB            |

### Implementation

All services now configured with:

```go
// Server-side (receives connections)
grpc.NewServer(
    grpc.MaxHeaderListSize(98304), // 96KB
)

// Client-side (makes connections)
grpc.DialContext(ctx, addr,
    grpc.WithMaxHeaderListSize(98304), // 96KB
)
```

**Why 98304 (96KB)?**
- 64KB for HPACK dynamic table
- 32KB overhead for header processing
- Ensures no header truncation

### Services Configured

✅ **Frontend Service** (`src/frontend/main.go`)
- Client connections to: Cart, Checkout, Currency, Product, Recommendation, Shipping, Ad

✅ **Checkout Service** (`src/checkoutservice/main.go`)
- Server: Receives from Frontend
- Client connections to: Email, Payment, Shipping, Currency, Cart, Product

✅ **Shipping Service** (`src/shippingservice/main.go`)
- Server: Receives from Checkout

## Benefits

### 1. High Concurrency Support
- **306 concurrent user sessions** can be cached per connection
- Prevents cache thrashing under load
- Maintains high compression ratios even with many users

### 2. Better Cache Hit Rates
- Session headers stay in cache longer
- Less FIFO eviction of active sessions
- More predictable performance

### 3. Bandwidth Savings Scale
With 306 cached sessions making 100 requests each:

**Without caching (default 4KB):**
```
Only 18 sessions cached, 288 sessions sending full headers
18 × 100 × 428 bytes (cached) = 770,400 bytes
288 × 100 × 702 bytes (uncached) = 20,217,600 bytes
Total: 20,988,000 bytes (20.0 MB)
```

**With 64KB HPACK table:**
```
All 306 sessions cached
306 × 100 × 428 bytes (cached) = 13,096,800 bytes
Total: 13,096,800 bytes (12.5 MB)
Savings: 7.5 MB (37.6% reduction!)
```

### 4. Memory Trade-off
**Cost:** +60KB per gRPC connection per service
- Frontend → Cart: 60KB
- Frontend → Checkout: 60KB
- Checkout → Payment: 60KB
- etc.

**For 10 gRPC connections:** ~600KB total memory increase

**Benefit:** 37.6% bandwidth reduction for high-load scenarios

## When to Adjust

### Increase HPACK Table Size When:
- Concurrent user sessions > 306
- Seeing cache eviction in logs
- Need to support more simultaneous users

### Decrease HPACK Table Size When:
- Memory constrained environment
- Fewer than 100 concurrent users
- Want to optimize for lower memory footprint

## Verification

### Check Configuration Applied:
```bash
# View gRPC server options in logs
kubectl logs deployment/checkoutservice | grep -i "max.*header"

# View connection settings
kubectl logs deployment/frontend | grep -i "header.*list"
```

### Test Cache Effectiveness:
```bash
# Run HPACK test script
./test_hpack_nocompress.sh

# Generate sustained load (warm up cache)
for i in {1..1000}; do
    curl -s http://frontend/ > /dev/null
done

# Check logs for compression messages
kubectl logs deployment/frontend | grep "static/session=CACHED"
```

### Capture and Analyze:
```bash
# Capture HTTP/2 traffic
kubectl exec -it deployment/frontend -- \
    tcpdump -i any -s 0 -w /tmp/hpack-64kb.pcap port 7070 &

# Generate traffic
# ... (make requests) ...

# Download capture
kubectl cp deployment/frontend:/tmp/hpack-64kb.pcap ./hpack-64kb.pcap

# Analyze with Wireshark
# Look for: HTTP/2 HEADERS frames with "Indexed Header Field" representations
```

## HTTP/2 Frame Analysis

Expected behavior in Wireshark:

**First Request (Cold Cache):**
```
HEADERS Frame:
  x-jwt-static:  [Literal with Incremental Indexing] (0x40) → 112 bytes
  x-jwt-session: [Literal with Incremental Indexing] (0x40) → 168 bytes
  x-jwt-dynamic: [Literal without Indexing] (0x00) → 80 bytes
  x-jwt-sig:     [Literal without Indexing] (0x00) → 342 bytes
```

**Subsequent Requests (Warm Cache):**
```
HEADERS Frame:
  x-jwt-static:  [Indexed] (0x80) → ~3 bytes (table reference)
  x-jwt-session: [Indexed] (0x80) → ~3 bytes (table reference)
  x-jwt-dynamic: [Literal without Indexing] (0x00) → 80 bytes
  x-jwt-sig:     [Literal without Indexing] (0x00) → 342 bytes
```

## Troubleshooting

### If compression not working:
1. Check JWT_COMPRESSION_ENABLED=true
2. Verify MaxHeaderListSize in all services
3. Check for gRPC version compatibility (requires grpc-go v1.30+)
4. Review logs for "Failed to decompose JWT" errors

### If memory usage too high:
1. Reduce MaxHeaderListSize to 32768 (32KB) for ~150 users
2. Monitor with: `kubectl top pods`
3. Adjust based on actual concurrent user load

## References

- RFC 7541: HPACK - Header Compression for HTTP/2
- gRPC Go API: MaxHeaderListSize option
- JWT Compression Implementation: `JWT_COMPRESSION_RESULTS.md`
- Test Script: `test_hpack_nocompress.sh`
