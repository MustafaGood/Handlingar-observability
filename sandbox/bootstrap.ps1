# Windows entrypoint for the reference sandbox. Mirrors bootstrap.sh.
$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Cluster = if ($env:CLUSTER) { $env:CLUSTER } else { "handlingar-obs" }

$required = @(
  "SANDBOX_DB_PASSWORD",
  "SANDBOX_REDIS_PASSWORD",
  "SANDBOX_GRAFANA_USER",
  "SANDBOX_GRAFANA_PASSWORD",
  "SANDBOX_ALERT_FROM",
  "SANDBOX_ALERT_TO"
)
foreach ($name in $required) {
  if (-not [Environment]::GetEnvironmentVariable($name)) {
    throw "set $name"
  }
}

foreach ($cmd in @("docker", "k3d", "kubectl", "helm", "cilium")) {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
    throw "missing command: $cmd"
  }
}

$existing = k3d cluster list 2>$null | Out-String
if ($existing -match "(?m)^$Cluster\b") {
  throw "cluster $Cluster already exists; delete with: k3d cluster delete $Cluster"
}

Write-Host "Creating k3d cluster $Cluster..."
k3d cluster create $Cluster `
  --image rancher/k3s:v1.32.4-k3s1 `
  --servers 1 `
  --agents 0 `
  --k3s-arg "--flannel-backend=none@server:0" `
  --k3s-arg "--disable-network-policy@server:0" `
  --k3s-arg "--disable=traefik@server:0" `
  --k3s-arg "--disable=metrics-server@server:0" `
  --wait

Write-Host "Installing Cilium..."
cilium install --version 1.17.2 --wait
kubectl -n kube-system rollout status daemonset/cilium --timeout=5m

helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ | Out-Null
helm repo add traefik https://traefik.github.io/charts | Out-Null
helm repo add jetstack https://charts.jetstack.io | Out-Null
helm repo add argo https://argoproj.github.io/argo-helm | Out-Null
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts | Out-Null
helm repo add grafana https://grafana.github.io/helm-charts | Out-Null
helm repo update

helm upgrade --install metrics-server metrics-server/metrics-server `
  --namespace kube-system `
  '--set' 'args={--kubelet-insecure-tls}' `
  --wait

helm upgrade --install traefik traefik/traefik `
  --namespace traefik --create-namespace `
  '--set' 'ingressClass.enabled=true' `
  '--set' 'providers.kubernetesCRD.enabled=true' `
  '--set' 'metrics.prometheus.enabled=true' `
  '--set' 'ports.metrics.expose.default=true' `
  --wait

helm upgrade --install cert-manager jetstack/cert-manager `
  --namespace cert-manager --create-namespace `
  '--set' 'crds.enabled=true' `
  '--set' 'prometheus.enabled=true' `
  --wait

helm upgrade --install argo-cd argo/argo-cd `
  --namespace argocd --create-namespace `
  '--set' 'configs.params.server.insecure=true' `
  '--set' 'redis.enabled=true' `
  '--set' 'dex.enabled=false' `
  '--set' 'notifications.enabled=false' `
  '--set' 'applicationSet.enabled=false' `
  --wait --timeout 10m

kubectl apply -f (Join-Path $Root "sandbox\issuer.yaml")

foreach ($ns in @("handlingar", "tst", "qat", "handlingar-preview", "observability")) {
  kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f -
}

function New-DatastoreSecret([string]$ns) {
  kubectl -n $ns create secret generic datastore `
    --from-literal=postgres-password=$env:SANDBOX_DB_PASSWORD `
    --from-literal=redis-password=$env:SANDBOX_REDIS_PASSWORD `
    --dry-run=client -o yaml | kubectl apply -f -
}
New-DatastoreSecret handlingar
New-DatastoreSecret tst

kubectl apply -f (Join-Path $Root "sandbox\workloads.yaml")
kubectl apply -f (Join-Path $Root "sandbox\app-netpol.yaml")
kubectl apply -f (Join-Path $Root "proposals\netpol-allow-prometheus-scrape.yaml")

kubectl -n observability create secret generic grafana-admin `
  --from-literal=admin-user=$env:SANDBOX_GRAFANA_USER `
  --from-literal=admin-password=$env:SANDBOX_GRAFANA_PASSWORD `
  --dry-run=client -o yaml | kubectl apply -f -

$dsn = "postgresql://postgres:$($env:SANDBOX_DB_PASSWORD)@postgres.handlingar.svc.cluster.local:5432/postgres?sslmode=disable"
kubectl -n observability create secret generic postgres-exporter-dsn `
  --from-literal=dsn=$dsn `
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n observability create secret generic redis-exporter `
  --from-literal=password=$env:SANDBOX_REDIS_PASSWORD `
  --dry-run=client -o yaml | kubectl apply -f -

$alertYaml = @"
global:
  resolve_timeout: 5m
  smtp_smarthost: mailpit.handlingar.svc.cluster.local:1025
  smtp_from: $($env:SANDBOX_ALERT_FROM)
  smtp_require_tls: false
route:
  receiver: email
receivers:
  - name: email
    email_configs:
      - to: $($env:SANDBOX_ALERT_TO)
        send_resolved: true
"@
$alertFile = Join-Path $env:TEMP "alertmanager-sandbox.yaml"
Set-Content -Path $alertFile -Value $alertYaml -Encoding utf8
kubectl -n observability create secret generic alertmanager-kube-prometheus-stack-alertmanager `
  --from-file=alertmanager.yaml=$alertFile `
  --dry-run=client -o yaml | kubectl apply -f -

Write-Host "Installing observability charts..."
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack `
  --version 91.9.0 `
  --namespace observability `
  -f (Join-Path $Root "values-kube-prometheus-stack.yaml") `
  --wait --timeout 15m

helm upgrade --install loki grafana/loki `
  --version 7.3.0 `
  --namespace observability `
  -f (Join-Path $Root "values-loki.yaml") `
  --wait --timeout 10m

helm upgrade --install alloy grafana/alloy `
  --version 1.13.0 `
  --namespace observability `
  -f (Join-Path $Root "values-alloy.yaml") `
  --wait --timeout 10m

helm upgrade --install blackbox-exporter prometheus-community/prometheus-blackbox-exporter `
  --version 11.19.1 `
  --namespace observability `
  -f (Join-Path $Root "values-blackbox-exporter.yaml") `
  -f (Join-Path $Root "sandbox\values-blackbox.yaml") `
  --wait --timeout 10m

helm upgrade --install postgres-exporter prometheus-community/prometheus-postgres-exporter `
  --version 8.2.0 `
  --namespace observability `
  -f (Join-Path $Root "values-postgres-exporter.yaml") `
  --wait --timeout 10m

helm upgrade --install redis-exporter prometheus-community/prometheus-redis-exporter `
  --version 6.33.0 `
  --namespace observability `
  -f (Join-Path $Root "values-redis-exporter.yaml") `
  --wait --timeout 10m

helm upgrade --install memcached-exporter prometheus-community/prometheus-memcached-exporter `
  --version 0.6.0 `
  --namespace observability `
  -f (Join-Path $Root "values-memcached-exporter.yaml") `
  --wait --timeout 10m

# Apply local manifests. Skip ExternalSecret (no ESO in the sandbox).
$manifestFiles = @(
  "manifests\namespace.yaml",
  "manifests\networkpolicy.yaml",
  "manifests\ingressroute-grafana.yaml",
  "manifests\certificate-grafana.yaml",
  "manifests\servicemonitors.yaml",
  "alerts\rules.yaml"
)
foreach ($rel in $manifestFiles) {
  kubectl apply -f (Join-Path $Root $rel)
}
# Dashboard ConfigMaps (and anything else kustomize owns except ExternalSecret).
kubectl apply -k $Root 2>$null

Write-Host "Sandbox ready. Check: kubectl -n observability get pods"
Write-Host "Footprint: kubectl -n observability top pods"
Write-Host "Exit test: make obs-alert-test  (then make obs-alert-restore)"

