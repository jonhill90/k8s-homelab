# Homelab v2 - Kubernetes on kind

Production-grade Kubernetes homelab with three-tier PKI, automated certificate management, complete observability stack, and Mac workstation kubectl workflow.

## Quick Start

```bash
# On WSL2 (hill-arch)
./scripts/01-setup-cluster.sh    # Create cluster
./scripts/02-deploy-all.sh        # Deploy all services
./scripts/03-export-root-ca.sh    # Export root CA certificate

# Export kubeconfig to Mac
scp ~/.kube/config jon@<mac-ip>:~/.kube/homelab-config
```

## Architecture Overview

**Network Flow:**
```
Mac Workstation
  ├─> kubectl → Windows → WSL2 → kind API (0.0.0.0:6443)
  └─> Browser → Windows → WSL2 → nginx-ingress → Services
```

**PKI Chain:**
```
Root CA (10 years)
  └─> Intermediate CA (5 years)
        └─> Service Certificates (90 days, auto-renewed)
```

**Infrastructure:**
- **Cluster**: 3-node kind cluster (1 control-plane, 2 workers)
- **Certificates**: cert-manager v1.13.2 with three-tier PKI
- **Ingress**: nginx-ingress controller
- **DNS**: AdGuard Home (cluster-wide DNS with ad blocking)
- **GitOps**: ArgoCD (declarative continuous delivery)
- **Monitoring**: metrics-server, Prometheus, Grafana, kube-state-metrics, node-exporter
- **Observability**: OpenTelemetry Collector, Loki (logs), Tempo (traces), Promtail (log collection)
- **Applications**: Kubernetes Dashboard, Portainer (Docker + K8s management), AdGuard Home, whoami test app

## Services

| Service | URL | Certificate | Purpose |
|---------|-----|-------------|---------|
| Kubernetes Dashboard | https://dashboard.homelab.local | Trusted (green lock) | K8s cluster management |
| Portainer | https://portainer.homelab.local | Trusted (green lock) | Docker + K8s management |
| ArgoCD | https://argocd.homelab.local | Trusted (green lock) | GitOps continuous delivery |
| AdGuard Home | https://adguard.homelab.local | Trusted (green lock) | DNS + ad blocking (cluster-wide) |
| Prometheus | https://prometheus.homelab.local | Trusted (green lock) | Metrics collection & monitoring |
| Grafana | https://grafana.homelab.local | Trusted (green lock) | Metrics visualization (admin/admin) |
| whoami Test App | https://whoami.homelab.local | Trusted (green lock) | Ingress test |

## Cluster Statistics

**Resource Count:**
- Nodes: 3 (1 control-plane, 2 workers)
- Pods: 34 (across 13 namespaces)
- Certificates: 9 (all READY=True)
- Ingress Routes: 7
- PersistentVolumes: 5 (55Gi total)
- Helm Releases: 1 (ArgoCD)

**Resource Usage (Typical Idle):**
- CPU: ~9.6% cluster-wide
- Memory: ~7.0% cluster-wide
- Disk: ~1.24% cluster-wide

**Storage Allocation:**
- AdGuard Home: 10Gi (DNS query logs & config)
- Prometheus: 10Gi (metrics, 15-day retention)
- Grafana: 5Gi (dashboards & settings)
- Loki: 20Gi (application logs)
- Tempo: 10Gi (distributed traces)

## Prerequisites

**Mac:**
- kubectl, k9s installed
- Root CA trusted in Keychain
- `/etc/hosts` entries:
  ```
  192.168.68.100  dashboard.homelab.local
  192.168.68.100  whoami.homelab.local
  192.168.68.100  portainer.homelab.local
  192.168.68.100  argocd.homelab.local
  192.168.68.100  adguard.homelab.local
  192.168.68.100  prometheus.homelab.local
  192.168.68.100  grafana.homelab.local
  ```

**Windows:**
- Port forwarding script running (`C:\Scripts\wsl-port-forward.ps1`)
- Root CA trusted in Certificate Store

**WSL2 (hill-arch):**
- Docker, kind, kubectl installed
- Git repository cloned

## Documentation

- [Architecture](docs/architecture.md) - Detailed network flow and component design
- [Setup Guide](docs/setup.md) - Step-by-step installation instructions
- [Troubleshooting](docs/troubleshooting.md) - Common issues and solutions
- [Port Forwarding](docs/port-forwarding.md) - Windows port forwarding configuration
- [Monitoring README](manifests/08-monitoring/README.md) - Complete monitoring guide

## Scripts

| Script | Purpose |
|--------|---------|
| `01-setup-cluster.sh` | Create kind cluster with correct API binding |
| `02-deploy-all.sh` | Deploy all manifests in correct order |
| `03-export-root-ca.sh` | Export root CA certificate to trust |
| `backup-cluster.sh` | Backup all cluster resources |
| `destroy-cluster.sh` | Delete cluster and cleanup |

## Folder Structure

```
k8s-homelab/
├── kind-config.yaml              # Cluster definition (0.0.0.0:6443)
├── manifests/
│   ├── 00-namespaces/            # Namespace definitions
│   ├── 01-cert-manager/          # Three-tier PKI configuration
│   ├── 02-adguard-home/          # DNS + ad blocking
│   ├── 02-ingress-nginx/         # Ingress controller
│   ├── 03-kubernetes-dashboard/  # Dashboard with ingress
│   ├── 04-whoami/                # Test application
│   ├── 05-dns/                   # DNS configuration
│   ├── 06-portainer/             # Portainer ingress + agent
│   │   ├── agent/                # Portainer agent for K8s management
│   │   ├── ingress.yaml          # HTTPS ingress for Portainer UI
│   │   ├── namespace.yaml        # Portainer namespace
│   │   └── service.yaml          # Service pointing to Docker container
│   ├── 07-metrics-server/        # Kubernetes metrics for kubectl top
│   ├── 08-monitoring/            # Prometheus + Grafana + exporters
│   ├── 09-opentelemetry/         # OpenTelemetry collector
│   └── 10-observability/         # Loki + Tempo + Promtail
├── scripts/                      # Automation scripts
└── docs/                         # Documentation
```

## Key Configuration

**API Server Binding:**
- Address: `0.0.0.0:6443` (accessible from Mac via Windows port forwarding)
- NOT `127.0.0.1:6443` (localhost only)

**Certificate Issuers:**
- `selfsigned-issuer` - Bootstrap self-signed issuer
- `homelab-root-ca-issuer` - Root CA issuer (10y)
- `homelab-issuer` - Final cluster issuer (uses intermediate CA)

**Ingress Configuration:**
- Runs on control-plane node (label: `ingress-ready=true`)
- Ports 80 and 443 mapped to host
- TLS certificates auto-issued by cert-manager

## Workflow

**Daily Development:**
```bash
# From Mac - no SSH required
kubectl get pods -A
kubectl top nodes
k9s
```

**Quick Health Check (30 seconds):**
```bash
kubectl get nodes                    # Expected: 3 Ready nodes
kubectl get pods -A | grep -v Running # Should be empty (all pods Running)
kubectl get certificate -A           # Expected: 8 certificates, all READY=True
kubectl get ingress -A               # Expected: 6 ingress resources
kubectl top nodes                    # Should show CPU/memory usage
kubectl top pods -A                  # Should show pod resource usage
```

**Deploy New Service:**
```bash
# Add manifest with cert-manager annotation
cert-manager.io/cluster-issuer: homelab-issuer

# Apply and verify
kubectl apply -f manifests/
kubectl get certificate -n <namespace>
```

## Portainer Setup

Portainer runs as a **Docker container** (not in Kubernetes) with ingress access via nginx-ingress.

**Deploy Portainer:**
```bash
# On WSL2 (hill-arch) - one-time setup
docker run -d \
  --name portainer \
  --restart=always \
  -p 9000:9000 \
  -p 9443:9443 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  --network kind \
  portainer/portainer-ce:latest

# Deploy Kubernetes ingress (from Mac)
kubectl apply -f manifests/06-portainer/
```

**Why Docker instead of Kubernetes?**
- Direct access to Docker socket (manage kind nodes and other containers)
- Can deploy Docker Compose stacks alongside Kubernetes
- Not affected by cluster restarts
- Still accessible via HTTPS with trusted certificate through ingress

**Deploy Portainer Agent (for Kubernetes management):**
```bash
# Deploy agent to cluster (from Mac)
kubectl apply -f manifests/06-portainer/agent/

# Verify agent running
kubectl get pods -n portainer
```

**Add Kubernetes to Portainer:**
1. Go to https://portainer.homelab.local
2. Environments → Add environment → Kubernetes (via agent)
3. Name: `homelab-cluster`
4. Environment URL: `172.18.0.4:30778` (control-plane IP + NodePort)
5. Click Add environment

**Access:** https://portainer.homelab.local (manage both Docker and Kubernetes)

## AdGuard Home Setup

AdGuard Home provides DNS resolution and ad blocking for all pods in the cluster.

**CoreDNS Configuration:**
```bash
# CoreDNS forwards all DNS queries to AdGuard Home
# AdGuard Service IP: 10.96.126.140:53
```

**Initial Setup:**
1. Go to https://adguard.homelab.local
2. Complete setup wizard:
   - Set admin username/password
   - Configure upstream DNS servers: `1.1.1.1`, `1.0.0.1`, `8.8.8.8`, `8.8.4.4`
3. Enable DNS blocklists (Filters → DNS blocklists)

**DNS Flow:**
```
Pod → CoreDNS (10.96.0.10) → AdGuard Home (10.96.126.140) → Upstream DNS
```

**Benefits:**
- Ad blocking for all cluster applications
- DNS query logging and analytics
- Custom filtering rules
- Safe browsing (malware/phishing protection)

**Note:** AdGuard is configured for cluster-internal use only. External devices (Mac, Windows) use their default DNS unless manually configured.

## Monitoring & Observability

The cluster includes a complete observability stack for metrics, logs, and traces.

### Metrics Collection (Prometheus + Grafana)

**Architecture:**
```
Prometheus scrapes:
├── kubelet → Node health metrics
├── cadvisor → Container CPU/memory/network/disk
├── kube-state-metrics → Pod/Deployment/Node states
├── node-exporter → Linux host metrics (3 DaemonSet pods)
├── API server → Control plane metrics
└── metrics-server → Resource metrics for kubectl top
```

**Access:**
- **Prometheus**: https://prometheus.homelab.local
  - Query metrics, view scrape targets (Status → Targets)
  - All targets should show "UP" status
- **Grafana**: https://grafana.homelab.local
  - Default credentials: `admin` / `admin` (prompts to change on first login)
  - Prometheus datasource pre-configured
  - Import recommended dashboards (Dashboards → Import):
    - ID 315: Kubernetes cluster monitoring (Prometheus)
    - ID 6417: Kubernetes Cluster (Prometheus)
    - ID 1860: Node Exporter Full

**Key Metrics Available:**
- `container_cpu_usage_seconds_total` - Container CPU usage
- `container_memory_usage_bytes` - Container memory usage
- `kube_pod_status_phase` - Pod states (Running/Pending/Failed)
- `kube_deployment_replicas` - Deployment health
- `node_filesystem_size_bytes` - Node disk usage
- `node_cpu_seconds_total` - Node CPU usage
- `node_memory_MemTotal_bytes` - Node memory capacity

**Example Queries:**
```promql
# Total running pods
sum(kube_pod_status_phase{phase="Running"})

# Node CPU usage (%)
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Pod memory usage
sum(container_memory_usage_bytes{pod=~".*"}) by (pod)
```

### Log Aggregation (Loki + Promtail)

**Components:**
- **Loki**: Centralized log storage (20Gi retention)
- **Promtail**: Log collection agent (DaemonSet on all nodes)

**Access:**
- Loki integrated with Grafana (Explore → Loki datasource)
- Query logs using LogQL syntax

**Example LogQL Queries:**
```logql
# All logs from namespace
{namespace="monitoring"}

# Error logs across cluster
{job="kubernetes-pods"} |= "error"

# Logs from specific pod
{pod="prometheus-965fd69bb-km2nn"}
```

### Distributed Tracing (Tempo + OpenTelemetry)

**Components:**
- **Tempo**: Trace storage backend (10Gi retention)
- **OpenTelemetry Collector**: Trace ingestion (OTLP endpoints)

**Endpoints:**
- OTLP gRPC: `otel-collector.opentelemetry:4317`
- OTLP HTTP: `otel-collector.opentelemetry:4318`

**Integration:**
Applications can send traces using OpenTelemetry SDKs to the collector endpoints.

### Monitoring Validation

```bash
# Verify metrics-server
kubectl top nodes
kubectl top pods -A

# Check Prometheus targets
curl -k https://prometheus.homelab.local/api/v1/targets

# Check all monitoring pods
kubectl get pods -n monitoring
kubectl get pods -n observability
kubectl get pods -n opentelemetry

# Verify exporters
kubectl get pods -l app=kube-state-metrics -n monitoring
kubectl get pods -l app=node-exporter -n monitoring

# Check persistent storage
kubectl get pvc -n monitoring
kubectl get pvc -n observability
```

## Validation

```bash
# Check cluster health
kubectl get nodes                    # 3 nodes Ready
kubectl get pods -A                  # All Running
kubectl top nodes                    # Resource usage
kubectl top pods -A                  # Pod resource usage

# Check certificates
kubectl get certificate -A           # All READY=True
kubectl get secret -A | grep tls     # TLS secrets created

# Check ingress
kubectl get ingress -A               # Hosts configured
curl -k https://dashboard.homelab.local
curl -k https://whoami.homelab.local
curl -k https://portainer.homelab.local
curl -k https://adguard.homelab.local
curl -k https://prometheus.homelab.local
curl -k https://grafana.homelab.local

# Check recent pod restarts (troubleshooting)
kubectl get pods -A -o wide | awk '{if ($4 > 5) print}'  # Pods with >5 restarts
```

## Lab History

- **Lab v1**: Successfully deployed, archived to `.archive/`
  - ❌ API server bound to `127.0.0.1` (incorrect)
  - ❌ No Git source control
  - ✅ Three-tier PKI working
  - ✅ Trusted certificates operational

- **Lab v2**: Production-grade rebuild (current)
  - ✅ API server on `0.0.0.0:6443`
  - ✅ Full Git source control
  - ✅ Mac-first kubectl workflow
  - ✅ Reproducible infrastructure
  - ✅ Complete observability stack

**Timeline:**
- **2025-10-28**: Project initiated, repository created
- **2025-10-29**: MVP complete (Dashboard + whoami + TLS)
- **2025-10-30**: AdGuard Home deployed
- **2025-10-31**: Portainer hybrid architecture deployed
- **2025-11-01**: Complete monitoring & observability stack deployed

## Contributing

This is a personal homelab project. See project documentation in basic-memory for architecture decisions and rationale.

## License

MIT
