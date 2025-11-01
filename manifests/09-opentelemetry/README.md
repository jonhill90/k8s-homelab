# OpenTelemetry Collector

OpenTelemetry Collector receives, processes, and exports telemetry data (traces, metrics, logs) from applications to backend systems.

## Components

- **OTel Collector**: Gateway deployment for centralized telemetry processing
  - Receives OTLP over gRPC (port 4317) and HTTP (port 4318)
  - Exports traces to Tempo
  - Exports logs to Loki
  - Exports metrics to Prometheus

## Deployment

```bash
# Deploy OTel Collector
kubectl apply -f manifests/09-opentelemetry/

# Verify deployment
kubectl get pods -n opentelemetry
kubectl logs -n opentelemetry deployment/otel-collector

# Check service endpoints
kubectl get svc -n opentelemetry
```

## Configuration

The OTel Collector is configured via ConfigMap (`otel-collector-configmap.yaml`) with three pipelines:

1. **Traces Pipeline**: OTLP receiver → Tempo exporter
2. **Logs Pipeline**: OTLP receiver → Loki exporter
3. **Metrics Pipeline**: OTLP + Prometheus receivers → Prometheus exporter

## Usage

Applications send telemetry to the collector:

```yaml
# Example: Configure app to send traces
env:
- name: OTEL_EXPORTER_OTLP_ENDPOINT
  value: "http://otel-collector.opentelemetry:4318"
```

## Resources

- CPU: 100m request, 500m limit
- Memory: 256Mi request, 1Gi limit
- No persistent storage (stateless)

## Endpoints

- `otel-collector.opentelemetry:4317` - OTLP gRPC
- `otel-collector.opentelemetry:4318` - OTLP HTTP
- `otel-collector.opentelemetry:8888` - Metrics (Prometheus scrape)

## Verification

```bash
# Check collector health
kubectl exec -n opentelemetry deployment/otel-collector -- \
  wget -qO- http://localhost:13133/

# Send test span
kubectl run otel-test --rm -it --image=curlimages/curl --restart=Never -- \
  curl -X POST http://otel-collector.opentelemetry:4318/v1/traces \
  -H "Content-Type: application/json" \
  -d '{"resourceSpans":[{"scopeSpans":[{"spans":[{"name":"test"}]}]}]}'
```

## Related

- **Tempo**: Trace storage backend (manifests/10-observability/tempo-*)
- **Loki**: Log storage backend (manifests/10-observability/loki-*)
- **Prometheus**: Metrics storage (already deployed in manifests/08-monitoring/)
