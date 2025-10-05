#!/bin/bash

# JWT Header Testing Script
# Tests if JWT tokens and session cookies are working as intended

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BASE_URL="${BASE_URL:-http://localhost:8080}"
COOKIE_FILE="/tmp/boutique-cookies.txt"
OUTPUT_DIR="/tmp/jwt-test-output"

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}JWT & Session Cookie Testing Script${NC}"
echo -e "${BLUE}======================================${NC}\n"

echo -e "${YELLOW}Testing URL: $BASE_URL${NC}\n"

# Clean up from previous runs
rm -f "$COOKIE_FILE"

# ======================
# Test 1: First Request
# ======================
echo -e "${BLUE}[Test 1] First Request - Should create session and JWT${NC}"

curl -i -c "$COOKIE_FILE" \
  -H "Accept: text/html" \
  "$BASE_URL/" \
  -o "$OUTPUT_DIR/response1.txt" \
  -s -D "$OUTPUT_DIR/headers1.txt"

# Check for cookies in response
echo -e "${YELLOW}Response Headers:${NC}"
cat "$OUTPUT_DIR/headers1.txt" | grep -i "set-cookie" || echo "No Set-Cookie headers found"

# Extract session ID
SESSION_ID=$(cat "$COOKIE_FILE" | grep "shop_session-id" | awk '{print $7}')
JWT_TOKEN=$(cat "$COOKIE_FILE" | grep "jwt_token" | awk '{print $7}')

echo ""
if [ -n "$SESSION_ID" ]; then
    echo -e "${GREEN}✓ Session cookie created: ${SESSION_ID:0:20}...${NC}"
else
    echo -e "${RED}✗ No session cookie found!${NC}"
fi

if [ -n "$JWT_TOKEN" ]; then
    echo -e "${GREEN}✓ JWT cookie created: ${JWT_TOKEN:0:40}...${NC}"
else
    echo -e "${RED}✗ No JWT cookie found!${NC}"
fi

# Check for X-JWT-Token header
X_JWT_HEADER=$(cat "$OUTPUT_DIR/headers1.txt" | grep -i "X-JWT-Token:" | awk '{print $2}')
if [ -n "$X_JWT_HEADER" ]; then
    echo -e "${GREEN}✓ X-JWT-Token header present in response${NC}"
else
    echo -e "${YELLOW}⚠ X-JWT-Token header not found in response${NC}"
fi

echo ""
sleep 1

# ======================
# Test 2: Second Request
# ======================
echo -e "${BLUE}[Test 2] Second Request - Should REUSE session and JWT${NC}"

curl -i -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
  -H "Accept: text/html" \
  "$BASE_URL/" \
  -o "$OUTPUT_DIR/response2.txt" \
  -s -D "$OUTPUT_DIR/headers2.txt"

# Extract session ID and JWT from second request
SESSION_ID_2=$(cat "$COOKIE_FILE" | grep "shop_session-id" | awk '{print $7}')
JWT_TOKEN_2=$(cat "$COOKIE_FILE" | grep "jwt_token" | awk '{print $7}')

echo -e "${YELLOW}Comparing cookies:${NC}"
if [ "$SESSION_ID" = "$SESSION_ID_2" ]; then
    echo -e "${GREEN}✓ Session ID SAME (as expected): ${SESSION_ID:0:20}...${NC}"
else
    echo -e "${RED}✗ Session ID CHANGED (unexpected!)${NC}"
    echo -e "  Old: ${SESSION_ID:0:40}"
    echo -e "  New: ${SESSION_ID_2:0:40}"
fi

if [ "$JWT_TOKEN" = "$JWT_TOKEN_2" ]; then
    echo -e "${GREEN}✓ JWT Token SAME (as expected): ${JWT_TOKEN:0:40}...${NC}"
else
    echo -e "${RED}✗ JWT Token CHANGED (unexpected!)${NC}"
    echo -e "  Old: ${JWT_TOKEN:0:60}"
    echo -e "  New: ${JWT_TOKEN_2:0:60}"
fi

echo ""
sleep 1

# ======================
# Test 3: Third Request
# ======================
echo -e "${BLUE}[Test 3] Third Request - Should STILL reuse same JWT${NC}"

curl -i -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
  -H "Accept: text/html" \
  "$BASE_URL/" \
  -o "$OUTPUT_DIR/response3.txt" \
  -s -D "$OUTPUT_DIR/headers3.txt"

SESSION_ID_3=$(cat "$COOKIE_FILE" | grep "shop_session-id" | awk '{print $7}')
JWT_TOKEN_3=$(cat "$COOKIE_FILE" | grep "jwt_token" | awk '{print $7}')

if [ "$SESSION_ID" = "$SESSION_ID_3" ] && [ "$JWT_TOKEN" = "$JWT_TOKEN_3" ]; then
    echo -e "${GREEN}✓ Session and JWT still the SAME after 3 requests${NC}"
else
    echo -e "${RED}✗ Session or JWT changed on third request${NC}"
fi

echo ""
sleep 1

# ======================
# Test 4: Add to Cart
# ======================
echo -e "${BLUE}[Test 4] Add to Cart - Testing session persistence${NC}"

curl -i -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
  -X POST \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "product_id=OLJCESPC7Z&quantity=1" \
  "$BASE_URL/cart" \
  -o "$OUTPUT_DIR/cart-add.txt" \
  -s -D "$OUTPUT_DIR/cart-add-headers.txt"

SESSION_ID_4=$(cat "$COOKIE_FILE" | grep "shop_session-id" | awk '{print $7}')
JWT_TOKEN_4=$(cat "$COOKIE_FILE" | grep "jwt_token" | awk '{print $7}')

if [ "$SESSION_ID" = "$SESSION_ID_4" ] && [ "$JWT_TOKEN" = "$JWT_TOKEN_4" ]; then
    echo -e "${GREEN}✓ Session and JWT SAME after adding to cart${NC}"
else
    echo -e "${RED}✗ Session or JWT changed when adding to cart${NC}"
fi

echo ""
sleep 1

# ======================
# Test 5: View Cart
# ======================
echo -e "${BLUE}[Test 5] View Cart - Verify items persisted${NC}"

curl -s -b "$COOKIE_FILE" "$BASE_URL/cart" -o "$OUTPUT_DIR/cart-view.html"

if grep -q "Your Cart" "$OUTPUT_DIR/cart-view.html"; then
    if grep -q "empty" "$OUTPUT_DIR/cart-view.html"; then
        echo -e "${RED}✗ Cart is empty (items not persisted)${NC}"
    else
        echo -e "${GREEN}✓ Cart has items (session working correctly)${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Could not determine cart status${NC}"
fi

echo ""

# ======================
# Test 6: Decode JWT
# ======================
echo -e "${BLUE}[Test 6] JWT Token Analysis${NC}"

if [ -n "$JWT_TOKEN" ]; then
    # Split JWT into parts
    HEADER=$(echo "$JWT_TOKEN" | cut -d'.' -f1)
    PAYLOAD=$(echo "$JWT_TOKEN" | cut -d'.' -f2)
    SIGNATURE=$(echo "$JWT_TOKEN" | cut -d'.' -f3)
    
    echo -e "${YELLOW}JWT Structure:${NC}"
    echo "  Header:    ${HEADER:0:30}..."
    echo "  Payload:   ${PAYLOAD:0:30}..."
    echo "  Signature: ${SIGNATURE:0:30}..."
    echo ""
    
    # Decode payload (add padding if needed)
    PAYLOAD_PADDED="$PAYLOAD"
    case $((${#PAYLOAD} % 4)) in
        2) PAYLOAD_PADDED="${PAYLOAD}==" ;;
        3) PAYLOAD_PADDED="${PAYLOAD}=" ;;
    esac
    
    echo -e "${YELLOW}Decoded JWT Payload:${NC}"
    echo "$PAYLOAD_PADDED" | base64 -d 2>/dev/null | jq . 2>/dev/null || \
        echo "$PAYLOAD_PADDED" | base64 -d 2>/dev/null
    echo ""
else
    echo -e "${RED}No JWT token to decode${NC}"
fi

# ======================
# Test 7: Cookie Inspection
# ======================
echo -e "${BLUE}[Test 7] Cookie Details${NC}"

echo -e "${YELLOW}Current Cookies:${NC}"
cat "$COOKIE_FILE" | grep -v "^#" | while read -r line; do
    COOKIE_NAME=$(echo "$line" | awk '{print $6}')
    COOKIE_VALUE=$(echo "$line" | awk '{print $7}')
    echo "  $COOKIE_NAME = ${COOKIE_VALUE:0:50}..."
done

echo ""

# ======================
# Test 8: Request Headers
# ======================
echo -e "${BLUE}[Test 8] Request Headers Sent by Client${NC}"

echo -e "${YELLOW}Making request with verbose cookie output:${NC}"
curl -v -b "$COOKIE_FILE" "$BASE_URL/" 2>&1 | grep -i "cookie:" | head -5

echo ""

# ======================
# Summary
# ======================
echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}======================================${NC}\n"

TESTS_PASSED=0
TESTS_FAILED=0

# Check if session persists
if [ "$SESSION_ID" = "$SESSION_ID_2" ] && [ "$SESSION_ID" = "$SESSION_ID_3" ] && [ "$SESSION_ID" = "$SESSION_ID_4" ]; then
    echo -e "${GREEN}✓ Session cookie persistence: PASS${NC}"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗ Session cookie persistence: FAIL${NC}"
    ((TESTS_FAILED++))
fi

# Check if JWT persists
if [ "$JWT_TOKEN" = "$JWT_TOKEN_2" ] && [ "$JWT_TOKEN" = "$JWT_TOKEN_3" ] && [ "$JWT_TOKEN" = "$JWT_TOKEN_4" ]; then
    echo -e "${GREEN}✓ JWT token persistence: PASS${NC}"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗ JWT token persistence: FAIL${NC}"
    ((TESTS_FAILED++))
fi

# Check if cookies were created
if [ -n "$SESSION_ID" ] && [ -n "$JWT_TOKEN" ]; then
    echo -e "${GREEN}✓ Cookie creation: PASS${NC}"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗ Cookie creation: FAIL${NC}"
    ((TESTS_FAILED++))
fi

echo ""
echo -e "${BLUE}Total: $TESTS_PASSED passed, $TESTS_FAILED failed${NC}"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "\n${GREEN}🎉 All tests PASSED! JWT implementation working correctly.${NC}\n"
    exit 0
else
    echo -e "\n${RED}❌ Some tests FAILED. Please review the output above.${NC}\n"
    exit 1
fi
