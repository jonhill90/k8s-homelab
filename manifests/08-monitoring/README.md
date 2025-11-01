# Monitoring Stack (Prometheus + Grafana)

Complete monitoring solution for Kubernetes homelab with metrics collection, visualization, and alerting.

## Components

### Prometheus
- **Purpose**: Time-series database and metrics collection
- **Scrape Targets**:
  - Kubernetes API server
  - Kubernetes nodes (kubelet metrics)
  - Kubernetes pods (with `prometheus.io/scrape: "true"` annotation)
  - Kubernetes services (with `prometheus.io/scrape: "true"` annotation)
- **Storage**: 10Gi PVC with 15-day retention
- **Access**: https://prometheus.homelab.local

### Grafana
- **Purpose**: Metrics visualization and dashboards
- **Data Source**: Prometheus (auto-configured)
- **Default Credentials**: admin/admin (change on first login)
- **Storage**: 5Gi PVC for dashboards and settings
- **Access**: https://grafana.homelab.local

## Architecture

```
Kubernetes Cluster
  ├─> Prometheus (scrapes metrics)
  │     ├─> API Server
  │     ├─> Nodes (kubelet)
  │     ├─> Pods (annotated)
  │     └─> Services (annotated)
  │
  └─> Grafana (visualizes metrics)
        └─> Prometheus datasource
```

## Installation

```bash
# Deploy monitoring stack
kubectl apply -f manifests/08-monitoring/namespace.yaml
kubectl apply -f manifests/08-monitoring/prometheus-deployment.yaml
kubectl apply -f manifests/08-monitoring/prometheus-service.yaml
kubectl apply -f manifests/08-monitoring/prometheus-ingress.yaml
kubectl apply -f manifests/08-monitoring/grafana-deployment.yaml
kubectl apply -f manifests/08-monitoring/grafana-service.yaml
kubectl apply -f manifests/08-monitoring/grafana-ingress.yaml

# Wait for deployments
kubectl wait --for=condition=ready pod -l app=prometheus -n monitoring --timeout=120s
kubectl wait --for=condition=ready pod -l app=grafana -n monitoring --timeout=120s

# Wait for certificates
kubectl wait --for=condition=ready certificate prometheus-tls -n monitoring --timeout=60s
kubectl wait --for=condition=ready certificate grafana-tls -n monitoring --timeout=60s
```

## DNS Configuration

Add to `/etc/hosts` on Mac:

```
192.168.68.100  prometheus.homelab.local
192.168.68.100  grafana.homelab.local
```

## Accessing Services

### Prometheus
- URL: https://prometheus.homelab.local
- Navigate to Status → Targets to see all scrape targets
- Navigate to Graph to query metrics (e.g., `up`, `node_cpu_seconds_total`)

### Grafana
- URL: https://grafana.homelab.local
- Login: admin/admin (change on first login)
- Data source already configured (Prometheus)
- Import community dashboards:
  - ID 315: Kubernetes cluster monitoring
  - ID 1860: Node Exporter Full
  - ID 6417: Kubernetes Cluster (Prometheus)

## Adding Metrics to Your Application

### For Pods

Add annotation to your pod spec:

```yaml
metadata:
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"        # Your metrics port
    prometheus.io/path: "/metrics"    # Metrics endpoint
```

### For Services

Add annotation to your service:

```yaml
metadata:
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
    prometheus.io/path: "/metrics"
```

## Useful Prometheus Queries

```promql
# Pod CPU usage
sum(rate(container_cpu_usage_seconds_total{namespace="default"}[5m])) by (pod)

# Pod memory usage
sum(container_memory_usage_bytes{namespace="default"}) by (pod)

# Node CPU usage
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Available memory per node
node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100

# Pod restart count
kube_pod_container_status_restarts_total
```

## Storage Notes

- **Prometheus**: 10Gi storage with 15-day retention (configurable via `--storage.tsdb.retention.time`)
- **Grafana**: 5Gi storage for dashboards and plugin data
- Both use `storageClassName: standard` (kind's local-path-provisioner)

## RBAC

Prometheus ServiceAccount has ClusterRole permissions to:
- Read nodes, services, endpoints, pods
- Read ingresses
- Access `/metrics` endpoint

## Troubleshooting

### Prometheus Not Scraping Targets

```bash
# Check Prometheus logs
kubectl logs -n monitoring deployment/prometheus

# Check service discovery
kubectl get endpoints -A

# Verify RBAC permissions
kubectl auth can-i get pods --as=system:serviceaccount:monitoring:prometheus -A
```

### Grafana Can't Connect to Prometheus

```bash
# Verify Prometheus service
kubectl get svc prometheus -n monitoring

# Test connectivity from Grafana pod
kubectl exec -n monitoring deployment/grafana -- curl http://prometheus:9090/-/healthy
```

### Certificates Not Issuing

```bash
# Check certificate status
kubectl describe certificate prometheus-tls -n monitoring
kubectl describe certificate grafana-tls -n monitoring

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager
```

## Future Enhancements

- [ ] Deploy kube-state-metrics for Kubernetes object metrics
- [ ] Deploy node-exporter as DaemonSet for node-level metrics
- [ ] Configure Alertmanager for alerting
- [ ] Add Loki for log aggregation
- [ ] Add custom recording rules for common queries
- [ ] Configure persistent remote storage (Thanos, Cortex, or Victoria Metrics)
