#!/bin/bash

# Script to disable JWT compression across all services
# This updates the YAML manifests and applies changes to running pods

set -e

SERVICES="frontend checkoutservice cartservice shippingservice paymentservice emailservice"
MANIFEST_DIR="kubernetes-manifests"

echo "=========================================="
echo "DISABLING JWT COMPRESSION"
echo "=========================================="
echo ""

# Update YAML files
echo "Step 1: Updating YAML manifests..."
for service in $SERVICES; do
    yaml_file="$MANIFEST_DIR/${service}.yaml"
    
    if [ -f "$yaml_file" ]; then
        # Check if the env var exists
        if grep -q "name: ENABLE_JWT_COMPRESSION" "$yaml_file"; then
            # Replace true with false
            sed -i 's/name: ENABLE_JWT_COMPRESSION/name: ENABLE_JWT_COMPRESSION/; /name: ENABLE_JWT_COMPRESSION/{n; s/value: "true"/value: "false"/}' "$yaml_file"
            echo "  ✓ Updated $service: ENABLE_JWT_COMPRESSION = false"
        else
            echo "  ⚠️  Warning: ENABLE_JWT_COMPRESSION not found in $service"
        fi
    else
        echo "  ✗ Error: $yaml_file not found"
    fi
done

echo ""
echo "Step 2: Verifying changes..."
for service in $SERVICES; do
    yaml_file="$MANIFEST_DIR/${service}.yaml"
    if [ -f "$yaml_file" ]; then
        value=$(grep -A 1 "name: ENABLE_JWT_COMPRESSION" "$yaml_file" | grep "value:" | head -1 | awk '{print $2}' | tr -d '"')
        printf "  %-25s: %s\n" "$service" "$value"
    fi
done

echo ""
echo "Step 3: Deploying changes with Skaffold..."
skaffold run

echo ""
echo "=========================================="
echo "✓ JWT COMPRESSION DISABLED"
echo "=========================================="
echo ""
echo "To verify the change took effect, you can run:"
echo "  kubectl get deployment <service-name> -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name==\"ENABLE_JWT_COMPRESSION\")].value}' && echo"
echo ""
