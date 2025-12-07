======================================================================
  K6 Load Test Results
======================================================================

--- ENABLED ---
  Iterations:        440
  Rate:              1.07 iter/s
  Data sent:         7005.65 KB (7173784 bytes)
  Data received:     46664.85 KB (47784802 bytes)
  Avg response time: 18.52 ms
  P95 response time: 65.84 ms
  P99 response time: 0.00 ms
  Failed requests:   0 (0.00%)
  Passed checks:     3300
  Failed checks:     0

--- DISABLED ---
  Iterations:        420
  Rate:              1.02 iter/s
  Data sent:         6938.46 KB (7104984 bytes)
  Data received:     46109.97 KB (47216614 bytes)
  Avg response time: 32.61 ms
  P95 response time: 73.20 ms
  P99 response time: 0.00 ms
  Failed requests:   0 (0.00%)
  Passed checks:     3300
  Failed checks:     0

======================================================================
  Performance Improvements
======================================================================

Data Sent (Upload):
  Compression OFF:   7104984 bytes
  Compression ON:    7173784 bytes
  Bytes difference:  -68800 bytes

Data Received (Download):
  Compression OFF:   47216614 bytes
  Compression ON:    47784802 bytes
  Bytes difference:  -568188 bytes

Response Time:
  Compression OFF:   32.61 ms (avg), 73.20 ms (p95)
  Compression ON:    18.52 ms (avg), 65.84 ms (p95)
  Avg improvement:   14.09 ms faster
  P95 improvement:   7.36 ms faster

======================================================================
  Network Traffic Analysis (PCAP)
======================================================================

--- ENABLED ---
  Total packets:     11366
  HTTP/2 packets:    8573
  Total traffic:     3372168 bytes (3293.13 KB)
  x-jwt-header frames:  4285
  x-jwt-payload values: 4320 (detected by JSON content)
  x-jwt-sig values:     4320 (detected by signature pattern)
  authorization frames: 0

  \033[0;36mHPACK Header Analysis (Compressed Format):\033[0m
    x-jwt-header size:  ~4 bytes (base64url, HPACK indexed)
    x-jwt-payload size: ~52 bytes (raw JSON)
    x-jwt-sig size:     ~342 bytes (base64url)

--- DISABLED ---
  Total packets:     11166
  HTTP/2 packets:    8362
  Total traffic:     3763521 bytes (3675.31 KB)
  x-jwt-header frames:  0
  x-jwt-payload values: 0 (detected by JSON content)
  x-jwt-sig values:     0 (detected by signature pattern)
  authorization frames: 4193

  \033[0;36mAuthorization Header Analysis (Standard Format):\033[0m
    authorization size: ~4 bytes (full JWT)

Network Traffic Comparison:
  Traffic saved:     391353 bytes (382.18 KB)
  Reduction:         10.40%

======================================================================
  gRPC Latency Analysis (Frontend ↔ CartService)
======================================================================

--- ENABLED ---
  gRPC streams analyzed: 4251
  Latency (request → response):
    Min:     0.030 ms
    Avg:     0.714 ms
    P50:     0.617 ms
    P95:     1.422 ms
    P99:     2.359 ms
    Max:     8.140 ms

--- DISABLED ---
  gRPC streams analyzed: 4111
  Latency (request → response):
    Min:     0.307 ms
    Avg:     1.744 ms
    P50:     0.587 ms
    P95:     1.593 ms
    P99:     4.781 ms
    Max:     981.218 ms

gRPC Latency Comparison (Frontend → CartService):

  Metric       Compression ON Compression OFF   Difference
  ------       -------------- ---------------   ----------
  Avg                0.714 ms       1.744 ms 1.030 ms faster
  P50                0.617 ms       0.587 ms 0.030 ms slower
  P95                1.422 ms       1.593 ms 0.171 ms faster
  P99                2.359 ms       4.781 ms 2.422 ms faster

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
    • x-jwt-header frames:  4285
    • x-jwt-payload values: 4320 (detected by JSON content)
    • x-jwt-sig values:     4320 (detected by signature pattern)
  Compression OFF:
    • authorization frames: 4193

======================================================================
  Summary
======================================================================

✓ JWT Compression Results (3-Header Format):

  📊 Data Transfer:
     • Upload bandwidth saved:   -0.97%
     • Download bandwidth saved: -1.20%
     • Total network reduction:  10.40%

  ⚡ Performance:
     • Average response time:    1.030 ms faster
     • P95 response time:        0.171 ms faster

  🔧 Implementation Details:
     • Headers sent:             3 (x-jwt-header, x-jwt-payload, x-jwt-sig)
     • x-jwt-header:             HPACK indexed after first request (~2 bytes)
     • Payload encoding:         Raw JSON (vs base64, ~25% smaller)
     • Signature encoding:       Base64url (unchanged)
For detailed packet analysis:
  wireshark jwt-compression-results-150-on-512kb-cs-20251207_170337/frontend-cart-traffic.pcap &
  wireshark jwt-compression-results-150-off-512kb-cs-20251207_162059/frontend-cart-traffic.pcap &

======================================================================