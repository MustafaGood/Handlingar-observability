#!/usr/bin/env python3
"""Check the T6 plan without touching the production server."""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
PLAN = (ROOT / "docs" / "plan-legacy-prod.md").read_text(encoding="utf-8")
PROPOSAL = (ROOT / "proposals" / "legacy-prod-scrape.yaml").read_text(encoding="utf-8")
KUSTOMIZE = (ROOT / "kustomization.yaml").read_text(encoding="utf-8")

PLAN_BITS = (
    "plan only",
    "Do not install",
    "node-exporter",
    "Postfix",
    "postfix_queue_messages",
    "private address",
    "9100",
    "9154",
    "HTTPS",
    "legacy-prod-scrape",
    "legacy-prod.invalid",
    "proposals/legacy-prod-scrape.yaml",
)
PROPOSAL_BITS = (
    "kind: ScrapeConfig",
    "legacy-prod.invalid:9100",
    "legacy-prod.invalid:9154",
    "scheme: HTTPS",
    "kind: CiliumNetworkPolicy",
    "kind: ExternalSecret",
    "key: password",
    "key: ca.crt",
)


def main() -> int:
    for needle in PLAN_BITS:
        if needle not in PLAN:
            print(f"plan missing {needle}", file=sys.stderr)
            return 1
    for needle in PROPOSAL_BITS:
        if needle not in PROPOSAL:
            print(f"proposal missing {needle}", file=sys.stderr)
            return 1
    if "legacy-prod-scrape.yaml" in KUSTOMIZE:
        print("legacy prod scrape is included in the install", file=sys.stderr)
        return 1
    if "@" in PLAN or "@" in PROPOSAL:
        print("plan contains an address literal", file=sys.stderr)
        return 1
    print("legacy plan ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
