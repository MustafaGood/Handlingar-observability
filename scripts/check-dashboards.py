#!/usr/bin/env python3
"""Check the six Grafana dashboards for the T3 rules."""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
REQUIRED = {
    "overview.json": [
        "Site up",
        "Request rate",
        "Error rate 5xx",
        "p95 latency",
        "Certificate days left",
        "Disk used",
        "Memory used per node",
        "Firing alerts",
    ],
    "alaveteli.json": [
        "Requests per second",
        "5xx rate",
        "p95 latency",
        "Sidekiq ready",
        "Sidekiq errors",
        "Puma busy threads",
    ],
    "backing-services.json": [
        "Postgres connections",
        "Postgres transactions",
        "Postgres longest transaction",
        "Postgres database size",
        "Redis memory",
        "Redis keys",
        "Redis evictions",
        "Memcached hit rate",
    ],
    "cluster.json": [
        "Node CPU",
        "Node memory",
        "Node disk",
        "Pod restarts",
        "Pending pods",
        "PVC fill",
    ],
    "mail.json": [
        "Postfix queue (empty until mail runs in the cluster)",
        "Mailpit log volume",
    ],
    "logs.json": [
        "Rails 5xx",
        "Sidekiq errors",
        "cert-manager errors",
    ],
}


def main() -> int:
    for name, titles in REQUIRED.items():
        path = ROOT / "dashboards" / name
        data = json.loads(path.read_text(encoding="utf-8"))
        if not data.get("title") or not data.get("uid"):
            print(f"{name}: missing title or uid", file=sys.stderr)
            return 1
        variables = [item.get("name") for item in data["templating"]["list"]]
        if "env" not in variables:
            print(f"{name}: missing env variable", file=sys.stderr)
            return 1
        found = []
        for panel in data["panels"]:
            found.append(panel["title"])
            uid = panel["datasource"]["uid"]
            if uid not in ("${prometheus}", "${loki}"):
                print(f"{name}: hardcoded datasource uid {uid}", file=sys.stderr)
                return 1
            expr = panel["targets"][0].get("expr", "")
            if not expr:
                print(f"{name}: empty query on {panel['title']}", file=sys.stderr)
                return 1
            width = panel["gridPos"]["x"] + panel["gridPos"]["w"]
            if width > 24:
                print(f"{name}: panel {panel['title']} is wider than the grid", file=sys.stderr)
                return 1
        for title in titles:
            if title not in found:
                print(f"{name}: missing panel {title}", file=sys.stderr)
                return 1
    print("dashboards ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
