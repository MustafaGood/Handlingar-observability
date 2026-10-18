# Troubleshooting with Grafana and Loki

Go from the alert mail to the dashboard, then to the Loki query, then to a
short paste. Run that paste through the repository masking tool before it
goes into a session. The supervisor links the tool. Do not paste secrets.

`<namespace>` is the namespace named in the mail. On the dashboard, set `env`
to that same namespace.

## R1 — Site down

Prerequisites: the SiteDown mail has arrived.

1. Open the Overview dashboard and set `env` to `<namespace>`.
2. Read Site up. `0` means the blackbox probe failed.
3. Open the Logs dashboard, keep the same `env`, and read Rails 5xx. The query is:

```
{namespace=~"<namespace>", app="alaveteli"} |~ "Completed 5[0-9]{2}"
```

4. Read the pod:

```bash
kubectl -n <namespace> get pods -l app=alaveteli
kubectl -n <namespace> describe pods -l app=alaveteli
```

5. After the masking tool, paste the mail summary, the `env` value, the Site up value, the Loki lines, and the kubectl output.

How to verify it worked: Site up is `1`, and SiteDown is no longer firing.

How to undo: if the web deployment was scaled down for the test, run `make obs-alert-restore`. If nothing was changed, there is nothing to undo.

## R2 — Sidekiq queue growing

Prerequisites: the SidekiqNotReady mail has arrived.

1. Open the Alaveteli dashboard and set `env` to `<namespace>`.
2. Read Sidekiq ready. Queue depth is not a metric yet. The alert means desired replicas are not available.
3. Read Sidekiq errors. The query is:

```
{namespace=~"<namespace>", app="alaveteli-sidekiq"} |~ "(?i)(error|exception)"
```

4. Read the deployment:

```bash
kubectl -n <namespace> get deploy alaveteli-sidekiq
kubectl -n <namespace> get pods -l app=alaveteli-sidekiq
```

5. After the masking tool, paste the mail summary, the `env` value, the Sidekiq ready value, the Loki lines, and the kubectl output.

How to verify it worked: available replicas match the desired count, and new error lines stop.

How to undo: if the deployment was scaled during the check, restore the previous replica count:

```bash
kubectl -n <namespace> scale deployment/alaveteli-sidekiq --replicas=1
```

If nothing was changed, there is nothing to undo. Do not delete the queue.

## R3 — Certificate expiring

Prerequisites: the CertificateExpiry mail has arrived.

1. Open the Overview dashboard and read Certificate days left.
2. Open the Logs dashboard and read cert-manager errors. The query is:

```
{namespace="cert-manager"} |~ "(?i)error"
```

3. List the certificates:

```bash
kubectl get certificate -A
```

4. After the masking tool, paste the certificate name, the days left, the Loki lines, and the kubectl output.

How to verify it worked: days left is above 7, and CertificateExpiry has cleared.

How to undo: this check does not change a certificate. Do not delete the Certificate or its Secret to clear the alert.

## R4 — Disk full

Prerequisites: the DiskFilling mail has arrived.

1. Open the Cluster dashboard.
2. Read Node disk and PVC fill. Note the instance or the volume name.
3. Read log lines for eviction or a full disk:

```
{namespace=~"<namespace>"} |~ "(?i)(evicted|no space left)"
```

4. List volumes:

```bash
kubectl get pvc -A
```

5. After the masking tool, paste the instance or volume name, the fill percent, the Loki lines, and the kubectl output.

How to verify it worked: used space is under 85 percent, and DiskFilling has cleared.

How to undo: if a test file was written to fill the disk, delete that file. Do not delete the Prometheus or Loki volume to silence the alert.

## R5 — Exit test

Prerequisites: Mailpit is the SMTP target, and the stack is up.

1. Run `make obs-alert-test`. That scales `alaveteli-web` in `tst` to 0 replicas.
2. Wait 3 minutes. The SiteDown mail should arrive in Mailpit.
3. Follow R1 with `<namespace>` set to `tst`.
4. Run `make obs-alert-restore`.
5. Wait until the pod is Ready. SiteDown should clear, and a resolved mail should arrive.

How to verify it worked: one firing mail and one resolved mail are in Mailpit.

How to undo: `make obs-alert-restore`.
