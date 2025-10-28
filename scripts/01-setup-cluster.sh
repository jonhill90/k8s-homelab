#!/bin/bash
set -e

echo "================================================"
echo "Homelab v2 - Cluster Setup"
echo "================================================"

# Delete existing cluster if it exists
if kind get clusters | grep -q homelab; then
    echo "Deleting existing cluster..."
    kind delete cluster --name homelab
fi

# Create new cluster
echo "Creating cluster with kind-config.yaml..."
kind create cluster --config kind-config.yaml

# Wait for cluster to be ready
echo "Waiting for cluster to be ready..."
kubectl wait --for=condition=ready node --all --timeout=300s

# Verify API server binding
echo ""
echo "Verifying API server binding..."
docker exec homelab-control-plane netstat -tlnp | grep 6443

if docker exec homelab-control-plane netstat -tlnp | grep 6443 | grep -q "0.0.0.0"; then
    echo "✅ API server correctly bound to 0.0.0.0:6443"
else
    echo "⚠️  WARNING: API server not bound to 0.0.0.0:6443"
    echo "This may prevent external access from Mac workstation"
fi

# Show cluster info
echo ""
echo "Cluster created successfully!"
kubectl get nodes

echo ""
echo "Next step: Run ./scripts/02-deploy-all.sh"
