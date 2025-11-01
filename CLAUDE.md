# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a **production-grade Kubernetes homelab** running on kind (Kubernetes in Docker) on WSL2 with kubectl access from Mac workstation. The repository contains Infrastructure as Code for a complete homelab with three-tier PKI, automated certificate management, and ingress routing.

**Critical Architecture Pattern:**
- **Execution Environment**: All cluster operations run on WSL2 (hill-arch)
- **Development Environment**: kubectl commands run from Mac workstation (no SSH required)
- **API Server Binding**: MUST be `0.0.0.0:6443` (NOT `127.0.0.1`) to enable external access
- **Network Path**: Mac → Windows (port forwarding) → WSL2 → kind cluster

## Project Context

This repository is managed as part of a larger personal knowledge management system in Obsidian. To understand the full context, decisions, and lessons learned, read these notes:

**Project Notes** (read these for comprehensive project context):
- `03-projects/03b-personal/project-personal-k8s-home-lab-2` - Main homelab v2 project with scope, tasks, timeline, lessons learned

**Research Notes** (read these for technical deep-dives):
- `202510280002` - Lab v2 Planning (migration from v1)
- `202510280006` - Lab v1 Cleanup (pre-deployment cleanup)
- `202510272229` - Proper Kubernetes Workflow (Mac workstation, no SSH)
- `202510272320` - Port Forwarding Script (Windows → WSL2)
- `202510252110` - Three-Tier PKI Architecture (Root → Intermediate → Service)
- `202510251938` - Production-Grade cert-manager (why this approach)
- `202510251924` - Industry Best Practices (on-premises certificates)
- `202510261303` - Visual PKI Guide (Mermaid diagrams, how it works)
- `202510242246` - K8s vs Docker Decision (why kind, not Docker Compose)
- `202510272142` - AdGuard vs Pi-hole (DNS solution comparison)
- `202511010247` - Portainer Deployment (hybrid Docker + K8s architecture)
- `202511010332` - AdGuard CoreDNS Integration (cluster-wide DNS)
- `202511010402` - Prometheus + Grafana Monitoring Stack (complete observability)

**Important**: Use the `mcp__basic-memory__read_note` tool to read these notes when you need context about why decisions were made, what was tried before, or what's planned next. Do not assume - read the actual notes.

## Current Cluster State

**Last Updated**: 2025-11-01 (3 days uptime)

**Cluster Health**: ✅ All systems operational
- **Nodes**: 3/3 Ready (1 control-plane, 2 workers)
- **Kubernetes Version**: v1.27.3
- **Total Pods**: 26 Running
- **Total Namespaces**: 12

**Deployed Services**:
- ✅ **Kubernetes Dashboard** - https://dashboard.homelab.local (cluster management UI)
- ✅ **Portainer** - https://portainer.homelab.local (Docker + K8s management, hybrid architecture)
- ✅ **AdGuard Home** - https://adguard.homelab.local (DNS + ad blocking, cluster-wide)
- ✅ **Prometheus** - https://prometheus.homelab.local (metrics collection & time-series database)
- ✅ **Grafana** - https://grafana.homelab.local (metrics visualization, admin/admin)
- ✅ **whoami** - https://whoami.homelab.local (test application)

**Infrastructure Components**:
- ✅ **cert-manager** - Three-tier PKI operational (8 certificates issued and ready)
- ✅ **nginx-ingress** - Running on control-plane, routing 6 ingress resources
- ✅ **CoreDNS** - Integrated with AdGuard (forwards to 10.96.126.140:53)
- ✅ **Portainer Agent** - K8s deployment with NodePort 30778
- ✅ **metrics-server** - Resource metrics for kubectl top and HPA

**Network Details**:
- Control-plane IP: 172.18.0.4 (kind network)
- Worker 1 IP: 172.18.0.2 (kind network)
- Worker 2 IP: 172.18.0.3 (kind network)
- Portainer Server: 172.18.0.5:9000 (Docker container on kind network)
- AdGuard DNS Service: 10.96.126.140:53
- CoreDNS: 10.96.0.10:53
- Prometheus Service: 10.96.72.113:9090
- Grafana Service: 10.96.186.116:3000

**Storage**:
- 3 PersistentVolumes (total 25Gi)
  - AdGuard Home: 10Gi
  - Prometheus: 10Gi (15-day retention)
  - Grafana: 5Gi
- StorageClass: `standard` (kind's local-path provisioner)

## Quick Health Check

Before making changes, verify cluster is healthy:

```bash
# From Mac - Quick 30-second health check
kubectl get nodes                    # Expected: 3 Ready nodes
kubectl get pods -A | grep -v Running # Should be empty (all pods Running)
kubectl get certificate -A           # Expected: 8 certificates, all READY=True
kubectl get ingress -A               # Expected: 6 ingress resources

# Verify critical services
kubectl get pods -n cert-manager     # Expected: 3/3 Running (cert-manager, cainjector, webhook)
kubectl get pods -n ingress-nginx    # Expected: 1/1 Running (ingress-nginx-controller)
kubectl get pods -n portainer        # Expected: 1/1 Running (portainer-agent)
kubectl get pods -n adguard-home     # Expected: 1/1 Running (adguard-home)
kubectl get pods -n monitoring       # Expected: 2/2 Running (prometheus, grafana)
kubectl get pods -n kube-system -l k8s-app=metrics-server  # Expected: 1/1 Running

# Test metrics-server
kubectl top nodes                    # Should show CPU/memory usage
kubectl top pods -A                  # Should show pod resource usage

# Check recent pod restarts (troubleshooting)
kubectl get pods -A -o wide | awk '{if ($4 > 5) print}'  # Pods with >5 restarts
```

**Healthy Cluster Baseline** (as of 2025-11-01):
- All 26 pods in Running state
- No recent restarts
- All 8 certificates issued and ready
- All 6 ingress routes responding with green lock (trusted TLS)
- metrics-server operational (kubectl top works)
- Prometheus scraping targets successfully
- Grafana connected to Prometheus datasource

## Common Commands

### Cluster Lifecycle (Run on WSL2)

```bash
# Create cluster
./scripts/01-setup-cluster.sh

# Deploy all services
./scripts/02-deploy-all.sh

# Export root CA certificate for client trust
./scripts/03-export-root-ca.sh

# Backup cluster resources
./scripts/backup-cluster.sh

# Destroy cluster
./scripts/destroy-cluster.sh
```

### Daily Operations (Run from Mac)

```bash
# View cluster status
kubectl get nodes
kubectl get pods -A
kubectl get certificate -A
kubectl get ingress -A

# Interactive cluster management
k9s

# View specific service
kubectl get pods -n <namespace>
kubectl logs -n <namespace> <pod-name>

# Check certificate status
kubectl describe certificate <cert-name> -n <namespace>
```

### Testing and Validation

```bash
# Verify API server binding (WSL2 only)
docker exec homelab-control-plane netstat -tlnp | grep 6443
# Must show: 0.0.0.0:6443 (NOT 127.0.0.1:6443)

# Test ingress routing
curl -k https://dashboard.homelab.local
curl -k https://whoami.homelab.local
curl -k https://portainer.homelab.local
curl -k https://adguard.homelab.local

# Verify certificate issuance
kubectl wait --for=condition=ready certificate <name> -n <namespace> --timeout=60s

# Check all certificates status
kubectl get certificate -A
# Expected: All showing READY=True (6 total)

# Check CoreDNS configuration (AdGuard integration)
kubectl get configmap coredns -n kube-system -o yaml | grep -A 5 "forward"
# Expected: forward . 10.96.126.140

# Verify Portainer hybrid architecture
kubectl get endpoints portainer -n portainer
# Expected: 172.18.0.5:9000 (Docker container, NOT pod IP)

# Check cluster resource distribution
kubectl get pods -A -o wide | grep -E "worker|worker2"
# Expected: Pods distributed across both worker nodes

# Validate storage
kubectl get pv,pvc -A
# Expected: 1 PV (10Gi) Bound to adguard-home/adguard-data
```

## Architecture Patterns

### Three-Tier PKI (cert-manager)

The cluster uses a three-tier certificate hierarchy matching enterprise PKI practices:

```
selfsigned-issuer (ClusterIssuer)
  └─> Root CA Certificate (10 years) → root-ca-secret
        └─> homelab-root-ca-issuer (ClusterIssuer)
              └─> Intermediate CA Certificate (5 years) → intermediate-ca-secret
                    └─> homelab-issuer (ClusterIssuer)
                          └─> Service Certificates (90 days, auto-renewed)
```

**Key Points:**
- Root CA stays offline in secret (never used directly for signing)
- Intermediate CA does actual signing (can be revoked if compromised)
- Service certs are short-lived and auto-renewed by cert-manager
- All certificates must reference `cert-manager.io/cluster-issuer: homelab-issuer` annotation

### Hybrid Portainer Architecture

Portainer uses a **unique hybrid deployment**:

- **Server**: Docker container on WSL2 (NOT in Kubernetes)
  - Direct Docker socket access (`/var/run/docker.sock`)
  - IP: `172.18.0.5` on kind network
  - Manages Docker containers and kind nodes

- **Agent**: Kubernetes Deployment in cluster
  - NodePort: `30778`
  - Provides K8s API access to Portainer Server
  - ClusterRole: `cluster-admin`

- **Ingress**: HTTPS access via nginx-ingress
  - Service without selector + manual Endpoints (points to Docker container IP)
  - Trusted TLS certificate from cert-manager

**Why?** kind nodes are containers-in-containers; Docker socket is not available inside pods.

### DNS Architecture (AdGuard Integration)

CoreDNS forwards all external DNS queries to AdGuard Home for cluster-wide ad blocking:

```
Pod → CoreDNS (10.96.0.10) → AdGuard Home (10.96.126.140:53) → Upstream DNS
```

**Configuration:**
- CoreDNS ConfigMap patched with `forward . 10.96.126.140`
- AdGuard runs as Deployment with PVC for persistent data
- Only affects cluster-internal pods (NOT external devices)

## Manifest Organization

Manifests are organized in **numbered directories** to enforce deployment order:

```
manifests/
├── 00-namespaces/         # Create namespaces first
├── 01-cert-manager/       # PKI (4 files: bootstrap → root → intermediate → issuer)
├── 02-adguard-home/       # DNS service
├── 02-ingress-nginx/      # Ingress controller
├── 03-kubernetes-dashboard/
├── 04-whoami/
├── 05-dns/               # DNS configuration
└── 06-portainer/
    ├── agent/            # K8s agent deployment
    ├── ingress.yaml      # HTTPS ingress
    ├── namespace.yaml
    └── service.yaml      # Service + manual Endpoints
```

**Deployment Script Pattern:**
- Install external dependencies first (cert-manager CRDs, nginx-ingress)
- Wait for readiness between steps (`kubectl wait --for=condition=ready`)
- Apply PKI in strict order (bootstrap → root → intermediate → issuer)
- Sleep between issuer creation and certificate requests (2s minimum)

## Adding New Services

### Standard Application with Ingress

1. Create manifests in numbered directory (e.g., `07-myapp/`)
2. Include namespace, deployment, service, ingress
3. Add certificate annotation to ingress:

```yaml
metadata:
  annotations:
    cert-manager.io/cluster-issuer: homelab-issuer
spec:
  tls:
  - hosts:
    - myapp.homelab.local
    secretName: myapp-tls  # cert-manager creates this
```

4. Update `/etc/hosts` on Mac: `<windows-ip>  myapp.homelab.local`
5. Apply manifests: `kubectl apply -f manifests/07-myapp/`
6. Wait for certificate: `kubectl wait --for=condition=ready certificate myapp-tls -n <namespace>`

### Storage Considerations

**StorageClass:** Use `standard` (NOT `local-path`)
- kind uses Rancher's local-path-provisioner
- Storage class name is `standard`
- PVCs with wrong storageClass stay Pending forever

**Binding Mode:** `WaitForFirstConsumer`
- PVC doesn't bind until pod is scheduled
- Don't expect immediate binding

**Example:**
```yaml
volumeClaimTemplates:
- metadata:
    name: data
  spec:
    storageClassName: standard  # Critical!
    accessModes: ["ReadWriteOnce"]
    resources:
      requests:
        storage: 10Gi
```

## Critical Configuration Details

### kind-config.yaml Requirements

**API Server Binding:**
```yaml
networking:
  apiServerAddress: "0.0.0.0"  # MUST be 0.0.0.0 for external access
  apiServerPort: 6443
kubeadmConfigPatches:
- |
  kind: ClusterConfiguration
  apiServer:
    certSANs:
    - "192.168.68.100"  # Windows host IP (for Mac access)
    - "k8s-api.homelab.local"
    - "localhost"
```

**Control Plane Configuration:**
```yaml
nodes:
  - role: control-plane
    labels:
      ingress-ready: "true"  # Required for ingress-nginx nodeSelector
    extraPortMappings:
      - containerPort: 80
        hostPort: 80
      - containerPort: 443
        hostPort: 443
```

### Ingress Controller Deployment

nginx-ingress MUST run on control-plane node:
- Official manifest: `https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml`
- Patch after deployment: `kubectl patch deployment ingress-nginx-controller -n ingress-nginx -p '{"spec":{"template":{"spec":{"nodeSelector":{"ingress-ready":"true"}}}}}'`

### Kubernetes Dashboard Access

Dashboard requires manual ServiceAccount creation:

```bash
kubectl -n kubernetes-dashboard create serviceaccount admin-user
kubectl create clusterrolebinding admin-user \
  --clusterrole=cluster-admin \
  --serviceaccount=kubernetes-dashboard:admin-user
kubectl -n kubernetes-dashboard create token admin-user
```

**Backend Protocol:** Dashboard runs HTTPS internally
- Ingress annotation: `nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"`
- nginx-ingress handles TLS termination and re-encryption

## Port Configuration Errors

**Common Issue:** Container port mismatch causing CrashLoopBackOff

When adding new services, verify container's actual listening port from logs:
```bash
kubectl logs -n <namespace> <pod-name>
```

**Example (AdGuard):**
- ❌ Assumed port: 3000 → Health checks fail, pod restarts continuously
- ✅ Actual port: 80 (from logs: `starting plain server addr=0.0.0.0:80`)
- Fix requires updating: deployment.yaml (containerPort + probes), service.yaml, ingress.yaml

## Environment-Specific Notes

### Mac Workstation Setup
- kubeconfig location: `~/.kube/config` (update server to `https://192.168.68.100:6443`)
- Root CA must be trusted: Keychain Access → System → Always Trust
- `/etc/hosts` entries: `192.168.68.100  dashboard.homelab.local whoami.homelab.local portainer.homelab.local adguard.homelab.local prometheus.homelab.local grafana.homelab.local`

### WSL2 (hill-arch) Setup
- Port forwarding script MUST be running: `C:\Scripts\wsl-port-forward.ps1`
- Docker on `kind` network required for Portainer hybrid architecture
- Git repository location: `~/source/repos/Personal/k8s-homelab/`

### Windows Configuration
- PowerShell script handles dynamic WSL2 IP on reboot
- Ports forwarded: 80, 443, 6443
- Root CA must be trusted: certmgr.msc → Trusted Root Certification Authorities

## Troubleshooting

### Certificates Not Issuing
1. Check issuer ready: `kubectl get clusterissuer`
2. Check certificate status: `kubectl describe certificate <name> -n <namespace>`
3. Check cert-manager logs: `kubectl logs -n cert-manager deployment/cert-manager`
4. Verify PKI order: bootstrap → root CA ready → intermediate CA ready → issuer ready

### Ingress Not Routing
1. Verify ingress resource: `kubectl get ingress -A`
2. Check nginx-ingress logs: `kubectl logs -n ingress-nginx deployment/ingress-nginx-controller`
3. Verify service exists: `kubectl get svc -n <namespace>`
4. Test from inside cluster: `kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- curl http://<service>.<namespace>`

### Pods CrashLoopBackOff
1. Check logs: `kubectl logs <pod> -n <namespace>`
2. Verify container port matches actual listening port
3. Check health probe configuration (port, path, timing)
4. Verify storage: `kubectl get pvc -n <namespace>` (must be Bound, storageClass: standard)

### Mac kubectl Not Working
1. Verify Windows port forwarding running
2. Check kubeconfig server: must be `https://192.168.68.100:6443`
3. Verify API server binding on WSL2: `docker exec homelab-control-plane netstat -tlnp | grep 6443` (must show 0.0.0.0)
4. Test connectivity: `curl -k https://192.168.68.100:6443`

## Deployment Statistics

**Manifest Files**: 33 YAML files across 9 numbered directories
**Documentation**: 7 markdown files (2,500+ lines)
**Automation Scripts**: 5 bash scripts

**Deployed Resources** (as of 2025-11-01):
- **Deployments**: 14 total
  - cert-manager ecosystem: 3 (cert-manager, cainjector, webhook)
  - Applications: 7 (adguard-home, whoami×2, dashboard, portainer-agent, prometheus, grafana)
  - Infrastructure: 4 (ingress-nginx, coredns×2, local-path-provisioner, metrics-server)
- **Services**: 16 total
- **Ingress Routes**: 6 (dashboard, whoami, portainer, adguard, prometheus, grafana)
- **Certificates**: 8 (root-ca, intermediate-ca, dashboard-tls, whoami-tls, portainer-tls, adguard-tls, prometheus-tls, grafana-tls)
- **ClusterIssuers**: 3 (selfsigned-issuer, homelab-root-ca-issuer, homelab-issuer)
- **PersistentVolumes**: 3 (total 25Gi: AdGuard 10Gi, Prometheus 10Gi, Grafana 5Gi)

**Pod Distribution**:
- Control-plane node: 7 pods (system components + ingress-nginx)
- Worker 1: 10 pods (distributed workloads)
- Worker 2: 9 pods (distributed workloads)

## Version History

This is **Lab v2** - a complete rebuild of Lab v1 with the following fixes:
- ✅ API server on `0.0.0.0:6443` (was `127.0.0.1`)
- ✅ Git source control (was ad-hoc manifests)
- ✅ Mac-first kubectl workflow (was SSH-based)
- ✅ Automated deployment scripts (was manual)

**Timeline**:
- **2025-10-28**: Lab v2 planning and repository setup
- **2025-10-29**: MVP deployment complete (Dashboard + whoami + PKI)
- **2025-10-30**: AdGuard Home deployed (port configuration fix)
- **2025-11-01**: Portainer hybrid architecture deployed + AdGuard CoreDNS integration + Complete monitoring stack (metrics-server, Prometheus, Grafana)

All architectural decisions are documented in `docs/architecture.md` and basic-memory project notes.
