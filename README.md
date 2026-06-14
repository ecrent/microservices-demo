# Optimizing network traffic by reducing metadata in microservices that use JWT and GRPC

> **Note**: This is a modified version of [Google's microservices-demo](https://github.com/GoogleCloudPlatform/microservices-demo) 
> extended for academic research on JWT compression optimization. See [ATTRIBUTION.md](ATTRIBUTION.md) for details.

## Overview

This repository demonstrates JWT compression techniques in a microservices architecture:
- **JWT Authentication**: Token-based authentication across services
- **JWT Compression**: Optional compression feature that splits JWT into multiple headers for better HTTP/2 HPACK caching
- **Performance Testing**: Comprehensive benchmarking tools to measure compression benefits

## Thesis

[Thesis is publicly available here](https://doi.org/10.5281/zenodo.20688308)

## Research Focus

This project investigates the performance impact of JWT compression in microservices environments, specifically:
- Network bandwidth reduction through header optimization
- HTTP/2 HPACK caching efficiency with split JWT headers
- Latency improvements under high concurrent load
- Scalability characteristics with compressed vs. uncompressed tokens

### Prerequisites

The following tools should already be available in your Github Codespace (at least 4core and 16GB ram):

- `kubectl` - Kubernetes CLI
- `jq` - JSON processor
- `tshark` - Network analysis
- `git` - Version control
- `minikube` - Lightweight Kubernetes


## Step-by-Step Instructions

### Step 1: Enable JWT Compression and Run Test


```bash
sudo apt update && sudo apt upgrade
```

```bash
minikube start
```
```bash
minikube ssh "sudo apt-get update && sudo apt-get install -y tcpdump"
```

Install skaffold for linux x86_64

```bash
curl -Lo skaffold https://storage.googleapis.com/skaffold/releases/latest/skaffold-linux-amd64 && sudo install skaffold /usr/local/bin/ && rm skaffold && skaffold version
```

Install k6 and tcpdump

```bash
curl -L https://github.com/grafana/k6/releases/download/v0.51.0/k6-v0.51.0-linux-amd64.tar.gz -o k6.tar.gz && tar -xzf k6.tar.gz && sudo mv k6-v0.51.0-linux-amd64/k6 /usr/local/bin/ && rm -rf k6.tar.gz k6-v0.51.0-linux-amd64 && k6 version
```
Install tshark

```bash
sudo DEBIAN_FRONTEND=noninteractive apt-get installsudo DEBIAN_FRONTEND=noninteractive apt-get install
```

```bash
sudo apt-get update && sudo apt-get install -y tcpdump
```

Enable JWT compression across all services:

```bash
./enable_jwt_compression.sh
```
This will take a little while.

**What this does:**
- Updates YAML manifests to set `ENABLE_JWT_COMPRESSION=true`
- Deploys changes using `skaffold run`
- Rebuilds and restarts all affected pods


### Step 2: Verify Pods are Running

Before running the test, confirm all pods are healthy:

```bash
kubectl get pods
```

If pods are not ready, wait a few more minutes and check again.

### Step 3: Run JWT Compression Test (Enabled)

The default settings for the test is for 512kb Dynamic Table size and for 200 Users

Run the load test with JWT compression enabled:

```bash
./run-jwt-compression-test.s
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

### Step 5: Verify Pods are Running

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


**Edit the script first** to set your test directories at the top:

```bash
# Edit these lines with your actual directory names
ENABLED_DIR="jwt-compression-on-results-20251017_143022"
DISABLED_DIR="jwt-compression-off-results-20251017_144530"
```

```bash
./compare-jwt-compression-enhanced.sh
```



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

*Last updated: December 14, 2025*
