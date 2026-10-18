# Resource footprint

- **Status:** measured on sandbox `handlingar-obs` (k3d, 1 server node)
- **Date:** 2026-10-18
- **Budget:** 1.5 vCPU and 3 GB memory requests for the whole stack

## Result

Request sum on the running sandbox: **about 760m CPU and 2592 MiB memory**.
That is under the 1.5 vCPU / 3 GB budget (DaemonSets counted once on this
single-node sandbox; on 3 workers Alloy and node-exporter scale to ×3 and the
request sum stays under budget per the ADR table).

Live usage at measurement time was far below requests (Prometheus ~7m/339Mi,
Grafana ~12m/384Mi, Loki ~6m/120Mi).

## How to measure

After `sandbox/bootstrap.sh` (or `bootstrap.ps1`) finishes and the pods are Ready:

```bash
kubectl -n observability top pods
kubectl top nodes
kubectl -n observability get pvc
```

## Request budget (ADR)

| Component | CPU request | Memory request |
| --- | --- | --- |
| Prometheus | 200m | 1 GiB |
| Prometheus Operator | 50m | 128 MiB |
| Alertmanager | 50m | 128 MiB |
| Grafana | 100m | 256 MiB |
| kube-state-metrics | 50m | 128 MiB |
| node-exporter ×3 | 150m | 192 MiB |
| Alloy ×3 | 150m | 384 MiB |
| Loki | 100m | 384 MiB |
| blackbox exporter | 20m | 64 MiB |
| Postgres exporter | 20m | 64 MiB |
| Redis exporter | 20m | 64 MiB |
| Memcached exporter | 20m | 64 MiB |
| **Sum (3 workers)** | **about 980m** | **about 2.9 GiB** |

## Measured usage (2026-10-18, single-node sandbox)

| Pod | CPU | Memory | Restarts | Notes |
| --- | --- | --- | --- | --- |
| prometheus-…-0 | 7m | 339Mi | 0 | PVC 10Gi Bound |
| grafana-… | 12m | 384Mi | 0 | |
| loki-0 | 6m | 120Mi | 0 | PVC 10Gi Bound |
| alertmanager-…-0 | 1m | 43Mi | 0 | |
| alloy-… | 4m | 42Mi | 0 | DaemonSet |
| node-exporter-… | 1m | 10Mi | 0 | DaemonSet |
| operator-… | 3m | 47Mi | 0 | |
| blackbox-exporter-… | 1m | 14Mi | 0 | |
| postgres-exporter-… | 1m | 8Mi | 0 | |
| redis-exporter-… | 2m | 8Mi | 0 | |
| memcached-exporter-… | 1m | 7Mi | 0 | |
| kube-state-metrics-… | (flapping) | — | probes | See note below |

**kube-state-metrics:** under default-deny on k3d+Cilium, kubelet probes to the
pod IP timed out. Values set `hostNetwork: true` so probes hit the host
namespace. Re-run `helm upgrade` after that change if the pod is still
CrashLoopBackOff.

## Disk

| PVC | Size | Status |
| --- | --- | --- |
| prometheus-…-db-… | 10Gi | Bound |
| storage-loki-0 | 10Gi | Bound |
