# handlingar-observability

Observability package for the handlingar.se K3s cluster: metrics, logs, and
email alerts. The supervisor copies this repository into
`infra/k8s/observability/` after review.

## Status

| Piece | State |
| --- | --- |
| ADR | proposed (numbers measured; awaiting supervisor accept) |
| Measured CPU and memory | measured, about 760m / 2592Mi requests, under budget |
| Helm values and manifests | installed and verified on sandbox `handlingar-obs` |
| Dashboards | six JSON files provisioned in live Grafana |
| Alerts | YAML rules; SiteDown to Mailpit exercised and restored |
| Runbook | written; exit scenario exercised (R5 / SiteDown) |
| Legacy server plan | written (T6), not a deployment |
| Sandbox | recreatable via `sandbox/bootstrap.sh` or `bootstrap.ps1` |

Decision: [docs/adr-observability-stack.md](docs/adr-observability-stack.md)

Runbook: [docs/runbook-troubleshooting.md](docs/runbook-troubleshooting.md)

Legacy server plan: [docs/plan-legacy-prod.md](docs/plan-legacy-prod.md)

Footprint: [docs/resource-footprint.md](docs/resource-footprint.md)

Alert test: [docs/alert-test.md](docs/alert-test.md)

## Charts

Install each chart in namespace `observability` with the release name in the
first column. Grafana is inside `kube-prometheus-stack`, not its own release.

| Release | Chart | Version | Values | Repository |
| --- | --- | --- | --- | --- |
| `kube-prometheus-stack` | `kube-prometheus-stack` | 91.9.0 | `values-kube-prometheus-stack.yaml` | `https://prometheus-community.github.io/helm-charts` |
| `loki` | `loki` | 7.3.0 | `values-loki.yaml` | `https://grafana.github.io/helm-charts` |
| `alloy` | `alloy` | 1.13.0 | `values-alloy.yaml` | `https://grafana.github.io/helm-charts` |
| `blackbox-exporter` | `prometheus-blackbox-exporter` | 11.19.1 | `values-blackbox-exporter.yaml` | `https://prometheus-community.github.io/helm-charts` |
| `postgres-exporter` | `prometheus-postgres-exporter` | 8.2.0 | `values-postgres-exporter.yaml` | `https://prometheus-community.github.io/helm-charts` |
| `redis-exporter` | `prometheus-redis-exporter` | 6.33.0 | `values-redis-exporter.yaml` | `https://prometheus-community.github.io/helm-charts` |
| `memcached-exporter` | `prometheus-memcached-exporter` | 0.6.0 | `values-memcached-exporter.yaml` | `https://prometheus-community.github.io/helm-charts` |

## DNS to approve before apply

| Name | Type | Value |
| --- | --- | --- |
| `grafana.nonprod.handlingar.se` | CNAME or A, created by external-dns from the IngressRoute | the Traefik load balancer |

No other name is created by this package.

## Secrets

Created by the supervisor from the ExternalSecret templates. This repo has no
secret values.

| Secret | Template |
| --- | --- |
| `grafana-admin` | `manifests/externalsecret-grafana-admin.yaml` |
| Alertmanager config | `manifests/externalsecret-alert-email.yaml` |
| `postgres-exporter-dsn` key `dsn` | `manifests/externalsecret-postgres-exporter.yaml` |
| `redis-exporter` key `password` | `manifests/externalsecret-redis-exporter.yaml` |

The store name in the templates is `cluster-secret-store`.

## Local manifests

```bash
kubectl apply -k .
```

`proposals/` is not applied by that command. See each file for what breaks if
it is skipped. On a cluster without External Secrets Operator, skip
`ExternalSecret` objects (the sandbox bootstrap does this automatically).

## Make targets

`make obs-up`, `make obs-status`, `make obs-alert-test`, `make obs-alert-restore`,
`make obs-down`.

Helm releases are installed by `sandbox/bootstrap.sh` (or `bootstrap.ps1`).
`make obs-up` applies the local manifests only.

Suggested Make targets for the platform repo after integration: `obs-up`,
`obs-status`, `obs-alert-test`, `obs-down`.

## Uninstall

Helm uninstall removes the releases. `make obs-down` removes the local
manifests. PersistentVolumeClaims for Prometheus and Loki are kept.

## Sandbox verification (2026-10-18)

- Cluster: k3d `handlingar-obs`, K3s v1.32.4, Cilium 1.17.2
- Dashboards in Grafana: Overview, Alaveteli, Backing services, Cluster, Mail, Logs
- Datasources: Prometheus, Loki, Alertmanager
- Exit test: scale `tst/alaveteli-web` to 0, SiteDown mail in Mailpit, then restore
- Loki: Alloy tails `/var/log/pods/*/*/*.log` (59 active files); labels
  `namespace`, `pod`, `container`
- NetworkPolicy: default-deny in `observability` with explicit allows + Cilium
  host probes; app scrape proposals in `proposals/`
