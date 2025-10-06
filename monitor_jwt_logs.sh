#!/bin/bash

# Real-time JWT Flow Monitor
# Shows live JWT compression logs from all services

echo "=========================================="
echo "JWT Flow Monitor - Real-time Logs"
echo "=========================================="
echo ""
echo "Monitoring JWT compression logs across all services..."
echo "Press Ctrl+C to stop"
echo ""

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

# Function to colorize service logs
colorize_logs() {
    while read -r line; do
        if [[ $line == *"Frontend"* ]]; then
            echo -e "${GREEN}$line${NC}"
        elif [[ $line == *"Checkout"* ]]; then
            echo -e "${BLUE}$line${NC}"
        elif [[ $line == *"Cart"* ]]; then
            echo -e "${YELLOW}$line${NC}"
        elif [[ $line == *"Payment"* ]]; then
            echo -e "${CYAN}$line${NC}"
        elif [[ $line == *"Shipping"* ]]; then
            echo -e "${RED}$line${NC}"
        elif [[ $line == *"Email"* ]]; then
            echo -e "\033[0;35m$line${NC}"  # Magenta
        else
            echo "$line"
        fi
    done
}

# Monitor all services in parallel
kubectl logs -f -l app=frontend --prefix=true 2>/dev/null | grep --line-buffered "\[JWT-FLOW\]\|\[JWT-COMPRESSION\]" &
kubectl logs -f -l app=checkoutservice --prefix=true 2>/dev/null | grep --line-buffered "\[JWT-FLOW\]\|\[JWT-COMPRESSION\]" &
kubectl logs -f -l app=cartservice --prefix=true 2>/dev/null | grep --line-buffered "\[JWT-FLOW\]\|\[JWT-COMPRESSION\]" &
kubectl logs -f -l app=paymentservice --prefix=true 2>/dev/null | grep --line-buffered "\[JWT-FLOW\]\|\[JWT-COMPRESSION\]" &
kubectl logs -f -l app=shippingservice --prefix=true 2>/dev/null | grep --line-buffered "\[JWT-FLOW\]\|\[JWT-COMPRESSION\]" &
kubectl logs -f -l app=emailservice --prefix=true 2>/dev/null | grep --line-buffered "\[JWT-FLOW\]\|\[JWT-COMPRESSION\]" &

# Wait for logs
wait
