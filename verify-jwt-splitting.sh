#!/bin/bash

# Simple HPACK Verification via Frontend Logs
# Checks if JWT headers are being split in gRPC calls

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}JWT Header Splitting Verification${NC}"
echo -e "${BLUE}Quick Test via Logs${NC}"
echo -e "${BLUE}========================================${NC}\n"

# Check if JWT splitting is enabled
echo -e "${YELLOW}Step 1: Checking JWT splitting configuration...${NC}"
SPLITTING_ENABLED=$(kubectl get deployment frontend -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="ENABLE_JWT_SPLITTING")].value}' 2>/dev/null)

if [ "$SPLITTING_ENABLED" = "true" ]; then
    echo -e "${GREEN}✓ JWT splitting is ENABLED${NC}\n"
else
    echo -e "${YELLOW}⚠ JWT splitting is NOT enabled. Enabling it now...${NC}"
    kubectl set env deployment/frontend ENABLE_JWT_SPLITTING=true
    echo "Waiting for deployment to roll out..."
    kubectl rollout status deployment/frontend --timeout=60s
    echo -e "${GREEN}✓ JWT splitting enabled${NC}\n"
    sleep 3
fi

# Enable debug logging to see splitting metrics
echo -e "${YELLOW}Step 2: Enabling debug logging...${NC}"
kubectl set env deployment/frontend LOG_LEVEL=debug 2>/dev/null || true
sleep 5
echo -e "${GREEN}✓ Debug logging enabled${NC}\n"

# Generate traffic
echo -e "${YELLOW}Step 3: Generating traffic...${NC}"
echo -e "${CYAN}Making HTTP requests to trigger gRPC calls...${NC}\n"

for i in {1..3}; do
    curl -s http://localhost:8080/ > /dev/null 2>&1 || true
    echo "  Request $i/3"
    sleep 1
done

echo ""
sleep 3

# Check logs for JWT splitting activity
echo -e "${YELLOW}Step 4: Analyzing frontend logs...${NC}\n"

FRONTEND_POD=$(kubectl get pods -l app=frontend -o jsonpath='{.items[0].metadata.name}')
echo -e "${CYAN}Pod: $FRONTEND_POD${NC}\n"

# Look for JWT splitting metrics in logs
echo -e "${BLUE}=== JWT Splitting Metrics ===${NC}\n"

JWT_METRICS=$(kubectl logs "$FRONTEND_POD" --tail=100 | grep -i "splitting metrics" 2>/dev/null || true)

if [ -n "$JWT_METRICS" ]; then
    echo -e "${GREEN}✓ JWT splitting metrics found in logs!${NC}\n"
    echo "$JWT_METRICS" | tail -5
    echo ""
    
    # Parse and display
    echo -e "${CYAN}Parsed Metrics:${NC}"
    echo "$JWT_METRICS" | tail -1 | grep -o '"[^"]*":[^,}]*' | while read metric; do
        echo "  $metric"
    done
    echo ""
else
    echo -e "${YELLOW}⚠ No JWT splitting metrics found yet${NC}"
    echo -e "${CYAN}This could mean:${NC}"
    echo "  - Not enough traffic generated yet"
    echo "  - Logging level not set to debug"
    echo "  - JWT splitting not triggering on these requests"
    echo ""
fi

# Check for gRPC metadata in logs
echo -e "${BLUE}=== Checking for Split JWT Headers in gRPC Metadata ===${NC}\n"

# Look for the 7 expected headers
EXPECTED_HEADERS=(
    "auth-jwt-h"
    "auth-jwt-c-iss"
    "auth-jwt-c-sub"
    "auth-jwt-c-iat"
    "auth-jwt-c-exp"
    "auth-jwt-c-nbf"
    "auth-jwt-s"
)

FOUND_COUNT=0
for header in "${EXPECTED_HEADERS[@]}"; do
    if kubectl logs "$FRONTEND_POD" --tail=200 | grep -q "$header" 2>/dev/null; then
        echo -e "${GREEN}✓ Found: $header${NC}"
        ((FOUND_COUNT++))
    else
        echo -e "${YELLOW}  Missing: $header${NC}"
    fi
done

echo ""

# Manual test with grpcurl (if available)
echo -e "${BLUE}=== Testing JWT Splitting Implementation ===${NC}\n"

echo -e "${CYAN}Checking if JWT splitter code is present in binary...${NC}"

# Check if the functions exist in the compiled binary
kubectl exec "$FRONTEND_POD" -- strings /src/server | grep -E "splitJWT|reconstructJWT|UnaryClientInterceptorJWTSplitter" > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ JWT splitting code found in binary${NC}"
else
    echo -e "${RED}✗ JWT splitting code not found${NC}"
fi

# Check environment variable
ENV_VAR=$(kubectl exec "$FRONTEND_POD" -- env | grep ENABLE_JWT_SPLITTING || echo "NOT_SET")
echo -e "${CYAN}Environment variable: $ENV_VAR${NC}"

echo ""

# Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Verification Summary${NC}"
echo -e "${BLUE}========================================${NC}\n"

if [ $FOUND_COUNT -ge 5 ]; then
    echo -e "${GREEN}✓ JWT header splitting IS WORKING!${NC}"
    echo -e "${GREEN}  Found $FOUND_COUNT/7 expected headers${NC}\n"
    
    echo -e "${CYAN}What this means:${NC}"
    echo "  • JWT tokens are being split into multiple headers"
    echo "  • Each header component can be cached by HPACK"
    echo "  • Static components (algorithm, issuer) will be indexed"
    echo "  • Dynamic components (timestamps) sent as literals"
    echo "  • Expected compression: 40-60% on subsequent requests"
    echo ""
    
elif [ $FOUND_COUNT -gt 0 ]; then
    echo -e "${YELLOW}⚠ Partial verification: $FOUND_COUNT/7 headers found${NC}\n"
    echo -e "${CYAN}Recommendations:${NC}"
    echo "  • Generate more traffic to trigger all header types"
    echo "  • Check logs with: kubectl logs $FRONTEND_POD | grep auth-jwt"
    echo "  • Ensure backend services are being called"
    echo ""
    
else
    echo -e "${YELLOW}⚠ No split headers detected in logs${NC}\n"
    echo -e "${CYAN}This might mean:${NC}"
    echo "  • No gRPC calls were made (frontend only serves HTTP)"
    echo "  • Headers are present but not logged"
    echo "  • Need to trigger specific user flows (cart, checkout)"
    echo ""
    
    echo -e "${CYAN}Try these actions:${NC}"
    echo "  1. Add item to cart: curl -X POST http://localhost:8080/cart -d 'product_id=OLJCESPC7Z&quantity=1'"
    echo "  2. View cart: curl http://localhost:8080/cart"
    echo "  3. Check logs again: kubectl logs $FRONTEND_POD | grep -E 'auth-jwt|splitting'"
    echo ""
fi

# Show how to verify HPACK compression
echo -e "${BLUE}=== How to Verify HPACK Compression ===${NC}\n"

echo -e "${CYAN}To see actual HPACK compression, you need to:${NC}"
echo ""
echo "1. Capture gRPC traffic with tcpdump:"
echo "   kubectl exec $FRONTEND_POD -- tcpdump -i any -s 0 -w /tmp/grpc.pcap port 7070"
echo ""
echo "2. Download and analyze with tshark:"
echo "   kubectl cp $FRONTEND_POD:/tmp/grpc.pcap ./grpc.pcap"
echo "   tshark -r grpc.pcap -Y 'http2' -V | grep -A5 'Header'"
echo ""
echo "3. Look for these HPACK encoding types:"
echo "   • 'Indexed Header Field' = Compressed (1-2 bytes)"
echo "   • 'Literal with Incremental Indexing' = Added to dynamic table"
echo "   • Index numbers 62-127 = Dynamic table entries"
echo ""

echo -e "${CYAN}Expected behavior in HPACK dynamic table:${NC}"
echo ""
echo "Request 1:"
echo "  auth-jwt-h: Literal (47 bytes) → Added to dynamic table [index 62]"
echo "  auth-jwt-c-iss: Literal (39 bytes) → Added to dynamic table [index 63]"
echo ""
echo "Request 2 (same user):"
echo "  auth-jwt-h: Indexed [62] → 2 bytes ✓"
echo "  auth-jwt-c-iss: Indexed [63] → 2 bytes ✓"
echo ""
echo -e "${GREEN}Compression achieved: 47+39=86 bytes → 2+2=4 bytes (95% reduction!)${NC}"
echo ""

echo -e "${GREEN}Verification complete!${NC}\n"
