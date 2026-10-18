#!/usr/bin/env python3
"""Check the T5 runbook shape without a cluster."""
import pathlib
import sys

TEXT = (
    pathlib.Path(__file__).resolve().parents[1] / "docs" / "runbook-troubleshooting.md"
).read_text(encoding="utf-8")

REQUIRED = (
    "## R1 — Site down",
    "## R2 — Sidekiq queue growing",
    "## R3 — Certificate expiring",
    "## R4 — Disk full",
    "Prerequisites:",
    "How to verify it worked:",
    "How to undo:",
    "masking tool",
    "Overview",
    "Alaveteli",
    "Logs",
    "Cluster",
    '{namespace=~"<namespace>", app="alaveteli"} |~ "Completed 5[0-9]{2}"',
    '{namespace=~"<namespace>", app="alaveteli-sidekiq"} |~ "(?i)(error|exception)"',
    '{namespace="cert-manager"} |~ "(?i)error"',
    '{namespace=~"<namespace>"} |~ "(?i)(evicted|no space left)"',
    "kubectl -n <namespace> get pods -l app=alaveteli",
    "kubectl -n <namespace> get deploy alaveteli-sidekiq",
    "kubectl get certificate -A",
    "kubectl get pvc -A",
    "make obs-alert-restore",
)


def main() -> int:
    missing = [needle for needle in REQUIRED if needle not in TEXT]
    if missing:
        print("runbook missing:", file=sys.stderr)
        for needle in missing:
            print(f"  {needle}", file=sys.stderr)
        return 1
    for heading in REQUIRED[:4]:
        body = TEXT.split(heading, 1)[1].split("\n## ", 1)[0]
        for label in ("Prerequisites:", "How to verify it worked:", "How to undo:"):
            if label not in body:
                print(f"{heading} missing {label}", file=sys.stderr)
                return 1
    print("runbook ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
