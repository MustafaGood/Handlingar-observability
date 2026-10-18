#!/usr/bin/env bash
# Render T2 without a cluster. Fails if a chart or the manifest set is invalid.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HELM="${HELM:-helm}"

render() {
  local release="$1"
  local chart="$2"
  local version="$3"
  local values="$4"
  echo "render ${release} ${version}"
  "$HELM" template "$release" "$chart" --version "$version" \
    --namespace observability \
    -f "$ROOT/$values" >/dev/null
}

render kube-prometheus-stack prometheus-community/kube-prometheus-stack 91.9.0 values-kube-prometheus-stack.yaml
render loki grafana/loki 7.3.0 values-loki.yaml
render alloy grafana/alloy 1.13.0 values-alloy.yaml
render blackbox-exporter prometheus-community/prometheus-blackbox-exporter 11.19.1 values-blackbox-exporter.yaml
render postgres-exporter prometheus-community/prometheus-postgres-exporter 8.2.0 values-postgres-exporter.yaml
render redis-exporter prometheus-community/prometheus-redis-exporter 6.33.0 values-redis-exporter.yaml
render memcached-exporter prometheus-community/prometheus-memcached-exporter 0.6.0 values-memcached-exporter.yaml

echo "check alerts"
if command -v python3 >/dev/null 2>&1; then
  python3 "$ROOT/scripts/check-alerts.py"
elif command -v python >/dev/null 2>&1; then
  python "$ROOT/scripts/check-alerts.py"
else
  echo "python is required to check alerts" >&2
  exit 1
fi

echo "check runbook"
if command -v python3 >/dev/null 2>&1; then
  python3 "$ROOT/scripts/check-runbook.py"
elif command -v python >/dev/null 2>&1; then
  python "$ROOT/scripts/check-runbook.py"
else
  echo "python is required to check the runbook" >&2
  exit 1
fi

echo "check legacy plan"
if command -v python3 >/dev/null 2>&1; then
  python3 "$ROOT/scripts/check-legacy-plan.py"
elif command -v python >/dev/null 2>&1; then
  python "$ROOT/scripts/check-legacy-plan.py"
else
  echo "python is required to check the legacy plan" >&2
  exit 1
fi

echo "check dashboards"
if command -v python3 >/dev/null 2>&1; then
  python3 "$ROOT/scripts/check-dashboards.py"
elif command -v python >/dev/null 2>&1; then
  python "$ROOT/scripts/check-dashboards.py"
else
  echo "python is required to check dashboards" >&2
  exit 1
fi

echo "render manifests"
rendered="$(kubectl kustomize "$ROOT")"
for needle in "kind: IngressRoute" "kind: PrometheusRule" "grafana_dashboard" "kind: ExternalSecret"; do
  case "$rendered" in
    *"$needle"*) ;;
    *) echo "missing ${needle}" >&2; exit 1 ;;
  esac
done
echo "ok"
