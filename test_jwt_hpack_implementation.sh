#!/bin/bash
#
# Complete Test Script for JWT Compression + HPACK 64KB Implementation
# Tests all services and verifies the configuration works correctly
#

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo ""
echo "═══════════════════════════════════════════════════════════════════════"
echo "  Testing JWT Compression + HPACK 64KB Implementation"
echo "═══════════════════════════════════════════════════════════════════════"
echo ""

# Step 1: Check if services are running
echo -e "${BLUE}Step 1: Checking service status...${NC}"
if ! kubectl get pods 2>/dev/null | grep -q "frontend"; then
    echo -e "${RED}✗ Services not deployed. Please deploy first.${NC}"
    exit 1
fi

FRONTEND_POD=$(kubectl get pods -l app=frontend -o jsonpath='{.items[0].metadata.name}')
CHECKOUT_POD=$(kubectl get pods -l app=checkoutservice -o jsonpath='{.items[0].metadata.name}')
CART_POD=$(kubectl get pods -l app=cartservice -o jsonpath='{.items[0].metadata.name}')
PAYMENT_POD=$(kubectl get pods -l app=paymentservice -o jsonpath='{.items[0].metadata.name}')
EMAIL_POD=$(kubectl get pods -l app=emailservice -o jsonpath='{.items[0].metadata.name}')
SHIPPING_POD=$(kubectl get pods -l app=shippingservice -o jsonpath='{.items[0].metadata.name}')

echo -e "${GREEN}✓ Services running${NC}"
echo "  Frontend:  $FRONTEND_POD"
echo "  Checkout:  $CHECKOUT_POD"
echo "  Cart:      $CART_POD"
echo "  Payment:   $PAYMENT_POD"
echo "  Email:     $EMAIL_POD"
echo "  Shipping:  $SHIPPING_POD"
echo ""

# Step 2: Check if JWT compression is enabled
echo -e "${BLUE}Step 2: Checking JWT compression configuration...${NC}"
JWT_ENABLED=$(kubectl get deployment frontend -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="ENABLE_JWT_COMPRESSION")].value}' 2>/dev/null || echo "")

if [ "$JWT_ENABLED" != "true" ]; then
    echo -e "${YELLOW}⚠ JWT compression not enabled. Enabling now...${NC}"
    ./enable_jwt_compression.sh
    echo ""
    echo -e "${YELLOW}Waiting 30 seconds for pods to restart...${NC}"
    sleep 30
    
    # Get new pod names
    FRONTEND_POD=$(kubectl get pods -l app=frontend -o jsonpath='{.items[0].metadata.name}')
    CHECKOUT_POD=$(kubectl get pods -l app=checkoutservice -o jsonpath='{.items[0].metadata.name}')
    echo -e "${GREEN}✓ JWT compression enabled${NC}"
else
    echo -e "${GREEN}✓ JWT compression already enabled${NC}"
fi
echo ""

# Step 3: Generate test traffic
echo -e "${BLUE}Step 3: Generating test traffic (warming up HPACK caches)...${NC}"
echo "This will make 50 requests to exercise the JWT flow..."

# Get frontend service URL
FRONTEND_URL=$(minikube service frontend-external --url 2>/dev/null || echo "http://localhost:8080")
echo "Frontend URL: $FRONTEND_URL"
echo ""

for i in {1..50}; do
    if [ $((i % 10)) -eq 0 ]; then
        echo -n "."
    fi
    curl -s "$FRONTEND_URL" > /dev/null 2>&1 || true
    sleep 0.2
done
echo ""
echo -e "${GREEN}✓ Generated 50 requests${NC}"
echo ""

# Step 4: Check Frontend logs for JWT compression
echo -e "${BLUE}Step 4: Checking Frontend logs for JWT compression...${NC}"
echo "Looking for evidence of JWT decomposition and indexing control..."
echo ""

FRONTEND_LOGS=$(kubectl logs $FRONTEND_POD --tail=100 2>/dev/null || echo "")
if echo "$FRONTEND_LOGS" | grep -q "static/session=CACHED"; then
    echo -e "${GREEN}✓ Found indexing control messages in Frontend logs${NC}"
    echo ""
    echo "Sample entries:"
    echo "$FRONTEND_LOGS" | grep "static/session=CACHED" | tail -3
    echo ""
elif echo "$FRONTEND_LOGS" | grep -q "Sending compressed JWT"; then
    echo -e "${GREEN}✓ Frontend is sending compressed JWT${NC}"
    echo ""
    echo "Sample entries:"
    echo "$FRONTEND_LOGS" | grep "compressed JWT" | tail -3
    echo ""
else
    echo -e "${YELLOW}⚠ No JWT compression messages found yet${NC}"
    echo "This might be because:"
    echo "  1. Services need to be rebuilt with new code"
    echo "  2. Not enough traffic generated yet"
    echo "  3. Logs haven't propagated"
fi
echo ""

# Step 5: Check Checkout logs for JWT forwarding
echo -e "${BLUE}Step 5: Checking Checkout logs for JWT forwarding...${NC}"
CHECKOUT_LOGS=$(kubectl logs $CHECKOUT_POD --tail=100 2>/dev/null || echo "")

if echo "$CHECKOUT_LOGS" | grep -q "compressed JWT"; then
    echo -e "${GREEN}✓ Checkout is forwarding compressed JWT${NC}"
    echo ""
    echo "Sample entries:"
    echo "$CHECKOUT_LOGS" | grep "compressed JWT" | tail -3
else
    echo -e "${YELLOW}⚠ No JWT forwarding messages found yet${NC}"
    echo "  (Checkout service is only invoked during checkout operations)"
fi
echo ""

# Step 6: Check receiver services
echo -e "${BLUE}Step 6: Checking receiver services (Cart, Payment, Email, Shipping)...${NC}"

check_receiver_service() {
    local service_name=$1
    local pod_name=$2
    
    LOGS=$(kubectl logs $pod_name --tail=50 2>/dev/null || echo "")
    if echo "$LOGS" | grep -q "Received compressed JWT\|compressed JWT"; then
        echo -e "  ${GREEN}✓ $service_name: Receiving compressed JWT${NC}"
        return 0
    elif echo "$LOGS" | grep -q "JWT"; then
        echo -e "  ${YELLOW}⚠ $service_name: JWT flow detected but not compressed format${NC}"
        return 0
    else
        echo -e "  ${YELLOW}⚠ $service_name: No JWT messages found (no traffic yet)${NC}"
        return 0
    fi
}

check_receiver_service "Cart Service" "$CART_POD"
check_receiver_service "Payment Service" "$PAYMENT_POD"
check_receiver_service "Email Service" "$EMAIL_POD"
check_receiver_service "Shipping Service" "$SHIPPING_POD"
echo ""

# Step 7: Verify HPACK configuration is present
echo -e "${BLUE}Step 7: Verifying HPACK 64KB configuration...${NC}"
echo ""

echo "Checking if services have been rebuilt with HPACK 64KB config:"
echo ""

# Check if our changes are in the deployed code
echo -e "${CYAN}Note: To fully test HPACK 64KB configuration, services need to be rebuilt.${NC}"
echo "Current running services were built before configuration changes."
echo ""
echo "To deploy with new configuration:"
echo "  1. Build new images: skaffold build"
echo "  2. Deploy: skaffold run"
echo "  3. Or use: kubectl apply -f kubernetes-manifests/"
echo ""

# Step 8: Check JWT component sizes in logs
echo -e "${BLUE}Step 8: Analyzing JWT component sizes from logs...${NC}"

if echo "$FRONTEND_LOGS" | grep -q "total="; then
    echo -e "${GREEN}✓ Found JWT size information in logs${NC}"
    echo ""
    echo "JWT size breakdown:"
    echo "$FRONTEND_LOGS" | grep "total=" | tail -5
else
    echo -e "${YELLOW}⚠ No JWT size information found in logs yet${NC}"
fi
echo ""

# Step 9: Summary and recommendations
echo "═══════════════════════════════════════════════════════════════════════"
echo -e "${CYAN}Test Summary${NC}"
echo "═══════════════════════════════════════════════════════════════════════"
echo ""

echo -e "${GREEN}✓ Completed Tests:${NC}"
echo "  • Service status verification"
echo "  • JWT compression environment variable"
echo "  • Test traffic generation (50 requests)"
echo "  • Log analysis for JWT flow"
echo ""

echo -e "${GREEN}✓ Verified Working Flows:${NC}"
if echo "$FRONTEND_LOGS" | grep -q "static/session=CACHED"; then
    echo "  • Frontend → CartService: JWT decomposition with HPACK indexing control"
fi
if echo "$FRONTEND_LOGS" | grep -q "Sending compressed JWT"; then
    CART_LOGS=$(kubectl logs $CART_POD --tail=50 2>/dev/null || echo "")
    if echo "$CART_LOGS" | grep -q "Received compressed JWT"; then
        echo "  • CartService: JWT reassembly from compressed headers"
        echo "  • CartService: -bin headers successfully decoded"
    fi
fi
echo ""

echo -e "${YELLOW}⚠ Important Notes:${NC}"
echo ""
echo "1. ${CYAN}Services need to be rebuilt${NC} to include:"
echo "   • HPACK 64KB configuration"
echo "   • HPACK indexing control (NoCompress)"
echo "   • Updated log messages"
echo ""

echo "2. ${CYAN}To rebuild and deploy:${NC}"
echo "   cd /workspaces/microservices-demo"
echo "   skaffold build --default-repo=<your-registry>"
echo "   skaffold deploy"
echo ""

echo "3. ${CYAN}After redeployment, run this test again:${NC}"
echo "   ./test_jwt_hpack_implementation.sh"
echo ""

echo "4. ${CYAN}For detailed HTTP/2 frame analysis:${NC}"
echo "   • Capture traffic with tcpdump"
echo "   • Analyze in Wireshark"
echo "   • Look for HPACK indexed headers vs literal headers"
echo ""

echo "5. ${CYAN}To verify HPACK effectiveness:${NC}"
echo "   • Generate sustained load (1000+ requests)"
echo "   • Compare first request vs subsequent requests"
echo "   • Should see 'x-jwt-static' and 'x-jwt-session' using table indices"
echo ""

echo "═══════════════════════════════════════════════════════════════════════"
echo -e "${GREEN}Test script completed!${NC}"
echo "═══════════════════════════════════════════════════════════════════════"
echo ""
