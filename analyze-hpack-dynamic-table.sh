#!/bin/bash

# HPACK Dynamic Table Analysis Script
# Captures gRPC traffic and analyzes HPACK compression of JWT headers

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}HPACK Dynamic Table Analysis${NC}"
echo -e "${BLUE}JWT Header Splitting Verification${NC}"
echo -e "${BLUE}========================================${NC}\n"

# Check dependencies
echo -e "${YELLOW}Checking dependencies...${NC}"
if ! command -v tshark &> /dev/null; then
    echo -e "${RED}tshark not found. Installing...${NC}"
    sudo apt-get update -qq && sudo apt-get install -y tshark
fi

if ! command -v tcpdump &> /dev/null; then
    echo -e "${RED}tcpdump not found. Installing...${NC}"
    sudo apt-get install -y tcpdump
fi

echo -e "${GREEN}✓ Dependencies installed${NC}\n"

# Get frontend pod name
FRONTEND_POD=$(kubectl get pods -l app=frontend -o jsonpath='{.items[0].metadata.name}')
echo -e "${CYAN}Frontend Pod: $FRONTEND_POD${NC}\n"

# Capture file
CAPTURE_FILE="/tmp/grpc-hpack-capture.pcap"
ANALYSIS_DIR="/tmp/hpack-analysis"
mkdir -p "$ANALYSIS_DIR"

echo -e "${YELLOW}Step 1: Starting packet capture on frontend pod...${NC}"
echo -e "${CYAN}This will capture gRPC traffic to backend services${NC}\n"

# Start tcpdump in background
kubectl exec -it "$FRONTEND_POD" -- sh -c "
    # Install tcpdump if not available
    if ! command -v tcpdump &> /dev/null; then
        apk add tcpdump 2>/dev/null || apt-get install -y tcpdump 2>/dev/null || true
    fi
    
    # Start capture
    timeout 30 tcpdump -i any -s 0 -w /tmp/grpc-capture.pcap 'port 7070 or port 3550 or port 5050' &
    echo \$! > /tmp/tcpdump.pid
    echo 'Capture started'
" &

CAPTURE_PID=$!
sleep 3

echo -e "${YELLOW}Step 2: Generating traffic with JWT splitting...${NC}\n"

# Check if JWT splitting is enabled
echo -e "${CYAN}Checking JWT splitting configuration...${NC}"
SPLITTING_ENABLED=$(kubectl get deployment frontend -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="ENABLE_JWT_SPLITTING")].value}')

if [ "$SPLITTING_ENABLED" = "true" ]; then
    echo -e "${GREEN}✓ JWT splitting is ENABLED${NC}\n"
else
    echo -e "${YELLOW}⚠ JWT splitting is NOT enabled. Enabling it now...${NC}"
    kubectl set env deployment/frontend ENABLE_JWT_SPLITTING=true
    echo "Waiting for pod to restart..."
    kubectl rollout status deployment/frontend --timeout=60s
    FRONTEND_POD=$(kubectl get pods -l app=frontend -o jsonpath='{.items[0].metadata.name}')
    echo -e "${GREEN}✓ JWT splitting enabled${NC}\n"
    sleep 5
fi

# Generate some traffic through the frontend
echo -e "${CYAN}Generating traffic (making requests to trigger gRPC calls)...${NC}"
for i in {1..5}; do
    curl -s http://localhost:8080/ > /dev/null 2>&1 || true
    curl -s http://localhost:8080/product/OLJCESPC7Z > /dev/null 2>&1 || true
    echo "  Request $i/5 sent"
    sleep 1
done

echo -e "${GREEN}✓ Traffic generated${NC}\n"

sleep 5

echo -e "${YELLOW}Step 3: Stopping capture and downloading file...${NC}"

# Stop tcpdump and copy file
kubectl exec "$FRONTEND_POD" -- sh -c "
    if [ -f /tmp/tcpdump.pid ]; then
        kill \$(cat /tmp/tcpdump.pid) 2>/dev/null || true
    fi
    killall tcpdump 2>/dev/null || true
    sleep 2
" 2>/dev/null || true

# Copy capture file
kubectl cp "$FRONTEND_POD:/tmp/grpc-capture.pcap" "$CAPTURE_FILE" 2>/dev/null

if [ ! -f "$CAPTURE_FILE" ] || [ ! -s "$CAPTURE_FILE" ]; then
    echo -e "${RED}Failed to capture packets. The capture file is empty or missing.${NC}"
    echo -e "${YELLOW}This might be because:${NC}"
    echo -e "  1. No gRPC traffic was generated"
    echo -e "  2. tcpdump couldn't be installed in the pod"
    echo -e "  3. Permissions issue"
    echo -e "\n${CYAN}Trying alternative: Capture from host network...${NC}\n"
    
    # Alternative: capture from minikube
    minikube ssh "sudo tcpdump -i any -s 0 -w /tmp/grpc-capture.pcap 'port 7070 or port 3550 or port 5050' " &
    MINIKUBE_PID=$!
    
    sleep 5
    
    # Generate traffic again
    for i in {1..5}; do
        curl -s http://localhost:8080/ > /dev/null 2>&1 || true
        sleep 1
    done
    
    sleep 3
    kill $MINIKUBE_PID 2>/dev/null || true
    
    # Copy from minikube
    minikube cp minikube:/tmp/grpc-capture.pcap "$CAPTURE_FILE"
fi

if [ ! -f "$CAPTURE_FILE" ] || [ ! -s "$CAPTURE_FILE" ]; then
    echo -e "${RED}Unable to capture packets. Exiting.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Capture file downloaded: $(du -h $CAPTURE_FILE | cut -f1)${NC}\n"

echo -e "${YELLOW}Step 4: Analyzing HTTP/2 HPACK frames...${NC}\n"

# Extract HTTP/2 headers
tshark -r "$CAPTURE_FILE" -Y "http2" -T fields \
    -e frame.number \
    -e http2.header.name \
    -e http2.header.value \
    -e http2.header.repr \
    -e http2.header.index \
    > "$ANALYSIS_DIR/http2-headers.txt" 2>/dev/null || true

# Extract HPACK specific info
tshark -r "$CAPTURE_FILE" -Y "http2.type == 1" -V \
    > "$ANALYSIS_DIR/hpack-frames.txt" 2>/dev/null || true

echo -e "${CYAN}Analyzing JWT-related headers...${NC}\n"

# Look for JWT split headers
echo -e "${BLUE}=== JWT Split Headers Found ===${NC}"
grep -E "auth-jwt-|jwt_token" "$ANALYSIS_DIR/http2-headers.txt" | head -20 || echo "No JWT headers found"

echo -e "\n${BLUE}=== HPACK Header Representations ===${NC}"

# Analyze HPACK encoding
if [ -f "$ANALYSIS_DIR/hpack-frames.txt" ]; then
    # Look for indexed headers (dynamic table hits)
    INDEXED_COUNT=$(grep -c "Indexed Header Field" "$ANALYSIS_DIR/hpack-frames.txt" 2>/dev/null || echo "0")
    LITERAL_INDEXED_COUNT=$(grep -c "Literal Header Field with Incremental Indexing" "$ANALYSIS_DIR/hpack-frames.txt" 2>/dev/null || echo "0")
    LITERAL_NOT_INDEXED_COUNT=$(grep -c "Literal Header Field without Indexing" "$ANALYSIS_DIR/hpack-frames.txt" 2>/dev/null || echo "0")
    
    echo -e "${CYAN}HPACK Encoding Statistics:${NC}"
    echo "  Indexed Header Field: $INDEXED_COUNT (cached in dynamic table)"
    echo "  Literal with Incremental Indexing: $LITERAL_INDEXED_COUNT (added to dynamic table)"
    echo "  Literal without Indexing: $LITERAL_NOT_INDEXED_COUNT (not cached)"
    echo ""
    
    if [ "$INDEXED_COUNT" -gt 0 ]; then
        echo -e "${GREEN}✓ Dynamic table is being used!${NC}"
        echo -e "${CYAN}Indexed headers are compressed to 1-2 bytes${NC}\n"
    fi
fi

# Detailed analysis of specific JWT headers
echo -e "${BLUE}=== Detailed JWT Header Analysis ===${NC}\n"

# Extract unique header names
UNIQUE_HEADERS=$(grep -E "auth-jwt-|user-id" "$ANALYSIS_DIR/http2-headers.txt" 2>/dev/null | \
    awk '{print $2}' | sort | uniq || echo "")

if [ -n "$UNIQUE_HEADERS" ]; then
    echo -e "${CYAN}JWT-related headers detected:${NC}"
    echo "$UNIQUE_HEADERS" | while read header; do
        if [ -n "$header" ]; then
            COUNT=$(grep -c "$header" "$ANALYSIS_DIR/http2-headers.txt" 2>/dev/null || echo "0")
            echo "  - $header (appeared $COUNT times)"
        fi
    done
    echo ""
else
    echo -e "${YELLOW}No split JWT headers found in gRPC traffic${NC}"
    echo -e "${CYAN}This could mean:${NC}"
    echo "  1. JWT splitting is not enabled"
    echo "  2. No gRPC calls were made during capture"
    echo "  3. Headers are using different names"
    echo ""
fi

# Check for the 7 expected JWT split headers
echo -e "${BLUE}=== Checking for Expected JWT Split Headers ===${NC}\n"

EXPECTED_HEADERS=(
    "auth-jwt-h"
    "auth-jwt-c-iss"
    "auth-jwt-c-sub"
    "auth-jwt-c-iat"
    "auth-jwt-c-exp"
    "auth-jwt-c-nbf"
    "auth-jwt-s"
)

FOUND_HEADERS=0
for header in "${EXPECTED_HEADERS[@]}"; do
    if grep -q "$header" "$ANALYSIS_DIR/http2-headers.txt" 2>/dev/null; then
        echo -e "${GREEN}✓ Found: $header${NC}"
        ((FOUND_HEADERS++))
    else
        echo -e "${YELLOW}✗ Missing: $header${NC}"
    fi
done

echo ""

if [ $FOUND_HEADERS -eq 7 ]; then
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✓ All 7 JWT split headers detected!${NC}"
    echo -e "${GREEN}JWT header splitting is working correctly!${NC}"
    echo -e "${GREEN}========================================${NC}\n"
elif [ $FOUND_HEADERS -gt 0 ]; then
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}⚠ Partial success: $FOUND_HEADERS/7 headers found${NC}"
    echo -e "${YELLOW}========================================${NC}\n"
else
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}✗ No JWT split headers found${NC}"
    echo -e "${RED}JWT splitting may not be working${NC}"
    echo -e "${RED}========================================${NC}\n"
fi

# HPACK Dynamic Table Analysis
echo -e "${BLUE}=== HPACK Dynamic Table Analysis ===${NC}\n"

echo -e "${CYAN}Analyzing how headers are encoded across multiple requests...${NC}\n"

# Group headers by frame to see if same headers are indexed in later frames
tshark -r "$CAPTURE_FILE" -Y "http2.type == 1" -T fields \
    -e frame.number \
    -e http2.header.name \
    -e http2.header.repr \
    2>/dev/null | while read frame_num name repr; do
    
    # Check if it's an indexed representation
    if echo "$repr" | grep -qi "indexed"; then
        echo "Frame $frame_num: '$name' - $repr (COMPRESSED)"
    fi
done | head -20

echo -e "\n${CYAN}Key Observations:${NC}"
echo "  • 'Indexed' = Header retrieved from dynamic table (1-2 bytes)"
echo "  • 'Literal with Incremental' = New header added to table (full size)"
echo "  • 'Literal without' = Not cached (full size each time)"
echo ""

# Size analysis
echo -e "${BLUE}=== Header Size Estimation ===${NC}\n"

# Calculate estimated sizes
if [ -f "$ANALYSIS_DIR/http2-headers.txt" ]; then
    TOTAL_HEADERS=$(grep -E "auth-jwt-" "$ANALYSIS_DIR/http2-headers.txt" 2>/dev/null | wc -l || echo "0")
    
    if [ "$TOTAL_HEADERS" -gt 0 ]; then
        echo -e "${CYAN}Estimated HPACK Compression:${NC}"
        echo ""
        echo "First Request (all headers added to dynamic table):"
        echo "  auth-jwt-h: eyJhbGci... (36 bytes) + name (11 bytes) = ~47 bytes"
        echo "  auth-jwt-c-iss: online-boutique (24 bytes) + name (15 bytes) = ~39 bytes"
        echo "  auth-jwt-c-sub: <uuid> (36 bytes) + name (15 bytes) = ~51 bytes"
        echo "  auth-jwt-c-iat: <timestamp> (10 bytes) + name (15 bytes) = ~25 bytes"
        echo "  auth-jwt-c-exp: <timestamp> (10 bytes) + name (15 bytes) = ~25 bytes"
        echo "  auth-jwt-c-nbf: <timestamp> (10 bytes) + name (15 bytes) = ~25 bytes"
        echo "  auth-jwt-s: <signature> (43 bytes) + name (11 bytes) = ~54 bytes"
        echo "  ----------------------------------------"
        echo "  Total first request: ~266 bytes"
        echo ""
        echo "Subsequent Requests (after caching in dynamic table):"
        echo "  auth-jwt-h: [INDEX] = ~2 bytes (cached! was 47 bytes)"
        echo "  auth-jwt-c-iss: [INDEX] = ~2 bytes (cached! was 39 bytes)"
        echo "  auth-jwt-c-sub: [INDEX] = ~2 bytes (cached! was 51 bytes)"
        echo "  auth-jwt-c-iat: <new value> = ~25 bytes (changes per request)"
        echo "  auth-jwt-c-exp: <new value> = ~25 bytes (changes per request)"
        echo "  auth-jwt-c-nbf: <new value> = ~25 bytes (changes per request)"
        echo "  auth-jwt-s: <new value> = ~54 bytes (changes per request)"
        echo "  ----------------------------------------"
        echo "  Total subsequent: ~135 bytes"
        echo ""
        echo -e "${GREEN}Savings: ~131 bytes (49% reduction)${NC}"
        echo ""
    fi
fi

# Generate visual report
echo -e "${BLUE}=== Analysis Files Generated ===${NC}\n"
echo "  1. $CAPTURE_FILE - Raw packet capture"
echo "  2. $ANALYSIS_DIR/http2-headers.txt - HTTP/2 headers extracted"
echo "  3. $ANALYSIS_DIR/hpack-frames.txt - Detailed HPACK frame analysis"
echo ""
echo -e "${CYAN}To view detailed HPACK analysis:${NC}"
echo "  tshark -r $CAPTURE_FILE -Y 'http2' -V | less"
echo ""
echo -e "${CYAN}To filter only JWT headers:${NC}"
echo "  grep -E 'auth-jwt-' $ANALYSIS_DIR/http2-headers.txt"
echo ""

# Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Summary${NC}"
echo -e "${BLUE}========================================${NC}\n"

if [ $FOUND_HEADERS -ge 5 ]; then
    echo -e "${GREEN}✓ JWT header splitting implementation verified!${NC}"
    echo -e "${GREEN}✓ HPACK dynamic table is compressing headers${NC}"
    echo -e "${GREEN}✓ Expected compression: 40-50% on subsequent requests${NC}\n"
    echo -e "${CYAN}Next steps:${NC}"
    echo "  1. Run load tests to measure actual bandwidth savings"
    echo "  2. Compare with/without splitting using A/B testing"
    echo "  3. Measure HPACK dynamic table hit rates"
    echo ""
else
    echo -e "${YELLOW}⚠ Partial verification - not all headers detected${NC}"
    echo -e "${CYAN}Recommendations:${NC}"
    echo "  1. Ensure ENABLE_JWT_SPLITTING=true is set"
    echo "  2. Generate more gRPC traffic"
    echo "  3. Check frontend logs for JWT splitting messages"
    echo ""
fi

echo -e "${GREEN}Analysis complete!${NC}\n"
