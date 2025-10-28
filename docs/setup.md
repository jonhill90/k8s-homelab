# Setup Guide

Complete step-by-step installation guide for Homelab v2.

## Prerequisites

### Windows Host

**Required:**
- Windows 10/11 with WSL2 enabled
- Port forwarding script running (see [Port Forwarding](port-forwarding.md))
- Administrator access

**Validation:**
```powershell
wsl --list --verbose  # Should show WSL2 distributions
```

### WSL2 (hill-arch)

**Required Tools:**
```bash
# Verify installations
docker --version        # Docker Engine
kind --version          # kind v0.20.0 or later
kubectl version --client # kubectl v1.28.0 or later
git --version           # Git 2.x
```

**Install Missing Tools:**
```bash
# Docker (if not installed)
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker

# kind
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
```

### Mac Workstation

**Required Tools:**
```bash
# Verify installations
kubectl version --client
k9s version
```

**Install Missing Tools:**
```bash
# Using Homebrew
brew install kubectl
brew install k9s
```

## Installation Steps

### Step 1: Clone Repository (WSL2)

```bash
# Navigate to repositories directory
cd ~/source/repos/Personal

# Clone repository (if not already cloned)
git clone https://github.com/<your-username>/k8s-homelab.git
cd k8s-homelab

# Verify structure
ls -la
```

### Step 2: Create Cluster (WSL2)

```bash
# Run cluster setup script
./scripts/01-setup-cluster.sh

# Expected output:
# - Deleting existing cluster (if any)
# - Creating new cluster with kind-config.yaml
# - Cluster "homelab" created
# - 3 nodes Ready
```

**Validation:**
```bash
# Check cluster
kubectl get nodes
# Should show 3 nodes: 1 control-plane, 2 workers (all Ready)

# Check API binding
docker exec homelab-control-plane netstat -tlnp | grep 6443
# Should show 0.0.0.0:6443 (NOT 127.0.0.1:6443)
```

### Step 3: Deploy Services (WSL2)

```bash
# Run deployment script
./scripts/02-deploy-all.sh

# Expected duration: ~5 minutes
# Script will:
# 1. Create namespaces
# 2. Install cert-manager
# 3. Configure three-tier PKI
# 4. Install nginx-ingress
# 5. Deploy Kubernetes Dashboard
# 6. Deploy whoami test app
```

**Validation:**
```bash
# Check all pods
kubectl get pods -A
# All pods should be Running

# Check certificates
kubectl get certificate -A
# All should show READY=True

# Check ingress
kubectl get ingress -A
# Should show dashboard.homelab.local and whoami.homelab.local
```

### Step 4: Export Root CA (WSL2)

```bash
# Export root CA certificate
./scripts/03-export-root-ca.sh

# Creates file: homelab-root-ca.crt
# This certificate must be trusted on Mac and Windows
```

### Step 5: Export kubeconfig (WSL2 → Mac)

```bash
# On WSL2: Copy kubeconfig
cp ~/.kube/config ~/kubeconfig-homelab

# On Mac: Download kubeconfig
scp jon@<windows-ip>:~/kubeconfig-homelab ~/.kube/homelab-config

# Or use Windows file sharing
# \\wsl$\hill-arch\home\jon\kubeconfig-homelab
```

### Step 6: Configure kubeconfig (Mac)

```bash
# Edit kubeconfig to use Windows IP
vi ~/.kube/homelab-config

# Find "server:" line and update to:
# server: https://<windows-ip>:6443

# Set as current context
export KUBECONFIG=~/.kube/homelab-config

# Or merge into main kubeconfig
kubectl config view --flatten > ~/.kube/config-backup
KUBECONFIG=~/.kube/config:~/.kube/homelab-config kubectl config view --flatten > ~/.kube/config-merged
mv ~/.kube/config-merged ~/.kube/config
```

**Validation:**
```bash
# Test connection from Mac
kubectl get nodes
# Should show 3 nodes

kubectl get pods -A
# Should show all pods
```

### Step 7: Trust Root CA (Mac)

```bash
# Copy root CA from WSL2 to Mac
scp jon@<windows-ip>:~/homelab-root-ca.crt ~/Downloads/

# Open Keychain Access
open /System/Applications/Utilities/Keychain\ Access.app

# Steps:
# 1. File → Import Items
# 2. Select homelab-root-ca.crt
# 3. Choose "System" keychain
# 4. Double-click "Homelab Root CA"
# 5. Expand "Trust"
# 6. Set "When using this certificate" to "Always Trust"
# 7. Close and enter password
```

**Validation:**
```bash
# Check certificate trust
security find-certificate -c "Homelab Root CA" -p /Library/Keychains/System.keychain
# Should display certificate
```

### Step 8: Trust Root CA (Windows)

```powershell
# Run as Administrator

# Copy certificate from WSL2
wsl cat /home/jon/homelab-root-ca.crt > $env:USERPROFILE\Downloads\homelab-root-ca.crt

# Import to Trusted Root Certification Authorities
Import-Certificate -FilePath "$env:USERPROFILE\Downloads\homelab-root-ca.crt" -CertStoreLocation Cert:\LocalMachine\Root

# Verify
Get-ChildItem -Path Cert:\LocalMachine\Root | Where-Object { $_.Subject -like "*Homelab Root CA*" }
```

### Step 9: Configure DNS (Mac)

```bash
# Edit hosts file
sudo vi /etc/hosts

# Add entries (replace <windows-ip> with your Windows IP)
<windows-ip>  dashboard.homelab.local
<windows-ip>  whoami.homelab.local
```

**Find Windows IP:**
```powershell
# On Windows
ipconfig | findstr IPv4
```

### Step 10: Verify Everything (Mac)

```bash
# Test kubectl
kubectl get nodes
kubectl get pods -A
k9s  # Interactive cluster management

# Test browser access
# Open: https://dashboard.homelab.local
# Expected: Green lock, no certificate warnings

# Open: https://whoami.homelab.local
# Expected: Green lock, shows request information
```

## Post-Installation

### Dashboard Access

**Get Token:**
```bash
# On Mac (with kubeconfig configured)
kubectl -n kubernetes-dashboard create token admin-user

# Or create service account
kubectl -n kubernetes-dashboard create serviceaccount admin-user
kubectl -n kubernetes-dashboard create clusterrolebinding admin-user \
  --clusterrole=cluster-admin \
  --serviceaccount=kubernetes-dashboard:admin-user
kubectl -n kubernetes-dashboard create token admin-user --duration=24h
```

**Login:**
1. Open https://dashboard.homelab.local
2. Choose "Token" authentication
3. Paste token
4. Click "Sign In"

### Backup Configuration

```bash
# On WSL2
./scripts/backup-cluster.sh

# Creates timestamped backup
# Location: ~/k8s-backups/backup-YYYYMMDD-HHMMSS/
```

### Add New Service

```bash
# Create manifest with cert-manager annotation
cat << 'EOF' > manifests/06-myservice/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myservice
  namespace: myservice
  annotations:
    cert-manager.io/cluster-issuer: homelab-issuer
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - myservice.homelab.local
      secretName: myservice-tls
  rules:
    - host: myservice.homelab.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: myservice
                port:
                  number: 80
EOF

# Apply manifest
kubectl apply -f manifests/06-myservice/

# Wait for certificate
kubectl get certificate -n myservice -w

# Add to /etc/hosts on Mac
sudo bash -c 'echo "<windows-ip>  myservice.homelab.local" >> /etc/hosts'

# Access service
curl https://myservice.homelab.local
```

## Updating the Cluster

### Update Manifests

```bash
# On Mac or WSL2
cd k8s-homelab
git pull

# On WSL2
kubectl apply -f manifests/
```

### Update cert-manager

```bash
# Check current version
kubectl get deployment -n cert-manager cert-manager -o jsonpath='{.spec.template.spec.containers[0].image}'

# Update version in script
vi scripts/02-deploy-all.sh

# Redeploy
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.yaml
```

### Recreate Cluster

```bash
# Backup first
./scripts/backup-cluster.sh

# Destroy and recreate
./scripts/destroy-cluster.sh
./scripts/01-setup-cluster.sh
./scripts/02-deploy-all.sh

# Restore applications (manual)
kubectl apply -f ~/k8s-backups/backup-YYYYMMDD-HHMMSS/
```

## Troubleshooting

If you encounter issues, see [Troubleshooting Guide](troubleshooting.md).

**Common Issues:**
- kubectl connection refused → Check port forwarding script
- Certificate not trusted → Verify root CA installed correctly
- Pods not starting → Check `kubectl describe pod <name>`
- Ingress not working → Check nginx-ingress logs

## Next Steps

1. Explore cluster with k9s
2. Deploy additional services
3. Set up monitoring (Prometheus/Grafana)
4. Configure automated backups
5. Add DNS server (AdGuard Home)

## Quick Reference

**Cluster Management:**
```bash
./scripts/01-setup-cluster.sh   # Create cluster
./scripts/02-deploy-all.sh      # Deploy services
./scripts/backup-cluster.sh     # Backup cluster
./scripts/destroy-cluster.sh    # Delete cluster
```

**Useful Commands:**
```bash
kubectl get nodes               # Cluster nodes
kubectl get pods -A             # All pods
kubectl get certificate -A      # All certificates
kubectl get ingress -A          # All ingress rules
kubectl logs -n cert-manager deployment/cert-manager  # cert-manager logs
```

**Service URLs:**
- Dashboard: https://dashboard.homelab.local
- whoami: https://whoami.homelab.local

**Documentation:**
- [Architecture](architecture.md)
- [Troubleshooting](troubleshooting.md)
- [Port Forwarding](port-forwarding.md)