# Reference sandbox

The sandbox copies the target cluster closely enough to install this package:
K3s v1.32, Cilium, Traefik, a ClusterIssuer named `letsencrypt-prod`, Argo CD,
cert-manager with Prometheus metrics, and workloads named like Alaveteli.

## What is not the real application

A full Alaveteli process is large for a laptop. The web and Sidekiq
deployments are a small HTTP process with the same names, labels, and port
3000. Postgres, Redis, Memcached, and Mailpit are real images. The metrics
and log path for the first version does not depend on Rails.

## Run

Export these variables in the shell. Do not write the values into a file in
this repository.

- `SANDBOX_DB_PASSWORD`
- `SANDBOX_REDIS_PASSWORD`
- `SANDBOX_GRAFANA_USER`
- `SANDBOX_GRAFANA_PASSWORD`
- `SANDBOX_ALERT_FROM`
- `SANDBOX_ALERT_TO`

Commands required: `docker`, `k3d`, `kubectl`, `helm`, `cilium`.

Linux / macOS:

```bash
./sandbox/bootstrap.sh
```

Windows (PowerShell):

```powershell
.\sandbox\bootstrap.ps1
```

Delete the cluster with `k3d cluster delete handlingar-obs` when finished.
Helm uninstall leaves PVCs; deleting the k3d cluster removes them.

Blackbox probes use `sandbox/values-blackbox.yaml`, which points at the
in-cluster Services instead of the public hostnames.

The bootstrap script creates Secrets itself and skips the ExternalSecret
manifests. Those templates are for the cluster that has the External Secrets
operator.

Default-deny NetworkPolicies for `handlingar` and `tst` live in
`sandbox/app-netpol.yaml`. Scrape and exporter allows are in
`proposals/netpol-allow-prometheus-scrape.yaml`.
