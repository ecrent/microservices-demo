#!/bin/bash

set -e

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_DIR="./jwt-compression-results-${TIMESTAMP}"
mkdir -p "${RESULTS_DIR}"

echo "======================================================================"
echo "  JWT Compression Performance Test (WSL/Docker Desktop)"
echo "  Testing HPACK efficiency with JWT renewal scenario"
echo "======================================================================"
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

# Check if frontend is accessible on localhost:80
if ! curl -s -o /dev/null -w "%{http_code}" http://localhost:80 > /dev/null 2>&1; then
    echo "Warning: Frontend not accessible on localhost:80"
    echo "Make sure your frontend service is exposed via NodePort or LoadBalancer"
fi

echo ""

# Function to cleanup on exit
cleanup() {
    echo ""
    echo "======================================================================"
    echo "  Cleaning up..."
    echo "======================================================================"
    
    # Stop tcpdump in cartservice pod
    if [ ! -z "${TCPDUMP_PID}" ]; then
        echo "Stopping tcpdump in cartservice pod..."
        kubectl exec ${CARTSERVICE_POD} -- pkill -INT tcpdump 2>/dev/null || true
        sleep 2
    fi
    
    # Copy pcap file from cartservice pod
    echo "Downloading capture file from cartservice pod..."
    kubectl cp ${CARTSERVICE_POD}:/tmp/frontend-cart-traffic.pcap "${RESULTS_DIR}/frontend-cart-traffic.pcap" 2>/dev/null || echo "  Warning: Could not copy pcap file"
    
    # Clean up remote pcap file
    kubectl exec ${CARTSERVICE_POD} -- rm -f /tmp/frontend-cart-traffic.pcap 2>/dev/null || true
    
    echo "Cleanup complete"
}

trap cleanup EXIT

# ====================================================================
# Start tcpdump in cartservice pod to capture incoming traffic
# ====================================================================
echo "======================================================================"
echo "  Starting traffic capture in CartService pod..."
echo "======================================================================"

# Get pod IPs
FRONTEND_IP=$(kubectl get pod ${FRONTEND_POD} -o jsonpath='{.status.podIP}')
CARTSERVICE_IP=$(kubectl get pod ${CARTSERVICE_POD} -o jsonpath='{.status.podIP}')

echo "Frontend IP: ${FRONTEND_IP}"
echo "CartService IP: ${CARTSERVICE_IP}"

# Check if tcpdump is available in cartservice pod
if ! kubectl exec ${CARTSERVICE_POD} -- which tcpdump > /dev/null 2>&1; then
    echo ""
    echo "Warning: tcpdump not found in cartservice pod"
    echo "Installing tcpdump..."
    kubectl exec ${CARTSERVICE_POD} -- sh -c "apt-get update -qq && apt-get install -y -qq tcpdump" || {
        echo "Error: Could not install tcpdump. Trying alternative capture method..."
        # Alternative: capture from host network namespace
        CARTSERVICE_CONTAINER_ID=$(docker ps | grep ${CARTSERVICE_POD} | awk '{print $1}' | head -1)
        if [ ! -z "${CARTSERVICE_CONTAINER_ID}" ]; then
            echo "Using host tcpdump with container network namespace..."
            CART_PID=$(docker inspect -f '{{.State.Pid}}' ${CARTSERVICE_CONTAINER_ID})
            sudo nsenter -t ${CART_PID} -n tcpdump -i any -s 0 'tcp port 7070' -w "${RESULTS_DIR}/frontend-cart-traffic.pcap" > /dev/null 2>&1 &
            TCPDUMP_PID=$!
        else
            echo "Error: Could not set up traffic capture"
            exit 1
        fi
    }
fi

# Start tcpdump in cartservice pod
if [ -z "${TCPDUMP_PID}" ]; then
    kubectl exec ${CARTSERVICE_POD} -- sh -c "tcpdump -i any -s 0 'host ${FRONTEND_IP} and tcp port 7070' -w /tmp/frontend-cart-traffic.pcap" > /dev/null 2>&1 &
    TCPDUMP_PID=$!
    
    echo "Traffic capture started in cartservice pod (PID: ${TCPDUMP_PID})"
    echo "Capturing traffic from ${FRONTEND_IP} on port 7070"
    sleep 3
fi

# ====================================================================
# Run k6 load test
# ====================================================================
echo ""
echo "======================================================================"
echo "  Running k6 load test (100 users, ~3 minutes)"
echo "======================================================================"
echo ""
echo "Test scenario:"
echo "  1. User visits frontpage → Gets JWT #1"
echo "  2. User adds 2 items to cart → Uses JWT #1"
echo "  3. User waits 125 seconds → JWT expires"
echo "  4. User returns to shopping → Gets JWT #2"
echo "  5. User adds 1 item to cart → Uses JWT #2"
echo "  6. User places order → Uses JWT #2"
echo "  7. User continues shopping"
echo ""
echo "Expected HPACK behavior:"
echo "  - JWT #1: Cold cache, full 702 bytes transmitted"
echo "  - JWT #2: Warm cache, ~428 bytes (static+session cached)"
echo ""
echo "Starting test..."
echo ""

# Create WSL-specific k6 config
cat > /tmp/k6-test-wsl.js <<'EOF'
import { check, sleep } from 'k6';
import http from 'k6/http';

export let options = {
    scenarios: {
        default: {
            executor: 'per-vu-iterations',
            vus: 100,
            iterations: 1,
            maxDuration: '3m30s',
        },
    },
    thresholds: {
        'http_req_duration': ['p(95)<2000'],
        'http_req_failed': ['rate<0.05'],
    },
};

const BASE_URL = 'http://localhost';

export default function () {
    // Load the k6 test from the main file
    const mainTest = open(__ENV.K6_MAIN_TEST || 'k6-user-journey-test.js');
    // Update BASE_URL in the test
    const updatedTest = mainTest.replace(/const BASE_URL = .+;/, `const BASE_URL = '${BASE_URL}';`);
    eval(updatedTest);
}
EOF

k6 run \
    --out json="${RESULTS_DIR}/k6-results.json" \
    --summary-export="${RESULTS_DIR}/k6-summary.json" \
    k6-user-journey-test.js 2>&1 | tee "${RESULTS_DIR}/k6-output.log"

echo ""
echo "======================================================================"
echo "  Test completed!"
echo "======================================================================"
echo ""

# Give tcpdump a moment to flush buffers
sleep 5

echo "Capture files and results saved to: ${RESULTS_DIR}"
echo ""
echo "Generated files:"
ls -lh "${RESULTS_DIR}/"
echo ""
echo "======================================================================"
echo "  Analysis Instructions"
echo "======================================================================"
echo ""
echo "To analyze HTTP/2 HPACK compression:"
echo ""
echo "1. Open pcap files in Wireshark:"
echo "   wireshark ${RESULTS_DIR}/frontend-cart-traffic.pcap"
echo ""
echo "2. Apply display filter:"
echo "   http2"
echo ""
echo "3. Look for HEADERS frames containing JWT headers:"
echo "   - x-jwt-static (should use 'Indexed Header Field' after first request)"
echo "   - x-jwt-session (should use 'Indexed Header Field' after first request)"
echo "   - x-jwt-dynamic (should use 'Literal without Indexing' always)"
echo "   - x-jwt-sig (should use 'Literal without Indexing' always)"
echo ""
echo "4. Compare frame sizes:"
echo "   - First request (cold cache): HEADERS frame ~750+ bytes"
echo "   - Subsequent requests (warm cache): HEADERS frame ~450-500 bytes"
echo "   - After JWT renewal (125s wait): New session, partial cache hit"
echo ""
echo "5. Or use tshark for quick analysis:"
echo "   tshark -r ${RESULTS_DIR}/frontend-cart-traffic.pcap -d tcp.port==7070,http2 -Y 'http2.type==1' -T fields -e frame.number -e frame.len -e http2.header.length"
echo ""
echo "======================================================================"
