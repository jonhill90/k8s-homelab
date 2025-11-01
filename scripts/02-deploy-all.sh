#!/bin/bash
set -e

echo "================================================"
echo "Homelab v2 - Deploy All Services"
echo "================================================"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# 1. Create namespaces
echo ""
echo "Step 1: Creating namespaces..."
kubectl apply -f manifests/00-namespaces/

# 2. Install cert-manager
echo ""
echo "Step 2: Installing cert-manager v1.13.2..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.yaml

echo "Waiting for cert-manager to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s

# 3. Configure three-tier PKI
echo ""
echo "Step 3: Configuring three-tier PKI..."
echo "  - Creating bootstrap issuer..."
kubectl apply -f manifests/01-cert-manager/00-bootstrap-issuer.yaml
sleep 2

echo "  - Creating root CA (10 years)..."
kubectl apply -f manifests/01-cert-manager/01-root-ca.yaml
echo "  - Waiting for root CA certificate..."
kubectl wait --for=condition=ready certificate root-ca -n cert-manager --timeout=60s

echo "  - Creating intermediate CA (5 years)..."
kubectl apply -f manifests/01-cert-manager/02-intermediate-ca.yaml
echo "  - Waiting for intermediate CA certificate..."
kubectl wait --for=condition=ready certificate intermediate-ca -n cert-manager --timeout=60s

echo "  - Creating final cluster issuer..."
kubectl apply -f manifests/01-cert-manager/03-cluster-issuer.yaml
sleep 2

# 4. Install nginx-ingress
echo ""
echo "Step 4: Installing nginx-ingress..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

echo "Patching ingress controller with nodeSelector..."
kubectl patch deployment ingress-nginx-controller -n ingress-nginx -p '{"spec":{"template":{"spec":{"nodeSelector":{"ingress-ready":"true"}}}}}'

echo "Waiting for nginx-ingress to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=controller -n ingress-nginx --timeout=300s

# 5. Deploy Kubernetes Dashboard
echo ""
echo "Step 5: Deploying Kubernetes Dashboard..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml

echo "Waiting for Dashboard to be ready..."
kubectl wait --for=condition=ready pod -l k8s-app=kubernetes-dashboard -n kubernetes-dashboard --timeout=300s

echo "Creating Dashboard ingress..."
kubectl apply -f manifests/03-kubernetes-dashboard/ingress.yaml

echo "Waiting for Dashboard certificate..."
kubectl wait --for=condition=ready certificate dashboard-tls -n kubernetes-dashboard --timeout=120s

# 6. Deploy whoami test app
echo ""
echo "Step 6: Deploying whoami test app..."
kubectl apply -f manifests/04-whoami/

echo "Waiting for whoami pods to be ready..."
kubectl wait --for=condition=ready pod -l app=whoami -n default --timeout=120s

echo "Waiting for whoami certificate..."
kubectl wait --for=condition=ready certificate whoami-tls -n default --timeout=120s

# 7. Deploy Portainer
echo ""
echo "Step 7: Deploying Portainer..."
kubectl apply -f manifests/06-portainer/

echo "Waiting for Portainer pod to be ready..."
kubectl wait --for=condition=ready pod -l app=portainer -n portainer --timeout=180s

echo "Waiting for Portainer certificate..."
kubectl wait --for=condition=ready certificate portainer-tls -n portainer --timeout=120s

# 8. Install metrics-server
echo ""
echo "Step 8: Installing metrics-server..."
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

echo "Patching metrics-server for kind cluster..."
kubectl patch deployment metrics-server -n kube-system -p '{"spec":{"template":{"spec":{"containers":[{"name":"metrics-server","args":["--cert-dir=/tmp","--secure-port=10250","--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname","--kubelet-use-node-status-port","--metric-resolution=15s","--kubelet-insecure-tls"]}]}}}}'

echo "Waiting for metrics-server to be ready..."
kubectl wait --for=condition=ready pod -l k8s-app=metrics-server -n kube-system --timeout=120s

# 9. Deploy monitoring stack (Prometheus + Grafana)
echo ""
echo "Step 9: Deploying monitoring stack..."
kubectl apply -f manifests/08-monitoring/namespace.yaml
kubectl apply -f manifests/08-monitoring/prometheus-deployment.yaml
kubectl apply -f manifests/08-monitoring/prometheus-service.yaml
kubectl apply -f manifests/08-monitoring/prometheus-ingress.yaml
kubectl apply -f manifests/08-monitoring/grafana-deployment.yaml
kubectl apply -f manifests/08-monitoring/grafana-service.yaml
kubectl apply -f manifests/08-monitoring/grafana-ingress.yaml

echo "Waiting for Prometheus to be ready..."
kubectl wait --for=condition=ready pod -l app=prometheus -n monitoring --timeout=180s

echo "Waiting for Grafana to be ready..."
kubectl wait --for=condition=ready pod -l app=grafana -n monitoring --timeout=180s

echo "Waiting for monitoring certificates..."
kubectl wait --for=condition=ready certificate prometheus-tls -n monitoring --timeout=120s
kubectl wait --for=condition=ready certificate grafana-tls -n monitoring --timeout=120s

# Summary
echo ""
echo "================================================"
echo "Deployment Complete!"
echo "================================================"
echo ""
kubectl get nodes
echo ""
kubectl get pods -A
echo ""
kubectl get certificate -A
echo ""
kubectl get ingress -A
echo ""
echo "✅ All services deployed successfully!"
echo ""
echo "Next steps:"
echo "1. Run ./scripts/03-export-root-ca.sh to export root CA"
echo "2. Export kubeconfig to Mac workstation"
echo "3. Trust root CA on Mac and Windows"
echo "4. Add hosts entries on Mac"
echo "5. Access services:"
echo "   - https://dashboard.homelab.local"
echo "   - https://whoami.homelab.local"
echo "   - https://portainer.homelab.local"
echo "   - https://prometheus.homelab.local"
echo "   - https://grafana.homelab.local (admin/admin)"
