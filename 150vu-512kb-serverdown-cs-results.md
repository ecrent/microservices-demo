======================================================================
  JWT Compression Performance Comparison
======================================================================

Comparing:
  ENABLED:  jwt-compression-results-150-on-512kb-serverdown-cs-20251207_174055
  DISABLED: jwt-compression-results-150-off-512kb-serverdown-cs-20251207_175106

======================================================================
  K6 Load Test Results
======================================================================

--- ENABLED ---
  Iterations:        440
  Rate:              1.07 iter/s
  Data sent:         6954.06 KB (7120954 bytes)
  Data received:     45580.24 KB (46674169 bytes)
  Avg response time: 45.71 ms
  P95 response time: 185.63 ms
  P99 response time: 0.00 ms
  Failed requests:   136 (2.97%)
  Passed checks:     3164
  Failed checks:     136

--- DISABLED ---
  Iterations:        420
  Rate:              1.02 iter/s
  Data sent:         6871.96 KB (7036892 bytes)
  Data received:     44739.74 KB (45813496 bytes)
  Avg response time: 63.29 ms
  P95 response time: 209.93 ms
  P99 response time: 0.00 ms
  Failed requests:   169 (3.75%)
  Passed checks:     3131
  Failed checks:     169

======================================================================
  Performance Improvements
======================================================================

Data Sent (Upload):
  Compression OFF:   7036892 bytes
  Compression ON:    7120954 bytes
  Bytes difference:  -84062 bytes

Data Received (Download):
  Compression OFF:   45813496 bytes
  Compression ON:    46674169 bytes
  Bytes difference:  -860673 bytes

Response Time:
  Compression OFF:   63.29 ms (avg), 209.93 ms (p95)
  Compression ON:    45.71 ms (avg), 185.63 ms (p95)
  Avg improvement:   17.58 ms faster
  P95 improvement:   24.30 ms faster

======================================================================
  Network Traffic Analysis (PCAP)
======================================================================

--- ENABLED ---
  Total packets:     3595
  HTTP/2 packets:    2555
  Total traffic:     1023528 bytes (999.54 KB)
  x-jwt-header frames:  1274
  x-jwt-payload values: 1320 (detected by JSON content)
  x-jwt-sig values:     1320 (detected by signature pattern)
  authorization frames: 0

  \033[0;36mHPACK Header Analysis (Compressed Format):\033[0m
    x-jwt-header size:  ~4 bytes (base64url, HPACK indexed)
    x-jwt-payload size: ~52 bytes (raw JSON)
    x-jwt-sig size:     ~342 bytes (base64url)

--- DISABLED ---
  Total packets:     3369
  HTTP/2 packets:    2371
  Total traffic:     1113351 bytes (1087.26 KB)
  x-jwt-header frames:  0
  x-jwt-payload values: 0 (detected by JSON content)
  x-jwt-sig values:     0 (detected by signature pattern)
  authorization frames: 1208

  \033[0;36mAuthorization Header Analysis (Standard Format):\033[0m
    authorization size: ~4 bytes (full JWT)

Network Traffic Comparison:
  Traffic saved:     89823 bytes (87.72 KB)
  Reduction:         8.07%

======================================================================
  gRPC Latency Analysis (Frontend ↔ CartService)
======================================================================

--- ENABLED ---
  gRPC streams analyzed: 1249
  Latency (request → response):
    Min:     0.328 ms
    Avg:     0.706 ms
    P50:     0.604 ms
    P95:     1.431 ms
    P99:     2.560 ms
    Max:     6.620 ms

--- DISABLED ---
  gRPC streams analyzed: 1150
  Latency (request → response):
    Min:     0.332 ms
    Avg:     3.027 ms
    P50:     0.624 ms
    P95:     2.106 ms
    P99:     30.231 ms
    Max:     1066.930 ms

gRPC Latency Comparison (Frontend → CartService):

  Metric       Compression ON Compression OFF   Difference
  ------       -------------- ---------------   ----------
  Avg                0.706 ms       3.027 ms 2.321 ms faster
  P50                0.604 ms       0.624 ms 0.020 ms faster
  P95                1.431 ms       2.106 ms 0.675 ms faster
  P99                2.560 ms      30.231 ms 27.671 ms faster

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
    • x-jwt-header frames:  1274
    • x-jwt-payload values: 1320 (detected by JSON content)
    • x-jwt-sig values:     1320 (detected by signature pattern)
  Compression OFF:
    • authorization frames: 1208

======================================================================
  Summary
======================================================================

✓ JWT Compression Results (3-Header Format):

  📊 Data Transfer:
     • Upload bandwidth saved:   -1.19%
     • Download bandwidth saved: -1.88%
     • Total network reduction:  8.07%

  ⚡ Performance:
     • Average response time:    2.321 ms faster
     • P95 response time:        0.675 ms faster

  🔧 Implementation Details:
     • Headers sent:             3 (x-jwt-header, x-jwt-payload, x-jwt-sig)
     • x-jwt-header:             HPACK indexed after first request (~2 bytes)
     • Payload encoding:         Raw JSON (vs base64, ~25% smaller)
     • Signature encoding:       Base64url (unchanged)
For detailed packet analysis:
  wireshark jwt-compression-results-150-on-512kb-serverdown-cs-20251207_174055/frontend-cart-traffic.pcap &
  wireshark jwt-compression-results-150-off-512kb-serverdown-cs-20251207_175106/frontend-cart-traffic.pcap &

======================================================================