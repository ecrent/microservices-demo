#!/bin/bash

# Script to capture network traffic between pods during the JWT flow test.
# This script will:
# 1. Start a tcpdump capture on the minikube node.
# 2. Run the test_jwt_flow.sh script.
# 3. Stop the tcpdump capture.
# 4. Copy the capture file locally.
# 5. Clean up the remote capture file.

set -e

echo "=========================================="
echo "Network Traffic Capture Script"
echo "=========================================="
echo ""

# Create a directory for the captures
mkdir -p captures

CAPTURE_FILE="/tmp/pod-traffic-capture.pcap"

# Find an available filename
BASE_NAME="pod-traffic-capture"
COUNTER=1
LOCAL_CAPTURE_FILE="captures/${BASE_NAME}.pcap"

while [ -f "$LOCAL_CAPTURE_FILE" ]; do
    COUNTER=$((COUNTER + 1))
    LOCAL_CAPTURE_FILE="captures/${BASE_NAME}-${COUNTER}.pcap"
done

echo "Will save capture to: ${LOCAL_CAPTURE_FILE}"

echo "Starting tcpdump on minikube node..."
echo "Capturing all TCP traffic between pods..."
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

echo ""
echo "Waiting for 2 seconds for tcpdump to initialize..."
sleep 2
echo ""

echo "=========================================="
echo "Running JWT Flow Test..."
echo "=========================================="
./test_jwt_flow.sh
echo "=========================================="
echo "JWT Flow Test Finished."
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
echo "PCAP file saved: ${LOCAL_CAPTURE_FILE}"
FILE_SIZE=$(ls -lh ${LOCAL_CAPTURE_FILE} 2>/dev/null | awk '{print $5}' || echo "unknown")
echo "File size: ${FILE_SIZE}"
echo ""
echo "You can now analyze this file with tools like Wireshark."
echo "For example: wireshark ${LOCAL_CAPTURE_FILE}"
echo "Or use tshark for command-line analysis: tshark -r ${LOCAL_CAPTURE_FILE}"
echo ""
