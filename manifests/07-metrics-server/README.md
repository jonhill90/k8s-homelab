# Metrics Server

Metrics Server is a scalable, efficient source of container resource metrics for Kubernetes built-in autoscaling pipelines.

## Purpose

Metrics Server collects resource metrics from Kubelets and exposes them in Kubernetes apiserver through Metrics API for use by:
- `kubectl top` commands
- Horizontal Pod Autoscaler (HPA)
- Vertical Pod Autoscaler (VPA)

## Installation

Metrics Server requires special configuration for kind clusters due to self-signed certificates:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch deployment metrics-server -n kube-system -p '{"spec":{"template":{"spec":{"containers":[{"name":"metrics-server","args":["--cert-dir=/tmp","--secure-port=10250","--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname","--kubelet-use-node-status-port","--metric-resolution=15s","--kubelet-insecure-tls"]}]}}}}'
```

## Verification

```bash
# Wait for metrics-server to be ready
kubectl wait --for=condition=ready pod -l k8s-app=metrics-server -n kube-system --timeout=60s

# Test kubectl top
kubectl top nodes
kubectl top pods -A
```

## Why in kube-system namespace?

Metrics Server is deployed to `kube-system` namespace by the official manifest as it's a core cluster component. We create a separate namespace manifest for consistency but use `kube-system` for actual deployment.
