#!/bin/bash
# JWT Compression Test for WSL/Docker Desktop
# Captures traffic from Docker host network namespace

set -e

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_DIR="./jwt-compression-results-${TIMESTAMP}"
mkdir -p "${RESULTS_DIR}"

echo "======================================================================"
echo "  JWT Compression Test (Docker Host Capture)"
echo "======================================================================"
echo ""
echo "Results will be saved to: ${RESULTS_DIR}"
echo ""

# Get pod information
FRONTEND_POD=$(kubectl get pods -l app=frontend -o jsonpath='{.items[0].metadata.name}')
CARTSERVICE_POD=$(kubectl get pods -l app=cartservice -o jsonpath='{.items[0].metadata.name}')

if [ -z "${FRONTEND_POD}" ] || [ -z "${CARTSERVICE_POD}" ]; then
    echo "Error: Could not find pods"
    exit 1
fi

# Get pod IPs
FRONTEND_IP=$(kubectl get pod ${FRONTEND_POD} -o jsonpath='{.status.podIP}')
CARTSERVICE_IP=$(kubectl get pod ${CARTSERVICE_POD} -o jsonpath='{.status.podIP}')

echo "Frontend pod: ${FRONTEND_POD} (${FRONTEND_IP})"
echo "Cart service pod: ${CARTSERVICE_POD} (${CARTSERVICE_IP})"
echo ""

# Cleanup function
cleanup() {
    echo ""
    echo "======================================================================"
    echo "  Cleaning up..."
    echo "======================================================================"
    
    if [ ! -z "${TCPDUMP_PID}" ]; then
        echo "Stopping tcpdump (PID: ${TCPDUMP_PID})..."
        sudo kill -INT ${TCPDUMP_PID} 2>/dev/null || true
        sleep 2
    fi
    
    echo "Cleanup complete"
}

trap cleanup EXIT

# ====================================================================
# Start tcpdump on Docker host
# ====================================================================
echo "======================================================================"
echo "  Starting traffic capture on host network..."
echo "======================================================================"

# Start tcpdump directly on host, capturing all traffic between the two IPs
echo "Capturing traffic between ${FRONTEND_IP} and ${CARTSERVICE_IP} on port 7070"
sudo tcpdump -i any -s 0 \
    "((host ${FRONTEND_IP} and host ${CARTSERVICE_IP}) and tcp port 7070)" \
    -w "${RESULTS_DIR}/frontend-cart-traffic.pcap" \
    > /dev/null 2>&1 &

TCPDUMP_PID=$!

sleep 2

if ps -p ${TCPDUMP_PID} > /dev/null; then
    echo "✓ Traffic capture started (PID: ${TCPDUMP_PID})"
    echo "  Writing to: ${RESULTS_DIR}/frontend-cart-traffic.pcap"
else
    echo "✗ tcpdump failed to start"
    exit 1
fi

# ====================================================================
# Run k6 test
# ====================================================================
echo ""
echo "======================================================================"
echo "  Running k6 load test (500 users)"
echo "======================================================================"
echo ""

k6 run \
    --out json="${RESULTS_DIR}/k6-results.json" \
    --summary-export="${RESULTS_DIR}/k6-summary.json" \
    k6-user-journey-test.js 2>&1 | tee "${RESULTS_DIR}/k6-output.log"

echo ""
echo "======================================================================"
echo "  Test completed!"
echo "======================================================================"
echo ""

# Give tcpdump time to flush
sleep 5

echo "Files saved to: ${RESULTS_DIR}"
ls -lh "${RESULTS_DIR}/"
echo ""
echo "======================================================================"
echo "  To analyze with Wireshark:"
echo "  wireshark ${RESULTS_DIR}/frontend-cart-traffic.pcap"
echo "======================================================================"
