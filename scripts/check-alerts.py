#!/usr/bin/env python3
"""Check the T4 alert rules without a cluster."""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
RULES = (ROOT / "alerts" / "rules.yaml").read_text(encoding="utf-8")
MAIL = (ROOT / "manifests" / "externalsecret-alert-email.yaml").read_text(encoding="utf-8")

REQUIRED = (
    "alert: SiteDown",
    'probe_success{env=~"handlingar|tst|qat"} == 0',
    "for: 3m",
    "severity: critical",
    "alert: HighErrorRate",
    "> 0.05",
    "for: 10m",
    "severity: warning",
    "alert: SidekiqNotReady",
    'deployment="alaveteli-sidekiq"',
    "alert: CertificateExpiry",
    "/ 86400 < 7",
    "alert: DiskFilling",
    "> 0.85",
    "alert: PostgresDown",
    "pg_up == 0",
    "for: 2m",
    "alert: PostgresConnectionsHigh",
    "> 0.9",
    "alert: PodCrashLoop",
    "increase(kube_pod_container_status_restarts_total[15m]) > 3",
    "alert: ArgoApplicationUnhealthy",
    'health_status="Degraded"',
    'sync_status="OutOfSync"',
    "for: 30m",
)


def main() -> int:
    if "kind: PrometheusRule" not in RULES:
        print("rules are not a PrometheusRule", file=sys.stderr)
        return 1
    for needle in REQUIRED:
        if needle not in RULES:
            print(f"missing {needle}", file=sys.stderr)
            return 1
    if "@" in RULES:
        print("alert rules contain an address literal", file=sys.stderr)
        return 1
    if "send_resolved: true" not in MAIL:
        print("resolved mail is not enabled", file=sys.stderr)
        return 1
    if "{{ .to }}" not in MAIL or "{{ .from }}" not in MAIL:
        print("mail receiver is not taken from the secret", file=sys.stderr)
        return 1
    print("alerts ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
