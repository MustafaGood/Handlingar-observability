#!/usr/bin/env bash
# Recreate the reference sandbox: K3s v1.32 + Cilium + Traefik + cert-manager
# + Alaveteli-shaped workloads + the observability package.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLUSTER="${CLUSTER:-handlingar-obs}"

: "${SANDBOX_DB_PASSWORD:?set SANDBOX_DB_PASSWORD}"
: "${SANDBOX_REDIS_PASSWORD:?set SANDBOX_REDIS_PASSWORD}"
: "${SANDBOX_GRAFANA_USER:?set SANDBOX_GRAFANA_USER}"
: "${SANDBOX_GRAFANA_PASSWORD:?set SANDBOX_GRAFANA_PASSWORD}"
: "${SANDBOX_ALERT_FROM:?set SANDBOX_ALERT_FROM}"
: "${SANDBOX_ALERT_TO:?set SANDBOX_ALERT_TO}"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing command: $1" >&2
    exit 1
  }
}

need docker
need k3d
need kubectl
need helm
need cilium

if k3d cluster list 2>/dev/null | grep -q "^${CLUSTER}"; then
  echo "cluster ${CLUSTER} already exists; delete with: k3d cluster delete ${CLUSTER}"
  exit 1
fi

k3d cluster create "$CLUSTER" \
  --image rancher/k3s:v1.32.4-k3s1 \
  --servers 1 \
  --agents 0 \
  --k3s-arg "--flannel-backend=none@server:0" \
  --k3s-arg "--disable-network-policy@server:0" \
  --k3s-arg "--disable=traefik@server:0" \
  --k3s-arg "--disable=metrics-server@server:0" \
  --wait

cilium install --version 1.17.2 --wait
kubectl -n kube-system rollout status daemonset/cilium --timeout=5m

# Metrics-server so kubectl top works for the footprint report.
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo add traefik https://traefik.github.io/charts
helm repo add jetstack https://charts.jetstack.io
helm repo add argo https://argoproj.github.io/argo-helm
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm upgrade --install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  --set args={--kubelet-insecure-tls} \
  --wait

helm upgrade --install traefik traefik/traefik \
  --namespace traefik --create-namespace \
  --set ingressClass.enabled=true \
  --set providers.kubernetesCRD.enabled=true \
  --set metrics.prometheus.enabled=true \
  --set ports.metrics.expose.default=true \
  --wait

helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set crds.enabled=true \
  --set prometheus.enabled=true \
  --wait

# Minimal Argo CD so ServiceMonitors and the Argo alert have a live target.
helm upgrade --install argo-cd argo/argo-cd \
  --namespace argocd --create-namespace \
  --set configs.params."server\.insecure"=true \
  --set redis.enabled=true \
  --set dex.enabled=false \
  --set notifications.enabled=false \
  --set applicationSet.enabled=false \
  --wait --timeout 10m

kubectl apply -f "$ROOT/sandbox/issuer.yaml"

for ns in handlingar tst qat handlingar-preview observability; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done

create_datastore_secret() {
  local ns="$1"
  kubectl -n "$ns" create secret generic datastore \
    --from-literal=postgres-password="$SANDBOX_DB_PASSWORD" \
    --from-literal=redis-password="$SANDBOX_REDIS_PASSWORD" \
    --dry-run=client -o yaml | kubectl apply -f -
}

create_datastore_secret handlingar
create_datastore_secret tst

kubectl apply -f "$ROOT/sandbox/workloads.yaml"
kubectl apply -f "$ROOT/sandbox/app-netpol.yaml"
kubectl apply -f "$ROOT/proposals/netpol-allow-prometheus-scrape.yaml"

kubectl -n observability create secret generic grafana-admin \
  --from-literal=admin-user="$SANDBOX_GRAFANA_USER" \
  --from-literal=admin-password="$SANDBOX_GRAFANA_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n observability create secret generic postgres-exporter-dsn \
  --from-literal=dsn="postgresql://postgres:${SANDBOX_DB_PASSWORD}@postgres.handlingar.svc.cluster.local:5432/postgres?sslmode=disable" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n observability create secret generic redis-exporter \
  --from-literal=password="$SANDBOX_REDIS_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

# Alertmanager reads this secret. The name must match the chart.
kubectl -n observability create secret generic alertmanager-kube-prometheus-stack-alertmanager \
  --from-literal=alertmanager.yaml="$(cat <<EOF
global:
  resolve_timeout: 5m
  smtp_smarthost: mailpit.handlingar.svc.cluster.local:1025
  smtp_from: ${SANDBOX_ALERT_FROM}
  smtp_require_tls: false
route:
  receiver: email
receivers:
  - name: email
    email_configs:
      - to: ${SANDBOX_ALERT_TO}
        send_resolved: true
EOF
)" \
  --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --version 91.9.0 \
  --namespace observability \
  -f "$ROOT/values-kube-prometheus-stack.yaml" \
  --wait --timeout 15m

helm upgrade --install loki grafana/loki \
  --version 7.3.0 \
  --namespace observability \
  -f "$ROOT/values-loki.yaml" \
  --wait --timeout 10m

helm upgrade --install alloy grafana/alloy \
  --version 1.13.0 \
  --namespace observability \
  -f "$ROOT/values-alloy.yaml" \
  --wait --timeout 10m

helm upgrade --install blackbox-exporter prometheus-community/prometheus-blackbox-exporter \
  --version 11.19.1 \
  --namespace observability \
  -f "$ROOT/values-blackbox-exporter.yaml" \
  -f "$ROOT/sandbox/values-blackbox.yaml" \
  --wait --timeout 10m

helm upgrade --install postgres-exporter prometheus-community/prometheus-postgres-exporter \
  --version 8.2.0 \
  --namespace observability \
  -f "$ROOT/values-postgres-exporter.yaml" \
  --wait --timeout 10m

helm upgrade --install redis-exporter prometheus-community/prometheus-redis-exporter \
  --version 6.33.0 \
  --namespace observability \
  -f "$ROOT/values-redis-exporter.yaml" \
  --wait --timeout 10m

helm upgrade --install memcached-exporter prometheus-community/prometheus-memcached-exporter \
  --version 0.6.0 \
  --namespace observability \
  -f "$ROOT/values-memcached-exporter.yaml" \
  --wait --timeout 10m

# Skip ExternalSecret. The sandbox creates those Secrets directly, and the
# External Secrets operator is not installed here.
kubectl kustomize "$ROOT" | awk '
  function flush() {
    if (buf != "" && buf !~ /kind: ExternalSecret/) printf "%s", buf
  }
  BEGIN { buf = "" }
  /^---$/ { flush(); buf = $0 ORS; next }
  { buf = buf $0 ORS }
  END { flush() }
' | kubectl apply -f -

echo "Sandbox ready. Check: kubectl -n observability get pods"
echo "Footprint: kubectl -n observability top pods"
echo "Exit test: make obs-alert-test  (then make obs-alert-restore)"
