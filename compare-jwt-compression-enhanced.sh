#!/bin/bash
#
# Enhanced JWT Compression Comparison Script
# Compares performance and network metrics between JWT compression ON and OFF
#

ENABLED_DIR="jwt-compression-results-150-on-512kb-cs-20251207_170337"
DISABLED_DIR="jwt-compression-results-150-off-512kb-cs-20251207_162059"

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
            
            # Check for JWT headers (new 2-header format: x-jwt-payload, x-jwt-sig)
            JWT_PAYLOAD_FRAMES=$(tshark -r "${PCAP}" -d tcp.port==7070,http2 -Y 'http2.header.name == "x-jwt-payload"' 2>/dev/null | wc -l)
            JWT_SIG_FRAMES=$(tshark -r "${PCAP}" -d tcp.port==7070,http2 -Y 'http2.header.name == "x-jwt-sig"' 2>/dev/null | wc -l)
            AUTH_FRAMES=$(tshark -r "${PCAP}" -d tcp.port==7070,http2 -Y 'http2.header.name == "authorization"' 2>/dev/null | wc -l)
            
            # Total JWT-related frames (either header present)
            JWT_FRAMES=$((JWT_PAYLOAD_FRAMES > JWT_SIG_FRAMES ? JWT_PAYLOAD_FRAMES : JWT_SIG_FRAMES))
            
            echo "  x-jwt-payload frames: ${JWT_PAYLOAD_FRAMES}"
            echo "  x-jwt-sig frames:     ${JWT_SIG_FRAMES}"
            echo "  authorization frames: ${AUTH_FRAMES}"
            echo ""
            
            # Extract header sizes for HPACK analysis
            if [ "$JWT_PAYLOAD_FRAMES" -gt 0 ]; then
                echo "  ${CYAN}HPACK Header Analysis:${NC}"
                # Get sample header values to analyze size
                SAMPLE_PAYLOAD=$(tshark -r "${PCAP}" -d tcp.port==7070,http2 -Y 'http2.header.name == "x-jwt-payload"' -T fields -e http2.header.value 2>/dev/null | head -1)
                SAMPLE_SIG=$(tshark -r "${PCAP}" -d tcp.port==7070,http2 -Y 'http2.header.name == "x-jwt-sig"' -T fields -e http2.header.value 2>/dev/null | head -1)
                if [ ! -z "$SAMPLE_PAYLOAD" ]; then
                    PAYLOAD_LEN=${#SAMPLE_PAYLOAD}
                    echo "    x-jwt-payload size: ~${PAYLOAD_LEN} bytes (raw JSON)"
                fi
                if [ ! -z "$SAMPLE_SIG" ]; then
                    SIG_LEN=${#SAMPLE_SIG}
                    echo "    x-jwt-sig size:     ~${SIG_LEN} bytes (base64url)"
                fi
                echo ""
            fi
            
            if [ "$AUTH_FRAMES" -gt 0 ]; then
                echo "  ${CYAN}Authorization Header Analysis:${NC}"
                SAMPLE_AUTH=$(tshark -r "${PCAP}" -d tcp.port==7070,http2 -Y 'http2.header.name == "authorization"' -T fields -e http2.header.value 2>/dev/null | head -1)
                if [ ! -z "$SAMPLE_AUTH" ]; then
                    AUTH_LEN=${#SAMPLE_AUTH}
                    echo "    authorization size: ~${AUTH_LEN} bytes (full JWT)"
                fi
                echo ""
            fi
            
            eval "${LABEL}_TOTAL_BYTES=$TOTAL_BYTES"
            eval "${LABEL}_JWT_FRAMES=$JWT_FRAMES"
            eval "${LABEL}_JWT_PAYLOAD_FRAMES=$JWT_PAYLOAD_FRAMES"
            eval "${LABEL}_JWT_SIG_FRAMES=$JWT_SIG_FRAMES"
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
# gRPC Latency Analysis (Frontend ↔ CartService)
# ====================================================================
echo -e "${BLUE}======================================================================"
echo "  gRPC Latency Analysis (Frontend ↔ CartService)"
echo -e "======================================================================${NC}"
echo ""

analyze_grpc_latency() {
    local PCAP=$1
    local LABEL=$2
    
    if [ ! -f "$PCAP" ]; then
        echo -e "${RED}  ✗ $LABEL: PCAP file not found${NC}"
        return 1
    fi
    
    echo -e "${CYAN}--- $LABEL ---${NC}"
    
    # Create temporary file for stream analysis
    local TMPFILE=$(mktemp)
    local LATENCIES_FILE=$(mktemp)
    
    # Extract HTTP/2 streams with TCP stream ID
    # Use -Eseparator with tab, and occurrence=a to get all values
    tshark -r "${PCAP}" -d tcp.port==7070,http2 \
        -Y 'http2.streamid > 0' \
        -T fields \
        -e frame.time_relative \
        -e tcp.stream \
        -e http2.streamid \
        -E separator='	' \
        -E occurrence=f 2>/dev/null > "$TMPFILE"
    
    # Process to calculate per-stream latency
    # Each line has: time \t tcp_stream \t h2_stream (first occurrence only)
    awk -F'\t' '
    {
        time = $1
        tcp_stream = $2
        h2_stream = $3
        
        if (h2_stream == "" || h2_stream == "0" || h2_stream ~ /,/) next
        
        # Unique key: TCP connection + HTTP/2 stream
        key = tcp_stream "-" h2_stream
        
        # Record first time for each stream
        if (!(key in first_time)) {
            first_time[key] = time
        }
        
        # Track last time seen
        last_time[key] = time
        
        # Count frames per stream
        frame_count[key]++
    }
    END {
        for (k in first_time) {
            # Only count streams with multiple frames (request + response)
            if (frame_count[k] >= 2) {
                latency_ms = (last_time[k] - first_time[k]) * 1000
                # Filter reasonable latencies (0.001ms to 5000ms)
                if (latency_ms >= 0.001 && latency_ms < 5000) {
                    print latency_ms
                }
            }
        }
    }
    ' "$TMPFILE" > "$LATENCIES_FILE"
    
    # Calculate statistics
    local COUNT=$(wc -l < "$LATENCIES_FILE" | tr -d ' ')
    
    if [ "$COUNT" -gt 0 ]; then
        # Sort latencies for percentile calculation
        sort -n "$LATENCIES_FILE" > "${LATENCIES_FILE}.sorted"
        
        # Calculate avg, p50, p95, p99
        local AVG=$(awk '{sum+=$1} END {printf "%.3f", sum/NR}' "$LATENCIES_FILE")
        local MIN=$(head -1 "${LATENCIES_FILE}.sorted")
        local MAX=$(tail -1 "${LATENCIES_FILE}.sorted")
        
        # P50 (median)
        local P50_IDX=$(awk "BEGIN {printf \"%.0f\", $COUNT * 0.50}")
        [ "$P50_IDX" -lt 1 ] && P50_IDX=1
        local P50=$(sed -n "${P50_IDX}p" "${LATENCIES_FILE}.sorted")
        
        # P95
        local P95_IDX=$(awk "BEGIN {printf \"%.0f\", $COUNT * 0.95}")
        [ "$P95_IDX" -lt 1 ] && P95_IDX=1
        local P95=$(sed -n "${P95_IDX}p" "${LATENCIES_FILE}.sorted")
        
        # P99
        local P99_IDX=$(awk "BEGIN {printf \"%.0f\", $COUNT * 0.99}")
        [ "$P99_IDX" -lt 1 ] && P99_IDX=1
        local P99=$(sed -n "${P99_IDX}p" "${LATENCIES_FILE}.sorted")
        
        echo "  gRPC streams analyzed: ${COUNT}"
        echo "  Latency (request → response):"
        echo "    Min:     $(printf '%.3f' $MIN) ms"
        echo "    Avg:     ${AVG} ms"
        echo "    P50:     $(printf '%.3f' $P50) ms"
        echo "    P95:     $(printf '%.3f' $P95) ms"
        echo "    P99:     $(printf '%.3f' $P99) ms"
        echo "    Max:     $(printf '%.3f' $MAX) ms"
        echo ""
        
        # Store for comparison
        eval "${LABEL}_GRPC_COUNT=$COUNT"
        eval "${LABEL}_GRPC_AVG=$AVG"
        eval "${LABEL}_GRPC_P50=$P50"
        eval "${LABEL}_GRPC_P95=$P95"
        eval "${LABEL}_GRPC_P99=$P99"
        eval "${LABEL}_GRPC_MIN=$MIN"
        eval "${LABEL}_GRPC_MAX=$MAX"
        
        rm -f "${LATENCIES_FILE}.sorted"
    else
        echo "  No complete gRPC streams found in capture"
        echo ""
    fi
    
    rm -f "$TMPFILE" "$LATENCIES_FILE"
}

if [ -f "$ENABLED_PCAP" ] && [ -f "$DISABLED_PCAP" ] && command -v tshark &> /dev/null; then
    analyze_grpc_latency "$ENABLED_PCAP" "ENABLED"
    analyze_grpc_latency "$DISABLED_PCAP" "DISABLED"
    
    # Compare latencies
    if [ ! -z "$ENABLED_GRPC_AVG" ] && [ ! -z "$DISABLED_GRPC_AVG" ]; then
        echo -e "${GREEN}gRPC Latency Comparison (Frontend → CartService):${NC}"
        echo ""
        
        AVG_DIFF=$(awk "BEGIN {printf \"%.3f\", $DISABLED_GRPC_AVG - $ENABLED_GRPC_AVG}")
        P50_DIFF=$(awk "BEGIN {printf \"%.3f\", $DISABLED_GRPC_P50 - $ENABLED_GRPC_P50}")
        P95_DIFF=$(awk "BEGIN {printf \"%.3f\", $DISABLED_GRPC_P95 - $ENABLED_GRPC_P95}")
        P99_DIFF=$(awk "BEGIN {printf \"%.3f\", $DISABLED_GRPC_P99 - $ENABLED_GRPC_P99}")
        
        printf "  %-12s %12s %12s %12s\n" "Metric" "Compression ON" "Compression OFF" "Difference"
        printf "  %-12s %12s %12s %12s\n" "------" "--------------" "---------------" "----------"
        printf "  %-12s %11.3f ms %11.3f ms " "Avg" "$ENABLED_GRPC_AVG" "$DISABLED_GRPC_AVG"
        if (( $(awk "BEGIN {print ($AVG_DIFF > 0)}") )); then
            echo -e "${GREEN}${AVG_DIFF} ms faster${NC}"
        elif (( $(awk "BEGIN {print ($AVG_DIFF < 0)}") )); then
            echo -e "${YELLOW}$(awk "BEGIN {printf \"%.3f\", -1*$AVG_DIFF}") ms slower${NC}"
        else
            echo "no change"
        fi
        
        printf "  %-12s %11.3f ms %11.3f ms " "P50" "$ENABLED_GRPC_P50" "$DISABLED_GRPC_P50"
        if (( $(awk "BEGIN {print ($P50_DIFF > 0)}") )); then
            echo -e "${GREEN}${P50_DIFF} ms faster${NC}"
        elif (( $(awk "BEGIN {print ($P50_DIFF < 0)}") )); then
            echo -e "${YELLOW}$(awk "BEGIN {printf \"%.3f\", -1*$P50_DIFF}") ms slower${NC}"
        else
            echo "no change"
        fi
        
        printf "  %-12s %11.3f ms %11.3f ms " "P95" "$ENABLED_GRPC_P95" "$DISABLED_GRPC_P95"
        if (( $(awk "BEGIN {print ($P95_DIFF > 0)}") )); then
            echo -e "${GREEN}${P95_DIFF} ms faster${NC}"
        elif (( $(awk "BEGIN {print ($P95_DIFF < 0)}") )); then
            echo -e "${YELLOW}$(awk "BEGIN {printf \"%.3f\", -1*$P95_DIFF}") ms slower${NC}"
        else
            echo "no change"
        fi
        
        printf "  %-12s %11.3f ms %11.3f ms " "P99" "$ENABLED_GRPC_P99" "$DISABLED_GRPC_P99"
        if (( $(awk "BEGIN {print ($P99_DIFF > 0)}") )); then
            echo -e "${GREEN}${P99_DIFF} ms faster${NC}"
        elif (( $(awk "BEGIN {print ($P99_DIFF < 0)}") )); then
            echo -e "${YELLOW}$(awk "BEGIN {printf \"%.3f\", -1*$P99_DIFF}") ms slower${NC}"
        else
            echo "no change"
        fi
        echo ""
    fi
else
    echo -e "${YELLOW}⚠ PCAP files or tshark not available for latency analysis${NC}"
    echo ""
fi

# ====================================================================
# JWT Header Analysis
# ====================================================================
echo -e "${BLUE}======================================================================"
echo "  JWT Header Analysis"
echo -e "======================================================================${NC}"
echo ""

echo -e "${CYAN}Implementation Details:${NC}"
echo "  Compression ON (2-header format):"
echo "    • x-jwt-payload: Raw JSON payload (not base64 encoded)"
echo "    • x-jwt-sig:     Base64url signature only"
echo "    • JWT header:    Hardcoded constant (eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9)"
echo ""
echo "  Compression OFF (standard format):"
echo "    • authorization: Bearer <header>.<payload>.<signature>"
echo ""

if [ ! -z "$ENABLED_JWT_PAYLOAD_FRAMES" ] && [ ! -z "$DISABLED_AUTH_FRAMES" ]; then
    echo -e "${GREEN}Header Usage Verification:${NC}"
    echo "  Compression ON:"
    echo "    • x-jwt-payload frames: $ENABLED_JWT_PAYLOAD_FRAMES"
    echo "    • x-jwt-sig frames:     $ENABLED_JWT_SIG_FRAMES"
    echo "  Compression OFF:"
    echo "    • authorization frames: $DISABLED_AUTH_FRAMES"
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
    echo -e "${GREEN}✓ JWT Compression Results (2-Header Format):${NC}"
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
    echo "  🔧 Implementation Optimizations:"
    echo "     • Operations reduced:       14 → 2 (86% reduction)"
    echo "     • Headers sent:             4 → 2 (50% reduction)"
    echo "     • JWT header:               Hardcoded (eliminated from wire)"
    echo "     • Payload encoding:         Raw JSON (vs base64)"

fi

echo -e "${CYAN}For detailed packet analysis:${NC}"
echo "  wireshark $ENABLED_PCAP &"
echo "  wireshark $DISABLED_PCAP &"
echo ""
echo -e "${BLUE}======================================================================${NC}"
