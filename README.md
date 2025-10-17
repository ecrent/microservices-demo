# JWT Compression Test Guide

This guide walks you through testing JWT compression performance in the microservices demo application using GitHub Codespaces.

## Overview

This repository extends Google's microservices demo with:
- **JWT Authentication**: Token-based authentication across services
- **JWT Compression**: Optional compression feature that splits JWT into multiple headers for better HTTP/2 HPACK caching

## Test Environment

- **Platform**: GitHub Codespaces (Ubuntu 24.04.2 LTS)
- **Orchestration**: Kubernetes with Skaffold
- **Load Testing**: k6
- **Network Analysis**: tcpdump, tshark, Wireshark

## Prerequisites

The following tools should already be available in your Codespace:
- `kubectl` - Kubernetes CLI
- `skaffold` - Kubernetes development tool
- `k6` - Load testing tool
- `jq` - JSON processor
- `tshark` - Network analysis
- `git` - Version control

## Test Workflow

The complete test involves 5 main steps:

```
1. Enable JWT Compression → Deploy → Verify pods are healthy → Test → Capture Results
2. Disable JWT Compression → Deploy → Verify pods are healthy → Test → Capture Results  
3. Compare results from both tests

```

---

## Step-by-Step Instructions

### Step 1: Enable JWT Compression and Run Test

First, enable JWT compression across all services:

```bash
./enable_jwt_compression.sh
```

**What this does:**
- Updates YAML manifests to set `ENABLE_JWT_COMPRESSION=true`
- Deploys changes using `skaffold run`
- Rebuilds and restarts all affected pods


### Step 2: Verify Pods are Running

Before running the test, confirm all pods are healthy:

```bash
kubectl get pods
```

**Wait until all pods show:**
- `READY`: `1/1`
- `STATUS`: `Running`
- `RESTARTS`: Low count (0-2)

**Example healthy output:**
```
NAME                                     READY   STATUS    RESTARTS   AGE
adservice-76bdd69666-ckc5j               1/1     Running   0          2m
cartservice-66d497c6b7-dp5jr             1/1     Running   0          2m
checkoutservice-666c784bd6-4jd22         1/1     Running   0          2m
currencyservice-5d5d496984-4jmd7         1/1     Running   0          2m
emailservice-667457d9d6-75jcq            1/1     Running   0          2m
frontend-6b8d69b9fb-wjqdg                1/1     Running   0          2m
...
```

If pods are not ready, wait a few more minutes and check again.

### Step 3: Run JWT Compression Test (Enabled)

Run the load test with JWT compression enabled:

```bash
./run-jwt-compression-test.sh
```

**What this does:**
- Starts network packet capture (tcpdump)
- Runs k6 load test simulating user journeys
- Captures performance metrics
- Saves results to a timestamped directory


### Step 4: Disable JWT Compression and Run Test

Now disable JWT compression:

```bash
./disable_jwt_compression.sh
```

### Step 5: Verify Pods are Running (Again)

Verify all pods restarted successfully:

```bash
kubectl get pods
```

Wait for all pods to be `Running` with `1/1` ready.

### Step 6: Run JWT Compression Test (Disabled)

Run the load test again with JWT compression disabled:

```bash
./run-jwt-compression-test.sh
```


### Step 7: Compare Results

Now compare the performance between both tests:

```bash
./compare-jwt-compression-enhanced.sh
```

**Edit the script first** to set your test directories at the top:

```bash
# Edit these lines with your actual directory names
ENABLED_DIR="jwt-compression-on-results-20251017_143022"
DISABLED_DIR="jwt-compression-off-results-20251017_144530"
```

Or modify the script to accept command-line arguments.

**What the comparison shows:**

1. **K6 Load Test Results**
   - Iterations, request rate
   - Data sent/received
   - Response times (avg, p95, p99)
   - Failed requests and checks

2. **Performance Improvements**
   - Bandwidth savings (upload/download)
   - Response time differences
   - Network traffic reduction

3. **Network Traffic Analysis**
   - Total packets and bytes
   - HTTP/2 traffic patterns
   - JWT header usage

4. **JWT Header Analysis**
   - Compression ON: 4 headers (~744 bytes first request, ~470 bytes cached)
   - Compression OFF: 1 header (~900+ bytes every request)

5. **Summary**
   - Overall bandwidth savings percentage
   - Performance improvements
   - Key benefits


## Troubleshooting

### Pods Not Starting
```bash
# Check pod status and events
kubectl describe pod <pod-name>

# Check logs
kubectl logs <pod-name>

# Restart deployment
kubectl rollout restart deployment <service-name>
```

### Test Script Fails
```bash
# Ensure scripts are executable
chmod +x *.sh

# Check if k6 is installed
k6 version

# Verify network tools
which tcpdump tshark
```

### Skaffold Errors
```bash
# Check Skaffold configuration
skaffold diagnose

# Clean and rebuild
skaffold delete
skaffold run
```

### Comparison Script Issues
```bash
# Verify test result directories exist
ls -la jwt-compression-*-results-*/

# Check if jq is installed
jq --version

# Manually check results
cat jwt-compression-on-results-*/k6-summary.json | jq .
```

---

## Advanced Analysis

### View Packet Captures

To analyze network traffic in detail:

```bash
# Install Wireshark (if not available)
sudo apt-get install wireshark

# Open pcap files
wireshark jwt-compression-on-results-*/frontend-cart-traffic.pcap &
wireshark jwt-compression-off-results-*/frontend-cart-traffic.pcap &
```

### Manual Metrics Extraction

```bash
# View k6 summary
cat jwt-compression-on-results-*/k6-summary.json | jq .

# Extract specific metrics
cat jwt-compression-on-results-*/k6-summary.json | jq '.metrics.http_req_duration.avg'

# Analyze PCAP with tshark
tshark -r jwt-compression-on-results-*/frontend-cart-traffic.pcap \
  -d tcp.port==7070,http2 \
  -Y 'http2.header.name contains "jwt"'
```

### Verify Environment Variables

```bash
# Check JWT compression setting for a service
kubectl get deployment frontend -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="ENABLE_JWT_COMPRESSION")].value}' && echo

# Check all services
for svc in frontend checkoutservice cartservice shippingservice paymentservice emailservice; do
  echo -n "$svc: "
  kubectl get deployment $svc -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="ENABLE_JWT_COMPRESSION")].value}' && echo
done
```

---

## Quick Reference

### Essential Commands

```bash
# 1. Enable compression
./enable_jwt_compression.sh

# 2. Check pods
kubectl get pods

# 3. Run test
./run-jwt-compression-test.sh

# 4. Disable compression
./disable_jwt_compression.sh

# 5. Check pods again
kubectl get pods

# 6. Run test again
./run-jwt-compression-test.sh

# 7. Compare results
./compare-jwt-compression-enhanced.sh
```


*Last updated: October 17, 2025*
