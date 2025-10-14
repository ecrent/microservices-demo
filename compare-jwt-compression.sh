#!/bin/bash

ENABLED_DIR="jwt-compression-on-results-20251014_035853"
DISABLED_DIR="jwt-compression-off-results-20251014_041345"

echo "======================================================================"
echo "  JWT Compression Performance Comparison"
echo "======================================================================"
echo ""
echo "Comparing:"
echo "  ENABLED:  ${ENABLED_DIR}"
echo "  DISABLED: ${DISABLED_DIR}"
echo ""

# ====================================================================
# K6 Test Results Comparison
# ====================================================================
echo "======================================================================"
echo "  K6 Load Test Comparison"
echo "======================================================================"
echo ""

echo "--- JWT COMPRESSION ENABLED ---"
if [ -f "${ENABLED_DIR}/k6-summary.json" ]; then
    cat "${ENABLED_DIR}/k6-summary.json" | jq -r '
        "  Total requests: \(.metrics.http_reqs.values.count // "N/A")",
        "  Failed requests: \(.metrics.http_req_failed.values.passes // 0)",
        "  Success rate: \(100 - ((.metrics.http_req_failed.values.rate // 0) * 100))%",
        "  Avg response time: \(.metrics.http_req_duration.values.avg // "N/A")ms",
        "  p95 response time: \(.metrics.http_req_duration.values["p(95)"] // "N/A")ms",
        "  p99 response time: \(.metrics.http_req_duration.values["p(99)"] // "N/A")ms"
    ' 2>/dev/null
else
    echo "  Summary file not found"
fi

echo ""
echo "--- JWT COMPRESSION DISABLED ---"
if [ -f "${DISABLED_DIR}/k6-summary.json" ]; then
    cat "${DISABLED_DIR}/k6-summary.json" | jq -r '
        "  Total requests: \(.metrics.http_reqs.values.count // "N/A")",
        "  Failed requests: \(.metrics.http_req_failed.values.passes // 0)",
        "  Success rate: \(100 - ((.metrics.http_req_failed.values.rate // 0) * 100))%",
        "  Avg response time: \(.metrics.http_req_duration.values.avg // "N/A")ms",
        "  p95 response time: \(.metrics.http_req_duration.values["p(95)"] // "N/A")ms",
        "  p99 response time: \(.metrics.http_req_duration.values["p(99)"] // "N/A")ms"
    ' 2>/dev/null
else
    echo "  Summary file not found"
fi

echo ""

# ====================================================================
# Network Traffic Analysis
# ====================================================================
echo "======================================================================"
echo "  Network Traffic Analysis (Frontend → CartService)"
echo "======================================================================"
echo ""

if ! command -v tshark &> /dev/null; then
    echo "Warning: tshark not installed. Skipping packet analysis."
    echo "Install with: sudo apt-get install tshark"
    echo ""
    exit 0
fi

# Analyze ENABLED capture
ENABLED_PCAP="${ENABLED_DIR}/frontend-cart-traffic.pcap"
DISABLED_PCAP="${DISABLED_DIR}/frontend-cart-traffic.pcap"

analyze_pcap() {
    local PCAP=$1
    local LABEL=$2
    
    if [ ! -f "${PCAP}" ]; then
        echo "  ${LABEL}: Capture file not found"
        return
    fi
    
    echo "--- ${LABEL} ---"
    
    # Count total packets
    TOTAL_PACKETS=$(tshark -r "${PCAP}" 2>/dev/null | wc -l)
    echo "  Total packets: ${TOTAL_PACKETS}"
    
    # Count HTTP/2 packets (decode gRPC port 7070 as HTTP/2)
    HTTP2_PACKETS=$(tshark -r "${PCAP}" -d tcp.port==7070,http2 -Y 'http2' 2>/dev/null | wc -l)
    echo "  HTTP/2 packets: ${HTTP2_PACKETS}"
    
    # Analyze HEADERS frames
    tshark -r "${PCAP}" -d tcp.port==7070,http2 -Y 'http2.type==1' -T fields \
        -e frame.number -e frame.len -e http2.header.length 2>/dev/null > /tmp/headers_${LABEL}.txt
    
    if [ -s /tmp/headers_${LABEL}.txt ]; then
        HEADERS_COUNT=$(wc -l < /tmp/headers_${LABEL}.txt)
        echo "  HTTP/2 HEADERS frames: ${HEADERS_COUNT}"
        
        # Calculate statistics
        awk '{sum+=$2; count++} END {
            if(count>0) printf "  Avg frame size: %.2f bytes\n", sum/count
        }' /tmp/headers_${LABEL}.txt
        
        # Get min/max
        awk '{print $2}' /tmp/headers_${LABEL}.txt | sort -n | awk '
            NR==1 {min=$1}
            {max=$1}
            END {
                printf "  Min frame size: %d bytes\n", min;
                printf "  Max frame size: %d bytes\n", max;
            }
        '
    else
        echo "  No HEADERS frames found"
    fi
    
    # Calculate total bytes transferred
    TOTAL_BYTES=$(tshark -r "${PCAP}" -T fields -e frame.len 2>/dev/null | awk '{sum+=$1} END {print sum}')
    if [ ! -z "${TOTAL_BYTES}" ] && [ "${TOTAL_BYTES}" -gt 0 ]; then
        KB=$(awk "BEGIN {printf \"%.2f\", ${TOTAL_BYTES}/1024}")
        echo "  Total traffic: ${TOTAL_BYTES} bytes (${KB} KB)"
    fi
    
    echo ""
}

analyze_pcap "${ENABLED_PCAP}" "JWT COMPRESSION ENABLED"
analyze_pcap "${DISABLED_PCAP}" "JWT COMPRESSION DISABLED"

# ====================================================================
# Bandwidth Savings Calculation
# ====================================================================
echo "======================================================================"
echo "  Bandwidth Savings Analysis"
echo "======================================================================"
echo ""

if [ -f /tmp/headers_JWT\ COMPRESSION\ ENABLED.txt ] && [ -f /tmp/headers_JWT\ COMPRESSION\ DISABLED.txt ]; then
    
    ENABLED_AVG=$(awk '{sum+=$2; count++} END {if(count>0) print sum/count; else print 0}' /tmp/headers_JWT\ COMPRESSION\ ENABLED.txt)
    DISABLED_AVG=$(awk '{sum+=$2; count++} END {if(count>0) print sum/count; else print 0}' /tmp/headers_JWT\ COMPRESSION\ DISABLED.txt)
    
    ENABLED_TOTAL=$(awk '{sum+=$2} END {print sum}' /tmp/headers_JWT\ COMPRESSION\ ENABLED.txt)
    DISABLED_TOTAL=$(awk '{sum+=$2} END {print sum}' /tmp/headers_JWT\ COMPRESSION\ DISABLED.txt)
    
    echo "Average HEADERS Frame Size:"
    printf "  With compression:    %.2f bytes\n" ${ENABLED_AVG}
    printf "  Without compression: %.2f bytes\n" ${DISABLED_AVG}
    
    SAVINGS=$(awk "BEGIN {if(${DISABLED_AVG}>0) printf \"%.2f\", (${DISABLED_AVG} - ${ENABLED_AVG}) / ${DISABLED_AVG} * 100; else print 0}")
    if [ ! -z "${SAVINGS}" ] && [ "$(awk "BEGIN {print (${SAVINGS} != 0)}")" -eq 1 ]; then
        printf "  Bandwidth savings:   %s%%\n" ${SAVINGS}
    fi
    
    echo ""
    echo "Total HEADERS Traffic:"
    ENABLED_KB=$(awk "BEGIN {printf \"%.2f\", ${ENABLED_TOTAL}/1024}")
    DISABLED_KB=$(awk "BEGIN {printf \"%.2f\", ${DISABLED_TOTAL}/1024}")
    printf "  With compression:    %d bytes (%s KB)\n" ${ENABLED_TOTAL} ${ENABLED_KB}
    printf "  Without compression: %d bytes (%s KB)\n" ${DISABLED_TOTAL} ${DISABLED_KB}
    
    if [ ${DISABLED_TOTAL} -gt 0 ]; then
        TOTAL_SAVINGS=$(awk "BEGIN {printf \"%.2f\", (${DISABLED_TOTAL} - ${ENABLED_TOTAL}) / ${DISABLED_TOTAL} * 100}")
        BYTES_SAVED=$((DISABLED_TOTAL - ENABLED_TOTAL))
        SAVED_KB=$(awk "BEGIN {printf \"%.2f\", ${BYTES_SAVED}/1024}")
        printf "  Total bytes saved:   %d bytes (%s KB)\n" ${BYTES_SAVED} ${SAVED_KB}
        printf "  Total savings:       %s%%\n" ${TOTAL_SAVINGS}
    fi
    
else
    echo "Unable to calculate savings - missing packet data"
fi

echo ""
echo "======================================================================"
echo "  Detailed Analysis"
echo "======================================================================"
echo ""

# Analyze JWT header presence
echo "JWT Header Analysis:"
echo ""

for PCAP_FILE in "${ENABLED_PCAP}" "${DISABLED_PCAP}"; do
    if [ -f "${PCAP_FILE}" ]; then
        BASENAME=$(basename "${PCAP_FILE}")
        echo "--- ${BASENAME} ---"
        
        # Check for JWT headers (decode gRPC as HTTP/2)
        JWT_COUNT=$(tshark -r "${PCAP_FILE}" -d tcp.port==7070,http2 -Y 'http2.header.name contains "jwt"' 2>/dev/null | wc -l)
        AUTH_COUNT=$(tshark -r "${PCAP_FILE}" -d tcp.port==7070,http2 -Y 'http2.header.name == "authorization"' 2>/dev/null | wc -l)
        
        echo "  Frames with x-jwt-* headers: ${JWT_COUNT}"
        echo "  Frames with authorization header: ${AUTH_COUNT}"
        
        # Sample header names
        echo "  Header names found:"
        tshark -r "${PCAP_FILE}" -d tcp.port==7070,http2 -Y 'http2.type==1' -T fields -e http2.header.name 2>/dev/null | \
            grep -E 'jwt|authorization' | sort | uniq -c | head -10 | sed 's/^/    /'
        
        echo ""
    fi
done

echo "======================================================================"
echo "  Summary"
echo "======================================================================"
echo ""
echo "JWT Compression implementation splits the JWT into 4 headers:"
echo "  - x-jwt-static:  Cached by HPACK (1 byte after first request)"
echo "  - x-jwt-session: Cached by HPACK (1 byte after first request)"
echo "  - x-jwt-dynamic: NOT cached (full size every request)"
echo "  - x-jwt-sig:     NOT cached (full size every request)"
echo ""
echo "Without compression, the full JWT is sent in the authorization header"
echo "every request with no caching benefit."
echo ""
echo "For detailed Wireshark analysis:"
echo "  wireshark ${ENABLED_PCAP} &"
echo "  wireshark ${DISABLED_PCAP} &"
echo ""
echo "======================================================================"

# Cleanup
rm -f /tmp/headers_*.txt
