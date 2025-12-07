======================================================================
  JWT Compression Performance Comparison
======================================================================

Comparing:
  ENABLED:  jwt-compression-results-250-on-512kb-cs-20251207_165608
  DISABLED: jwt-compression-results-250-off-512kb-cs-20251207_162919

======================================================================
  K6 Load Test Results
======================================================================

--- ENABLED ---
  Iterations:        640
  Rate:              1.56 iter/s
  Data sent:         11362.68 KB (11635384 bytes)
  Data received:     75181.87 KB (76986232 bytes)
  Avg response time: 47.94 ms
  P95 response time: 161.45 ms
  P99 response time: 0.00 ms
  Failed requests:   0 (0.00%)
  Passed checks:     5500
  Failed checks:     0

--- DISABLED ---
  Iterations:        640
  Rate:              1.56 iter/s
  Data sent:         11362.68 KB (11635384 bytes)
  Data received:     75179.61 KB (76983922 bytes)
  Avg response time: 67.00 ms
  P95 response time: 268.58 ms
  P99 response time: 0.00 ms
  Failed requests:   0 (0.00%)
  Passed checks:     5500
  Failed checks:     0

======================================================================
  Performance Improvements
======================================================================

Data Sent (Upload):
  Compression OFF:   11635384 bytes
  Compression ON:    11635384 bytes
  Bytes difference:  0 bytes

Data Received (Download):
  Compression OFF:   76983922 bytes
  Compression ON:    76986232 bytes
  Bytes difference:  -2310 bytes

Response Time:
  Compression OFF:   67.00 ms (avg), 268.58 ms (p95)
  Compression ON:    47.94 ms (avg), 161.45 ms (p95)
  Avg improvement:   19.06 ms faster
  P95 improvement:   107.13 ms faster

======================================================================
  Network Traffic Analysis (PCAP)
======================================================================

--- ENABLED ---
  Total packets:     18273
  HTTP/2 packets:    13341
  Total traffic:     5450839 bytes (5323.08 KB)
  x-jwt-header frames:  6721
  x-jwt-payload values: 6920 (detected by JSON content)
  x-jwt-sig values:     6920 (detected by signature pattern)
  authorization frames: 0

  \033[0;36mHPACK Header Analysis (Compressed Format):\033[0m
    x-jwt-header size:  ~4 bytes (base64url, HPACK indexed)
    x-jwt-payload size: ~52 bytes (raw JSON)
    x-jwt-sig size:     ~342 bytes (base64url)

--- DISABLED ---
  Total packets:     18036
  HTTP/2 packets:    12988
  Total traffic:     6244917 bytes (6098.55 KB)
  x-jwt-header frames:  0
  x-jwt-payload values: 0 (detected by JSON content)
  x-jwt-sig values:     0 (detected by signature pattern)
  authorization frames: 6583

  \033[0;36mAuthorization Header Analysis (Standard Format):\033[0m
    authorization size: ~4 bytes (full JWT)

Network Traffic Comparison:
  Traffic saved:     794078 bytes (775.47 KB)
  Reduction:         12.72%

======================================================================
  gRPC Latency Analysis (Frontend ↔ CartService)
======================================================================

--- ENABLED ---
  gRPC streams analyzed: 6483
  Latency (request → response):
    Min:     0.051 ms
    Avg:     1.727 ms
    P50:     0.718 ms
    P95:     1.973 ms
    P99:     3.732 ms
    Max:     993.511 ms

--- DISABLED ---
  gRPC streams analyzed: 6217
  Latency (request → response):
    Min:     0.299 ms
    Avg:     2.629 ms
    P50:     0.795 ms
    P95:     2.780 ms
    P99:     5.663 ms
    Max:     981.766 ms

gRPC Latency Comparison (Frontend → CartService):

  Metric       Compression ON Compression OFF   Difference
  ------       -------------- ---------------   ----------
  Avg                1.727 ms       2.629 ms 0.902 ms faster
  P50                0.718 ms       0.795 ms 0.077 ms faster
  P95                1.973 ms       2.780 ms 0.807 ms faster
  P99                3.732 ms       5.663 ms 1.931 ms faster

======================================================================
  JWT Header Analysis
======================================================================

Implementation Details:
  Compression ON (3-header format):
    • x-jwt-header:  Base64url JWT header (HPACK indexed after first request)
    • x-jwt-payload: Raw JSON payload (not base64 encoded, ~25% smaller)
    • x-jwt-sig:     Base64url signature only

  Compression OFF (standard format):
    • authorization: Bearer <header>.<payload>.<signature>

Header Usage Verification:
  Compression ON:
    • x-jwt-header frames:  6721
    • x-jwt-payload values: 6920 (detected by JSON content)
    • x-jwt-sig values:     6920 (detected by signature pattern)
  Compression OFF:
    • authorization frames: 6583

======================================================================
  Summary
======================================================================

✓ JWT Compression Results (3-Header Format):

  📊 Data Transfer:
     • Upload bandwidth saved:   0.00%
     • Download bandwidth saved: -0.00%
     • Total network reduction:  12.72%

  ⚡ Performance:
     • Average response time:    0.902 ms faster
     • P95 response time:        0.807 ms faster

  🔧 Implementation Details:
     • Headers sent:             3 (x-jwt-header, x-jwt-payload, x-jwt-sig)
     • x-jwt-header:             HPACK indexed after first request (~2 bytes)
     • Payload encoding:         Raw JSON (vs base64, ~25% smaller)
     • Signature encoding:       Base64url (unchanged)
For detailed packet analysis:
  wireshark jwt-compression-results-250-on-512kb-cs-20251207_165608/frontend-cart-traffic.pcap &
  wireshark jwt-compression-results-250-off-512kb-cs-20251207_162919/frontend-cart-traffic.pcap &

======================================================================