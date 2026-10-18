# Alert test

Exercised on the reference sandbox (`handlingar-obs`) on **2026-10-18**.

## How to fire SiteDown on purpose

```bash
make obs-alert-test
```

That scales `alaveteli-web` in `tst` to 0 replicas. The blackbox probe for
`env="tst"` stays at 0 for 3 minutes, then `SiteDown` fires and Alertmanager
sends mail to Mailpit (`mailpit.handlingar.svc:1025`).

```bash
make obs-alert-restore
```

When the pod is Ready again, `probe_success{env="tst"}` returns to 1 and the
alert clears (`ALERTS{alertname="SiteDown"}` empty). Alertmanager is configured
with `send_resolved: true`.

## Live result (2026-10-18)

1. Scaled `tst/alaveteli-web` to 0.
2. After the 3 minute window: `probe_success{env="tst"}=0`,
   `ALERTS{alertname="SiteDown"}` state `firing`, Alertmanager status `active`.
3. Mailpit received grouped alert emails from
   `kube-prometheus-stack-prometheus` (Subject `[FIRING:N] …`).
4. Scaled back to 1 replica.
5. Within ~3 minutes: `probe_success{env="tst"}=1`, SiteDown series gone.

Exit criterion demonstrated: outage visible via alert mail before a human
notices by other means.

## Adjustments made during the live run

- SiteDown matches only the `handlingar`, `tst`, and `qat` probes.
- HighErrorRate stays quiet when a service has no requests.
- SidekiqNotReady uses desired replicas that are not available (no queue metric yet).
- Early Alertmanager DNS timeouts under default-deny were fixed by keeping
  `allow-dns-egress` + `allow-alertmanager-egress-mailpit` and same-namespace
  allows; after that, notify succeeded.
- Default kube-prometheus chart alerts also fired (PodCrashLoop on
  kube-state-metrics while probes were broken). That noise dropped after
  `hostNetwork: true` for kube-state-metrics.
