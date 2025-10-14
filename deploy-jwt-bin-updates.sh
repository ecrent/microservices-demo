#!/bin/bash
set -e

echo "========================================="
echo "Deploying JWT -bin Header Updates"
echo "========================================="
echo ""

# Set minikube docker env
echo "[1/6] Setting Minikube Docker environment..."
eval $(minikube docker-env)

# Build frontend
echo "[2/6] Building frontend..."
cd /workspaces/microservices-demo
docker build -t frontend:latest ./src/frontend

# Build checkoutservice
echo "[3/6] Building checkoutservice..."
docker build -t checkoutservice:latest ./src/checkoutservice

# Build shippingservice
echo "[4/6] Building shippingservice..."
docker build -t shippingservice:latest ./src/shippingservice

# Build paymentservice
echo "[5/6] Building paymentservice..."
docker build -t paymentservice:latest ./src/paymentservice

# Restart deployments
echo "[6/6] Restarting Kubernetes deployments..."
kubectl set image deployment/frontend server=frontend:latest
kubectl set image deployment/checkoutservice server=checkoutservice:latest
kubectl set image deployment/shippingservice server=shippingservice:latest
kubectl set image deployment/paymentservice server=paymentservice:latest

echo ""
echo "Waiting for rollouts to complete..."
kubectl rollout status deployment/frontend
kubectl rollout status deployment/checkoutservice
kubectl rollout status deployment/shippingservice
kubectl rollout status deployment/paymentservice

echo ""
echo "========================================="
echo "✅ JWT -bin Header Updates Deployed!"
echo "========================================="
echo ""
echo "Summary of changes:"
echo "  - Frontend: Sends dynamic/sig as -bin headers (base64 encoded)"
echo "  - Checkoutservice: Decodes -bin headers, forwards to backends"
echo "  - Shippingservice: Decodes -bin headers from checkoutservice"
echo "  - Paymentservice: Decodes -bin headers from checkoutservice"
echo ""
echo "These changes prevent HPACK indexing of dynamic JWT components"
echo "while allowing static/session components to be cached efficiently."
echo ""
