# ADR: Observability stack

- **Status:** proposed
- **Date:** 2026-10-05
- **Supersedes:** none
- **Superseded by:** none

The supervisor assigns the ADR number. This file is the T1 draft. It does not
install anything.

## Context

handlingar.se is moving onto a K3s cluster (`v1.32.4+k3s1`) on Hetzner Cloud.
There is no metrics, log, or alert stack. Production still runs on a single
server and is out of scope for this version.

The stack must run inside the cluster, in namespace `observability`, and fit
about **1.5 vCPU and 3 GB of memory requests** on the dev cluster (1 master
plus 3 workers, each 2 vCPU / 4 GB). One Prometheus, one Loki, and one Grafana
see every environment. Dashboards, alert rules, and Helm values live in git.
Secrets are names only; values are injected later and are never written in
this repository.

Alaveteli (`alaveteli-web`, port 3000) and Sidekiq expose no `/metrics`
endpoint today. Postgres, Redis, and Memcached have no exporters. The first
version must not wait for an application image change.

Resource numbers below are the **request budget**. Live measurement from the
sandbox (2026-10-18) is in `docs/resource-footprint.md`: about **760m CPU /
2592 MiB** requests on a single-node run, under the 1.5 vCPU / 3 GB budget.

## Decision

Run a slim **kube-prometheus-stack** (Prometheus, Grafana, Alertmanager,
node-exporter, kube-state-metrics), **Loki** as one process with files on a
volume, and **Alloy** as the log collector. Alert rules are `PrometheusRule`
objects. Alertmanager sends email. Site health for the first version comes
from Traefik metrics plus a blackbox probe, not from a change to Alaveteli.
Postgres, Redis, and Memcached exporters run as their own Deployments in
`observability` and connect over the network.

### Charts and versions

Pinned on 2026-10-05. Image tags are the tags those charts pin. No `latest`.

| Role | Chart | Version | App version | Repository |
| --- | --- | --- | --- | --- |
| Metrics, Grafana, alerts | `kube-prometheus-stack` | 91.9.0 | v0.94.1 (Prometheus Operator) | `https://prometheus-community.github.io/helm-charts` |
| Logs | `loki` | 7.3.0 | 3.6.12 | `https://grafana.github.io/helm-charts` |
| Log collector | `alloy` | 1.13.0 | v1.20.0 | `https://grafana.github.io/helm-charts` |
| Site probe | `prometheus-blackbox-exporter` | 11.19.1 | v0.28.0 | `https://prometheus-community.github.io/helm-charts` |
| Postgres | `prometheus-postgres-exporter` | 8.2.0 | v0.20.1 | `https://prometheus-community.github.io/helm-charts` |
| Redis | `prometheus-redis-exporter` | 6.33.0 | v1.93.0 | `https://prometheus-community.github.io/helm-charts` |
| Memcached | `prometheus-memcached-exporter` | 0.6.0 | v0.17.0 | `https://prometheus-community.github.io/helm-charts` |

`kube-prometheus-stack` 91.9.0 already includes Grafana chart 13.2.7,
kube-state-metrics chart 8.6.0, and prometheus-node-exporter chart 4.59.0.
Those are not separate Argo CD applications. The Windows exporter subchart is
left disabled.

### What the slim profile turns off

The full chart is too large for 3×4 GB nodes. The values file keeps the
components that satisfy the scrape list and disables the rest:

- Windows exporter.
- ServiceMonitors for the embedded control-plane processes (controller
  manager, scheduler, proxy, and the datastore). On this K3s build those
  targets stay empty and only add dead series.
- Default chart network policy. This package ships its own default-deny
  policies in `manifests/networkpolicy.yaml`.
- Extra Grafana plugins and the chart's unused default dashboard set. The
  dashboards for T3 are provisioned from this repo.

Scrape targets that must be green: kube-state-metrics, node-exporter,
kubelet/cAdvisor, Traefik, cert-manager, CoreDNS, Argo CD, blackbox, and the
three data-service exporters.

### Logs

Loki runs as a **single binary** with a filesystem volume and **14 day**
retention. Metrics stay at **30 days**, which is the platform rule. Log
retention is shorter because each worker disk is 40 GB and every application
namespace plus the platform namespaces are collected.

Alloy runs as a DaemonSet, reads container logs from the node filesystem, and
ships them to Loki. Promtail is not used: it is in maintenance, and Alloy is
the collector Grafana still ships. One collector is enough at this size.
Alloy does not need ingress from other namespaces; it does need egress to
Loki, DNS, and the API server.

Log streams are labelled `namespace`, `pod`, `container`, and `app`.

### Alerts and email

Rules are `PrometheusRule` YAML. Alertmanager routes them to email. Grafana
shows the same alerts; it does not evaluate a second copy of the rules.

The mail path is Secret `alert-smtp` (`host`, `port`, `from`, `to`). In the
sandbox that secret points at Mailpit. In the cluster it points at whatever
SMTP the supervisor injects. No address is written in git. Outbound SMTP is
the one place a Cilium `toFQDNs` rule is required, and that rule is paired
with a DNS visibility rule in the same policy.

Grafana admin login is Secret `grafana-admin`, referenced by name. An
`ExternalSecret` template is delivered with no value in it.

### Alaveteli and Sidekiq, first version

No application change. Request rate, 5xx rate, and latency come from
**Traefik** metrics, split by the ingress host for each environment. Up/down
comes from **blackbox exporter** probing `/` on each public host. Sidekiq
queue health for the first version is the Sidekiq pod's Ready condition plus
a Loki query for Sidekiq errors. A later proposal, not part of this install,
is the `yabeda-rails` and `yabeda-sidekiq` gems so the Alaveteli dashboard
can show queue depth, failed jobs, and Puma threads from a `/metrics`
endpoint.

### Postgres, Redis, and Memcached

Exporters are Deployments in `observability`, not sidecars on the database
pods. A sidecar would patch someone else's workload. A separate Deployment
needs only a NetworkPolicy proposal and a secret:

- egress from `observability` to the database port
- ingress on the application namespace from the exporter
- password via External Secrets (`postgres-exporter-dsn`, and the Redis and
  Memcached equivalents)

If those proposals are not applied, the backing-service panels stay empty.
The rest of the stack still works.

### Request budget

Requests for 3 workers. Limits are set on every container in T2. This is a
ceiling to aim at, not a measurement.

| Component | Requests | Notes |
| --- | --- | --- |
| Prometheus | 200m CPU, 1 GiB | 30 day retention, slim scrape set |
| Prometheus Operator | 50m CPU, 128 MiB | |
| Alertmanager | 50m CPU, 128 MiB | email only |
| Grafana | 100m CPU, 256 MiB | |
| kube-state-metrics | 50m CPU, 128 MiB | |
| node-exporter | 50m CPU, 64 MiB each | DaemonSet, 3 workers |
| Alloy | 50m CPU, 128 MiB each | DaemonSet, 3 workers |
| Loki | 100m CPU, 384 MiB | single binary, 14 day logs |
| blackbox exporter | 20m CPU, 64 MiB | |
| Postgres exporter | 20m CPU, 64 MiB | |
| Redis exporter | 20m CPU, 64 MiB | |
| Memcached exporter | 20m CPU, 64 MiB | |
| **Sum** | **about 980m CPU, 2.9 GiB** | under 1.5 vCPU / 3 GB |

## Alternatives considered

- **Full kube-prometheus-stack defaults.** Rejected. The extra control-plane
  scrapes, Windows exporter, and bundled dashboards do not fit the memory
  budget on 4 GB nodes.
- **Standalone Prometheus chart plus a separate Grafana chart.** Rejected.
  The operator, `ServiceMonitor` CRDs, node-exporter, kube-state-metrics, and
  Alertmanager are already one chart. A slim values file is the smaller
  change. Splitting them adds Argo CD applications without saving memory.
- **VictoriaMetrics.** Rejected. It replaces Prometheus. The platform
  assumption is Prometheus, and a second metrics database is more to run.
- **Promtail.** Rejected. Maintenance mode. Alloy replaces it.
- **Grafana Alerting as the only rule engine.** Rejected for this version.
  Alertmanager is already in the chart, and `PrometheusRule` is the form the
  alert task allows. A second evaluator would not remove Alertmanager.
- **Exporter sidecars.** Rejected for this version. They edit the Postgres,
  Redis, and Memcached workloads. Separate Deployments keep that edit out of
  those manifests.
- **`yabeda` gems in the first install.** Rejected as a blocker. The site can
  be watched from Traefik and blackbox without a new image. The gems stay a
  written proposal.
- **Metabase.** Rejected. It is a query and chart product over a database,
  not a metrics, log, and alert stack.
- **HolmesGPT or any similar automatic troubleshooter.** Rejected. Out of
  scope. Troubleshooting stays a manual runbook: a person copies a Grafana
  or Loki extract into a session after masking secrets.
- **Any hosted metrics, log, or alert service.** Rejected. The stack is
  self-hosted in the cluster. Off-site backup to Hetzner Object Storage is a
  later, optional task and is not required for this ADR.

## Measurement

Live CPU, memory, and disk are recorded in `docs/resource-footprint.md`
(2026-10-18 sandbox). The request sum stayed under budget. This ADR stays
**proposed** until the supervisor accepts the decision.

## Consequences

- T2 may start only after the supervisor accepts this ADR, or accepts it with
  named changes.
- Argo CD gets one application per chart in the table above, except Grafana,
  which rides inside `kube-prometheus-stack`. Chart name, repository URL, and
  version are the pins in that table.
- DNS `grafana.nonprod.handlingar.se` must be listed and approved before the
  IngressRoute is applied. Type and value are recorded in the package README
  at T2.
- Secrets `grafana-admin`, `alert-smtp`, and the exporter DSNs are created by
  the supervisor from ExternalSecret templates. This repo never contains the
  values.
- Scrape ingress in `handlingar`, `tst`, `qat`, and `handlingar-preview`, and
  the database NetworkPolicies, are proposals. Without them, application and
  database panels are empty. Cluster metrics and Loki still work.
- The legacy production server is not scraped. A plan for that is T6, after
  the cluster stack is done.
- The exit check stays the same: scale `alaveteli-web` in `tst` to 0 replicas,
  see the mail in Mailpit inside the alert window, and see the alert clear
  when the pod is Ready again.
