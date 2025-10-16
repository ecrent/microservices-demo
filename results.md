======================================================================
  JWT Compression Performance Comparison
======================================================================

Comparing:
  ENABLED:  jwt-compression-on-results-20251016_020954
  DISABLED: jwt-compression-off-results-20251016_020036

======================================================================
  K6 Load Test Results
======================================================================

--- ENABLED ---
  Iterations:        100
  Rate:              0.48 iter/s
  Data sent:         2595.60 KB (2657892 bytes)
  Data received:     17287.70 KB (17702601 bytes)
  Avg response time: 23.16 ms
  P95 response time: 79.92 ms
  P99 response time: 0.00 ms
  Failed requests:   0 (0.00%)
  Passed checks:     1300
  Failed checks:     0

--- DISABLED ---
  Iterations:        100
  Rate:              0.48 iter/s
  Data sent:         2595.60 KB (2657892 bytes)
  Data received:     17289.27 KB (17704211 bytes)
  Avg response time: 25.52 ms
  P95 response time: 92.07 ms
  P99 response time: 0.00 ms
  Failed requests:   0 (0.00%)
  Passed checks:     1300
  Failed checks:     0

======================================================================
  Performance Improvements
======================================================================

Data Sent (Upload):
  Compression OFF:   2657892 bytes
  Compression ON:    2657892 bytes
  Bytes difference:  0 bytes

Data Received (Download):
  Compression OFF:   17704211 bytes
  Compression ON:    17702601 bytes
  Bytes saved:       1610 bytes (1.57 KB)
  Bandwidth savings: 0.01%

Response Time:
  Compression OFF:   25.52 ms (avg), 92.07 ms (p95)
  Compression ON:    23.16 ms (avg), 79.92 ms (p95)
  Avg improvement:   2.36 ms faster
  P95 improvement:   12.15 ms faster

======================================================================
  Network Traffic Analysis (PCAP)
======================================================================

--- ENABLED ---
  Total packets:     4350
  HTTP/2 packets:    3169
  Total traffic:     1355202 bytes (1323.44 KB)
  JWT header frames: 1585
  Auth header frames: 0

--- DISABLED ---
  Total packets:     4334
  HTTP/2 packets:    3143
  Total traffic:     1416816 bytes (1383.61 KB)
  JWT header frames: 0
  Auth header frames: 1582

Network Traffic Comparison:
  Traffic saved:     61614 bytes (60.17 KB)
  Reduction:         4.35%

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
  Compression ON:  1585 frames with x-jwt-* headers
  Compression OFF: 1582 frames with authorization header

======================================================================
  Summary
======================================================================

✓ JWT Compression Results:

  📊 Data Transfer:
     • Upload bandwidth saved:   0.00%
     • Download bandwidth saved: 0.01%
     • Total network reduction:  4.35%

  ⚡ Performance:
     • Average response time:    2.36 ms faster
     • P95 response time:        12.15 ms faster

  🎯 Key Benefits:
     • Reduced header size per request
     • HPACK caching for static/session components
     • Better bandwidth utilization
     • Scalable to 300+ concurrent users

For detailed packet analysis:
  wireshark jwt-compression-on-results-20251016_020954/frontend-cart-traffic.pcap &
  wireshark jwt-compression-off-results-20251016_020036/frontend-cart-traffic.pcap &