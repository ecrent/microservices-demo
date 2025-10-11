#!/bin/bash

# Script to enable JWT compression across all microservices
# This sets ENABLE_JWT_COMPRESSION=true and restarts the pods

set -e

echo "=========================================="
echo "Enabling JWT Compression"
echo "=========================================="
echo ""

SERVICES=(
    "frontend"
    "checkoutservice"
    "cartservice"
    "shippingservice"
    "paymentservice"
    "emailservice"
)

echo "Setting ENABLE_JWT_COMPRESSION=true for all services..."
echo ""

for service in "${SERVICES[@]}"; do
    echo "📝 Setting $service..."
    kubectl set env deployment/$service ENABLE_JWT_COMPRESSION=true
done

echo ""
echo "✅ JWT Compression enabled for all services"
echo ""
echo "Pods will automatically restart to apply the changes."
echo "You can monitor the rollout with:"
echo "  kubectl rollout status deployment/<service-name>"
echo ""
echo "=========================================="
echo "Complete! ✅"
echo "=========================================="
