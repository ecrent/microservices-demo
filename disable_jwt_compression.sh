#!/bin/bash

# Script to disable JWT compression across all microservices
# This sets ENABLE_JWT_COMPRESSION=false and restarts the pods

set -e

echo "=========================================="
echo "Disabling JWT Compression"
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

echo "Setting ENABLE_JWT_COMPRESSION=false for all services..."
echo ""

for service in "${SERVICES[@]}"; do
    echo "📝 Setting $service..."
    kubectl set env deployment/$service ENABLE_JWT_COMPRESSION=false
done

echo ""
echo "✅ JWT Compression disabled for all services"
echo ""
echo "Pods will automatically restart to apply the changes."
echo "You can monitor the rollout with:"
echo "  kubectl rollout status deployment/<service-name>"
echo ""
echo "=========================================="
echo "Complete! ✅"
echo "=========================================="
