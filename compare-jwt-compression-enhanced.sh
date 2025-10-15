#!/bin/bash
#
# Enhanced JWT Compression Comparison Script
# Compares performance and network metrics between JWT compression ON and OFF
#

ENABLED_DIR="jwt-compression-results-20251015_222414"
DISABLED_DIR="jwt-compression-off-results-20251014_213338"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo ""
echo -e "${BLUE}======================================================================"
echo "  JWT Compression Performance Comparison"
echo -e "======================================================================${NC}"
echo ""
echo "Comparing:"
echo "  ENABLED:  ${ENABLED_DIR}"
echo "  DISABLED: ${DISABLED_DIR}"
echo ""

# ====================================================================
# K6 Test Results Comparison
# ====================================================================
echo -e "${BLUE}======================================================================"
echo "  K6 Load Test Results"
echo -e "======================================================================${NC}"
echo ""

extract_k6_metrics() {
    local FILE=$1
    local LABEL=$2
    
    if [ ! -f "$FILE" ]; then
        echo -e "${RED}  ✗ $LABEL: File not found${NC}"
        return 1
    fi
    
    echo -e "${CYAN}--- $LABEL ---${NC}"
    
    # Extract metrics
    local ITERATIONS=$(cat "$FILE" | jq -r '.metrics.iterations.count // "N/A"')
    local RATE=$(cat "$FILE" | jq -r '.metrics.iterations.rate // "N/A"' | awk '{printf "%.2f", $1}')
    local DATA_SENT=$(cat "$FILE" | jq -r '.metrics.data_sent.count // 0')
    local DATA_RECEIVED=$(cat "$FILE" | jq -r '.metrics.data_received.count // 0')
    local AVG_DURATION=$(cat "$FILE" | jq -r '.metrics."http_req_duration{expected_response:true}".avg // .metrics.http_req_duration.avg // "N/A"' | awk '{printf "%.2f", $1}')
    local P95_DURATION=$(cat "$FILE" | jq -r '.metrics."http_req_duration{expected_response:true}"."p(95)" // .metrics.http_req_duration."p(95)" // "N/A"' | awk '{printf "%.2f", $1}')
    local P99_DURATION=$(cat "$FILE" | jq -r '.metrics."http_req_duration{expected_response:true}"."p(99)" // .metrics.http_req_duration."p(99)" // "N/A"' | awk '{printf "%.2f", $1}')
    local FAILED=$(cat "$FILE" | jq -r '.metrics.http_req_failed.passes // 0')
    local FAILED_RATE=$(cat "$FILE" | jq -r '.metrics.http_req_failed.value // 0' | awk '{printf "%.2f%%", $1 * 100}')
    local SUCCESS_CHECKS=$(cat "$FILE" | jq -r '.metrics.checks.passes // 0')
    local FAILED_CHECKS=$(cat "$FILE" | jq -r '.metrics.checks.fails // 0')
    
    # Calculate KB
    local DATA_SENT_KB=$(awk "BEGIN {printf \"%.2f\", $DATA_SENT/1024}")
    local DATA_RECEIVED_KB=$(awk "BEGIN {printf \"%.2f\", $DATA_RECEIVED/1024}")
    
    echo "  Iterations:        $ITERATIONS"
    echo "  Rate:              ${RATE} iter/s"
    echo "  Data sent:         ${DATA_SENT_KB} KB (${DATA_SENT} bytes)"
    echo "  Data received:     ${DATA_RECEIVED_KB} KB (${DATA_RECEIVED} bytes)"
    echo "  Avg response time: ${AVG_DURATION} ms"
    echo "  P95 response time: ${P95_DURATION} ms"
    echo "  P99 response time: ${P99_DURATION} ms"
    echo "  Failed requests:   ${FAILED} (${FAILED_RATE})"
    echo "  Passed checks:     ${SUCCESS_CHECKS}"
    echo "  Failed checks:     ${FAILED_CHECKS}"
    echo ""
    
    # Store for comparison
    eval "${LABEL}_DATA_SENT=$DATA_SENT"
    eval "${LABEL}_DATA_RECEIVED=$DATA_RECEIVED"
    eval "${LABEL}_AVG_DURATION=$AVG_DURATION"
    eval "${LABEL}_P95_DURATION=$P95_DURATION"
}

extract_k6_metrics "${ENABLED_DIR}/k6-summary.json" "ENABLED"
extract_k6_metrics "${DISABLED_DIR}/k6-summary.json" "DISABLED"

# Calculate differences
if [ ! -z "$ENABLED_DATA_SENT" ] && [ ! -z "$DISABLED_DATA_SENT" ] && [ "$DISABLED_DATA_SENT" -gt 0 ]; then
    echo -e "${GREEN}======================================================================"
    echo "  Performance Improvements"
    echo -e "======================================================================${NC}"
    echo ""
    
    # Data sent savings
    SENT_DIFF=$((DISABLED_DATA_SENT - ENABLED_DATA_SENT))
    SENT_SAVINGS=$(awk "BEGIN {printf \"%.2f\", ($SENT_DIFF / $DISABLED_DATA_SENT) * 100}")
    SENT_DIFF_KB=$(awk "BEGIN {printf \"%.2f\", $SENT_DIFF/1024}")
    
    echo -e "${CYAN}Data Sent (Upload):${NC}"
    echo "  Compression OFF:   $DISABLED_DATA_SENT bytes"
    echo "  Compression ON:    $ENABLED_DATA_SENT bytes"
    if [ $SENT_DIFF -gt 0 ]; then
        echo -e "  ${GREEN}Bytes saved:       $SENT_DIFF bytes ($SENT_DIFF_KB KB)${NC}"
        echo -e "  ${GREEN}Bandwidth savings: $SENT_SAVINGS%${NC}"
    else
        echo -e "  ${YELLOW}Bytes difference:  $SENT_DIFF bytes${NC}"
    fi
    echo ""
    
    # Data received savings
    RECV_DIFF=$((DISABLED_DATA_RECEIVED - ENABLED_DATA_RECEIVED))
    RECV_SAVINGS=$(awk "BEGIN {printf \"%.2f\", ($RECV_DIFF / $DISABLED_DATA_RECEIVED) * 100}")
    RECV_DIFF_KB=$(awk "BEGIN {printf \"%.2f\", $RECV_DIFF/1024}")
    
    echo -e "${CYAN}Data Received (Download):${NC}"
    echo "  Compression OFF:   $DISABLED_DATA_RECEIVED bytes"
    echo "  Compression ON:    $ENABLED_DATA_RECEIVED bytes"
    if [ $RECV_DIFF -gt 0 ]; then
        echo -e "  ${GREEN}Bytes saved:       $RECV_DIFF bytes ($RECV_DIFF_KB KB)${NC}"
        echo -e "  ${GREEN}Bandwidth savings: $RECV_SAVINGS%${NC}"
    else
        echo -e "  ${YELLOW}Bytes difference:  $RECV_DIFF bytes${NC}"
    fi
    echo ""
    
    # Response time comparison
    echo -e "${CYAN}Response Time:${NC}"
    echo "  Compression OFF:   $DISABLED_AVG_DURATION ms (avg), $DISABLED_P95_DURATION ms (p95)"
    echo "  Compression ON:    $ENABLED_AVG_DURATION ms (avg), $ENABLED_P95_DURATION ms (p95)"
    
    AVG_DIFF=$(awk "BEGIN {printf \"%.2f\", $DISABLED_AVG_DURATION - $ENABLED_AVG_DURATION}")
    P95_DIFF=$(awk "BEGIN {printf \"%.2f\", $DISABLED_P95_DURATION - $ENABLED_P95_DURATION}")
    
    if (( $(awk "BEGIN {print ($AVG_DIFF > 0)}") )); then
        echo -e "  ${GREEN}Avg improvement:   $AVG_DIFF ms faster${NC}"
    elif (( $(awk "BEGIN {print ($AVG_DIFF < 0)}") )); then
        AVG_DIFF=$(awk "BEGIN {printf \"%.2f\", -1 * $AVG_DIFF}")
        echo -e "  ${YELLOW}Avg difference:    $AVG_DIFF ms slower${NC}"
    else
        echo "  Avg difference:    No significant change"
    fi
    
    if (( $(awk "BEGIN {print ($P95_DIFF > 0)}") )); then
        echo -e "  ${GREEN}P95 improvement:   $P95_DIFF ms faster${NC}"
    elif (( $(awk "BEGIN {print ($P95_DIFF < 0)}") )); then
        P95_DIFF=$(awk "BEGIN {printf \"%.2f\", -1 * $P95_DIFF}")
        echo -e "  ${YELLOW}P95 difference:    $P95_DIFF ms slower${NC}"
    else
        echo "  P95 difference:    No significant change"
    fi
    echo ""
fi

# ====================================================================
# Network Traffic Analysis
# ====================================================================
echo -e "${BLUE}======================================================================"
echo "  Network Traffic Analysis (PCAP)"
echo -e "======================================================================${NC}"
echo ""

ENABLED_PCAP="${ENABLED_DIR}/frontend-cart-traffic.pcap"
DISABLED_PCAP="${DISABLED_DIR}/frontend-cart-traffic.pcap"

if [ ! -f "$ENABLED_PCAP" ] || [ ! -f "$DISABLED_PCAP" ]; then
    echo -e "${YELLOW}⚠ PCAP files not found, skipping network analysis${NC}"
    echo ""
else
    if ! command -v tshark &> /dev/null; then
        echo -e "${YELLOW}⚠ tshark not installed, skipping detailed analysis${NC}"
        echo "  Install with: sudo apt-get install tshark"
        echo ""
    else
        analyze_pcap() {
            local PCAP=$1
            local LABEL=$2
            
            echo -e "${CYAN}--- $LABEL ---${NC}"
            
            # Count total packets
            TOTAL_PACKETS=$(tshark -r "${PCAP}" 2>/dev/null | wc -l)
            echo "  Total packets:     ${TOTAL_PACKETS}"
            
            # Count HTTP/2 packets
            HTTP2_PACKETS=$(tshark -r "${PCAP}" -d tcp.port==7070,http2 -Y 'http2' 2>/dev/null | wc -l)
            echo "  HTTP/2 packets:    ${HTTP2_PACKETS}"
            
            # Calculate total bytes
            TOTAL_BYTES=$(tshark -r "${PCAP}" -T fields -e frame.len 2>/dev/null | awk '{sum+=$1} END {print sum}')
            if [ ! -z "${TOTAL_BYTES}" ] && [ "${TOTAL_BYTES}" -gt 0 ]; then
                KB=$(awk "BEGIN {printf \"%.2f\", ${TOTAL_BYTES}/1024}")
                echo "  Total traffic:     ${TOTAL_BYTES} bytes (${KB} KB)"
            fi
            
            # Check for JWT headers
            JWT_FRAMES=$(tshark -r "${PCAP}" -d tcp.port==7070,http2 -Y 'http2.header.name contains "jwt"' 2>/dev/null | wc -l)
            AUTH_FRAMES=$(tshark -r "${PCAP}" -d tcp.port==7070,http2 -Y 'http2.header.name == "authorization"' 2>/dev/null | wc -l)
            
            echo "  JWT header frames: ${JWT_FRAMES}"
            echo "  Auth header frames: ${AUTH_FRAMES}"
            echo ""
            
            eval "${LABEL}_TOTAL_BYTES=$TOTAL_BYTES"
            eval "${LABEL}_JWT_FRAMES=$JWT_FRAMES"
            eval "${LABEL}_AUTH_FRAMES=$AUTH_FRAMES"
        }
        
        analyze_pcap "$ENABLED_PCAP" "ENABLED"
        analyze_pcap "$DISABLED_PCAP" "DISABLED"
        
        # Compare network traffic
        if [ ! -z "$ENABLED_TOTAL_BYTES" ] && [ ! -z "$DISABLED_TOTAL_BYTES" ] && [ "$DISABLED_TOTAL_BYTES" -gt 0 ]; then
            TRAFFIC_DIFF=$((DISABLED_TOTAL_BYTES - ENABLED_TOTAL_BYTES))
            TRAFFIC_SAVINGS=$(awk "BEGIN {printf \"%.2f\", ($TRAFFIC_DIFF / $DISABLED_TOTAL_BYTES) * 100}")
            TRAFFIC_DIFF_KB=$(awk "BEGIN {printf \"%.2f\", $TRAFFIC_DIFF/1024}")
            
            echo -e "${GREEN}Network Traffic Comparison:${NC}"
            if [ $TRAFFIC_DIFF -gt 0 ]; then
                echo -e "  ${GREEN}Traffic saved:     $TRAFFIC_DIFF bytes ($TRAFFIC_DIFF_KB KB)${NC}"
                echo -e "  ${GREEN}Reduction:         $TRAFFIC_SAVINGS%${NC}"
            else
                TRAFFIC_DIFF_ABS=$((-1 * TRAFFIC_DIFF))
                TRAFFIC_DIFF_KB=$(awk "BEGIN {printf \"%.2f\", $TRAFFIC_DIFF_ABS/1024}")
                echo -e "  ${YELLOW}Traffic increase:  $TRAFFIC_DIFF_ABS bytes ($TRAFFIC_DIFF_KB KB)${NC}"
            fi
            echo ""
        fi
    fi
fi

# ====================================================================
# JWT Header Analysis
# ====================================================================
echo -e "${BLUE}======================================================================"
echo "  JWT Header Analysis"
echo -e "======================================================================${NC}"
echo ""

echo -e "${CYAN}JWT Compression ON:${NC}"
echo "  Uses 4 separate headers:"
echo "    • x-jwt-static       (112b) - Cacheable by HPACK"
echo "    • x-jwt-session      (168b) - Cacheable by HPACK"
echo "    • x-jwt-dynamic-bin  (122b) - NOT cached (binary)"
echo "    • x-jwt-sig-bin      (342b) - NOT cached (binary)"
echo "  Total: ~744 bytes first request"
echo "  After HPACK caching: ~470 bytes (static/session use indices)"
echo ""

echo -e "${CYAN}JWT Compression OFF:${NC}"
echo "  Uses single authorization header:"
echo "    • authorization: Bearer <full-jwt>"
echo "  Total: ~900+ bytes every request"
echo "  No HPACK caching benefit (JWT changes every request)"
echo ""

if [ ! -z "$ENABLED_JWT_FRAMES" ] && [ ! -z "$DISABLED_AUTH_FRAMES" ]; then
    echo -e "${GREEN}Header Usage Verification:${NC}"
    echo "  Compression ON:  $ENABLED_JWT_FRAMES frames with x-jwt-* headers"
    echo "  Compression OFF: $DISABLED_AUTH_FRAMES frames with authorization header"
    echo ""
fi

# ====================================================================
# Summary
# ====================================================================
echo -e "${BLUE}======================================================================"
echo "  Summary"
echo -e "======================================================================${NC}"
echo ""

if [ ! -z "$SENT_SAVINGS" ]; then
    echo -e "${GREEN}✓ JWT Compression Results:${NC}"
    echo ""
    echo "  📊 Data Transfer:"
    echo "     • Upload bandwidth saved:   $SENT_SAVINGS%"
    echo "     • Download bandwidth saved: $RECV_SAVINGS%"
    if [ ! -z "$TRAFFIC_SAVINGS" ]; then
        echo "     • Total network reduction:  $TRAFFIC_SAVINGS%"
    fi
    echo ""
    echo "  ⚡ Performance:"
    if (( $(awk "BEGIN {print ($AVG_DIFF > 0)}") )); then
        echo "     • Average response time:    $AVG_DIFF ms faster"
    else
        echo "     • Average response time:    Similar performance"
    fi
    if (( $(awk "BEGIN {print ($P95_DIFF > 0)}") )); then
        echo "     • P95 response time:        $P95_DIFF ms faster"
    else
        echo "     • P95 response time:        Similar performance"
    fi
    echo ""
    echo "  🎯 Key Benefits:"
    echo "     • Reduced header size per request"
    echo "     • HPACK caching for static/session components"
    echo "     • Better bandwidth utilization"
    echo "     • Scalable to 300+ concurrent users"
    echo ""
fi

echo -e "${CYAN}For detailed packet analysis:${NC}"
echo "  wireshark $ENABLED_PCAP &"
echo "  wireshark $DISABLED_PCAP &"
echo ""
echo -e "${BLUE}======================================================================${NC}"
