#!/bin/bash

# JWT Flow Test Script
# Simulates: Landing → Add to Cart → Checkout → Continue Shopping
# Shows JWT compression flow across all microservices

set -e

FRONTEND_URL="http://localhost:8080"
PRODUCT_ID="OLJCESPC7Z"  # Vintage Typewriter
QUANTITY=1

echo "=========================================="
echo "JWT Flow Test: User Journey Simulation"
echo "=========================================="
echo ""
echo "Journey: Landing → Add to Cart → Checkout → Continue Shopping"
echo ""

# Color codes for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to show step header
show_step() {
    echo ""
    echo -e "${GREEN}=========================================="
    echo -e "STEP $1: $2"
    echo -e "==========================================${NC}"
    echo ""
}

# Function to show logs from a service
show_service_logs() {
    local service=$1
    local pattern=$2
    echo -e "${BLUE}📋 $service logs:${NC}"
    kubectl logs -l app=$service --tail=50 | grep -E "\[JWT-FLOW\]|\[JWT-COMPRESSION\]" | tail -10 || echo "  (no JWT flow logs yet)"
    echo ""
}

# Function to make HTTP request and show response
make_request() {
    local method=$1
    local url=$2
    local data=$3
    local desc=$4
    
    echo -e "${YELLOW}📤 $desc${NC}"
    echo "   Request: $method $url"
    
    if [ -n "$data" ]; then
        curl -s -X $method "$url" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "$data" \
            -c /tmp/cookies.txt \
            -b /tmp/cookies.txt \
            -w "\n   Response: HTTP %{http_code}\n" \
            -o /dev/null
    else
        curl -s -X $method "$url" \
            -c /tmp/cookies.txt \
            -b /tmp/cookies.txt \
            -w "\n   Response: HTTP %{http_code}\n" \
            -o /dev/null
    fi
    
    sleep 1  # Give logs time to propagate
}

# Clear previous cookies
rm -f /tmp/cookies.txt

echo "🔍 Pre-test: Clearing old logs..."
echo ""

# ============================================
# STEP 1: Landing Page (Load Products)
# ============================================
show_step "1" "Landing Page - Load Products"

make_request "GET" "$FRONTEND_URL/" "" "User visits homepage"

echo "Expected JWT Flow:"
echo "  ✓ Frontend → Product Catalog: Skipping JWT (public service)"
echo "  ✓ Frontend → Currency Service: Skipping JWT (public service)"
echo ""

show_service_logs "frontend" "JWT-FLOW.*ProductCatalog\|JWT-FLOW.*Currency"

# ============================================
# STEP 2: Add Item to Cart
# ============================================
show_step "2" "Add Item to Cart"

make_request "POST" "$FRONTEND_URL/cart" "product_id=$PRODUCT_ID&quantity=$QUANTITY" "User adds $PRODUCT_ID (qty: $QUANTITY) to cart"

echo "Expected JWT Flow:"
echo "  ✓ Frontend → Cart Service: Sending compressed JWT"
echo "  ✓ Cart Service ← Frontend: Received compressed JWT"
echo ""

show_service_logs "frontend" "JWT-FLOW.*CartService"
show_service_logs "cartservice" "JWT-FLOW"

# ============================================
# STEP 3: View Cart
# ============================================
show_step "3" "View Cart"

make_request "GET" "$FRONTEND_URL/cart" "" "User views cart"

echo "Expected JWT Flow:"
echo "  ✓ Frontend → Cart Service: Sending compressed JWT"
echo "  ✓ Cart Service ← Frontend: Received compressed JWT"
echo ""

show_service_logs "cartservice" "JWT-FLOW"

# ============================================
# STEP 4: Place Order (Checkout)
# ============================================
show_step "4" "Place Order - Checkout Flow"

# Prepare checkout data
CHECKOUT_DATA="email=test@example.com"
CHECKOUT_DATA="${CHECKOUT_DATA}&street_address=123+Main+St"
CHECKOUT_DATA="${CHECKOUT_DATA}&zip_code=12345"
CHECKOUT_DATA="${CHECKOUT_DATA}&city=Springfield"
CHECKOUT_DATA="${CHECKOUT_DATA}&state=IL"
CHECKOUT_DATA="${CHECKOUT_DATA}&country=USA"
CHECKOUT_DATA="${CHECKOUT_DATA}&credit_card_number=4111111111111111"
CHECKOUT_DATA="${CHECKOUT_DATA}&credit_card_expiration_month=12"
CHECKOUT_DATA="${CHECKOUT_DATA}&credit_card_expiration_year=2025"
CHECKOUT_DATA="${CHECKOUT_DATA}&credit_card_cvv=123"

make_request "POST" "$FRONTEND_URL/cart/checkout" "$CHECKOUT_DATA" "User places order"

echo "Expected JWT Flow (Multi-service orchestration):"
echo "  ✓ Frontend → Checkout Service: Sending compressed JWT"
echo "  ✓ Checkout Service ← Frontend: Received compressed JWT"
echo "  ✓ Checkout Service → Payment Service: Forwarding compressed JWT"
echo "  ✓ Payment Service ← Checkout: Received compressed JWT"
echo "  ✓ Checkout Service → Shipping Service: Forwarding compressed JWT"
echo "  ✓ Shipping Service ← Checkout: Received compressed JWT"
echo "  ✓ Checkout Service → Email Service: Forwarding compressed JWT"
echo "  ✓ Email Service ← Checkout: Received compressed JWT"
echo ""

echo "Waiting 2 seconds for all services to process..."
sleep 2

show_service_logs "frontend" "JWT-FLOW.*Checkout"
show_service_logs "checkoutservice" "JWT-FLOW"
show_service_logs "paymentservice" "JWT-FLOW"
show_service_logs "shippingservice" "JWT-FLOW"
show_service_logs "emailservice" "JWT-FLOW"

# ============================================
# STEP 5: Continue Shopping (Return to Home)
# ============================================
show_step "5" "Continue Shopping - Return to Homepage"

make_request "GET" "$FRONTEND_URL/" "" "User returns to homepage"

echo "Expected JWT Flow:"
echo "  ✓ Frontend → Product Catalog: Skipping JWT (public service)"
echo "  ✓ Frontend → Currency Service: Skipping JWT (public service)"
echo ""

show_service_logs "frontend" "JWT-FLOW.*ProductCatalog\|JWT-FLOW.*Currency"

# ============================================
# SUMMARY
# ============================================
echo ""
echo -e "${GREEN}=========================================="
echo "COMPLETE JWT FLOW TRACE"
echo -e "==========================================${NC}"
echo ""

echo -e "${BLUE}📊 All JWT Flow Logs (Last 30 entries):${NC}"
echo ""

echo "--- Frontend ---"
kubectl logs -l app=frontend --tail=100 | grep "\[JWT-FLOW\]" | tail -15 || echo "(no logs)"

echo ""
echo "--- Checkout Service ---"
kubectl logs -l app=checkoutservice --tail=100 | grep "\[JWT-FLOW\]" | tail -10 || echo "(no logs)"

echo ""
echo "--- Cart Service ---"
kubectl logs -l app=cartservice --tail=100 | grep "\[JWT-FLOW\]" | tail -10 || echo "(no logs)"

echo ""
echo "--- Payment Service ---"
kubectl logs -l app=paymentservice --tail=100 | grep "\[JWT-FLOW\]" | tail -10 || echo "(no logs)"

echo ""
echo "--- Shipping Service ---"
kubectl logs -l app=shippingservice --tail=100 | grep "\[JWT-FLOW\]" | tail -10 || echo "(no logs)"

echo ""
echo "--- Email Service ---"
kubectl logs -l app=emailservice --tail=100 | grep "\[JWT-FLOW\]" | tail -10 || echo "(no logs)"

echo ""
echo -e "${GREEN}=========================================="
echo "Test Complete! ✅"
echo -e "==========================================${NC}"
echo ""
