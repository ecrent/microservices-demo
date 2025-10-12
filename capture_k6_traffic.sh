#!/bin/bash

# Script to capture network traffic during k6 load test for JWT compression analysis.
# This script will:
# 1. Start a tcpdump capture on the minikube node.
# 2. Run the k6 load test.
# 3. Stop the tcpdump capture.
# 4. Copy the capture file locally.
# 5. Clean up the remote capture file.

set -e

# Parameters
COMPRESSION_MODE=${1:-"jwt-compression-on"}
TEST_DURATION=${2:-"5m"}
FRONTEND_URL=${3:-"http://localhost:8080"}

echo "=========================================="
echo "k6 Load Test Traffic Capture Script"
echo "=========================================="
echo ""
echo "Configuration:"
echo "  Compression Mode: $COMPRESSION_MODE"
echo "  Test Duration: $TEST_DURATION"
echo "  Frontend URL: $FRONTEND_URL"
echo "  NOTE: Using 5 VUs (test mode) - Edit k6-jwt-load-test.js for production 500 VUs"
echo ""

# Create a directory for the captures
mkdir -p captures

CAPTURE_FILE="/tmp/k6-traffic-capture.pcap"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Generate capture filename based on compression mode
BASE_NAME="k6-${COMPRESSION_MODE}-${TIMESTAMP}"
LOCAL_CAPTURE_FILE="captures/${BASE_NAME}.pcap"

echo "Will save capture to: ${LOCAL_CAPTURE_FILE}"

echo "Starting tcpdump on minikube node..."
echo "Capturing all TCP traffic between pods (excluding SSH)..."
echo ""

# Start tcpdump on minikube in the background
# We need to get the actual tcpdump PID, not the sudo wrapper
# Use nohup and disown to ensure it stays running after SSH exits
minikube ssh "sudo nohup tcpdump -i any -w ${CAPTURE_FILE} 'tcp and not port 22' >/dev/null 2>&1 & sleep 1 && pgrep -f \"tcpdump.*${CAPTURE_FILE}\" | head -1 | sudo tee /tmp/tcpdump.pid"
sleep 2

# Get the PID and clean it up
TCPDUMP_PID=$(minikube ssh "sudo cat /tmp/tcpdump.pid 2>/dev/null" | tr -d '[:space:]')
echo "✓ Tcpdump started on minikube node with PID: $TCPDUMP_PID"
echo ""

# Verify tcpdump is running
echo "Verifying tcpdump is running..."
if [ -n "$TCPDUMP_PID" ]; then
    minikube ssh "sudo ps -p $TCPDUMP_PID >/dev/null 2>&1" && echo "✓ Tcpdump is running" || echo "Warning: tcpdump process not found"
else
    echo "Warning: Could not get tcpdump PID"
fi
echo ""

echo "Waiting for 2 seconds for tcpdump to initialize..."
sleep 2
echo ""

echo "=========================================="
echo "Running k6 Load Test..."
echo "=========================================="
echo ""

# Run k6 load test
k6 run \
  --duration "$TEST_DURATION" \
  --env BASE_URL="$FRONTEND_URL" \
  --out json="captures/k6-results-${COMPRESSION_MODE}-${TIMESTAMP}.json" \
  --summary-export="captures/k6-summary-${COMPRESSION_MODE}-${TIMESTAMP}.json" \
  k6-jwt-load-test.js

echo ""
echo "=========================================="
echo "k6 Load Test Finished."
echo "=========================================="
echo ""

echo "Stopping tcpdump on minikube node..."
CLEAN_PID=$(echo "$TCPDUMP_PID" | tr -d '[:space:]')
if [ -n "$CLEAN_PID" ] && [ "$CLEAN_PID" != "unknown" ]; then
  minikube ssh "sudo kill $CLEAN_PID 2>/dev/null || true"
  sleep 2
  echo "✓ Tcpdump stopped (PID: $CLEAN_PID)"
else
  echo "⚠ Could not stop tcpdump - PID not found"
fi
echo ""

# Verify the file was created
echo "Verifying capture file..."
minikube ssh "sudo ls -lh ${CAPTURE_FILE} 2>/dev/null || echo 'File not found'"
echo ""

echo "Copying capture file locally..."
minikube ssh "sudo chmod 644 ${CAPTURE_FILE}"
minikube cp minikube:${CAPTURE_FILE} ${LOCAL_CAPTURE_FILE}
echo "✓ Capture file saved to: ${LOCAL_CAPTURE_FILE}"
echo ""

echo "Cleaning up remote capture files..."
minikube ssh "sudo rm -f ${CAPTURE_FILE} /tmp/tcpdump.log /tmp/tcpdump.pid"
echo "✓ Cleanup complete"
echo ""

echo ""
echo "=========================================="
echo "Capture Complete! ✅"
echo "=========================================="
echo ""
echo "Files saved:"
echo "  📦 PCAP: ${LOCAL_CAPTURE_FILE}"
echo "  📊 k6 Results: captures/k6-results-${COMPRESSION_MODE}-${TIMESTAMP}.json"
echo "  📈 k6 Summary: captures/k6-summary-${COMPRESSION_MODE}-${TIMESTAMP}.json"
echo ""

FILE_SIZE=$(ls -lh ${LOCAL_CAPTURE_FILE} 2>/dev/null | awk '{print $5}' || echo "unknown")
echo "PCAP file size: ${FILE_SIZE}"
echo ""

echo "Analysis commands:"
echo "  1. View in Wireshark:"
echo "     wireshark ${LOCAL_CAPTURE_FILE}"
echo ""
echo "  2. Extract HTTP/2 headers (gRPC):"
echo "     tshark -r ${LOCAL_CAPTURE_FILE} -Y 'http2' -T fields -e http2.header.name -e http2.header.value"
echo ""
echo "  3. Count JWT headers:"
echo "     tshark -r ${LOCAL_CAPTURE_FILE} -Y 'http2.header.name == \"authorization\"' | wc -l"
echo "     tshark -r ${LOCAL_CAPTURE_FILE} -Y 'http2.header.name == \"x-jwt-static\"' | wc -l"
echo ""
echo "  4. Measure bandwidth:"
echo "     tshark -r ${LOCAL_CAPTURE_FILE} -q -z io,stat,10"
echo ""
