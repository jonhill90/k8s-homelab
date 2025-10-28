# Architecture

## Overview

Homelab v2 is a production-grade Kubernetes homelab running on kind (Kubernetes in Docker) on WSL2, with kubectl access from Mac workstation.

## Network Flow

```
┌─────────────────┐
│  Mac Workstation│
│  (10.0.0.x)     │
└────────┬────────┘
         │
         │ kubectl commands (6443)
         │ HTTPS requests (80, 443)
         │
         v
┌─────────────────────────┐
│   Windows Host          │
│   Port Forwarding:      │
│   - 6443 → WSL2:6443    │
│   - 80   → WSL2:80      │
│   - 443  → WSL2:443     │
└────────┬────────────────┘
         │
         v
┌─────────────────────────┐
│   WSL2 (hill-arch)      │
│   Dynamic IP (172.x.x.x)│
└────────┬────────────────┘
         │
         v
┌──────────────────────────────────────┐
│  kind Cluster (homelab)              │
│  ┌────────────────────────────────┐  │
│  │  Control Plane                 │  │
│  │  - API Server (0.0.0.0:6443)   │  │
│  │  - nginx-ingress (80, 443)     │  │
│  │  - cert-manager                │  │
│  └────────────────────────────────┘  │
│  ┌────────────────────────────────┐  │
│  │  Worker 1                      │  │
│  │  - Application Pods            │  │
│  └────────────────────────────────┘  │
│  ┌────────────────────────────────┐  │
│  │  Worker 2                      │  │
│  │  - Application Pods            │  │
│  └────────────────────────────────┘  │
└──────────────────────────────────────┘
```

## Component Details

### kind Cluster

**Configuration:**
- Name: `homelab`
- Nodes: 3 (1 control-plane, 2 workers)
- API Server: `0.0.0.0:6443` (NOT `127.0.0.1`)
- Container Runtime: Docker

**Why 0.0.0.0:6443?**
- Allows API server to be accessible from outside WSL2
- Windows port forwarding can route Mac → Windows → WSL2 → kind
- Critical for Mac workstation kubectl workflow

**Port Mappings (Control Plane):**
- Container port 80 → Host port 80 (HTTP ingress)
- Container port 443 → Host port 443 (HTTPS ingress)

### Three-Tier PKI Architecture

```
┌───────────────────────────────┐
│  selfsigned-issuer            │
│  (ClusterIssuer)              │
│  Self-signed bootstrap        │
└──────────┬────────────────────┘
           │
           │ Signs
           v
┌───────────────────────────────┐
│  Root CA Certificate          │
│  (10 years)                   │
│  CN: Homelab Root CA          │
│  Secret: root-ca-secret       │
└──────────┬────────────────────┘
           │
           │ Creates issuer
           v
┌───────────────────────────────┐
│  homelab-root-ca-issuer       │
│  (ClusterIssuer)              │
│  Uses root-ca-secret          │
└──────────┬────────────────────┘
           │
           │ Signs
           v
┌───────────────────────────────┐
│  Intermediate CA Certificate  │
│  (5 years)                    │
│  CN: Homelab Intermediate CA  │
│  Secret: intermediate-ca-secret│
└──────────┬────────────────────┘
           │
           │ Creates final issuer
           v
┌───────────────────────────────┐
│  homelab-issuer               │
│  (ClusterIssuer)              │
│  Uses intermediate-ca-secret  │
└──────────┬────────────────────┘
           │
           │ Issues service certs
           v
┌───────────────────────────────┐
│  Service Certificates         │
│  (90 days, auto-renewed)      │
│  - dashboard-tls              │
│  - whoami-tls                 │
│  - <future services>          │
└───────────────────────────────┘
```

**Why Three Tiers?**
- **Root CA**: Never used directly, kept offline (in secret)
- **Intermediate CA**: Does the actual signing, can be revoked if compromised
- **Service Certs**: Short-lived, auto-renewed by cert-manager
- **Industry Standard**: Matches enterprise PKI practices

### cert-manager

**Version:** v1.13.2

**Components:**
- Controller: Watches for Certificate resources
- Webhook: Validates certificate requests
- CAInjector: Injects CA bundles into resources

**Certificate Lifecycle:**
1. Service manifest requests certificate (annotation)
2. cert-manager creates Certificate resource
3. Certificate references `homelab-issuer` ClusterIssuer
4. Intermediate CA signs the certificate
5. TLS secret created in service namespace
6. Ingress uses TLS secret for HTTPS
7. Auto-renewal 30 days before expiry

### nginx-ingress

**Deployment:**
- Uses official kind-specific manifest
- Runs on control-plane node (nodeSelector: `ingress-ready=true`)
- Exposed via kind port mappings (80, 443)

**How It Works:**
1. Client requests `https://dashboard.homelab.local`
2. Windows forwards to WSL2 IP on port 443
3. WSL2 forwards to kind control-plane on port 443
4. nginx-ingress receives request
5. Looks up Ingress resource for `dashboard.homelab.local`
6. Routes to Dashboard service in `kubernetes-dashboard` namespace
7. Returns response with trusted TLS certificate

### Kubernetes Dashboard

**Deployment:**
- Official v2.7.0 manifest
- Namespace: `kubernetes-dashboard`
- Service: ClusterIP (internal only)
- Access: Via ingress only (no NodePort, no LoadBalancer)

**Certificate:**
- Requested via annotation: `cert-manager.io/cluster-issuer: homelab-issuer`
- Secret name: `dashboard-tls`
- Auto-issued by cert-manager
- Trusted by browsers after root CA install

**Backend Protocol:**
- Dashboard runs HTTPS internally
- Ingress annotation: `nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"`
- nginx-ingress handles TLS termination and re-encryption

### whoami Test Application

**Purpose:**
- Validate ingress configuration
- Test certificate issuance
- Debug request headers and routing

**Deployment:**
- Image: `traefik/whoami`
- Replicas: 2
- Returns request information (IP, headers, hostname)

## DNS Configuration

**Local DNS (Mac):**
```
# /etc/hosts
<windows-ip>  dashboard.homelab.local
<windows-ip>  whoami.homelab.local
```

**Resolution Flow:**
1. Mac browser requests `dashboard.homelab.local`
2. `/etc/hosts` resolves to Windows IP
3. Windows port forwarding routes to WSL2
4. nginx-ingress routes to Dashboard pod

## Port Forwarding (Windows)

**Script:** `C:\Scripts\wsl-port-forward.ps1`

**Functionality:**
- Detects WSL2 IP dynamically (changes on reboot)
- Creates Windows firewall rules
- Forwards ports: 80, 443, 6443
- Runs as Administrator (required for port forwarding)

**Why Needed?**
- WSL2 is NAT'd behind Windows
- External devices (Mac) can't reach WSL2 directly
- Port forwarding bridges Windows → WSL2

## Security Model

### Certificate Trust

**Root CA Installation:**
- **Mac**: Keychain Access → System keychain → Always Trust
- **Windows**: Certificate Store → Trusted Root Certification Authorities
- **Result**: All services show green lock (trusted certificates)

### Network Isolation

**Ingress-Only Access:**
- Services use ClusterIP (not NodePort or LoadBalancer)
- Only accessible via ingress controller
- No direct pod access from outside cluster

**TLS Everywhere:**
- All ingress traffic uses HTTPS
- Certificates auto-issued and auto-renewed
- No HTTP traffic (redirects or rejected)

### Authentication

**Kubernetes Dashboard:**
- Token-based authentication
- Service account tokens
- No anonymous access

**kubectl Access:**
- Client certificate authentication
- kubeconfig with embedded certs
- Token authentication (optional)

## Storage

**Kind Default:**
- Local path provisioner (built-in)
- PersistentVolumes backed by Docker volumes
- Storage class: `standard`

**Data Persistence:**
- PVCs survive pod restarts
- Data lost if cluster deleted (backup first)

## Backup Strategy

**Script:** `backup-cluster.sh`

**What's Backed Up:**
- All Kubernetes resources (YAML export)
- Cluster configuration
- Certificate secrets (encrypted)

**What's NOT Backed Up:**
- PersistentVolume data (manual backup required)
- Docker images (re-pulled on restore)

## Scaling Considerations

**Current Limitations:**
- Single control-plane (no HA)
- Docker on WSL2 (resource limits)
- Local storage only

**Future Enhancements:**
- NFS persistent storage
- Multi-node HA control-plane
- Monitoring (Prometheus/Grafana)
- DNS server (AdGuard Home)

## Comparison: Lab v1 vs v2

| Aspect | Lab v1 | Lab v2 |
|--------|--------|--------|
| API Binding | `127.0.0.1:6443` ❌ | `0.0.0.0:6443` ✅ |
| Source Control | None ❌ | Git repository ✅ |
| Workflow | SSH-based ❌ | Mac kubectl ✅ |
| Documentation | Scattered notes ❌ | Complete docs ✅ |
| Reproducibility | Manual setup ❌ | Automated scripts ✅ |
| PKI Architecture | Working ✅ | Preserved ✅ |
| Certificates | Trusted ✅ | Trusted ✅ |

## Technical Decisions

### Why kind Instead of kubeadm?

**Advantages:**
- Fast cluster creation (<2 minutes)
- Isolated in Docker (easy cleanup)
- Perfect for development/testing
- Minimal resource overhead

**Trade-offs:**
- Not production-grade
- Storage limitations
- Single-machine only

### Why Three-Tier PKI?

**Alternatives Considered:**
- Let's Encrypt: Requires public DNS, 90-day manual renewal
- Self-signed per service: No trust chain, browser warnings
- Single CA: Can't revoke without re-trusting everything

**Chosen Approach:**
- Root CA offline (in secret)
- Intermediate CA does signing
- Service certs short-lived
- Matches enterprise practices

### Why Mac Workstation?

**Previous Approach (Lab v1):**
- SSH into WSL2 for every kubectl command
- Slow (latency)
- No native tools (k9s)

**New Approach (Lab v2):**
- kubectl directly from Mac
- Native k9s with mouse support
- Faster workflow
- Professional development experience

## Monitoring Points

**Cluster Health:**
```bash
kubectl get nodes
kubectl get pods -A
kubectl top nodes
kubectl top pods -A
```

**Certificate Status:**
```bash
kubectl get certificate -A
kubectl describe certificate <name> -n <namespace>
```

**Ingress Status:**
```bash
kubectl get ingress -A
kubectl describe ingress <name> -n <namespace>
```

**cert-manager Logs:**
```bash
kubectl logs -n cert-manager deployment/cert-manager
```

## Next Steps

1. Deploy AdGuard Home for DNS + ad blocking
2. Add monitoring (metrics-server, Prometheus)
3. Implement backup automation
4. Document additional services
5. Consider persistent NFS storage