#!/bin/bash

if [ -z "$1" ]; then
    echo "Usage: $0 <results-directory>"
    echo ""
    echo "Example: $0 ./jwt-compression-results-20251013_210000"
    exit 1
fi

RESULTS_DIR="$1"

if [ ! -d "${RESULTS_DIR}" ]; then
    echo "Error: Directory ${RESULTS_DIR} not found"
    exit 1
fi

echo "======================================================================"
echo "  JWT Compression Performance Analysis"
echo "======================================================================"
echo ""
echo "Analyzing results from: ${RESULTS_DIR}"
echo ""

# Check if pcap file exists
TRAFFIC_PCAP="${RESULTS_DIR}/frontend-cart-traffic.pcap"

if [ ! -f "${TRAFFIC_PCAP}" ]; then
    echo "Error: Traffic pcap file not found: ${TRAFFIC_PCAP}"
    exit 1
fi

echo "Analyzing capture file: ${TRAFFIC_PCAP}"
echo ""

echo "======================================================================"
echo "  K6 Load Test Summary"
echo "======================================================================"
echo ""

if [ -f "${RESULTS_DIR}/k6-summary.json" ]; then
    echo "Test Statistics:"
    cat "${RESULTS_DIR}/k6-summary.json" | jq -r '
        "  Total requests: \(.metrics.http_reqs.values.count // "N/A")",
        "  Failed requests: \(.metrics.http_req_failed.values.passes // 0)",
        "  Success rate: \(100 - (.metrics.http_req_failed.values.rate * 100) // 100)%",
        "  Avg response time: \(.metrics.http_req_duration.values.avg // "N/A")ms",
        "  p95 response time: \(.metrics.http_req_duration.values["p(95)"] // "N/A")ms",
        "  JWT renewals: \(.metrics.jwt_renewals.values.count // "N/A")",
        "  Cart operations: \(.metrics.cart_operations.values.count // "N/A")"
    ' 2>/dev/null || echo "  Could not parse k6 summary"
else
    echo "  k6 summary not found"
fi

echo ""
echo "======================================================================"
echo "  HTTP/2 Traffic Analysis (Frontend → CartService)"
echo "======================================================================"
echo ""

# Check if tshark is available
if ! command -v tshark &> /dev/null; then
    echo "Warning: tshark not installed. Install with: sudo apt-get install tshark"
    echo ""
    echo "Pcap files available for manual analysis:"
    ls -lh "${FRONTEND_PCAP}" "${CART_PCAP}"
    exit 0
fi

# Analyze HTTP/2 HEADERS frames
echo "Analyzing HTTP/2 HEADERS frames..."
echo ""

# Extract all HEADERS frame sizes
tshark -r "${TRAFFIC_PCAP}" -Y 'http2.type==1' -T fields \
    -e frame.number \
    -e frame.time_relative \
    -e frame.len \
    -e http2.header.length \
    -e http2.headers 2>/dev/null > /tmp/headers_analysis.txt

if [ ! -s /tmp/headers_analysis.txt ]; then
    echo "No HTTP/2 HEADERS frames found in capture"
    exit 0
fi

# Count frames
TOTAL_FRAMES=$(wc -l < /tmp/headers_analysis.txt)
echo "Total HEADERS frames captured: ${TOTAL_FRAMES}"
echo ""

# Calculate statistics
echo "Frame Size Statistics:"
awk '{print $3}' /tmp/headers_analysis.txt | sort -n | awk '
BEGIN {
    sum=0; count=0; min=999999; max=0;
}
{
    sum+=$1; count++;
    if($1<min) min=$1;
    if($1>max) max=$1;
    frames[count]=$1;
}
END {
    avg=sum/count;
    
    # Calculate median
    if(count%2==1) {
        median=frames[int(count/2)+1];
    } else {
        median=(frames[count/2]+frames[count/2+1])/2;
    }
    
    printf "  Minimum frame size: %d bytes\n", min;
    printf "  Maximum frame size: %d bytes\n", max;
    printf "  Average frame size: %.2f bytes\n", avg;
    printf "  Median frame size: %.2f bytes\n", median;
}'

echo ""
echo "Frame Size Distribution:"
awk '{print $3}' /tmp/headers_analysis.txt | sort -n | uniq -c | sort -rn | head -10 | \
    awk '{printf "  %s bytes: %s occurrences\n", $2, $1}'

echo ""
echo "======================================================================"
echo "  HPACK Compression Efficiency Analysis"
echo "======================================================================"
echo ""

# Look for JWT headers in frames
echo "Searching for JWT-related headers..."
tshark -r "${TRAFFIC_PCAP}" -Y 'http2.type==1 && (http2.header.name contains "jwt" || http2.header.name == "authorization")' \
    -T fields -e frame.number -e frame.time_relative -e frame.len 2>/dev/null > /tmp/jwt_frames.txt

if [ -s /tmp/jwt_frames.txt ]; then
    JWT_FRAME_COUNT=$(wc -l < /tmp/jwt_frames.txt)
    echo "Frames containing JWT headers: ${JWT_FRAME_COUNT}"
    echo ""
    
    # Group by time periods to identify JWT renewal
    echo "JWT Frame Timeline (showing potential compression):"
    awk '
    {
        frame=$1; time=$2; size=$3;
        if(NR<=5) {
            printf "  Frame %5s @ %8.2fs: %5d bytes (COLD cache - first JWT)\n", frame, time, size;
        } else if(time > 125 && time < 135 && !printed_renewal) {
            printf "  ...\n";
            printf "  Frame %5s @ %8.2fs: %5d bytes (JWT RENEWAL - new session)\n", frame, time, size;
            printed_renewal=1;
        } else if(time > 135 && NR > 5 && !printed_warm) {
            printf "  Frame %5s @ %8.2fs: %5d bytes (WARM cache - cached headers)\n", frame, time, size;
            printed_warm=1;
        }
    }
    ' /tmp/jwt_frames.txt | head -20
    
    echo ""
    
    # Calculate compression ratio
    echo "Estimated Compression Ratio:"
    awk '
    BEGIN {
        cold_sum=0; cold_count=0;
        warm_sum=0; warm_count=0;
    }
    {
        time=$2; size=$3;
        if(time < 10) {
            cold_sum += size;
            cold_count++;
        } else if(time > 135) {
            warm_sum += size;
            warm_count++;
        }
    }
    END {
        if(cold_count > 0) {
            cold_avg = cold_sum/cold_count;
            printf "  Cold cache (first 10s): %.2f bytes avg (%d samples)\n", cold_avg, cold_count;
        }
        if(warm_count > 0) {
            warm_avg = warm_sum/warm_count;
            printf "  Warm cache (after 135s): %.2f bytes avg (%d samples)\n", warm_avg, warm_count;
        }
        if(cold_count > 0 && warm_count > 0) {
            savings = ((cold_avg - warm_avg) / cold_avg) * 100;
            printf "  Bandwidth savings: %.1f%%\n", savings;
        }
    }
    ' /tmp/jwt_frames.txt
else
    echo "No JWT headers found in capture (this might be normal if using cookies)"
fi

echo ""
echo "======================================================================"
echo "  Detailed Analysis Available"
echo "======================================================================"
echo ""
echo "For detailed packet analysis, use:"
echo "  wireshark ${TRAFFIC_PCAP}"
echo ""
echo "Or use tshark to extract specific headers:"
echo "  tshark -r ${TRAFFIC_PCAP} -Y 'http2' -V | grep -A 20 'Header:'"
echo ""
echo "======================================================================"

# Cleanup
rm -f /tmp/headers_analysis.txt /tmp/jwt_frames.txt
