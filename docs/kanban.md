# Kanban: Handlingar observability (LIA)

Board status for the PDF Definition of done.

## Done (~90%)

- [x] ADR draft (T1)
- [x] Sandbox recreatable from `sandbox/`
- [x] Install stack from zero in sandbox
- [x] Logs searchable in Loki / Grafana Explore
- [x] Six dashboards from JSON
- [x] Alerts (T4) + test email to Mailpit + restore
- [x] Resource footprint measured under budget
- [x] requests/limits, pinned versions, securityContext
- [x] NetworkPolicy default-deny + allows
- [x] Runbook (T5) written and exercised
- [x] No §3.5 violations
- [x] Exit criteria (SiteDown in tst)
- [x] GitHub repo published
- [x] T6 legacy plan (optional)

## In progress

- [ ] Scrape targets all green (partial, about 17/24)

## Todo (~10%)

- [ ] ADR accepted by supervisor
- [ ] Demo / handover to supervisor
- [ ] Optional: polish Traefik / cert-manager / kubelet scrapes

## Notes

- Repo: https://github.com/MustafaGood/Handlingar-observability
- ADR: `docs/adr-observability-stack.md` (status: proposed)
