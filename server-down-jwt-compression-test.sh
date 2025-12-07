#!/bin/bash

set -e

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_DIR="./jwt-compression-results-${TIMESTAMP}"
ERROR_RATE=${1:-0.1}  # Default 10% error rate
mkdir -p "${RESULTS_DIR}"

echo "======================================================================"
echo "  JWT Compression Performance Test with Error Injection"
echo "  Testing HPACK efficiency with ${ERROR_RATE} ($(echo "$ERROR_RATE * 100" | bc)%) error rate"
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

# Check if port-forward is already running
if ! pgrep -f "kubectl.*port-forward.*8080:8080" > /dev/null; then
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

# ====================================================================
# Enable error injection
# ====================================================================
echo "======================================================================"
echo "  Enabling Error Injection (${ERROR_RATE} rate)"
echo "======================================================================"
echo ""

kubectl set env deployment/frontend \
    ENABLE_ERROR_INJECTION=true \
    ERROR_INJECTION_RATE=${ERROR_RATE} \
    ERROR_INJECTION_TYPE=unavailable \
    ERROR_INJECTION_TARGET=CartService

echo "Waiting for deployment to roll out..."
kubectl rollout status deployment/frontend
echo ""

# Refresh pod names after rollout
FRONTEND_POD=$(kubectl get pods -l app=frontend -o jsonpath='{.items[0].metadata.name}')
echo "New frontend pod: ${FRONTEND_POD}"

# Kill old port-forward and restart it (rollout killed the old connection)
echo "Restarting port-forward after rollout..."
pkill -f "kubectl.*port-forward.*8080:80" 2>/dev/null || true
sleep 2
kubectl port-forward service/frontend 8080:80 > /dev/null 2>&1 &
PORT_FORWARD_PID=$!
sleep 3

# Verify port-forward is working
if curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/_healthz 2>/dev/null | grep -q "200"; then
    echo "Port-forward is working (PID: ${PORT_FORWARD_PID})"
else
    echo "Warning: Port-forward may not be working properly"
fi
echo ""

# Function to cleanup on exit
cleanup() {
    echo ""
    echo "======================================================================"
    echo "  Cleaning up..."
    echo "======================================================================"
    
    # Stop tcpdump capture on minikube node
    if [ "$TCPDUMP_RUNNING" = "yes" ]; then
        echo "Stopping tcpdump in minikube..."
        minikube ssh "sudo pkill -INT tcpdump" 2>/dev/null || true
        sleep 3
    fi
    
    # Copy pcap file from minikube node
    echo "Downloading capture file from minikube..."
    if minikube cp minikube:/tmp/frontend-cart-traffic.pcap "${RESULTS_DIR}/frontend-cart-traffic.pcap" 2>/dev/null; then
        PCAP_SIZE=$(ls -lh "${RESULTS_DIR}/frontend-cart-traffic.pcap" | awk '{print $5}')
        echo "  ✓ Captured pcap file: ${PCAP_SIZE}"
    else
        echo "  ✗ Warning: Could not copy pcap file"
    fi
    
    # Clean up on minikube
    minikube ssh "sudo rm -f /tmp/frontend-cart-traffic.pcap /tmp/tcpdump.log" 2>/dev/null || true
    
    # Disable error injection (no wait for rollout to complete)
    echo "Disabling error injection (will rollout in background)..."
    kubectl set env deployment/frontend ENABLE_ERROR_INJECTION=false 2>/dev/null || true
    # Don't wait for rollout - let it happen in background
    
    # Stop port-forward if we started it
    if [ ! -z "${PORT_FORWARD_PID}" ]; then
        echo "Stopping port-forward (PID: ${PORT_FORWARD_PID})..."
        kill ${PORT_FORWARD_PID} 2>/dev/null || true
    fi
    
    echo "Cleanup complete"
    echo "Note: Error injection will be disabled after deployment rollout completes."
}

trap cleanup EXIT

# ====================================================================
# Start tcpdump on host to capture frontend <-> cartservice traffic
# ====================================================================
echo "======================================================================"
echo "  Starting traffic capture on Minikube node..."
echo "======================================================================"

# Get pod IPs
FRONTEND_IP=$(kubectl get pod ${FRONTEND_POD} -o jsonpath='{.status.podIP}')
CARTSERVICE_IP=$(kubectl get pod ${CARTSERVICE_POD} -o jsonpath='{.status.podIP}')

echo "Frontend IP: ${FRONTEND_IP}"
echo "CartService IP: ${CARTSERVICE_IP}"

# Clean up any old pcap file
minikube ssh "sudo rm -f /tmp/frontend-cart-traffic.pcap" 2>/dev/null || true

# Start tcpdump on minikube node using nohup to keep it running after SSH disconnects
minikube ssh "sudo sh -c 'nohup tcpdump -i any -s 0 \"(host ${FRONTEND_IP} and host ${CARTSERVICE_IP}) and tcp port 7070\" -w /tmp/frontend-cart-traffic.pcap > /tmp/tcpdump.log 2>&1 &'" 

# Give tcpdump a moment to start
sleep 2

# Verify tcpdump is running
TCPDUMP_CHECK=$(minikube ssh "pgrep tcpdump" 2>/dev/null || echo "")
if [ ! -z "$TCPDUMP_CHECK" ]; then
    echo "Traffic capture started successfully (tcpdump PID in minikube: ${TCPDUMP_CHECK})"
    TCPDUMP_RUNNING="yes"
else
    echo "⚠ Warning: tcpdump may not have started properly"
    TCPDUMP_RUNNING=""
fi

echo "Capturing traffic between ${FRONTEND_IP} <-> ${CARTSERVICE_IP} on port 7070"
sleep 1

# ====================================================================
# Background job: Trigger cartservice outage during test
# ====================================================================
(
    # Wait for 130 seconds (60s ramp-up + 70s steady state)
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Outage scheduler: Waiting 130 seconds before triggering cartservice outage..."
    sleep 130
    
    echo ""
    echo "======================================================================"
    echo "  [$(date '+%Y-%m-%d %H:%M:%S')] TRIGGERING CARTSERVICE OUTAGE"
    echo "======================================================================"
    echo "Scaling cartservice to 0 replicas..."
    kubectl scale deployment/cartservice --replicas=0
    
    echo "Waiting for pod to terminate..."
    kubectl wait --for=delete pod -l app=cartservice --timeout=30s 2>/dev/null || true
    echo "  ✓ Cartservice pod terminated"
    
    echo "Outage duration: 10 seconds..."
    sleep 10
    
    echo ""
    echo "======================================================================"
    echo "  [$(date '+%Y-%m-%d %H:%M:%S')] RESTORING CARTSERVICE"
    echo "======================================================================"
    echo "Scaling cartservice back to 1 replica..."
    kubectl scale deployment/cartservice --replicas=1
    
    echo "Waiting for new pod to be ready..."
    kubectl wait --for=condition=ready pod -l app=cartservice --timeout=60s
    
    NEW_CARTSERVICE_POD=$(kubectl get pods -l app=cartservice -o jsonpath='{.items[0].metadata.name}')
    NEW_CARTSERVICE_IP=$(kubectl get pod ${NEW_CARTSERVICE_POD} -o jsonpath='{.status.podIP}')
    
    echo "  ✓ Cartservice restored"
    echo "  New pod: ${NEW_CARTSERVICE_POD}"
    echo "  New IP: ${NEW_CARTSERVICE_IP}"
    echo "  Note: HPACK dynamic table has been reset (cold cache)"
    echo ""
    echo "======================================================================"
    
) &

OUTAGE_JOB_PID=$!
echo "[Background] Cartservice outage scheduled (PID: ${OUTAGE_JOB_PID})"
echo ""

# ====================================================================
# Run k6 load test
# ====================================================================
echo ""
echo "======================================================================"
echo "  Running k6 load test with ${ERROR_RATE} error rate + scheduled outage"
echo "======================================================================"
echo ""
echo "Test scenario:"
echo "  1. User visits frontpage → Gets JWT"
echo "  2. User adds items to cart → Uses JWT"
echo "  3. User places order → Uses JWT"
echo "  4. ${ERROR_RATE} ($(echo "$ERROR_RATE * 100" | bc)%) of cart service calls will fail"
echo ""
echo "Scheduled service outage:"
echo "  - Timing: 130s after test start (70s into steady state)"
echo "  - Duration: 10 seconds + deployment time"
echo "  - Impact: CartService pod restart → HPACK dynamic table reset"
echo ""

echo "Starting test..."
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

# Wait for outage job to complete if still running
if kill -0 ${OUTAGE_JOB_PID} 2>/dev/null; then
    echo "Waiting for outage job to complete..."
    wait ${OUTAGE_JOB_PID} 2>/dev/null || true
fi

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
echo "1. Open pcap file in Wireshark:"
echo "   wireshark ${RESULTS_DIR}/frontend-cart-traffic.pcap"
echo ""
echo "2. Apply display filter:"
echo "   http2"
echo ""
echo "3. Look for HEADERS frames containing JWT headers:"
echo "   - x-jwt-header (HPACK indexed after first request)"
echo "   - x-jwt-payload (raw JSON payload)"
echo "   - x-jwt-sig (base64url signature)"
echo ""
echo "4. Or use tshark for quick analysis:"
echo "   tshark -r ${RESULTS_DIR}/frontend-cart-traffic.pcap -Y 'http2.type==1' -T fields -e frame.number -e frame.len -e http2.header.length"
echo ""
echo "======================================================================"
