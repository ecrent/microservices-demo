lts-150-on-512kb-cs-20251207_170337/frontend-cart-traffic.pcap
Analyzing pcap file: jwt-compression-results-150-on-512kb-cs-20251207_170337/frontend-cart-traffic.pcap
Extracting HTTP/2 headers individually...
Looking for headers: x-jwt-header, x-jwt-payload, x-jwt-sig
Processing 8557 lines of tshark output...

================================================================================
JWT HEADER HPACK INDEXING ANALYSIS REPORT (3-Header Format)
================================================================================

Pcap File: jwt-compression-results-150-on-512kb-cs-20251207_170337/frontend-cart-traffic.pcap
Total Frames with JWT Headers: 4285
Unique Sessions Detected: 590

================================================================================
HEADER INDEXING STATISTICS
================================================================================

Header               Total      Literal    Indexed    Index Rate   Unique Values  
--------------------------------------------------------------------------------
x-jwt-header         4320       606        3714         86.0%      1              
x-jwt-payload        4320       2994       1326         30.7%      890            
x-jwt-sig            4320       2994       1326         30.7%      890            
--------------------------------------------------------------------------------
TOTAL                12960      6594       6366         49.1%

================================================================================
HPACK DYNAMIC TABLE ANALYSIS
================================================================================

Header Name Indexing (name portion only):
Header               Name Indexed    Name Literal    Name Index Rate
----------------------------------------------------------------------
x-jwt-header         3714            606               86.0%
x-jwt-payload        4320            0                100.0%
x-jwt-sig            4320            0                100.0%

Header Value Size Statistics:
Header               Min Size     Max Size     Avg Size     Unique Values  
----------------------------------------------------------------------
x-jwt-header         36           36           36.0         1              
x-jwt-payload        413          413          413.0        890            
x-jwt-sig            342          342          342.0        890            

Estimated HPACK Dynamic Table Entry Sizes:
  • x-jwt-header entry: ~80 bytes (value=36 + name=12 + overhead=32)
  • x-jwt-payload entry: ~458 bytes (value=413 + name=13 + overhead=32)
  • x-jwt-sig entry: ~383 bytes (value=342 + name=9 + overhead=32)
  • Total per request: ~921 bytes

  With default 4KB table: ~4.4 user entries fit
  With 512KB table: ~569 user entries fit

================================================================================
ACTUAL BYTE SAVINGS ANALYSIS
================================================================================

--------------------------------------------------------------------------------
Breakdown: How bytes were transmitted
--------------------------------------------------------------------------------
Header               Potential    Literal Sent   Indexed Refs   Actual Sent    Saved       
--------------------------------------------------------------------------------
x-jwt-header            216,000         30,300     3714 (~7428)         37,728      178,272
x-jwt-payload         1,848,960      1,242,510     1326 (~2652)      1,245,162      603,798
x-jwt-sig             1,524,960      1,029,936     1326 (~2652)      1,032,588      492,372
--------------------------------------------------------------------------------
TOTAL                 3,589,920      2,315,478                         2,315,478    1,274,442

Overall compression: 35.5% reduction (3,589,920 → 2,315,478 bytes)

--------------------------------------------------------------------------------
Indexing Efficiency Analysis
--------------------------------------------------------------------------------

  x-jwt-header:
    • Total header occurrences: 4320
    • Unique values seen: 1
    • First occurrences (must be literal): 1
    • Reused from dynamic table (indexed): 3714
    • Value reuse rate: 100.0% (4319 reuses of 4320 total)
    • Cache hit rate: 86.0% (3714 hits of 4319 potential reuses)
    • Evicted before reuse: 605 (value was in table but got evicted)

  x-jwt-payload:
    • Total header occurrences: 4320
    • Unique values seen: 890
    • First occurrences (must be literal): 890
    • Reused from dynamic table (indexed): 1326
    • Value reuse rate: 79.4% (3430 reuses of 4320 total)
    • Cache hit rate: 38.7% (1326 hits of 3430 potential reuses)
    • Evicted before reuse: 2104 (value was in table but got evicted)

  x-jwt-sig:
    • Total header occurrences: 4320
    • Unique values seen: 890
    • First occurrences (must be literal): 890
    • Reused from dynamic table (indexed): 1326
    • Value reuse rate: 79.4% (3430 reuses of 4320 total)
    • Cache hit rate: 38.7% (1326 hits of 3430 potential reuses)
    • Evicted before reuse: 2104 (value was in table but got evicted)



 Analyzing pcap file: jwt-compression-results-150-off-512kb-cs-20251207_162059/frontend-cart-traffic.pcap
Extracting HTTP/2 frames with authorization header and indexing details...
Looking for header: authorization (Bearer JWT)
Processing 8343 lines of output...

================================================================================
AUTHORIZATION HEADER HPACK INDEXING ANALYSIS (Baseline - Compression OFF)
================================================================================

Pcap File: jwt-compression-results-150-off-512kb-cs-20251207_162059/frontend-cart-traffic.pcap
Total Frames Analyzed: 4193
Frames with Authorization Header: 4193
Unique Sessions Detected: 869

================================================================================
HEADER INDEXING STATISTICS
================================================================================

Header               Total      Literal    Indexed    Index Rate   Unique Values  
--------------------------------------------------------------------------------
authorization        4260       2972       1288         30.2%      869            

================================================================================
HPACK DYNAMIC TABLE ANALYSIS
================================================================================

Header Name Indexing:
  • 'authorization' name indexed: 4260 (100.0%)
  • 'authorization' name literal: 0

Header Value Size Statistics:
  • Min size: 938 bytes
  • Max size: 938 bytes
  • Avg size: 938.0 bytes
  • Unique values: 869

Estimated HPACK Dynamic Table Entry Size:
  • Entry size: ~983 bytes (value=938 + name=13 + overhead=32)

  With default 4KB table: ~4.2 entries fit
  With 512KB table: ~533 entries fit

================================================================================
ACTUAL BYTE SAVINGS ANALYSIS
================================================================================

--------------------------------------------------------------------------------
Breakdown: How bytes were transmitted
--------------------------------------------------------------------------------
Header               Potential    Literal Sent   Indexed Refs   Actual Sent    Saved       
--------------------------------------------------------------------------------
authorization         4,059,780      2,793,680     1288 (~2576)      2,796,256    1,263,524

Overall compression: 31.1% reduction (4,059,780 → 2,796,256 bytes)

--------------------------------------------------------------------------------
Indexing Efficiency Analysis
--------------------------------------------------------------------------------

  authorization:
    • Total header occurrences: 4260
    • Unique values seen: 869
    • First occurrences (must be literal): 868
    • Reused from dynamic table (indexed): 1288
    • Value reuse rate: 79.6% (3391 reuses of 4260 total)
    • Cache hit rate: 38.0% (1288 hits of 3392 potential reuses)
    • Evicted before reuse: 2103 (value was in table but got evicted)

================================================================================   