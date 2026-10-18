# Plan: scrape the legacy production server

This is a plan only. Do not install anything on the production server from
this repository. Production is still the single server outside the cluster.
Nothing in `proposals/legacy-prod-scrape.yaml` is applied by `kubectl apply -k .`.

## Goal

After the cluster stack is accepted, scrape node metrics and Postfix queue
metrics from that server into the cluster Prometheus.

The Mail dashboard already queries `postfix_queue_messages`. That panel stays
empty until this plan is applied by the supervisor.

## Network path

1. node-exporter listens on the server private address, port 9100. It does not
   listen on the public address.
2. The Postfix exporter listens on the same private address, port 9154, and
   exposes `postfix_queue_messages`.
3. The server firewall allows those two ports only from the cluster egress
   address. That address is a parameter. It is not written here.
4. Prometheus in namespace `observability` opens the connection. The return
   traffic is the same connection. There is no public ingress on the server
   for these ports.
5. The hostname used in the proposal is `legacy-prod.invalid`. Replace it
   when the supervisor chooses the real name. `.invalid` does not resolve.

## TLS and auth

The scrape is HTTPS. Prometheus checks the server certificate against a CA
in Secret `legacy-prod-scrape`, key `ca.crt`. The name it expects is the
same hostname as the target.

The username and password are keys `username` and `password` in that same
Secret. An ExternalSecret template is in the proposal file. It has no values.
The supervisor fills the store. Do not write the password in git.

## What the supervisor applies later

`proposals/legacy-prod-scrape.yaml` contains:

- two `ScrapeConfig` objects, one for node-exporter and one for Postfix
- a `CiliumNetworkPolicy` that lets Prometheus reach that hostname on ports
  9100 and 9154, with a DNS rule in the same policy
- an `ExternalSecret` named `legacy-prod-scrape`

## If this is not done

The cluster dashboards do not show the legacy server. The Postfix panel stays
empty. The cluster stack does not depend on this plan.
