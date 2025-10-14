#!/bin/bash

set -e

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_DIR="./jwt-simple-test-${TIMESTAMP}"
mkdir -p "${RESULTS_DIR}"

echo "======================================================================"
echo "  Simple JWT Test - Single User Journey"
echo "======================================================================"
echo ""
echo "Test scenario:"
echo "  1. User visits frontpage → Gets JWT"
echo "  2. User adds 1 item to cart → Uses JWT in gRPC call"
echo "  Total duration: ~10 seconds"
echo ""
echo "Results will be saved to: ${RESULTS_DIR}"
echo ""

# Get pod names
FRONTEND_POD=$(kubectl get pods -l app=frontend -o jsonpath='{.items[0].metadata.name}')
CARTSERVICE_POD=$(kubectl get pods -l app=cartservice -o jsonpath='{.items[0].metadata.name}')

if [ -z "${FRONTEND_POD}" ] || [ -z "${CARTSERVICE_POD}" ]; then
    echo "Error: Could not find frontend or cartservice pods"
    exit 1
fi

echo "Frontend pod: ${FRONTEND_POD}"
echo "Cart service pod: ${CARTSERVICE_POD}"
echo ""

# Check if port-forward is already running
if ! pgrep -f "kubectl.*port-forward.*8080:80" > /dev/null; then
    echo "Starting port-forward to frontend service..."
    kubectl port-forward service/frontend 8080:80 > /dev/null 2>&1 &
    PORT_FORWARD_PID=$!
    sleep 3
    echo "Port-forward started (PID: ${PORT_FORWARD_PID})"
else
    echo "Port-forward already running"
    PORT_FORWARD_PID=""
fi

echo ""

# Function to cleanup on exit
cleanup() {
    echo ""
    echo "======================================================================"
    echo "  Cleaning up..."
    echo "======================================================================"
    
    # Stop tcpdump capture on minikube node
    if [ ! -z "${TCPDUMP_PID}" ]; then
        echo "Stopping tcpdump (PID: ${TCPDUMP_PID})..."
        kill -INT ${TCPDUMP_PID} 2>/dev/null || true
        sleep 2
    fi
    
    # Copy pcap file from minikube node
    echo "Downloading capture file from minikube..."
    minikube cp minikube:/tmp/frontend-cart-traffic.pcap "${RESULTS_DIR}/frontend-cart-traffic.pcap" 2>/dev/null || echo "  Warning: Could not copy pcap file"
    
    # Stop port-forward if we started it
    if [ ! -z "${PORT_FORWARD_PID}" ]; then
        echo "Stopping port-forward (PID: ${PORT_FORWARD_PID})..."
        kill ${PORT_FORWARD_PID} 2>/dev/null || true
    fi
    
    echo "Cleanup complete"
}

trap cleanup EXIT

# ====================================================================
# Start tcpdump on minikube node to capture frontend <-> cartservice traffic
# ====================================================================
echo "======================================================================"
echo "  Starting traffic capture on Minikube node..."
echo "======================================================================"

# Get pod IPs
FRONTEND_IP=$(kubectl get pod ${FRONTEND_POD} -o jsonpath='{.status.podIP}')
CARTSERVICE_IP=$(kubectl get pod ${CARTSERVICE_POD} -o jsonpath='{.status.podIP}')

echo "Frontend IP: ${FRONTEND_IP}"
echo "CartService IP: ${CARTSERVICE_IP}"

# Start tcpdump on minikube node (capturing gRPC traffic on port 7070)
minikube ssh "sudo tcpdump -i any -s 0 '(host ${FRONTEND_IP} and host ${CARTSERVICE_IP}) and tcp port 7070' -w /tmp/frontend-cart-traffic.pcap" > /dev/null 2>&1 &
TCPDUMP_PID=$!

echo "Traffic capture started on minikube node (PID: ${TCPDUMP_PID})"
echo "Capturing gRPC traffic between ${FRONTEND_IP} <-> ${CARTSERVICE_IP} on port 7070"
sleep 3

# ====================================================================
# Run k6 simple test
# ====================================================================
echo ""
echo "======================================================================"
echo "  Running k6 simple test (1 user, 10 seconds max)"
echo "======================================================================"
echo ""

k6 run \
    --out json="${RESULTS_DIR}/k6-results.json" \
    --summary-export="${RESULTS_DIR}/k6-summary.json" \
    k6-simple-test.js 2>&1 | tee "${RESULTS_DIR}/k6-output.log"

echo ""
echo "======================================================================"
echo "  Test completed!"
echo "======================================================================"
echo ""

# Give tcpdump a moment to flush buffers
sleep 3

echo "Capture files and results saved to: ${RESULTS_DIR}"
echo ""
echo "Generated files:"
ls -lh "${RESULTS_DIR}/"
echo ""
echo "======================================================================"
echo "  Analysis Instructions"
echo "======================================================================"
echo ""
echo "To analyze the gRPC call with JWT headers:"
echo ""
echo "1. Open pcap in Wireshark:"
echo "   wireshark ${RESULTS_DIR}/frontend-cart-traffic.pcap"
echo ""
echo "2. Apply display filter:"
echo "   http2"
echo ""
echo "3. Find the AddItem gRPC call (HEADERS frame)"
echo "   Look for ':path' = '/hipstershop.CartService/AddItem'"
echo ""
echo "4. Expand 'Header: ' section to see JWT headers:"
echo "   - x-jwt-static"
echo "   - x-jwt-session"
echo "   - x-jwt-dynamic"
echo "   - x-jwt-sig"
echo ""
echo "5. Check HPACK representation for each header:"
echo "   - Should see 'Literal Header Field with Incremental Indexing'"
echo "   - Note the byte sizes"
echo ""
echo "6. Or use tshark for quick analysis:"
echo "   tshark -r ${RESULTS_DIR}/frontend-cart-traffic.pcap -Y 'http2.type==1' -V | grep -A 5 'x-jwt'"
echo ""
echo "======================================================================"
