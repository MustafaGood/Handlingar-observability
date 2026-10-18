# Kanban: Handlingar observability (LIA)

Board status for the PDF Definition of done.

## Done (~98%)

- [x] ADR draft (T1), status `ready for acceptance`
- [x] Sandbox recreatable from `sandbox/`
- [x] Install stack from zero in sandbox
- [x] Scrape targets all green (24/24 in sandbox)
- [x] Logs searchable in Loki / Grafana Explore
- [x] Six dashboards from JSON
- [x] Alerts (T4) + test email to Mailpit + restore
- [x] Resource footprint measured under budget
- [x] requests/limits, pinned versions, securityContext
- [x] NetworkPolicy default-deny + allows (Cilium host scrape)
- [x] Runbook (T5) written and exercised
- [x] No §3.5 violations
- [x] Exit criteria (SiteDown in tst)
- [x] GitHub repo published
- [x] T6 legacy plan (optional)

## Todo (supervisor only)

- [ ] ADR accepted by supervisor (checklist in ADR)
- [ ] Demo / handover to supervisor

## Notes

- Repo: https://github.com/MustafaGood/Handlingar-observability
- ADR: `docs/adr-observability-stack.md` (status: ready for acceptance)
- Project board: https://github.com/users/MustafaGood/projects/3
