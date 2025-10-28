# Troubleshooting Guide

Common issues and solutions for Homelab v2.

## kubectl Connection Issues

### Error: "connection refused" from Mac

**Symptom:**
```bash
kubectl get nodes
# Error: Unable to connect to the server: dial tcp <ip>:6443: connect: connection refused
```

**Causes:**
1. Port forwarding script not running on Windows
2. Wrong server IP in kubeconfig
3. API server not bound to 0.0.0.0

**Solutions:**

**Check port forwarding (Windows):**
```powershell
# Verify script is running
Get-Process -Name powershell | Where-Object { $_.CommandLine -like "*wsl-port-forward*" }

# Restart script
C:\Scripts\wsl-port-forward.ps1
```

**Check server IP in kubeconfig (Mac):**
```bash
# View current server
kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'

# Should be: https://<windows-ip>:6443
# NOT: https://127.0.0.1:6443 or https://localhost:6443

# Update if wrong
kubectl config set-cluster homelab --server=https://<windows-ip>:6443
```

**Verify API binding (WSL2):**
```bash
# Check kind API server binding
docker exec homelab-control-plane netstat -tlnp | grep 6443

# Should show: 0.0.0.0:6443
# If shows 127.0.0.1:6443, recreate cluster with correct kind-config.yaml
```

### Error: "certificate signed by unknown authority"

**Symptom:**
```bash
kubectl get nodes
# Unable to connect to the server: x509: certificate signed by unknown authority
```

**Cause:**
kubeconfig references incorrect CA certificate or cluster endpoint

**Solutions:**

**Re-export kubeconfig (WSL2 → Mac):**
```bash
# On WSL2
kubectl config view --raw > ~/kubeconfig-fresh

# On Mac
scp jon@<windows-ip>:~/kubeconfig-fresh ~/.kube/homelab-config
export KUBECONFIG=~/.kube/homelab-config

# Update server IP
kubectl config set-cluster homelab --server=https://<windows-ip>:6443
```

**Skip TLS verification (temporary debugging only):**
```bash
kubectl get nodes --insecure-skip-tls-verify
```

## Certificate Issues

### Certificates not being issued

**Symptom:**
```bash
kubectl get certificate -A
# NAME              READY   SECRET            AGE
# dashboard-tls     False   dashboard-tls     5m
```

**Diagnosis:**
```bash
# Check certificate details
kubectl describe certificate dashboard-tls -n kubernetes-dashboard

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager --tail=50
```

**Common Causes:**

**1. ClusterIssuer not ready**
```bash
# Check issuers
kubectl get clusterissuer
# All should show READY=True

# If not ready, check events
kubectl describe clusterissuer homelab-issuer
```

**2. Wrong issuer name in annotation**
```yaml
# Check ingress annotation
kubectl get ingress dashboard -n kubernetes-dashboard -o yaml | grep issuer

# Should be: cert-manager.io/cluster-issuer: homelab-issuer
# NOT: cert-manager.io/issuer: homelab-issuer (different resource type)
```

**3. cert-manager not running**
```bash
# Check cert-manager pods
kubectl get pods -n cert-manager

# Should have 3 pods: cert-manager, cainjector, webhook (all Running)

# If not, reinstall
kubectl delete namespace cert-manager
./scripts/02-deploy-all.sh
```

**Solutions:**

**Recreate certificate:**
```bash
# Delete and reapply
kubectl delete certificate dashboard-tls -n kubernetes-dashboard
kubectl apply -f manifests/03-kubernetes-dashboard/ingress.yaml

# Watch status
kubectl get certificate -n kubernetes-dashboard -w
```

**Check certificate chain:**
```bash
# Verify secrets exist
kubectl get secret -n cert-manager root-ca-secret
kubectl get secret -n cert-manager intermediate-ca-secret

# If missing, reapply PKI manifests
kubectl apply -f manifests/01-cert-manager/
```

### Browser shows certificate warnings

**Symptom:**
Browser shows "Your connection is not private" or "Certificate error"

**Causes:**
1. Root CA not trusted on client machine
2. Certificate not issued yet
3. Wrong hostname in browser

**Solutions:**

**Check certificate status:**
```bash
kubectl get certificate -n kubernetes-dashboard
# Should show READY=True
```

**Verify root CA is trusted (Mac):**
```bash
security find-certificate -c "Homelab Root CA" -p /Library/Keychains/System.keychain

# If not found, install:
# 1. Copy homelab-root-ca.crt from WSL2
# 2. Open Keychain Access
# 3. Import to System keychain
# 4. Set to "Always Trust"
```

**Verify root CA is trusted (Windows):**
```powershell
Get-ChildItem -Path Cert:\LocalMachine\Root | Where-Object { $_.Subject -like "*Homelab Root CA*" }

# If not found, install:
Import-Certificate -FilePath "homelab-root-ca.crt" -CertStoreLocation Cert:\LocalMachine\Root
```

**Check hostname:**
```bash
# Must match ingress host exactly
# Browser: https://dashboard.homelab.local
# NOT: https://dashboard.homelab.local/ (trailing slash OK)
# NOT: https://192.168.1.100 (IP address)
# NOT: https://dashboard (missing domain)
```

**Test certificate chain:**
```bash
# From Mac
openssl s_client -connect <windows-ip>:443 -servername dashboard.homelab.local < /dev/null

# Look for:
# - "Verify return code: 0 (ok)"
# - Certificate chain showing Root → Intermediate → Service
```

## Pod Issues

### Pods stuck in "Pending"

**Symptom:**
```bash
kubectl get pods -A
# NAME                    READY   STATUS    RESTARTS   AGE
# my-pod-12345-abcde      0/1     Pending   0          2m
```

**Diagnosis:**
```bash
# Check why pending
kubectl describe pod <pod-name> -n <namespace>

# Look at "Events" section for errors
```

**Common Causes:**

**1. No nodes available**
```bash
kubectl get nodes
# All nodes should be "Ready"

# If NotReady, check:
docker ps | grep kind
# All containers should be "Up"
```

**2. Resource constraints**
```bash
# Check node resources
kubectl top nodes

# If limits exceeded, reduce pod resources or add nodes
```

**3. PVC not bound**
```bash
kubectl get pvc -A
# All should be "Bound"

# If pending, check storage class
kubectl get storageclass
```

**Solutions:**

**Restart node:**
```bash
docker restart homelab-control-plane
# Wait for node to be Ready
kubectl get nodes -w
```

**Delete and recreate pod:**
```bash
kubectl delete pod <pod-name> -n <namespace>
# Deployment/ReplicaSet will recreate it
```

### Pods stuck in "CrashLoopBackOff"

**Symptom:**
```bash
kubectl get pods -A
# NAME                    READY   STATUS             RESTARTS   AGE
# my-pod-12345-abcde      0/1     CrashLoopBackOff   5          10m
```

**Diagnosis:**
```bash
# Check logs
kubectl logs <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous  # Previous crash

# Check events
kubectl describe pod <pod-name> -n <namespace>
```

**Common Causes:**
1. Application error (check logs)
2. Missing dependencies (ConfigMap, Secret)
3. Resource limits too low
4. Image pull error

**Solutions:**

**Check application logs:**
```bash
kubectl logs <pod-name> -n <namespace> --tail=100
```

**Check dependencies:**
```bash
# ConfigMaps
kubectl get configmap -n <namespace>

# Secrets
kubectl get secret -n <namespace>
```

**Increase resources:**
```yaml
# Edit deployment
kubectl edit deployment <name> -n <namespace>

# Increase resources:
resources:
  requests:
    memory: "256Mi"
    cpu: "500m"
  limits:
    memory: "512Mi"
    cpu: "1000m"
```

### Pods stuck in "ImagePullBackOff"

**Symptom:**
```bash
kubectl get pods -A
# NAME                    READY   STATUS             RESTARTS   AGE
# my-pod-12345-abcde      0/1     ImagePullBackOff   0          5m
```

**Diagnosis:**
```bash
kubectl describe pod <pod-name> -n <namespace>
# Look for "Failed to pull image" in Events
```

**Common Causes:**
1. Image doesn't exist
2. Typo in image name
3. Private registry requires authentication

**Solutions:**

**Check image name:**
```bash
# Verify image exists
docker pull <image-name>

# If private registry, create secret
kubectl create secret docker-registry regcred \
  --docker-server=<registry> \
  --docker-username=<user> \
  --docker-password=<pass> \
  -n <namespace>

# Reference in pod spec
imagePullSecrets:
  - name: regcred
```

## Ingress Issues

### Ingress not routing traffic

**Symptom:**
Browser shows "404 Not Found" or "503 Service Temporarily Unavailable"

**Diagnosis:**
```bash
# Check ingress
kubectl get ingress -A
kubectl describe ingress <name> -n <namespace>

# Check nginx-ingress logs
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller --tail=50
```

**Common Causes:**

**1. nginx-ingress not running**
```bash
kubectl get pods -n ingress-nginx
# Should show controller pod Running

# If not, reinstall
kubectl apply -f manifests/02-ingress-nginx/controller.yaml
```

**2. Wrong host in ingress**
```yaml
# Browser uses: dashboard.homelab.local
# Ingress must match exactly:
spec:
  rules:
    - host: dashboard.homelab.local  # Must match browser
```

**3. Service not found**
```bash
# Check backend service exists
kubectl get service -n <namespace>

# Must match ingress backend:
spec:
  rules:
    - http:
        paths:
          - backend:
              service:
                name: kubernetes-dashboard  # Must exist
                port:
                  number: 443
```

**Solutions:**

**Test ingress directly:**
```bash
# Get nginx-ingress pod
INGRESS_POD=$(kubectl get pods -n ingress-nginx -o name | grep controller)

# Test routing
kubectl exec -n ingress-nginx $INGRESS_POD -- curl -H "Host: dashboard.homelab.local" http://localhost
```

**Check /etc/hosts (Mac):**
```bash
cat /etc/hosts | grep homelab
# Should have: <windows-ip>  dashboard.homelab.local

# If missing:
sudo bash -c 'echo "<windows-ip>  dashboard.homelab.local" >> /etc/hosts'
```

## Network Issues

### Can't access services from Mac

**Symptom:**
```bash
curl https://dashboard.homelab.local
# curl: (7) Failed to connect to dashboard.homelab.local port 443: Connection refused
```

**Diagnosis Flow:**
```bash
# 1. Check /etc/hosts
cat /etc/hosts | grep dashboard.homelab.local

# 2. Check Windows reachable
ping <windows-ip>

# 3. Check port open on Windows
nc -zv <windows-ip> 443

# 4. Check WSL2 reachable from Windows
# On Windows PowerShell:
Test-NetConnection -ComputerName $(wsl hostname -I).Trim() -Port 443
```

**Solutions:**

**Check port forwarding (Windows):**
```powershell
# Verify forwarding rules
netsh interface portproxy show all

# Should show: 0.0.0.0:443 → <wsl-ip>:443

# If missing, restart script
C:\Scripts\wsl-port-forward.ps1
```

**Check Windows firewall:**
```powershell
# Allow ports
New-NetFirewallRule -DisplayName "WSL2 HTTPS" -Direction Inbound -LocalPort 443 -Protocol TCP -Action Allow
New-NetFirewallRule -DisplayName "WSL2 HTTP" -Direction Inbound -LocalPort 80 -Protocol TCP -Action Allow
New-NetFirewallRule -DisplayName "WSL2 K8s API" -Direction Inbound -LocalPort 6443 -Protocol TCP -Action Allow
```

## cert-manager Issues

### cert-manager pods not starting

**Symptom:**
```bash
kubectl get pods -n cert-manager
# No pods or pods in CrashLoopBackOff
```

**Solutions:**

**Reinstall cert-manager:**
```bash
# Delete namespace
kubectl delete namespace cert-manager

# Wait for deletion
kubectl get namespace cert-manager
# Should return: not found

# Reinstall
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.yaml

# Wait for ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s
```

### ClusterIssuer not ready

**Symptom:**
```bash
kubectl get clusterissuer
# NAME              READY   AGE
# homelab-issuer    False   5m
```

**Diagnosis:**
```bash
kubectl describe clusterissuer homelab-issuer
# Check "Events" and "Status" for errors
```

**Common Causes:**
1. Referenced secret doesn't exist
2. Invalid CA certificate in secret
3. cert-manager not ready

**Solutions:**

**Check secrets:**
```bash
kubectl get secret -n cert-manager intermediate-ca-secret
# Should exist

# If missing, reapply PKI manifests
kubectl apply -f manifests/01-cert-manager/
```

**Recreate issuer:**
```bash
kubectl delete clusterissuer homelab-issuer
kubectl apply -f manifests/01-cert-manager/03-cluster-issuer.yaml
```

## Cluster Issues

### Cluster won't start

**Symptom:**
```bash
kind create cluster --config kind-config.yaml
# Error: failed to create cluster: ...
```

**Solutions:**

**Check Docker:**
```bash
docker ps
# Should work without sudo

# If permission error:
sudo usermod -aG docker $USER
newgrp docker
```

**Delete old cluster:**
```bash
kind delete cluster --name homelab
kind create cluster --config kind-config.yaml
```

**Check disk space:**
```bash
df -h
# Ensure sufficient space in /var/lib/docker
```

## Getting Help

**Check logs:**
```bash
# cert-manager
kubectl logs -n cert-manager deployment/cert-manager

# nginx-ingress
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller

# Dashboard
kubectl logs -n kubernetes-dashboard deployment/kubernetes-dashboard

# All events
kubectl get events -A --sort-by='.lastTimestamp'
```

**Describe resources:**
```bash
kubectl describe pod <name> -n <namespace>
kubectl describe certificate <name> -n <namespace>
kubectl describe ingress <name> -n <namespace>
kubectl describe clusterissuer <name>
```

**Export for debugging:**
```bash
# Export cluster state
kubectl get all -A -o yaml > cluster-state.yaml

# Export certificates
kubectl get certificate -A -o yaml > certificates.yaml

# Export ingress
kubectl get ingress -A -o yaml > ingress.yaml
```

## Emergency Recovery

**Nuclear option - Full rebuild:**
```bash
# Backup first
./scripts/backup-cluster.sh

# Destroy everything
./scripts/destroy-cluster.sh

# Rebuild
./scripts/01-setup-cluster.sh
./scripts/02-deploy-all.sh

# Restore applications
kubectl apply -f ~/k8s-backups/backup-YYYYMMDD-HHMMSS/
```

## Still Stuck?

Check the following documentation:
- [Architecture](architecture.md) - Understanding how components interact
- [Setup Guide](setup.md) - Detailed installation steps
- [Port Forwarding](port-forwarding.md) - Windows networking configuration

Review project notes in basic-memory for additional context and architectural decisions.