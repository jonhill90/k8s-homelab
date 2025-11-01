# Homelab v2 - Kubernetes on kind

Production-grade Kubernetes homelab with three-tier PKI, automated certificate management, and Mac workstation kubectl workflow.

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
- **Services**: Kubernetes Dashboard, Portainer (Docker container with K8s ingress), whoami test app

## Services

| Service | URL | Certificate |
|---------|-----|-------------|
| Kubernetes Dashboard | https://dashboard.homelab.local | Trusted (green lock) |
| Portainer | https://portainer.homelab.local | Trusted (green lock) |
| whoami Test App | https://whoami.homelab.local | Trusted (green lock) |

## Prerequisites

**Mac:**
- kubectl, k9s installed
- Root CA trusted in Keychain
- `/etc/hosts` entries for `*.homelab.local`

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
│   └── 06-portainer/             # Ingress for Portainer (runs as Docker container)
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
k9s
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

**Access:** https://portainer.homelab.local (complete initial setup wizard)

## Validation

```bash
# Check cluster health
kubectl get nodes                    # 3 nodes Ready
kubectl get pods -A                  # All Running

# Check certificates
kubectl get certificate -A           # All True
kubectl get secret -A | grep tls     # TLS secrets created

# Check ingress
kubectl get ingress -A               # Hosts configured
curl -k https://dashboard.homelab.local
curl -k https://portainer.homelab.local
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

## Contributing

This is a personal homelab project. See project documentation in basic-memory for architecture decisions and rationale.

## License

MIT