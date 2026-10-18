.PHONY: obs-up obs-status obs-alert-test obs-down

obs-up:
	kubectl apply -k .

obs-status:
	kubectl -n observability get pods,servicemonitors,prometheusrules,ingressroute,certificate

obs-alert-test:
	kubectl -n tst scale deployment/alaveteli-web --replicas=0
	@echo Wait for the SiteDown window, then restore with obs-alert-restore

obs-alert-restore:
	kubectl -n tst scale deployment/alaveteli-web --replicas=1

obs-down:
	kubectl delete -k .
	@echo PVCs are kept. Delete them by hand if the disk must be freed.
