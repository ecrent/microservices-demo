Comparing:
  ENABLED:  jwt-compression-results-400-on-512kb-cs-20251207_164727
  DISABLED: jwt-compression-results-400-off-512kb-cs-20251207_163715

======================================================================
  K6 Load Test Results
======================================================================

--- ENABLED ---
  Iterations:        911
  Rate:              2.22 iter/s
  Data sent:         17800.80 KB (18228024 bytes)
  Data received:     117145.91 KB (119957413 bytes)
  Avg response time: 295.70 ms
  P95 response time: 998.55 ms
  P99 response time: 0.00 ms
  Failed requests:   0 (0.00%)
  Passed checks:     8800
  Failed checks:     0

--- DISABLED ---
  Iterations:        940
  Rate:              2.29 iter/s
  Data sent:         17898.23 KB (18327784 bytes)
  Data received:     117955.70 KB (120786636 bytes)
  Avg response time: 196.53 ms
  P95 response time: 590.08 ms
  P99 response time: 0.00 ms
  Failed requests:   0 (0.00%)
  Passed checks:     8800
  Failed checks:     0

======================================================================
  Performance Improvements
======================================================================

Data Sent (Upload):
  Compression OFF:   18327784 bytes
  Compression ON:    18228024 bytes
  Bytes saved:       99760 bytes (97.42 KB)
  Bandwidth savings: 0.54%

Data Received (Download):
  Compression OFF:   120786636 bytes
  Compression ON:    119957413 bytes
  Bytes saved:       829223 bytes (809.79 KB)
  Bandwidth savings: 0.69%

Response Time:
  Compression OFF:   196.53 ms (avg), 590.08 ms (p95)
  Compression ON:    295.70 ms (avg), 998.55 ms (p95)
  Avg difference:    99.17 ms slower
  P95 difference:    408.47 ms slower

======================================================================
  Network Traffic Analysis (PCAP)
======================================================================

--- ENABLED ---
  Total packets:     22372
  HTTP/2 packets:    16279
  Total traffic:     8984059 bytes (8773.50 KB)
  x-jwt-header frames:  8385
  x-jwt-payload values: 10733 (detected by JSON content)
  x-jwt-sig values:     10733 (detected by signature pattern)
  authorization frames: 0

  \033[0;36mHPACK Header Analysis (Compressed Format):\033[0m
    x-jwt-header size:  ~4 bytes (base64url, HPACK indexed)
    x-jwt-payload size: ~52 bytes (raw JSON)
    x-jwt-sig size:     ~342 bytes (base64url)

--- DISABLED ---
  Total packets:     24429
  HTTP/2 packets:    17947
  Total traffic:     10443900 bytes (10199.12 KB)
  x-jwt-header frames:  0
  x-jwt-payload values: 0 (detected by JSON content)
  x-jwt-sig values:     0 (detected by signature pattern)
  authorization frames: 9094

  \033[0;36mAuthorization Header Analysis (Standard Format):\033[0m
    authorization size: ~4 bytes (full JWT)

Network Traffic Comparison:
  Traffic saved:     1459841 bytes (1425.63 KB)
  Reduction:         13.98%

======================================================================
  gRPC Latency Analysis (Frontend ↔ CartService)
======================================================================

--- ENABLED ---
  gRPC streams analyzed: 6986
  Latency (request → response):
    Min:     0.089 ms
    Avg:     5.031 ms
    P50:     0.947 ms
    P95:     5.242 ms
    P99:     15.698 ms
    Max:     985.917 ms

--- DISABLED ---
  gRPC streams analyzed: 8031
  Latency (request → response):
    Min:     0.069 ms
    Avg:     3.273 ms
    P50:     1.043 ms
    P95:     5.017 ms
    P99:     8.966 ms
    Max:     853.957 ms

gRPC Latency Comparison (Frontend → CartService):

  Metric       Compression ON Compression OFF   Difference
  ------       -------------- ---------------   ----------
  Avg                5.031 ms       3.273 ms 1.758 ms slower
  P50                0.947 ms       1.043 ms 0.096 ms faster
  P95                5.242 ms       5.017 ms 0.225 ms slower
  P99               15.698 ms       8.966 ms 6.732 ms slower

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
    • x-jwt-header frames:  8385
    • x-jwt-payload values: 10733 (detected by JSON content)
    • x-jwt-sig values:     10733 (detected by signature pattern)
  Compression OFF:
    • authorization frames: 9094

======================================================================
  Summary
======================================================================

✓ JWT Compression Results (3-Header Format):

  📊 Data Transfer:
     • Upload bandwidth saved:   0.54%
     • Download bandwidth saved: 0.69%
     • Total network reduction:  13.98%

  ⚡ Performance:
     • Average response time:    Similar performance
     • P95 response time:        Similar performance

  🔧 Implementation Details:
     • Headers sent:             3 (x-jwt-header, x-jwt-payload, x-jwt-sig)
     • x-jwt-header:             HPACK indexed after first request (~2 bytes)
     • Payload encoding:         Raw JSON (vs base64, ~25% smaller)
     • Signature encoding:       Base64url (unchanged)
For detailed packet analysis:
  wireshark jwt-compression-results-400-on-512kb-cs-20251207_164727/frontend-cart-traffic.pcap &
  wireshark jwt-compression-results-400-off-512kb-cs-20251207_163715/frontend-cart-traffic.pcap &

======================================================================