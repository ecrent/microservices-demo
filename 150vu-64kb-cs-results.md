
7min
======================================================================
  JWT Compression Performance Comparison
======================================================================

Comparing:
  ENABLED:  jwt-compression-results-150-on-64kb-cs-20251207_182655
  DISABLED: jwt-compression-results-150-off-64kb-cs-20251207_181718

======================================================================
  K6 Load Test Results
======================================================================

--- ENABLED ---
  Iterations:        420
  Rate:              1.02 iter/s
  Data sent:         6938.46 KB (7104984 bytes)
  Data received:     46109.05 KB (47215666 bytes)
  Avg response time: 32.69 ms
  P95 response time: 78.27 ms
  P99 response time: 0.00 ms
  Failed requests:   0 (0.00%)
  Passed checks:     3300
  Failed checks:     0

--- DISABLED ---
  Iterations:        404
  Rate:              0.99 iter/s
  Data sent:         6884.71 KB (7049944 bytes)
  Data received:     45663.87 KB (46759806 bytes)
  Avg response time: 38.19 ms
  P95 response time: 77.85 ms
  P99 response time: 0.00 ms
  Failed requests:   0 (0.00%)
  Passed checks:     3300
  Failed checks:     0

======================================================================
  Performance Improvements
======================================================================

Data Sent (Upload):
  Compression OFF:   7049944 bytes
  Compression ON:    7104984 bytes
  Bytes difference:  -55040 bytes

Data Received (Download):
  Compression OFF:   46759806 bytes
  Compression ON:    47215666 bytes
  Bytes difference:  -455860 bytes

Response Time:
  Compression OFF:   38.19 ms (avg), 77.85 ms (p95)
  Compression ON:    32.69 ms (avg), 78.27 ms (p95)
  Avg improvement:   5.50 ms faster
  P95 difference:    0.42 ms slower

======================================================================
  Network Traffic Analysis (PCAP)
======================================================================

--- ENABLED ---
  Total packets:     11178
  HTTP/2 packets:    8319
  Total traffic:     3332608 bytes (3254.50 KB)
  x-jwt-header frames:  4169
  x-jwt-payload values: 4260 (detected by JSON content)
  x-jwt-sig values:     4260 (detected by signature pattern)
  authorization frames: 0

  \033[0;36mHPACK Header Analysis (Compressed Format):\033[0m
    x-jwt-header size:  ~4 bytes (base64url, HPACK indexed)
    x-jwt-payload size: ~52 bytes (raw JSON)
    x-jwt-sig size:     ~342 bytes (base64url)

--- DISABLED ---
  Total packets:     11010
  HTTP/2 packets:    8205
  Total traffic:     3727335 bytes (3639.98 KB)
  x-jwt-header frames:  0
  x-jwt-payload values: 0 (detected by JSON content)
  x-jwt-sig values:     0 (detected by signature pattern)
  authorization frames: 4116

  \033[0;36mAuthorization Header Analysis (Standard Format):\033[0m
    authorization size: ~4 bytes (full JWT)

Network Traffic Comparison:
  Traffic saved:     394727 bytes (385.48 KB)
  Reduction:         10.59%

======================================================================
  gRPC Latency Analysis (Frontend ↔ CartService)
======================================================================

--- ENABLED ---
  gRPC streams analyzed: 4097
  Latency (request → response):
    Min:     0.321 ms
    Avg:     0.999 ms
    P50:     0.622 ms
    P95:     1.599 ms
    P99:     4.875 ms
    Max:     72.802 ms

--- DISABLED ---
  gRPC streams analyzed: 4044
  Latency (request → response):
    Min:     0.327 ms
    Avg:     1.735 ms
    P50:     0.619 ms
    P95:     1.582 ms
    P99:     3.953 ms
    Max:     995.071 ms

gRPC Latency Comparison (Frontend → CartService):

  Metric       Compression ON Compression OFF   Difference
  ------       -------------- ---------------   ----------
  Avg                0.999 ms       1.735 ms 0.736 ms faster
  P50                0.622 ms       0.619 ms 0.003 ms slower
  P95                1.599 ms       1.582 ms 0.017 ms slower
  P99                4.875 ms       3.953 ms 0.922 ms slower

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
    • x-jwt-header frames:  4169
    • x-jwt-payload values: 4260 (detected by JSON content)
    • x-jwt-sig values:     4260 (detected by signature pattern)
  Compression OFF:
    • authorization frames: 4116

======================================================================
  Summary
======================================================================

✓ JWT Compression Results (3-Header Format):

  📊 Data Transfer:
     • Upload bandwidth saved:   -0.78%
     • Download bandwidth saved: -0.97%
     • Total network reduction:  10.59%

  ⚡ Performance:
     • Average response time:    0.736 ms faster
     • P95 response time:        Similar performance

  🔧 Implementation Details:
     • Headers sent:             3 (x-jwt-header, x-jwt-payload, x-jwt-sig)
     • x-jwt-header:             HPACK indexed after first request (~2 bytes)
     • Payload encoding:         Raw JSON (vs base64, ~25% smaller)
     • Signature encoding:       Base64url (unchanged)
For detailed packet analysis:
  wireshark jwt-compression-results-150-on-64kb-cs-20251207_182655/frontend-cart-traffic.pcap &
  wireshark jwt-compression-results-150-off-64kb-cs-20251207_181718/frontend-cart-traffic.pcap &

======================================================================