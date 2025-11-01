# Observability Stack (Tempo + Loki + Promtail)

Complete observability backend for distributed tracing and centralized logging, integrated with Grafana for visualization.

## Components

### Tempo
- **Purpose**: Distributed tracing backend
- **Storage**: 10Gi PVC (7-day retention)
- **Endpoint**: `tempo.observability:3100`
- **Features**:
  - Trace search by service, operation, tags
  - Request flow visualization
  - Performance analysis (latency percentiles)

### Loki
- **Purpose**: Log aggregation system
- **Storage**: 20Gi PVC (30-day retention)
- **Endpoint**: `loki.observability:3100`
- **Features**:
  - Label-based log indexing (efficient storage)
  - LogQL query language (similar to PromQL)
  - Regex search across all logs

### Promtail
- **Purpose**: Log collection agent (DaemonSet)
- **Deployment**: Runs on every node
- **Features**:
  - Automatic pod discovery
  - Kubernetes metadata enrichment
  - Ships logs to Loki

## Deployment

```bash
# Deploy observability stack
kubectl apply -f manifests/10-observability/

# Wait for PVCs to bind (may take a moment)
kubectl get pvc -n observability -w

# Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app=tempo -n observability --timeout=120s
kubectl wait --for=condition=ready pod -l app=loki -n observability --timeout=120s

# Verify Promtail running on all nodes
kubectl get pods -n observability -l app=promtail -o wide
```

## Verification

### Check Tempo

```bash
# Check Tempo ready
kubectl exec -n observability deployment/tempo -- wget -qO- http://localhost:3100/ready

# Query for traces (after sending some)
curl http://tempo.observability:3100/api/search
```

### Check Loki

```bash
# Check Loki ready
kubectl exec -n observability deployment/loki -- wget -qO- http://localhost:3100/ready

# Query logs
curl -G -s "http://loki.observability:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={namespace="default"}' | jq
```

### Check Promtail

```bash
# View Promtail logs (should show discovered pods)
kubectl logs -n observability daemonset/promtail --tail=20

# Check Promtail on specific node
kubectl logs -n observability -l app=promtail --tail=10 --selector="app=promtail"
```

## Grafana Integration

### Add Datasources

1. Open Grafana: https://grafana.homelab.local
2. Go to Configuration → Data Sources → Add data source

**Tempo:**
- Name: `Tempo`
- Type: `Tempo`
- URL: `http://tempo.observability:3100`
- Save & Test

**Loki:**
- Name: `Loki`
- Type: `Loki`
- URL: `http://loki.observability:3100`
- Save & Test

### Configure Trace-to-Logs Correlation

In Tempo datasource settings:
- **Derived fields**:
  - Name: `trace_id`
  - Regex: `traceID=(\w+)`
  - URL: `${__value.raw}`
  - Internal link → Loki
  - Query: `{trace_id="${__value.raw}"}`

This enables "View Logs" button in traces!

## Usage Examples

### Search Logs in Grafana

Navigate to Explore → Select Loki datasource:

```logql
# All logs from default namespace
{namespace="default"}

# Error logs across all namespaces
{namespace=~".+"} |= "error"

# Logs from specific pod
{pod="whoami-589cfdb474-trq2b"}

# Logs matching regex
{namespace="monitoring"} |~ ".*connection.*"

# Count errors per minute
rate({namespace="default"} |= "error" [1m])
```

### View Traces in Grafana

Navigate to Explore → Select Tempo datasource:

- Search by service name
- Filter by duration (find slow requests)
- Filter by tags
- View service graph

## Storage Usage

### Current Usage

```bash
# Check PVC usage
kubectl exec -n observability deployment/tempo -- df -h /var/tempo
kubectl exec -n observability deployment/loki -- df -h /loki
```

### Adjust Retention

**Tempo** (edit tempo-deployment.yaml):
```yaml
compactor:
  compaction:
    block_retention: 168h  # Change to 336h for 14 days
```

**Loki** (edit loki-deployment.yaml):
```yaml
limits_config:
  retention_period: 720h  # Change to 1440h for 60 days
```

Apply changes:
```bash
kubectl apply -f manifests/10-observability/
kubectl rollout restart -n observability deployment/tempo deployment/loki
```

## Troubleshooting

### Promtail Not Collecting Logs

**Check permissions:**
```bash
kubectl logs -n observability daemonset/promtail | grep -i error
```

**Common issues:**
- HostPath `/var/log/pods` not accessible (expected in kind)
- ServiceAccount missing RBAC permissions (check ClusterRole)

**Solution for kind:**
Promtail should work out of the box in kind since it uses Docker logging.

### Loki Out of Memory

**Symptoms:**
- Pod restarting (OOMKilled)
- Slow queries

**Solutions:**
```bash
# Increase memory limits
kubectl edit deployment loki -n observability
# Change limits.memory: 2Gi → 4Gi

# Or reduce retention
# Edit loki-deployment.yaml retention_period: 720h → 168h
```

### Tempo Queries Slow

**Check storage:**
```bash
kubectl exec -n observability deployment/tempo -- ls -lh /var/tempo/traces
```

**Optimize:**
- Local disk sufficient for homelab
- For production, consider S3-compatible storage

### Missing Logs in Grafana

**Verify Promtail → Loki flow:**
```bash
# Check Promtail is sending
kubectl logs -n observability -l app=promtail --tail=50 | grep "POST"

# Check Loki is receiving
kubectl logs -n observability deployment/loki --tail=50 | grep "push"

# Query Loki directly
kubectl exec -n observability deployment/loki -- \
  wget -qO- 'http://localhost:3100/loki/api/v1/label/namespace/values' | jq
```

## Performance Tuning

### Low Log Volume

For homelab with <100 pods:
- Default settings are fine
- Memory: 512Mi is sufficient

### High Log Volume

If you have >100 pods or verbose logging:

**Loki:**
```yaml
limits_config:
  ingestion_rate_mb: 32  # Increase from 16
  ingestion_burst_size_mb: 64  # Increase from 32
```

**Promtail:**
```yaml
# Add batch size config
clients:
  - url: http://loki.observability:3100/loki/api/v1/push
    batchwait: 1s
    batchsize: 1048576  # 1MB batches
```

## Next Steps

1. **Import Grafana Dashboards**:
   - Dashboard 14981: Loki & Promtail
   - Dashboard 15141: Kubernetes Logs (Loki)

2. **Instrument Applications**:
   - Add OTel SDK to apps
   - Send traces to OTel Collector
   - See traces appear in Tempo

3. **Create Alerts** (optional):
   - Alert on specific log patterns in Loki
   - Alert on high error rates in traces

## Resources

- **Tempo**: ~100m CPU, ~512Mi memory idle
- **Loki**: ~100m CPU, ~512Mi memory idle
- **Promtail**: ~50m CPU, ~128Mi memory per node (3 nodes = ~150m CPU, ~384Mi total)
- **Total**: ~350m CPU, ~1.5Gi memory

## Related

- **OTel Collector**: Telemetry receiver (manifests/09-opentelemetry/)
- **Prometheus**: Metrics storage (manifests/08-monitoring/)
- **Grafana**: Unified visualization (manifests/08-monitoring/)
