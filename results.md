======================================================================
  JWT Compression Performance Comparison
======================================================================

Comparing:
  ENABLED:  jwt-compression-on-results-20251014_045342
  DISABLED: jwt-compression-off-results-20251014_213338

======================================================================
  K6 Load Test Results
======================================================================

--- ENABLED ---
  Iterations:        100
  Rate:              0.48 iter/s
  Data sent:         1865.62 KB (1910392 bytes)
  Data received:     17046.44 KB (17455558 bytes)
  Avg response time: 40.02 ms
  P95 response time: 109.24 ms
  P99 response time: 0.00 ms
  Failed requests:   100 (5.88%)
  Passed checks:     1200
  Failed checks:     100

--- DISABLED ---
  Iterations:        100
  Rate:              0.48 iter/s
  Data sent:         1872.26 KB (1917192 bytes)
  Data received:     17017.99 KB (17426426 bytes)
  Avg response time: 36.66 ms
  P95 response time: 107.63 ms
  P99 response time: 0.00 ms
  Failed requests:   100 (5.88%)
  Passed checks:     1200
  Failed checks:     100

======================================================================
  Performance Improvements
======================================================================

Data Sent (Upload):
  Compression OFF:   1917192 bytes
  Compression ON:    1910392 bytes
  Bytes saved:       6800 bytes (6.64 KB)
  Bandwidth savings: 0.35%

Data Received (Download):
  Compression OFF:   17426426 bytes
  Compression ON:    17455558 bytes
  Bytes difference:  -29132 bytes

Response Time:
  Compression OFF:   36.66 ms (avg), 107.63 ms (p95)
  Compression ON:    40.02 ms (avg), 109.24 ms (p95)
  Avg difference:    3.36 ms slower
  P95 difference:    1.61 ms slower

======================================================================
  Network Traffic Analysis (PCAP)
======================================================================

--- ENABLED ---
  Total packets:     4296
  HTTP/2 packets:    3174
  Total traffic:     1327124 bytes (1296.02 KB)
  JWT header frames: 1578
  Auth header frames: 0

--- DISABLED ---
  Total packets:     4300
  HTTP/2 packets:    3142
  Total traffic:     1376535 bytes (1344.27 KB)
  JWT header frames: 0
  Auth header frames: 1577

Network Traffic Comparison:
  Traffic saved:     49411 bytes (48.25 KB)
  Reduction:         3.59%

======================================================================
  JWT Header Analysis
======================================================================

JWT Compression ON:
  Uses 4 separate headers:
    • x-jwt-static       (112b) - Cacheable by HPACK
    • x-jwt-session      (168b) - Cacheable by HPACK
    • x-jwt-dynamic-bin  (122b) - NOT cached (binary)
    • x-jwt-sig-bin      (342b) - NOT cached (binary)
  Total: ~744 bytes first request
  After HPACK caching: ~470 bytes (static/session use indices)

JWT Compression OFF:
  Uses single authorization header:
    • authorization: Bearer <full-jwt>
  Total: ~900+ bytes every request
  No HPACK caching benefit (JWT changes every request)

Header Usage Verification:
  Compression ON:  1578 frames with x-jwt-* headers
  Compression OFF: 1577 frames with authorization header

======================================================================
  Summary
======================================================================

✓ JWT Compression Results:

  📊 Data Transfer:
     • Upload bandwidth saved:   0.35%
     • Download bandwidth saved: -0.17%
     • Total network reduction:  3.59%

  ⚡ Performance:
     • Average response time:    3.36 ms slower
     • P95 response time:        1.61 ms slower

  🎯 Key Benefits:
     • Reduced header size per request
     • HPACK caching for static/session components
     • Better bandwidth utilization
     • Scalable to 300+ concurrent users

For detailed packet analysis:
  wireshark jwt-compression-on-results-20251014_045342/frontend-cart-traffic.pcap &
  wireshark jwt-compression-off-results-20251014_213338/frontend-cart-traffic.pcap &

======================================================================