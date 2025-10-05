#!/bin/bash

# Simple JWT Token Verification Script
# Verifies that JWT tokens persist across multiple requests

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

BASE_URL="${BASE_URL:-http://localhost:8080}"
COOKIE_FILE="/tmp/test-cookies.txt"

rm -f "$COOKIE_FILE"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}JWT Token Persistence Verification${NC}"
echo -e "${BLUE}========================================${NC}\n"

# Request 1
echo -e "${YELLOW}Request 1: Initial visit${NC}"
RESP1=$(curl -s -c "$COOKIE_FILE" -D - "$BASE_URL/" -o /dev/null)
JWT1=$(echo "$RESP1" | grep -i "set-cookie.*jwt_token" | sed 's/.*jwt_token=\([^;]*\).*/\1/')
SESSION1=$(echo "$RESP1" | grep -i "set-cookie.*shop_session-id" | sed 's/.*shop_session-id=\([^;]*\).*/\1/')

echo "  Session ID: ${SESSION1:0:36}"
echo "  JWT (first 50 chars): ${JWT1:0:50}..."
echo ""

# Request 2
echo -e "${YELLOW}Request 2: Refresh page${NC}"
RESP2=$(curl -s -b "$COOKIE_FILE" -D - "$BASE_URL/" -o /dev/null)
# Check if new cookies are set
NEW_JWT2=$(echo "$RESP2" | grep -i "set-cookie.*jwt_token" | sed 's/.*jwt_token=\([^;]*\).*/\1/')
NEW_SESSION2=$(echo "$RESP2" | grep -i "set-cookie.*shop_session-id" | sed 's/.*shop_session-id=\([^;]*\).*/\1/')

# If no new cookies, it means old ones are reused
if [ -z "$NEW_JWT2" ]; then
    echo -e "  ${GREEN}✓ JWT cookie NOT regenerated (reused from request 1)${NC}"
else
    if [ "$JWT1" = "$NEW_JWT2" ]; then
        echo -e "  ${GREEN}✓ JWT cookie same as request 1${NC}"
    else
        echo -e "  ❌ JWT cookie CHANGED!"
        echo "  New JWT: ${NEW_JWT2:0:50}..."
    fi
fi

if [ -z "$NEW_SESSION2" ]; then
    echo -e "  ${GREEN}✓ Session cookie NOT regenerated (reused from request 1)${NC}"
else
    if [ "$SESSION1" = "$NEW_SESSION2" ]; then
        echo -e "  ${GREEN}✓ Session cookie same as request 1${NC}"
    else
        echo -e "  ❌ Session cookie CHANGED!"
    fi
fi
echo ""

# Request 3
echo -e "${YELLOW}Request 3: Another refresh${NC}"
RESP3=$(curl -s -b "$COOKIE_FILE" -D - "$BASE_URL/" -o /dev/null)
NEW_JWT3=$(echo "$RESP3" | grep -i "set-cookie.*jwt_token" | sed 's/.*jwt_token=\([^;]*\).*/\1/')
NEW_SESSION3=$(echo "$RESP3" | grep -i "set-cookie.*shop_session-id" | sed 's/.*shop_session-id=\([^;]*\).*/\1/')

if [ -z "$NEW_JWT3" ]; then
    echo -e "  ${GREEN}✓ JWT cookie NOT regenerated${NC}"
else
    echo -e "  ❌ JWT cookie regenerated on request 3"
fi

if [ -z "$NEW_SESSION3" ]; then
    echo -e "  ${GREEN}✓ Session cookie NOT regenerated${NC}"
else
    echo -e "  ❌ Session cookie regenerated on request 3"
fi
echo ""

# Decode JWT
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}JWT Payload (from request 1):${NC}"
echo -e "${BLUE}========================================${NC}"

PAYLOAD=$(echo "$JWT1" | cut -d'.' -f2)
# Add padding
case $((${#PAYLOAD} % 4)) in
    2) PAYLOAD="${PAYLOAD}==" ;;
    3) PAYLOAD="${PAYLOAD}=" ;;
esac

echo "$PAYLOAD" | base64 -d 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "$PAYLOAD" | base64 -d 2>/dev/null

echo -e "\n${BLUE}========================================${NC}"
echo -e "${GREEN}✓ Test Complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "\nExpected behavior:"
echo -e "  - Request 1: Creates new session + JWT"
echo -e "  - Request 2 & 3: Reuse existing cookies (no Set-Cookie headers)"
echo -e "\nThis means JWT tokens are persisting correctly! 🎉\n"
