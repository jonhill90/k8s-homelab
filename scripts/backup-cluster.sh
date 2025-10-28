#!/bin/bash
set -e

echo "================================================"
echo "Homelab v2 - Backup Cluster"
echo "================================================"

BACKUP_DIR="$HOME/k8s-backups/backup-$(date +%Y%m%d-%H%M%S)"

echo "Creating backup directory: $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

echo ""
echo "Backing up cluster resources..."

# Export all resources by namespace
for ns in $(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'); do
    echo "  - Namespace: $ns"
    mkdir -p "$BACKUP_DIR/$ns"

    # Export all resources in namespace
    kubectl get all -n "$ns" -o yaml > "$BACKUP_DIR/$ns/all.yaml" 2>/dev/null || true

    # Export specific resources
    kubectl get configmap -n "$ns" -o yaml > "$BACKUP_DIR/$ns/configmaps.yaml" 2>/dev/null || true
    kubectl get secret -n "$ns" -o yaml > "$BACKUP_DIR/$ns/secrets.yaml" 2>/dev/null || true
    kubectl get ingress -n "$ns" -o yaml > "$BACKUP_DIR/$ns/ingress.yaml" 2>/dev/null || true
    kubectl get certificate -n "$ns" -o yaml > "$BACKUP_DIR/$ns/certificates.yaml" 2>/dev/null || true
done

# Export cluster-wide resources
echo ""
echo "Backing up cluster-wide resources..."
mkdir -p "$BACKUP_DIR/cluster"
kubectl get clusterissuer -o yaml > "$BACKUP_DIR/cluster/clusterissuers.yaml" 2>/dev/null || true
kubectl get clusterrole -o yaml > "$BACKUP_DIR/cluster/clusterroles.yaml" 2>/dev/null || true
kubectl get clusterrolebinding -o yaml > "$BACKUP_DIR/cluster/clusterrolebindings.yaml" 2>/dev/null || true
kubectl get storageclass -o yaml > "$BACKUP_DIR/cluster/storageclasses.yaml" 2>/dev/null || true

# Export kubeconfig
echo ""
echo "Backing up kubeconfig..."
cp ~/.kube/config "$BACKUP_DIR/kubeconfig.yaml"

# Create backup summary
echo ""
echo "Creating backup summary..."
cat > "$BACKUP_DIR/README.md" << EOF
# Homelab Cluster Backup
Date: $(date)
Cluster: homelab

## Contents
- Namespace resources exported by namespace
- Cluster-wide resources in cluster/
- kubeconfig.yaml

## Restore Instructions
\`\`\`bash
# Recreate cluster
./scripts/01-setup-cluster.sh

# Apply backed up resources
kubectl apply -f $BACKUP_DIR/

# Verify
kubectl get all -A
\`\`\`

## Notes
- PersistentVolume data is NOT backed up
- Secrets are backed up (handle securely)
- Some resources may need manual adjustment before restore
EOF

echo ""
echo "✅ Backup complete!"
echo "Location: $BACKUP_DIR"
echo ""
ls -lh "$BACKUP_DIR"
