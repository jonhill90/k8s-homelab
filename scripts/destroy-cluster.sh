#!/bin/bash
set -e

echo "================================================"
echo "Homelab v2 - Destroy Cluster"
echo "================================================"

echo ""
echo "⚠️  WARNING: This will permanently delete the homelab cluster!"
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

echo ""
read -p "Have you backed up the cluster? (yes/no): " backup_confirm

if [ "$backup_confirm" != "yes" ]; then
    echo ""
    echo "Please run ./scripts/backup-cluster.sh first!"
    echo "Aborted."
    exit 0
fi

echo ""
echo "Deleting cluster..."
kind delete cluster --name homelab

echo ""
echo "Pruning Docker resources..."
docker system prune -f

echo ""
echo "✅ Cluster destroyed successfully!"
echo ""
echo "To recreate the cluster:"
echo "1. ./scripts/01-setup-cluster.sh"
echo "2. ./scripts/02-deploy-all.sh"
