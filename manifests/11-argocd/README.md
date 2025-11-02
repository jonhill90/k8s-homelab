# ArgoCD GitOps Deployment

**Status**: ✅ Deployed and Operational
**Access**: https://argocd.homelab.local
**Repository**: https://github.com/jonhill90/k8s-homelab

## Overview

ArgoCD provides **declarative GitOps continuous delivery** for the homelab cluster. It monitors the Git repository and automatically synchronizes cluster state to match the manifests in Git.

## Deployment Method

**Helm Chart Installation** (not plain manifests):

```bash
# Add Helm repository
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# Install ArgoCD with custom values
helm install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --version 9.0.5 \
  --values manifests/11-argocd/values.yaml

# Apply custom ingress (cert-manager integration)
kubectl apply -f manifests/11-argocd/ingress.yaml

# Wait for certificate
kubectl wait --for=condition=ready certificate argocd-tls -n argocd --timeout=120s
```

**Why Helm instead of manifests?**
- ArgoCD is a complex multi-component application (8+ services)
- Official Helm chart is well-maintained and frequently updated
- Helm provides easy upgrades and rollbacks
- Industry-standard deployment method for ArgoCD

## Files in This Directory

```
manifests/11-argocd/
├── README.md           # This file
├── values.yaml         # Helm chart values (resource limits, config)
├── ingress.yaml        # Custom ingress with cert-manager TLS
└── applications/       # ArgoCD Application manifests
    ├── whoami-app.yaml     # whoami test application
    └── postgres-app.yaml   # PostgreSQL database
```

## Initial Setup

### 1. Get Admin Password

```bash
# Retrieve initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

**Credentials** (stored in Obsidian project note, NOT in Git):
- Username: `admin`
- Password: `q5uGw7Ofv1E0r81r` (initial - should be changed)

### 2. Access Web UI

**URL**: https://argocd.homelab.local

Verify:
- ✅ Green lock (trusted TLS certificate from cert-manager)
- ✅ Login with admin credentials
- ✅ Empty dashboard (no applications yet)

### 3. Install ArgoCD CLI (Optional)

```bash
# macOS
brew install argocd

# Login via CLI
argocd login argocd.homelab.local
# Username: admin
# Password: <from step 1>
```

### 4. Connect Git Repository

**Already configured**: `https://github.com/jonhill90/k8s-homelab`

Via CLI:
```bash
argocd repo add https://github.com/jonhill90/k8s-homelab \
  --type git \
  --name k8s-homelab
```

Via UI:
1. Settings → Repositories → Connect Repo
2. Repository URL: `https://github.com/jonhill90/k8s-homelab`
3. Type: Git
4. Project: default

## Managing Applications

### Current Applications

**whoami** - Test application (manifests/04-whoami/)
- Status: Synced + Healthy
- Auto-sync: ✅ Enabled
- Self-heal: ✅ Enabled
- Prune: ✅ Enabled

**postgres** - Shared PostgreSQL database (manifests/12-database/)
- Status: Synced + Healthy
- Auto-sync: ✅ Enabled
- Self-heal: ✅ Enabled
- Prune: ✅ Enabled

### Create New Application

**Method 1: Application Manifest (Recommended)**

Create `manifests/11-argocd/applications/myapp-app.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/jonhill90/k8s-homelab
    targetRevision: HEAD
    path: manifests/XX-myapp  # Path to manifests in repo
  destination:
    server: https://kubernetes.default.svc
    namespace: myapp  # Target namespace
  syncPolicy:
    automated:
      prune: true      # Delete resources not in Git
      selfHeal: true   # Revert manual changes
    syncOptions:
    - CreateNamespace=true  # Auto-create namespace if missing
```

Apply:
```bash
kubectl apply -f manifests/11-argocd/applications/myapp-app.yaml
```

**Method 2: ArgoCD CLI**

```bash
argocd app create myapp \
  --repo https://github.com/jonhill90/k8s-homelab \
  --path manifests/XX-myapp \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace myapp \
  --sync-policy automated \
  --auto-prune \
  --self-heal
```

**Method 3: Web UI**

1. Applications → New App
2. Application Name: `myapp`
3. Project: `default`
4. Repository URL: `https://github.com/jonhill90/k8s-homelab`
5. Path: `manifests/XX-myapp`
6. Cluster: `https://kubernetes.default.svc`
7. Namespace: `myapp`
8. Sync Policy: `Automatic`
9. Enable: Prune, Self-Heal

## GitOps Workflow

### Automated Deployment (Auto-Sync Enabled)

```
1. Edit manifests locally
2. Git commit + push
3. ArgoCD detects change (polls every 3 minutes)
4. ArgoCD syncs cluster to match Git
5. Application becomes "Synced + Healthy"
```

**No manual kubectl apply needed!**

### Manual Deployment (Auto-Sync Disabled)

```
1. Edit manifests locally
2. Git commit + push
3. ArgoCD detects change → Shows "OutOfSync"
4. Manually sync via UI or CLI:
   argocd app sync myapp
5. Application becomes "Synced + Healthy"
```

### Drift Detection & Self-Heal

**Test drift detection:**
```bash
# Manually scale deployment (creates drift)
kubectl scale deployment whoami --replicas=10 -n default

# ArgoCD detects OutOfSync state
argocd app get whoami
# Status: OutOfSync (cluster has 10 replicas, Git has 4)

# With self-heal enabled, ArgoCD auto-reverts to Git state within 5 seconds
# Without self-heal, manual sync required:
argocd app sync whoami
```

## Common Operations

### Check Application Status

```bash
# List all applications
argocd app list

# Get detailed status
argocd app get whoami

# View sync history
argocd app history whoami
```

### Manual Sync

```bash
# Sync specific application
argocd app sync whoami

# Sync with prune (delete extra resources)
argocd app sync whoami --prune

# Dry-run (preview changes without applying)
argocd app sync whoami --dry-run
```

### View Application Details

```bash
# Show application manifest diff
argocd app diff whoami

# View application resources
argocd app resources whoami

# View application logs
argocd app logs whoami
```

### Rollback

```bash
# List sync history
argocd app history whoami

# Rollback to previous revision
argocd app rollback whoami <revision-id>
```

## Sync Policies

### Auto-Sync (Enabled by Default)

```yaml
syncPolicy:
  automated:
    prune: true      # Delete resources removed from Git
    selfHeal: true   # Revert manual kubectl changes
```

**Behavior**:
- ✅ Git changes auto-deployed within 3 minutes
- ✅ Manual changes auto-reverted within 5 seconds
- ✅ Deleted manifests = deleted resources

**Best for**: Production-ready apps, stable infrastructure

### Manual Sync (Alternative)

```yaml
syncPolicy: {}  # No automated sync
```

**Behavior**:
- ⏸️ Git changes detected but NOT auto-deployed
- ⏸️ Manual sync required via CLI/UI
- ✅ Full control over when changes apply

**Best for**: Testing, learning, unstable apps

## Monitoring ArgoCD

### Health Check

```bash
# Check ArgoCD pods
kubectl get pods -n argocd

# Expected: 7 pods Running
# - argocd-application-controller-0 (StatefulSet)
# - argocd-applicationset-controller
# - argocd-dex-server
# - argocd-notifications-controller
# - argocd-redis
# - argocd-repo-server
# - argocd-server
```

### Prometheus Metrics

ArgoCD exposes Prometheus metrics on port 8082 (application-controller).

**Available metrics**:
- `argocd_app_sync_status` - Application sync state
- `argocd_app_health_status` - Application health
- `argocd_git_request_total` - Git operation counts
- `argocd_kubectl_exec_total` - kubectl operations

**Already scraped by Prometheus** (see `manifests/08-monitoring/prometheus-deployment.yaml`)

### Grafana Dashboard

**Pre-installed dashboard**: ArgoCD (UID: qPkgGHg7k)

Access: https://grafana.homelab.local/d/qPkgGHg7k/argocd

Shows:
- Application sync status
- Git operations
- kubectl exec counts
- Sync history

## Upgrading ArgoCD

```bash
# Update Helm repo
helm repo update

# Check available versions
helm search repo argo/argo-cd --versions

# Upgrade to new version
helm upgrade argocd argo/argo-cd \
  --namespace argocd \
  --version <new-version> \
  --values manifests/11-argocd/values.yaml

# Verify upgrade
helm status argocd -n argocd
kubectl get pods -n argocd
```

## Troubleshooting

### Application Stuck in "Progressing"

```bash
# View sync status
argocd app get <app-name>

# Check events
kubectl get events -n <namespace>

# View ArgoCD logs
kubectl logs -n argocd deployment/argocd-application-controller
```

### "OutOfSync" Status Won't Clear

```bash
# Hard refresh (re-fetch Git state)
argocd app get <app-name> --hard-refresh

# Force sync (ignore hooks and errors)
argocd app sync <app-name> --force
```

### Certificate Issues

```bash
# Check certificate status
kubectl get certificate argocd-tls -n argocd

# If not ready, check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager
```

### Can't Access UI

```bash
# Check ingress
kubectl get ingress -n argocd

# Check nginx-ingress logs
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller

# Verify /etc/hosts entry on Mac
grep argocd /etc/hosts
# Expected: 192.168.68.100  argocd.homelab.local
```

## Security Best Practices

### Change Admin Password

```bash
# Login via CLI
argocd login argocd.homelab.local

# Update password
argocd account update-password
# Enter current password
# Enter new password (store in Obsidian, NOT Git)
```

### Delete Initial Secret

```bash
# After changing password, delete initial secret
kubectl -n argocd delete secret argocd-initial-admin-secret
```

### Create Additional Users

Edit `argocd-cm` ConfigMap to add users (future enhancement).

### Enable Audit Logging

Set `server.audit.enabled=true` in values.yaml (future enhancement).

## References

- **ArgoCD Docs**: https://argo-cd.readthedocs.io/en/stable/
- **Helm Chart**: https://github.com/argoproj/argo-helm/tree/main/charts/argo-cd
- **Getting Started**: https://argo-cd.readthedocs.io/en/stable/getting_started/
- **Best Practices**: https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/

## Status

**Deployed**: 2025-11-01
**Version**: argo-cd-9.0.5 (app v3.1.9)
**Applications Managed**: 2 (whoami, postgres)
**Auto-Sync**: ✅ Enabled
**Monitoring**: ✅ Prometheus + Grafana
**Next**: Add more applications to ArgoCD management
