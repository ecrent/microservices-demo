# JWT Compression Performance Test

## Overview
This test measures the network performance impact of JWT compression with HPACK session caching across JWT renewal scenarios.

## Test Scenario

100 virtual users perform the following journey (total ~3 minutes):

1. **Visit frontpage** → Receive JWT #1 (if new/expired)
2. **Add 2 items to cart** → Use JWT #1 with HPACK compression
3. **Wait 125 seconds** → JWT expires (120s TTL)
4. **Return to shopping** → Receive JWT #2 (new session)
5. **Add 1 item to cart** → Use JWT #2 with HPACK compression
6. **Place order** → Complete checkout with JWT #2
7. **Continue shopping** → Browse more

## Expected HPACK Behavior

### JWT #1 (Cold Cache)
- **First request**: Full 702 bytes transmitted
  - x-jwt-static: 112b (literal with indexing)
  - x-jwt-session: 168b (literal with indexing)
  - x-jwt-dynamic: 80b (literal WITHOUT indexing)
  - x-jwt-sig: 342b (literal WITHOUT indexing)

### JWT #1 (Warm Cache)
- **Subsequent requests**: ~428 bytes transmitted
  - x-jwt-static: 1 byte (indexed reference)
  - x-jwt-session: 1 byte (indexed reference)
  - x-jwt-dynamic: 80b (not cached)
  - x-jwt-sig: 342b (not cached)
  - **Savings: 39% bandwidth reduction**

### JWT #2 (After Renewal)
- **First request**: ~584 bytes transmitted
  - x-jwt-static: 1 byte (still cached from JWT #1!)
  - x-jwt-session: 168b (new session, literal with indexing)
  - x-jwt-dynamic: 80b (not cached)
  - x-jwt-sig: 342b (not cached)
  - **Savings: 17% vs cold start** (static header reused)

## Running the Test

```bash
cd /workspaces/microservices-demo

# Run the test (captures traffic + runs k6)
./run-jwt-compression-test.sh

# Analyze results
./analyze-jwt-compression.sh ./jwt-compression-results-<timestamp>
```

## Output Files

The test creates a timestamped directory with:

- `frontend-cart-traffic.pcap` - Network capture of Frontend ↔ CartService traffic
- `k6-results.json` - Detailed k6 metrics
- `k6-summary.json` - Test summary statistics
- `k6-output.log` - Full k6 console output

## Traffic Capture Details

- **Capture point**: Minikube node (captures pod-to-pod traffic)
- **Filter**: Frontend IP ↔ CartService IP on port 7070 (gRPC)
- **Protocol**: HTTP/2 with HPACK compression
- **Focus**: HEADERS frames containing JWT components

## Analysis

The analysis script provides:

1. **K6 Test Summary**
   - Total requests, success rate, response times
   - JWT renewals count, cart operations count

2. **HTTP/2 Traffic Analysis**
   - Total HEADERS frames captured
   - Frame size distribution (min/max/avg/median)

3. **HPACK Compression Efficiency**
   - Cold cache vs warm cache frame sizes
   - Bandwidth savings percentage
   - JWT renewal impact

## Manual Analysis with Wireshark

```bash
wireshark ./jwt-compression-results-<timestamp>/frontend-cart-traffic.pcap
```

**Display filters to try:**
- `http2` - All HTTP/2 traffic
- `http2.type==1` - HEADERS frames only
- `http2.header.name contains "jwt"` - Frames with JWT headers

**What to look for:**
- HEADERS frame sizes decreasing after first request
- "Indexed Header Field" representations for static/session headers
- "Literal without Indexing" for dynamic/signature headers

## Requirements

- k6 (installed) ✓
- kubectl with minikube ✓
- tcpdump on minikube node (available by default) ✓
- tshark (optional, for automated analysis)

Install tshark: `sudo apt-get install tshark`

## Performance Impact

**Expected Results:**
- **First JWT (cold)**: 702 bytes per request
- **First JWT (warm)**: 428 bytes per request (39% savings)
- **Second JWT (cold)**: 584 bytes per request (17% savings from static cache hit)
- **Second JWT (warm)**: 428 bytes per request (39% savings)

**Network Savings with 100 users:**
- Each user makes ~10 gRPC calls to CartService
- Total calls: ~1000 requests
- Cold only: 702 KB
- With HPACK: ~460 KB
- **Total savings: ~242 KB (34% reduction)**

This demonstrates that JWT shredding + HPACK indexing control provides significant bandwidth savings, especially important in high-traffic microservice environments.
